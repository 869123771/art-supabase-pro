-- Make the compensation boundary explicit for database audits: business tables are
-- never accessed directly by signed-in users; permission-checked RPCs are the only
-- public API. Also add indexes whose leading columns exactly match every FK.

create policy hr_pay_component_deny_direct_access
  on public.hr_pay_component
  for all
  to authenticated
  using (false)
  with check (false)

create policy hr_compensation_plan_deny_direct_access
  on public.hr_compensation_plan
  for all
  to authenticated
  using (false)
  with check (false)

create policy hr_compensation_plan_item_deny_direct_access
  on public.hr_compensation_plan_item
  for all
  to authenticated
  using (false)
  with check (false)

create policy hr_salary_band_deny_direct_access
  on public.hr_salary_band
  for all
  to authenticated
  using (false)
  with check (false)

create policy hr_employee_compensation_deny_direct_access
  on public.hr_employee_compensation
  for all
  to authenticated
  using (false)
  with check (false)

create policy hr_employee_compensation_item_deny_direct_access
  on public.hr_employee_compensation_item
  for all
  to authenticated
  using (false)
  with check (false)

create index hr_compensation_plan_item_tenant_idx
  on public.hr_compensation_plan_item(tenant_id)

create index hr_employee_compensation_employee_fk_idx
  on public.hr_employee_compensation(employee_id, tenant_id)

create index hr_employee_compensation_source_change_fk_idx
  on public.hr_employee_compensation(source_change_id)
  where source_change_id is not null

create index hr_employee_compensation_item_tenant_idx
  on public.hr_employee_compensation_item(tenant_id)
