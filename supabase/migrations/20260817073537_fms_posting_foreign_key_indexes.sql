begin;

create index if not exists fms_posting_rule_account_set_fk_idx
  on public.fms_posting_rule (account_set_id, tenant_id);

create index if not exists fms_posting_rule_line_rule_scope_fk_idx
  on public.fms_posting_rule_line (rule_id, account_set_id, tenant_id);

create index if not exists fms_posting_rule_line_subject_scope_fk_idx
  on public.fms_posting_rule_line (subject_id, account_set_id, tenant_id);

create index if not exists fms_posting_event_account_set_scope_fk_idx
  on public.fms_posting_event (account_set_id, tenant_id);

drop index if exists public.fms_posting_rule_line_subject_idx;

commit;;
