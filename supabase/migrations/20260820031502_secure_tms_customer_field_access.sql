-- Secure customer master data and customer addresses behind tenant-aware,
-- creator-aware field-permission boundaries.

alter table public.tms_customer
  add column if not exists created_by_user_id uuid;

alter table public.tms_customer_address
  add column if not exists created_by_user_id uuid;

update public.tms_customer customer_row
set created_by_user_id = creator.id
from public.sys_user creator
where customer_row.created_by_user_id is null
  and creator.tenant_id = customer_row.tenant_id
  and lower(creator.user_email) = lower(customer_row.create_by);

update public.tms_customer_address address_row
set created_by_user_id = creator.id
from public.sys_user creator
where address_row.created_by_user_id is null
  and creator.tenant_id = address_row.tenant_id
  and lower(creator.user_email) = lower(address_row.create_by);

do $$
begin
  if exists (select 1 from public.tms_customer where created_by_user_id is null) then
    raise exception 'Cannot secure tms_customer: one or more creator identities could not be backfilled';
  end if;

  if exists (select 1 from public.tms_customer_address where created_by_user_id is null) then
    raise exception 'Cannot secure tms_customer_address: one or more creator identities could not be backfilled';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tms_customer_creator_tenant_fkey'
      and conrelid = 'public.tms_customer'::regclass
  ) then
    alter table public.tms_customer
      add constraint tms_customer_creator_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user(id, tenant_id)
      on update restrict
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tms_customer_address_creator_tenant_fkey'
      and conrelid = 'public.tms_customer_address'::regclass
  ) then
    alter table public.tms_customer_address
      add constraint tms_customer_address_creator_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user(id, tenant_id)
      on update restrict
      on delete restrict;
  end if;
end
$$;

alter table public.tms_customer
  alter column created_by_user_id set not null;

alter table public.tms_customer_address
  alter column created_by_user_id set not null;

create index if not exists idx_tms_customer_tenant_creator
  on public.tms_customer (tenant_id, created_by_user_id, create_time desc);

create index if not exists idx_tms_customer_address_tenant_creator
  on public.tms_customer_address (tenant_id, created_by_user_id, create_time desc);

comment on column public.tms_customer.created_by_user_id is
  'Stable creator identity used for record-owner field permission resolution.';
comment on column public.tms_customer_address.created_by_user_id is
  'Stable creator identity used for record-owner field permission resolution.';

create or replace function app_private.set_tms_customer_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    if (select auth.uid()) is not null then
      if v_current_user_id is null then
        raise exception 'Authenticated application user not found' using errcode = '42501';
      end if;
      new.created_by_user_id := v_current_user_id;
    elsif new.created_by_user_id is null then
      raise exception 'Creator identity is required';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists tms_customer_creator_identity on public.tms_customer;
create trigger tms_customer_creator_identity
before insert or update on public.tms_customer
for each row execute function app_private.set_tms_customer_creator_identity();

drop trigger if exists tms_customer_address_creator_identity on public.tms_customer_address;
create trigger tms_customer_address_creator_identity
before insert or update on public.tms_customer_address
for each row execute function app_private.set_tms_customer_creator_identity();

-- Extend the catalog seeder so existing and future tenants receive the same resources.
create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  if p_tenant_id is null or not exists (
    select 1 from public.sys_tenant where id = p_tenant_id
  ) then
    raise exception 'Tenant not found';
  end if;

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.contract', '运输合同', 'TmsContract', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'contractAmount', '合同金额', 'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'transportUnitPrice', '运输单价', 'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'roadConsumptionRate', '路耗标准', 'hidden', 'amount', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'lossDeductionPrice', '亏扣价', 'hidden', 'amount', true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'transportDetailsPricing', '明细单价与运费', 'hidden', 'amount', true, 50, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'partyContactPhone', '相对方联系电话', 'hidden', 'phone', false, 60, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'attachments', '合同附件', 'hidden', 'none', true, 70, '624944977@qq.com', '624944977@qq.com')
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
    p_tenant_id, 'tms.customer', '客户档案', 'TmsCustomer', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'contactPhone', '联系人电话', 'hidden', 'phone', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'addressDetail', '公司详细地址与定位', 'hidden', 'address', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'taxNo', '纳税人识别号', 'hidden', 'id_card', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'bankAccount', '银行账号', 'hidden', 'bank_account', true, 40, '624944977@qq.com', '624944977@qq.com')
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
    p_tenant_id, 'tms.customer_address', '客户地址', 'TmsCustomerAddress', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'contactPhone', '地址联系人电话', 'hidden', 'phone', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'addressDetail', '详细地址与定位', 'hidden', 'address', true, 20, '624944977@qq.com', '624944977@qq.com')
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

do $$
declare
  tenant_row record;
begin
  for tenant_row in select id from public.sys_tenant loop
    perform app_private.seed_field_permission_catalog(tenant_row.id);
  end loop;
end
$$;

-- Preserve current customer-master behavior for existing roles. Roles that own the
-- customer pages retain edit; other existing roles retain read for shared selectors.
insert into public.sys_role_field_permission (
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  role_row.tenant_id,
  role_row.id,
  resource_row.id,
  field_row.id,
  case when exists (
    select 1
    from public.sys_role_menu role_menu
    join public.sys_menu menu_row on menu_row.id = role_menu.menu_id
    where role_menu.tenant_id = role_row.tenant_id
      and role_menu.role_id = role_row.id
      and menu_row.name = resource_row.menu_name
      and menu_row.type is distinct from 'button'
  ) then 'edit' else 'read' end,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role role_row
join public.sys_permission_resource resource_row
  on resource_row.tenant_id = role_row.tenant_id
 and resource_row.resource_key in ('tms.customer', 'tms.customer_address')
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
where role_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_access_business_menu(p_menu_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and (
      app_private.is_platform_super()
      or exists (
        select 1
        from public.sys_user current_user_row
        join public.sys_role role_row
          on role_row.tenant_id = current_user_row.tenant_id
         and role_row.enabled is true
         and role_row.role_code = any(coalesce(current_user_row.user_roles, array[]::text[]))
        join public.sys_role_menu role_menu
          on role_menu.tenant_id = role_row.tenant_id
         and role_menu.role_id = role_row.id
        join public.sys_menu menu_row
          on menu_row.id = role_menu.menu_id
         and menu_row.name = p_menu_name
         and menu_row.type is distinct from 'button'
        where current_user_row.auth_user_id = (select auth.uid())
          and current_user_row.status = '1'
          and current_user_row.deleted_at is null
          and (menu_row.meta->>'is_enable') is distinct from 'false'
      )
    );
$$;

create or replace function app_private.can_execute_business_action(
  p_menu_name text,
  p_permission text,
  p_record_owner_id uuid default null,
  p_allow_owner boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_private.can_access_business_menu(p_menu_name)
    and (
      app_private.is_platform_super()
      or (
        p_allow_owner
        and p_record_owner_id is not null
        and p_record_owner_id = app_private.current_app_user_id()
      )
      or not exists (
        select 1 from public.sys_menu menu_row
        where menu_row.type = 'button'
          and menu_row.name = p_permission
          and (menu_row.meta->>'is_enable') is distinct from 'false'
      )
      or app_private.has_permission(p_permission)
    );
$$;

create or replace function app_private.tms_customer_to_secure_json(
  p_customer public.tms_customer,
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
    app_private.field_access_map('tms.customer', p_customer.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_customer) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'contactPhone', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'contact_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{contact_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_customer.contact_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'addressDetail', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data
      - 'address_detail' - 'postal_code' - 'longitude' - 'latitude'
      - 'coordinate_system' - 'coordinate_source' - 'coordinate_status'
      - 'geocode_provider' - 'geocoded_at';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{address_detail}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_customer.address_detail, 'address')
    ), 'null'::jsonb)) - 'postal_code' - 'longitude' - 'latitude'
       - 'coordinate_system' - 'coordinate_source' - 'coordinate_status'
       - 'geocode_provider' - 'geocoded_at';
  end if;

  v_level := coalesce(v_access->>'taxNo', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'tax_no';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{tax_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_customer.tax_no, 'id_card')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'bankAccount', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'bank_account';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{bank_account}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_customer.bank_account, 'bank_account')
    ), 'null'::jsonb));
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_customer.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.tms_customer_option_to_secure_json(
  p_customer public.tms_customer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_secure jsonb := app_private.tms_customer_to_secure_json(p_customer, null);
begin
  return jsonb_strip_nulls(jsonb_build_object(
    'id', p_customer.id,
    'tenant_id', p_customer.tenant_id,
    'customer_code', p_customer.customer_code,
    'customer_name', p_customer.customer_name,
    'enabled', p_customer.enabled,
    'contact_name', p_customer.contact_name,
    'contact_phone', v_secure->'contact_phone',
    'region', p_customer.region,
    'region_adcode', p_customer.region_adcode,
    'address_detail', v_secure->'address_detail',
    'longitude', v_secure->'longitude',
    'latitude', v_secure->'latitude',
    'coordinate_system', v_secure->'coordinate_system',
    'coordinate_source', v_secure->'coordinate_source',
    'coordinate_status', v_secure->'coordinate_status',
    'geocode_provider', v_secure->'geocode_provider',
    'geocoded_at', v_secure->'geocoded_at',
    'postal_code', v_secure->'postal_code',
    'field_access', v_secure->'field_access',
    'is_record_owner', v_secure->'is_record_owner'
  ));
end;
$$;

create or replace function app_private.tms_customer_address_to_secure_json(
  p_address public.tms_customer_address,
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
    app_private.field_access_map('tms.customer_address', p_address.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_address) - 'tenant_id' - 'created_by_user_id';
  v_level text;
  v_customer jsonb;
begin
  v_level := coalesce(v_access->>'contactPhone', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'contact_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{contact_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_address.contact_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'addressDetail', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data
      - 'address_detail' - 'postal_code' - 'longitude' - 'latitude'
      - 'coordinate_system' - 'coordinate_source' - 'coordinate_status'
      - 'geocode_provider' - 'geocoded_at' - 'geofence_radius_m' - 'geofence_updated_at';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{address_detail}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_address.address_detail, 'address')
    ), 'null'::jsonb)) - 'postal_code' - 'longitude' - 'latitude'
       - 'coordinate_system' - 'coordinate_source' - 'coordinate_status'
       - 'geocode_provider' - 'geocoded_at' - 'geofence_radius_m' - 'geofence_updated_at';
  end if;

  if p_address.customer_id is not null then
    select jsonb_build_object(
      'id', customer_row.id,
      'customer_code', customer_row.customer_code,
      'customer_name', customer_row.customer_name,
      'contact_name', customer_row.contact_name
    ) into v_customer
    from public.tms_customer customer_row
    where customer_row.id = p_address.customer_id
      and customer_row.tenant_id = p_address.tenant_id;
  end if;

  return v_data || jsonb_build_object(
    'customer', v_customer,
    'field_access', v_access,
    'is_record_owner', p_address.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.tms_list_customers_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_customer_id uuid default null,
  p_customer_level text default null,
  p_industry text default null,
  p_enabled boolean default null,
  p_keyword text default null,
  p_create_time_from timestamptz default null,
  p_create_time_to timestamptz default null,
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
  v_permission text := case when p_purpose = 'export' then 'TmsCustomer:Export' else 'TmsCustomer:View' end;
  v_limit integer;
  v_base_access jsonb;
  v_can_search_phone boolean;
  v_can_search_address boolean;
  v_result jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid customer read purpose';
  end if;
  if not app_private.can_execute_business_action('TmsCustomer', v_permission, null, false) then
    raise exception 'Missing customer read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.customer', null);
  v_can_search_phone := coalesce(v_base_access->>'contactPhone', 'hidden') in ('read', 'edit');
  v_can_search_address := coalesce(v_base_access->>'addressDetail', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select customer_row as customer_record
    from public.tms_customer customer_row
    where (app_private.is_platform_super() or customer_row.tenant_id = v_tenant_id)
      and (p_customer_id is null or customer_row.id = p_customer_id)
      and (p_ids is null or customer_row.id = any(p_ids))
      and (p_customer_level is null or customer_row.customer_level = p_customer_level)
      and (p_industry is null or customer_row.industry = p_industry)
      and (p_enabled is null or customer_row.enabled = p_enabled)
      and (p_create_time_from is null or customer_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or customer_row.create_time <= p_create_time_to)
      and (
        nullif(btrim(p_keyword), '') is null
        or customer_row.customer_name ilike '%' || btrim(p_keyword) || '%'
        or customer_row.customer_code ilike '%' || btrim(p_keyword) || '%'
        or customer_row.contact_name ilike '%' || btrim(p_keyword) || '%'
        or (v_can_search_phone and customer_row.contact_phone ilike '%' || btrim(p_keyword) || '%')
        or (v_can_search_address and customer_row.address_detail ilike '%' || btrim(p_keyword) || '%')
      )
  ), paged as (
    select filtered.customer_record
    from filtered
    order by (filtered.customer_record).create_time desc, (filtered.customer_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_customer_to_secure_json(paged.customer_record, null)
        order by (paged.customer_record).create_time desc, (paged.customer_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.tms_list_customer_options_secure(
  p_exclude_id uuid default null,
  p_include_disabled boolean default false,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
begin
  if (select auth.uid()) is null or v_current_tenant_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  v_target_tenant_id := case
    when app_private.is_platform_super() then coalesce(p_tenant_id, v_current_tenant_id)
    else v_current_tenant_id
  end;

  return coalesce((
    select jsonb_agg(
      app_private.tms_customer_option_to_secure_json(customer_row)
      order by customer_row.customer_name, customer_row.id
    )
    from (
      select customer_record.*
      from public.tms_customer customer_record
      where customer_record.tenant_id = v_target_tenant_id
        and (p_include_disabled or customer_record.enabled)
        and (p_exclude_id is null or customer_record.id <> p_exclude_id)
      order by customer_record.customer_name, customer_record.id
      limit 1000
    ) customer_row
  ), '[]'::jsonb);
end;
$$;

create or replace function public.tms_list_customer_selector_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_keyword text default null,
  p_address_type text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_customer_access jsonb;
  v_can_search_phone boolean;
  v_can_search_address boolean;
  v_limit integer := least(200, greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_result jsonb;
begin
  if (select auth.uid()) is null or v_tenant_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_address_type is not null and p_address_type not in ('shipping', 'receiving') then
    raise exception 'Invalid customer address type';
  end if;

  v_customer_access := app_private.field_access_map('tms.customer', null);
  v_can_search_phone := coalesce(v_customer_access->>'contactPhone', 'hidden') in ('read', 'edit');
  v_can_search_address := coalesce(v_customer_access->>'addressDetail', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select customer_row as customer_record
    from public.tms_customer customer_row
    where customer_row.tenant_id = v_tenant_id
      and customer_row.enabled
      and (
        nullif(btrim(p_keyword), '') is null
        or customer_row.customer_name ilike '%' || btrim(p_keyword) || '%'
        or customer_row.customer_code ilike '%' || btrim(p_keyword) || '%'
        or customer_row.contact_name ilike '%' || btrim(p_keyword) || '%'
        or (v_can_search_phone and customer_row.contact_phone ilike '%' || btrim(p_keyword) || '%')
        or (v_can_search_address and customer_row.address_detail ilike '%' || btrim(p_keyword) || '%')
      )
  ), paged as (
    select filtered.customer_record
    from filtered
    order by (filtered.customer_record).create_time desc, (filtered.customer_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  ), shaped as (
    select
      app_private.tms_customer_option_to_secure_json(paged.customer_record) as customer_json,
      address_pick.address_record
    from paged
    left join lateral (
      select address_row as address_record
      from public.tms_customer_address address_row
      where p_address_type is not null
        and address_row.tenant_id = (paged.customer_record).tenant_id
        and address_row.customer_id = (paged.customer_record).id
        and address_row.address_type = p_address_type
      order by address_row.is_default desc, address_row.update_time desc nulls last,
               address_row.create_time desc, address_row.id
      limit 1
    ) address_pick on true
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        case when shaped.address_record is null then shaped.customer_json
        else (
          shaped.customer_json
          || jsonb_build_object('address_id', (shaped.address_record).id,
                                'address_type', (shaped.address_record).address_type)
          || (
            app_private.tms_customer_address_to_secure_json(shaped.address_record, null)
            - 'id' - 'customer_id' - 'customer' - 'field_access' - 'is_record_owner'
          )
          || jsonb_build_object(
            'field_access', app_private.field_access_map(
              'tms.customer_address', (shaped.address_record).created_by_user_id
            ),
            'is_record_owner', (shaped.address_record).created_by_user_id = app_private.current_app_user_id()
          )
        ) end
      ) from shaped
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.tms_list_customer_addresses_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_customer_id uuid default null,
  p_address_type text default null,
  p_keyword text default null,
  p_create_time_from timestamptz default null,
  p_create_time_to timestamptz default null,
  p_record_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_base_access jsonb;
  v_can_search_phone boolean;
  v_can_search_address boolean;
  v_limit integer := least(500, greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'TmsCustomerAddress', 'TmsCustomerAddress:View', null, false
  ) then
    raise exception 'Missing customer address read permission' using errcode = '42501';
  end if;
  if p_address_type is not null and p_address_type not in ('shipping', 'receiving') then
    raise exception 'Invalid customer address type';
  end if;

  v_base_access := app_private.field_access_map('tms.customer_address', null);
  v_can_search_phone := coalesce(v_base_access->>'contactPhone', 'hidden') in ('read', 'edit');
  v_can_search_address := coalesce(v_base_access->>'addressDetail', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select address_row as address_record
    from public.tms_customer_address address_row
    where (app_private.is_platform_super() or address_row.tenant_id = v_tenant_id)
      and (p_record_id is null or address_row.id = p_record_id)
      and (p_customer_id is null or address_row.customer_id = p_customer_id)
      and (p_address_type is null or address_row.address_type = p_address_type)
      and (p_create_time_from is null or address_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or address_row.create_time <= p_create_time_to)
      and (
        nullif(btrim(p_keyword), '') is null
        or address_row.contact_name ilike '%' || btrim(p_keyword) || '%'
        or (v_can_search_phone and address_row.contact_phone ilike '%' || btrim(p_keyword) || '%')
        or (v_can_search_address and address_row.address_detail ilike '%' || btrim(p_keyword) || '%')
      )
  ), paged as (
    select filtered.address_record
    from filtered
    order by (filtered.address_record).update_time desc nulls last,
             (filtered.address_record).create_time desc, (filtered.address_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_customer_address_to_secure_json(paged.address_record, null)
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.tms_list_customer_address_options_secure(
  p_customer_id uuid default null,
  p_tenant_id uuid default null,
  p_address_type text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
begin
  if (select auth.uid()) is null or v_current_tenant_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_address_type is not null and p_address_type not in ('shipping', 'receiving') then
    raise exception 'Invalid customer address type';
  end if;
  v_target_tenant_id := case
    when app_private.is_platform_super() then coalesce(p_tenant_id, v_current_tenant_id)
    else v_current_tenant_id
  end;

  return coalesce((
    select jsonb_agg(
      app_private.tms_customer_address_to_secure_json(address_row, null)
      order by address_row.is_default desc, address_row.update_time desc nulls last,
               address_row.create_time desc, address_row.id
    )
    from public.tms_customer_address address_row
    where address_row.tenant_id = v_target_tenant_id
      and (p_customer_id is null or address_row.customer_id = p_customer_id)
      and (p_address_type is null or address_row.address_type = p_address_type)
  ), '[]'::jsonb);
end;
$$;

create or replace function public.tms_get_customer_default_address_secure(
  p_customer_id uuid,
  p_address_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_address public.tms_customer_address%rowtype;
begin
  if (select auth.uid()) is null or app_private.current_user_tenant_id() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_address_type not in ('shipping', 'receiving') then
    raise exception 'Invalid customer address type';
  end if;

  select * into v_address
  from public.tms_customer_address address_row
  where address_row.tenant_id = app_private.current_user_tenant_id()
    and address_row.customer_id = p_customer_id
    and address_row.address_type = p_address_type
  order by address_row.is_default desc, address_row.update_time desc nulls last,
           address_row.create_time desc, address_row.id
  limit 1;

  if not found then return null; end if;
  return app_private.tms_customer_address_to_secure_json(v_address, null);
end;
$$;

create or replace function app_private.assert_tms_customer_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Customer payload must be a JSON object';
  end if;
  select array_agg(key order by key) into v_invalid_keys
  from jsonb_object_keys(p_payload) key
  where key <> all(array[
    'parent_unit_id', 'customer_code', 'customer_name', 'industry', 'customer_level',
    'tags', 'region', 'region_adcode', 'address_detail', 'longitude', 'latitude',
    'coordinate_system', 'coordinate_source', 'coordinate_status', 'geocode_provider',
    'geocoded_at', 'postal_code', 'enabled', 'contact_name', 'contact_phone',
    'contact_department', 'contact_position', 'contact_email', 'contact_qq',
    'invoice_title', 'tax_no', 'bank_name', 'bank_account', 'remark'
  ]::text[]);
  if v_invalid_keys is not null then
    raise exception 'Customer payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function app_private.assert_tms_customer_reference_scope(
  p_tenant_id uuid,
  p_parent_unit_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_parent_unit_id is not null and not exists (
    select 1 from public.tms_customer parent_row
    where parent_row.id = p_parent_unit_id and parent_row.tenant_id = p_tenant_id
  ) then
    raise exception 'Parent customer is outside the current tenant';
  end if;
end;
$$;

create or replace function public.tms_create_customer_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_customer%rowtype;
  v_id uuid;
begin
  if not app_private.can_execute_business_action('TmsCustomer', 'TmsCustomer:Add', null, false) then
    raise exception 'Missing customer create permission' using errcode = '42501';
  end if;
  perform app_private.assert_tms_customer_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.tms_customer, p_payload);
  perform app_private.assert_tms_customer_reference_scope(v_tenant_id, v_input.parent_unit_id);

  insert into public.tms_customer (
    parent_unit_id, customer_code, customer_name, industry, customer_level, tags,
    region, region_adcode, address_detail, longitude, latitude, coordinate_system,
    coordinate_source, coordinate_status, geocode_provider, geocoded_at, postal_code,
    enabled, contact_name, contact_phone, contact_department, contact_position,
    contact_email, contact_qq, invoice_title, tax_no, bank_name, bank_account, remark,
    tenant_id
  ) values (
    v_input.parent_unit_id, nullif(v_input.customer_code, ''), v_input.customer_name,
    v_input.industry, v_input.customer_level, coalesce(v_input.tags, array[]::text[]),
    v_input.region, v_input.region_adcode, v_input.address_detail, v_input.longitude,
    v_input.latitude, v_input.coordinate_system, v_input.coordinate_source,
    v_input.coordinate_status, v_input.geocode_provider, v_input.geocoded_at,
    v_input.postal_code, coalesce(v_input.enabled, true), v_input.contact_name,
    v_input.contact_phone, v_input.contact_department, v_input.contact_position,
    v_input.contact_email, v_input.contact_qq, v_input.invoice_title, v_input.tax_no,
    v_input.bank_name, v_input.bank_account, v_input.remark, v_tenant_id
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.tms_update_customer_secure(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.tms_customer%rowtype;
  v_candidate public.tms_customer%rowtype;
  v_updated public.tms_customer%rowtype;
begin
  select * into v_old
  from public.tms_customer customer_row
  where customer_row.id = p_id
    and (app_private.is_platform_super() or customer_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Customer not found or access denied'; end if;
  if not app_private.can_execute_business_action(
    'TmsCustomer', 'TmsCustomer:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing customer edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_customer_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  perform app_private.assert_tms_customer_reference_scope(v_old.tenant_id, v_candidate.parent_unit_id);

  if v_candidate.contact_phone is distinct from v_old.contact_phone
     and app_private.resolve_field_access('tms.customer', 'contactPhone', v_old.created_by_user_id) <> 'edit' then
    raise exception 'No edit permission for customer contact phone' using errcode = '42501';
  end if;
  if (v_candidate.region, v_candidate.region_adcode, v_candidate.address_detail,
      v_candidate.postal_code, v_candidate.longitude,
      v_candidate.latitude, v_candidate.coordinate_system, v_candidate.coordinate_source,
      v_candidate.coordinate_status, v_candidate.geocode_provider, v_candidate.geocoded_at)
     is distinct from
     (v_old.region, v_old.region_adcode, v_old.address_detail, v_old.postal_code,
      v_old.longitude, v_old.latitude,
      v_old.coordinate_system, v_old.coordinate_source, v_old.coordinate_status,
      v_old.geocode_provider, v_old.geocoded_at)
     and app_private.resolve_field_access('tms.customer', 'addressDetail', v_old.created_by_user_id) <> 'edit' then
    raise exception 'No edit permission for customer address' using errcode = '42501';
  end if;
  if v_candidate.tax_no is distinct from v_old.tax_no
     and app_private.resolve_field_access('tms.customer', 'taxNo', v_old.created_by_user_id) <> 'edit' then
    raise exception 'No edit permission for customer tax number' using errcode = '42501';
  end if;
  if v_candidate.bank_account is distinct from v_old.bank_account
     and app_private.resolve_field_access('tms.customer', 'bankAccount', v_old.created_by_user_id) <> 'edit' then
    raise exception 'No edit permission for customer bank account' using errcode = '42501';
  end if;

  update public.tms_customer set
    parent_unit_id = v_candidate.parent_unit_id,
    customer_code = v_candidate.customer_code,
    customer_name = v_candidate.customer_name,
    industry = v_candidate.industry,
    customer_level = v_candidate.customer_level,
    tags = v_candidate.tags,
    region = v_candidate.region,
    region_adcode = v_candidate.region_adcode,
    address_detail = v_candidate.address_detail,
    longitude = v_candidate.longitude,
    latitude = v_candidate.latitude,
    coordinate_system = v_candidate.coordinate_system,
    coordinate_source = v_candidate.coordinate_source,
    coordinate_status = v_candidate.coordinate_status,
    geocode_provider = v_candidate.geocode_provider,
    geocoded_at = v_candidate.geocoded_at,
    postal_code = v_candidate.postal_code,
    enabled = v_candidate.enabled,
    contact_name = v_candidate.contact_name,
    contact_phone = v_candidate.contact_phone,
    contact_department = v_candidate.contact_department,
    contact_position = v_candidate.contact_position,
    contact_email = v_candidate.contact_email,
    contact_qq = v_candidate.contact_qq,
    invoice_title = v_candidate.invoice_title,
    tax_no = v_candidate.tax_no,
    bank_name = v_candidate.bank_name,
    bank_account = v_candidate.bank_account,
    remark = v_candidate.remark
  where id = v_old.id
  returning * into v_updated;
  return app_private.tms_customer_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.tms_delete_customer_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer public.tms_customer%rowtype;
begin
  select * into v_customer from public.tms_customer customer_row
  where customer_row.id = p_id
    and (app_private.is_platform_super() or customer_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then return false; end if;
  if not app_private.can_execute_business_action(
    'TmsCustomer', 'TmsCustomer:Delete', v_customer.created_by_user_id, true
  ) then
    raise exception 'Missing customer delete permission' using errcode = '42501';
  end if;
  delete from public.tms_customer where id = v_customer.id;
  return true;
end;
$$;

create or replace function public.tms_delete_customers_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_deleted integer := 0;
begin
  if coalesce(cardinality(p_ids), 0) > 500 then
    raise exception 'A maximum of 500 customers can be deleted at once';
  end if;
  foreach v_id in array coalesce(p_ids, array[]::uuid[]) loop
    if public.tms_delete_customer_secure(v_id) then v_deleted := v_deleted + 1; end if;
  end loop;
  return v_deleted;
end;
$$;

create or replace function public.tms_import_customers_secure(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_existing public.tms_customer%rowtype;
  v_id uuid;
  v_count integer := 0;
begin
  if not app_private.can_execute_business_action('TmsCustomer', 'TmsCustomer:Import', null, false) then
    raise exception 'Missing customer import permission' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Customer import payload must be a JSON array';
  end if;
  if jsonb_array_length(p_rows) > 1000 then
    raise exception 'A maximum of 1000 customers can be imported at once';
  end if;
  for v_item in select value from jsonb_array_elements(p_rows) loop
    v_existing := null;
    if nullif(v_item->>'customer_code', '') is not null then
      select * into v_existing from public.tms_customer customer_row
      where customer_row.tenant_id = app_private.current_user_tenant_id()
        and customer_row.customer_code = v_item->>'customer_code'
      for update;
    end if;
    if v_existing.id is null then
      v_id := public.tms_create_customer_secure(v_item);
    else
      perform public.tms_update_customer_secure(v_existing.id, v_item - 'customer_code');
      v_id := v_existing.id;
    end if;
    v_count := v_count + 1;
  end loop;
  return jsonb_build_object('count', v_count);
end;
$$;

create or replace function app_private.assert_tms_customer_address_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Customer address payload must be a JSON object';
  end if;
  select array_agg(key order by key) into v_invalid_keys
  from jsonb_object_keys(p_payload) key
  where key <> all(array[
    'customer_id', 'address_type', 'contact_name', 'contact_phone', 'region',
    'region_adcode', 'address_detail', 'longitude', 'latitude', 'coordinate_system',
    'coordinate_source', 'coordinate_status', 'geocode_provider', 'geocoded_at',
    'postal_code', 'is_default', 'remark', 'geofence_enabled', 'geofence_radius_m',
    'geofence_updated_at'
  ]::text[]);
  if v_invalid_keys is not null then
    raise exception 'Customer address payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function app_private.assert_tms_customer_address_reference_scope(
  p_tenant_id uuid,
  p_customer_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_customer_id is not null and not exists (
    select 1 from public.tms_customer customer_row
    where customer_row.id = p_customer_id and customer_row.tenant_id = p_tenant_id
  ) then
    raise exception 'Customer address parent is outside the current tenant';
  end if;
end;
$$;

create or replace function public.tms_create_customer_address_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_customer_address%rowtype;
  v_id uuid;
begin
  if not app_private.can_execute_business_action(
    'TmsCustomerAddress', 'TmsCustomerAddress:Add', null, false
  ) then
    raise exception 'Missing customer address create permission' using errcode = '42501';
  end if;
  perform app_private.assert_tms_customer_address_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.tms_customer_address, p_payload);
  perform app_private.assert_tms_customer_address_reference_scope(v_tenant_id, v_input.customer_id);

  insert into public.tms_customer_address (
    customer_id, address_type, contact_name, contact_phone, region, region_adcode,
    address_detail, longitude, latitude, coordinate_system, coordinate_source,
    coordinate_status, geocode_provider, geocoded_at, postal_code, is_default, remark,
    tenant_id
  ) values (
    v_input.customer_id, v_input.address_type, v_input.contact_name, v_input.contact_phone,
    v_input.region, v_input.region_adcode, v_input.address_detail, v_input.longitude,
    v_input.latitude, coalesce(v_input.coordinate_system, 'gcj02'), v_input.coordinate_source,
    coalesce(v_input.coordinate_status, 'pending'), v_input.geocode_provider,
    v_input.geocoded_at, v_input.postal_code, coalesce(v_input.is_default, false),
    v_input.remark, v_tenant_id
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.tms_update_customer_address_secure(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.tms_customer_address%rowtype;
  v_candidate public.tms_customer_address%rowtype;
  v_updated public.tms_customer_address%rowtype;
  v_geofence_changed boolean;
begin
  select * into v_old from public.tms_customer_address address_row
  where address_row.id = p_id
    and (app_private.is_platform_super() or address_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Customer address not found or access denied'; end if;

  perform app_private.assert_tms_customer_address_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  v_geofence_changed := (v_candidate.geofence_enabled, v_candidate.geofence_radius_m,
    v_candidate.geofence_updated_at) is distinct from
    (v_old.geofence_enabled, v_old.geofence_radius_m, v_old.geofence_updated_at);

  if v_geofence_changed then
    if not app_private.can_execute_business_action(
      'TmsCustomerAddress', 'TmsCustomerAddress:Geofence', v_old.created_by_user_id, false
    ) then
      raise exception 'Missing customer address geofence permission' using errcode = '42501';
    end if;
    if app_private.resolve_field_access(
      'tms.customer_address', 'addressDetail', v_old.created_by_user_id
    ) <> 'edit' then
      raise exception 'No edit permission for customer address location' using errcode = '42501';
    end if;
  elsif not app_private.can_execute_business_action(
    'TmsCustomerAddress', 'TmsCustomerAddress:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing customer address edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_customer_address_reference_scope(v_old.tenant_id, v_candidate.customer_id);
  if v_candidate.contact_phone is distinct from v_old.contact_phone
     and app_private.resolve_field_access(
       'tms.customer_address', 'contactPhone', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for address contact phone' using errcode = '42501';
  end if;
  if (v_candidate.region, v_candidate.region_adcode, v_candidate.address_detail,
      v_candidate.postal_code, v_candidate.longitude,
      v_candidate.latitude, v_candidate.coordinate_system, v_candidate.coordinate_source,
      v_candidate.coordinate_status, v_candidate.geocode_provider, v_candidate.geocoded_at)
     is distinct from
     (v_old.region, v_old.region_adcode, v_old.address_detail, v_old.postal_code,
      v_old.longitude, v_old.latitude,
      v_old.coordinate_system, v_old.coordinate_source, v_old.coordinate_status,
      v_old.geocode_provider, v_old.geocoded_at)
     and app_private.resolve_field_access(
       'tms.customer_address', 'addressDetail', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for customer address detail' using errcode = '42501';
  end if;

  update public.tms_customer_address set
    customer_id = v_candidate.customer_id,
    address_type = v_candidate.address_type,
    contact_name = v_candidate.contact_name,
    contact_phone = v_candidate.contact_phone,
    region = v_candidate.region,
    region_adcode = v_candidate.region_adcode,
    address_detail = v_candidate.address_detail,
    longitude = v_candidate.longitude,
    latitude = v_candidate.latitude,
    coordinate_system = v_candidate.coordinate_system,
    coordinate_source = v_candidate.coordinate_source,
    coordinate_status = v_candidate.coordinate_status,
    geocode_provider = v_candidate.geocode_provider,
    geocoded_at = v_candidate.geocoded_at,
    postal_code = v_candidate.postal_code,
    is_default = v_candidate.is_default,
    remark = v_candidate.remark,
    geofence_enabled = v_candidate.geofence_enabled,
    geofence_radius_m = v_candidate.geofence_radius_m,
    geofence_updated_at = v_candidate.geofence_updated_at
  where id = v_old.id
  returning * into v_updated;
  return app_private.tms_customer_address_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.tms_delete_customer_address_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_address public.tms_customer_address%rowtype;
begin
  select * into v_address from public.tms_customer_address address_row
  where address_row.id = p_id
    and (app_private.is_platform_super() or address_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then return false; end if;
  if not app_private.can_execute_business_action(
    'TmsCustomerAddress', 'TmsCustomerAddress:Delete', v_address.created_by_user_id, true
  ) then
    raise exception 'Missing customer address delete permission' using errcode = '42501';
  end if;
  delete from public.tms_customer_address where id = v_address.id;
  return true;
end;
$$;

create or replace function public.tms_delete_customer_addresses_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_deleted integer := 0;
begin
  if coalesce(cardinality(p_ids), 0) > 500 then
    raise exception 'A maximum of 500 customer addresses can be deleted at once';
  end if;
  foreach v_id in array coalesce(p_ids, array[]::uuid[]) loop
    if public.tms_delete_customer_address_secure(v_id) then v_deleted := v_deleted + 1; end if;
  end loop;
  return v_deleted;
end;
$$;

create or replace function public.tms_list_favorite_routes_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_tenant_id uuid default null,
  p_customer_id uuid default null,
  p_enabled boolean default null,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
  v_limit integer := least(500, greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  v_result jsonb;
begin
  if not app_private.can_access_business_menu('TmsFavoriteRoute') then
    raise exception 'Missing favorite route page permission' using errcode = '42501';
  end if;
  v_target_tenant_id := case
    when app_private.is_platform_super() then coalesce(p_tenant_id, v_current_tenant_id)
    else v_current_tenant_id
  end;

  with filtered as materialized (
    select route_row as route_record
    from public.tms_favorite_route route_row
    where route_row.tenant_id = v_target_tenant_id
      and (p_customer_id is null or route_row.customer_id = p_customer_id)
      and (p_enabled is null or route_row.enabled = p_enabled)
      and (
        nullif(btrim(p_keyword), '') is null
        or route_row.route_name ilike '%' || btrim(p_keyword) || '%'
        or route_row.remark ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select filtered.route_record
    from filtered
    order by (filtered.route_record).enabled desc,
             (filtered.route_record).update_time desc nulls last,
             (filtered.route_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        (to_jsonb(paged.route_record) - 'tenant_id')
        || jsonb_build_object(
          'tenant', jsonb_build_object(
            'id', tenant_row.id,
            'tenant_code', tenant_row.tenant_code,
            'tenant_name', tenant_row.tenant_name
          ),
          'customer', app_private.tms_customer_option_to_secure_json(customer_row),
          'origin_address', app_private.tms_customer_address_to_secure_json(origin_row, null),
          'destination_address', app_private.tms_customer_address_to_secure_json(destination_row, null)
        )
      )
      from paged
      join public.sys_tenant tenant_row on tenant_row.id = (paged.route_record).tenant_id
      join public.tms_customer customer_row on customer_row.id = (paged.route_record).customer_id
      join public.tms_customer_address origin_row on origin_row.id = (paged.route_record).origin_address_id
      join public.tms_customer_address destination_row on destination_row.id = (paged.route_record).destination_address_id
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function app_private.set_tms_customer_creator_identity() from public, anon, authenticated;
revoke all on function app_private.can_access_business_menu(text) from public, anon, authenticated;
revoke all on function app_private.can_execute_business_action(text, text, uuid, boolean) from public, anon, authenticated;
revoke all on function app_private.tms_customer_to_secure_json(public.tms_customer, jsonb) from public, anon, authenticated;
revoke all on function app_private.tms_customer_option_to_secure_json(public.tms_customer) from public, anon, authenticated;
revoke all on function app_private.tms_customer_address_to_secure_json(public.tms_customer_address, jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_customer_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_customer_reference_scope(uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.assert_tms_customer_address_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_customer_address_reference_scope(uuid, uuid) from public, anon, authenticated;

revoke all on function public.tms_list_customers_secure(integer, integer, uuid, text, text, boolean, text, timestamptz, timestamptz, uuid[], text) from public, anon;
revoke all on function public.tms_list_customer_options_secure(uuid, boolean, uuid) from public, anon;
revoke all on function public.tms_list_customer_selector_secure(integer, integer, text, text) from public, anon;
revoke all on function public.tms_list_customer_addresses_secure(integer, integer, uuid, text, text, timestamptz, timestamptz, uuid) from public, anon;
revoke all on function public.tms_list_customer_address_options_secure(uuid, uuid, text) from public, anon;
revoke all on function public.tms_get_customer_default_address_secure(uuid, text) from public, anon;
revoke all on function public.tms_create_customer_secure(jsonb) from public, anon;
revoke all on function public.tms_update_customer_secure(uuid, jsonb) from public, anon;
revoke all on function public.tms_delete_customer_secure(uuid) from public, anon;
revoke all on function public.tms_delete_customers_secure(uuid[]) from public, anon;
revoke all on function public.tms_import_customers_secure(jsonb) from public, anon;
revoke all on function public.tms_create_customer_address_secure(jsonb) from public, anon;
revoke all on function public.tms_update_customer_address_secure(uuid, jsonb) from public, anon;
revoke all on function public.tms_delete_customer_address_secure(uuid) from public, anon;
revoke all on function public.tms_delete_customer_addresses_secure(uuid[]) from public, anon;
revoke all on function public.tms_list_favorite_routes_secure(integer, integer, uuid, uuid, boolean, text) from public, anon;

grant execute on function public.tms_list_customers_secure(integer, integer, uuid, text, text, boolean, text, timestamptz, timestamptz, uuid[], text) to authenticated;
grant execute on function public.tms_list_customer_options_secure(uuid, boolean, uuid) to authenticated;
grant execute on function public.tms_list_customer_selector_secure(integer, integer, text, text) to authenticated;
grant execute on function public.tms_list_customer_addresses_secure(integer, integer, uuid, text, text, timestamptz, timestamptz, uuid) to authenticated;
grant execute on function public.tms_list_customer_address_options_secure(uuid, uuid, text) to authenticated;
grant execute on function public.tms_get_customer_default_address_secure(uuid, text) to authenticated;
grant execute on function public.tms_create_customer_secure(jsonb) to authenticated;
grant execute on function public.tms_update_customer_secure(uuid, jsonb) to authenticated;
grant execute on function public.tms_delete_customer_secure(uuid) to authenticated;
grant execute on function public.tms_delete_customers_secure(uuid[]) to authenticated;
grant execute on function public.tms_import_customers_secure(jsonb) to authenticated;
grant execute on function public.tms_create_customer_address_secure(jsonb) to authenticated;
grant execute on function public.tms_update_customer_address_secure(uuid, jsonb) to authenticated;
grant execute on function public.tms_delete_customer_address_secure(uuid) to authenticated;
grant execute on function public.tms_delete_customer_addresses_secure(uuid[]) to authenticated;
grant execute on function public.tms_list_favorite_routes_secure(integer, integer, uuid, uuid, boolean, text) to authenticated;

-- Close direct data paths. Non-sensitive customer identity columns remain available
-- for existing foreign-key embeds; all sensitive values require the secure RPCs.
revoke all on table public.tms_customer from anon;
revoke all on table public.tms_customer_address from anon;
revoke all on table public.tms_customer from authenticated;
revoke all on table public.tms_customer_address from authenticated;

grant select (
  id, tenant_id, parent_unit_id, customer_code, customer_name, industry, customer_level,
  tags, region, enabled, contact_name, contact_department, contact_position, contact_email,
  contact_qq, invoice_title, bank_name, remark, create_by, create_time, update_by, update_time
) on public.tms_customer to authenticated;

;
