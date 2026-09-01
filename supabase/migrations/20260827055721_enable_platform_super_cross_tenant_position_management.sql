-- Platform super administrators can manage business records across tenants while
-- ordinary tenant users remain constrained to their authenticated tenant and
-- explicit business permissions. In the all-tenant shell scope, the target
-- tenant is derived from the selected organization or the record being edited.

create or replace function app_private.resolve_organization_tenant_id(
  p_organization_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
begin
  if auth.uid() is null then
    raise exception '请先登录后再访问组织数据' using errcode = '42501';
  end if;

  select organization_row.tenant_id
  into v_tenant_id
  from public.sys_organization organization_row
  join public.sys_tenant tenant_row on tenant_row.id = organization_row.tenant_id
  where organization_row.id = p_organization_id
    and organization_row.status = '1'
    and tenant_row.status = '1'
    and tenant_row.builtin_type is distinct from 'platform'
    and (
      tenant_row.service_start_date is null
      or tenant_row.service_start_date <= (now() at time zone 'Asia/Shanghai')::date
    )
    and (
      tenant_row.service_end_date is null
      or tenant_row.service_end_date >= (now() at time zone 'Asia/Shanghai')::date
    );

  if v_tenant_id is null then
    raise exception '组织不存在、已停用或所属租户不在服务期' using errcode = '22023';
  end if;

  if not app_private.is_platform_super()
    and v_tenant_id <> app_private.current_user_tenant_id() then
    raise exception '组织超出当前租户范围' using errcode = '42501';
  end if;

  return v_tenant_id;
end;
$$;

revoke all on function app_private.resolve_organization_tenant_id(uuid)
  from public, anon, authenticated, service_role;

create or replace function app_private.smis_set_position_scope_tenant()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
begin
  if auth.uid() is null then
    raise exception '请先登录后再维护岗位数据' using errcode = '42501';
  end if;

  v_tenant_id := app_private.resolve_organization_tenant_id(new.organization_id);

  if not exists (
    select 1
    from public.hr_position position_row
    where position_row.id = new.position_id
      and position_row.tenant_id = v_tenant_id
      and position_row.enabled
  ) then
    raise exception '岗位不存在、已停用或与所选组织不属于同一租户'
      using errcode = '22023';
  end if;

  new.tenant_id := v_tenant_id;
  return new;
end;
$$;

revoke all on function app_private.smis_set_position_scope_tenant()
  from public, anon, authenticated, service_role;

drop trigger if exists smis_position_safety_responsibility_tenant_guard
  on public.smis_position_safety_responsibility;
create trigger smis_position_safety_responsibility_tenant_guard
before insert or update
on public.smis_position_safety_responsibility
for each row
execute function app_private.smis_set_position_scope_tenant();

drop trigger if exists smis_position_risk_control_tenant_guard
  on public.smis_position_risk_control;
create trigger smis_position_risk_control_tenant_guard
before insert or update
on public.smis_position_risk_control
for each row
execute function app_private.smis_set_position_scope_tenant();

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
as $$
declare
  v_is_platform_super boolean := app_private.is_platform_super();
  v_tenant_id uuid;
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

  v_tenant_id := case
    when p_organization_id is not null
      then app_private.resolve_organization_tenant_id(p_organization_id)
    when v_is_platform_super then null
    else app_private.current_user_tenant_id()
  end;

  v_limit := least(
    500,
    greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select
      position_row.id,
      position_row.tenant_id,
      position_row.position_code,
      position_row.position_name,
      position_row.position_kind,
      position_row.description,
      position_row.sort,
      (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.tenant_id = position_row.tenant_id
          and employee_row.position_id = position_row.id
          and employee_row.employment_status <> 'terminated'
          and (
            p_organization_id is null
            or employee_row.organization_id = p_organization_id
          )
      )::integer as employee_count
    from public.hr_position position_row
    where (v_tenant_id is null or position_row.tenant_id = v_tenant_id)
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
          where headcount_row.tenant_id = position_row.tenant_id
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
          where employee_row.tenant_id = position_row.tenant_id
            and employee_row.position_id = position_row.id
            and employee_row.organization_id = p_organization_id
            and employee_row.employment_status <> 'terminated'
        )
        or exists (
          select 1
          from public.smis_position_safety_responsibility responsibility_row
          where responsibility_row.tenant_id = position_row.tenant_id
            and responsibility_row.position_id = position_row.id
            and responsibility_row.organization_id = p_organization_id
        )
      )
  ), paged as (
    select *
    from filtered
    order by tenant_id, sort, position_name, position_code
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(to_jsonb(paged) order by tenant_id, sort, position_name, position_code)
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.smis_list_risk_positions_secure(
  p_organization_id uuid,
  p_from integer default 0,
  p_to integer default 499,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionRiskList',
    'SmisPositionRiskList:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS position risk list view permission'
      using errcode = '42501';
  end if;

  v_tenant_id := app_private.resolve_organization_tenant_id(p_organization_id);
  v_limit := least(
    500,
    greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select
      position_row.id,
      position_row.tenant_id,
      position_row.position_code,
      position_row.position_name,
      position_row.position_kind,
      position_row.description,
      position_row.sort,
      (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.tenant_id = position_row.tenant_id
          and employee_row.organization_id = p_organization_id
          and employee_row.position_id = position_row.id
          and employee_row.employment_status <> 'terminated'
      )::integer as employee_count,
      (
        select count(*)
        from public.smis_position_risk_control risk_row
        where risk_row.tenant_id = position_row.tenant_id
          and risk_row.organization_id = p_organization_id
          and risk_row.position_id = position_row.id
      )::integer as control_count
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
        exists (
          select 1
          from public.hr_position_headcount headcount_row
          where headcount_row.tenant_id = position_row.tenant_id
            and headcount_row.organization_id = p_organization_id
            and headcount_row.position_id = position_row.id
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
          where employee_row.tenant_id = position_row.tenant_id
            and employee_row.organization_id = p_organization_id
            and employee_row.position_id = position_row.id
            and employee_row.employment_status <> 'terminated'
        )
        or exists (
          select 1
          from public.smis_position_risk_control risk_row
          where risk_row.tenant_id = position_row.tenant_id
            and risk_row.organization_id = p_organization_id
            and risk_row.position_id = position_row.id
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
$$;

create or replace function public.smis_list_position_work_instructions_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_file_type text default null,
  p_organization_id uuid default null,
  p_position_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_is_platform_super boolean := app_private.is_platform_super();
  v_tenant_id uuid;
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionWorkInstruction',
    'SmisPositionWorkInstruction:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS work instruction view permission' using errcode = '42501';
  end if;

  v_tenant_id := case
    when p_organization_id is not null
      then app_private.resolve_organization_tenant_id(p_organization_id)
    when v_is_platform_super then null
    else app_private.current_user_tenant_id()
  end;
  v_limit := least(
    200,
    greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select instruction_row.*
    from public.smis_position_work_instruction instruction_row
    where (v_tenant_id is null or instruction_row.tenant_id = v_tenant_id)
      and (
        nullif(btrim(p_keyword), '') is null
        or instruction_row.instruction_name ilike '%' || btrim(p_keyword) || '%'
        or coalesce(instruction_row.file_number, '') ilike '%' || btrim(p_keyword) || '%'
        or coalesce(instruction_row.version_no, '') ilike '%' || btrim(p_keyword) || '%'
      )
      and (
        nullif(btrim(p_file_type), '') is null
        or instruction_row.file_type ilike '%' || btrim(p_file_type) || '%'
      )
      and (
        p_organization_id is null
        or exists (
          select 1
          from public.smis_position_work_instruction_scope scope_row
          where scope_row.instruction_id = instruction_row.id
            and scope_row.tenant_id = instruction_row.tenant_id
            and scope_row.organization_id = p_organization_id
            and (p_position_id is null or scope_row.position_id = p_position_id)
        )
      )
  ), paged as (
    select *
    from filtered
    order by tenant_id, update_time desc, instruction_name
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        to_jsonb(paged) || jsonb_build_object(
          'scopes', coalesce((
            select jsonb_agg(jsonb_build_object(
              'scope_key', 'scope:' || scope_row.organization_id::text || ':' || scope_row.position_id::text,
              'organization_id', scope_row.organization_id,
              'organization_name', organization_row.organization_name,
              'organization_code', organization_row.organization_code,
              'position_id', scope_row.position_id,
              'position_name', position_row.position_name,
              'position_code', position_row.position_code
            ) order by organization_row.sort, organization_row.organization_name, position_row.sort, position_row.position_name)
            from public.smis_position_work_instruction_scope scope_row
            join public.sys_organization organization_row
              on organization_row.id = scope_row.organization_id
             and organization_row.tenant_id = scope_row.tenant_id
            join public.hr_position position_row
              on position_row.id = scope_row.position_id
             and position_row.tenant_id = scope_row.tenant_id
            where scope_row.instruction_id = paged.id
              and scope_row.tenant_id = paged.tenant_id
          ), '[]'::jsonb)
        ) order by paged.tenant_id, paged.update_time desc, paged.instruction_name
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

create or replace function public.smis_save_position_work_instruction_secure(
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_tenant_id uuid;
  v_scope_tenant_id uuid;
  v_instruction_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_is_edit boolean := v_instruction_id is not null;
  v_is_platform_super boolean := app_private.is_platform_super();
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), 'unknown');
  v_scopes jsonb := coalesce(p_payload -> 'scopes', '[]'::jsonb);
begin
  if jsonb_typeof(v_scopes) <> 'array' or jsonb_array_length(v_scopes) = 0 then
    raise exception '请至少选择一个适用组织岗位' using errcode = '22023';
  end if;

  if not app_private.can_execute_business_action(
    'SmisPositionWorkInstruction',
    case when v_is_edit
      then 'SmisPositionWorkInstruction:Edit'
      else 'SmisPositionWorkInstruction:Add'
    end,
    null,
    true
  ) then
    raise exception 'Missing SMIS work instruction write permission' using errcode = '42501';
  end if;

  if nullif(btrim(p_payload ->> 'instruction_name'), '') is null then
    raise exception '作业指导名称不能为空' using errcode = '22023';
  end if;

  select app_private.resolve_organization_tenant_id(
    nullif(scope_item ->> 'organization_id', '')::uuid
  )
  into v_scope_tenant_id
  from jsonb_array_elements(v_scopes) scope_item
  limit 1;

  if v_is_edit then
    select instruction_row.tenant_id
    into v_tenant_id
    from public.smis_position_work_instruction instruction_row
    where instruction_row.id = v_instruction_id
      and (v_is_platform_super or instruction_row.tenant_id = v_current_tenant_id)
    for update;

    if v_tenant_id is null then
      raise exception '作业指导书不存在或超出当前租户范围' using errcode = 'P0002';
    end if;

    if v_scope_tenant_id <> v_tenant_id then
      raise exception '作业指导书不能跨租户变更适用范围' using errcode = '22023';
    end if;
  else
    v_tenant_id := v_scope_tenant_id;
  end if;

  if exists (
    select 1
    from (
      select distinct
        nullif(scope_item ->> 'organization_id', '')::uuid as organization_id,
        nullif(scope_item ->> 'position_id', '')::uuid as position_id
      from jsonb_array_elements(v_scopes) scope_item
    ) selected_scope
    where selected_scope.organization_id is null
       or selected_scope.position_id is null
       or not exists (
         select 1
         from public.sys_organization organization_row
         join public.hr_position position_row
           on position_row.id = selected_scope.position_id
          and position_row.tenant_id = v_tenant_id
          and position_row.enabled
         where organization_row.id = selected_scope.organization_id
           and organization_row.tenant_id = v_tenant_id
           and organization_row.status = '1'
           and (
             position_row.organization_id = organization_row.id
             or exists (
               select 1
               from public.hr_position_headcount headcount_row
               where headcount_row.tenant_id = v_tenant_id
                 and headcount_row.organization_id = organization_row.id
                 and headcount_row.position_id = position_row.id
                 and headcount_row.enabled
             )
             or exists (
               select 1
               from public.hr_employee employee_row
               where employee_row.tenant_id = v_tenant_id
                 and employee_row.organization_id = organization_row.id
                 and employee_row.position_id = position_row.id
                 and employee_row.employment_status <> 'terminated'
             )
             or exists (
               select 1
               from public.smis_position_work_instruction_scope existing_scope
               where existing_scope.tenant_id = v_tenant_id
                 and existing_scope.organization_id = organization_row.id
                 and existing_scope.position_id = position_row.id
             )
           )
       )
  ) then
    raise exception '适用组织岗位不存在、已停用、跨租户或超出当前账号范围'
      using errcode = '42501';
  end if;

  if v_is_edit then
    update public.smis_position_work_instruction
    set instruction_name = btrim(p_payload ->> 'instruction_name'),
        file_number = nullif(btrim(p_payload ->> 'file_number'), ''),
        file_type = nullif(btrim(p_payload ->> 'file_type'), ''),
        upload_date = nullif(p_payload ->> 'upload_date', '')::date,
        version_no = nullif(btrim(p_payload ->> 'version_no'), ''),
        file_url = nullif(btrim(p_payload ->> 'file_url'), ''),
        original_file_name = nullif(btrim(p_payload ->> 'original_file_name'), ''),
        update_by = v_actor,
        update_time = now()
    where id = v_instruction_id
      and tenant_id = v_tenant_id;

    delete from public.smis_position_work_instruction_scope
    where instruction_id = v_instruction_id
      and tenant_id = v_tenant_id;
  else
    insert into public.smis_position_work_instruction (
      tenant_id,
      instruction_name,
      file_number,
      file_type,
      upload_date,
      version_no,
      file_url,
      original_file_name,
      create_by,
      update_by
    ) values (
      v_tenant_id,
      btrim(p_payload ->> 'instruction_name'),
      nullif(btrim(p_payload ->> 'file_number'), ''),
      nullif(btrim(p_payload ->> 'file_type'), ''),
      nullif(p_payload ->> 'upload_date', '')::date,
      nullif(btrim(p_payload ->> 'version_no'), ''),
      nullif(btrim(p_payload ->> 'file_url'), ''),
      nullif(btrim(p_payload ->> 'original_file_name'), ''),
      v_actor,
      v_actor
    )
    returning id into v_instruction_id;
  end if;

  insert into public.smis_position_work_instruction_scope (
    tenant_id,
    instruction_id,
    organization_id,
    position_id,
    create_by
  )
  select distinct
    v_tenant_id,
    v_instruction_id,
    nullif(scope_item ->> 'organization_id', '')::uuid,
    nullif(scope_item ->> 'position_id', '')::uuid,
    v_actor
  from jsonb_array_elements(v_scopes) scope_item;

  return v_instruction_id;
end;
$$;

create or replace function public.smis_delete_position_work_instructions_secure(
  p_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_platform_super boolean := app_private.is_platform_super();
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_deleted integer;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionWorkInstruction',
    'SmisPositionWorkInstruction:Delete',
    null,
    true
  ) then
    raise exception 'Missing SMIS work instruction delete permission' using errcode = '42501';
  end if;

  delete from public.smis_position_work_instruction instruction_row
  where instruction_row.id = any(coalesce(p_ids, array[]::uuid[]))
    and (v_is_platform_super or instruction_row.tenant_id = v_tenant_id);

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

;
