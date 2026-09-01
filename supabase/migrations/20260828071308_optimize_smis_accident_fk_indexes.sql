-- Align covering-index column order with the composite foreign-key order so
-- parent updates/deletes and FK validation can use the index directly.
drop index if exists public.smis_accident_report_tenant_reporter_idx;
create index smis_accident_report_tenant_reporter_idx
  on public.smis_accident_report (reporter_employee_id, tenant_id);
drop index if exists public.smis_accident_measure_report_idx;
create index smis_accident_measure_report_idx
  on public.smis_accident_prevention_measure (accident_report_id, tenant_id, sort);
drop index if exists public.smis_accident_measure_responsible_idx;
create index smis_accident_measure_responsible_idx
  on public.smis_accident_prevention_measure (responsible_employee_id, tenant_id)
  where responsible_employee_id is not null;
drop index if exists public.smis_accident_person_report_idx;
create index smis_accident_person_report_idx
  on public.smis_accident_person (accident_report_id, tenant_id, sort);
drop index if exists public.smis_accident_person_employee_idx;
create index smis_accident_person_employee_idx
  on public.smis_accident_person (employee_id, tenant_id);
drop index if exists public.smis_work_injury_declaration_report_idx;
create index smis_work_injury_declaration_report_idx
  on public.smis_work_injury_declaration (accident_report_id, tenant_id);
drop index if exists public.smis_work_injury_declaration_employee_idx;
create index smis_work_injury_declaration_employee_idx
  on public.smis_work_injury_declaration (declarant_employee_id, tenant_id);
