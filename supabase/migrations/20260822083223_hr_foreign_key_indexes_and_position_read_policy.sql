-- Cover every HR foreign key in its declared column order.
create index if not exists hr_attendance_employee_fk_idx on public.hr_attendance_record(employee_id,tenant_id);
create index if not exists hr_attendance_shift_fk_idx on public.hr_attendance_record(shift_id,tenant_id);
create index if not exists hr_candidate_onboard_employee_fk_idx on public.hr_candidate(onboard_employee_id,tenant_id);
create index if not exists hr_candidate_requisition_fk_idx on public.hr_candidate(requisition_id,tenant_id);
create index if not exists hr_employee_position_fk_idx on public.hr_employee(position_id,tenant_id);
create index if not exists hr_employee_competency_competency_fk_idx on public.hr_employee_competency(competency_id,tenant_id);
create index if not exists hr_employee_competency_employee_fk_idx on public.hr_employee_competency(employee_id,tenant_id);
create index if not exists hr_employee_competency_assessor_fk_idx on public.hr_employee_competency(tenant_id,assessor_user_id);
create index if not exists hr_employee_qualification_employee_fk_idx on public.hr_employee_qualification(employee_id,tenant_id);
create index if not exists hr_lifecycle_case_employee_fk_idx on public.hr_lifecycle_case(employee_id,tenant_id);
create index if not exists hr_lifecycle_case_owner_fk_idx on public.hr_lifecycle_case(tenant_id,owner_user_id);
create index if not exists hr_lifecycle_task_case_fk_idx on public.hr_lifecycle_task(lifecycle_case_id,tenant_id);
create index if not exists hr_lifecycle_task_responsible_fk_idx on public.hr_lifecycle_task(tenant_id,responsible_user_id);
create index if not exists hr_performance_goal_review_fk_idx on public.hr_performance_goal(review_id,tenant_id);
create index if not exists hr_performance_review_cycle_fk_idx on public.hr_performance_review(cycle_id,tenant_id);
create index if not exists hr_performance_review_employee_fk_idx on public.hr_performance_review(employee_id,tenant_id);
create index if not exists hr_performance_review_reviewer_fk_idx on public.hr_performance_review(tenant_id,reviewer_user_id);
create index if not exists hr_personnel_change_employee_fk_idx on public.hr_personnel_change(employee_id,tenant_id);
create index if not exists hr_personnel_change_from_position_fk_idx on public.hr_personnel_change(from_position_id,tenant_id);
create index if not exists hr_personnel_change_to_position_fk_idx on public.hr_personnel_change(to_position_id,tenant_id);
create index if not exists hr_position_competency_competency_fk_idx on public.hr_position_competency(competency_id,tenant_id);
create index if not exists hr_position_competency_position_fk_idx on public.hr_position_competency(position_id,tenant_id);
create index if not exists hr_position_headcount_organization_fk_idx on public.hr_position_headcount(organization_id);
create index if not exists hr_position_headcount_position_fk_idx on public.hr_position_headcount(position_id,tenant_id);
create index if not exists hr_recruitment_organization_fk_idx on public.hr_recruitment_requisition(organization_id);
create index if not exists hr_recruitment_position_fk_idx on public.hr_recruitment_requisition(position_id,tenant_id);
create index if not exists hr_self_service_employee_fk_idx on public.hr_self_service_request(employee_id,tenant_id);
create index if not exists hr_shift_assignment_employee_fk_idx on public.hr_shift_assignment(employee_id,tenant_id);
create index if not exists hr_shift_assignment_shift_fk_idx on public.hr_shift_assignment(shift_id,tenant_id);
create index if not exists hr_training_enrollment_employee_fk_idx on public.hr_training_enrollment(employee_id,tenant_id);
create index if not exists hr_training_enrollment_plan_fk_idx on public.hr_training_enrollment(plan_id,tenant_id);

create policy hr_position_tenant_select
on public.hr_position for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id=(select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:Position:View'))
      or (select app_private.has_permission('Hr:PersonnelChange:View'))
      or (select app_private.has_permission('Hr:Headcount:View'))
      or (select app_private.has_permission('Hr:Talent:View'))
      or (select app_private.has_permission('Hr:Recruitment:View'))
    )
  )
);

-- Renamed wrappers are internal implementation details; only the current public facade is callable.
revoke all on function public.hr_submit_approval_before_hr_p1(text,uuid) from public,anon,authenticated;
revoke all on function public.hr_submit_approval_before_hr_p2(text,uuid) from public,anon,authenticated;
;
