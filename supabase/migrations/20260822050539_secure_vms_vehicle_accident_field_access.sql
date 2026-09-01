alter table public.vehicle_accident_record
  add column if not exists created_by_user_id uuid;

update public.vehicle_accident_record accident_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = accident_row.tenant_id
    and lower(user_row.user_email) = lower(accident_row.create_by)
    and user_row.deleted_at is null
  order by user_row.create_time, user_row.id
  limit 1
)
where accident_row.created_by_user_id is null;

do $$
begin
  if exists (select 1 from public.vehicle_accident_record where created_by_user_id is null) then
    raise exception 'Cannot secure vehicle accident records: unresolved creators remain';
  end if;
end;
$$;

alter table public.vehicle_accident_record
  alter column created_by_user_id set not null;

alter table public.vehicle_accident_record
  drop constraint if exists vehicle_accident_record_creator_tenant_fk;
alter table public.vehicle_accident_record
  add constraint vehicle_accident_record_creator_tenant_fk
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on update restrict on delete restrict;

create index if not exists vehicle_accident_record_creator_tenant_idx
  on public.vehicle_accident_record(created_by_user_id, tenant_id);

create or replace function app_private.set_vehicle_accident_creator_identity()
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
    elsif v_current_user_id is null and new.created_by_user_id is null then
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
      raise exception 'Authenticated vehicle accident creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Vehicle accident creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists vehicle_accident_creator_identity on public.vehicle_accident_record;
create trigger vehicle_accident_creator_identity
before insert or update on public.vehicle_accident_record
for each row execute function app_private.set_vehicle_accident_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
rename to seed_field_permission_catalog_before_vms_vehicle_accident;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_vms_vehicle_accident(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'vms.vehicle_accident', '车辆事故记录', 'VehicleAccident',
    'created_by_user_id', '624944977@qq.com', '624944977@qq.com'
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
    (p_tenant_id, v_resource_id, 'driverContact', '驾驶员姓名与手机号',
      'hidden', 'phone', true, true, true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'accidentLocation', '事故地点与坐标',
      'hidden', 'address', true, true, true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'accidentNarrative', '事故经过与备注',
      'hidden', 'none', true, true, true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'lossAmounts', '事故损失与公司承担金额',
      'hidden', 'amount', true, true, true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'documents', '事故附件',
      'hidden', 'none', true, true, true, 50, '624944977@qq.com', '624944977@qq.com')
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
  on menu_row.type = 'menu' and menu_row.name = 'VehicleAccident'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'vms.vehicle_accident'
  and resource_row.enabled and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_access_vms_vehicle_accident_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select app_private.is_platform_super()
    or exists (
      select 1
      from public.sys_menu menu_row
      where menu_row.type = 'menu'
        and menu_row.name in (
          'VehicleAccident', 'VehicleAccidentDetail',
          'VehicleQuery', 'VehicleQueryDetail'
        )
        and app_private.can_access_business_menu(menu_row.name)
    );
$$;

create or replace function app_private.vehicle_accident_to_secure_json(
  p_accident public.vehicle_accident_record,
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
    app_private.field_access_map('vms.vehicle_accident', p_accident.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_accident) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'driverContact', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'driver_name' - 'driver_phone';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{driver_name}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_accident.driver_name, 'none')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{driver_phone}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_accident.driver_phone, 'phone')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'accidentLocation', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'accident_location' - 'accident_longitude' - 'accident_latitude';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{accident_location}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_accident.accident_location, 'address')
    ), 'null'::jsonb));
    v_data := v_data - 'accident_longitude' - 'accident_latitude';
  end if;

  v_level := coalesce(v_access->>'accidentNarrative', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'accident_summary' - 'remark';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{accident_summary}', '"***"'::jsonb);
    v_data := jsonb_set(v_data, '{remark}', '"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'lossAmounts', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'company_bear_amount' - 'economic_loss';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{company_bear_amount}', '"***"'::jsonb);
    v_data := jsonb_set(v_data, '{economic_loss}', '"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'documents', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'attachments';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{attachments}', '[]'::jsonb);
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_accident.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.vms_list_vehicle_accidents_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_vehicle_id uuid default null,
  p_company_name text default null,
  p_plate_no text default null,
  p_driver_name text default null,
  p_processed boolean default null,
  p_data_source text default null,
  p_accident_time_from timestamptz default null,
  p_accident_time_to timestamptz default null,
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
    raise exception 'Invalid vehicle accident read purpose';
  end if;
  if p_purpose = 'export' then
    if not app_private.can_execute_business_action(
      'VehicleAccident', 'VehicleAccident:Export', null, false
    ) then
      raise exception 'Missing vehicle accident export permission' using errcode = '42501';
    end if;
  elsif not app_private.can_access_vms_vehicle_accident_data() then
    raise exception 'Missing vehicle accident read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select accident_row as accident_record
    from public.vehicle_accident_record accident_row
    where (app_private.is_platform_super() or accident_row.tenant_id = v_tenant_id)
      and (p_vehicle_id is null or accident_row.vehicle_id = p_vehicle_id)
      and (p_ids is null or accident_row.id = any(p_ids))
      and (nullif(btrim(p_company_name), '') is null or accident_row.company_name ilike '%' || btrim(p_company_name) || '%')
      and (nullif(btrim(p_plate_no), '') is null or accident_row.plate_no ilike '%' || btrim(p_plate_no) || '%')
      and (
        nullif(btrim(p_driver_name), '') is null
        or (
          app_private.resolve_field_access(
            'vms.vehicle_accident', 'driverContact', accident_row.created_by_user_id
          ) in ('read', 'edit')
          and accident_row.driver_name ilike '%' || btrim(p_driver_name) || '%'
        )
      )
      and (p_processed is null or accident_row.processed = p_processed)
      and (nullif(btrim(p_data_source), '') is null or accident_row.data_source = btrim(p_data_source))
      and (p_accident_time_from is null or accident_row.accident_time >= p_accident_time_from)
      and (p_accident_time_to is null or accident_row.accident_time <= p_accident_time_to)
      and (p_create_time_from is null or accident_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or accident_row.create_time <= p_create_time_to)
  ), paged as (
    select filtered.accident_record
    from filtered
    order by (filtered.accident_record).accident_time desc, (filtered.accident_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.vehicle_accident_to_secure_json(paged.accident_record, null)
        order by (paged.accident_record).accident_time desc, (paged.accident_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', app_private.field_access_map('vms.vehicle_accident', null)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.vms_get_vehicle_accident_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_accident public.vehicle_accident_record%rowtype;
begin
  select * into v_accident
  from public.vehicle_accident_record accident_row
  where accident_row.id = p_id
    and (app_private.is_platform_super() or accident_row.tenant_id = app_private.current_user_tenant_id());
  if not found then return null; end if;

  if not app_private.can_execute_business_action(
    'VehicleAccident', 'VehicleAccident:View', v_accident.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle accident view permission' using errcode = '42501';
  end if;
  return app_private.vehicle_accident_to_secure_json(v_accident, null);
end;
$$;

create or replace function app_private.assert_vms_vehicle_accident_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_allowed constant text[] := array[
    'vehicle_id', 'plate_no', 'company_name', 'driver_name', 'driver_phone',
    'accident_time', 'accident_location', 'accident_longitude', 'accident_latitude',
    'accident_summary', 'damage_level', 'responsibility_type', 'responsibility_percent',
    'company_bear_amount', 'economic_loss', 'reported', 'insurance_reported',
    'processed', 'data_source', 'remark', 'attachments'
  ]::text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Vehicle accident payload must be a JSON object';
  end if;
  for v_key in select jsonb_object_keys(p_payload)
  loop
    if not (v_key = any(v_allowed)) then
      raise exception 'Unsupported vehicle accident field: %', v_key;
    end if;
  end loop;
end;
$$;

create or replace function app_private.normalize_vms_vehicle_accident_references(
  p_input public.vehicle_accident_record
)
returns public.vehicle_accident_record
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_input public.vehicle_accident_record := p_input;
begin
  if v_input.vehicle_id is null then raise exception 'Vehicle is required'; end if;
  select vehicle_row.plate_no, vehicle_row.company_name
  into v_input.plate_no, v_input.company_name
  from public.vehicle_archive vehicle_row
  where vehicle_row.id = v_input.vehicle_id and vehicle_row.tenant_id = v_input.tenant_id;
  if not found then
    raise exception 'Vehicle is outside the current tenant' using errcode = '42501';
  end if;
  return v_input;
end;
$$;

create or replace function public.vms_create_vehicle_accident_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.vehicle_accident_record%rowtype;
  v_created public.vehicle_accident_record%rowtype;
begin
  if not app_private.can_execute_business_action(
    'VehicleAccident', 'VehicleAccident:Add', null, false
  ) then
    raise exception 'Missing vehicle accident add permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then raise exception 'Current tenant not found' using errcode = '42501'; end if;

  perform app_private.assert_vms_vehicle_accident_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.vehicle_accident_record, p_payload);
  v_input.id := gen_random_uuid();
  v_input.tenant_id := v_tenant_id;
  v_input := app_private.normalize_vms_vehicle_accident_references(v_input);
  v_input.reported := coalesce(v_input.reported, false);
  v_input.insurance_reported := coalesce(v_input.insurance_reported, false);
  v_input.processed := coalesce(v_input.processed, false);
  v_input.data_source := coalesce(nullif(btrim(v_input.data_source), ''), 'self');
  v_input.attachments := coalesce(v_input.attachments, '[]'::jsonb);
  v_input.create_time := now();
  v_input.update_time := now();
  insert into public.vehicle_accident_record select (v_input).* returning * into v_created;
  return v_created.id;
end;
$$;

create or replace function public.vms_update_vehicle_accident_secure(
  p_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.vehicle_accident_record%rowtype;
  v_candidate public.vehicle_accident_record%rowtype;
  v_updated public.vehicle_accident_record%rowtype;
begin
  select * into v_old
  from public.vehicle_accident_record accident_row
  where accident_row.id = p_id
    and (app_private.is_platform_super() or accident_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Vehicle accident record not found'; end if;

  if not app_private.can_execute_business_action(
    'VehicleAccident', 'VehicleAccident:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle accident edit permission' using errcode = '42501';
  end if;
  perform app_private.assert_vms_vehicle_accident_payload_keys(p_payload);
  if p_payload = '{}'::jsonb then
    return app_private.vehicle_accident_to_secure_json(v_old, null);
  end if;

  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  v_candidate.id := v_old.id;
  v_candidate.tenant_id := v_old.tenant_id;
  v_candidate.created_by_user_id := v_old.created_by_user_id;
  v_candidate.create_time := v_old.create_time;
  v_candidate := app_private.normalize_vms_vehicle_accident_references(v_candidate);
  v_candidate.attachments := coalesce(v_candidate.attachments, '[]'::jsonb);
  v_candidate.update_time := now();

  if (v_candidate.driver_name, v_candidate.driver_phone) is distinct from
     (v_old.driver_name, v_old.driver_phone)
     and app_private.resolve_field_access(
       'vms.vehicle_accident', 'driverContact', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle accident driver contact' using errcode = '42501';
  end if;
  if (v_candidate.accident_location, v_candidate.accident_longitude, v_candidate.accident_latitude)
     is distinct from (v_old.accident_location, v_old.accident_longitude, v_old.accident_latitude)
     and app_private.resolve_field_access(
       'vms.vehicle_accident', 'accidentLocation', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle accident location' using errcode = '42501';
  end if;
  if (v_candidate.accident_summary, v_candidate.remark) is distinct from
     (v_old.accident_summary, v_old.remark)
     and app_private.resolve_field_access(
       'vms.vehicle_accident', 'accidentNarrative', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle accident narrative' using errcode = '42501';
  end if;
  if (v_candidate.company_bear_amount, v_candidate.economic_loss) is distinct from
     (v_old.company_bear_amount, v_old.economic_loss)
     and app_private.resolve_field_access(
       'vms.vehicle_accident', 'lossAmounts', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle accident loss amounts' using errcode = '42501';
  end if;
  if v_candidate.attachments is distinct from v_old.attachments
     and app_private.resolve_field_access(
       'vms.vehicle_accident', 'documents', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle accident documents' using errcode = '42501';
  end if;

  update public.vehicle_accident_record
  set vehicle_id = v_candidate.vehicle_id,
      plate_no = v_candidate.plate_no,
      company_name = v_candidate.company_name,
      driver_name = v_candidate.driver_name,
      driver_phone = v_candidate.driver_phone,
      accident_time = v_candidate.accident_time,
      accident_location = v_candidate.accident_location,
      accident_longitude = v_candidate.accident_longitude,
      accident_latitude = v_candidate.accident_latitude,
      accident_summary = v_candidate.accident_summary,
      damage_level = v_candidate.damage_level,
      responsibility_type = v_candidate.responsibility_type,
      responsibility_percent = v_candidate.responsibility_percent,
      company_bear_amount = v_candidate.company_bear_amount,
      economic_loss = v_candidate.economic_loss,
      reported = v_candidate.reported,
      insurance_reported = v_candidate.insurance_reported,
      processed = v_candidate.processed,
      data_source = v_candidate.data_source,
      remark = v_candidate.remark,
      attachments = v_candidate.attachments,
      update_time = v_candidate.update_time
  where id = v_old.id
  returning * into v_updated;
  return app_private.vehicle_accident_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.vms_delete_vehicle_accident_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_ids, '{}'::uuid[])));
  v_accident public.vehicle_accident_record%rowtype;
  v_deleted integer;
begin
  if coalesce(array_length(v_ids, 1), 0) = 0 then return 0; end if;
  if exists (
    select 1 from public.vehicle_accident_record accident_row
    where accident_row.id = any(v_ids)
      and not (app_private.is_platform_super() or accident_row.tenant_id = app_private.current_user_tenant_id())
  ) or (select count(*) from public.vehicle_accident_record accident_row where accident_row.id = any(v_ids)) <> array_length(v_ids, 1) then
    raise exception 'One or more vehicle accident records are missing or outside the current tenant';
  end if;

  for v_accident in
    select * from public.vehicle_accident_record accident_row where accident_row.id = any(v_ids) for update
  loop
    if not app_private.can_execute_business_action(
      'VehicleAccident', 'VehicleAccident:Delete', v_accident.created_by_user_id, true
    ) then
      raise exception 'Missing vehicle accident delete permission' using errcode = '42501';
    end if;
  end loop;
  delete from public.vehicle_accident_record accident_row where accident_row.id = any(v_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function public.vms_list_vehicle_accident_options_secure(
  p_keyword text default null,
  p_limit integer default 100
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
  if not (
    app_private.is_platform_super()
    or app_private.can_access_business_menu('SmisAccidentEmergency')
  ) then
    raise exception 'Missing SMIS accident reference permission' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(
    jsonb_strip_nulls(jsonb_build_object(
      'id', accident_row.id,
      'plate_no', accident_row.plate_no,
      'accident_time', accident_row.accident_time,
      'accident_location', case app_private.resolve_field_access(
        'vms.vehicle_accident', 'accidentLocation', accident_row.created_by_user_id
      )
        when 'masked' then app_private.mask_permission_value(accident_row.accident_location, 'address')
        when 'read' then accident_row.accident_location
        when 'edit' then accident_row.accident_location
        else null
      end,
      'accident_summary', case app_private.resolve_field_access(
        'vms.vehicle_accident', 'accidentNarrative', accident_row.created_by_user_id
      )
        when 'masked' then '***'
        when 'read' then accident_row.accident_summary
        when 'edit' then accident_row.accident_summary
        else null
      end,
      'economic_loss', case app_private.resolve_field_access(
        'vms.vehicle_accident', 'lossAmounts', accident_row.created_by_user_id
      )
        when 'masked' then to_jsonb('***'::text)
        when 'read' then to_jsonb(accident_row.economic_loss)
        when 'edit' then to_jsonb(accident_row.economic_loss)
        else null
      end,
      'field_access', app_private.field_access_map(
        'vms.vehicle_accident', accident_row.created_by_user_id
      )
    )) order by accident_row.accident_time desc, accident_row.id
  ), '[]'::jsonb) into v_result
  from (
    select accident_record.*
    from public.vehicle_accident_record accident_record
    where (
      app_private.is_platform_super()
      or accident_record.tenant_id = app_private.current_user_tenant_id()
    )
      and (
        nullif(btrim(p_keyword), '') is null
        or accident_record.plate_no ilike '%' || btrim(p_keyword) || '%'
        or (
          app_private.resolve_field_access(
            'vms.vehicle_accident', 'accidentNarrative', accident_record.created_by_user_id
          ) in ('read', 'edit')
          and accident_record.accident_summary ilike '%' || btrim(p_keyword) || '%'
        )
      )
    order by accident_record.accident_time desc, accident_record.id
    limit least(greatest(coalesce(p_limit, 100), 1), 500)
  ) accident_row;
  return v_result;
end;
$$;

create or replace function public.vms_get_vehicle_accident_health_context_secure(
  p_vehicle_id uuid default null,
  p_limit integer default 100
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
  if not app_private.can_access_vms_vehicle_reference_data() then
    raise exception 'Missing vehicle accident context permission' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', accident_row.id,
    'vehicle_id', accident_row.vehicle_id,
    'accident_time', accident_row.accident_time,
    'damage_level', accident_row.damage_level,
    'processed', accident_row.processed,
    'create_time', accident_row.create_time
  ) order by accident_row.accident_time desc, accident_row.id), '[]'::jsonb)
  into v_result
  from (
    select accident_record.*
    from public.vehicle_accident_record accident_record
    where (app_private.is_platform_super() or accident_record.tenant_id = app_private.current_user_tenant_id())
      and (p_vehicle_id is null or accident_record.vehicle_id = p_vehicle_id)
    order by accident_record.accident_time desc, accident_record.id
    limit least(greatest(coalesce(p_limit, 100), 1), 500)
  ) accident_row;
  return v_result;
end;
$$;

revoke all on table public.vehicle_accident_record from anon, authenticated;
drop policy if exists vehicle_accident_record_tenant_select on public.vehicle_accident_record;
drop policy if exists vehicle_accident_record_tenant_insert on public.vehicle_accident_record;
drop policy if exists vehicle_accident_record_tenant_update on public.vehicle_accident_record;
drop policy if exists vehicle_accident_record_tenant_delete on public.vehicle_accident_record;
drop policy if exists vehicle_accident_record_service_all on public.vehicle_accident_record;
create policy vehicle_accident_record_service_all
on public.vehicle_accident_record
for all to service_role
using (true) with check (true);

revoke all on function app_private.seed_field_permission_catalog(uuid) from public, anon, authenticated;
grant execute on function app_private.seed_field_permission_catalog(uuid) to service_role;
revoke all on function app_private.set_vehicle_accident_creator_identity() from public, anon, authenticated;
revoke all on function app_private.can_access_vms_vehicle_accident_data() from public, anon, authenticated;
revoke all on function app_private.vehicle_accident_to_secure_json(public.vehicle_accident_record, jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_vms_vehicle_accident_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.normalize_vms_vehicle_accident_references(public.vehicle_accident_record) from public, anon, authenticated;
grant execute on function app_private.set_vehicle_accident_creator_identity() to service_role;
grant execute on function app_private.can_access_vms_vehicle_accident_data() to service_role;
grant execute on function app_private.vehicle_accident_to_secure_json(public.vehicle_accident_record, jsonb) to service_role;
grant execute on function app_private.assert_vms_vehicle_accident_payload_keys(jsonb) to service_role;
grant execute on function app_private.normalize_vms_vehicle_accident_references(public.vehicle_accident_record) to service_role;

revoke all on function public.vms_list_vehicle_accidents_secure(
  integer, integer, uuid, text, text, text, boolean, text,
  timestamptz, timestamptz, timestamptz, timestamptz, uuid[], text
) from public, anon;
revoke all on function public.vms_get_vehicle_accident_secure(uuid) from public, anon;
revoke all on function public.vms_create_vehicle_accident_secure(jsonb) from public, anon;
revoke all on function public.vms_update_vehicle_accident_secure(uuid, jsonb) from public, anon;
revoke all on function public.vms_delete_vehicle_accident_secure(uuid[]) from public, anon;
revoke all on function public.vms_list_vehicle_accident_options_secure(text, integer) from public, anon;
revoke all on function public.vms_get_vehicle_accident_health_context_secure(uuid, integer) from public, anon;
grant execute on function public.vms_list_vehicle_accidents_secure(
  integer, integer, uuid, text, text, text, boolean, text,
  timestamptz, timestamptz, timestamptz, timestamptz, uuid[], text
) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_accident_secure(uuid) to authenticated, service_role;
grant execute on function public.vms_create_vehicle_accident_secure(jsonb) to authenticated, service_role;
grant execute on function public.vms_update_vehicle_accident_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.vms_delete_vehicle_accident_secure(uuid[]) to authenticated, service_role;
grant execute on function public.vms_list_vehicle_accident_options_secure(text, integer) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_accident_health_context_secure(uuid, integer) to authenticated, service_role;

;
