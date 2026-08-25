alter table public.hr_performance_review
  add column if not exists calibration_comment text;
