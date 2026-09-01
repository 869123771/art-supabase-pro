alter table public.vehicle_part_usage
  add column if not exists created_by_user_id uuid;

update public.vehicle_part_usage usage_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = usage_row.tenant_id
    and lower(user_row.user_email) = lower(usage_row.create_by)
    and user_row.deleted_at is null
  order by user_row.create_time, user_row.id
  limit 1
)
where usage_row.created_by_user_id is null;

do $$
begin
  if exists (select 1 from public.vehicle_part_usage where created_by_user_id is null) then
    raise exception 'Vehicle part usage creator backfill is incomplete';
  end if;
end;
$$;

alter table public.vehicle_part_usage alter column created_by_user_id set not null;
alter table public.vehicle_part_usage
  drop constraint if exists vehicle_part_usage_creator_tenant_fk;
alter table public.vehicle_part_usage
  add constraint vehicle_part_usage_creator_tenant_fk
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on update restrict on delete restrict;

create index if not exists vehicle_part_usage_creator_tenant_idx
  on public.vehicle_part_usage(created_by_user_id, tenant_id);
create index if not exists vehicle_part_usage_tenant_time_idx
  on public.vehicle_part_usage(tenant_id, create_time desc, id);

create or replace function app_private.set_vehicle_part_usage_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
  v_current_user_tenant_id uuid;
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null then
      select user_row.tenant_id into v_current_user_tenant_id
      from public.sys_user user_row where user_row.id = v_current_user_id;
    end if;
    if v_current_user_id is not null and v_current_user_tenant_id = new.tenant_id then
      new.created_by_user_id := v_current_user_id;
    elsif new.created_by_user_id is null and nullif(btrim(new.create_by), '') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
        and user_row.deleted_at is null
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null or not exists (
      select 1 from public.sys_user user_row
      where user_row.id = new.created_by_user_id and user_row.tenant_id = new.tenant_id
    ) then
      raise exception 'Vehicle part usage creator is missing or outside the record tenant'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Vehicle part usage creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists vehicle_part_usage_creator_identity on public.vehicle_part_usage;
create trigger vehicle_part_usage_creator_identity
before insert or update on public.vehicle_part_usage
for each row execute function app_private.set_vehicle_part_usage_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
rename to seed_field_permission_catalog_before_vms_vehicle_part_usage;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_vms_vehicle_part_usage(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'vms.vehicle_part_usage', '车辆配件使用记录',
    'VehiclePartsManage', 'created_by_user_id',
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

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sensitive, enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'supplierDetails', '供应商与联系人',
      'hidden', 'none', true, true, true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'traceabilityTag', 'RFID 追溯标签',
      'hidden', 'none', true, true, true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'lifecycleLimits', '启用、质保与寿命数据',
      'hidden', 'none', true, true, true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'dispositionNotes', '报废原因与备注',
      'hidden', 'none', true, true, true, 40, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sensitive = true,
        enabled = true,
        sort = excluded.sort,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id, role_menu.role_id, resource_row.id, field_row.id,
  'edit', '624944977@qq.com', '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu' and menu_row.name = 'VehiclePartsManage'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'vms.vehicle_part_usage'
  and resource_row.enabled and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_access_vms_vehicle_part_usage_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_private.is_platform_super()
    or exists (
      select 1 from public.sys_menu menu_row
      where menu_row.type = 'menu'
        and menu_row.name in (
          'VehiclePartsManage', 'VehiclePartUsageDetail',
          'VehicleQuery', 'VehicleQueryDetail'
        )
        and app_private.can_access_business_menu(menu_row.name)
    );
$$;

create or replace function app_private.vehicle_part_usage_to_secure_json(
  p_usage public.vehicle_part_usage,
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
    app_private.field_access_map('vms.vehicle_part_usage', p_usage.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_usage) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'supplierDetails', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'supplier_id' - 'supplier_name' - 'supplier_contact';
  elsif v_level = 'masked' then
    v_data := v_data - 'supplier_id';
    v_data := jsonb_set(v_data, '{supplier_name}', '"***"'::jsonb);
    v_data := jsonb_set(v_data, '{supplier_contact}', '"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'traceabilityTag', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'rfid_tag';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{rfid_tag}', '"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'lifecycleLimits', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data
      - 'enable_mode' - 'enable_date'
      - 'warranty_mode' - 'warranty_mileage' - 'warranty_duration'
      - 'service_mileage_enabled' - 'service_mileage'
      - 'service_years_enabled' - 'service_years' - 'used_mileage';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{enable_date}', 'null'::jsonb);
    v_data := jsonb_set(v_data, '{warranty_mileage}', 'null'::jsonb);
    v_data := jsonb_set(v_data, '{warranty_duration}', 'null'::jsonb);
    v_data := jsonb_set(v_data, '{service_mileage}', 'null'::jsonb);
    v_data := jsonb_set(v_data, '{service_years}', 'null'::jsonb);
    v_data := jsonb_set(v_data, '{used_mileage}', 'null'::jsonb);
    v_data := v_data || jsonb_build_object('lifecycle_limits_masked', true);
  end if;

  v_level := coalesce(v_access->>'dispositionNotes', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'scrap_reason' - 'remark';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{scrap_reason}', '"***"'::jsonb);
    v_data := jsonb_set(v_data, '{remark}', '"***"'::jsonb);
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_usage.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.vms_list_vehicle_part_usages_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_vehicle_id uuid default null,
  p_company_name text default null,
  p_plate_no text default null,
  p_part_type text default null,
  p_part_name text default null,
  p_category_id uuid default null,
  p_rfid_tag text default null,
  p_status text default null,
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
  v_limit integer;
  v_result jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid vehicle part usage read purpose';
  end if;
  if p_purpose = 'export' then
    if not exists (
      select 1 from public.sys_menu menu_row
      where menu_row.type = 'button'
        and menu_row.name = 'VehiclePartUsage:Export'
        and (menu_row.meta->>'is_enable') is distinct from 'false'
    ) or not app_private.can_execute_business_action(
      'VehiclePartsManage', 'VehiclePartUsage:Export', null, false
    ) then
      raise exception 'Missing vehicle part usage export permission' using errcode = '42501';
    end if;
  elsif not app_private.can_access_vms_vehicle_part_usage_data() then
    raise exception 'Missing vehicle part usage read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select usage_row as usage_record
    from public.vehicle_part_usage usage_row
    where (app_private.is_platform_super() or usage_row.tenant_id = v_tenant_id)
      and (p_vehicle_id is null or usage_row.vehicle_id = p_vehicle_id)
      and (p_ids is null or usage_row.id = any(p_ids))
      and (nullif(btrim(p_company_name), '') is null or usage_row.company_name ilike '%' || btrim(p_company_name) || '%')
      and (nullif(btrim(p_plate_no), '') is null or usage_row.plate_no ilike '%' || btrim(p_plate_no) || '%')
      and (nullif(btrim(p_part_type), '') is null or usage_row.part_type = btrim(p_part_type))
      and (nullif(btrim(p_part_name), '') is null or usage_row.part_name ilike '%' || btrim(p_part_name) || '%')
      and (p_category_id is null or usage_row.category_id = p_category_id)
      and (nullif(btrim(p_status), '') is null or usage_row.status = btrim(p_status))
      and (
        nullif(btrim(p_rfid_tag), '') is null
        or (
          app_private.resolve_field_access(
            'vms.vehicle_part_usage', 'traceabilityTag', usage_row.created_by_user_id
          ) in ('read', 'edit')
          and usage_row.rfid_tag ilike '%' || btrim(p_rfid_tag) || '%'
        )
      )
      and (p_create_time_from is null or usage_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or usage_row.create_time <= p_create_time_to)
  ), paged as (
    select filtered.usage_record
    from filtered
    order by (filtered.usage_record).create_time desc, (filtered.usage_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.vehicle_part_usage_to_secure_json(paged.usage_record, null)
        order by (paged.usage_record).create_time desc, (paged.usage_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', app_private.field_access_map('vms.vehicle_part_usage', null)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.vms_get_vehicle_part_usage_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_usage public.vehicle_part_usage%rowtype;
begin
  select * into v_usage
  from public.vehicle_part_usage usage_row
  where usage_row.id = p_id
    and (app_private.is_platform_super() or usage_row.tenant_id = app_private.current_user_tenant_id());
  if not found then return null; end if;
  if not app_private.can_execute_business_action(
    'VehiclePartsManage', 'VehiclePartUsage:View', v_usage.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle part usage view permission' using errcode = '42501';
  end if;
  return app_private.vehicle_part_usage_to_secure_json(v_usage, null);
end;
$$;

create or replace function app_private.assert_vms_vehicle_part_usage_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_allowed constant text[] := array[
    'vehicle_id', 'plate_no', 'company_name', 'part_id', 'part_type',
    'part_name', 'part_code', 'category_id', 'category_name', 'brand', 'model',
    'unit', 'quality_category', 'manufacturer', 'supplier_id', 'supplier_name',
    'supplier_contact', 'is_consumable', 'rfid_enabled', 'rfid_tag', 'enable_mode',
    'enable_date', 'warranty_mode', 'warranty_mileage', 'warranty_duration',
    'service_mileage_enabled', 'service_mileage', 'service_years_enabled',
    'service_years', 'used_mileage', 'status', 'scrap_reason', 'remark'
  ]::text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Vehicle part usage payload must be a JSON object';
  end if;
  for v_key in select jsonb_object_keys(p_payload)
  loop
    if not (v_key = any(v_allowed)) then
      raise exception 'Unsupported vehicle part usage field: %', v_key;
    end if;
  end loop;
end;
$$;

create or replace function app_private.normalize_vms_vehicle_part_usage_references(
  p_input public.vehicle_part_usage
)
returns public.vehicle_part_usage
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_input public.vehicle_part_usage := p_input;
begin
  if v_input.vehicle_id is null then raise exception 'Vehicle is required'; end if;
  select vehicle_row.plate_no, vehicle_row.company_name
  into v_input.plate_no, v_input.company_name
  from public.vehicle_archive vehicle_row
  where vehicle_row.id = v_input.vehicle_id and vehicle_row.tenant_id = v_input.tenant_id;
  if not found then
    raise exception 'Vehicle is outside the current tenant' using errcode = '42501';
  end if;

  if v_input.part_id is null then raise exception 'Vehicle part is required'; end if;
  select part_row.part_name, part_row.part_code, part_row.category_id,
         category_row.category_name, part_row.brand, part_row.model, part_row.unit,
         part_row.manufacturer, part_row.supplier_id, supplier_row.supplier_name,
         part_row.supplier_contact, part_row.is_consumable
  into v_input.part_name, v_input.part_code, v_input.category_id,
       v_input.category_name, v_input.brand, v_input.model, v_input.unit,
       v_input.manufacturer, v_input.supplier_id, v_input.supplier_name,
       v_input.supplier_contact, v_input.is_consumable
  from public.vehicle_parts part_row
  left join public.vehicle_parts_category category_row
    on category_row.id = part_row.category_id and category_row.tenant_id = part_row.tenant_id
  left join public.vehicle_supplier supplier_row
    on supplier_row.id = part_row.supplier_id and supplier_row.tenant_id = part_row.tenant_id
  where part_row.id = v_input.part_id and part_row.tenant_id = v_input.tenant_id;
  if not found then
    raise exception 'Vehicle part is outside the current tenant' using errcode = '42501';
  end if;

  if v_input.part_type not in ('original', 'replacement') then
    raise exception 'Invalid vehicle part type';
  end if;
  if v_input.enable_mode not in ('vehicle', 'date')
     or (v_input.enable_mode = 'date' and v_input.enable_date is null) then
    raise exception 'Invalid vehicle part enable date';
  end if;
  if v_input.warranty_mode not in ('vehicle', 'self') then
    raise exception 'Invalid vehicle part warranty mode';
  end if;
  if v_input.warranty_mode = 'self'
     and v_input.warranty_mileage is null and v_input.warranty_duration is null then
    raise exception 'Vehicle part warranty mileage or duration is required';
  end if;
  if not v_input.service_mileage_enabled and not v_input.service_years_enabled then
    raise exception 'Vehicle part service mileage or years is required';
  end if;
  if v_input.service_mileage_enabled and v_input.service_mileage is null then
    raise exception 'Vehicle part service mileage is required';
  end if;
  if v_input.service_years_enabled and v_input.service_years is null then
    raise exception 'Vehicle part service years is required';
  end if;
  if v_input.status not in ('normal', 'reused', 'scrapped') then
    raise exception 'Invalid vehicle part usage status';
  end if;
  if v_input.status = 'scrapped' and nullif(btrim(v_input.scrap_reason), '') is null then
    raise exception 'Vehicle part scrap reason is required';
  end if;
  if v_input.rfid_enabled and nullif(btrim(v_input.rfid_tag), '') is null then
    raise exception 'Vehicle part RFID tag is required';
  end if;
  return v_input;
end;
$$;

create or replace function public.vms_create_vehicle_part_usage_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.vehicle_part_usage%rowtype;
  v_created public.vehicle_part_usage%rowtype;
begin
  if not app_private.can_execute_business_action(
    'VehiclePartsManage', 'VehiclePartUsage:Add', null, false
  ) then
    raise exception 'Missing vehicle part usage add permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then raise exception 'Current tenant not found' using errcode = '42501'; end if;

  perform app_private.assert_vms_vehicle_part_usage_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.vehicle_part_usage, p_payload);
  v_input.id := gen_random_uuid();
  v_input.tenant_id := v_tenant_id;
  v_input.created_by_user_id := app_private.current_app_user_id();
  v_input := app_private.normalize_vms_vehicle_part_usage_references(v_input);
  v_input.create_time := now();
  v_input.update_time := now();
  insert into public.vehicle_part_usage select (v_input).* returning * into v_created;
  return v_created.id;
end;
$$;

create or replace function public.vms_update_vehicle_part_usage_secure(
  p_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.vehicle_part_usage%rowtype;
  v_candidate public.vehicle_part_usage%rowtype;
  v_updated public.vehicle_part_usage%rowtype;
begin
  select * into v_old
  from public.vehicle_part_usage usage_row
  where usage_row.id = p_id
    and (app_private.is_platform_super() or usage_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Vehicle part usage record not found'; end if;
  if not app_private.can_execute_business_action(
    'VehiclePartsManage', 'VehiclePartUsage:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle part usage edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_vms_vehicle_part_usage_payload_keys(p_payload);
  if p_payload = '{}'::jsonb then
    return app_private.vehicle_part_usage_to_secure_json(v_old, null);
  end if;
  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  v_candidate.id := v_old.id;
  v_candidate.tenant_id := v_old.tenant_id;
  v_candidate.created_by_user_id := v_old.created_by_user_id;
  v_candidate.create_time := v_old.create_time;
  v_candidate := app_private.normalize_vms_vehicle_part_usage_references(v_candidate);
  v_candidate.update_time := now();

  if v_candidate.part_id = v_old.part_id
     and (v_candidate.supplier_id, v_candidate.supplier_name, v_candidate.supplier_contact)
       is distinct from (v_old.supplier_id, v_old.supplier_name, v_old.supplier_contact)
     and app_private.resolve_field_access(
       'vms.vehicle_part_usage', 'supplierDetails', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle part supplier details' using errcode = '42501';
  end if;
  if (v_candidate.rfid_enabled, v_candidate.rfid_tag)
       is distinct from (v_old.rfid_enabled, v_old.rfid_tag)
     and app_private.resolve_field_access(
       'vms.vehicle_part_usage', 'traceabilityTag', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle part traceability tag' using errcode = '42501';
  end if;
  if (
       v_candidate.enable_mode, v_candidate.enable_date,
       v_candidate.warranty_mode, v_candidate.warranty_mileage, v_candidate.warranty_duration,
       v_candidate.service_mileage_enabled, v_candidate.service_mileage,
       v_candidate.service_years_enabled, v_candidate.service_years, v_candidate.used_mileage
     ) is distinct from (
       v_old.enable_mode, v_old.enable_date,
       v_old.warranty_mode, v_old.warranty_mileage, v_old.warranty_duration,
       v_old.service_mileage_enabled, v_old.service_mileage,
       v_old.service_years_enabled, v_old.service_years, v_old.used_mileage
     )
     and app_private.resolve_field_access(
       'vms.vehicle_part_usage', 'lifecycleLimits', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle part lifecycle limits' using errcode = '42501';
  end if;
  if (v_candidate.scrap_reason, v_candidate.remark)
       is distinct from (v_old.scrap_reason, v_old.remark)
     and app_private.resolve_field_access(
       'vms.vehicle_part_usage', 'dispositionNotes', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle part disposition notes' using errcode = '42501';
  end if;

  update public.vehicle_part_usage
  set vehicle_id = v_candidate.vehicle_id,
      plate_no = v_candidate.plate_no,
      company_name = v_candidate.company_name,
      part_id = v_candidate.part_id,
      part_type = v_candidate.part_type,
      part_name = v_candidate.part_name,
      part_code = v_candidate.part_code,
      category_id = v_candidate.category_id,
      category_name = v_candidate.category_name,
      brand = v_candidate.brand,
      model = v_candidate.model,
      unit = v_candidate.unit,
      quality_category = v_candidate.quality_category,
      manufacturer = v_candidate.manufacturer,
      supplier_id = v_candidate.supplier_id,
      supplier_name = v_candidate.supplier_name,
      supplier_contact = v_candidate.supplier_contact,
      is_consumable = v_candidate.is_consumable,
      rfid_enabled = v_candidate.rfid_enabled,
      rfid_tag = v_candidate.rfid_tag,
      enable_mode = v_candidate.enable_mode,
      enable_date = v_candidate.enable_date,
      warranty_mode = v_candidate.warranty_mode,
      warranty_mileage = v_candidate.warranty_mileage,
      warranty_duration = v_candidate.warranty_duration,
      service_mileage_enabled = v_candidate.service_mileage_enabled,
      service_mileage = v_candidate.service_mileage,
      service_years_enabled = v_candidate.service_years_enabled,
      service_years = v_candidate.service_years,
      used_mileage = v_candidate.used_mileage,
      status = v_candidate.status,
      scrap_reason = v_candidate.scrap_reason,
      remark = v_candidate.remark,
      update_time = v_candidate.update_time
  where id = v_old.id
  returning * into v_updated;
  return app_private.vehicle_part_usage_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.vms_delete_vehicle_part_usages_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_ids, '{}'::uuid[])));
  v_usage public.vehicle_part_usage%rowtype;
  v_deleted integer;
begin
  if coalesce(array_length(v_ids, 1), 0) = 0 then return 0; end if;
  if exists (
    select 1 from public.vehicle_part_usage usage_row
    where usage_row.id = any(v_ids)
      and not (app_private.is_platform_super() or usage_row.tenant_id = app_private.current_user_tenant_id())
  ) or (
    select count(*) from public.vehicle_part_usage usage_row where usage_row.id = any(v_ids)
  ) <> array_length(v_ids, 1) then
    raise exception 'One or more vehicle part usage records are missing or outside the current tenant';
  end if;
  for v_usage in
    select * from public.vehicle_part_usage usage_row where usage_row.id = any(v_ids) for update
  loop
    if not app_private.can_execute_business_action(
      'VehiclePartsManage', 'VehiclePartUsage:Delete', v_usage.created_by_user_id, true
    ) then
      raise exception 'Missing vehicle part usage delete permission' using errcode = '42501';
    end if;
  end loop;
  delete from public.vehicle_part_usage usage_row where usage_row.id = any(v_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function public.vms_get_vehicle_part_health_context_secure(
  p_vehicle_id uuid default null,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not app_private.can_access_vms_vehicle_part_usage_data() then
    raise exception 'Missing vehicle part health context permission' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'part_name', usage_row.part_name,
    'status', usage_row.status,
    'enable_date', usage_row.enable_date,
    'service_mileage_enabled', usage_row.service_mileage_enabled,
    'service_mileage', usage_row.service_mileage,
    'service_years_enabled', usage_row.service_years_enabled,
    'service_years', usage_row.service_years,
    'used_mileage', usage_row.used_mileage
  ) order by usage_row.create_time desc, usage_row.id), '[]'::jsonb)
  into v_result
  from (
    select usage_record.*
    from public.vehicle_part_usage usage_record
    where (app_private.is_platform_super() or usage_record.tenant_id = app_private.current_user_tenant_id())
      and (p_vehicle_id is null or usage_record.vehicle_id = p_vehicle_id)
      and app_private.resolve_field_access(
        'vms.vehicle_part_usage', 'lifecycleLimits', usage_record.created_by_user_id
      ) in ('read', 'edit')
    order by usage_record.create_time desc, usage_record.id
    limit least(greatest(coalesce(p_limit, 200), 1), 500)
  ) usage_row;
  return v_result;
end;
$$;

revoke all on table public.vehicle_part_usage from anon, authenticated;
drop policy if exists vehicle_part_usage_tenant_select on public.vehicle_part_usage;
drop policy if exists vehicle_part_usage_tenant_insert on public.vehicle_part_usage;
drop policy if exists vehicle_part_usage_tenant_update on public.vehicle_part_usage;
drop policy if exists vehicle_part_usage_tenant_delete on public.vehicle_part_usage;
drop policy if exists vehicle_part_usage_service_all on public.vehicle_part_usage;
create policy vehicle_part_usage_service_all
on public.vehicle_part_usage
for all to service_role using (true) with check (true);

revoke all on function app_private.seed_field_permission_catalog(uuid) from public, anon, authenticated;
grant execute on function app_private.seed_field_permission_catalog(uuid) to service_role;
revoke all on function app_private.set_vehicle_part_usage_creator_identity() from public, anon, authenticated;
revoke all on function app_private.can_access_vms_vehicle_part_usage_data() from public, anon, authenticated;
revoke all on function app_private.vehicle_part_usage_to_secure_json(public.vehicle_part_usage, jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_vms_vehicle_part_usage_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.normalize_vms_vehicle_part_usage_references(public.vehicle_part_usage) from public, anon, authenticated;
grant execute on function app_private.set_vehicle_part_usage_creator_identity() to service_role;
grant execute on function app_private.can_access_vms_vehicle_part_usage_data() to service_role;
grant execute on function app_private.vehicle_part_usage_to_secure_json(public.vehicle_part_usage, jsonb) to service_role;
grant execute on function app_private.assert_vms_vehicle_part_usage_payload_keys(jsonb) to service_role;
grant execute on function app_private.normalize_vms_vehicle_part_usage_references(public.vehicle_part_usage) to service_role;

revoke all on function public.vms_list_vehicle_part_usages_secure(
  integer, integer, uuid, text, text, text, text, uuid, text, text,
  timestamptz, timestamptz, uuid[], text
) from public, anon;
revoke all on function public.vms_get_vehicle_part_usage_secure(uuid) from public, anon;
revoke all on function public.vms_create_vehicle_part_usage_secure(jsonb) from public, anon;
revoke all on function public.vms_update_vehicle_part_usage_secure(uuid, jsonb) from public, anon;
revoke all on function public.vms_delete_vehicle_part_usages_secure(uuid[]) from public, anon;
revoke all on function public.vms_get_vehicle_part_health_context_secure(uuid, integer) from public, anon;
grant execute on function public.vms_list_vehicle_part_usages_secure(
  integer, integer, uuid, text, text, text, text, uuid, text, text,
  timestamptz, timestamptz, uuid[], text
) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_part_usage_secure(uuid) to authenticated, service_role;
grant execute on function public.vms_create_vehicle_part_usage_secure(jsonb) to authenticated, service_role;
grant execute on function public.vms_update_vehicle_part_usage_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.vms_delete_vehicle_part_usages_secure(uuid[]) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_part_health_context_secure(uuid, integer) to authenticated, service_role;

;
