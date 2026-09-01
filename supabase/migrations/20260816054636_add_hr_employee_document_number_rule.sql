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
  create_by,
  update_by,
  tenant_id
)
select
  'hr.employee',
  '员工编号',
  '员工工号',
  'master_data',
  menu.id,
  'hr_employee',
  'employee_no',
  'EMP{YYYYMM}{SEQ:3}',
  'month',
  true,
  true,
  '用于员工花名册新增档案的员工编号，可按租户切换自动编码或手工填写。',
  'migration',
  'migration',
  scene_tenant.tenant_id
from public.sys_menu menu
cross join lateral (
  select tenant_id
  from public.sys_document_number_scene
  order by create_time
  limit 1
) scene_tenant
where menu.name = 'HrEmployeeRoster'
  and not exists (
    select 1 from public.sys_document_number_scene where rule_key = 'hr.employee'
  );

insert into public.sys_document_number_rule (
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
  manual_required,
  builtin,
  enabled,
  remark,
  create_by,
  update_by
)
select
  tenant.id,
  'hr.employee',
  '员工编号',
  'master_data',
  'hr_employee',
  'employee_no',
  true,
  'EMP{YYYYMM}{SEQ:3}',
  'month',
  1,
  'Asia/Shanghai',
  true,
  true,
  true,
  '员工档案新增时按租户规则生成员工编号。',
  'migration',
  'migration'
from public.sys_tenant tenant
where not exists (
  select 1
  from public.sys_document_number_rule rule
  where rule.tenant_id = tenant.id and rule.rule_key = 'hr.employee'
);

drop trigger if exists document_number_employee_no on public.hr_employee;
create trigger document_number_employee_no
before insert on public.hr_employee
for each row execute function app_private.trg_assign_configurable_number('hr.employee', 'employee_no');;
