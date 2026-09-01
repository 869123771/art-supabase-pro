-- Cover composite foreign keys used by voucher-template lookups and parent deletes.

create index if not exists fms_voucher_template_account_set_tenant_fk_idx
  on public.fms_voucher_template(account_set_id, tenant_id);

create index if not exists fms_voucher_template_line_template_tenant_fk_idx
  on public.fms_voucher_template_line(template_id, account_set_id, tenant_id);

create index if not exists fms_voucher_template_line_subject_tenant_fk_idx
  on public.fms_voucher_template_line(subject_id, account_set_id, tenant_id);

create index if not exists fms_voucher_template_line_currency_tenant_fk_idx
  on public.fms_voucher_template_line(currency_id, account_set_id, tenant_id)
  where currency_id is not null;

;
