-- Register the primary HR identifiers with the shared configurable number engine.

with scene_definition (
  rule_key,
  rule_name,
  field_label,
  category,
  menu_name,
  target_table,
  target_column,
  default_template,
  default_reset_cycle,
  remark
) as (
  values
    ('hr.employee', '员工编号', '员工工号', 'master_data', 'HrEmployeeRoster', 'hr_employee', 'employee_no', 'EMP{YYYYMM}{SEQ:3}', 'month', '员工花名册主档编号'),
    ('hr.position', '岗位编号', '岗位编码', 'master_data', 'HrPosition', 'hr_position', 'position_code', 'POS{YYYYMM}{SEQ:3}', 'month', '岗位主数据编码'),
    ('hr.employee_contract', '劳动合同编号', '合同编号', 'business_document', 'HrCompliance', 'hr_employee_contract', 'contract_no', 'HRC{YYYYMM}{SEQ:4}', 'month', '员工劳动合同编号'),
    ('hr.personnel_change', '人事异动编号', '异动单号', 'business_document', 'HrPersonnelChange', 'hr_personnel_change', 'change_no', 'HRCG{YYYYMMDD}{SEQ:3}', 'day', '转正、调动、晋升与离职异动单号'),
    ('hr.lifecycle_case', '生命周期事项编号', '事项编号', 'business_document', 'HrLifecycle', 'hr_lifecycle_case', 'case_no', 'HRLC{YYYYMMDD}{SEQ:3}', 'day', '入转调离生命周期事项编号'),
    ('hr.self_service_request', '员工自助申请编号', '申请编号', 'business_document', 'HrSelfService', 'hr_self_service_request', 'request_no', 'HRSS{YYYYMMDD}{SEQ:4}', 'day', '请假、加班与员工自助申请编号'),
    ('hr.recruitment_requisition', '招聘需求编号', '需求编号', 'business_document', 'HrRecruitment', 'hr_recruitment_requisition', 'requisition_no', 'HRRQ{YYYYMM}{SEQ:4}', 'month', '招聘需求审批单号')
)
insert into public.sys_document_number_scene (
  rule_key,
  rule_name,
  field_label,
  category,
  menu_id,
  target_table,
  target_column,
  default_template,
  default_reset_cycle,
  manual_required,
  enabled,
  remark,
  tenant_id,
  create_by,
  update_by
)
select
  definition.rule_key,
  definition.rule_name,
  definition.field_label,
  definition.category,
  menu.id,
  definition.target_table,
  definition.target_column,
  definition.default_template,
  definition.default_reset_cycle,
  true,
  true,
  definition.remark,
  platform_tenant.id,
  'migration',
  'migration'
from scene_definition definition
join public.sys_menu menu on menu.name = definition.menu_name
join public.sys_tenant platform_tenant on platform_tenant.tenant_code = 'platform'
on conflict (rule_key) do update set
  rule_name = excluded.rule_name,
  field_label = excluded.field_label,
  category = excluded.category,
  menu_id = excluded.menu_id,
  target_table = excluded.target_table,
  target_column = excluded.target_column,
  default_template = excluded.default_template,
  default_reset_cycle = excluded.default_reset_cycle,
  manual_required = excluded.manual_required,
  enabled = true,
  remark = excluded.remark,
  update_by = 'migration',
  update_time = now();

insert into public.sys_document_number_rule (
  id,
  tenant_id,
  rule_key,
  rule_name,
  category,
  target_table,
  target_column,
  auto_enabled,
  template,
  reset_cycle,
  sequence_start,
  timezone,
  rule_version,
  manual_required,
  builtin,
  enabled,
  remark,
  create_by,
  update_by
)
select
  gen_random_uuid(),
  tenant.id,
  scene.rule_key,
  scene.rule_name,
  scene.category,
  scene.target_table,
  scene.target_column,
  true,
  scene.default_template,
  scene.default_reset_cycle,
  1,
  'Asia/Shanghai',
  1,
  scene.manual_required,
  true,
  true,
  scene.remark,
  'migration',
  'migration'
from public.sys_document_number_scene scene
cross join public.sys_tenant tenant
where scene.rule_key = any(array[
  'hr.employee',
  'hr.position',
  'hr.employee_contract',
  'hr.personnel_change',
  'hr.lifecycle_case',
  'hr.self_service_request',
  'hr.recruitment_requisition'
])
  and tenant.status = '1'
on conflict (tenant_id, rule_key) do nothing;

drop trigger if exists document_number_position_code on public.hr_position;
create trigger document_number_position_code
before insert on public.hr_position
for each row execute function app_private.trg_assign_configurable_number(
  'hr.position',
  'position_code'
);

drop trigger if exists document_number_personnel_change_no on public.hr_personnel_change;
create trigger document_number_personnel_change_no
before insert on public.hr_personnel_change
for each row execute function app_private.trg_assign_configurable_number(
  'hr.personnel_change',
  'change_no'
);

drop trigger if exists document_number_lifecycle_case_no on public.hr_lifecycle_case;
create trigger document_number_lifecycle_case_no
before insert on public.hr_lifecycle_case
for each row execute function app_private.trg_assign_configurable_number(
  'hr.lifecycle_case',
  'case_no'
);

drop trigger if exists document_number_self_service_request_no on public.hr_self_service_request;
create trigger document_number_self_service_request_no
before insert on public.hr_self_service_request
for each row execute function app_private.trg_assign_configurable_number(
  'hr.self_service_request',
  'request_no'
);

drop trigger if exists document_number_recruitment_requisition_no on public.hr_recruitment_requisition;
create trigger document_number_recruitment_requisition_no
before insert on public.hr_recruitment_requisition
for each row execute function app_private.trg_assign_configurable_number(
  'hr.recruitment_requisition',
  'requisition_no'
);

create or replace function app_private.trg_assign_hr_contract_number()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule public.sys_document_number_rule;
  v_current text;
  v_override text;
  v_value text;
begin
  -- The employee profile saves children with INSERT .. ON CONFLICT. Preserve the
  -- existing contract number instead of consuming and replacing it on every edit.
  if new.id is not null and exists (
    select 1 from public.hr_employee_contract existing where existing.id = new.id
  ) then
    return new;
  end if;

  select * into v_rule
  from public.sys_document_number_rule
  where tenant_id = new.tenant_id
    and rule_key = 'hr.employee_contract'
    and enabled;
  if not found then
    raise exception '未找到已启用的编号规则：hr.employee_contract';
  end if;

  v_current := nullif(btrim(coalesce(new.contract_no, '')), '');
  v_override := nullif(btrim(current_setting(
    'app.document_number.hr_employee_contract', true
  )), '');
  if v_rule.auto_enabled then
    v_value := app_private.next_document_number('hr.employee_contract', new.tenant_id);
  else
    v_value := coalesce(v_current, v_override);
    if v_rule.manual_required and v_value is null then
      raise exception '%未启用自动编码，请手工填写', v_rule.rule_name;
    end if;
  end if;
  new.contract_no := v_value;
  return new;
end;
$$;

drop trigger if exists document_number_employee_contract_no on public.hr_employee_contract;
create trigger document_number_employee_contract_no
before insert on public.hr_employee_contract
for each row execute function app_private.trg_assign_hr_contract_number();

notify pgrst, 'reload schema';

;
