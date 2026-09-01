alter table public.vehicle_maintenance_record
  add column if not exists created_by_user_id uuid;

update public.vehicle_maintenance_record maintenance_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = maintenance_row.tenant_id
    and lower(user_row.user_email) = lower(maintenance_row.create_by)
    and user_row.deleted_at is null
  order by user_row.create_time, user_row.id
  limit 1
)
where maintenance_row.created_by_user_id is null;

do $$
begin
  if exists (
    select 1 from public.vehicle_maintenance_record where created_by_user_id is null
  ) then
    raise exception 'Cannot secure vehicle maintenance records: unresolved creators remain';
  end if;
end;
$$;

alter table public.vehicle_maintenance_record
  alter column created_by_user_id set not null;

alter table public.vehicle_maintenance_record
  drop constraint if exists vehicle_maintenance_record_creator_tenant_fk;
alter table public.vehicle_maintenance_record
  add constraint vehicle_maintenance_record_creator_tenant_fk
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on update restrict on delete restrict;

create index if not exists vehicle_maintenance_record_creator_tenant_idx
  on public.vehicle_maintenance_record(tenant_id, created_by_user_id);

create or replace function app_private.set_vehicle_maintenance_creator_identity()
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
      raise exception 'Authenticated vehicle maintenance creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Vehicle maintenance creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists vehicle_maintenance_creator_identity on public.vehicle_maintenance_record;
create trigger vehicle_maintenance_creator_identity
before insert or update on public.vehicle_maintenance_record
for each row execute function app_private.set_vehicle_maintenance_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
rename to seed_field_permission_catalog_before_vms_vehicle_maintenance;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_vms_vehicle_maintenance(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'vms.vehicle_maintenance', '车辆维修保养', 'VehicleMaintenance',
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
    (p_tenant_id, v_resource_id, 'maintenanceIdentifiers', '维修保养单号',
      'hidden', 'id_card', true, true, true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'totalCost', '维修保养总费用',
      'hidden', 'amount', true, true, true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'maintenanceItems', '项目、配件与明细费用',
      'hidden', 'none', true, true, true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'documents', '维修保养附件',
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
  on menu_row.type = 'menu' and menu_row.name = 'VehicleMaintenance'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'vms.vehicle_maintenance'
  and resource_row.enabled and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_access_vms_vehicle_maintenance_data()
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
          'VehicleMaintenance', 'VehicleMaintenanceDetail',
          'VehicleQuery', 'VehicleQueryDetail'
        )
        and app_private.can_access_business_menu(menu_row.name)
    );
$$;

create or replace function app_private.vehicle_maintenance_to_secure_json(
  p_maintenance public.vehicle_maintenance_record,
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
    app_private.field_access_map('vms.vehicle_maintenance', p_maintenance.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_maintenance) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'maintenanceIdentifiers', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'maintenance_no';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{maintenance_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_maintenance.maintenance_no, 'id_card')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'totalCost', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'cost_amount';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{cost_amount}', '"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'maintenanceItems', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'items';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{items}', '[]'::jsonb);
  end if;

  v_level := coalesce(v_access->>'documents', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'attachments';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{attachments}', '[]'::jsonb);
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_maintenance.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.vms_list_vehicle_maintenance_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_vehicle_id uuid default null,
  p_company_name text default null,
  p_plate_no text default null,
  p_maintenance_no text default null,
  p_maintenance_type text default null,
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
    raise exception 'Invalid vehicle maintenance read purpose';
  end if;
  if p_purpose = 'export' then
    if not app_private.can_execute_business_action(
      'VehicleMaintenance', 'VehicleMaintenance:Export', null, false
    ) then
      raise exception 'Missing vehicle maintenance export permission' using errcode = '42501';
    end if;
  elsif not app_private.can_access_vms_vehicle_maintenance_data() then
    raise exception 'Missing vehicle maintenance read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select maintenance_row as maintenance_record
    from public.vehicle_maintenance_record maintenance_row
    where (app_private.is_platform_super() or maintenance_row.tenant_id = v_tenant_id)
      and (p_vehicle_id is null or maintenance_row.vehicle_id = p_vehicle_id)
      and (p_ids is null or maintenance_row.id = any(p_ids))
      and (nullif(btrim(p_company_name), '') is null or maintenance_row.company_name ilike '%' || btrim(p_company_name) || '%')
      and (nullif(btrim(p_plate_no), '') is null or maintenance_row.plate_no ilike '%' || btrim(p_plate_no) || '%')
      and (
        nullif(btrim(p_maintenance_no), '') is null
        or (
          app_private.resolve_field_access(
            'vms.vehicle_maintenance', 'maintenanceIdentifiers', maintenance_row.created_by_user_id
          ) in ('read', 'edit')
          and maintenance_row.maintenance_no ilike '%' || btrim(p_maintenance_no) || '%'
        )
      )
      and (nullif(btrim(p_maintenance_type), '') is null or maintenance_row.maintenance_type = btrim(p_maintenance_type))
      and (p_create_time_from is null or maintenance_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or maintenance_row.create_time <= p_create_time_to)
  ), paged as (
    select filtered.maintenance_record
    from filtered
    order by (filtered.maintenance_record).start_time desc, (filtered.maintenance_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.vehicle_maintenance_to_secure_json(paged.maintenance_record, null)
        order by (paged.maintenance_record).start_time desc, (paged.maintenance_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', app_private.field_access_map('vms.vehicle_maintenance', null)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.vms_get_vehicle_maintenance_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_maintenance public.vehicle_maintenance_record%rowtype;
begin
  select * into v_maintenance
  from public.vehicle_maintenance_record maintenance_row
  where maintenance_row.id = p_id
    and (app_private.is_platform_super() or maintenance_row.tenant_id = app_private.current_user_tenant_id());
  if not found then return null; end if;

  if not app_private.can_execute_business_action(
    'VehicleMaintenance', 'VehicleMaintenance:View', v_maintenance.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle maintenance view permission' using errcode = '42501';
  end if;
  return app_private.vehicle_maintenance_to_secure_json(v_maintenance, null);
end;
$$;

create or replace function app_private.assert_vms_vehicle_maintenance_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_allowed constant text[] := array[
    'vehicle_id', 'plate_no', 'company_name', 'maintenance_no', 'maintenance_type',
    'initiator', 'start_time', 'end_time', 'cost_amount', 'workshop',
    'external_repair', 'remark', 'items', 'attachments'
  ]::text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Vehicle maintenance payload must be a JSON object';
  end if;
  for v_key in select jsonb_object_keys(p_payload)
  loop
    if not (v_key = any(v_allowed)) then
      raise exception 'Unsupported vehicle maintenance field: %', v_key;
    end if;
  end loop;
end;
$$;

create or replace function app_private.normalize_vms_vehicle_maintenance_references(
  p_input public.vehicle_maintenance_record
)
returns public.vehicle_maintenance_record
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_input public.vehicle_maintenance_record := p_input;
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

create or replace function public.vms_create_vehicle_maintenance_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.vehicle_maintenance_record%rowtype;
  v_created public.vehicle_maintenance_record%rowtype;
begin
  if not app_private.can_execute_business_action(
    'VehicleMaintenance', 'VehicleMaintenance:Add', null, false
  ) then
    raise exception 'Missing vehicle maintenance add permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then raise exception 'Current tenant not found' using errcode = '42501'; end if;

  perform app_private.assert_vms_vehicle_maintenance_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.vehicle_maintenance_record, p_payload);
  v_input.id := gen_random_uuid();
  v_input.tenant_id := v_tenant_id;
  v_input := app_private.normalize_vms_vehicle_maintenance_references(v_input);
  v_input.items := coalesce(v_input.items, '[]'::jsonb);
  v_input.attachments := coalesce(v_input.attachments, '[]'::jsonb);
  v_input.create_time := now();
  v_input.update_time := now();
  insert into public.vehicle_maintenance_record select (v_input).* returning * into v_created;
  return v_created.id;
end;
$$;

create or replace function public.vms_update_vehicle_maintenance_secure(
  p_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.vehicle_maintenance_record%rowtype;
  v_candidate public.vehicle_maintenance_record%rowtype;
  v_updated public.vehicle_maintenance_record%rowtype;
  v_safe_payload jsonb;
  v_assignments text;
begin
  select * into v_old
  from public.vehicle_maintenance_record maintenance_row
  where maintenance_row.id = p_id
    and (app_private.is_platform_super() or maintenance_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Vehicle maintenance record not found'; end if;

  if not app_private.can_execute_business_action(
    'VehicleMaintenance', 'VehicleMaintenance:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle maintenance edit permission' using errcode = '42501';
  end if;
  perform app_private.assert_vms_vehicle_maintenance_payload_keys(p_payload);
  if p_payload = '{}'::jsonb then
    return app_private.vehicle_maintenance_to_secure_json(v_old, null);
  end if;

  select * into v_candidate from jsonb_populate_record(v_old, p_payload);
  v_candidate.id := v_old.id;
  v_candidate.tenant_id := v_old.tenant_id;
  v_candidate.created_by_user_id := v_old.created_by_user_id;
  v_candidate.create_time := v_old.create_time;
  v_candidate := app_private.normalize_vms_vehicle_maintenance_references(v_candidate);
  v_candidate.items := coalesce(v_candidate.items, '[]'::jsonb);
  v_candidate.attachments := coalesce(v_candidate.attachments, '[]'::jsonb);
  v_candidate.update_time := now();

  if v_candidate.maintenance_no is distinct from v_old.maintenance_no
     and app_private.resolve_field_access(
       'vms.vehicle_maintenance', 'maintenanceIdentifiers', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle maintenance identifier' using errcode = '42501';
  end if;
  if v_candidate.cost_amount is distinct from v_old.cost_amount
     and app_private.resolve_field_access(
       'vms.vehicle_maintenance', 'totalCost', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle maintenance cost' using errcode = '42501';
  end if;
  if v_candidate.items is distinct from v_old.items
     and app_private.resolve_field_access(
       'vms.vehicle_maintenance', 'maintenanceItems', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle maintenance items' using errcode = '42501';
  end if;
  if v_candidate.attachments is distinct from v_old.attachments
     and app_private.resolve_field_access(
       'vms.vehicle_maintenance', 'documents', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle maintenance documents' using errcode = '42501';
  end if;

  v_safe_payload := p_payload - 'plate_no' - 'company_name';
  select string_agg(format('%I = ($1).%I', payload_key, payload_key), ', ')
  into v_assignments from jsonb_object_keys(v_safe_payload) payload_key;
  if v_assignments is null then
    return app_private.vehicle_maintenance_to_secure_json(v_old, null);
  end if;
  execute format(
    'update public.vehicle_maintenance_record set %s where id = $2 returning *', v_assignments
  ) into v_updated using v_candidate, v_old.id;
  return app_private.vehicle_maintenance_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.vms_delete_vehicle_maintenance_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_ids, '{}'::uuid[])));
  v_maintenance public.vehicle_maintenance_record%rowtype;
  v_deleted integer;
begin
  if coalesce(array_length(v_ids, 1), 0) = 0 then return 0; end if;
  if exists (
    select 1 from public.vehicle_maintenance_record maintenance_row
    where maintenance_row.id = any(v_ids)
      and not (app_private.is_platform_super() or maintenance_row.tenant_id = app_private.current_user_tenant_id())
  ) or (select count(*) from public.vehicle_maintenance_record maintenance_row where maintenance_row.id = any(v_ids)) <> array_length(v_ids, 1) then
    raise exception 'One or more vehicle maintenance records are missing or outside the current tenant';
  end if;

  for v_maintenance in
    select * from public.vehicle_maintenance_record maintenance_row where maintenance_row.id = any(v_ids) for update
  loop
    if not app_private.can_execute_business_action(
      'VehicleMaintenance', 'VehicleMaintenance:Delete', v_maintenance.created_by_user_id, true
    ) then
      raise exception 'Missing vehicle maintenance delete permission' using errcode = '42501';
    end if;
  end loop;
  delete from public.vehicle_maintenance_record maintenance_row where maintenance_row.id = any(v_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function public.vms_get_vehicle_maintenance_health_context_secure(
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
    raise exception 'Missing vehicle maintenance context permission' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', maintenance_row.id,
    'vehicle_id', maintenance_row.vehicle_id,
    'maintenance_type', maintenance_row.maintenance_type,
    'start_time', maintenance_row.start_time,
    'end_time', maintenance_row.end_time,
    'create_time', maintenance_row.create_time
  ) order by maintenance_row.start_time desc, maintenance_row.id), '[]'::jsonb)
  into v_result
  from (
    select maintenance_record.*
    from public.vehicle_maintenance_record maintenance_record
    where (app_private.is_platform_super() or maintenance_record.tenant_id = app_private.current_user_tenant_id())
      and (p_vehicle_id is null or maintenance_record.vehicle_id = p_vehicle_id)
    order by maintenance_record.start_time desc, maintenance_record.id
    limit least(greatest(coalesce(p_limit, 100), 1), 500)
  ) maintenance_row;
  return v_result;
end;
$$;

revoke all on table public.vehicle_maintenance_record from anon, authenticated;
drop policy if exists vehicle_maintenance_record_tenant_select on public.vehicle_maintenance_record;
drop policy if exists vehicle_maintenance_record_tenant_insert on public.vehicle_maintenance_record;
drop policy if exists vehicle_maintenance_record_tenant_update on public.vehicle_maintenance_record;
drop policy if exists vehicle_maintenance_record_tenant_delete on public.vehicle_maintenance_record;
drop policy if exists vehicle_maintenance_record_service_all on public.vehicle_maintenance_record;
create policy vehicle_maintenance_record_service_all
on public.vehicle_maintenance_record
for all to service_role
using (true) with check (true);

revoke all on function app_private.seed_field_permission_catalog(uuid) from public, anon, authenticated;
grant execute on function app_private.seed_field_permission_catalog(uuid) to service_role;
revoke all on function app_private.set_vehicle_maintenance_creator_identity() from public, anon, authenticated;
revoke all on function app_private.can_access_vms_vehicle_maintenance_data() from public, anon, authenticated;
revoke all on function app_private.vehicle_maintenance_to_secure_json(public.vehicle_maintenance_record, jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_vms_vehicle_maintenance_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.normalize_vms_vehicle_maintenance_references(public.vehicle_maintenance_record) from public, anon, authenticated;
grant execute on function app_private.set_vehicle_maintenance_creator_identity() to service_role;
grant execute on function app_private.can_access_vms_vehicle_maintenance_data() to service_role;
grant execute on function app_private.vehicle_maintenance_to_secure_json(public.vehicle_maintenance_record, jsonb) to service_role;
grant execute on function app_private.assert_vms_vehicle_maintenance_payload_keys(jsonb) to service_role;
grant execute on function app_private.normalize_vms_vehicle_maintenance_references(public.vehicle_maintenance_record) to service_role;

revoke all on function public.vms_list_vehicle_maintenance_secure(
  integer, integer, uuid, text, text, text, text, timestamptz, timestamptz, uuid[], text
) from public, anon;
revoke all on function public.vms_get_vehicle_maintenance_secure(uuid) from public, anon;
revoke all on function public.vms_create_vehicle_maintenance_secure(jsonb) from public, anon;
revoke all on function public.vms_update_vehicle_maintenance_secure(uuid, jsonb) from public, anon;
revoke all on function public.vms_delete_vehicle_maintenance_secure(uuid[]) from public, anon;
revoke all on function public.vms_get_vehicle_maintenance_health_context_secure(uuid, integer) from public, anon;
grant execute on function public.vms_list_vehicle_maintenance_secure(
  integer, integer, uuid, text, text, text, text, timestamptz, timestamptz, uuid[], text
) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_maintenance_secure(uuid) to authenticated, service_role;
grant execute on function public.vms_create_vehicle_maintenance_secure(jsonb) to authenticated, service_role;
grant execute on function public.vms_update_vehicle_maintenance_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.vms_delete_vehicle_maintenance_secure(uuid[]) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_maintenance_health_context_secure(uuid, integer) to authenticated, service_role;

;
