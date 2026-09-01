begin;

-- Keep the referencing side of composite foreign keys indexed so parent-row
-- updates/deletes and tenant-scoped joins do not degrade into sequential scans.
create index if not exists fms_voucher_account_set_tenant_fk_idx
  on public.fms_voucher (account_set_id, tenant_id);

create index if not exists fms_voucher_period_fk_idx
  on public.fms_voucher (accounting_period_id, account_set_id, tenant_id);

create index if not exists fms_voucher_action_voucher_fk_idx
  on public.fms_voucher_action (voucher_id, account_set_id, tenant_id);

create index if not exists fms_voucher_line_currency_fk_idx
  on public.fms_voucher_line (currency_id, account_set_id, tenant_id);

create index if not exists fms_voucher_line_subject_fk_idx
  on public.fms_voucher_line (subject_id, account_set_id, tenant_id);

create index if not exists fms_voucher_line_voucher_fk_idx
  on public.fms_voucher_line (voucher_id, account_set_id, tenant_id);

create index if not exists fms_voucher_counter_account_set_tenant_fk_idx
  on public.fms_voucher_number_counter (account_set_id, tenant_id);

create index if not exists smis_accident_case_creator_tenant_fk_idx
  on public.smis_accident_case (created_by_user_id, tenant_id);

commit;;
