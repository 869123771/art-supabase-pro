alter table public.hr_position
  add column if not exists parent_id uuid null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.hr_position'::regclass
      and conname = 'hr_position_parent_id_fkey'
  ) then
    alter table public.hr_position
      add constraint hr_position_parent_id_fkey
      foreign key (parent_id) references public.hr_position(id) on delete restrict;
  end if;
end;
$$;

create index if not exists idx_hr_position_parent_id
  on public.hr_position(parent_id);

create or replace function app_private.validate_hr_position_parent()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_parent_tenant_id uuid;
begin
  if new.parent_id is null then
    return new;
  end if;

  if new.parent_id = new.id then
    raise exception '上级岗位不能选择当前岗位';
  end if;

  select position_row.tenant_id
  into v_parent_tenant_id
  from public.hr_position position_row
  where position_row.id = new.parent_id;

  if v_parent_tenant_id is null then
    raise exception '上级岗位不存在';
  end if;
  if v_parent_tenant_id <> new.tenant_id then
    raise exception '上级岗位必须与当前岗位属于同一租户';
  end if;

  if tg_op = 'UPDATE' and exists (
    with recursive descendants as (
      select position_row.id
      from public.hr_position position_row
      where position_row.parent_id = new.id
      union all
      select child_row.id
      from public.hr_position child_row
      join descendants parent_row on child_row.parent_id = parent_row.id
    )
    select 1 from descendants where id = new.parent_id
  ) then
    raise exception '上级岗位不能选择当前岗位的下级岗位';
  end if;

  return new;
end;
$function$;

revoke all on function app_private.validate_hr_position_parent() from public;

drop trigger if exists hr_position_validate_parent on public.hr_position;
create trigger hr_position_validate_parent
before insert or update of parent_id, tenant_id on public.hr_position
for each row
execute function app_private.validate_hr_position_parent();

create or replace function public.hr_create_position_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_id uuid;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:Add', null, false) then
    raise exception 'Missing position create permission' using errcode = '42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception '岗位数据格式不正确';
  end if;
  if exists (
    select 1
    from jsonb_object_keys(p_payload) key
    where key <> all(array[
      'tenant_id','parent_id','position_code','position_name','enabled','sort','description'
    ]::text[])
  ) then
    raise exception '岗位数据包含不允许写入的字段';
  end if;

  v_tenant_id := case when app_private.is_platform_super()
    then nullif(p_payload->>'tenant_id', '')::uuid
    else app_private.current_user_tenant_id()
  end;
  if v_tenant_id is null then raise exception '请选择岗位所属租户'; end if;

  insert into public.hr_position (
    tenant_id, parent_id, position_code, position_name, enabled, sort, description, create_by
  ) values (
    v_tenant_id,
    nullif(p_payload->>'parent_id', '')::uuid,
    upper(btrim(p_payload->>'position_code')),
    btrim(p_payload->>'position_name'),
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort')::integer, 0),
    nullif(btrim(p_payload->>'description'), ''),
    coalesce(auth.uid()::text, 'system')
  )
  returning id into v_id;

  return v_id;
end;
$function$;

create or replace function public.hr_update_position_secure(p_id uuid, p_payload jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:Edit', null, false) then
    raise exception 'Missing position edit permission' using errcode = '42501';
  end if;
  select * into v_position from public.hr_position where id = p_id;
  if not found or (
    not app_private.is_platform_super()
    and v_position.tenant_id <> app_private.current_user_tenant_id()
  ) then
    raise exception '岗位不存在或无权编辑';
  end if;
  if exists (
    select 1
    from jsonb_object_keys(p_payload) key
    where key <> all(array[
      'parent_id','position_code','position_name','enabled','sort','description'
    ]::text[])
  ) then
    raise exception '岗位数据包含不允许写入的字段';
  end if;
  if v_position.system_code = 'driver' and (
    coalesce((p_payload->>'enabled')::boolean, v_position.enabled) = false
    or upper(coalesce(nullif(btrim(p_payload->>'position_code'), ''), v_position.position_code))
      <> v_position.position_code
  ) then
    raise exception '系统司机岗位不可停用或修改编码';
  end if;

  update public.hr_position position_row
  set parent_id = case
        when p_payload ? 'parent_id' then nullif(p_payload->>'parent_id', '')::uuid
        else position_row.parent_id
      end,
      position_code = upper(coalesce(
        nullif(btrim(p_payload->>'position_code'), ''),
        position_row.position_code
      )),
      position_name = coalesce(
        nullif(btrim(p_payload->>'position_name'), ''),
        position_row.position_name
      ),
      enabled = coalesce((p_payload->>'enabled')::boolean, position_row.enabled),
      sort = coalesce((p_payload->>'sort')::integer, position_row.sort),
      description = case
        when p_payload ? 'description' then nullif(btrim(p_payload->>'description'), '')
        else position_row.description
      end,
      update_by = coalesce(auth.uid()::text, 'system'),
      update_time = now()
  where position_row.id = p_id;

  update public.hr_employee employee_row
  set job_title = position_row.position_name,
      update_time = now()
  from public.hr_position position_row
  where position_row.id = p_id
    and employee_row.position_id = position_row.id
    and employee_row.tenant_id = position_row.tenant_id;

  return true;
end;
$function$;

create or replace function public.hr_delete_position_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:Delete', null, false) then
    raise exception 'Missing position delete permission' using errcode = '42501';
  end if;
  select * into v_position from public.hr_position where id = p_id;
  if not found or (
    not app_private.is_platform_super()
    and v_position.tenant_id <> app_private.current_user_tenant_id()
  ) then
    raise exception '岗位不存在或无权删除';
  end if;
  if v_position.system_code is not null then raise exception '系统岗位不可删除'; end if;
  if exists (select 1 from public.hr_position where parent_id = p_id) then
    raise exception '该岗位仍有下级岗位，请先调整岗位层级';
  end if;
  if exists (select 1 from public.hr_employee where position_id = p_id) then
    raise exception '该岗位已有员工使用，请先调整员工岗位';
  end if;
  delete from public.hr_position where id = p_id;
  return true;
end;
$function$;

create or replace function public.hr_list_position_options_secure(
  p_tenant_id uuid default null,
  p_include_disabled boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.can_execute_business_action('HrEmployeeRoster', 'Hr:Employee:Add', null, false)
    or app_private.can_execute_business_action('HrEmployeeRoster', 'Hr:Employee:Edit', null, false)
    or app_private.can_execute_business_action('HrPosition', 'Hr:Position:View', null, false)
  ) then
    raise exception 'Missing employee or position permission' using errcode = '42501';
  end if;

  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  if p_tenant_id is null then return '[]'::jsonb; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', position_row.id,
      'tenant_id', position_row.tenant_id,
      'parent_id', position_row.parent_id,
      'position_code', position_row.position_code,
      'position_name', position_row.position_name,
      'position_kind', position_row.position_kind,
      'system_code', position_row.system_code,
      'enabled', position_row.enabled,
      'sort', position_row.sort,
      'description', position_row.description
    ) order by position_row.sort, position_row.position_name)
    from public.hr_position position_row
    where position_row.tenant_id = p_tenant_id
      and (p_include_disabled or position_row.enabled)
  ), '[]'::jsonb);
end;
$function$;

create or replace function public.hr_list_positions_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_enabled boolean default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:View', null, false) then
    raise exception 'Missing position view permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  v_limit := least(
    2000,
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select
      position_row.*,
      tenant_row.tenant_code,
      tenant_row.tenant_name,
      (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.position_id = position_row.id
          and employee_row.tenant_id = position_row.tenant_id
          and employee_row.employment_status <> 'terminated'
      ) as employee_count
    from public.hr_position position_row
    join public.sys_tenant tenant_row on tenant_row.id = position_row.tenant_id
    where (p_tenant_id is null or position_row.tenant_id = p_tenant_id)
      and (p_enabled is null or position_row.enabled = p_enabled)
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or position_row.description ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select *
    from filtered
    order by tenant_name, sort, position_name
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        (to_jsonb(paged) - 'tenant_code' - 'tenant_name') || jsonb_build_object(
          'tenant', jsonb_build_object(
            'id', paged.tenant_id,
            'tenant_code', paged.tenant_code,
            'tenant_name', paged.tenant_name
          )
        )
        order by tenant_name, sort, position_name
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$function$;

create or replace function public.hr_get_organization_position_directory_secure(
  p_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
  v_employee_total bigint;
  v_employee_limit integer := 2000;
begin
  if not app_private.can_execute_business_action(
    'HrOrganizationPosition',
    'Hr:OrganizationPosition:View',
    null,
    false
  ) then
    raise exception 'Missing organization position directory view permission'
      using errcode = '42501';
  end if;

  select organization_row.tenant_id
  into v_target_tenant_id
  from public.sys_organization organization_row
  where organization_row.id = p_organization_id
    and organization_row.status = '1';

  if v_target_tenant_id is null
    or (
      not app_private.is_platform_super()
      and v_target_tenant_id <> v_current_tenant_id
    )
  then
    raise exception '组织不存在、已停用或超出当前租户范围' using errcode = '42501';
  end if;

  select count(*)
  into v_employee_total
  from public.hr_employee employee_row
  where employee_row.tenant_id = v_target_tenant_id
    and employee_row.organization_id = p_organization_id
    and employee_row.employment_status <> 'terminated';

  return (
    with recursive eligible_positions as (
      select position_row.id, position_row.parent_id
      from public.hr_position position_row
      where position_row.tenant_id = v_target_tenant_id
        and position_row.enabled
        and (
          exists (
            select 1
            from public.hr_employee employee_row
            where employee_row.tenant_id = v_target_tenant_id
              and employee_row.organization_id = p_organization_id
              and employee_row.position_id = position_row.id
              and employee_row.employment_status <> 'terminated'
          )
          or exists (
            select 1
            from public.hr_position_headcount headcount_row
            where headcount_row.tenant_id = v_target_tenant_id
              and headcount_row.organization_id = p_organization_id
              and headcount_row.position_id = position_row.id
              and headcount_row.enabled
              and headcount_row.effective_from <= current_date
              and (
                headcount_row.effective_to is null
                or headcount_row.effective_to >= current_date
              )
          )
        )
    ), selected_positions as (
      select id, parent_id from eligible_positions
      union
      select parent_row.id, parent_row.parent_id
      from public.hr_position parent_row
      join selected_positions child_row on parent_row.id = child_row.parent_id
      where parent_row.tenant_id = v_target_tenant_id
    ), position_records as (
      select
        position_row.id,
        position_row.tenant_id,
        position_row.parent_id,
        position_row.position_code,
        position_row.position_name,
        position_row.position_kind,
        position_row.system_code,
        position_row.enabled,
        position_row.sort,
        position_row.description,
        (
          select count(*)
          from public.hr_employee employee_row
          where employee_row.tenant_id = v_target_tenant_id
            and employee_row.organization_id = p_organization_id
            and employee_row.position_id = position_row.id
            and employee_row.employment_status <> 'terminated'
        )::integer as employee_count
      from public.hr_position position_row
      where position_row.id in (select id from selected_positions)
    ), employee_records as (
      select
        employee_row.id,
        employee_row.organization_id,
        employee_row.position_id,
        employee_row.employee_no,
        employee_row.employee_name,
        employee_row.avatar_url,
        employee_row.job_title,
        employee_row.employment_status,
        employee_row.employment_type,
        employee_row.hire_date
      from public.hr_employee employee_row
      where employee_row.tenant_id = v_target_tenant_id
        and employee_row.organization_id = p_organization_id
        and employee_row.employment_status <> 'terminated'
      order by employee_row.employee_name, employee_row.employee_no
      limit v_employee_limit
    )
    select jsonb_build_object(
      'positions', coalesce((
        select jsonb_agg(to_jsonb(position_records) order by sort, position_name, position_code)
        from position_records
      ), '[]'::jsonb),
      'employees', coalesce((
        select jsonb_agg(to_jsonb(employee_records) order by employee_name, employee_no)
        from employee_records
      ), '[]'::jsonb),
      'employee_total', v_employee_total,
      'truncated', v_employee_total > v_employee_limit
    )
  );
end;
$function$;

create or replace function public.smis_list_positions_secure(
  p_from integer default 0,
  p_to integer default 499,
  p_keyword text default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionSafetyResponsibility',
    'SmisPositionSafetyResponsibility:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS position safety responsibility view permission'
      using errcode = '42501';
  end if;

  if p_organization_id is not null and not exists (
    select 1
    from public.sys_organization organization_row
    where organization_row.id = p_organization_id
      and organization_row.tenant_id = v_tenant_id
      and organization_row.status = '1'
  ) then
    raise exception 'Organization is outside the current tenant or unavailable'
      using errcode = '42501';
  end if;

  v_limit := least(
    500,
    greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with recursive eligible as materialized (
    select
      position_row.id,
      position_row.parent_id
    from public.hr_position position_row
    where position_row.tenant_id = v_tenant_id
      and position_row.enabled
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or coalesce(position_row.description, '') ilike '%' || btrim(p_keyword) || '%'
      )
      and (
        p_organization_id is null
        or exists (
          select 1
          from public.hr_position_headcount headcount_row
          where headcount_row.tenant_id = v_tenant_id
            and headcount_row.position_id = position_row.id
            and headcount_row.organization_id = p_organization_id
            and headcount_row.enabled
            and headcount_row.effective_from <= current_date
            and (
              headcount_row.effective_to is null
              or headcount_row.effective_to >= current_date
            )
        )
        or exists (
          select 1
          from public.hr_employee employee_row
          where employee_row.tenant_id = v_tenant_id
            and employee_row.position_id = position_row.id
            and employee_row.organization_id = p_organization_id
            and employee_row.employment_status <> 'terminated'
        )
        or exists (
          select 1
          from public.smis_position_safety_responsibility responsibility_row
          where responsibility_row.tenant_id = v_tenant_id
            and responsibility_row.position_id = position_row.id
            and responsibility_row.organization_id = p_organization_id
        )
      )
  ), selected_positions as (
    select id, parent_id from eligible
    union
    select parent_row.id, parent_row.parent_id
    from public.hr_position parent_row
    join selected_positions child_row on parent_row.id = child_row.parent_id
    where parent_row.tenant_id = v_tenant_id
  ), filtered as materialized (
    select
      position_row.id,
      position_row.parent_id,
      position_row.position_code,
      position_row.position_name,
      position_row.position_kind,
      position_row.description,
      position_row.sort,
      (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.tenant_id = v_tenant_id
          and employee_row.position_id = position_row.id
          and employee_row.employment_status <> 'terminated'
          and (
            p_organization_id is null
            or employee_row.organization_id = p_organization_id
          )
      )::integer as employee_count
    from public.hr_position position_row
    where position_row.id in (select id from selected_positions)
  ), paged as (
    select *
    from filtered
    order by sort, position_name, position_code
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(to_jsonb(paged) order by sort, position_name, position_code)
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$function$;

revoke all on function public.hr_get_organization_position_directory_secure(uuid) from public;
revoke all on function public.hr_get_organization_position_directory_secure(uuid) from anon;
grant execute on function public.hr_get_organization_position_directory_secure(uuid)
  to authenticated, service_role;

do $$
begin
  if not exists (
    select 1
    from public.sys_menu
    where id = '71c46d59-3f0e-410d-9f26-9f96d34163b0'::uuid
  ) then
    update public.sys_menu
    set sort = sort + 1,
        update_by = '624944977@qq.com',
        update_time = now()
    where parent_id = 'aa71d8bd-c141-4aef-9697-8e75433de2c2'::uuid
      and type = 'menu'
      and sort >= 2;
  end if;
end;
$$;

insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort, type, app_code,
  create_by, update_by
) values (
  '71c46d59-3f0e-410d-9f26-9f96d34163b0'::uuid,
  'aa71d8bd-c141-4aef-9697-8e75433de2c2'::uuid,
  'HrOrganizationPosition',
  'organization-position',
  '/hr/personnel/organization-position',
  jsonb_build_object(
    'title', '组织岗位人员',
    'icon', 'ri:organization-chart',
    'is_hide', false,
    'is_enable', true,
    'keep_alive', true,
    'is_iframe', false,
    'fixed_tab', false,
    'show_badge', false,
    'show_text_badge', '',
    'is_hide_tab', false,
    'is_full_page', false,
    'active_path', '',
    'link', '',
    'roles', jsonb_build_array('R_SUPER', 'R_ADMIN')
  ),
  2,
  'menu',
  'hr',
  '624944977@qq.com',
  '624944977@qq.com'
)
on conflict (id) do update
set parent_id = excluded.parent_id,
    name = excluded.name,
    path = excluded.path,
    component = excluded.component,
    meta = excluded.meta,
    sort = excluded.sort,
    type = excluded.type,
    app_code = excluded.app_code,
    update_by = excluded.update_by,
    update_time = now();

insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort, type, app_code,
  create_by, update_by
) values (
  '71c46d59-3f0e-410d-9f26-9f96d34163b1'::uuid,
  '71c46d59-3f0e-410d-9f26-9f96d34163b0'::uuid,
  'Hr:OrganizationPosition:View',
  '',
  '',
  jsonb_build_object(
    'title', '查看组织岗位人员',
    'icon', '',
    'is_hide', true,
    'is_enable', true,
    'roles', jsonb_build_array()
  ),
  1,
  'button',
  'hr',
  '624944977@qq.com',
  '624944977@qq.com'
)
on conflict (id) do update
set parent_id = excluded.parent_id,
    name = excluded.name,
    meta = excluded.meta,
    sort = excluded.sort,
    type = excluded.type,
    app_code = excluded.app_code,
    update_by = excluded.update_by,
    update_time = now();

insert into public.sys_role_menu (
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select
  employee_view_grant.role_id,
  new_menu.menu_id,
  employee_view_grant.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu employee_view_grant
cross join (
  values
    ('71c46d59-3f0e-410d-9f26-9f96d34163b0'::uuid),
    ('71c46d59-3f0e-410d-9f26-9f96d34163b1'::uuid)
) as new_menu(menu_id)
where employee_view_grant.menu_id = '83d8eb9e-7de4-4609-bfee-44c4563039bc'::uuid
on conflict (role_id, menu_id) do nothing;

;
