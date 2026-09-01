begin;

create index if not exists fms_fund_account_account_set_fk_idx
  on public.fms_fund_account (account_set_id, tenant_id);

create index if not exists fms_fund_transfer_account_set_fk_idx
  on public.fms_fund_transfer (account_set_id, tenant_id);

commit;

;
