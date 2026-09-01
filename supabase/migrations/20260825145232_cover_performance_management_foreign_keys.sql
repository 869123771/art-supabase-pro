create index if not exists hr_performance_check_in_review_fk_idx
  on public.hr_performance_check_in(review_id, tenant_id);

create index if not exists hr_performance_calibration_session_cycle_fk_idx
  on public.hr_performance_calibration_session(cycle_id, tenant_id);

create index if not exists hr_performance_calibration_item_session_fk_idx
  on public.hr_performance_calibration_item(session_id, tenant_id);

;
