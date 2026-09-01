-- Tenant-scoped carrier and driver field authorization.
-- Sensitive values are only exposed through permission-aware RPCs; direct Data API
-- access remains available for non-sensitive relation columns only.

alter table public.tms_carrier
  add column if not exists created_by_user_id uuid;

alter table public.tms_driver
  add column if not exists created_by_user_id uuid;

update public.tms_carrier carrier_row
set created_by_user_id = creator.id
from public.sys_user creator
where carrier_row.created_by_user_id is null
  and creator.tenant_id = carrier_row.tenant_id
  and lower(creator.user_email) = lower(carrier_row.create_by);

update public.tms_driver driver_row
set created_by_user_id = creator.id
from public.sys_user creator
where driver_row.created_by_user_id is null
  and creator.tenant_id = driver_row.tenant_id
  and lower(creator.user_email) = lower(driver_row.create_by);

do $$
begin
  if exists (select 1 from public.tms_carrier where created_by_user_id is null) then
    raise exception 'Carrier creator identity backfill is incomplete';
  end if;
  if exists (select 1 from public.tms_driver where created_by_user_id is null) then
    raise exception 'Driver creator identity backfill is incomplete';
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tms_carrier_created_by_user_tenant_fkey'
      and conrelid = 'public.tms_carrier'::regclass
  ) then
    alter table public.tms_carrier
      add constraint tms_carrier_created_by_user_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user (id, tenant_id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'tms_driver_created_by_user_tenant_fkey'
      and conrelid = 'public.tms_driver'::regclass
  ) then
    alter table public.tms_driver
      add constraint tms_driver_created_by_user_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user (id, tenant_id)
      on delete restrict;
  end if;
end
$$;

alter table public.tms_carrier
  alter column created_by_user_id set not null;

alter table public.tms_driver
  alter column created_by_user_id set not null;

create index if not exists tms_carrier_tenant_creator_time_idx
  on public.tms_carrier (tenant_id, created_by_user_id, create_time desc);
create index if not exists tms_carrier_creator_tenant_idx
  on public.tms_carrier (created_by_user_id, tenant_id);
create index if not exists tms_driver_tenant_creator_time_idx
  on public.tms_driver (tenant_id, created_by_user_id, create_time desc);
create index if not exists tms_driver_creator_tenant_idx
  on public.tms_driver (created_by_user_id, tenant_id);
create index if not exists vehicle_archive_tenant_primary_driver_idx
  on public.vehicle_archive (tenant_id, primary_driver_id)
  where primary_driver_id is not null;
create index if not exists vehicle_archive_tenant_secondary_driver_idx
  on public.vehicle_archive (tenant_id, secondary_driver_id)
  where secondary_driver_id is not null;

comment on column public.tms_carrier.created_by_user_id is
  'Immutable application-user owner used by record-creator field permission overrides.';
comment on column public.tms_driver.created_by_user_id is
  'Immutable application-user owner used by record-creator field permission overrides.';

create or replace function app_private.set_tms_carrier_driver_creator_identity()
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
        and lower(user_row.user_email) = lower(new.create_by)
      limit 1;
    end if;

    if new.created_by_user_id is null then
      raise exception 'Authenticated carrier or driver creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Record creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists tms_carrier_creator_identity on public.tms_carrier;
create trigger tms_carrier_creator_identity
before insert or update of created_by_user_id on public.tms_carrier
for each row execute function app_private.set_tms_carrier_driver_creator_identity();

drop trigger if exists tms_driver_creator_identity on public.tms_driver;
create trigger tms_driver_creator_identity
before insert or update of created_by_user_id on public.tms_driver
for each row execute function app_private.set_tms_carrier_driver_creator_identity();

create or replace function app_private.refresh_tms_carrier_relation_counts(
  p_tenant_id uuid,
  p_carrier_id uuid
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update public.tms_carrier carrier_row
  set driver_count = (
        select count(*)::integer
        from public.tms_driver driver_row
        where driver_row.tenant_id = p_tenant_id
          and driver_row.carrier_id = p_carrier_id
      ),
      vehicle_count = (
        select count(*)::integer
        from public.vehicle_archive vehicle_row
        where vehicle_row.tenant_id = p_tenant_id
          and vehicle_row.carrier_id = p_carrier_id
      )
  where carrier_row.tenant_id = p_tenant_id
    and carrier_row.id = p_carrier_id;
$$;

create or replace function app_private.sync_tms_carrier_relation_counts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') and old.carrier_id is not null then
    perform app_private.refresh_tms_carrier_relation_counts(old.tenant_id, old.carrier_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE')
     and new.carrier_id is not null
     and (tg_op = 'INSERT' or (new.tenant_id, new.carrier_id) is distinct from (old.tenant_id, old.carrier_id)) then
    perform app_private.refresh_tms_carrier_relation_counts(new.tenant_id, new.carrier_id);
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists tms_driver_sync_carrier_counts on public.tms_driver;
create trigger tms_driver_sync_carrier_counts
after insert or update or delete on public.tms_driver
for each row execute function app_private.sync_tms_carrier_relation_counts();

drop trigger if exists vehicle_archive_sync_carrier_counts on public.vehicle_archive;
create trigger vehicle_archive_sync_carrier_counts
after insert or update or delete on public.vehicle_archive
for each row execute function app_private.sync_tms_carrier_relation_counts();

update public.tms_carrier carrier_row
set driver_count = (
      select count(*)::integer from public.tms_driver driver_row
      where driver_row.tenant_id = carrier_row.tenant_id
        and driver_row.carrier_id = carrier_row.id
    ),
    vehicle_count = (
      select count(*)::integer from public.vehicle_archive vehicle_row
      where vehicle_row.tenant_id = carrier_row.tenant_id
        and vehicle_row.carrier_id = carrier_row.id
    );

-- Extend the existing tenant catalog seeder without copying prior resource definitions.
alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_carrier_driver;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_carrier_driver(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.carrier', '承运商档案', 'TmsCarrier', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'addressDetail', '公司详细地址', 'hidden', 'address', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'taxNo', '税务识别信息', 'hidden', 'id_card', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'bankAccount', '银行账户信息', 'hidden', 'bank_account', true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'attachments', '资质与合同附件', 'hidden', 'none', true, 50, '624944977@qq.com', '624944977@qq.com')
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
    p_tenant_id, 'tms.driver', '司机档案', 'TmsDriver', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'contactPhone', '司机手机号码', 'hidden', 'phone', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'idCardNo', '身份证号码', 'hidden', 'id_card', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'homeAddress', '家庭住址', 'hidden', 'address', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'emergencyContact', '紧急联系人信息', 'hidden', 'phone', true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'identityDocuments', '身份证与驾驶证影像', 'hidden', 'none', true, 50, '624944977@qq.com', '624944977@qq.com')
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

-- Preserve current behavior only for roles that already own the exact master-data page.
insert into public.sys_role_field_permission (
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select
  role_row.tenant_id, role_row.id, resource_row.id, field_row.id, 'edit',
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role role_row
join public.sys_permission_resource resource_row
  on resource_row.tenant_id = role_row.tenant_id
 and resource_row.resource_key in ('tms.carrier', 'tms.driver')
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
where role_row.enabled is true
  and exists (
    select 1
    from public.sys_role_menu role_menu
    join public.sys_menu menu_row on menu_row.id = role_menu.menu_id
    where role_menu.tenant_id = role_row.tenant_id
      and role_menu.role_id = role_row.id
      and menu_row.name = resource_row.menu_name
      and menu_row.type is distinct from 'button'
  )
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.tms_carrier_to_secure_json(
  p_carrier public.tms_carrier,
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
    app_private.field_access_map('tms.carrier', p_carrier.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_carrier) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'contactPhone', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'contact_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{contact_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_carrier.contact_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'addressDetail', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'address_detail' - 'postal_code';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{address_detail}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_carrier.address_detail, 'address')
    ), 'null'::jsonb)) - 'postal_code';
  end if;

  v_level := coalesce(v_access->>'taxNo', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'tax_no' - 'tax_registration_no';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{tax_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_carrier.tax_no, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{tax_registration_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_carrier.tax_registration_no, 'id_card')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'bankAccount', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'bank_name' - 'bank_account_name' - 'bank_account';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{bank_account_name}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_carrier.bank_account_name, 'none')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{bank_account}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_carrier.bank_account, 'bank_account')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'attachments', 'hidden');
  if v_level in ('hidden', 'masked') then
    v_data := v_data - 'business_license_url' - 'contract_attachment_url';
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_carrier.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.tms_carrier_option_to_secure_json(
  p_carrier public.tms_carrier
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_secure jsonb := app_private.tms_carrier_to_secure_json(p_carrier, null);
begin
  return jsonb_strip_nulls(jsonb_build_object(
    'id', p_carrier.id,
    'carrier_code', p_carrier.carrier_code,
    'company_name', p_carrier.company_name,
    'enabled', p_carrier.enabled,
    'contact_name', p_carrier.contact_name,
    'contact_phone', v_secure->'contact_phone',
    'field_access', v_secure->'field_access',
    'is_record_owner', v_secure->'is_record_owner'
  ));
end;
$$;

create or replace function app_private.tms_driver_to_secure_json(
  p_driver public.tms_driver,
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
    app_private.field_access_map('tms.driver', p_driver.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_driver) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'contactPhone', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_driver.phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'idCardNo', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'id_card_no';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{id_card_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_driver.id_card_no, 'id_card')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'homeAddress', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'home_address';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{home_address}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_driver.home_address, 'address')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'emergencyContact', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'emergency_contact_name' - 'emergency_contact_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{emergency_contact_name}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_driver.emergency_contact_name, 'none')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{emergency_contact_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_driver.emergency_contact_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'identityDocuments', 'hidden');
  if v_level in ('hidden', 'masked') then
    v_data := v_data
      - 'id_card_front_url' - 'id_card_back_url'
      - 'driver_license_front_url' - 'driver_license_back_url';
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_driver.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.tms_driver_with_relations_to_secure_json(
  p_driver public.tms_driver
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_carrier jsonb;
  v_vehicles jsonb;
begin
  select app_private.tms_carrier_option_to_secure_json(carrier_row)
  into v_carrier
  from public.tms_carrier carrier_row
  where carrier_row.id = p_driver.carrier_id
    and carrier_row.tenant_id = p_driver.tenant_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', vehicle_row.id,
    'carrier_id', vehicle_row.carrier_id,
    'plate_no', vehicle_row.plate_no
  ) order by vehicle_row.plate_no, vehicle_row.id), '[]'::jsonb)
  into v_vehicles
  from public.vehicle_archive vehicle_row
  where vehicle_row.tenant_id = p_driver.tenant_id
    and vehicle_row.carrier_id = p_driver.carrier_id
    and (vehicle_row.primary_driver_id = p_driver.id or vehicle_row.secondary_driver_id = p_driver.id);

  return app_private.tms_driver_to_secure_json(p_driver, null)
    || jsonb_build_object('carrier', v_carrier, 'assigned_vehicles', v_vehicles);
end;
$$;

create or replace function app_private.tms_driver_option_to_secure_json(
  p_driver public.tms_driver
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_secure jsonb := app_private.tms_driver_to_secure_json(p_driver, null);
begin
  return jsonb_strip_nulls(jsonb_build_object(
    'id', p_driver.id,
    'carrier_id', p_driver.carrier_id,
    'driver_name', p_driver.driver_name,
    'phone', v_secure->'phone',
    'driver_type', p_driver.driver_type,
    'license_type', p_driver.license_type,
    'license_expire_date', p_driver.license_expire_date,
    'enabled', p_driver.enabled,
    'field_access', v_secure->'field_access',
    'is_record_owner', v_secure->'is_record_owner'
  ));
end;
$$;

create or replace function public.tms_list_carriers_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_record_id uuid default null,
  p_carrier_type text default null,
  p_enabled boolean default null,
  p_signed_contract boolean default null,
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
  v_permission text := case when p_purpose = 'export' then 'TmsCarrier:Export' else 'TmsCarrier:View' end;
  v_limit integer;
  v_base_access jsonb;
  v_can_search_phone boolean;
  v_result jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid carrier read purpose';
  end if;
  if not app_private.can_execute_business_action('TmsCarrier', v_permission, null, false) then
    raise exception 'Missing carrier read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.carrier', null);
  v_can_search_phone := coalesce(v_base_access->>'contactPhone', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select carrier_row as carrier_record
    from public.tms_carrier carrier_row
    where (app_private.is_platform_super() or carrier_row.tenant_id = v_tenant_id)
      and (p_record_id is null or carrier_row.id = p_record_id)
      and (p_ids is null or carrier_row.id = any(p_ids))
      and (p_carrier_type is null or carrier_row.carrier_type = p_carrier_type)
      and (p_enabled is null or carrier_row.enabled = p_enabled)
      and (p_signed_contract is null or carrier_row.signed_contract = p_signed_contract)
      and (p_create_time_from is null or carrier_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or carrier_row.create_time <= p_create_time_to)
      and (
        nullif(btrim(p_keyword), '') is null
        or carrier_row.company_name ilike '%' || btrim(p_keyword) || '%'
        or carrier_row.carrier_code ilike '%' || btrim(p_keyword) || '%'
        or carrier_row.contact_name ilike '%' || btrim(p_keyword) || '%'
        or (v_can_search_phone and carrier_row.contact_phone ilike '%' || btrim(p_keyword) || '%')
      )
  ), paged as (
    select filtered.carrier_record
    from filtered
    order by (filtered.carrier_record).create_time desc, (filtered.carrier_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_carrier_to_secure_json(paged.carrier_record, null)
        order by (paged.carrier_record).create_time desc, (paged.carrier_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.tms_get_carrier_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_carrier public.tms_carrier%rowtype;
begin
  if not app_private.can_execute_business_action('TmsCarrier', 'TmsCarrier:View', null, false) then
    raise exception 'Missing carrier view permission' using errcode = '42501';
  end if;
  select * into v_carrier
  from public.tms_carrier carrier_row
  where carrier_row.id = p_id
    and (app_private.is_platform_super() or carrier_row.tenant_id = app_private.current_user_tenant_id());
  if not found then return null; end if;
  return app_private.tms_carrier_to_secure_json(v_carrier, null);
end;
$$;

create or replace function public.tms_list_carrier_options_secure(
  p_exclude_id uuid default null,
  p_include_disabled boolean default false,
  p_keyword text default null,
  p_ids uuid[] default null,
  p_max_rows integer default 200
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
  v_can_search_phone boolean;
begin
  if (select auth.uid()) is null or v_tenant_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  v_access := app_private.field_access_map('tms.carrier', null);
  v_can_search_phone := coalesce(v_access->>'contactPhone', 'hidden') in ('read', 'edit');

  return coalesce((
    select jsonb_agg(
      app_private.tms_carrier_option_to_secure_json(carrier_row)
      order by carrier_row.company_name, carrier_row.id
    )
    from (
      select carrier_record.*
      from public.tms_carrier carrier_record
      where (app_private.is_platform_super() or carrier_record.tenant_id = v_tenant_id)
        and (p_include_disabled or carrier_record.enabled)
        and (p_exclude_id is null or carrier_record.id <> p_exclude_id)
        and (p_ids is null or carrier_record.id = any(p_ids))
        and (
          nullif(btrim(p_keyword), '') is null
          or carrier_record.company_name ilike '%' || btrim(p_keyword) || '%'
          or carrier_record.carrier_code ilike '%' || btrim(p_keyword) || '%'
          or carrier_record.contact_name ilike '%' || btrim(p_keyword) || '%'
          or (v_can_search_phone and carrier_record.contact_phone ilike '%' || btrim(p_keyword) || '%')
        )
      order by carrier_record.company_name, carrier_record.id
      limit least(greatest(coalesce(p_max_rows, 200), 1), 1000)
    ) carrier_row
  ), '[]'::jsonb);
end;
$$;

create or replace function public.tms_list_drivers_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_record_id uuid default null,
  p_carrier_id uuid default null,
  p_driver_type text default null,
  p_gender text default null,
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
  v_permission text := case when p_purpose = 'export' then 'TmsDriver:Export' else 'TmsDriver:View' end;
  v_limit integer;
  v_base_access jsonb;
  v_can_search_phone boolean;
  v_can_search_id boolean;
  v_can_search_address boolean;
  v_result jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid driver read purpose';
  end if;
  if not app_private.can_execute_business_action('TmsDriver', v_permission, null, false) then
    raise exception 'Missing driver read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.driver', null);
  v_can_search_phone := coalesce(v_base_access->>'contactPhone', 'hidden') in ('read', 'edit');
  v_can_search_id := coalesce(v_base_access->>'idCardNo', 'hidden') in ('read', 'edit');
  v_can_search_address := coalesce(v_base_access->>'homeAddress', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select driver_row as driver_record
    from public.tms_driver driver_row
    where (app_private.is_platform_super() or driver_row.tenant_id = v_tenant_id)
      and (p_record_id is null or driver_row.id = p_record_id)
      and (p_ids is null or driver_row.id = any(p_ids))
      and (p_carrier_id is null or driver_row.carrier_id = p_carrier_id)
      and (p_driver_type is null or driver_row.driver_type = p_driver_type)
      and (p_gender is null or driver_row.gender = p_gender)
      and (p_enabled is null or driver_row.enabled = p_enabled)
      and (p_create_time_from is null or driver_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or driver_row.create_time <= p_create_time_to)
      and (
        nullif(btrim(p_keyword), '') is null
        or driver_row.driver_name ilike '%' || btrim(p_keyword) || '%'
        or driver_row.license_type ilike '%' || btrim(p_keyword) || '%'
        or (v_can_search_phone and driver_row.phone ilike '%' || btrim(p_keyword) || '%')
        or (v_can_search_id and driver_row.id_card_no ilike '%' || btrim(p_keyword) || '%')
        or (v_can_search_address and driver_row.home_address ilike '%' || btrim(p_keyword) || '%')
      )
  ), paged as (
    select filtered.driver_record
    from filtered
    order by (filtered.driver_record).create_time desc, (filtered.driver_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_driver_with_relations_to_secure_json(paged.driver_record)
        order by (paged.driver_record).create_time desc, (paged.driver_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.tms_get_driver_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_driver public.tms_driver%rowtype;
begin
  if not app_private.can_execute_business_action('TmsDriver', 'TmsDriver:View', null, false) then
    raise exception 'Missing driver view permission' using errcode = '42501';
  end if;
  select * into v_driver
  from public.tms_driver driver_row
  where driver_row.id = p_id
    and (app_private.is_platform_super() or driver_row.tenant_id = app_private.current_user_tenant_id());
  if not found then return null; end if;
  return app_private.tms_driver_with_relations_to_secure_json(v_driver);
end;
$$;

create or replace function public.tms_list_driver_options_secure(
  p_carrier_id uuid default null,
  p_driver_name text default null,
  p_driver_type text default null,
  p_ids uuid[] default null,
  p_include_disabled boolean default false,
  p_max_rows integer default 200
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
  v_can_search_phone boolean;
begin
  if (select auth.uid()) is null or v_tenant_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  v_access := app_private.field_access_map('tms.driver', null);
  v_can_search_phone := coalesce(v_access->>'contactPhone', 'hidden') in ('read', 'edit');

  return coalesce((
    select jsonb_agg(
      app_private.tms_driver_option_to_secure_json(driver_row)
      order by driver_row.driver_name, driver_row.id
    )
    from (
      select driver_record.*
      from public.tms_driver driver_record
      where (app_private.is_platform_super() or driver_record.tenant_id = v_tenant_id)
        and (p_include_disabled or driver_record.enabled)
        and (p_carrier_id is null or driver_record.carrier_id = p_carrier_id)
        and (p_driver_type is null or driver_record.driver_type = p_driver_type)
        and (p_ids is null or driver_record.id = any(p_ids))
        and (
          nullif(btrim(p_driver_name), '') is null
          or driver_record.driver_name ilike '%' || btrim(p_driver_name) || '%'
          or (v_can_search_phone and driver_record.phone ilike '%' || btrim(p_driver_name) || '%')
        )
      order by driver_record.driver_name, driver_record.id
      limit least(greatest(coalesce(p_max_rows, 200), 1), 1000)
    ) driver_row
  ), '[]'::jsonb);
end;
$$;

create or replace function public.tms_list_drivers_by_carrier_secure(p_carrier_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('TmsCarrier', 'TmsCarrier:View', null, false) then
    raise exception 'Missing carrier view permission' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(
      app_private.tms_driver_with_relations_to_secure_json(driver_row)
      order by driver_row.create_time desc, driver_row.id
    )
    from (
      select driver_record.*
      from public.tms_driver driver_record
      where driver_record.carrier_id = p_carrier_id
        and (app_private.is_platform_super() or driver_record.tenant_id = v_tenant_id)
      order by driver_record.create_time desc, driver_record.id
      limit 1000
    ) driver_row
  ), '[]'::jsonb);
end;
$$;

create or replace function app_private.assert_tms_carrier_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Carrier payload must be a JSON object';
  end if;
  select array_agg(key order by key) into v_invalid_keys
  from jsonb_object_keys(p_payload) key
  where key <> all(array[
    'parent_unit_id', 'carrier_code', 'company_name', 'carrier_type',
    'business_license_no', 'tax_registration_no', 'legal_representative', 'region',
    'address_detail', 'postal_code', 'enabled', 'business_license_url', 'contact_name',
    'contact_phone', 'contact_department', 'contact_position', 'contact_email',
    'contact_qq', 'invoice_title', 'tax_no', 'bank_name', 'bank_account_name',
    'bank_account', 'signed_contract', 'contract_attachment_url', 'remark'
  ]::text[]);
  if v_invalid_keys is not null then
    raise exception 'Carrier payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function app_private.assert_tms_carrier_reference_scope(
  p_tenant_id uuid,
  p_carrier_id uuid,
  p_parent_unit_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_parent_unit_id is not null and p_parent_unit_id = p_carrier_id then
    raise exception 'Carrier cannot be its own parent';
  end if;
  if p_parent_unit_id is not null and not exists (
    select 1 from public.tms_carrier parent_row
    where parent_row.id = p_parent_unit_id
      and parent_row.tenant_id = p_tenant_id
  ) then
    raise exception 'Parent carrier is outside the current tenant';
  end if;
end;
$$;

create or replace function public.tms_create_carrier_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_carrier%rowtype;
  v_id uuid;
begin
  if not app_private.can_execute_business_action('TmsCarrier', 'TmsCarrier:Add', null, false) then
    raise exception 'Missing carrier create permission' using errcode = '42501';
  end if;
  perform app_private.assert_tms_carrier_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.tms_carrier, p_payload);
  perform app_private.assert_tms_carrier_reference_scope(v_tenant_id, null, v_input.parent_unit_id);

  insert into public.tms_carrier (
    parent_unit_id, carrier_code, company_name, carrier_type, business_license_no,
    tax_registration_no, legal_representative, region, address_detail, postal_code,
    enabled, business_license_url, contact_name, contact_phone, contact_department,
    contact_position, contact_email, contact_qq, invoice_title, tax_no, bank_name,
    bank_account_name, bank_account, signed_contract, contract_attachment_url, remark,
    tenant_id
  ) values (
    v_input.parent_unit_id, nullif(v_input.carrier_code, ''), v_input.company_name,
    v_input.carrier_type, v_input.business_license_no, v_input.tax_registration_no,
    v_input.legal_representative, v_input.region, v_input.address_detail,
    v_input.postal_code, coalesce(v_input.enabled, true), v_input.business_license_url,
    v_input.contact_name, v_input.contact_phone, v_input.contact_department,
    v_input.contact_position, v_input.contact_email, v_input.contact_qq,
    v_input.invoice_title, v_input.tax_no, v_input.bank_name, v_input.bank_account_name,
    v_input.bank_account, coalesce(v_input.signed_contract, false),
    v_input.contract_attachment_url, v_input.remark, v_tenant_id
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.tms_update_carrier_secure(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.tms_carrier%rowtype;
  v_candidate public.tms_carrier%rowtype;
  v_updated public.tms_carrier%rowtype;
begin
  select * into v_old
  from public.tms_carrier carrier_row
  where carrier_row.id = p_id
    and (app_private.is_platform_super() or carrier_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Carrier not found or access denied'; end if;
  if not app_private.can_execute_business_action(
    'TmsCarrier', 'TmsCarrier:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing carrier edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_carrier_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  perform app_private.assert_tms_carrier_reference_scope(
    v_old.tenant_id, v_old.id, v_candidate.parent_unit_id
  );

  if v_candidate.contact_phone is distinct from v_old.contact_phone
     and app_private.resolve_field_access(
       'tms.carrier', 'contactPhone', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for carrier contact phone' using errcode = '42501';
  end if;
  if (v_candidate.region, v_candidate.address_detail, v_candidate.postal_code) is distinct from
     (v_old.region, v_old.address_detail, v_old.postal_code)
     and app_private.resolve_field_access(
       'tms.carrier', 'addressDetail', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for carrier address' using errcode = '42501';
  end if;
  if (v_candidate.tax_no, v_candidate.tax_registration_no) is distinct from
     (v_old.tax_no, v_old.tax_registration_no)
     and app_private.resolve_field_access(
       'tms.carrier', 'taxNo', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for carrier tax information' using errcode = '42501';
  end if;
  if (v_candidate.bank_name, v_candidate.bank_account_name, v_candidate.bank_account)
     is distinct from (v_old.bank_name, v_old.bank_account_name, v_old.bank_account)
     and app_private.resolve_field_access(
       'tms.carrier', 'bankAccount', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for carrier bank account' using errcode = '42501';
  end if;
  if (v_candidate.business_license_url, v_candidate.contract_attachment_url)
     is distinct from (v_old.business_license_url, v_old.contract_attachment_url)
     and app_private.resolve_field_access(
       'tms.carrier', 'attachments', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for carrier attachments' using errcode = '42501';
  end if;

  update public.tms_carrier set
    parent_unit_id = v_candidate.parent_unit_id,
    carrier_code = v_candidate.carrier_code,
    company_name = v_candidate.company_name,
    carrier_type = v_candidate.carrier_type,
    business_license_no = v_candidate.business_license_no,
    tax_registration_no = v_candidate.tax_registration_no,
    legal_representative = v_candidate.legal_representative,
    region = v_candidate.region,
    address_detail = v_candidate.address_detail,
    postal_code = v_candidate.postal_code,
    enabled = v_candidate.enabled,
    business_license_url = v_candidate.business_license_url,
    contact_name = v_candidate.contact_name,
    contact_phone = v_candidate.contact_phone,
    contact_department = v_candidate.contact_department,
    contact_position = v_candidate.contact_position,
    contact_email = v_candidate.contact_email,
    contact_qq = v_candidate.contact_qq,
    invoice_title = v_candidate.invoice_title,
    tax_no = v_candidate.tax_no,
    bank_name = v_candidate.bank_name,
    bank_account_name = v_candidate.bank_account_name,
    bank_account = v_candidate.bank_account,
    signed_contract = v_candidate.signed_contract,
    contract_attachment_url = v_candidate.contract_attachment_url,
    remark = v_candidate.remark
  where id = v_old.id
  returning * into v_updated;
  return app_private.tms_carrier_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.tms_delete_carrier_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_carrier public.tms_carrier%rowtype;
begin
  select * into v_carrier
  from public.tms_carrier carrier_row
  where carrier_row.id = p_id
    and (app_private.is_platform_super() or carrier_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then return false; end if;
  if not app_private.can_execute_business_action(
    'TmsCarrier', 'TmsCarrier:Delete', v_carrier.created_by_user_id, true
  ) then
    raise exception 'Missing carrier delete permission' using errcode = '42501';
  end if;
  delete from public.tms_carrier where id = v_carrier.id;
  return true;
end;
$$;

create or replace function public.tms_delete_carriers_secure(p_ids uuid[])
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
    raise exception 'A maximum of 500 carriers can be deleted at once';
  end if;
  foreach v_id in array coalesce(p_ids, array[]::uuid[]) loop
    if public.tms_delete_carrier_secure(v_id) then
      v_deleted := v_deleted + 1;
    end if;
  end loop;
  return v_deleted;
end;
$$;

create or replace function public.tms_import_carriers_secure(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item jsonb;
  v_existing public.tms_carrier%rowtype;
  v_count integer := 0;
begin
  if not app_private.can_execute_business_action('TmsCarrier', 'TmsCarrier:Import', null, false) then
    raise exception 'Missing carrier import permission' using errcode = '42501';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Carrier import payload must be a JSON array';
  end if;
  if jsonb_array_length(p_rows) > 1000 then
    raise exception 'A maximum of 1000 carriers can be imported at once';
  end if;

  for v_item in select value from jsonb_array_elements(p_rows) loop
    v_existing := null;
    if nullif(v_item->>'carrier_code', '') is not null then
      select * into v_existing
      from public.tms_carrier carrier_row
      where carrier_row.tenant_id = app_private.current_user_tenant_id()
        and carrier_row.carrier_code = v_item->>'carrier_code'
      for update;
    end if;
    if v_existing.id is null then
      perform public.tms_create_carrier_secure(v_item);
    else
      perform public.tms_update_carrier_secure(v_existing.id, v_item - 'carrier_code');
    end if;
    v_count := v_count + 1;
  end loop;
  return jsonb_build_object('count', v_count);
end;
$$;

create or replace function app_private.assert_tms_driver_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Driver payload must be a JSON object';
  end if;
  select array_agg(key order by key) into v_invalid_keys
  from jsonb_object_keys(p_payload) key
  where key <> all(array[
    'carrier_id', 'driver_name', 'phone', 'gender', 'id_card_no', 'license_type',
    'driver_type', 'license_expire_date', 'home_address', 'emergency_contact_name',
    'emergency_contact_phone', 'enabled', 'id_card_front_url', 'id_card_back_url',
    'driver_license_front_url', 'driver_license_back_url', 'remark'
  ]::text[]);
  if v_invalid_keys is not null then
    raise exception 'Driver payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function app_private.assert_tms_driver_carrier_scope(
  p_tenant_id uuid,
  p_carrier_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_carrier_id is null or not exists (
    select 1 from public.tms_carrier carrier_row
    where carrier_row.id = p_carrier_id
      and carrier_row.tenant_id = p_tenant_id
  ) then
    raise exception 'Driver carrier is outside the current tenant';
  end if;
end;
$$;

create or replace function public.tms_create_driver_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_driver%rowtype;
  v_id uuid;
begin
  if not app_private.can_execute_business_action('TmsDriver', 'TmsDriver:Add', null, false) then
    raise exception 'Missing driver create permission' using errcode = '42501';
  end if;
  perform app_private.assert_tms_driver_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.tms_driver, p_payload);
  perform app_private.assert_tms_driver_carrier_scope(v_tenant_id, v_input.carrier_id);

  insert into public.tms_driver (
    carrier_id, driver_name, phone, gender, id_card_no, license_type, driver_type,
    license_expire_date, home_address, emergency_contact_name, emergency_contact_phone,
    enabled, id_card_front_url, id_card_back_url, driver_license_front_url,
    driver_license_back_url, remark, tenant_id
  ) values (
    v_input.carrier_id, v_input.driver_name, v_input.phone, v_input.gender,
    v_input.id_card_no, v_input.license_type, coalesce(v_input.driver_type, 'primary'),
    v_input.license_expire_date, v_input.home_address, v_input.emergency_contact_name,
    v_input.emergency_contact_phone, coalesce(v_input.enabled, true),
    v_input.id_card_front_url, v_input.id_card_back_url, v_input.driver_license_front_url,
    v_input.driver_license_back_url, v_input.remark, v_tenant_id
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.tms_update_driver_secure(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.tms_driver%rowtype;
  v_candidate public.tms_driver%rowtype;
  v_updated public.tms_driver%rowtype;
begin
  select * into v_old
  from public.tms_driver driver_row
  where driver_row.id = p_id
    and (app_private.is_platform_super() or driver_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Driver not found or access denied'; end if;
  if not app_private.can_execute_business_action(
    'TmsDriver', 'TmsDriver:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing driver edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_driver_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  perform app_private.assert_tms_driver_carrier_scope(v_old.tenant_id, v_candidate.carrier_id);

  if v_candidate.phone is distinct from v_old.phone
     and app_private.resolve_field_access(
       'tms.driver', 'contactPhone', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver phone' using errcode = '42501';
  end if;
  if v_candidate.id_card_no is distinct from v_old.id_card_no
     and app_private.resolve_field_access(
       'tms.driver', 'idCardNo', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver identity number' using errcode = '42501';
  end if;
  if v_candidate.home_address is distinct from v_old.home_address
     and app_private.resolve_field_access(
       'tms.driver', 'homeAddress', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver home address' using errcode = '42501';
  end if;
  if (v_candidate.emergency_contact_name, v_candidate.emergency_contact_phone)
     is distinct from (v_old.emergency_contact_name, v_old.emergency_contact_phone)
     and app_private.resolve_field_access(
       'tms.driver', 'emergencyContact', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver emergency contact' using errcode = '42501';
  end if;
  if (v_candidate.id_card_front_url, v_candidate.id_card_back_url,
      v_candidate.driver_license_front_url, v_candidate.driver_license_back_url)
     is distinct from (v_old.id_card_front_url, v_old.id_card_back_url,
      v_old.driver_license_front_url, v_old.driver_license_back_url)
     and app_private.resolve_field_access(
       'tms.driver', 'identityDocuments', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for driver identity documents' using errcode = '42501';
  end if;

  update public.tms_driver set
    carrier_id = v_candidate.carrier_id,
    driver_name = v_candidate.driver_name,
    phone = v_candidate.phone,
    gender = v_candidate.gender,
    id_card_no = v_candidate.id_card_no,
    license_type = v_candidate.license_type,
    driver_type = v_candidate.driver_type,
    license_expire_date = v_candidate.license_expire_date,
    home_address = v_candidate.home_address,
    emergency_contact_name = v_candidate.emergency_contact_name,
    emergency_contact_phone = v_candidate.emergency_contact_phone,
    enabled = v_candidate.enabled,
    id_card_front_url = v_candidate.id_card_front_url,
    id_card_back_url = v_candidate.id_card_back_url,
    driver_license_front_url = v_candidate.driver_license_front_url,
    driver_license_back_url = v_candidate.driver_license_back_url,
    remark = v_candidate.remark
  where id = v_old.id
  returning * into v_updated;
  return app_private.tms_driver_with_relations_to_secure_json(v_updated);
end;
$$;

create or replace function public.tms_delete_driver_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_driver public.tms_driver%rowtype;
begin
  select * into v_driver
  from public.tms_driver driver_row
  where driver_row.id = p_id
    and (app_private.is_platform_super() or driver_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then return false; end if;
  if not app_private.can_execute_business_action(
    'TmsDriver', 'TmsDriver:Delete', v_driver.created_by_user_id, true
  ) then
    raise exception 'Missing driver delete permission' using errcode = '42501';
  end if;
  delete from public.tms_driver where id = v_driver.id;
  return true;
end;
$$;

create or replace function public.tms_delete_drivers_secure(p_ids uuid[])
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
    raise exception 'A maximum of 500 drivers can be deleted at once';
  end if;
  foreach v_id in array coalesce(p_ids, array[]::uuid[]) loop
    if public.tms_delete_driver_secure(v_id) then
      v_deleted := v_deleted + 1;
    end if;
  end loop;
  return v_deleted;
end;
$$;

revoke all on function app_private.set_tms_carrier_driver_creator_identity() from public, anon, authenticated;
revoke all on function app_private.refresh_tms_carrier_relation_counts(uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.sync_tms_carrier_relation_counts() from public, anon, authenticated;
revoke all on function app_private.seed_field_permission_catalog_before_carrier_driver(uuid) from public, anon, authenticated;
revoke all on function app_private.seed_field_permission_catalog(uuid) from public, anon, authenticated;
revoke all on function app_private.tms_carrier_to_secure_json(public.tms_carrier, jsonb) from public, anon, authenticated;
revoke all on function app_private.tms_carrier_option_to_secure_json(public.tms_carrier) from public, anon, authenticated;
revoke all on function app_private.tms_driver_to_secure_json(public.tms_driver, jsonb) from public, anon, authenticated;
revoke all on function app_private.tms_driver_with_relations_to_secure_json(public.tms_driver) from public, anon, authenticated;
revoke all on function app_private.tms_driver_option_to_secure_json(public.tms_driver) from public, anon, authenticated;
revoke all on function app_private.assert_tms_carrier_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_carrier_reference_scope(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function app_private.assert_tms_driver_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_driver_carrier_scope(uuid, uuid) from public, anon, authenticated;

revoke all on function public.tms_list_carriers_secure(integer, integer, uuid, text, boolean, boolean, text, timestamptz, timestamptz, uuid[], text) from public, anon, authenticated;
revoke all on function public.tms_get_carrier_secure(uuid) from public, anon, authenticated;
revoke all on function public.tms_list_carrier_options_secure(uuid, boolean, text, uuid[], integer) from public, anon, authenticated;
revoke all on function public.tms_list_drivers_secure(integer, integer, uuid, uuid, text, text, boolean, text, timestamptz, timestamptz, uuid[], text) from public, anon, authenticated;
revoke all on function public.tms_get_driver_secure(uuid) from public, anon, authenticated;
revoke all on function public.tms_list_driver_options_secure(uuid, text, text, uuid[], boolean, integer) from public, anon, authenticated;
revoke all on function public.tms_list_drivers_by_carrier_secure(uuid) from public, anon, authenticated;
revoke all on function public.tms_create_carrier_secure(jsonb) from public, anon, authenticated;
revoke all on function public.tms_update_carrier_secure(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.tms_delete_carrier_secure(uuid) from public, anon, authenticated;
revoke all on function public.tms_delete_carriers_secure(uuid[]) from public, anon, authenticated;
revoke all on function public.tms_import_carriers_secure(jsonb) from public, anon, authenticated;
revoke all on function public.tms_create_driver_secure(jsonb) from public, anon, authenticated;
revoke all on function public.tms_update_driver_secure(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.tms_delete_driver_secure(uuid) from public, anon, authenticated;
revoke all on function public.tms_delete_drivers_secure(uuid[]) from public, anon, authenticated;

grant execute on function public.tms_list_carriers_secure(integer, integer, uuid, text, boolean, boolean, text, timestamptz, timestamptz, uuid[], text) to authenticated;
grant execute on function public.tms_get_carrier_secure(uuid) to authenticated;
grant execute on function public.tms_list_carrier_options_secure(uuid, boolean, text, uuid[], integer) to authenticated;
grant execute on function public.tms_list_drivers_secure(integer, integer, uuid, uuid, text, text, boolean, text, timestamptz, timestamptz, uuid[], text) to authenticated;
grant execute on function public.tms_get_driver_secure(uuid) to authenticated;
grant execute on function public.tms_list_driver_options_secure(uuid, text, text, uuid[], boolean, integer) to authenticated;
grant execute on function public.tms_list_drivers_by_carrier_secure(uuid) to authenticated;
grant execute on function public.tms_create_carrier_secure(jsonb) to authenticated;
grant execute on function public.tms_update_carrier_secure(uuid, jsonb) to authenticated;
grant execute on function public.tms_delete_carrier_secure(uuid) to authenticated;
grant execute on function public.tms_delete_carriers_secure(uuid[]) to authenticated;
grant execute on function public.tms_import_carriers_secure(jsonb) to authenticated;
grant execute on function public.tms_create_driver_secure(jsonb) to authenticated;
grant execute on function public.tms_update_driver_secure(uuid, jsonb) to authenticated;
grant execute on function public.tms_delete_driver_secure(uuid) to authenticated;
grant execute on function public.tms_delete_drivers_secure(uuid[]) to authenticated;

-- Close direct sensitive and write paths while preserving safe foreign-key embeds.
revoke all on table public.tms_carrier from anon;
revoke all on table public.tms_driver from anon;
revoke all on table public.tms_carrier from authenticated;
revoke all on table public.tms_driver from authenticated;

grant select (
  id, tenant_id, parent_unit_id, carrier_code, company_name, carrier_type,
  business_license_no, legal_representative, region, enabled, driver_count,
  vehicle_count, contact_name, contact_department, contact_position, contact_email,
  contact_qq, invoice_title, signed_contract, remark, create_by, create_time,
  update_by, update_time
) on public.tms_carrier to authenticated;

grant select (
  id, tenant_id, carrier_id, driver_name, gender, license_type, driver_type,
  license_expire_date, enabled, remark, create_by, create_time, update_by, update_time
) on public.tms_driver to authenticated;

comment on function public.tms_list_carriers_secure(integer, integer, uuid, text, boolean, boolean, text, timestamptz, timestamptz, uuid[], text) is
  'Tenant-scoped carrier list/export with per-record field shaping and creator override.';
comment on function public.tms_list_drivers_secure(integer, integer, uuid, uuid, text, text, boolean, text, timestamptz, timestamptz, uuid[], text) is
  'Tenant-scoped driver list/export with per-record field shaping and creator override.';

;
