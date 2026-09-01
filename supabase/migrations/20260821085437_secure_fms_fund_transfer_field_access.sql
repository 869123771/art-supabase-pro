-- Secure fund transfer reads and writes with tenant-scoped field permissions.
-- Button permissions remain owned by the existing operation permission functions.

alter table public.fms_fund_transfer
  add column if not exists created_by_user_id uuid;

update public.fms_fund_transfer transfer_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = transfer_row.tenant_id
    and lower(user_row.user_email) = lower(transfer_row.create_by)
  order by user_row.create_time, user_row.id
  limit 1
)
where transfer_row.created_by_user_id is null
  and nullif(btrim(coalesce(transfer_row.create_by, '')), '') is not null;

do $$
begin
  if exists (
    select 1
    from public.fms_fund_transfer
    where created_by_user_id is null
  ) then
    raise exception 'Unable to backfill fms_fund_transfer.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_fund_transfer
  alter column created_by_user_id set not null;

create index if not exists fms_fund_transfer_tenant_creator_idx
  on public.fms_fund_transfer(tenant_id, created_by_user_id);

create index if not exists fms_fund_transfer_creator_tenant_idx
  on public.fms_fund_transfer(created_by_user_id, tenant_id);

alter table public.fms_fund_transfer
  drop constraint if exists fms_fund_transfer_creator_tenant_fkey;

alter table public.fms_fund_transfer
  add constraint fms_fund_transfer_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_fund_transfer_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.created_by_user_id is null then
      new.created_by_user_id := app_private.current_app_user_id();
    end if;
    if new.created_by_user_id is null
       and nullif(btrim(coalesce(new.create_by, '')), '') is not null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve fund transfer creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Fund transfer creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_fund_transfer_creator_identity
  on public.fms_fund_transfer;
create trigger fms_fund_transfer_creator_identity
before insert or update of created_by_user_id
on public.fms_fund_transfer
for each row execute function app_private.set_fms_fund_transfer_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_fund_transfer;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_fund_transfer(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.fund_transfer', '资金调拨',
    'FinanceFundTransfer', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'transferAccounts', '转出、转入账户信息',
      'hidden', 'bank_account', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'transferAmounts', '调拨金额与银行手续费',
      'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'bankReference', '银行参考号',
      'hidden', 'none', true, 30, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

-- Preserve current behavior for roles that already own the menu. Tenant admins can
-- tighten these defaults afterwards without changing button grants.
insert into public.sys_role_field_permission (
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id,
  role_menu.role_id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'FinanceFundTransfer'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.fund_transfer'
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.fms_fund_transfer_raw_json(p_transfer_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(summary_row)
    - 'tenant_id'
    - 'created_by_user_id'
  from public.fms_fund_transfer_summary summary_row
  join public.fms_fund_transfer transfer_row
    on transfer_row.id = summary_row.id
   and transfer_row.tenant_id = summary_row.tenant_id
  where summary_row.id = p_transfer_id
    and summary_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_fund_transfer_to_secure_json(
  p_transfer jsonb,
  p_owner_id uuid,
  p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(
    p_access,
    app_private.field_access_map('fms.fund_transfer', p_owner_id)
  );
  v_data jsonb := coalesce(p_transfer, '{}'::jsonb)
    - 'tenant_id'
    - 'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'source_account_id', 'source_account_code', 'source_account_name',
      'source_account_no_masked', 'target_account_id', 'target_account_code',
      'target_account_name', 'target_account_no_masked'
    ]::text[],
    coalesce(v_access->>'transferAccounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['amount', 'fee_amount']::text[],
    coalesce(v_access->>'transferAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['bank_reference']::text[],
    coalesce(v_access->>'bankReference', 'hidden')
  );
  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_fund_transfers_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_source_account_id uuid default null,
  p_target_account_id uuid default null,
  p_status text default null,
  p_keyword text default null,
  p_transfer_start_date date default null,
  p_transfer_end_date date default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - v_from + 1, 1), 1000);
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map('fms.fund_transfer', null);
  v_row record;
begin
  if p_tenant_id is not null and p_tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant fund transfer access is forbidden'
      using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceFundTransfer', null, null, false
  ) then
    raise exception 'Missing fund transfer menu permission'
      using errcode = '42501';
  end if;

  select count(*)::integer
  into v_total
  from public.fms_fund_transfer_summary summary_row
  join public.fms_fund_transfer transfer_row
    on transfer_row.id = summary_row.id
   and transfer_row.tenant_id = summary_row.tenant_id
  where summary_row.tenant_id = v_tenant_id
    and (p_account_set_id is null or summary_row.account_set_id = p_account_set_id)
    and (
      p_source_account_id is null
      or (
        summary_row.source_account_id = p_source_account_id
        and app_private.resolve_field_access(
          'fms.fund_transfer', 'transferAccounts', transfer_row.created_by_user_id
        ) in ('read', 'edit')
      )
    )
    and (
      p_target_account_id is null
      or (
        summary_row.target_account_id = p_target_account_id
        and app_private.resolve_field_access(
          'fms.fund_transfer', 'transferAccounts', transfer_row.created_by_user_id
        ) in ('read', 'edit')
      )
    )
    and (p_status is null or summary_row.status = p_status)
    and (p_transfer_start_date is null or summary_row.transfer_date >= p_transfer_start_date)
    and (p_transfer_end_date is null or summary_row.transfer_date <= p_transfer_end_date)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or summary_row.transfer_no ilike '%' || btrim(p_keyword) || '%'
      or summary_row.purpose ilike '%' || btrim(p_keyword) || '%'
      or (
        app_private.resolve_field_access(
          'fms.fund_transfer', 'transferAccounts', transfer_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          summary_row.source_account_name ilike '%' || btrim(p_keyword) || '%'
          or summary_row.target_account_name ilike '%' || btrim(p_keyword) || '%'
        )
      )
      or (
        app_private.resolve_field_access(
          'fms.fund_transfer', 'bankReference', transfer_row.created_by_user_id
        ) in ('read', 'edit')
        and summary_row.bank_reference ilike '%' || btrim(p_keyword) || '%'
      )
    );

  for v_row in
    select summary_row.id, transfer_row.created_by_user_id
    from public.fms_fund_transfer_summary summary_row
    join public.fms_fund_transfer transfer_row
      on transfer_row.id = summary_row.id
     and transfer_row.tenant_id = summary_row.tenant_id
    where summary_row.tenant_id = v_tenant_id
      and (p_account_set_id is null or summary_row.account_set_id = p_account_set_id)
      and (
        p_source_account_id is null
        or (
          summary_row.source_account_id = p_source_account_id
          and app_private.resolve_field_access(
            'fms.fund_transfer', 'transferAccounts', transfer_row.created_by_user_id
          ) in ('read', 'edit')
        )
      )
      and (
        p_target_account_id is null
        or (
          summary_row.target_account_id = p_target_account_id
          and app_private.resolve_field_access(
            'fms.fund_transfer', 'transferAccounts', transfer_row.created_by_user_id
          ) in ('read', 'edit')
        )
      )
      and (p_status is null or summary_row.status = p_status)
      and (p_transfer_start_date is null or summary_row.transfer_date >= p_transfer_start_date)
      and (p_transfer_end_date is null or summary_row.transfer_date <= p_transfer_end_date)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or summary_row.transfer_no ilike '%' || btrim(p_keyword) || '%'
        or summary_row.purpose ilike '%' || btrim(p_keyword) || '%'
        or (
          app_private.resolve_field_access(
            'fms.fund_transfer', 'transferAccounts', transfer_row.created_by_user_id
          ) in ('read', 'edit')
          and (
            summary_row.source_account_name ilike '%' || btrim(p_keyword) || '%'
            or summary_row.target_account_name ilike '%' || btrim(p_keyword) || '%'
          )
        )
        or (
          app_private.resolve_field_access(
            'fms.fund_transfer', 'bankReference', transfer_row.created_by_user_id
          ) in ('read', 'edit')
          and summary_row.bank_reference ilike '%' || btrim(p_keyword) || '%'
        )
      )
    order by summary_row.transfer_date desc, summary_row.create_time desc, summary_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_fund_transfer_to_secure_json(
        app_private.fms_fund_transfer_raw_json(v_row.id),
        v_row.created_by_user_id
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', coalesce(v_total, 0),
    'field_access', v_base_access
  );
end;
$$;

create or replace function public.fms_get_fund_transfer_secure(p_transfer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceFundTransfer', null, null, false
  ) then
    raise exception 'Missing fund transfer menu permission'
      using errcode = '42501';
  end if;
  select transfer_row.created_by_user_id
  into v_owner_id
  from public.fms_fund_transfer transfer_row
  where transfer_row.id = p_transfer_id
    and transfer_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Fund transfer does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  return app_private.fms_fund_transfer_to_secure_json(
    app_private.fms_fund_transfer_raw_json(p_transfer_id),
    v_owner_id
  );
end;
$$;

create or replace function public.fms_list_fund_transfer_actions_secure(p_transfer_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceFundTransfer', null, null, false
  ) then
    raise exception 'Missing fund transfer menu permission'
      using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.fms_fund_transfer transfer_row
    where transfer_row.id = p_transfer_id
      and transfer_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Fund transfer does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  select coalesce(
    jsonb_agg((to_jsonb(action_row) - 'tenant_id') order by action_row.action_time, action_row.id),
    '[]'::jsonb
  )
  into v_result
  from public.fms_fund_transfer_action action_row
  where action_row.transfer_id = p_transfer_id
    and action_row.tenant_id = app_private.current_user_tenant_id();
  return v_result;
end;
$$;

create or replace function public.save_fms_fund_transfer_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_existing public.fms_fund_transfer%rowtype;
  v_saved public.fms_fund_transfer%rowtype;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_access jsonb;
begin
  if v_id is not null then
    select *
    into v_existing
    from public.fms_fund_transfer transfer_row
    where transfer_row.id = v_id
      and transfer_row.tenant_id = v_tenant_id
    for update;
    if not found then
      raise exception 'Fund transfer does not exist in the current tenant'
        using errcode = 'P0002';
    end if;
    v_access := app_private.field_access_map(
      'fms.fund_transfer', v_existing.created_by_user_id
    );

    if coalesce(v_access->>'transferAccounts', 'hidden') <> 'edit' then
      if (v_payload ? 'sourceAccountId'
          and nullif(v_payload->>'sourceAccountId', '')::uuid is distinct from v_existing.source_account_id)
         or (v_payload ? 'targetAccountId'
          and nullif(v_payload->>'targetAccountId', '')::uuid is distinct from v_existing.target_account_id) then
        raise exception 'Fund transfer account fields are not editable'
          using errcode = '42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'sourceAccountId', v_existing.source_account_id,
        'targetAccountId', v_existing.target_account_id
      );
    end if;

    if coalesce(v_access->>'transferAmounts', 'hidden') <> 'edit' then
      if (v_payload ? 'amount'
          and nullif(v_payload->>'amount', '')::numeric is distinct from v_existing.amount)
         or (v_payload ? 'feeAmount'
          and nullif(v_payload->>'feeAmount', '')::numeric is distinct from v_existing.fee_amount) then
        raise exception 'Fund transfer amount fields are not editable'
          using errcode = '42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'amount', v_existing.amount,
        'feeAmount', v_existing.fee_amount
      );
    end if;

    if coalesce(v_access->>'bankReference', 'hidden') <> 'edit' then
      if v_payload ? 'bankReference'
         and nullif(btrim(v_payload->>'bankReference'), '') is distinct from v_existing.bank_reference then
        raise exception 'Fund transfer bank reference is not editable'
          using errcode = '42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'bankReference', v_existing.bank_reference
      );
    end if;
  end if;

  v_saved := public.save_fms_fund_transfer(v_payload);
  if v_saved.tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant fund transfer write is forbidden'
      using errcode = '42501';
  end if;
  return app_private.fms_fund_transfer_to_secure_json(
    app_private.fms_fund_transfer_raw_json(v_saved.id),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.transition_fms_fund_transfer_secure(
  p_transfer_id uuid,
  p_action text,
  p_remark text default null,
  p_execution_date date default null,
  p_expected_version integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_saved public.fms_fund_transfer%rowtype;
begin
  if not exists (
    select 1
    from public.fms_fund_transfer transfer_row
    where transfer_row.id = p_transfer_id
      and transfer_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Fund transfer does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_saved := public.transition_fms_fund_transfer(
    p_transfer_id, p_action, p_remark, p_execution_date, p_expected_version
  );
  return app_private.fms_fund_transfer_to_secure_json(
    app_private.fms_fund_transfer_raw_json(v_saved.id),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.delete_fms_fund_transfer_secure(p_transfer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.fms_fund_transfer transfer_row
    where transfer_row.id = p_transfer_id
      and transfer_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Fund transfer does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  return public.delete_fms_fund_transfer(p_transfer_id);
end;
$$;

revoke all on table public.fms_fund_transfer from anon, authenticated;
revoke all on table public.fms_fund_transfer_summary from anon, authenticated;
revoke all on table public.fms_fund_transfer_action from anon, authenticated;

revoke execute on function public.save_fms_fund_transfer(jsonb)
  from public, anon, authenticated;
revoke execute on function public.transition_fms_fund_transfer(uuid, text, text, date, integer)
  from public, anon, authenticated;
revoke execute on function public.delete_fms_fund_transfer(uuid)
  from public, anon, authenticated;

revoke all on function public.fms_list_fund_transfers_secure(
  integer, integer, uuid, uuid, uuid, text, text, date, date, uuid
) from public, anon, authenticated;
revoke all on function public.fms_get_fund_transfer_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.fms_list_fund_transfer_actions_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.save_fms_fund_transfer_secure(jsonb)
  from public, anon, authenticated;
revoke all on function public.transition_fms_fund_transfer_secure(
  uuid, text, text, date, integer
) from public, anon, authenticated;
revoke all on function public.delete_fms_fund_transfer_secure(uuid)
  from public, anon, authenticated;

grant execute on function public.fms_list_fund_transfers_secure(
  integer, integer, uuid, uuid, uuid, text, text, date, date, uuid
) to authenticated;
grant execute on function public.fms_get_fund_transfer_secure(uuid)
  to authenticated;
grant execute on function public.fms_list_fund_transfer_actions_secure(uuid)
  to authenticated;
grant execute on function public.save_fms_fund_transfer_secure(jsonb)
  to authenticated;
grant execute on function public.transition_fms_fund_transfer_secure(
  uuid, text, text, date, integer
) to authenticated;
grant execute on function public.delete_fms_fund_transfer_secure(uuid)
  to authenticated;

do $$
begin
  if exists (
    select 1
    from public.sys_tenant tenant_row
    where not exists (
      select 1
      from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'fms.fund_transfer'
        and resource_row.owner_column = 'created_by_user_id'
        and resource_row.enabled is true
    )
  ) then
    raise exception 'Missing fms.fund_transfer permission resource';
  end if;
  if exists (
    select 1
    from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.fund_transfer'
      and (
        select count(*)
        from public.sys_permission_field field_row
        where field_row.tenant_id = resource_row.tenant_id
          and field_row.resource_id = resource_row.id
          and field_row.enabled is true
      ) <> 3
  ) then
    raise exception 'Unexpected fms.fund_transfer field catalog';
  end if;
  if has_table_privilege('authenticated', 'public.fms_fund_transfer', 'select')
     or has_table_privilege('authenticated', 'public.fms_fund_transfer_summary', 'select')
     or has_table_privilege('authenticated', 'public.fms_fund_transfer_action', 'select')
     or has_table_privilege('anon', 'public.fms_fund_transfer', 'select')
     or has_table_privilege('anon', 'public.fms_fund_transfer_summary', 'select')
     or has_table_privilege('anon', 'public.fms_fund_transfer_action', 'select') then
    raise exception 'Direct fund transfer reads remain exposed';
  end if;
  if has_function_privilege(
    'anon',
    'public.fms_list_fund_transfers_secure(integer,integer,uuid,uuid,uuid,text,text,date,date,uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.save_fms_fund_transfer_secure(jsonb)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.save_fms_fund_transfer(jsonb)',
    'execute'
  ) then
    raise exception 'Fund transfer function privileges are not secure';
  end if;
end;
$$;

;
