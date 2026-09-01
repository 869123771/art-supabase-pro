begin;

drop index if exists public.fms_voucher_account_set_fk_idx;
drop index if exists public.fms_voucher_line_voucher_fk_idx;
drop index if exists public.fms_voucher_line_currency_fk_idx;
drop index if exists public.fms_voucher_counter_account_set_fk_idx;
drop index if exists public.fms_voucher_template_account_set_fk_idx;
drop index if exists public.fms_voucher_template_line_template_fk_idx;
drop index if exists public.fms_voucher_template_line_subject_fk_idx;
drop index if exists public.fms_voucher_template_line_currency_fk_idx;

commit;;
