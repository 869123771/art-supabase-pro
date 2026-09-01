create or replace function app_private.workflow_dictionary_label(
  p_dict_code text,
  p_value text
)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select dictionary_item.label
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type
    on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = p_dict_code
    and dictionary_type.status = '1'
    and dictionary_item.status = '1'
    and dictionary_item.value = p_value
  order by dictionary_item.sort, dictionary_item.label
  limit 1
$function$;

revoke all on function app_private.workflow_dictionary_label(text, text)
from public, anon, authenticated;

create or replace function app_private.get_hr_workflow_business_snapshot(
  p_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  instance_row public.wf_instance;
  business_row record;
  result_value jsonb;
  metrics_value jsonb := '[]'::jsonb;
  fields_value jsonb := '[]'::jsonb;
  warnings_value jsonb := '[]'::jsonb;
  subtitle_value text;
  business_no_value text;
  status_value text;
  route_value text;
begin
  if (select auth.uid()) is null
    or not app_private.can_view_workflow_instance(p_instance_id)
  then
    raise exception '无权查看该审批业务信息' using errcode = '42501';
  end if;

  select *
  into instance_row
  from public.wf_instance
  where id = p_instance_id;

  if not found then
    raise exception '审批实例不存在';
  end if;

  if instance_row.business_type = 'hr_personnel_change' then
    select
      change_row.*,
      employee_row.employee_name,
      employee_row.employee_no,
      app_private.workflow_dictionary_label(
        'hrPersonnelChangeType',
        change_row.change_type
      ) as change_type_label
    into business_row
    from public.hr_personnel_change change_row
    left join public.hr_employee employee_row
      on employee_row.id = change_row.employee_id
      and employee_row.tenant_id = change_row.tenant_id
    where change_row.id = instance_row.business_id
      and change_row.tenant_id = instance_row.tenant_id;

    route_value := '/hr/personnel/personnel-change';
    if not found then
      warnings_value := jsonb_build_array('业务原单已删除，当前仅展示流程快照');
    else
      business_no_value := business_row.change_no;
      status_value := business_row.status;
      subtitle_value := concat_ws(
        ' · ',
        business_row.employee_name,
        business_row.employee_no
      );
      metrics_value := jsonb_build_array(
        jsonb_build_object(
          'label', '异动类型',
          'value', coalesce(business_row.change_type_label, '待确认'),
          'tone', 'primary'
        ),
        jsonb_build_object(
          'label', '生效日期',
          'value', coalesce(business_row.effective_date::text, '--'),
          'tone', 'info'
        )
      );
      fields_value := jsonb_build_array(
        jsonb_build_object('label', '异动单号', 'value', coalesce(business_row.change_no, '--')),
        jsonb_build_object('label', '员工', 'value', coalesce(business_row.employee_name, '--')),
        jsonb_build_object('label', '员工编号', 'value', coalesce(business_row.employee_no, '--')),
        jsonb_build_object(
          'label', '异动类型',
          'value', coalesce(business_row.change_type_label, business_row.change_type, '--')
        ),
        jsonb_build_object('label', '生效日期', 'value', coalesce(business_row.effective_date::text, '--')),
        jsonb_build_object('label', '异动原因', 'value', coalesce(business_row.reason, '--'))
      );
    end if;

  elsif instance_row.business_type = 'hr_lifecycle_case' then
    select
      case_row.*,
      employee_row.employee_name,
      employee_row.employee_no,
      app_private.workflow_dictionary_label(
        'hrLifecycleCaseType',
        case_row.case_type
      ) as case_type_label
    into business_row
    from public.hr_lifecycle_case case_row
    left join public.hr_employee employee_row
      on employee_row.id = case_row.employee_id
      and employee_row.tenant_id = case_row.tenant_id
    where case_row.id = instance_row.business_id
      and case_row.tenant_id = instance_row.tenant_id;

    route_value := '/hr/personnel/lifecycle';
    if not found then
      warnings_value := jsonb_build_array('业务原单已删除，当前仅展示流程快照');
    else
      business_no_value := business_row.case_no;
      status_value := business_row.status;
      subtitle_value := concat_ws(' · ', business_row.employee_name, business_row.employee_no);
      metrics_value := jsonb_build_array(
        jsonb_build_object(
          'label', '事项类型',
          'value', coalesce(business_row.case_type_label, '待确认'),
          'tone', 'primary'
        ),
        jsonb_build_object(
          'label', '计划生效',
          'value', coalesce(business_row.planned_effective_date::text, '--'),
          'tone', 'info'
        )
      );
      fields_value := jsonb_build_array(
        jsonb_build_object('label', '事项编号', 'value', coalesce(business_row.case_no, '--')),
        jsonb_build_object('label', '员工', 'value', coalesce(business_row.employee_name, '--')),
        jsonb_build_object('label', '员工编号', 'value', coalesce(business_row.employee_no, '--')),
        jsonb_build_object(
          'label', '事项类型',
          'value', coalesce(business_row.case_type_label, business_row.case_type, '--')
        ),
        jsonb_build_object(
          'label', '计划生效日期',
          'value', coalesce(business_row.planned_effective_date::text, '--')
        ),
        jsonb_build_object('label', '备注', 'value', coalesce(business_row.remark, '--'))
      );
    end if;

  elsif instance_row.business_type = 'hr_self_service_request' then
    select
      request_row.*,
      employee_row.employee_name,
      employee_row.employee_no,
      app_private.workflow_dictionary_label(
        'hrSelfServiceRequestType',
        request_row.request_type
      ) as request_type_label
    into business_row
    from public.hr_self_service_request request_row
    left join public.hr_employee employee_row
      on employee_row.id = request_row.employee_id
      and employee_row.tenant_id = request_row.tenant_id
    where request_row.id = instance_row.business_id
      and request_row.tenant_id = instance_row.tenant_id;

    route_value := '/hr/operations/self-service';
    if not found then
      warnings_value := jsonb_build_array('业务原单已删除，当前仅展示流程快照');
    else
      business_no_value := business_row.request_no;
      status_value := business_row.status;
      subtitle_value := concat_ws(' · ', business_row.employee_name, business_row.title);
      metrics_value := jsonb_build_array(
        jsonb_build_object(
          'label', '申请类型',
          'value', coalesce(business_row.request_type_label, '待确认'),
          'tone', 'primary'
        ),
        jsonb_build_object(
          'label', '申请时长',
          'value', coalesce(business_row.duration_hours::text || ' 小时', '--'),
          'tone', 'info'
        )
      );
      fields_value := jsonb_build_array(
        jsonb_build_object('label', '申请编号', 'value', coalesce(business_row.request_no, '--')),
        jsonb_build_object('label', '员工', 'value', coalesce(business_row.employee_name, '--')),
        jsonb_build_object('label', '申请标题', 'value', coalesce(business_row.title, '--')),
        jsonb_build_object(
          'label', '申请类型',
          'value', coalesce(business_row.request_type_label, business_row.request_type, '--')
        ),
        jsonb_build_object('label', '开始时间', 'value', coalesce(business_row.start_at::text, '--')),
        jsonb_build_object('label', '结束时间', 'value', coalesce(business_row.end_at::text, '--'))
      );
    end if;

  elsif instance_row.business_type = 'hr_recruitment_requisition' then
    select
      requisition_row.*,
      organization_row.organization_name,
      position_row.position_name
    into business_row
    from public.hr_recruitment_requisition requisition_row
    left join public.sys_organization organization_row
      on organization_row.id = requisition_row.organization_id
      and organization_row.tenant_id = requisition_row.tenant_id
    left join public.hr_position position_row
      on position_row.id = requisition_row.position_id
      and position_row.tenant_id = requisition_row.tenant_id
    where requisition_row.id = instance_row.business_id
      and requisition_row.tenant_id = instance_row.tenant_id;

    route_value := '/hr/recruitment/workbench';
    if not found then
      warnings_value := jsonb_build_array('业务原单已删除，当前仅展示流程快照');
    else
      business_no_value := business_row.requisition_no;
      status_value := business_row.status;
      subtitle_value := concat_ws(
        ' · ',
        business_row.organization_name,
        business_row.position_name
      );
      metrics_value := jsonb_build_array(
        jsonb_build_object(
          'label', '招聘人数',
          'value', coalesce(business_row.opening_count, 0)::text || ' 人',
          'tone', 'primary'
        ),
        jsonb_build_object(
          'label', '期望到岗',
          'value', coalesce(business_row.expected_onboard_date::text, '--'),
          'tone', 'info'
        )
      );
      fields_value := jsonb_build_array(
        jsonb_build_object('label', '需求编号', 'value', coalesce(business_row.requisition_no, '--')),
        jsonb_build_object('label', '招聘组织', 'value', coalesce(business_row.organization_name, '--')),
        jsonb_build_object('label', '招聘岗位', 'value', coalesce(business_row.position_name, '--')),
        jsonb_build_object('label', '需求人数', 'value', coalesce(business_row.opening_count, 0)::text || ' 人'),
        jsonb_build_object('label', '已录用', 'value', coalesce(business_row.hired_count, 0)::text || ' 人'),
        jsonb_build_object(
          'label', '期望到岗日期',
          'value', coalesce(business_row.expected_onboard_date::text, '--')
        )
      );
    end if;
  else
    raise exception '不支持的 HR 审批业务类型: %', instance_row.business_type;
  end if;

  result_value := jsonb_build_object(
    'instanceId', instance_row.id,
    'businessType', instance_row.business_type,
    'businessId', instance_row.business_id,
    'title', instance_row.business_title,
    'subtitle', subtitle_value,
    'businessNo', business_no_value,
    'status', status_value,
    'routePath', route_value,
    'metrics', metrics_value,
    'fields', fields_value,
    'warnings', warnings_value,
    'attachments', '[]'::jsonb
  );

  return result_value;
end
$function$;

revoke all on function app_private.get_hr_workflow_business_snapshot(uuid)
from public, anon, authenticated;

create or replace function app_private.get_workflow_business_snapshot_v3(
  p_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  business_type_value text;
begin
  select instance_row.business_type
  into business_type_value
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;

  if business_type_value in (
    'hr_personnel_change',
    'hr_lifecycle_case',
    'hr_self_service_request',
    'hr_recruitment_requisition'
  ) then
    return app_private.get_hr_workflow_business_snapshot(p_instance_id);
  end if;

  return app_private.get_workflow_business_snapshot_v2(p_instance_id);
end
$function$;

revoke all on function app_private.get_workflow_business_snapshot_v3(uuid)
from public, anon, authenticated;

create or replace function public.get_workflow_business_snapshot(
  p_instance_id uuid
)
returns jsonb
language sql
stable
set search_path = ''
as $function$
  select app_private.get_workflow_business_snapshot_v3(p_instance_id)
$function$;

;
