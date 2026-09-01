alter table public.vehicle_violation_record
  add column if not exists created_by_user_id uuid;

update public.vehicle_violation_record violation_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = violation_row.tenant_id
    and lower(user_row.user_email) = lower(violation_row.create_by)
    and user_row.deleted_at is null
  order by user_row.create_time, user_row.id
  limit 1
)
where violation_row.created_by_user_id is null
  and nullif(btrim(violation_row.create_by), '') is not null;

alter table public.vehicle_violation_record
  drop constraint if exists vehicle_violation_record_creator_tenant_fk;
alter table public.vehicle_violation_record
  add constraint vehicle_violation_record_creator_tenant_fk
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on update restrict on delete restrict;

create index if not exists vehicle_violation_record_creator_tenant_idx
  on public.vehicle_violation_record(created_by_user_id, tenant_id)
  where created_by_user_id is not null;

create or replace function app_private.set_vehicle_violation_creator_identity()
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

    if new.created_by_user_id is not null and not exists (
      select 1 from public.sys_user user_row
      where user_row.id = new.created_by_user_id and user_row.tenant_id = new.tenant_id
    ) then
      raise exception 'Vehicle violation creator is outside the record tenant'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Vehicle violation creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists vehicle_violation_creator_identity on public.vehicle_violation_record;
create trigger vehicle_violation_creator_identity
before insert or update on public.vehicle_violation_record
for each row execute function app_private.set_vehicle_violation_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
rename to seed_field_permission_catalog_before_vms_vehicle_violation;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_vms_vehicle_violation(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'vms.vehicle_violation', '车辆违章记录', 'VehicleViolation',
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
    (p_tenant_id, v_resource_id, 'driverIdentity', '违章驾驶员',
      'hidden', 'none', true, true, true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'violationLocation', '违章地点',
      'hidden', 'address', true, true, true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'violationNarrative', '违章行为与备注',
      'hidden', 'none', true, true, true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'penaltyAmounts', '扣分与罚款金额',
      'hidden', 'amount', true, true, true, 40, '624944977@qq.com', '624944977@qq.com')
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
  on menu_row.type = 'menu' and menu_row.name = 'VehicleViolation'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'vms.vehicle_violation'
  and resource_row.enabled and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_access_vms_vehicle_violation_data()
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
        and menu_row.name in ('VehicleViolation', 'VehicleQuery', 'VehicleQueryDetail')
        and app_private.can_access_business_menu(menu_row.name)
    );
$$;

create or replace function app_private.vehicle_violation_to_secure_json(
  p_violation public.vehicle_violation_record,
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
    app_private.field_access_map('vms.vehicle_violation', p_violation.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_violation) - 'tenant_id' - 'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'driverIdentity', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'driver_name';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{driver_name}', '"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'violationLocation', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'violation_location';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{violation_location}', coalesce(to_jsonb(
      app_private.mask_permission_value(p_violation.violation_location, 'address')
    ), 'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'violationNarrative', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'violation_behavior' - 'remark';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{violation_behavior}', '"***"'::jsonb);
    v_data := jsonb_set(v_data, '{remark}', '"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'penaltyAmounts', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'penalty_points' - 'fine_amount';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{penalty_points}', '"***"'::jsonb);
    v_data := jsonb_set(v_data, '{fine_amount}', '"***"'::jsonb);
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_violation.created_by_user_id is not null
      and p_violation.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.vms_list_vehicle_violations_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_vehicle_id uuid default null,
  p_company_name text default null,
  p_plate_no text default null,
  p_driver_name text default null,
  p_violation_behavior text default null,
  p_processed boolean default null,
  p_violation_time_from timestamptz default null,
  p_violation_time_to timestamptz default null,
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
    raise exception 'Invalid vehicle violation read purpose';
  end if;
  if p_purpose = 'export' then
    if not app_private.can_execute_business_action(
      'VehicleViolation', 'VehicleViolation:Export', null, false
    ) then
      raise exception 'Missing vehicle violation export permission' using errcode = '42501';
    end if;
  elsif not app_private.can_access_vms_vehicle_violation_data() then
    raise exception 'Missing vehicle violation read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select violation_row as violation_record
    from public.vehicle_violation_record violation_row
    where (app_private.is_platform_super() or violation_row.tenant_id = v_tenant_id)
      and (p_vehicle_id is null or violation_row.vehicle_id = p_vehicle_id)
      and (p_ids is null or violation_row.id = any(p_ids))
      and (nullif(btrim(p_company_name), '') is null or violation_row.company_name ilike '%' || btrim(p_company_name) || '%')
      and (nullif(btrim(p_plate_no), '') is null or violation_row.plate_no ilike '%' || btrim(p_plate_no) || '%')
      and (
        nullif(btrim(p_driver_name), '') is null
        or (
          app_private.resolve_field_access(
            'vms.vehicle_violation', 'driverIdentity', violation_row.created_by_user_id
          ) in ('read', 'edit')
          and violation_row.driver_name ilike '%' || btrim(p_driver_name) || '%'
        )
      )
      and (
        nullif(btrim(p_violation_behavior), '') is null
        or (
          app_private.resolve_field_access(
            'vms.vehicle_violation', 'violationNarrative', violation_row.created_by_user_id
          ) in ('read', 'edit')
          and violation_row.violation_behavior ilike '%' || btrim(p_violation_behavior) || '%'
        )
      )
      and (p_processed is null or violation_row.processed = p_processed)
      and (p_violation_time_from is null or violation_row.violation_time >= p_violation_time_from)
      and (p_violation_time_to is null or violation_row.violation_time <= p_violation_time_to)
  ), paged as (
    select filtered.violation_record
    from filtered
    order by (filtered.violation_record).violation_time desc, (filtered.violation_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.vehicle_violation_to_secure_json(paged.violation_record, null)
        order by (paged.violation_record).violation_time desc, (paged.violation_record).id
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', app_private.field_access_map('vms.vehicle_violation', null)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on table public.vehicle_violation_record from anon, authenticated;
drop policy if exists vehicle_violation_record_tenant_select on public.vehicle_violation_record;
drop policy if exists vehicle_violation_record_tenant_insert on public.vehicle_violation_record;
drop policy if exists vehicle_violation_record_tenant_update on public.vehicle_violation_record;
drop policy if exists vehicle_violation_record_tenant_delete on public.vehicle_violation_record;
drop policy if exists vehicle_violation_record_service_all on public.vehicle_violation_record;
create policy vehicle_violation_record_service_all
on public.vehicle_violation_record
for all to service_role
using (true) with check (true);

revoke all on function app_private.seed_field_permission_catalog(uuid) from public, anon, authenticated;
grant execute on function app_private.seed_field_permission_catalog(uuid) to service_role;
revoke all on function app_private.set_vehicle_violation_creator_identity() from public, anon, authenticated;
revoke all on function app_private.can_access_vms_vehicle_violation_data() from public, anon, authenticated;
revoke all on function app_private.vehicle_violation_to_secure_json(public.vehicle_violation_record, jsonb) from public, anon, authenticated;
grant execute on function app_private.set_vehicle_violation_creator_identity() to service_role;
grant execute on function app_private.can_access_vms_vehicle_violation_data() to service_role;
grant execute on function app_private.vehicle_violation_to_secure_json(public.vehicle_violation_record, jsonb) to service_role;

revoke all on function public.vms_list_vehicle_violations_secure(
  integer, integer, uuid, text, text, text, text, boolean,
  timestamptz, timestamptz, uuid[], text
) from public, anon;
grant execute on function public.vms_list_vehicle_violations_secure(
  integer, integer, uuid, text, text, text, text, boolean,
  timestamptz, timestamptz, uuid[], text
) to authenticated, service_role;

;
