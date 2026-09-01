-- User-requested correction: positions remain a flat master-data list.
-- Only the organization -> position -> employee read-only directory is retained.

drop trigger if exists hr_position_validate_parent on public.hr_position;
drop function if exists app_private.validate_hr_position_parent();

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
      'tenant_id','position_code','position_name','enabled','sort','description'
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
    tenant_id, position_code, position_name, enabled, sort, description, create_by
  ) values (
    v_tenant_id,
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
      'position_code','position_name','enabled','sort','description'
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
  set position_code = upper(coalesce(
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
      'position_code', position_row.position_code,
      'position_name', position_row.position_name,
      'position_kind', position_row.position_kind,
      'system_code', position_row.system_code,
      'enabled', position_row.enabled
    ) order by position_row.sort, position_row.position_name)
    from public.hr_position position_row
    where position_row.tenant_id = p_tenant_id
      and (p_include_disabled or position_row.enabled)
  ), '[]'::jsonb);
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
    with position_records as (
      select
        position_row.id,
        position_row.tenant_id,
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

  with filtered as materialized (
    select
      position_row.id,
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

drop index if exists public.idx_hr_position_parent_id;
alter table public.hr_position drop column if exists parent_id;

;
