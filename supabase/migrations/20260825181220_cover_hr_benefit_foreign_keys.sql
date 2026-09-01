-- Cover composite benefit foreign keys in their declared column order.
create index if not exists hr_benefit_option_plan_fk_idx
  on public.hr_benefit_option(plan_id, tenant_id);
create index if not exists hr_benefit_option_pay_component_fk_idx
  on public.hr_benefit_option(pay_component_id, tenant_id)
  where pay_component_id is not null;
create index if not exists hr_benefit_life_event_employee_fk_idx
  on public.hr_benefit_life_event(employee_id, tenant_id);
create index if not exists hr_employee_benefit_enrollment_employee_fk_idx
  on public.hr_employee_benefit_enrollment(employee_id, tenant_id);
create index if not exists hr_employee_benefit_enrollment_plan_fk_idx
  on public.hr_employee_benefit_enrollment(plan_id, tenant_id);
create index if not exists hr_employee_benefit_enrollment_option_fk_idx
  on public.hr_employee_benefit_enrollment(option_id, tenant_id);
create index if not exists hr_employee_benefit_enrollment_event_fk_idx
  on public.hr_employee_benefit_enrollment(life_event_id, tenant_id)
  where life_event_id is not null;
create index if not exists hr_benefit_event_actor_fk_idx
  on public.hr_benefit_event(actor_user_id, tenant_id)
  where actor_user_id is not null;

;
