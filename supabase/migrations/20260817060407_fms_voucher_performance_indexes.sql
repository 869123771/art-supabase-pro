begin;

create index if not exists fms_voucher_account_set_fk_idx
  on public.fms_voucher (account_set_id);
create index if not exists fms_voucher_period_fk_idx
  on public.fms_voucher (accounting_period_id);
create index if not exists fms_voucher_reversal_fk_idx
  on public.fms_voucher (reversal_voucher_id)
  where reversal_voucher_id is not null;

create index if not exists fms_voucher_action_voucher_fk_idx
  on public.fms_voucher_action (voucher_id);

create index if not exists fms_voucher_line_voucher_fk_idx
  on public.fms_voucher_line (voucher_id);
create index if not exists fms_voucher_line_subject_fk_idx
  on public.fms_voucher_line (subject_id);
create index if not exists fms_voucher_line_currency_fk_idx
  on public.fms_voucher_line (currency_id)
  where currency_id is not null;

create index if not exists fms_voucher_counter_account_set_fk_idx
  on public.fms_voucher_number_counter (account_set_id);

create index if not exists fms_voucher_template_account_set_fk_idx
  on public.fms_voucher_template (account_set_id);
create index if not exists fms_voucher_template_line_template_fk_idx
  on public.fms_voucher_template_line (template_id);
create index if not exists fms_voucher_template_line_subject_fk_idx
  on public.fms_voucher_template_line (subject_id);
create index if not exists fms_voucher_template_line_currency_fk_idx
  on public.fms_voucher_template_line (currency_id)
  where currency_id is not null;

commit;;
