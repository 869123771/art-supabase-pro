-- Secure the system-generated fund journal with tenant and field-aware reads.
-- The creator is the authenticated actor whose business operation posts the entry.

alter table public.fms_fund_ledger_entry
  add column if not exists created_by_user_id uuid;

update public.fms_fund_ledger_entry entry_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = entry_row.tenant_id
    and lower(user_row.user_email) = lower(coalesce(entry_row.posted_by, entry_row.create_by))
  order by user_row.create_time, user_row.id
  limit 1
)
where entry_row.created_by_user_id is null
  and nullif(btrim(coalesce(entry_row.posted_by, entry_row.create_by, '')), '') is not null;

do $$
begin
  if exists (
    select 1
    from public.fms_fund_ledger_entry
    where created_by_user_id is null
  ) then
    raise exception 'Unable to backfill fms_fund_ledger_entry.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_fund_ledger_entry
  alter column created_by_user_id set not null;

create index if not exists fms_fund_ledger_entry_tenant_creator_idx
  on public.fms_fund_ledger_entry(tenant_id, created_by_user_id);

create index if not exists fms_fund_ledger_entry_creator_tenant_idx
  on public.fms_fund_ledger_entry(created_by_user_id, tenant_id);

alter table public.fms_fund_ledger_entry
  drop constraint if exists fms_fund_ledger_entry_creator_tenant_fkey;

alter table public.fms_fund_ledger_entry
  add constraint fms_fund_ledger_entry_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_fund_ledger_creator_identity()
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
       and nullif(btrim(coalesce(new.posted_by, new.create_by, '')), '') is not null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(coalesce(new.posted_by, new.create_by))
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve fund ledger creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Fund ledger creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_fund_ledger_creator_identity
  on public.fms_fund_ledger_entry;
create trigger fms_fund_ledger_creator_identity
before insert or update of created_by_user_id
on public.fms_fund_ledger_entry
for each row execute function app_private.set_fms_fund_ledger_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_fund_ledger;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_fund_ledger(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.fund_ledger', '资金日记账',
    'FinanceFundJournal', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'accountDetails', '资金账户信息',
      'hidden', 'bank_account', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'ledgerAmounts', '资金流水发生金额',
      'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'transactionDetails', '业务单号、交易对方与银行凭证',
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
 and menu_row.name = 'FinanceFundJournal'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.fund_ledger'
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.fms_fund_ledger_raw_json(p_entry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (
    to_jsonb(entry_row)
      - 'tenant_id'
      - 'created_by_user_id'
  ) || jsonb_build_object(
    'currency_code', currency_row.currency_code,
    'fund_account', jsonb_build_object(
      'id', account_row.id,
      'account_code', account_row.account_code,
      'account_name', account_row.account_name,
      'account_no_masked', account_row.account_no_masked
    )
  )
  from public.fms_fund_ledger_entry entry_row
  join public.fms_fund_account account_row
    on account_row.id = entry_row.fund_account_id
   and account_row.tenant_id = entry_row.tenant_id
  join public.fms_currency currency_row
    on currency_row.id = account_row.currency_id
   and currency_row.account_set_id = account_row.account_set_id
  where entry_row.id = p_entry_id
    and entry_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_fund_ledger_to_secure_json(
  p_entry jsonb,
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
    app_private.field_access_map('fms.fund_ledger', p_owner_id)
  );
  v_data jsonb := coalesce(p_entry, '{}'::jsonb)
    - 'tenant_id'
    - 'created_by_user_id';
  v_account jsonb := coalesce(v_data->'fund_account', '{}'::jsonb);
  v_account_access text := coalesce(v_access->>'accountDetails', 'hidden');
begin
  v_data := v_data - 'fund_account';
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['fund_account_id']::text[],
    v_account_access
  );
  if v_account_access <> 'hidden' then
    v_account := app_private.apply_jsonb_text_access(
      v_account,
      array['id', 'account_code', 'account_name', 'account_no_masked']::text[],
      v_account_access
    );
    v_data := v_data || jsonb_build_object('fund_account', v_account);
  end if;

  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['amount']::text[],
    coalesce(v_access->>'ledgerAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'source_id', 'source_no', 'summary', 'counterparty_name', 'bank_reference'
    ]::text[],
    coalesce(v_access->>'transactionDetails', 'hidden')
  );
  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_fund_ledger_entries_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_fund_account_id uuid default null,
  p_direction text default null,
  p_source_type text default null,
  p_status text default null,
  p_keyword text default null,
  p_entry_start_date date default null,
  p_entry_end_date date default null,
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
  v_base_access jsonb := app_private.field_access_map('fms.fund_ledger', null);
  v_row record;
begin
  if p_tenant_id is not null and p_tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant fund ledger access is forbidden'
      using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceFundJournal', null, null, false
  ) then
    raise exception 'Missing fund journal menu permission'
      using errcode = '42501';
  end if;

  select count(*)::integer
  into v_total
  from public.fms_fund_ledger_entry entry_row
  join public.fms_fund_account account_row
    on account_row.id = entry_row.fund_account_id
   and account_row.tenant_id = entry_row.tenant_id
  where entry_row.tenant_id = v_tenant_id
    and (p_account_set_id is null or entry_row.account_set_id = p_account_set_id)
    and (
      p_fund_account_id is null
      or (
        entry_row.fund_account_id = p_fund_account_id
        and app_private.resolve_field_access(
          'fms.fund_ledger', 'accountDetails', entry_row.created_by_user_id
        ) in ('read', 'edit')
      )
    )
    and (p_direction is null or entry_row.direction = p_direction)
    and (p_source_type is null or entry_row.source_type = p_source_type)
    and (p_status is null or entry_row.status = p_status)
    and (p_entry_start_date is null or entry_row.entry_date >= p_entry_start_date)
    and (p_entry_end_date is null or entry_row.entry_date <= p_entry_end_date)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or entry_row.entry_no ilike '%' || btrim(p_keyword) || '%'
      or (
        app_private.resolve_field_access(
          'fms.fund_ledger', 'accountDetails', entry_row.created_by_user_id
        ) in ('read', 'edit')
        and account_row.account_name ilike '%' || btrim(p_keyword) || '%'
      )
      or (
        app_private.resolve_field_access(
          'fms.fund_ledger', 'transactionDetails', entry_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          entry_row.source_no ilike '%' || btrim(p_keyword) || '%'
          or entry_row.summary ilike '%' || btrim(p_keyword) || '%'
          or entry_row.counterparty_name ilike '%' || btrim(p_keyword) || '%'
          or entry_row.bank_reference ilike '%' || btrim(p_keyword) || '%'
        )
      )
    );

  for v_row in
    select entry_row.id, entry_row.created_by_user_id
    from public.fms_fund_ledger_entry entry_row
    join public.fms_fund_account account_row
      on account_row.id = entry_row.fund_account_id
     and account_row.tenant_id = entry_row.tenant_id
    where entry_row.tenant_id = v_tenant_id
      and (p_account_set_id is null or entry_row.account_set_id = p_account_set_id)
      and (
        p_fund_account_id is null
        or (
          entry_row.fund_account_id = p_fund_account_id
          and app_private.resolve_field_access(
            'fms.fund_ledger', 'accountDetails', entry_row.created_by_user_id
          ) in ('read', 'edit')
        )
      )
      and (p_direction is null or entry_row.direction = p_direction)
      and (p_source_type is null or entry_row.source_type = p_source_type)
      and (p_status is null or entry_row.status = p_status)
      and (p_entry_start_date is null or entry_row.entry_date >= p_entry_start_date)
      and (p_entry_end_date is null or entry_row.entry_date <= p_entry_end_date)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or entry_row.entry_no ilike '%' || btrim(p_keyword) || '%'
        or (
          app_private.resolve_field_access(
            'fms.fund_ledger', 'accountDetails', entry_row.created_by_user_id
          ) in ('read', 'edit')
          and account_row.account_name ilike '%' || btrim(p_keyword) || '%'
        )
        or (
          app_private.resolve_field_access(
            'fms.fund_ledger', 'transactionDetails', entry_row.created_by_user_id
          ) in ('read', 'edit')
          and (
            entry_row.source_no ilike '%' || btrim(p_keyword) || '%'
            or entry_row.summary ilike '%' || btrim(p_keyword) || '%'
            or entry_row.counterparty_name ilike '%' || btrim(p_keyword) || '%'
            or entry_row.bank_reference ilike '%' || btrim(p_keyword) || '%'
          )
        )
      )
    order by entry_row.entry_date desc, entry_row.create_time desc, entry_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_fund_ledger_to_secure_json(
        app_private.fms_fund_ledger_raw_json(v_row.id),
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

revoke all on table public.fms_fund_ledger_entry from anon, authenticated;

revoke all on function public.fms_list_fund_ledger_entries_secure(
  integer, integer, uuid, uuid, text, text, text, text, date, date, uuid
) from public, anon, authenticated;

grant execute on function public.fms_list_fund_ledger_entries_secure(
  integer, integer, uuid, uuid, text, text, text, text, date, date, uuid
) to authenticated;

do $$
begin
  if exists (
    select 1
    from public.sys_tenant tenant_row
    where not exists (
      select 1
      from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'fms.fund_ledger'
        and resource_row.owner_column = 'created_by_user_id'
        and resource_row.enabled is true
    )
  ) then
    raise exception 'Missing fms.fund_ledger permission resource';
  end if;
  if exists (
    select 1
    from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.fund_ledger'
      and (
        select count(*)
        from public.sys_permission_field field_row
        where field_row.tenant_id = resource_row.tenant_id
          and field_row.resource_id = resource_row.id
          and field_row.enabled is true
      ) <> 3
  ) then
    raise exception 'Unexpected fms.fund_ledger field catalog';
  end if;
  if has_table_privilege('authenticated', 'public.fms_fund_ledger_entry', 'select')
     or has_table_privilege('anon', 'public.fms_fund_ledger_entry', 'select') then
    raise exception 'Direct fund ledger reads remain exposed';
  end if;
  if has_function_privilege(
    'anon',
    'public.fms_list_fund_ledger_entries_secure(integer,integer,uuid,uuid,text,text,text,text,date,date,uuid)',
    'execute'
  ) then
    raise exception 'Anonymous fund ledger RPC access remains exposed';
  end if;
end;
$$;

;
