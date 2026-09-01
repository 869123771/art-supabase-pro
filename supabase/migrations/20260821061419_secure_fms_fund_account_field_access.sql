-- Secure FMS fund account details and balances at the database boundary.
-- Full list, option, overview, and write paths are tenant scoped and field aware.

alter table public.fms_fund_account
  add column if not exists created_by_user_id uuid;

update public.fms_fund_account account_row
set created_by_user_id = (
  select candidate.id
  from public.sys_user candidate
  where candidate.tenant_id = account_row.tenant_id
    and lower(candidate.user_email) = lower(account_row.create_by)
  order by candidate.create_time, candidate.id
  limit 1
)
where account_row.created_by_user_id is null
  and nullif(btrim(coalesce(account_row.create_by, '')), '') is not null;

do $$
begin
  if exists (
    select 1
    from public.fms_fund_account
    where created_by_user_id is null
  ) then
    raise exception 'Unable to backfill fms_fund_account.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_fund_account
  alter column created_by_user_id set not null;

create index if not exists fms_fund_account_tenant_creator_idx
  on public.fms_fund_account(tenant_id, created_by_user_id);

create index if not exists fms_fund_account_creator_tenant_idx
  on public.fms_fund_account(created_by_user_id, tenant_id);

alter table public.fms_fund_account
  drop constraint if exists fms_fund_account_creator_tenant_fkey;

alter table public.fms_fund_account
  add constraint fms_fund_account_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_fund_account_creator_identity()
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
      raise exception 'Unable to resolve fund account creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Fund account creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_fund_account_creator_identity
  on public.fms_fund_account;
create trigger fms_fund_account_creator_identity
before insert or update of created_by_user_id
on public.fms_fund_account
for each row execute function app_private.set_fms_fund_account_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_fund_account;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_fund_account(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.fund_account', '资金账户',
    'FinanceFundAccount', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'accountDetails', '账号尾号、开户机构与支行',
      'hidden', 'bank_account', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'accountBalances', '期初、冻结、当前与可用余额',
      'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com')
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
 and menu_row.name = 'FinanceFundAccount'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.fund_account'
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.fms_fund_account_raw_json(p_account_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(summary_row)
    - 'tenant_id'
    - 'created_by_user_id'
    - 'account_no_fingerprint'
  from public.fms_fund_account_summary summary_row
  join public.fms_fund_account account_row
    on account_row.id = summary_row.id
   and account_row.tenant_id = summary_row.tenant_id
  where summary_row.id = p_account_id
    and summary_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_fund_account_to_secure_json(
  p_account jsonb,
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
    app_private.field_access_map('fms.fund_account', p_owner_id)
  );
  v_data jsonb := coalesce(p_account, '{}'::jsonb)
    - 'tenant_id'
    - 'created_by_user_id'
    - 'account_no_fingerprint';
  v_level text;
begin
  v_level := coalesce(v_access->>'accountDetails', 'hidden');
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['bank_name', 'bank_branch']::text[],
    v_level
  );
  if v_level = 'hidden' then
    v_data := v_data - 'account_no_masked';
  end if;

  v_level := coalesce(v_access->>'accountBalances', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'opening_balance', 'frozen_balance', 'inflow_amount', 'outflow_amount',
      'current_balance', 'available_balance'
    ]::text[],
    v_level
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['balance_as_of', 'latest_balance_date']::text[],
    v_level
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_fund_accounts_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_account_type text default null,
  p_status text default null,
  p_keyword text default null,
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
  v_current_user_id uuid := app_private.current_app_user_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - v_from + 1, 1), 1000);
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map('fms.fund_account', null);
  v_row record;
begin
  if p_tenant_id is not null and p_tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant fund account access is forbidden'
      using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceFundAccount', null, null, false
  ) then
    raise exception 'Missing fund account menu permission'
      using errcode = '42501';
  end if;

  select count(*)::integer
  into v_total
  from public.fms_fund_account account_row
  where account_row.tenant_id = v_tenant_id
    and (p_account_set_id is null or account_row.account_set_id = p_account_set_id)
    and (p_account_type is null or account_row.account_type = p_account_type)
    and (p_status is null or account_row.status = p_status)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or account_row.account_code ilike '%' || btrim(p_keyword) || '%'
      or account_row.account_name ilike '%' || btrim(p_keyword) || '%'
      or (
        app_private.resolve_field_access(
          'fms.fund_account', 'accountDetails', account_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          account_row.bank_name ilike '%' || btrim(p_keyword) || '%'
          or account_row.bank_branch ilike '%' || btrim(p_keyword) || '%'
          or account_row.account_no_masked ilike '%' || btrim(p_keyword) || '%'
        )
      )
    );

  for v_row in
    select account_row.id, account_row.created_by_user_id
    from public.fms_fund_account account_row
    where account_row.tenant_id = v_tenant_id
      and (p_account_set_id is null or account_row.account_set_id = p_account_set_id)
      and (p_account_type is null or account_row.account_type = p_account_type)
      and (p_status is null or account_row.status = p_status)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or account_row.account_code ilike '%' || btrim(p_keyword) || '%'
        or account_row.account_name ilike '%' || btrim(p_keyword) || '%'
        or (
          app_private.resolve_field_access(
            'fms.fund_account', 'accountDetails', account_row.created_by_user_id
          ) in ('read', 'edit')
          and (
            account_row.bank_name ilike '%' || btrim(p_keyword) || '%'
            or account_row.bank_branch ilike '%' || btrim(p_keyword) || '%'
            or account_row.account_no_masked ilike '%' || btrim(p_keyword) || '%'
          )
        )
      )
    order by account_row.is_default desc, account_row.account_code, account_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_fund_account_to_secure_json(
        app_private.fms_fund_account_raw_json(v_row.id),
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

create or replace function public.fms_list_fund_account_options_secure(
  p_account_set_id uuid default null,
  p_status text default 'active',
  p_base_currency_only boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_records jsonb := '[]'::jsonb;
  v_row record;
  v_access jsonb;
  v_record jsonb;
  v_level text;
begin
  for v_row in
    select
      account_row.id,
      account_row.created_by_user_id,
      account_row.account_set_id,
      account_row.currency_id,
      account_row.account_code,
      account_row.account_name,
      account_row.account_type,
      account_row.account_no_masked,
      account_row.status,
      account_row.reconciliation_enabled,
      summary_row.available_balance,
      currency_row.currency_code
    from public.fms_fund_account account_row
    join public.fms_fund_account_summary summary_row
      on summary_row.id = account_row.id
     and summary_row.tenant_id = account_row.tenant_id
    join public.fms_currency currency_row
      on currency_row.id = account_row.currency_id
     and currency_row.account_set_id = account_row.account_set_id
    join public.fms_account_set account_set_row
      on account_set_row.id = account_row.account_set_id
     and account_set_row.tenant_id = account_row.tenant_id
    where account_row.tenant_id = v_tenant_id
      and (p_account_set_id is null or account_row.account_set_id = p_account_set_id)
      and (p_status is null or account_row.status = p_status)
      and (
        not coalesce(p_base_currency_only, false)
        or currency_row.currency_code = account_set_row.base_currency_code
      )
    order by account_row.is_default desc, account_row.account_code, account_row.id
    limit 1000
  loop
    v_access := app_private.field_access_map(
      'fms.fund_account', v_row.created_by_user_id
    );
    v_record := jsonb_build_object(
      'id', v_row.id,
      'tenant_id', v_tenant_id,
      'account_set_id', v_row.account_set_id,
      'currency_id', v_row.currency_id,
      'currency_code', v_row.currency_code,
      'account_code', v_row.account_code,
      'account_name', v_row.account_name,
      'account_type', v_row.account_type,
      'status', v_row.status,
      'reconciliation_enabled', v_row.reconciliation_enabled,
      'field_access', v_access,
      'is_record_owner', v_row.created_by_user_id = app_private.current_app_user_id()
    );

    v_level := coalesce(v_access->>'accountDetails', 'hidden');
    if v_level <> 'hidden' then
      v_record := v_record || jsonb_build_object(
        'account_no_masked', v_row.account_no_masked
      );
    end if;

    v_record := app_private.apply_jsonb_amount_access(
      v_record || jsonb_build_object('available_balance', v_row.available_balance),
      array['available_balance']::text[],
      coalesce(v_access->>'accountBalances', 'hidden')
    );
    v_records := v_records || jsonb_build_array(v_record);
  end loop;
  return v_records;
end;
$$;

create or replace function public.fms_get_fund_account_overview_secure(
  p_account_set_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb := app_private.field_access_map('fms.fund_account', null);
  v_level text := coalesce(v_access->>'accountBalances', 'hidden');
  v_result jsonb;
  v_balances jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceFundAccount', null, null, false
  ) then
    raise exception 'Missing fund account menu permission'
      using errcode = '42501';
  end if;
  if p_account_set_id is not null and not exists (
    select 1
    from public.fms_account_set account_set_row
    where account_set_row.id = p_account_set_id
      and account_set_row.tenant_id = v_tenant_id
  ) then
    raise exception 'Account set is outside the current tenant'
      using errcode = '42501';
  end if;

  select jsonb_build_object(
    'account_count', count(*),
    'active_account_count', count(*) filter (where account_row.status = 'active'),
    'foreign_currency_account_count', count(*) filter (
      where currency_row.currency_code <> account_set_row.base_currency_code
    )
  ), jsonb_build_object(
    'base_currency_current_balance', coalesce(sum(summary_row.current_balance) filter (
      where currency_row.currency_code = account_set_row.base_currency_code
    ), 0),
    'base_currency_available_balance', coalesce(sum(summary_row.available_balance) filter (
      where currency_row.currency_code = account_set_row.base_currency_code
    ), 0),
    'base_currency_frozen_balance', coalesce(sum(summary_row.frozen_balance) filter (
      where currency_row.currency_code = account_set_row.base_currency_code
    ), 0)
  )
  into v_result, v_balances
  from public.fms_fund_account account_row
  join public.fms_fund_account_summary summary_row
    on summary_row.id = account_row.id
   and summary_row.tenant_id = account_row.tenant_id
  join public.fms_account_set account_set_row
    on account_set_row.id = account_row.account_set_id
   and account_set_row.tenant_id = account_row.tenant_id
  join public.fms_currency currency_row
    on currency_row.id = account_row.currency_id
   and currency_row.account_set_id = account_row.account_set_id
  where account_row.tenant_id = v_tenant_id
    and (p_account_set_id is null or account_row.account_set_id = p_account_set_id);

  v_result := coalesce(v_result, '{}'::jsonb);
  if v_level <> 'hidden' then
    v_result := v_result || app_private.apply_jsonb_amount_access(
      coalesce(v_balances, '{}'::jsonb),
      array[
        'base_currency_current_balance', 'base_currency_available_balance',
        'base_currency_frozen_balance'
      ]::text[],
      v_level
    );
  end if;
  return v_result || jsonb_build_object('field_access', v_access);
end;
$$;

create or replace function public.save_fms_fund_account_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_existing public.fms_fund_account%rowtype;
  v_saved public.fms_fund_account%rowtype;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_access jsonb;
begin
  if not exists (
    select 1
    from public.fms_account_set account_set_row
    where account_set_row.id = (v_payload->>'accountSetId')::uuid
      and account_set_row.tenant_id = v_tenant_id
  ) then
    raise exception 'Account set is outside the current tenant'
      using errcode = '42501';
  end if;

  if v_id is not null then
    select *
    into v_existing
    from public.fms_fund_account account_row
    where account_row.id = v_id
      and account_row.tenant_id = v_tenant_id
    for update;
    if not found then
      raise exception 'Fund account does not exist in the current tenant'
        using errcode = 'P0002';
    end if;
    v_access := app_private.field_access_map(
      'fms.fund_account', v_existing.created_by_user_id
    );

    if coalesce(v_access->>'accountDetails', 'hidden') <> 'edit' then
      v_payload := v_payload
        || jsonb_build_object(
          'bankName', v_existing.bank_name,
          'bankBranch', v_existing.bank_branch
        )
        - 'accountNo';
    end if;
    if coalesce(v_access->>'accountBalances', 'hidden') <> 'edit' then
      v_payload := v_payload || jsonb_build_object(
        'openingBalance', v_existing.opening_balance,
        'frozenBalance', v_existing.frozen_balance,
        'balanceAsOf', v_existing.balance_as_of
      );
    end if;
  end if;

  v_saved := public.save_fms_fund_account(v_payload);
  if v_saved.tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant fund account write is forbidden'
      using errcode = '42501';
  end if;
  return app_private.fms_fund_account_to_secure_json(
    app_private.fms_fund_account_raw_json(v_saved.id),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.delete_fms_fund_account_secure(p_account_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.fms_fund_account account_row
    where account_row.id = p_account_id
      and account_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Fund account does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  return public.delete_fms_fund_account(p_account_id);
end;
$$;

revoke all on table public.fms_fund_account from anon, authenticated;
revoke all on table public.fms_fund_account_summary from anon, authenticated;

revoke execute on function public.fms_fund_account_overview(uuid)
  from public, anon, authenticated;
revoke execute on function public.save_fms_fund_account(jsonb)
  from public, anon, authenticated;
revoke execute on function public.delete_fms_fund_account(uuid)
  from public, anon, authenticated;

revoke all on function public.fms_list_fund_accounts_secure(
  integer, integer, uuid, text, text, text, uuid
) from public, anon, authenticated;
revoke all on function public.fms_list_fund_account_options_secure(
  uuid, text, boolean
) from public, anon, authenticated;
revoke all on function public.fms_get_fund_account_overview_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.save_fms_fund_account_secure(jsonb)
  from public, anon, authenticated;
revoke all on function public.delete_fms_fund_account_secure(uuid)
  from public, anon, authenticated;

grant execute on function public.fms_list_fund_accounts_secure(
  integer, integer, uuid, text, text, text, uuid
) to authenticated;
grant execute on function public.fms_list_fund_account_options_secure(
  uuid, text, boolean
) to authenticated;
grant execute on function public.fms_get_fund_account_overview_secure(uuid)
  to authenticated;
grant execute on function public.save_fms_fund_account_secure(jsonb)
  to authenticated;
grant execute on function public.delete_fms_fund_account_secure(uuid)
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
        and resource_row.resource_key = 'fms.fund_account'
        and resource_row.owner_column = 'created_by_user_id'
        and resource_row.enabled is true
    )
  ) then
    raise exception 'Missing fms.fund_account permission resource';
  end if;
  if exists (
    select 1
    from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.fund_account'
      and (
        select count(*)
        from public.sys_permission_field field_row
        where field_row.tenant_id = resource_row.tenant_id
          and field_row.resource_id = resource_row.id
          and field_row.enabled is true
      ) <> 2
  ) then
    raise exception 'Unexpected fms.fund_account field catalog';
  end if;
  if has_table_privilege('authenticated', 'public.fms_fund_account', 'select')
     or has_table_privilege('authenticated', 'public.fms_fund_account_summary', 'select')
     or has_table_privilege('anon', 'public.fms_fund_account', 'select')
     or has_table_privilege('anon', 'public.fms_fund_account_summary', 'select') then
    raise exception 'Direct fund account reads remain exposed';
  end if;
  if has_function_privilege(
    'anon',
    'public.fms_list_fund_accounts_secure(integer,integer,uuid,text,text,text,uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.save_fms_fund_account_secure(jsonb)',
    'execute'
  ) then
    raise exception 'Anonymous fund account RPC access remains exposed';
  end if;
end;
$$;

;
