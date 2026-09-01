begin;
create index if not exists fms_accounting_period_account_set_tenant_idx
  on public.fms_accounting_period (account_set_id, tenant_id);
create index if not exists fms_currency_account_set_tenant_idx
  on public.fms_currency (account_set_id, tenant_id);
create index if not exists fms_exchange_rate_account_set_tenant_idx
  on public.fms_exchange_rate (account_set_id, tenant_id);
create index if not exists fms_exchange_rate_currency_scope_idx
  on public.fms_exchange_rate (currency_id, account_set_id, tenant_id);
create index if not exists fms_auxiliary_type_account_set_tenant_idx
  on public.fms_auxiliary_type (account_set_id, tenant_id);
create index if not exists fms_auxiliary_item_account_set_tenant_idx
  on public.fms_auxiliary_item (account_set_id, tenant_id);
create index if not exists fms_auxiliary_item_type_scope_idx
  on public.fms_auxiliary_item (auxiliary_type_id, account_set_id, tenant_id);
create index if not exists fms_subject_account_set_tenant_idx
  on public.fms_subject (account_set_id, tenant_id);
create index if not exists fms_subject_parent_scope_idx
  on public.fms_subject (parent_id, account_set_id, tenant_id);
create index if not exists fms_subject_auxiliary_account_set_tenant_idx
  on public.fms_subject_auxiliary_type (account_set_id, tenant_id);
create index if not exists fms_subject_auxiliary_subject_scope_idx
  on public.fms_subject_auxiliary_type (subject_id, account_set_id, tenant_id);
create index if not exists fms_subject_auxiliary_type_scope_idx
  on public.fms_subject_auxiliary_type (auxiliary_type_id, account_set_id, tenant_id);
create index if not exists fms_opening_balance_account_set_tenant_idx
  on public.fms_opening_balance (account_set_id, tenant_id);
create index if not exists fms_opening_balance_subject_scope_idx
  on public.fms_opening_balance (subject_id, account_set_id, tenant_id);
create index if not exists fms_opening_balance_currency_scope_idx
  on public.fms_opening_balance (currency_id, account_set_id, tenant_id);
create index if not exists fms_opening_balance_control_account_set_tenant_idx
  on public.fms_opening_balance_control (account_set_id, tenant_id);
commit;
