begin;

create index if not exists idx_smis_business_record_created_by
  on public.smis_business_record (created_by)
  where created_by is not null;

create index if not exists idx_smis_business_event_operator
  on public.smis_business_event (operator_id)
  where operator_id is not null;

create index if not exists idx_smis_exam_attempt_user
  on public.smis_exam_attempt (user_id, started_at desc);

commit;

;
