create or replace function public.smis_list_emergency_drill_plans_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_drill_form text default null,
  p_plan_category text default null,
  p_organization_id uuid default null,
  p_warning_status text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_tenant uuid; v_records jsonb; v_total bigint; v_overview jsonb; v_orgs jsonb;
begin
  if not app_private.has_permission('SmisEmergencyDrillPlan:View') then raise exception '当前账号无权查看应急演练计划'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  with base as (
    select p.*,
      case when p.status in ('completed','cancelled') and not (r.status='submitted' and r.actual_start_date>p.plan_end_date) then 'normal'
           when r.status='submitted' and r.actual_start_date>p.plan_end_date then 'warning'
           when coalesce(r.status,'draft')<>'submitted' and p.status='planned' and p.plan_end_date<=current_date+3 then 'warning'
           else 'normal' end warning_status,
      r.id record_id,r.status record_status,r.actual_start_date
    from public.smis_emergency_drill_plan p
    left join public.smis_emergency_drill_record r on r.tenant_id=p.tenant_id and r.drill_plan_id=p.id
    where p.tenant_id=v_tenant
  ), filtered as (
    select * from base where
      (nullif(btrim(p_keyword),'') is null or plan_no ilike '%'||btrim(p_keyword)||'%' or drill_name ilike '%'||btrim(p_keyword)||'%')
      and (p_status is null or status=p_status)
      and (p_drill_form is null or drill_form=p_drill_form)
      and (p_plan_category is null or plan_category=p_plan_category)
      and (p_organization_id is null or applicable_organization_id=p_organization_id or compilation_organization_id=p_organization_id)
      and (p_warning_status is null or warning_status=p_warning_status)
  )
  select count(*) into v_total from filtered;

  with base as (
    select p.*,
      case when p.status in ('completed','cancelled') and not (r.status='submitted' and r.actual_start_date>p.plan_end_date) then 'normal'
           when r.status='submitted' and r.actual_start_date>p.plan_end_date then 'warning'
           when coalesce(r.status,'draft')<>'submitted' and p.status='planned' and p.plan_end_date<=current_date+3 then 'warning'
           else 'normal' end warning_status,
      r.id record_id,r.status record_status,r.actual_start_date
    from public.smis_emergency_drill_plan p
    left join public.smis_emergency_drill_record r on r.tenant_id=p.tenant_id and r.drill_plan_id=p.id
    where p.tenant_id=v_tenant
  ), filtered as (
    select * from base where
      (nullif(btrim(p_keyword),'') is null or plan_no ilike '%'||btrim(p_keyword)||'%' or drill_name ilike '%'||btrim(p_keyword)||'%')
      and (p_status is null or status=p_status) and (p_drill_form is null or drill_form=p_drill_form)
      and (p_plan_category is null or plan_category=p_plan_category)
      and (p_organization_id is null or applicable_organization_id=p_organization_id or compilation_organization_id=p_organization_id)
      and (p_warning_status is null or warning_status=p_warning_status)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,'planNo',p.plan_no,'drillName',p.drill_name,'sourcePlanId',p.source_plan_id,
    'sourcePlanNo',rescue.plan_no,'sourcePlanName',rescue.plan_name,
    'compilationOrganizationId',p.compilation_organization_id,'compilationOrganizationName',comp.organization_name,
    'applicableOrganizationId',p.applicable_organization_id,'applicableOrganizationName',org.organization_name,
    'drillForm',p.drill_form,'planCategory',p.plan_category,'responsibleEmployeeId',p.responsible_employee_id,
    'responsibleEmployeeNo',employee.employee_no,'responsibleEmployeeName',employee.employee_name,
    'planStartDate',p.plan_start_date,'planEndDate',p.plan_end_date,'drillLocation',p.drill_location,
    'drillSubject',p.drill_subject,'drillPurpose',p.drill_purpose,'planLevel',p.plan_level,
    'isSpecialEquipmentDrill',p.is_special_equipment_drill,'attachmentUrls',p.attachment_urls,
    'remark',p.remark,'status',p.status,'warningStatus',p.warning_status,'recordId',p.record_id,
    'recordStatus',p.record_status,'actualStartDate',p.actual_start_date,
    'trainees',coalesce((select jsonb_agg(jsonb_build_object('id',t.employee_id,'tenantId',t.tenant_id,
      'organizationId',t.organization_id,'employeeNo',t.employee_no,'employeeName',t.employee_name,
      'jobTitle',t.job_title,'phone',t.phone,'employmentStatus','active','organization',jsonb_build_object(
        'id',t.organization_id,'organizationCode','','organizationName',t.organization_name)) order by t.sort,t.employee_name)
      from public.smis_emergency_drill_plan_trainee t where t.tenant_id=p.tenant_id and t.drill_plan_id=p.id),'[]'::jsonb),
    'createTime',p.create_time,'updateTime',p.update_time) order by p.update_time desc),'[]'::jsonb)
  into v_records
  from (select * from filtered order by update_time desc offset greatest(p_from,0) limit greatest(p_to-p_from+1,0)) p
  join public.smis_emergency_rescue_plan rescue on rescue.id=p.source_plan_id and rescue.tenant_id=p.tenant_id
  join public.sys_organization comp on comp.id=p.compilation_organization_id and comp.tenant_id=p.tenant_id
  join public.sys_organization org on org.id=p.applicable_organization_id and org.tenant_id=p.tenant_id
  left join public.hr_employee employee on employee.id=p.responsible_employee_id and employee.tenant_id=p.tenant_id;

  with status_rows as (
    select p.status,case when r.status='submitted' and r.actual_start_date>p.plan_end_date then 'warning'
      when coalesce(r.status,'draft')<>'submitted' and p.status='planned' and p.plan_end_date<=current_date+3 then 'warning' else 'normal' end warning_status
    from public.smis_emergency_drill_plan p left join public.smis_emergency_drill_record r
      on r.tenant_id=p.tenant_id and r.drill_plan_id=p.id where p.tenant_id=v_tenant)
  select jsonb_build_object('total',count(*),'planned',count(*) filter(where status='planned'),
    'completed',count(*) filter(where status='completed'),'warning',count(*) filter(where warning_status='warning'))
  into v_overview from status_rows;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'parentId',parent_id,'organizationName',organization_name,
    'organizationCode',organization_code,'organizationType',organization_type,'sort',sort,'children','[]'::jsonb)
    order by sort,organization_name),'[]'::jsonb) into v_orgs
  from public.sys_organization where tenant_id=v_tenant and status='1';
  return jsonb_build_object('records',v_records,'total',v_total,'overview',v_overview,'organizations',v_orgs);
end $$;

create or replace function public.smis_save_emergency_drill_plan_secure(p_id uuid,p_payload jsonb,p_submit boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_tenant uuid; v_id uuid; v_source public.smis_emergency_rescue_plan; v_no text;
  v_name text:=btrim(coalesce(p_payload->>'drill_name','')); v_comp uuid:=nullif(p_payload->>'compilation_organization_id','')::uuid;
  v_org uuid:=nullif(p_payload->>'applicable_organization_id','')::uuid; v_employee uuid:=nullif(p_payload->>'responsible_employee_id','')::uuid;
  v_start date:=nullif(p_payload->>'plan_start_date','')::date; v_end date:=nullif(p_payload->>'plan_end_date','')::date;
  v_source_id uuid:=nullif(p_payload->>'source_plan_id','')::uuid; v_form text:=p_payload->>'drill_form';
  v_category text:=p_payload->>'plan_category'; v_level text; v_employee_ids jsonb:=coalesce(p_payload->'trainee_ids','[]'::jsonb);
begin
  if p_id is null and not app_private.has_permission('SmisEmergencyDrillPlan:Add') then raise exception '当前账号无权新增应急演练计划'; end if;
  if p_id is not null and not app_private.has_permission('SmisEmergencyDrillPlan:Edit') then raise exception '当前账号无权编辑应急演练计划'; end if;
  if p_submit and not app_private.has_permission('SmisEmergencyDrillPlan:Submit') then raise exception '当前账号无权提交应急演练计划'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  select * into v_source from public.smis_emergency_rescue_plan where id=v_source_id and tenant_id=v_tenant and is_valid and record_status='submitted';
  if v_source.id is null then raise exception '请选择当前租户已提交且有效的应急救援预案'; end if;
  if v_name='' then raise exception '请输入演练计划名称'; end if;
  if v_form not in ('onsite','desktop') then raise exception '请选择有效的演练形式'; end if;
  if v_category not in ('comprehensive','onsite','special') then raise exception '请选择有效的计划类别'; end if;
  if not exists(select 1 from public.sys_organization where id=v_comp and tenant_id=v_tenant and status='1') then raise exception '请选择有效的编制单位'; end if;
  if not exists(select 1 from public.sys_organization where id=v_org and tenant_id=v_tenant and status='1') then raise exception '请选择有效的演练组织'; end if;
  if v_employee is not null and not exists(select 1 from public.hr_employee where id=v_employee and tenant_id=v_tenant and employment_status in ('probation','active')) then raise exception '请选择当前租户在职员工担任演练负责人'; end if;
  if v_end is not null and v_start is not null and v_end<v_start then raise exception '计划完成日期不能早于计划开始日期'; end if;
  if p_submit and (v_start is null or v_end is null or v_employee is null) then raise exception '提交前请完善计划日期和演练负责人'; end if;
  if exists(select 1 from jsonb_array_elements_text(v_employee_ids) x(id) where not exists(
    select 1 from public.hr_employee e where e.id=x.id::uuid and e.tenant_id=v_tenant and e.employment_status in ('probation','active'))) then raise exception '参训人员包含无效或非当前租户员工'; end if;
  v_level:=app_private.smis_plan_level_for_organization(v_tenant,v_org);
  if p_id is null then
    v_no:=nullif(upper(btrim(p_payload->>'plan_no')),'');
    if v_no is null then v_no:=app_private.next_document_number('smis.emergency_drill_plan',v_tenant); end if;
    insert into public.smis_emergency_drill_plan(plan_no,source_plan_id,drill_name,compilation_organization_id,
      applicable_organization_id,drill_form,plan_category,responsible_employee_id,plan_start_date,plan_end_date,
      planned_date,drill_location,drill_subject,drill_purpose,plan_level,is_special_equipment_drill,attachment_urls,remark,status,tenant_id)
    values(v_no,v_source_id,v_name,v_comp,v_org,v_form,v_category,v_employee,v_start,v_end,v_end,
      nullif(btrim(p_payload->>'drill_location'),''),nullif(btrim(p_payload->>'drill_subject'),''),
      nullif(btrim(p_payload->>'drill_purpose'),''),v_level,coalesce((p_payload->>'is_special_equipment_drill')::boolean,false),
      array(select jsonb_array_elements_text(coalesce(p_payload->'attachment_urls','[]'::jsonb))),
      nullif(btrim(p_payload->>'remark'),''),case when p_submit then 'planned' else 'draft' end,v_tenant) returning id into v_id;
  else
    if not exists(select 1 from public.smis_emergency_drill_plan where id=p_id and tenant_id=v_tenant and status='draft') then raise exception '仅草稿演练计划可以编辑'; end if;
    update public.smis_emergency_drill_plan set source_plan_id=v_source_id,drill_name=v_name,compilation_organization_id=v_comp,
      applicable_organization_id=v_org,drill_form=v_form,plan_category=v_category,responsible_employee_id=v_employee,
      plan_start_date=v_start,plan_end_date=v_end,planned_date=v_end,drill_location=nullif(btrim(p_payload->>'drill_location'),''),
      drill_subject=nullif(btrim(p_payload->>'drill_subject'),''),drill_purpose=nullif(btrim(p_payload->>'drill_purpose'),''),plan_level=v_level,
      is_special_equipment_drill=coalesce((p_payload->>'is_special_equipment_drill')::boolean,false),
      attachment_urls=array(select jsonb_array_elements_text(coalesce(p_payload->'attachment_urls','[]'::jsonb))),
      remark=nullif(btrim(p_payload->>'remark'),''),status=case when p_submit then 'planned' else status end
    where id=p_id and tenant_id=v_tenant returning id into v_id;
  end if;
  delete from public.smis_emergency_drill_plan_trainee where tenant_id=v_tenant and drill_plan_id=v_id;
  insert into public.smis_emergency_drill_plan_trainee(tenant_id,drill_plan_id,employee_id,employee_no,employee_name,
    organization_id,organization_name,job_title,phone,sort)
  select v_tenant,v_id,e.id,e.employee_no,e.employee_name,e.organization_id,o.organization_name,e.job_title,e.phone,row_number() over()-1
  from jsonb_array_elements_text(v_employee_ids) x(id) join public.hr_employee e on e.id=x.id::uuid and e.tenant_id=v_tenant
  left join public.sys_organization o on o.id=e.organization_id and o.tenant_id=e.tenant_id;
  return v_id;
exception when unique_violation then raise exception '演练计划编号已存在，请检查编号规则'; end $$;

create or replace function public.smis_delete_emergency_drill_plans_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare v_tenant uuid; v_count integer;
begin
  if not app_private.has_permission('SmisEmergencyDrillPlan:Delete') then raise exception '当前账号无权删除应急演练计划'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  if exists(select 1 from public.smis_emergency_drill_plan where id=any(p_ids) and tenant_id=v_tenant and status<>'draft') then raise exception '仅草稿演练计划可以删除'; end if;
  delete from public.smis_emergency_drill_plan where id=any(p_ids) and tenant_id=v_tenant; get diagnostics v_count=row_count; return v_count;
end $$;

create or replace function public.smis_push_emergency_drill_plan_to_record_secure(p_plan_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_tenant uuid; v_plan public.smis_emergency_drill_plan; v_id uuid;
begin
  if not app_private.has_permission('SmisEmergencyDrillPlan:Push') then raise exception '当前账号无权下推演练记录'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  select * into v_plan from public.smis_emergency_drill_plan where id=p_plan_id and tenant_id=v_tenant;
  if v_plan.id is null then raise exception '演练计划不存在或不属于当前租户'; end if;
  if v_plan.status<>'planned' then raise exception '仅计划中的演练计划可以下推记录'; end if;
  select id into v_id from public.smis_emergency_drill_record where tenant_id=v_tenant and drill_plan_id=p_plan_id;
  if v_id is null then
    insert into public.smis_emergency_drill_record(tenant_id,drill_plan_id,drill_location,drill_subject,drill_purpose,status)
    values(v_tenant,p_plan_id,v_plan.drill_location,v_plan.drill_subject,v_plan.drill_purpose,'draft') returning id into v_id;
    insert into public.smis_emergency_drill_record_participant(tenant_id,drill_record_id,employee_id,employee_no,employee_name,
      organization_id,organization_name,job_title,phone,sort)
    select tenant_id,v_id,employee_id,employee_no,employee_name,organization_id,organization_name,job_title,phone,sort
    from public.smis_emergency_drill_plan_trainee where tenant_id=v_tenant and drill_plan_id=p_plan_id;
  end if;
  return v_id;
end $$;

create or replace function public.smis_list_emergency_drill_records_secure(
 p_from integer default 0,p_to integer default 19,p_keyword text default null,p_status text default null,
 p_start_date date default null,p_end_date date default null,p_organization_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_tenant uuid; v_records jsonb; v_total bigint; v_overview jsonb; v_options jsonb; v_orgs jsonb;
begin
  if not app_private.has_permission('SmisEmergencyDrillRecord:View') then raise exception '当前账号无权查看应急演练记录'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  with filtered as (
    select r.* from public.smis_emergency_drill_record r join public.smis_emergency_drill_plan p on p.id=r.drill_plan_id and p.tenant_id=r.tenant_id
    where r.tenant_id=v_tenant and (nullif(btrim(p_keyword),'') is null or p.plan_no ilike '%'||btrim(p_keyword)||'%' or p.drill_name ilike '%'||btrim(p_keyword)||'%')
      and (p_status is null or r.status=p_status) and (p_start_date is null or r.actual_start_date>=p_start_date)
      and (p_end_date is null or r.actual_start_date<=p_end_date) and (p_organization_id is null or p.applicable_organization_id=p_organization_id))
  select count(*) into v_total from filtered;
  with filtered as (
    select r.* from public.smis_emergency_drill_record r join public.smis_emergency_drill_plan p on p.id=r.drill_plan_id and p.tenant_id=r.tenant_id
    where r.tenant_id=v_tenant and (nullif(btrim(p_keyword),'') is null or p.plan_no ilike '%'||btrim(p_keyword)||'%' or p.drill_name ilike '%'||btrim(p_keyword)||'%')
      and (p_status is null or r.status=p_status) and (p_start_date is null or r.actual_start_date>=p_start_date)
      and (p_end_date is null or r.actual_start_date<=p_end_date) and (p_organization_id is null or p.applicable_organization_id=p_organization_id))
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'drillPlanId',p.id,'planNo',p.plan_no,'drillName',p.drill_name,
    'sourcePlanName',rescue.plan_name,'drillForm',p.drill_form,'planCategory',p.plan_category,'planLevel',p.plan_level,
    'applicableOrganizationId',p.applicable_organization_id,'applicableOrganizationName',org.organization_name,
    'responsibleEmployeeName',employee.employee_name,'planStartDate',p.plan_start_date,'planEndDate',p.plan_end_date,
    'actualStartDate',r.actual_start_date,'actualEndDate',r.actual_end_date,'drillLocation',r.drill_location,
    'drillSubject',r.drill_subject,'drillPurpose',r.drill_purpose,'drillProcess',r.drill_process,'drillSummary',r.drill_summary,
    'drillEvaluation',r.drill_evaluation,'drillTeam',r.drill_team,'equipmentMaterials',r.equipment_materials,
    'imageUrls',r.image_urls,'attachmentUrls',r.attachment_urls,'status',r.status,'remark',r.remark,
    'participants',coalesce((select jsonb_agg(jsonb_build_object('id',x.employee_id,'tenantId',x.tenant_id,'organizationId',x.organization_id,
      'employeeNo',x.employee_no,'employeeName',x.employee_name,'jobTitle',x.job_title,'phone',x.phone,'employmentStatus','active',
      'organization',jsonb_build_object('id',x.organization_id,'organizationCode','','organizationName',x.organization_name)) order by x.sort,x.employee_name)
      from public.smis_emergency_drill_record_participant x where x.tenant_id=r.tenant_id and x.drill_record_id=r.id),'[]'::jsonb),
    'createTime',r.create_time,'updateTime',r.update_time) order by r.update_time desc),'[]'::jsonb) into v_records
  from (select * from filtered order by update_time desc offset greatest(p_from,0) limit greatest(p_to-p_from+1,0)) r
  join public.smis_emergency_drill_plan p on p.id=r.drill_plan_id and p.tenant_id=r.tenant_id
  join public.smis_emergency_rescue_plan rescue on rescue.id=p.source_plan_id and rescue.tenant_id=p.tenant_id
  join public.sys_organization org on org.id=p.applicable_organization_id and org.tenant_id=p.tenant_id
  left join public.hr_employee employee on employee.id=p.responsible_employee_id and employee.tenant_id=p.tenant_id;
  select jsonb_build_object('total',count(*),'draft',count(*)filter(where status='draft'),'submitted',count(*)filter(where status='submitted'),
    'late',count(*)filter(where status='submitted' and actual_start_date>(select p.plan_end_date from public.smis_emergency_drill_plan p where p.id=drill_plan_id)))
  into v_overview from public.smis_emergency_drill_record where tenant_id=v_tenant;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'planNo',p.plan_no,'drillName',p.drill_name,'sourcePlanName',rescue.plan_name,
    'drillForm',p.drill_form,'planCategory',p.plan_category,'planLevel',p.plan_level,'applicableOrganizationId',p.applicable_organization_id,
    'applicableOrganizationName',org.organization_name,'responsibleEmployeeName',employee.employee_name,'planStartDate',p.plan_start_date,
    'planEndDate',p.plan_end_date,'drillLocation',p.drill_location,'drillSubject',p.drill_subject,'drillPurpose',p.drill_purpose)
    order by p.plan_end_date,p.plan_no),'[]'::jsonb) into v_options
  from public.smis_emergency_drill_plan p join public.smis_emergency_rescue_plan rescue on rescue.id=p.source_plan_id and rescue.tenant_id=p.tenant_id
  join public.sys_organization org on org.id=p.applicable_organization_id and org.tenant_id=p.tenant_id
  left join public.hr_employee employee on employee.id=p.responsible_employee_id and employee.tenant_id=p.tenant_id
  where p.tenant_id=v_tenant and p.status in ('planned','completed');
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'parentId',parent_id,'organizationName',organization_name,'organizationCode',organization_code,
    'organizationType',organization_type,'sort',sort,'children','[]'::jsonb) order by sort,organization_name),'[]'::jsonb) into v_orgs
  from public.sys_organization where tenant_id=v_tenant and status='1';
  return jsonb_build_object('records',v_records,'total',v_total,'overview',v_overview,'planOptions',v_options,'organizations',v_orgs);
end $$;

create or replace function public.smis_save_emergency_drill_record_secure(p_id uuid,p_payload jsonb,p_submit boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_tenant uuid; v_id uuid; v_plan public.smis_emergency_drill_plan; v_plan_id uuid:=nullif(p_payload->>'drill_plan_id','')::uuid;
  v_start date:=nullif(p_payload->>'actual_start_date','')::date; v_end date:=nullif(p_payload->>'actual_end_date','')::date;
  v_employee_ids jsonb:=coalesce(p_payload->'participant_ids','[]'::jsonb);
begin
  if p_id is null and not app_private.has_permission('SmisEmergencyDrillRecord:Add') then raise exception '当前账号无权新增演练记录'; end if;
  if p_id is not null and not app_private.has_permission('SmisEmergencyDrillRecord:Edit') then raise exception '当前账号无权编辑演练记录'; end if;
  if p_submit and not app_private.has_permission('SmisEmergencyDrillRecord:Submit') then raise exception '当前账号无权提交演练记录'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  select * into v_plan from public.smis_emergency_drill_plan where id=v_plan_id and tenant_id=v_tenant and status in ('planned','completed');
  if v_plan.id is null then raise exception '请选择当前租户计划中的演练计划'; end if;
  if v_end is not null and v_start is not null and v_end<v_start then raise exception '实际结束日期不能早于实际开始日期'; end if;
  if p_submit and v_start is null then raise exception '提交前请填写实际演练日期'; end if;
  if p_submit and jsonb_array_length(v_employee_ids)=0 then raise exception '提交前请至少选择一名参演人员'; end if;
  if exists(select 1 from jsonb_array_elements_text(v_employee_ids) x(id) where not exists(
    select 1 from public.hr_employee e where e.id=x.id::uuid and e.tenant_id=v_tenant)) then raise exception '参演人员包含无效或非当前租户员工'; end if;
  if p_id is null then
    insert into public.smis_emergency_drill_record(tenant_id,drill_plan_id,actual_start_date,actual_end_date,drill_location,drill_subject,
      drill_purpose,drill_process,drill_summary,drill_evaluation,drill_team,equipment_materials,image_urls,attachment_urls,status,remark)
    values(v_tenant,v_plan_id,v_start,v_end,coalesce(nullif(btrim(p_payload->>'drill_location'),''),v_plan.drill_location),
      coalesce(nullif(btrim(p_payload->>'drill_subject'),''),v_plan.drill_subject),coalesce(nullif(btrim(p_payload->>'drill_purpose'),''),v_plan.drill_purpose),
      nullif(btrim(p_payload->>'drill_process'),''),nullif(btrim(p_payload->>'drill_summary'),''),nullif(btrim(p_payload->>'drill_evaluation'),''),
      nullif(btrim(p_payload->>'drill_team'),''),nullif(btrim(p_payload->>'equipment_materials'),''),
      array(select jsonb_array_elements_text(coalesce(p_payload->'image_urls','[]'::jsonb))),
      array(select jsonb_array_elements_text(coalesce(p_payload->'attachment_urls','[]'::jsonb))),case when p_submit then 'submitted' else 'draft' end,
      nullif(btrim(p_payload->>'remark'),'')) returning id into v_id;
  else
    if not exists(select 1 from public.smis_emergency_drill_record where id=p_id and tenant_id=v_tenant and status='draft') then raise exception '仅草稿演练记录可以编辑'; end if;
    update public.smis_emergency_drill_record set drill_plan_id=v_plan_id,actual_start_date=v_start,actual_end_date=v_end,
      drill_location=coalesce(nullif(btrim(p_payload->>'drill_location'),''),v_plan.drill_location),
      drill_subject=coalesce(nullif(btrim(p_payload->>'drill_subject'),''),v_plan.drill_subject),
      drill_purpose=coalesce(nullif(btrim(p_payload->>'drill_purpose'),''),v_plan.drill_purpose),drill_process=nullif(btrim(p_payload->>'drill_process'),''),
      drill_summary=nullif(btrim(p_payload->>'drill_summary'),''),drill_evaluation=nullif(btrim(p_payload->>'drill_evaluation'),''),
      drill_team=nullif(btrim(p_payload->>'drill_team'),''),equipment_materials=nullif(btrim(p_payload->>'equipment_materials'),''),
      image_urls=array(select jsonb_array_elements_text(coalesce(p_payload->'image_urls','[]'::jsonb))),
      attachment_urls=array(select jsonb_array_elements_text(coalesce(p_payload->'attachment_urls','[]'::jsonb))),
      status=case when p_submit then 'submitted' else status end,remark=nullif(btrim(p_payload->>'remark'),'')
    where id=p_id and tenant_id=v_tenant returning id into v_id;
  end if;
  delete from public.smis_emergency_drill_record_participant where tenant_id=v_tenant and drill_record_id=v_id;
  insert into public.smis_emergency_drill_record_participant(tenant_id,drill_record_id,employee_id,employee_no,employee_name,
    organization_id,organization_name,job_title,phone,sort)
  select v_tenant,v_id,e.id,e.employee_no,e.employee_name,e.organization_id,o.organization_name,e.job_title,e.phone,row_number() over()-1
  from jsonb_array_elements_text(v_employee_ids) x(id) join public.hr_employee e on e.id=x.id::uuid and e.tenant_id=v_tenant
  left join public.sys_organization o on o.id=e.organization_id and o.tenant_id=e.tenant_id;
  if p_submit then update public.smis_emergency_drill_plan set status='completed' where id=v_plan_id and tenant_id=v_tenant; end if;
  return v_id;
exception when unique_violation then raise exception '该演练计划已存在演练记录，请直接编辑原记录'; end $$;

create or replace function public.smis_delete_emergency_drill_records_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path='' as $$
declare v_tenant uuid; v_count integer;
begin
  if not app_private.has_permission('SmisEmergencyDrillRecord:Delete') then raise exception '当前账号无权删除演练记录'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  if exists(select 1 from public.smis_emergency_drill_record where id=any(p_ids) and tenant_id=v_tenant and status<>'draft') then raise exception '仅草稿演练记录可以删除'; end if;
  delete from public.smis_emergency_drill_record where id=any(p_ids) and tenant_id=v_tenant; get diagnostics v_count=row_count; return v_count;
end $$;

create or replace function public.smis_emergency_drill_report_secure(p_start_date date default null,p_end_date date default null,p_organization_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_tenant uuid; v_rows jsonb; v_outstanding jsonb; v_overview jsonb;
begin
  if not app_private.has_permission('SmisEmergencyDrillReport:View') then raise exception '当前账号无权查看应急演练报表'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  with records as (
    select p.*,r.actual_start_date,r.actual_end_date,org.organization_name
    from public.smis_emergency_drill_plan p join public.smis_emergency_drill_record r on r.drill_plan_id=p.id and r.tenant_id=p.tenant_id and r.status='submitted'
    join public.sys_organization org on org.id=p.applicable_organization_id and org.tenant_id=p.tenant_id
    where p.tenant_id=v_tenant and (p_start_date is null or r.actual_start_date>=p_start_date)
      and (p_end_date is null or r.actual_start_date<=p_end_date) and (p_organization_id is null or p.applicable_organization_id=p_organization_id))
  select coalesce(jsonb_agg(jsonb_build_object('organizationId',applicable_organization_id,'organizationName',organization_name,
    'planCategory',plan_category,'planLevel',plan_level,'drillCount',drill_count,'lateCount',late_count,
    'averageIntervalDays',average_interval_days) order by organization_name,plan_category,plan_level),'[]'::jsonb) into v_rows
  from (select applicable_organization_id,organization_name,plan_category,plan_level,count(*) drill_count,
    count(*)filter(where actual_start_date>plan_end_date) late_count,
    case when count(*)>1 then round((max(actual_start_date)-min(actual_start_date))::numeric/(count(*)-1),1) else null end average_interval_days
    from records group by applicable_organization_id,organization_name,plan_category,plan_level) grouped;
  select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'planNo',p.plan_no,'drillName',p.drill_name,'organizationName',org.organization_name,
    'planCategory',p.plan_category,'planLevel',p.plan_level,'planEndDate',p.plan_end_date,
    'warningStatus',case when p.plan_end_date<=current_date+3 then 'warning' else 'normal' end) order by p.plan_end_date,p.plan_no),'[]'::jsonb) into v_outstanding
  from public.smis_emergency_drill_plan p join public.sys_organization org on org.id=p.applicable_organization_id and org.tenant_id=p.tenant_id
  left join public.smis_emergency_drill_record r on r.drill_plan_id=p.id and r.tenant_id=p.tenant_id and r.status='submitted'
  where p.tenant_id=v_tenant and p.status='planned' and r.id is null
    and (p_start_date is null or p.plan_end_date>=p_start_date) and (p_end_date is null or p.plan_end_date<=p_end_date)
    and (p_organization_id is null or p.applicable_organization_id=p_organization_id);
  select jsonb_build_object('planCount',count(*),'completedCount',count(*)filter(where r.status='submitted'),
    'outstandingCount',count(*)filter(where p.status='planned' and r.id is null),
    'warningCount',count(*)filter(where p.status='planned' and r.id is null and p.plan_end_date<=current_date+3),
    'lateCount',count(*)filter(where r.status='submitted' and r.actual_start_date>p.plan_end_date)) into v_overview
  from public.smis_emergency_drill_plan p left join public.smis_emergency_drill_record r on r.drill_plan_id=p.id and r.tenant_id=p.tenant_id
  where p.tenant_id=v_tenant and (p_start_date is null or coalesce(r.actual_start_date,p.plan_end_date)>=p_start_date)
    and (p_end_date is null or coalesce(r.actual_start_date,p.plan_end_date)<=p_end_date)
    and (p_organization_id is null or p.applicable_organization_id=p_organization_id);
  return jsonb_build_object('overview',v_overview,'rows',v_rows,'outstanding',v_outstanding);
end $$;

create or replace function public.smis_push_emergency_rescue_plan_to_drill_secure(p_plan_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_tenant uuid; v_plan public.smis_emergency_rescue_plan; v_id uuid; v_no text;
begin
  if not app_private.has_permission('SmisEmergencyRescuePlan:Push') then raise exception '当前账号无权下推演练计划'; end if;
  v_tenant:=app_private.current_user_tenant_id();
  select * into v_plan from public.smis_emergency_rescue_plan where id=p_plan_id and tenant_id=v_tenant;
  if v_plan.id is null then raise exception '应急预案不存在或不属于当前租户'; end if;
  if v_plan.record_status<>'submitted' or not v_plan.is_valid then raise exception '仅已提交且有效的预案可以下推演练计划'; end if;
  if exists(select 1 from public.smis_emergency_drill_plan where source_plan_id=p_plan_id and tenant_id=v_tenant and status='draft') then raise exception '该预案已有待完善的演练计划草稿'; end if;
  v_no:=app_private.next_document_number('smis.emergency_drill_plan',v_tenant);
  insert into public.smis_emergency_drill_plan(plan_no,source_plan_id,drill_name,compilation_organization_id,applicable_organization_id,
    drill_form,plan_category,plan_level,is_special_equipment_drill,status,tenant_id)
  values(v_no,v_plan.id,v_plan.plan_name||'演练',v_plan.applicable_organization_id,v_plan.applicable_organization_id,
    'onsite',v_plan.plan_category,v_plan.plan_level,v_plan.is_special_equipment_drill,'draft',v_tenant) returning id into v_id;
  return v_id;
end $$;

grant execute on function public.smis_list_emergency_drill_plans_secure(integer,integer,text,text,text,text,uuid,text) to authenticated,service_role;
grant execute on function public.smis_save_emergency_drill_plan_secure(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.smis_delete_emergency_drill_plans_secure(uuid[]) to authenticated,service_role;
grant execute on function public.smis_push_emergency_drill_plan_to_record_secure(uuid) to authenticated,service_role;
grant execute on function public.smis_list_emergency_drill_records_secure(integer,integer,text,text,date,date,uuid) to authenticated,service_role;
grant execute on function public.smis_save_emergency_drill_record_secure(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.smis_delete_emergency_drill_records_secure(uuid[]) to authenticated,service_role;
grant execute on function public.smis_emergency_drill_report_secure(date,date,uuid) to authenticated,service_role;
grant execute on function public.smis_push_emergency_rescue_plan_to_drill_secure(uuid) to authenticated,service_role;


;
