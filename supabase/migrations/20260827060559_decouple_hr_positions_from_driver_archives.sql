-- 岗位只描述 HR 组织任职关系；司机档案由 TMS 司机管理独立维护。
-- 保留历史列以兼容既有数据和下游查询，但统一归一为普通岗位语义。
update public.hr_position
set
  position_kind = 'standard',
  system_code = null,
  update_time = now(),
  update_by = '624944977@qq.com'
where position_kind is distinct from 'standard'
   or system_code is not null;

comment on column public.hr_position.position_kind is
  '兼容历史数据的保留列；岗位不再区分司机岗位，值固定为 standard。';
comment on column public.hr_position.system_code is
  '兼容历史数据的保留列；岗位不再承担司机系统岗位语义，值固定为空。';

create or replace function app_private.sync_hr_employee_position_title()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
  v_job_profile public.hr_job_profile%rowtype;
begin
  select * into v_position
  from public.hr_position position_row
  where position_row.id = new.position_id
    and position_row.tenant_id = new.tenant_id;

  if not found then raise exception '所选岗位不存在或不属于员工所在租户'; end if;
  if not v_position.enabled then raise exception '所选岗位已停用'; end if;
  if v_position.organization_id is not null
     and new.organization_id is distinct from v_position.organization_id then
    raise exception '所选岗位不属于员工所在组织';
  end if;

  select * into v_job_profile
  from public.hr_job_profile profile_row
  where profile_row.id = v_position.job_profile_id
    and profile_row.tenant_id = v_position.tenant_id;
  new.job_title := v_job_profile.job_name;
  return new;
end;
$function$;

create or replace function public.hr_create_employee_with_driver_secure(
  p_employee jsonb,
  p_driver jsonb default null::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_employee public.hr_employee%rowtype;
  v_tenant_id uuid;
  v_employee_id uuid;
begin
  if not app_private.can_execute_business_action(
    'HrEmployeeRoster', 'Hr:Employee:Add', null, false
  ) then
    raise exception 'Missing employee create permission' using errcode = '42501';
  end if;
  if p_employee is null or jsonb_typeof(p_employee) <> 'object' then
    raise exception '员工数据格式不正确';
  end if;
  if p_driver is not null and p_driver <> 'null'::jsonb then
    raise exception '员工档案不再创建司机档案，请前往司机管理从员工花名册选取';
  end if;
  if exists (
    select 1
    from jsonb_object_keys(p_employee) key
    where key <> all(array[
      'tenant_id','organization_id','employee_no','employee_name','avatar_url','position_id',
      'employment_status','employment_type','gender','birth_date','phone','email','id_card_no',
      'ethnicity','education_level','school_name','major_name','marital_status','political_status',
      'native_place','home_address','hire_date','probation_end_date','leave_date',
      'contract_start_date','contract_end_date','emergency_contact_name',
      'emergency_contact_relation','emergency_contact_phone','remark'
    ]::text[])
  ) then
    raise exception '员工数据包含不允许写入的字段';
  end if;

  select * into v_employee
  from jsonb_populate_record(null::public.hr_employee, p_employee);
  v_tenant_id := case when app_private.is_platform_super()
    then v_employee.tenant_id
    else app_private.current_user_tenant_id()
  end;
  if v_tenant_id is null then raise exception '请选择员工所属租户'; end if;

  if not exists (
    select 1
    from public.hr_position position_row
    where position_row.id = v_employee.position_id
      and position_row.tenant_id = v_tenant_id
      and position_row.enabled
  ) then
    raise exception '所选岗位不存在、已停用或不属于当前租户';
  end if;
  if not exists (
    select 1
    from public.sys_organization organization_row
    where organization_row.id = v_employee.organization_id
      and organization_row.tenant_id = v_tenant_id
      and organization_row.status = '1'
  ) then
    raise exception '所选组织不存在、已停用或不属于当前租户';
  end if;

  insert into public.hr_employee (
    tenant_id, organization_id, employee_no, employee_name, avatar_url, position_id,
    employment_status, employment_type, gender, birth_date, phone, email, id_card_no,
    ethnicity, education_level, school_name, major_name, marital_status, political_status,
    native_place, home_address, hire_date, probation_end_date, leave_date,
    contract_start_date, contract_end_date, emergency_contact_name,
    emergency_contact_relation, emergency_contact_phone, remark, create_by
  ) values (
    v_tenant_id, v_employee.organization_id, btrim(v_employee.employee_no),
    btrim(v_employee.employee_name), v_employee.avatar_url, v_employee.position_id,
    coalesce(v_employee.employment_status, 'active'),
    coalesce(v_employee.employment_type, 'full_time'), v_employee.gender,
    v_employee.birth_date, v_employee.phone, v_employee.email, v_employee.id_card_no,
    v_employee.ethnicity, v_employee.education_level, v_employee.school_name,
    v_employee.major_name, v_employee.marital_status, v_employee.political_status,
    v_employee.native_place, v_employee.home_address, v_employee.hire_date,
    v_employee.probation_end_date, v_employee.leave_date, v_employee.contract_start_date,
    v_employee.contract_end_date, v_employee.emergency_contact_name,
    v_employee.emergency_contact_relation, v_employee.emergency_contact_phone,
    v_employee.remark, coalesce(auth.uid()::text, 'system')
  ) returning id into v_employee_id;

  return jsonb_build_object('employee_id', v_employee_id, 'driver_id', null);
end;
$function$;

-- 把原完整档案保存实现收进私有边界，并在公开 RPC 入口移除 driver 模块。
alter function public.hr_save_employee_profile_secure(jsonb) set schema app_private;
alter function app_private.hr_save_employee_profile_secure(jsonb)
  rename to save_employee_profile_records_secure;
revoke all on function app_private.save_employee_profile_records_secure(jsonb)
  from public, anon, authenticated;

create function public.hr_save_employee_profile_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception '员工档案数据格式不正确';
  end if;
  if p_payload ? 'driver' and p_payload -> 'driver' <> 'null'::jsonb then
    raise exception '员工档案不再创建司机档案，请前往司机管理从员工花名册选取';
  end if;
  return app_private.save_employee_profile_records_secure(p_payload - 'driver');
end;
$function$;

revoke all on function public.hr_save_employee_profile_secure(jsonb) from public, anon;
grant execute on function public.hr_save_employee_profile_secure(jsonb)
  to authenticated, service_role;

revoke all on function public.hr_create_employee_with_driver_secure(jsonb, jsonb)
  from public, anon, authenticated;
grant execute on function public.hr_create_employee_with_driver_secure(jsonb, jsonb)
  to service_role;

drop function if exists public.hr_list_driver_carrier_options_secure(uuid);

create or replace function public.hr_update_position_secure(p_id uuid, p_payload jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
  v_organization_id uuid;
  v_job_profile_id uuid;
  v_grade_id uuid;
  v_headcount_limit integer;
  v_multiple boolean;
begin
  if not app_private.can_execute_business_action(
    'HrPosition', 'Hr:Position:Edit', null, false
  ) then
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
    select 1 from jsonb_object_keys(p_payload) key
    where key <> all(array[
      'organization_id','job_profile_id','grade_id','position_code','position_name','enabled','sort',
      'description','headcount_limit','multiple_incumbents_allowed'
    ]::text[])
  ) then
    raise exception '岗位数据包含不允许写入的字段';
  end if;

  v_organization_id := coalesce(
    nullif(p_payload->>'organization_id', '')::uuid,
    v_position.organization_id
  );
  v_job_profile_id := coalesce(
    nullif(p_payload->>'job_profile_id', '')::uuid,
    v_position.job_profile_id
  );
  v_grade_id := case when p_payload ? 'grade_id'
    then nullif(p_payload->>'grade_id', '')::uuid
    else v_position.grade_id
  end;
  v_headcount_limit := coalesce(
    (p_payload->>'headcount_limit')::integer,
    v_position.headcount_limit
  );
  v_multiple := coalesce(
    (p_payload->>'multiple_incumbents_allowed')::boolean,
    v_position.multiple_incumbents_allowed
  );
  if v_organization_id is null then raise exception '请选择岗位所属组织'; end if;
  if not v_multiple and v_headcount_limit <> 1 then
    raise exception '单人岗位的编制人数必须为 1';
  end if;
  if not exists (
    select 1 from public.sys_organization
    where id = v_organization_id
      and tenant_id = v_position.tenant_id
      and status = '1'
  ) then
    raise exception '所选组织不存在、已停用或不属于当前租户';
  end if;
  if not exists (
    select 1 from public.hr_job_profile
    where id = v_job_profile_id
      and tenant_id = v_position.tenant_id
      and enabled
  ) then
    raise exception '所选标准职务不存在、已停用或不属于当前租户';
  end if;
  if v_grade_id is not null and not exists (
    select 1 from public.hr_grade
    where id = v_grade_id
      and tenant_id = v_position.tenant_id
      and enabled
  ) then
    raise exception '所选职级不存在、已停用或不属于当前租户';
  end if;

  update public.hr_position position_row
  set
    organization_id = v_organization_id,
    job_profile_id = v_job_profile_id,
    grade_id = v_grade_id,
    position_code = upper(coalesce(
      nullif(btrim(p_payload->>'position_code'), ''),
      position_row.position_code
    )),
    position_name = coalesce(
      nullif(btrim(p_payload->>'position_name'), ''),
      position_row.position_name
    ),
    position_kind = 'standard',
    system_code = null,
    enabled = coalesce((p_payload->>'enabled')::boolean, position_row.enabled),
    sort = coalesce((p_payload->>'sort')::integer, position_row.sort),
    description = case when p_payload ? 'description'
      then nullif(btrim(p_payload->>'description'), '')
      else position_row.description
    end,
    headcount_limit = v_headcount_limit,
    multiple_incumbents_allowed = v_multiple,
    update_by = coalesce(auth.uid()::text, 'system'),
    update_time = now()
  where position_row.id = p_id;

  update public.hr_employee employee_row
  set
    organization_id = v_organization_id,
    job_title = profile_row.job_name,
    update_time = now()
  from public.hr_job_profile profile_row
  where profile_row.id = v_job_profile_id
    and employee_row.position_id = p_id
    and employee_row.tenant_id = v_position.tenant_id;
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
  if not app_private.can_execute_business_action(
    'HrPosition', 'Hr:Position:Delete', null, false
  ) then
    raise exception 'Missing position delete permission' using errcode = '42501';
  end if;
  select * into v_position from public.hr_position where id = p_id;
  if not found or (
    not app_private.is_platform_super()
    and v_position.tenant_id <> app_private.current_user_tenant_id()
  ) then
    raise exception '岗位不存在或无权删除';
  end if;
  if exists (select 1 from public.hr_employee where position_id = p_id) then
    raise exception '该岗位已有员工使用，请先调整员工岗位';
  end if;
  delete from public.hr_position where id = p_id;
  return true;
end;
$function$;

;
