-- 新增演练记录时只返回尚未生成记录的计划，避免用户选择后命中唯一约束。
create or replace function public.smis_list_emergency_drill_records_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_organization_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_tenant uuid;
  v_records jsonb;
  v_total bigint;
  v_overview jsonb;
  v_options jsonb;
  v_orgs jsonb;
begin
  if not app_private.has_permission('SmisEmergencyDrillRecord:View') then
    raise exception '当前账号无权查看应急演练记录';
  end if;
  v_tenant:=app_private.current_user_tenant_id();

  with filtered as (
    select r.*
    from public.smis_emergency_drill_record r
    join public.smis_emergency_drill_plan p
      on p.id=r.drill_plan_id and p.tenant_id=r.tenant_id
    where r.tenant_id=v_tenant
      and (
        nullif(btrim(p_keyword),'') is null
        or p.plan_no ilike '%'||btrim(p_keyword)||'%'
        or p.drill_name ilike '%'||btrim(p_keyword)||'%'
      )
      and (p_status is null or r.status=p_status)
      and (p_start_date is null or r.actual_start_date>=p_start_date)
      and (p_end_date is null or r.actual_start_date<=p_end_date)
      and (p_organization_id is null or p.applicable_organization_id=p_organization_id)
  )
  select count(*) into v_total from filtered;

  with filtered as (
    select r.*
    from public.smis_emergency_drill_record r
    join public.smis_emergency_drill_plan p
      on p.id=r.drill_plan_id and p.tenant_id=r.tenant_id
    where r.tenant_id=v_tenant
      and (
        nullif(btrim(p_keyword),'') is null
        or p.plan_no ilike '%'||btrim(p_keyword)||'%'
        or p.drill_name ilike '%'||btrim(p_keyword)||'%'
      )
      and (p_status is null or r.status=p_status)
      and (p_start_date is null or r.actual_start_date>=p_start_date)
      and (p_end_date is null or r.actual_start_date<=p_end_date)
      and (p_organization_id is null or p.applicable_organization_id=p_organization_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,
    'drillPlanId',p.id,
    'planNo',p.plan_no,
    'drillName',p.drill_name,
    'sourcePlanName',rescue.plan_name,
    'drillForm',p.drill_form,
    'planCategory',p.plan_category,
    'planLevel',p.plan_level,
    'applicableOrganizationId',p.applicable_organization_id,
    'applicableOrganizationName',org.organization_name,
    'responsibleEmployeeName',employee.employee_name,
    'planStartDate',p.plan_start_date,
    'planEndDate',p.plan_end_date,
    'actualStartDate',r.actual_start_date,
    'actualEndDate',r.actual_end_date,
    'drillLocation',r.drill_location,
    'drillSubject',r.drill_subject,
    'drillPurpose',r.drill_purpose,
    'drillProcess',r.drill_process,
    'drillSummary',r.drill_summary,
    'drillEvaluation',r.drill_evaluation,
    'drillTeam',r.drill_team,
    'equipmentMaterials',r.equipment_materials,
    'imageUrls',r.image_urls,
    'attachmentUrls',r.attachment_urls,
    'status',r.status,
    'remark',r.remark,
    'participants',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',x.employee_id,
        'tenantId',x.tenant_id,
        'organizationId',x.organization_id,
        'employeeNo',x.employee_no,
        'employeeName',x.employee_name,
        'jobTitle',x.job_title,
        'phone',x.phone,
        'employmentStatus','active',
        'organization',jsonb_build_object(
          'id',x.organization_id,
          'organizationCode','',
          'organizationName',x.organization_name
        ))
      order by x.sort,x.employee_name)
      from public.smis_emergency_drill_record_participant x
      where x.tenant_id=r.tenant_id and x.drill_record_id=r.id
    ),'[]'::jsonb),
    'createTime',r.create_time,
    'updateTime',r.update_time
  ) order by r.update_time desc),'[]'::jsonb)
  into v_records
  from (
    select * from filtered
    order by update_time desc
    offset greatest(p_from,0)
    limit greatest(p_to-p_from+1,0)
  ) r
  join public.smis_emergency_drill_plan p
    on p.id=r.drill_plan_id and p.tenant_id=r.tenant_id
  join public.smis_emergency_rescue_plan rescue
    on rescue.id=p.source_plan_id and rescue.tenant_id=p.tenant_id
  join public.sys_organization org
    on org.id=p.applicable_organization_id and org.tenant_id=p.tenant_id
  left join public.hr_employee employee
    on employee.id=p.responsible_employee_id and employee.tenant_id=p.tenant_id;

  select jsonb_build_object(
    'total',count(*),
    'draft',count(*) filter(where status='draft'),
    'submitted',count(*) filter(where status='submitted'),
    'late',count(*) filter(
      where status='submitted'
        and actual_start_date>(
          select p.plan_end_date
          from public.smis_emergency_drill_plan p
          where p.id=drill_plan_id
        )
    ))
  into v_overview
  from public.smis_emergency_drill_record
  where tenant_id=v_tenant;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',p.id,
    'planNo',p.plan_no,
    'drillName',p.drill_name,
    'sourcePlanName',rescue.plan_name,
    'drillForm',p.drill_form,
    'planCategory',p.plan_category,
    'planLevel',p.plan_level,
    'applicableOrganizationId',p.applicable_organization_id,
    'applicableOrganizationName',org.organization_name,
    'responsibleEmployeeName',employee.employee_name,
    'planStartDate',p.plan_start_date,
    'planEndDate',p.plan_end_date,
    'drillLocation',p.drill_location,
    'drillSubject',p.drill_subject,
    'drillPurpose',p.drill_purpose
  ) order by p.plan_end_date,p.plan_no),'[]'::jsonb)
  into v_options
  from public.smis_emergency_drill_plan p
  join public.smis_emergency_rescue_plan rescue
    on rescue.id=p.source_plan_id and rescue.tenant_id=p.tenant_id
  join public.sys_organization org
    on org.id=p.applicable_organization_id and org.tenant_id=p.tenant_id
  left join public.hr_employee employee
    on employee.id=p.responsible_employee_id and employee.tenant_id=p.tenant_id
  left join public.smis_emergency_drill_record existing_record
    on existing_record.drill_plan_id=p.id and existing_record.tenant_id=p.tenant_id
  where p.tenant_id=v_tenant
    and p.status='planned'
    and existing_record.id is null;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,
    'parentId',parent_id,
    'organizationName',organization_name,
    'organizationCode',organization_code,
    'organizationType',organization_type,
    'sort',sort,
    'children','[]'::jsonb
  ) order by sort,organization_name),'[]'::jsonb)
  into v_orgs
  from public.sys_organization
  where tenant_id=v_tenant and status='1';

  return jsonb_build_object(
    'records',v_records,
    'total',v_total,
    'overview',v_overview,
    'planOptions',v_options,
    'organizations',v_orgs
  );
end
$$;

revoke all on function public.smis_list_emergency_drill_records_secure(
  integer,integer,text,text,date,date,uuid)
from public,anon;
grant execute on function public.smis_list_emergency_drill_records_secure(
  integer,integer,text,text,date,date,uuid)
to authenticated,service_role;

;
