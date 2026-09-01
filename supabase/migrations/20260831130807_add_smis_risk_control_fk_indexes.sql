-- Add covering indexes in the same column order as the employee and task-item
-- foreign keys introduced by the risk-control lifecycle migration.

create index if not exists smis_risk_control_assignment_employee_fk_idx
  on public.smis_risk_control_assignment(responsible_employee_id, tenant_id);

create index if not exists smis_risk_inspection_task_responsible_fk_idx
  on public.smis_risk_inspection_task(responsible_employee_id, tenant_id);

create index if not exists smis_risk_inspection_task_assignee_fk_idx
  on public.smis_risk_inspection_task(assignee_employee_id, tenant_id);

create index if not exists smis_risk_inspection_task_executor_fk_idx
  on public.smis_risk_inspection_task(actual_executor_employee_id, tenant_id)
  where actual_executor_employee_id is not null;

create index if not exists smis_risk_inspection_task_item_risk_item_fk_idx
  on public.smis_risk_inspection_task_item(tenant_id, risk_item_id)
  where risk_item_id is not null;

create index if not exists smis_risk_inspection_task_item_measure_fk_idx
  on public.smis_risk_inspection_task_item(tenant_id, control_measure_id)
  where control_measure_id is not null;

;
