-- 应急演练计划编号只能由租户编号引擎生成，忽略客户端提交的编号。
create or replace function public.smis_save_emergency_drill_plan_secure(
  p_id uuid,
  p_payload jsonb,
  p_submit boolean default false)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_tenant uuid;
  v_id uuid;
  v_source public.smis_emergency_rescue_plan;
  v_no text;
  v_name text:=btrim(coalesce(p_payload->>'drill_name',''));
  v_comp uuid:=nullif(p_payload->>'compilation_organization_id','')::uuid;
  v_org uuid:=nullif(p_payload->>'applicable_organization_id','')::uuid;
  v_employee uuid:=nullif(p_payload->>'responsible_employee_id','')::uuid;
  v_start date:=nullif(p_payload->>'plan_start_date','')::date;
  v_end date:=nullif(p_payload->>'plan_end_date','')::date;
  v_source_id uuid:=nullif(p_payload->>'source_plan_id','')::uuid;
  v_form text:=p_payload->>'drill_form';
  v_category text:=p_payload->>'plan_category';
  v_level text;
  v_employee_ids jsonb:=coalesce(p_payload->'trainee_ids','[]'::jsonb);
begin
  if p_id is null and not app_private.has_permission('SmisEmergencyDrillPlan:Add') then
    raise exception '当前账号无权新增应急演练计划';
  end if;
  if p_id is not null and not app_private.has_permission('SmisEmergencyDrillPlan:Edit') then
    raise exception '当前账号无权编辑应急演练计划';
  end if;
  if p_submit and not app_private.has_permission('SmisEmergencyDrillPlan:Submit') then
    raise exception '当前账号无权提交应急演练计划';
  end if;

  v_tenant:=app_private.current_user_tenant_id();
  select * into v_source
  from public.smis_emergency_rescue_plan
  where id=v_source_id
    and tenant_id=v_tenant
    and is_valid
    and record_status='submitted';

  if v_source.id is null then raise exception '请选择当前租户已提交且有效的应急救援预案'; end if;
  if v_name='' then raise exception '请输入演练计划名称'; end if;
  if v_form not in ('onsite','desktop') then raise exception '请选择有效的演练形式'; end if;
  if v_category not in ('comprehensive','onsite','special') then raise exception '请选择有效的计划类别'; end if;
  if not exists(
    select 1 from public.sys_organization
    where id=v_comp and tenant_id=v_tenant and status='1'
  ) then raise exception '请选择有效的编制单位'; end if;
  if not exists(
    select 1 from public.sys_organization
    where id=v_org and tenant_id=v_tenant and status='1'
  ) then raise exception '请选择有效的演练组织'; end if;
  if v_employee is not null and not exists(
    select 1 from public.hr_employee
    where id=v_employee
      and tenant_id=v_tenant
      and employment_status in ('probation','active')
  ) then raise exception '请选择当前租户在职员工担任演练负责人'; end if;
  if v_end is not null and v_start is not null and v_end<v_start then
    raise exception '计划完成日期不能早于计划开始日期';
  end if;
  if p_submit and (v_start is null or v_end is null or v_employee is null) then
    raise exception '提交前请完善计划日期和演练负责人';
  end if;
  if exists(
    select 1
    from jsonb_array_elements_text(v_employee_ids) x(id)
    where not exists(
      select 1 from public.hr_employee e
      where e.id=x.id::uuid
        and e.tenant_id=v_tenant
        and e.employment_status in ('probation','active')
    )
  ) then raise exception '参训人员包含无效或非当前租户员工'; end if;

  v_level:=app_private.smis_plan_level_for_organization(v_tenant,v_org);
  if p_id is null then
    v_no:=app_private.next_document_number('smis.emergency_drill_plan',v_tenant);
    insert into public.smis_emergency_drill_plan(
      plan_no,source_plan_id,drill_name,compilation_organization_id,
      applicable_organization_id,drill_form,plan_category,responsible_employee_id,
      plan_start_date,plan_end_date,planned_date,drill_location,drill_subject,
      drill_purpose,plan_level,is_special_equipment_drill,attachment_urls,remark,status,tenant_id)
    values(
      v_no,v_source_id,v_name,v_comp,v_org,v_form,v_category,v_employee,v_start,v_end,v_end,
      nullif(btrim(p_payload->>'drill_location'),''),
      nullif(btrim(p_payload->>'drill_subject'),''),
      nullif(btrim(p_payload->>'drill_purpose'),''),
      v_level,
      coalesce((p_payload->>'is_special_equipment_drill')::boolean,false),
      array(select jsonb_array_elements_text(coalesce(p_payload->'attachment_urls','[]'::jsonb))),
      nullif(btrim(p_payload->>'remark'),''),
      case when p_submit then 'planned' else 'draft' end,
      v_tenant)
    returning id into v_id;
  else
    if not exists(
      select 1 from public.smis_emergency_drill_plan
      where id=p_id and tenant_id=v_tenant and status='draft'
    ) then raise exception '仅草稿演练计划可以编辑'; end if;
    update public.smis_emergency_drill_plan
    set source_plan_id=v_source_id,
        drill_name=v_name,
        compilation_organization_id=v_comp,
        applicable_organization_id=v_org,
        drill_form=v_form,
        plan_category=v_category,
        responsible_employee_id=v_employee,
        plan_start_date=v_start,
        plan_end_date=v_end,
        planned_date=v_end,
        drill_location=nullif(btrim(p_payload->>'drill_location'),''),
        drill_subject=nullif(btrim(p_payload->>'drill_subject'),''),
        drill_purpose=nullif(btrim(p_payload->>'drill_purpose'),''),
        plan_level=v_level,
        is_special_equipment_drill=coalesce((p_payload->>'is_special_equipment_drill')::boolean,false),
        attachment_urls=array(select jsonb_array_elements_text(coalesce(p_payload->'attachment_urls','[]'::jsonb))),
        remark=nullif(btrim(p_payload->>'remark'),''),
        status=case when p_submit then 'planned' else status end
    where id=p_id and tenant_id=v_tenant
    returning id into v_id;
  end if;

  delete from public.smis_emergency_drill_plan_trainee
  where tenant_id=v_tenant and drill_plan_id=v_id;

  insert into public.smis_emergency_drill_plan_trainee(
    tenant_id,drill_plan_id,employee_id,employee_no,employee_name,
    organization_id,organization_name,job_title,phone,sort)
  select v_tenant,v_id,e.id,e.employee_no,e.employee_name,e.organization_id,
    o.organization_name,e.job_title,e.phone,row_number() over()-1
  from jsonb_array_elements_text(v_employee_ids) x(id)
  join public.hr_employee e on e.id=x.id::uuid and e.tenant_id=v_tenant
  left join public.sys_organization o
    on o.id=e.organization_id and o.tenant_id=e.tenant_id;

  return v_id;
exception
  when unique_violation then
    raise exception '演练计划编号已存在，请检查编号规则';
end
$$;

revoke all on function public.smis_save_emergency_drill_plan_secure(uuid,jsonb,boolean)
  from public,anon;
grant execute on function public.smis_save_emergency_drill_plan_secure(uuid,jsonb,boolean)
  to authenticated,service_role;

;
