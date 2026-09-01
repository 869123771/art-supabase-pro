begin;

-- These names deliberately differ from legacy single-column indexes. The first
-- migration could not widen those indexes because CREATE INDEX IF NOT EXISTS
-- only compares names, not index definitions.
create index if not exists fms_voucher_period_covering_fk_idx
  on public.fms_voucher (accounting_period_id, account_set_id, tenant_id);

create index if not exists fms_voucher_action_voucher_covering_fk_idx
  on public.fms_voucher_action (voucher_id, account_set_id, tenant_id);

create index if not exists fms_voucher_line_subject_covering_fk_idx
  on public.fms_voucher_line (subject_id, account_set_id, tenant_id);

commit;;
