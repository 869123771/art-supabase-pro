-- Extend tenant field authorization to customer and carrier settlement statements.
-- Amounts are never exposed through the direct Data API. Authenticated clients must
-- use the secure RPCs below so tenant, button, owner, role, user and masking rules
-- are evaluated in one database boundary.

alter table public.tms_customer_statement
  add column if not exists created_by_user_id uuid;

alter table public.tms_carrier_statement
  add column if not exists created_by_user_id uuid;

update public.tms_customer_statement statement_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = statement_row.tenant_id
    and user_row.deleted_at is null
    and (
      lower(user_row.user_email) = lower(statement_row.create_by)
      or lower(user_row.user_name) = lower(statement_row.create_by)
      or lower(user_row.nick_name) = lower(statement_row.create_by)
    )
  order by
    case
      when lower(user_row.user_email) = lower(statement_row.create_by) then 0
      when lower(user_row.user_name) = lower(statement_row.create_by) then 1
      else 2
    end,
    user_row.create_time,
    user_row.id
  limit 1
)
where statement_row.created_by_user_id is null;

update public.tms_carrier_statement statement_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = statement_row.tenant_id
    and user_row.deleted_at is null
    and (
      lower(user_row.user_email) = lower(statement_row.create_by)
      or lower(user_row.user_name) = lower(statement_row.create_by)
      or lower(user_row.nick_name) = lower(statement_row.create_by)
    )
  order by
    case
      when lower(user_row.user_email) = lower(statement_row.create_by) then 0
      when lower(user_row.user_name) = lower(statement_row.create_by) then 1
      else 2
    end,
    user_row.create_time,
    user_row.id
  limit 1
)
where statement_row.created_by_user_id is null;

do $$
begin
  if exists (
    select 1 from public.tms_customer_statement where created_by_user_id is null
  ) then
    raise exception 'Unable to resolve every customer statement creator';
  end if;
  if exists (
    select 1 from public.tms_carrier_statement where created_by_user_id is null
  ) then
    raise exception 'Unable to resolve every carrier statement creator';
  end if;
end;
$$;

alter table public.tms_customer_statement
  alter column created_by_user_id set not null;

alter table public.tms_carrier_statement
  alter column created_by_user_id set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.tms_customer_statement'::regclass
      and conname = 'tms_customer_statement_created_by_user_tenant_fkey'
  ) then
    alter table public.tms_customer_statement
      add constraint tms_customer_statement_created_by_user_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user (id, tenant_id)
      on delete restrict;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.tms_carrier_statement'::regclass
      and conname = 'tms_carrier_statement_created_by_user_tenant_fkey'
  ) then
    alter table public.tms_carrier_statement
      add constraint tms_carrier_statement_created_by_user_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user (id, tenant_id)
      on delete restrict;
  end if;
end;
$$;

create index if not exists tms_customer_statement_tenant_creator_idx
  on public.tms_customer_statement (tenant_id, created_by_user_id);

create index if not exists tms_carrier_statement_tenant_creator_idx
  on public.tms_carrier_statement (tenant_id, created_by_user_id);

create or replace function app_private.set_tms_statement_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null then
      new.created_by_user_id := v_current_user_id;
    elsif new.created_by_user_id is null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and user_row.deleted_at is null
        and (
          lower(user_row.user_email) = lower(new.create_by)
          or lower(user_row.user_name) = lower(new.create_by)
          or lower(user_row.nick_name) = lower(new.create_by)
        )
      order by
        case
          when lower(user_row.user_email) = lower(new.create_by) then 0
          when lower(user_row.user_name) = lower(new.create_by) then 1
          else 2
        end,
        user_row.create_time,
        user_row.id
      limit 1;
    end if;

    if new.created_by_user_id is null then
      raise exception 'Authenticated statement creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Statement creator identity is immutable' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists tms_customer_statement_creator_identity
  on public.tms_customer_statement;
create trigger tms_customer_statement_creator_identity
before insert or update of created_by_user_id on public.tms_customer_statement
for each row execute function app_private.set_tms_statement_creator_identity();

drop trigger if exists tms_carrier_statement_creator_identity
  on public.tms_carrier_statement;
create trigger tms_carrier_statement_creator_identity
before insert or update of created_by_user_id on public.tms_carrier_statement
for each row execute function app_private.set_tms_statement_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_statement;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_statement(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.customer_statement', '客户对账单',
    'FinanceCustomerSettlement', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'statementAmounts', '应收与对账金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'settlementAmounts', '已结与未结金额',
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

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.carrier_statement', '承运商对账单',
    'FinanceCarrierSettlement', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'statementAmounts', '成本与应付对账金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'settlementAmounts', '已付与未付金额',
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

-- Preserve existing finance workflows during rollout. Administrators can tighten
-- these role grants later from the field-permission matrix.
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
 and (
   (
     resource_row.resource_key = 'tms.customer_statement'
     and menu_row.name in ('FinanceCustomerSettlement', 'FinanceCashTransaction')
   )
   or (
     resource_row.resource_key = 'tms.carrier_statement'
     and menu_row.name in (
       'FinanceCarrierSettlement', 'FinanceCashTransaction',
       'FinanceCarrierPaymentApplication'
     )
   )
 )
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key in ('tms.customer_statement', 'tms.carrier_statement')
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.apply_jsonb_array_amount_access(
  p_rows jsonb,
  p_keys text[],
  p_access text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      app_private.apply_jsonb_amount_access(row_value, p_keys, p_access)
      order by row_number
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
    with ordinality as rows(row_value, row_number);
$$;

create or replace function app_private.tms_customer_statement_to_secure_json(
  p_statement jsonb,
  p_owner_id uuid,
  p_items jsonb default null,
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
    app_private.field_access_map('tms.customer_statement', p_owner_id)
  );
  v_data jsonb := coalesce(p_statement, '{}'::jsonb) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'statementAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['statement_amount']::text[],
    v_level
  );
  if p_items is not null then
    v_data := jsonb_set(
      v_data,
      '{items}',
      app_private.apply_jsonb_array_amount_access(
        p_items,
        array['receivable_amount', 'adjustment_amount', 'line_amount']::text[],
        v_level
      ),
      true
    );
  end if;

  v_level := coalesce(v_access->>'settlementAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['settled_amount', 'outstanding_amount']::text[],
    v_level
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.tms_carrier_statement_to_secure_json(
  p_statement jsonb,
  p_owner_id uuid,
  p_items jsonb default null,
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
    app_private.field_access_map('tms.carrier_statement', p_owner_id)
  );
  v_data jsonb := coalesce(p_statement, '{}'::jsonb) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'statementAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['statement_amount']::text[],
    v_level
  );
  if p_items is not null then
    v_data := jsonb_set(
      v_data,
      '{items}',
      app_private.apply_jsonb_array_amount_access(
        p_items,
        array['cost_amount', 'adjustment_amount', 'line_amount']::text[],
        v_level
      ),
      true
    );
  end if;

  v_level := coalesce(v_access->>'settlementAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'settled_amount', 'outstanding_amount',
      'statement_outstanding_amount', 'reserved_amount'
    ]::text[],
    v_level
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.tms_list_customer_statements_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_customer_id uuid default null,
  p_record_id uuid default null,
  p_status text default null,
  p_keyword text default null,
  p_period_start date default null,
  p_period_end date default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_permission text := case when p_purpose = 'export'
    then 'FinanceCustomerSettlement:Export'
    else 'FinanceCustomerSettlement:View'
  end;
  v_limit integer;
  v_base_access jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid customer statement read purpose';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCustomerSettlement', v_permission, null, false
  ) then
    raise exception 'Missing customer statement read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.customer_statement', null);

  return (
    with filtered as materialized (
      select
        summary_row as statement_record,
        statement_row.created_by_user_id
      from public.tms_customer_statement_summary summary_row
      join public.tms_customer_statement statement_row
        on statement_row.id = summary_row.id
       and statement_row.tenant_id = summary_row.tenant_id
      where (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id)
        and (p_customer_id is null or summary_row.customer_id = p_customer_id)
        and (p_record_id is null or summary_row.id = p_record_id)
        and (p_status is null or summary_row.status = p_status)
        and (p_period_start is null or summary_row.period_start >= p_period_start)
        and (p_period_end is null or summary_row.period_end <= p_period_end)
        and (p_ids is null or summary_row.id = any(p_ids))
        and (
          nullif(btrim(p_keyword), '') is null
          or summary_row.statement_no ilike '%' || btrim(p_keyword) || '%'
          or summary_row.customer_name ilike '%' || btrim(p_keyword) || '%'
          or summary_row.remark ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.*
      from filtered
      order by (filtered.statement_record).create_time desc,
               (filtered.statement_record).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          app_private.tms_customer_statement_to_secure_json(
            to_jsonb(paged.statement_record),
            paged.created_by_user_id
          )
          order by (paged.statement_record).create_time desc,
                   (paged.statement_record).id
        )
        from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'fieldAccess', v_base_access
    )
  );
end;
$$;

create or replace function public.tms_list_carrier_statements_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_carrier_id uuid default null,
  p_record_id uuid default null,
  p_status text default null,
  p_keyword text default null,
  p_period_start date default null,
  p_period_end date default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_permission text := case when p_purpose = 'export'
    then 'FinanceCarrierSettlement:Export'
    else 'FinanceCarrierSettlement:View'
  end;
  v_limit integer;
  v_base_access jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid carrier statement read purpose';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCarrierSettlement', v_permission, null, false
  ) then
    raise exception 'Missing carrier statement read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.carrier_statement', null);

  return (
    with filtered as materialized (
      select
        summary_row as statement_record,
        statement_row.created_by_user_id
      from public.tms_carrier_statement_summary summary_row
      join public.tms_carrier_statement statement_row
        on statement_row.id = summary_row.id
       and statement_row.tenant_id = summary_row.tenant_id
      where (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id)
        and (p_carrier_id is null or summary_row.carrier_id = p_carrier_id)
        and (p_record_id is null or summary_row.id = p_record_id)
        and (p_status is null or summary_row.status = p_status)
        and (p_period_start is null or summary_row.period_start >= p_period_start)
        and (p_period_end is null or summary_row.period_end <= p_period_end)
        and (p_ids is null or summary_row.id = any(p_ids))
        and (
          nullif(btrim(p_keyword), '') is null
          or summary_row.statement_no ilike '%' || btrim(p_keyword) || '%'
          or summary_row.carrier_name ilike '%' || btrim(p_keyword) || '%'
          or summary_row.remark ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.*
      from filtered
      order by (filtered.statement_record).create_time desc,
               (filtered.statement_record).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          app_private.tms_carrier_statement_to_secure_json(
            to_jsonb(paged.statement_record),
            paged.created_by_user_id
          )
          order by (paged.statement_record).create_time desc,
                   (paged.statement_record).id
        )
        from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'fieldAccess', v_base_access
    )
  );
end;
$$;

create or replace function public.tms_get_customer_statement_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_statement public.tms_customer_statement_summary%rowtype;
  v_owner_id uuid;
  v_items jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceCustomerSettlement', 'FinanceCustomerSettlement:View', null, false
  ) then
    raise exception 'Missing customer statement view permission' using errcode = '42501';
  end if;

  select summary_row.*
  into v_statement
  from public.tms_customer_statement_summary summary_row
  join public.tms_customer_statement statement_row
    on statement_row.id = summary_row.id
   and statement_row.tenant_id = summary_row.tenant_id
  where summary_row.id = p_id
    and (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id);

  if not found then
    return null;
  end if;

  select statement_row.created_by_user_id
  into v_owner_id
  from public.tms_customer_statement statement_row
  where statement_row.id = v_statement.id
    and statement_row.tenant_id = v_statement.tenant_id;

  select coalesce(
    jsonb_agg(
      to_jsonb(item_row) - 'tenant_id'
      order by item_row.completed_at_snapshot, item_row.id
    ),
    '[]'::jsonb
  )
  into v_items
  from public.tms_customer_statement_item item_row
  where item_row.statement_id = p_id
    and item_row.tenant_id = v_statement.tenant_id;

  return app_private.tms_customer_statement_to_secure_json(
    to_jsonb(v_statement), v_owner_id, v_items
  );
end;
$$;

create or replace function public.tms_get_carrier_statement_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_statement public.tms_carrier_statement_summary%rowtype;
  v_owner_id uuid;
  v_items jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceCarrierSettlement', 'FinanceCarrierSettlement:View', null, false
  ) then
    raise exception 'Missing carrier statement view permission' using errcode = '42501';
  end if;

  select summary_row.*
  into v_statement
  from public.tms_carrier_statement_summary summary_row
  join public.tms_carrier_statement statement_row
    on statement_row.id = summary_row.id
   and statement_row.tenant_id = summary_row.tenant_id
  where summary_row.id = p_id
    and (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id);

  if not found then
    return null;
  end if;

  select statement_row.created_by_user_id
  into v_owner_id
  from public.tms_carrier_statement statement_row
  where statement_row.id = v_statement.id
    and statement_row.tenant_id = v_statement.tenant_id;

  select coalesce(
    jsonb_agg(
      to_jsonb(item_row) - 'tenant_id'
      order by item_row.occurred_on_snapshot, item_row.id
    ),
    '[]'::jsonb
  )
  into v_items
  from public.tms_carrier_statement_item item_row
  where item_row.statement_id = p_id
    and item_row.tenant_id = v_statement.tenant_id;

  return app_private.tms_carrier_statement_to_secure_json(
    to_jsonb(v_statement), v_owner_id, v_items
  );
end;
$$;

create or replace function public.tms_list_customer_statement_eligible_waybills_secure(
  p_customer_id uuid,
  p_period_start date,
  p_period_end date,
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb;
  v_amount_access text;
  v_limit integer;
begin
  if not app_private.can_execute_business_action(
    'FinanceCustomerSettlement', 'FinanceCustomerSettlement:Add', null, false
  ) then
    raise exception 'Missing customer statement create permission' using errcode = '42501';
  end if;
  if p_period_start is null or p_period_end is null or p_period_start > p_period_end then
    raise exception 'Invalid customer statement period';
  end if;

  v_access := app_private.field_access_map('tms.customer_statement', null);
  v_amount_access := coalesce(v_access->>'statementAmounts', 'hidden');
  v_limit := least(500, greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1));

  return (
    with filtered as materialized (
      select eligible_row
      from public.tms_customer_statement_eligible_waybill eligible_row
      where eligible_row.tenant_id = v_tenant_id
        and eligible_row.customer_id = p_customer_id
        and eligible_row.completed_at >= p_period_start::timestamp
        and eligible_row.completed_at < (p_period_end + 1)::timestamp
        and (
          nullif(btrim(p_keyword), '') is null
          or eligible_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
          or eligible_row.order_no ilike '%' || btrim(p_keyword) || '%'
          or eligible_row.origin_station ilike '%' || btrim(p_keyword) || '%'
          or eligible_row.destination_station ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.eligible_row
      from filtered
      order by (filtered.eligible_row).completed_at desc,
               (filtered.eligible_row).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          app_private.apply_jsonb_amount_access(
            to_jsonb(paged.eligible_row) - 'tenant_id',
            array['receivable_amount']::text[],
            v_amount_access
          )
          order by (paged.eligible_row).completed_at desc,
                   (paged.eligible_row).id
        ) from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'fieldAccess', v_access
    )
  );
end;
$$;

create or replace function public.tms_list_carrier_statement_eligible_costs_secure(
  p_carrier_id uuid,
  p_period_start date,
  p_period_end date,
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb;
  v_amount_access text;
  v_limit integer;
begin
  if not app_private.can_execute_business_action(
    'FinanceCarrierSettlement', 'FinanceCarrierSettlement:Add', null, false
  ) then
    raise exception 'Missing carrier statement create permission' using errcode = '42501';
  end if;
  if p_period_start is null or p_period_end is null or p_period_start > p_period_end then
    raise exception 'Invalid carrier statement period';
  end if;

  v_access := app_private.field_access_map('tms.carrier_statement', null);
  v_amount_access := coalesce(v_access->>'statementAmounts', 'hidden');
  v_limit := least(500, greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1));

  return (
    with filtered as materialized (
      select eligible_row
      from public.tms_carrier_statement_eligible_cost eligible_row
      where eligible_row.tenant_id = v_tenant_id
        and eligible_row.carrier_id = p_carrier_id
        and eligible_row.occurred_on between p_period_start and p_period_end
        and (
          nullif(btrim(p_keyword), '') is null
          or eligible_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
          or eligible_row.payee_name ilike '%' || btrim(p_keyword) || '%'
          or eligible_row.origin_city ilike '%' || btrim(p_keyword) || '%'
          or eligible_row.destination_city ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.eligible_row
      from filtered
      order by (filtered.eligible_row).occurred_on desc,
               (filtered.eligible_row).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          app_private.apply_jsonb_amount_access(
            to_jsonb(paged.eligible_row) - 'tenant_id',
            array['cost_amount']::text[],
            v_amount_access
          )
          order by (paged.eligible_row).occurred_on desc,
                   (paged.eligible_row).id
        ) from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'fieldAccess', v_access
    )
  );
end;
$$;

create or replace function public.tms_list_customer_statement_allocatable_secure(
  p_customer_id uuid,
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(
    500,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
begin
  if not (
    app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:Add', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:Allocate', null, false
    )
  ) then
    raise exception 'Missing customer receipt allocation permission' using errcode = '42501';
  end if;

  return (
    with filtered as materialized (
      select allocatable_row
      from public.tms_customer_statement_allocatable allocatable_row
      join public.tms_customer_statement statement_row
        on statement_row.id = allocatable_row.id
       and statement_row.tenant_id = allocatable_row.tenant_id
      where allocatable_row.tenant_id = v_tenant_id
        and allocatable_row.customer_id = p_customer_id
        and app_private.resolve_field_access(
          'tms.customer_statement', 'statementAmounts', statement_row.created_by_user_id
        ) in ('read', 'edit')
        and app_private.resolve_field_access(
          'tms.customer_statement', 'settlementAmounts', statement_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          nullif(btrim(p_keyword), '') is null
          or allocatable_row.statement_no ilike '%' || btrim(p_keyword) || '%'
          or allocatable_row.customer_name ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.allocatable_row
      from filtered
      order by (filtered.allocatable_row).period_end,
               (filtered.allocatable_row).create_time,
               (filtered.allocatable_row).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          to_jsonb(paged.allocatable_row) - 'tenant_id'
          order by (paged.allocatable_row).period_end,
                   (paged.allocatable_row).create_time,
                   (paged.allocatable_row).id
        ) from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    )
  );
end;
$$;

create or replace function public.tms_list_carrier_statement_allocatable_secure(
  p_carrier_id uuid,
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(
    500,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
begin
  if not (
    app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:CreatePayment', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:Allocate', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCarrierPaymentApplication', 'FinanceCarrierPaymentApplication:Add', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCarrierPaymentApplication', 'FinanceCarrierPaymentApplication:Edit', null, false
    )
  ) then
    raise exception 'Missing carrier payment allocation permission' using errcode = '42501';
  end if;

  return (
    with filtered as materialized (
      select allocatable_row
      from public.tms_carrier_statement_allocatable allocatable_row
      join public.tms_carrier_statement statement_row
        on statement_row.id = allocatable_row.id
       and statement_row.tenant_id = allocatable_row.tenant_id
      where allocatable_row.tenant_id = v_tenant_id
        and allocatable_row.carrier_id = p_carrier_id
        and app_private.resolve_field_access(
          'tms.carrier_statement', 'statementAmounts', statement_row.created_by_user_id
        ) in ('read', 'edit')
        and app_private.resolve_field_access(
          'tms.carrier_statement', 'settlementAmounts', statement_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          nullif(btrim(p_keyword), '') is null
          or allocatable_row.statement_no ilike '%' || btrim(p_keyword) || '%'
          or allocatable_row.carrier_name ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.allocatable_row
      from filtered
      order by (filtered.allocatable_row).period_end,
               (filtered.allocatable_row).create_time,
               (filtered.allocatable_row).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          to_jsonb(paged.allocatable_row) - 'tenant_id'
          order by (paged.allocatable_row).period_end,
                   (paged.allocatable_row).create_time,
                   (paged.allocatable_row).id
        ) from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    )
  );
end;
$$;

create or replace function public.tms_create_customer_statement_secure(
  p_customer_id uuid,
  p_period_start date,
  p_period_end date,
  p_waybill_ids uuid[],
  p_remark text default null,
  p_statement_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCustomerSettlement', 'FinanceCustomerSettlement:Add', null, false
  ) then
    raise exception 'Missing customer statement create permission' using errcode = '42501';
  end if;

  return public.create_tms_customer_statement(
    p_customer_id,
    p_period_start,
    p_period_end,
    p_waybill_ids,
    p_remark,
    p_statement_no
  );
end;
$$;

create or replace function public.tms_create_carrier_statement_secure(
  p_carrier_id uuid,
  p_period_start date,
  p_period_end date,
  p_cost_ids uuid[],
  p_remark text default null,
  p_statement_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCarrierSettlement', 'FinanceCarrierSettlement:Add', null, false
  ) then
    raise exception 'Missing carrier statement create permission' using errcode = '42501';
  end if;

  return public.create_tms_carrier_statement(
    p_carrier_id,
    p_period_start,
    p_period_end,
    p_cost_ids,
    p_remark,
    p_statement_no
  );
end;
$$;

create or replace function public.tms_void_customer_statement_secure(
  p_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'FinanceCustomerSettlement', 'FinanceCustomerSettlement:Void', null, false
  ) then
    raise exception 'Missing customer statement void permission' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Void reason is required';
  end if;

  update public.tms_customer_statement
  set status = 'voided', void_reason = btrim(p_reason)
  where id = p_id
    and (app_private.is_platform_super() or tenant_id = v_tenant_id)
    and status = 'confirmed';

  if not found then
    raise exception 'Customer statement is missing or cannot be voided';
  end if;
  return true;
end;
$$;

create or replace function public.tms_void_carrier_statement_secure(
  p_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'FinanceCarrierSettlement', 'FinanceCarrierSettlement:Void', null, false
  ) then
    raise exception 'Missing carrier statement void permission' using errcode = '42501';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Void reason is required';
  end if;

  update public.tms_carrier_statement
  set status = 'voided', void_reason = btrim(p_reason)
  where id = p_id
    and (app_private.is_platform_super() or tenant_id = v_tenant_id)
    and status = 'confirmed';

  if not found then
    raise exception 'Carrier statement is missing or cannot be voided';
  end if;
  return true;
end;
$$;

create or replace function public.tms_delete_customer_statement_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'FinanceCustomerSettlement', 'FinanceCustomerSettlement:Delete', null, false
  ) then
    raise exception 'Missing customer statement delete permission' using errcode = '42501';
  end if;

  delete from public.tms_customer_statement
  where id = p_id
    and (app_private.is_platform_super() or tenant_id = v_tenant_id)
    and status = 'draft';

  if not found then
    raise exception 'Customer statement is missing or cannot be deleted';
  end if;
  return true;
end;
$$;

create or replace function public.tms_delete_carrier_statement_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'FinanceCarrierSettlement', 'FinanceCarrierSettlement:Delete', null, false
  ) then
    raise exception 'Missing carrier statement delete permission' using errcode = '42501';
  end if;

  delete from public.tms_carrier_statement
  where id = p_id
    and (app_private.is_platform_super() or tenant_id = v_tenant_id)
    and status = 'draft';

  if not found then
    raise exception 'Carrier statement is missing or cannot be deleted';
  end if;
  return true;
end;
$$;

-- Remove every direct sensitive read path. A deliberately small set of
-- non-sensitive base columns remains readable for nested cash-allocation labels.
revoke all on table
  public.tms_customer_statement_summary,
  public.tms_customer_statement_eligible_waybill,
  public.tms_customer_statement_allocatable,
  public.tms_customer_statement_item,
  public.tms_carrier_statement_summary,
  public.tms_carrier_statement_eligible_cost,
  public.tms_carrier_statement_allocatable,
  public.tms_carrier_statement_item
from public, anon, authenticated;

revoke all on table
  public.tms_customer_statement,
  public.tms_carrier_statement
from public, anon, authenticated;

grant select (
  id, statement_no, customer_id, customer_name_snapshot,
  period_start, period_end, status
) on public.tms_customer_statement to authenticated;

grant select (
  id, statement_no, carrier_id, carrier_name_snapshot,
  period_start, period_end, status
) on public.tms_carrier_statement to authenticated;

revoke execute on function public.create_tms_customer_statement(
  uuid, date, date, uuid[], text
) from public, anon, authenticated;
revoke execute on function public.create_tms_customer_statement(
  uuid, date, date, uuid[], text, text
) from public, anon, authenticated;
revoke execute on function public.create_tms_carrier_statement(
  uuid, date, date, uuid[], text
) from public, anon, authenticated;
revoke execute on function public.create_tms_carrier_statement(
  uuid, date, date, uuid[], text, text
) from public, anon, authenticated;

revoke execute on function app_private.set_tms_statement_creator_identity()
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog_before_statement(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.apply_jsonb_array_amount_access(jsonb, text[], text)
  from public, anon, authenticated;
revoke execute on function app_private.tms_customer_statement_to_secure_json(
  jsonb, uuid, jsonb, jsonb
) from public, anon, authenticated;
revoke execute on function app_private.tms_carrier_statement_to_secure_json(
  jsonb, uuid, jsonb, jsonb
) from public, anon, authenticated;

revoke execute on function public.tms_list_customer_statements_secure(
  integer, integer, uuid, uuid, text, text, date, date, uuid[], text
) from public, anon;
revoke execute on function public.tms_list_carrier_statements_secure(
  integer, integer, uuid, uuid, text, text, date, date, uuid[], text
) from public, anon;
revoke execute on function public.tms_get_customer_statement_secure(uuid)
  from public, anon;
revoke execute on function public.tms_get_carrier_statement_secure(uuid)
  from public, anon;
revoke execute on function public.tms_list_customer_statement_eligible_waybills_secure(
  uuid, date, date, text, integer, integer
) from public, anon;
revoke execute on function public.tms_list_carrier_statement_eligible_costs_secure(
  uuid, date, date, text, integer, integer
) from public, anon;
revoke execute on function public.tms_list_customer_statement_allocatable_secure(
  uuid, text, integer, integer
) from public, anon;
revoke execute on function public.tms_list_carrier_statement_allocatable_secure(
  uuid, text, integer, integer
) from public, anon;
revoke execute on function public.tms_create_customer_statement_secure(
  uuid, date, date, uuid[], text, text
) from public, anon;
revoke execute on function public.tms_create_carrier_statement_secure(
  uuid, date, date, uuid[], text, text
) from public, anon;
revoke execute on function public.tms_void_customer_statement_secure(uuid, text)
  from public, anon;
revoke execute on function public.tms_void_carrier_statement_secure(uuid, text)
  from public, anon;
revoke execute on function public.tms_delete_customer_statement_secure(uuid)
  from public, anon;
revoke execute on function public.tms_delete_carrier_statement_secure(uuid)
  from public, anon;

grant execute on function public.tms_list_customer_statements_secure(
  integer, integer, uuid, uuid, text, text, date, date, uuid[], text
) to authenticated, service_role;
grant execute on function public.tms_list_carrier_statements_secure(
  integer, integer, uuid, uuid, text, text, date, date, uuid[], text
) to authenticated, service_role;
grant execute on function public.tms_get_customer_statement_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_get_carrier_statement_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_list_customer_statement_eligible_waybills_secure(
  uuid, date, date, text, integer, integer
) to authenticated, service_role;
grant execute on function public.tms_list_carrier_statement_eligible_costs_secure(
  uuid, date, date, text, integer, integer
) to authenticated, service_role;
grant execute on function public.tms_list_customer_statement_allocatable_secure(
  uuid, text, integer, integer
) to authenticated, service_role;
grant execute on function public.tms_list_carrier_statement_allocatable_secure(
  uuid, text, integer, integer
) to authenticated, service_role;
grant execute on function public.tms_create_customer_statement_secure(
  uuid, date, date, uuid[], text, text
) to authenticated, service_role;
grant execute on function public.tms_create_carrier_statement_secure(
  uuid, date, date, uuid[], text, text
) to authenticated, service_role;
grant execute on function public.tms_void_customer_statement_secure(uuid, text)
  to authenticated, service_role;
grant execute on function public.tms_void_carrier_statement_secure(uuid, text)
  to authenticated, service_role;
grant execute on function public.tms_delete_customer_statement_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_delete_carrier_statement_secure(uuid)
  to authenticated, service_role;

;
