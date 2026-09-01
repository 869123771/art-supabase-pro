
drop index if exists public.hr_employee_contract_employee_id_idx;
drop index if exists public.hr_employee_education_employee_id_idx;
drop index if exists public.hr_employee_work_experience_employee_id_idx;
drop index if exists public.hr_employee_training_employee_id_idx;
drop index if exists public.hr_employee_reward_employee_id_idx;

create index if not exists hr_employee_contract_employee_tenant_idx
  on public.hr_employee_contract (employee_id, tenant_id);
create index if not exists hr_employee_education_employee_tenant_idx
  on public.hr_employee_education (employee_id, tenant_id);
create index if not exists hr_employee_work_experience_employee_tenant_idx
  on public.hr_employee_work_experience (employee_id, tenant_id);
create index if not exists hr_employee_training_employee_tenant_idx
  on public.hr_employee_training (employee_id, tenant_id);
create index if not exists hr_employee_reward_employee_tenant_idx
  on public.hr_employee_reward (employee_id, tenant_id);
;
