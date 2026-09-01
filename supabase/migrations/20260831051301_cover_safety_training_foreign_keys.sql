begin;

drop index if exists public.smis_safety_training_plan_organizer_idx;
drop index if exists public.smis_safety_training_plan_target_idx;
drop index if exists public.smis_safety_training_plan_responsible_idx;
drop index if exists public.smis_safety_training_plan_participant_plan_idx;
drop index if exists public.smis_safety_training_plan_participant_employee_idx;
drop index if exists public.smis_safety_training_record_plan_idx;
drop index if exists public.smis_safety_training_record_participant_record_idx;
drop index if exists public.smis_safety_training_record_participant_employee_idx;

create index smis_safety_training_plan_organizer_idx
  on public.smis_safety_training_plan (organizer_organization_id, tenant_id);
create index smis_safety_training_plan_target_idx
  on public.smis_safety_training_plan (target_organization_id, tenant_id);
create index smis_safety_training_plan_responsible_idx
  on public.smis_safety_training_plan (responsible_employee_id, tenant_id);
create index smis_safety_training_plan_participant_plan_idx
  on public.smis_safety_training_plan_participant (training_plan_id, tenant_id);
create index smis_safety_training_plan_participant_employee_idx
  on public.smis_safety_training_plan_participant (employee_id, tenant_id);
create index smis_safety_training_record_plan_idx
  on public.smis_safety_training_record (training_plan_id, tenant_id);
create index smis_safety_training_record_participant_record_idx
  on public.smis_safety_training_record_participant (training_record_id, tenant_id);
create index smis_safety_training_record_participant_employee_idx
  on public.smis_safety_training_record_participant (employee_id, tenant_id);

commit;

;
