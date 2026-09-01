alter table public.vehicle_inspection
  add column if not exists created_by_user_id uuid;

update public.vehicle_inspection inspection_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = inspection_row.tenant_id
    and lower(user_row.user_email) = lower(inspection_row.create_by)
    and user_row.deleted_at is null
  order by user_row.create_time, user_row.id
  limit 1
)
where inspection_row.created_by_user_id is null;

do $$
begin
  if exists (select 1 from public.vehicle_inspection where created_by_user_id is null) then
    raise exception 'Cannot resolve every vehicle inspection creator identity';
  end if;
end;
$$;

alter table public.vehicle_inspection
  alter column created_by_user_id set not null;

alter table public.vehicle_inspection
  drop constraint if exists vehicle_inspection_created_by_user_tenant_fkey;
alter table public.vehicle_inspection
  add constraint vehicle_inspection_created_by_user_tenant_fkey
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on delete restrict;

create index if not exists idx_vehicle_inspection_creator_tenant
  on public.vehicle_inspection(created_by_user_id, tenant_id);

create or replace function app_private.set_vehicle_inspection_creator_identity()
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
      raise exception 'Authenticated vehicle inspection creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Vehicle inspection creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists vehicle_inspection_creator_identity on public.vehicle_inspection;
create trigger vehicle_inspection_creator_identity
before insert or update on public.vehicle_inspection
for each row execute function app_private.set_vehicle_inspection_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
rename to seed_field_permission_catalog_before_vms_vehicle_inspection;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_vms_vehicle_inspection(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'vms.vehicle_inspection', '车辆年检', 'VehicleInspection',
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
    (p_tenant_id, v_resource_id, 'inspectionIdentifiers', '年检号与交强险保单号',
      'hidden', 'id_card', true, true, true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'monetaryAmounts', '年检金额与交强险保费',
      'hidden', 'amount', true, true, true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'documents', '年检证明附件',
      'hidden', 'none', true, true, true, 30, '624944977@qq.com', '624944977@qq.com')
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
  on menu_row.type = 'menu' and menu_row.name = 'VehicleInspection'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'vms.vehicle_inspection'
  and resource_row.enabled and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_access_vms_vehicle_inspection_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1 from public.sys_menu menu_row
      where menu_row.type = 'menu'
        and menu_row.name = any(array[
          'VehicleInspection', 'VehicleInspectionDetail',
          'VehicleQuery', 'VehicleQueryDetail', 'Console'
        ]::text[])
        and app_private.can_access_business_menu(menu_row.name)
    );
$$;

create or replace function app_private.vehicle_inspection_to_secure_json(
  p_inspection public.vehicle_inspection,
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
    app_private.field_access_map('vms.vehicle_inspection', p_inspection.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_inspection) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'inspectionIdentifiers', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'inspection_no' - 'compulsory_policy_no';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{inspection_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_inspection.inspection_no, 'id_card')
    ), 'null'::jsonb));
    v_data := jsonb_set(v_data, '{compulsory_policy_no}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_inspection.compulsory_policy_no, 'id_card')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'monetaryAmounts', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'inspection_amount' - 'compulsory_premium';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{inspection_amount}', '"***"'::jsonb);
    v_data := jsonb_set(v_data, '{compulsory_premium}', '"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'documents', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'attachments';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{attachments}', '[]'::jsonb);
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_inspection.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.vms_list_vehicle_inspections_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_vehicle_id uuid default null,
  p_company_name text default null,
  p_plate_no text default null,
  p_inspection_no text default null,
  p_expire_from date default null,
  p_expire_to date default null,
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
    raise exception 'Invalid vehicle inspection read purpose';
  end if;
  if p_purpose = 'export' then
    if not app_private.can_execute_business_action(
      'VehicleInspection', 'VehicleInspection:Export', null, false
    ) then
      raise exception 'Missing vehicle inspection export permission' using errcode = '42501';
    end if;
  elsif not app_private.can_access_vms_vehicle_inspection_data() then
    raise exception 'Missing vehicle inspection read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select inspection_row as inspection_record
    from public.vehicle_inspection inspection_row
    where (app_private.is_platform_super() or inspection_row.tenant_id = v_tenant_id)
      and (p_vehicle_id is null or inspection_row.vehicle_id = p_vehicle_id)
      and (p_ids is null or inspection_row.id = any(p_ids))
      and (nullif(btrim(p_company_name), '') is null or inspection_row.company_name ilike '%' || btrim(p_company_name) || '%')
      and (nullif(btrim(p_plate_no), '') is null or inspection_row.plate_no ilike '%' || btrim(p_plate_no) || '%')
      and (
        nullif(btrim(p_inspection_no), '') is null
        or (
          app_private.resolve_field_access(
            'vms.vehicle_inspection', 'inspectionIdentifiers', inspection_row.created_by_user_id
          ) in ('read', 'edit')
          and inspection_row.inspection_no ilike '%' || btrim(p_inspection_no) || '%'
        )
      )
      and (p_expire_from is null or inspection_row.expire_date >= p_expire_from)
      and (p_expire_to is null or inspection_row.expire_date <= p_expire_to)
      and (p_create_time_from is null or inspection_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or inspection_row.create_time <= p_create_time_to)
  ), paged as (
    select filtered.inspection_record
    from filtered
    order by (filtered.inspection_record).create_time desc, (filtered.inspection_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.vehicle_inspection_to_secure_json(paged.inspection_record, null)
        order by (paged.inspection_record).create_time desc, (paged.inspection_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', app_private.field_access_map('vms.vehicle_inspection', null)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.vms_get_vehicle_inspection_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_inspection public.vehicle_inspection%rowtype;
begin
  select * into v_inspection
  from public.vehicle_inspection inspection_row
  where inspection_row.id = p_id
    and (app_private.is_platform_super() or inspection_row.tenant_id = app_private.current_user_tenant_id());
  if not found then return null; end if;

  if not app_private.can_execute_business_action(
    'VehicleInspection', 'VehicleInspection:View', v_inspection.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle inspection view permission' using errcode = '42501';
  end if;
  return app_private.vehicle_inspection_to_secure_json(v_inspection, null);
end;
$$;

create or replace function app_private.assert_vms_vehicle_inspection_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_key text;
  v_allowed constant text[] := array[
    'vehicle_id', 'plate_no', 'company_name', 'inspection_no', 'inspection_date',
    'inspection_amount', 'vehicle_office', 'expire_date', 'compulsory_policy_no',
    'compulsory_company_id', 'compulsory_company_name', 'compulsory_insure_date',
    'compulsory_premium', 'compulsory_expire_date', 'remark', 'attachments'
  ]::text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Vehicle inspection payload must be a JSON object';
  end if;
  for v_key in select jsonb_object_keys(p_payload)
  loop
    if not (v_key = any(v_allowed)) then
      raise exception 'Unsupported vehicle inspection field: %', v_key;
    end if;
  end loop;
end;
$$;

create or replace function app_private.normalize_vms_vehicle_inspection_references(
  p_input public.vehicle_inspection
)
returns public.vehicle_inspection
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_input public.vehicle_inspection := p_input;
begin
  if v_input.vehicle_id is null then raise exception 'Vehicle is required'; end if;
  select vehicle_row.plate_no, vehicle_row.company_name
  into v_input.plate_no, v_input.company_name
  from public.vehicle_archive vehicle_row
  where vehicle_row.id = v_input.vehicle_id and vehicle_row.tenant_id = v_input.tenant_id;
  if not found then
    raise exception 'Vehicle is outside the current tenant' using errcode = '42501';
  end if;

  if v_input.compulsory_company_id is not null then
    select company_row.company_name into v_input.compulsory_company_name
    from public.vehicle_insurance_company company_row
    where company_row.id = v_input.compulsory_company_id
      and company_row.tenant_id = v_input.tenant_id;
    if not found then
      raise exception 'Inspection insurance company is outside the current tenant'
        using errcode = '42501';
    end if;
  else
    v_input.compulsory_company_name := null;
  end if;
  return v_input;
end;
$$;

create or replace function public.vms_create_vehicle_inspection_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.vehicle_inspection%rowtype;
  v_created public.vehicle_inspection%rowtype;
begin
  if not app_private.can_execute_business_action(
    'VehicleInspection', 'VehicleInspection:Add', null, false
  ) then
    raise exception 'Missing vehicle inspection add permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then raise exception 'Current tenant not found' using errcode = '42501'; end if;

  perform app_private.assert_vms_vehicle_inspection_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.vehicle_inspection, p_payload);
  v_input.id := gen_random_uuid();
  v_input.tenant_id := v_tenant_id;
  v_input := app_private.normalize_vms_vehicle_inspection_references(v_input);
  v_input.attachments := coalesce(v_input.attachments, '[]'::jsonb);
  v_input.create_time := now();
  v_input.update_time := now();
  insert into public.vehicle_inspection select (v_input).* returning * into v_created;
  return v_created.id;
end;
$$;

create or replace function public.vms_update_vehicle_inspection_secure(
  p_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old public.vehicle_inspection%rowtype;
  v_candidate public.vehicle_inspection%rowtype;
  v_updated public.vehicle_inspection%rowtype;
  v_safe_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_assignments text;
begin
  select * into v_old
  from public.vehicle_inspection inspection_row
  where inspection_row.id = p_id
    and (app_private.is_platform_super() or inspection_row.tenant_id = app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Vehicle inspection not found or access denied'; end if;

  if not app_private.can_execute_business_action(
    'VehicleInspection', 'VehicleInspection:Edit', v_old.created_by_user_id, true
  ) then
    raise exception 'Missing vehicle inspection edit permission' using errcode = '42501';
  end if;

  perform app_private.assert_vms_vehicle_inspection_payload_keys(v_safe_payload);
  select * into v_candidate from jsonb_populate_record(v_old, v_safe_payload);
  v_candidate.tenant_id := v_old.tenant_id;
  v_candidate := app_private.normalize_vms_vehicle_inspection_references(v_candidate);
  v_candidate.update_time := now();

  if (v_candidate.inspection_no, v_candidate.compulsory_policy_no)
     is distinct from (v_old.inspection_no, v_old.compulsory_policy_no)
     and app_private.resolve_field_access(
       'vms.vehicle_inspection', 'inspectionIdentifiers', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle inspection identifiers' using errcode = '42501';
  end if;

  if (v_candidate.inspection_amount, v_candidate.compulsory_premium)
     is distinct from (v_old.inspection_amount, v_old.compulsory_premium)
     and app_private.resolve_field_access(
       'vms.vehicle_inspection', 'monetaryAmounts', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle inspection amounts' using errcode = '42501';
  end if;

  if v_candidate.attachments is distinct from v_old.attachments
     and app_private.resolve_field_access(
       'vms.vehicle_inspection', 'documents', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for vehicle inspection documents' using errcode = '42501';
  end if;

  v_safe_payload := v_safe_payload || jsonb_build_object(
    'plate_no', v_candidate.plate_no,
    'company_name', v_candidate.company_name,
    'compulsory_company_name', v_candidate.compulsory_company_name,
    'update_time', v_candidate.update_time
  );
  select string_agg(
    format('%1$I = ($1::public.vehicle_inspection).%1$I', payload_key), ', '
  ) into v_assignments from jsonb_object_keys(v_safe_payload) payload_key;
  execute format(
    'update public.vehicle_inspection set %s where id = $2 returning *', v_assignments
  ) into v_updated using v_candidate, v_old.id;
  return app_private.vehicle_inspection_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.vms_delete_vehicle_inspections_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_ids, array[]::uuid[])));
  v_inspection public.vehicle_inspection%rowtype;
  v_deleted integer;
begin
  if cardinality(v_ids) = 0 then return 0; end if;
  if (
    select count(*) from public.vehicle_inspection inspection_row
    where inspection_row.id = any(v_ids)
      and (app_private.is_platform_super() or inspection_row.tenant_id = app_private.current_user_tenant_id())
  ) <> cardinality(v_ids) then
    raise exception 'One or more vehicle inspection records are missing or outside the current tenant';
  end if;

  for v_inspection in
    select * from public.vehicle_inspection inspection_row where inspection_row.id = any(v_ids) for update
  loop
    if not app_private.can_execute_business_action(
      'VehicleInspection', 'VehicleInspection:Delete', v_inspection.created_by_user_id, true
    ) then
      raise exception 'Missing vehicle inspection delete permission' using errcode = '42501';
    end if;
  end loop;
  delete from public.vehicle_inspection inspection_row where inspection_row.id = any(v_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function public.vms_get_vehicle_inspection_expiry_context_secure(
  p_vehicle_id uuid default null,
  p_until date default null,
  p_limit integer default 30
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
    raise exception 'Missing vehicle inspection context permission' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', inspection_row.id,
    'vehicle_id', inspection_row.vehicle_id,
    'plate_no', inspection_row.plate_no,
    'company_name', inspection_row.company_name,
    'inspection_date', inspection_row.inspection_date,
    'expire_date', inspection_row.expire_date,
    'create_time', inspection_row.create_time
  ) order by inspection_row.expire_date, inspection_row.id), '[]'::jsonb)
  into v_result
  from (
    select inspection_record.*
    from public.vehicle_inspection inspection_record
    where (app_private.is_platform_super() or inspection_record.tenant_id = app_private.current_user_tenant_id())
      and (p_vehicle_id is null or inspection_record.vehicle_id = p_vehicle_id)
      and (p_until is null or inspection_record.expire_date <= p_until)
    order by inspection_record.expire_date, inspection_record.id
    limit least(greatest(coalesce(p_limit, 30), 1), 500)
  ) inspection_row;
  return v_result;
end;
$$;

revoke all on table public.vehicle_inspection from anon, authenticated;
drop policy if exists vehicle_inspection_tenant_select on public.vehicle_inspection;
drop policy if exists vehicle_inspection_tenant_insert on public.vehicle_inspection;
drop policy if exists vehicle_inspection_tenant_update on public.vehicle_inspection;
drop policy if exists vehicle_inspection_tenant_delete on public.vehicle_inspection;
create policy vehicle_inspection_secure_service_access on public.vehicle_inspection
for all to service_role using (true) with check (true);

revoke all on function app_private.seed_field_permission_catalog(uuid) from public, anon, authenticated;
grant execute on function app_private.seed_field_permission_catalog(uuid) to service_role;
revoke all on function app_private.set_vehicle_inspection_creator_identity() from public, anon, authenticated;
revoke all on function app_private.can_access_vms_vehicle_inspection_data() from public, anon, authenticated;
revoke all on function app_private.vehicle_inspection_to_secure_json(public.vehicle_inspection, jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_vms_vehicle_inspection_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.normalize_vms_vehicle_inspection_references(public.vehicle_inspection) from public, anon, authenticated;
grant execute on function app_private.set_vehicle_inspection_creator_identity() to service_role;
grant execute on function app_private.can_access_vms_vehicle_inspection_data() to service_role;
grant execute on function app_private.vehicle_inspection_to_secure_json(public.vehicle_inspection, jsonb) to service_role;
grant execute on function app_private.assert_vms_vehicle_inspection_payload_keys(jsonb) to service_role;
grant execute on function app_private.normalize_vms_vehicle_inspection_references(public.vehicle_inspection) to service_role;

revoke all on function public.vms_list_vehicle_inspections_secure(
  integer, integer, uuid, text, text, text, date, date, timestamptz, timestamptz, uuid[], text
) from public, anon;
revoke all on function public.vms_get_vehicle_inspection_secure(uuid) from public, anon;
revoke all on function public.vms_create_vehicle_inspection_secure(jsonb) from public, anon;
revoke all on function public.vms_update_vehicle_inspection_secure(uuid, jsonb) from public, anon;
revoke all on function public.vms_delete_vehicle_inspections_secure(uuid[]) from public, anon;
revoke all on function public.vms_get_vehicle_inspection_expiry_context_secure(uuid, date, integer) from public, anon;
grant execute on function public.vms_list_vehicle_inspections_secure(
  integer, integer, uuid, text, text, text, date, date, timestamptz, timestamptz, uuid[], text
) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_inspection_secure(uuid) to authenticated, service_role;
grant execute on function public.vms_create_vehicle_inspection_secure(jsonb) to authenticated, service_role;
grant execute on function public.vms_update_vehicle_inspection_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.vms_delete_vehicle_inspections_secure(uuid[]) to authenticated, service_role;
grant execute on function public.vms_get_vehicle_inspection_expiry_context_secure(uuid, date, integer) to authenticated, service_role;

;
