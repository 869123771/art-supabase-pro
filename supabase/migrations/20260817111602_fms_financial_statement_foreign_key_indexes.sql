begin;

drop index if exists public.fms_financial_statement_item_parent_idx;
drop index if exists public.fms_financial_statement_mapping_item_idx;
drop index if exists public.fms_financial_statement_mapping_subject_idx;
drop index if exists public.fms_financial_statement_formula_target_idx;
drop index if exists public.fms_financial_statement_formula_source_idx;
drop index if exists public.fms_cash_flow_allocation_line_idx;
drop index if exists public.fms_posting_rule_line_cash_flow_item_idx;

create index fms_financial_statement_item_account_set_fk_idx
  on public.fms_financial_statement_item (account_set_id, tenant_id);
create index fms_financial_statement_item_parent_fk_idx
  on public.fms_financial_statement_item (parent_id, account_set_id, tenant_id)
  where parent_id is not null;

create index fms_financial_statement_mapping_item_fk_idx
  on public.fms_financial_statement_mapping (
    statement_item_id, account_set_id, tenant_id
  );
create index fms_financial_statement_mapping_subject_fk_idx
  on public.fms_financial_statement_mapping (subject_id, account_set_id, tenant_id);

create index fms_financial_statement_formula_target_fk_idx
  on public.fms_financial_statement_formula (target_item_id, account_set_id, tenant_id);
create index fms_financial_statement_formula_source_fk_idx
  on public.fms_financial_statement_formula (source_item_id, account_set_id, tenant_id);

create index fms_cash_flow_allocation_line_fk_idx
  on public.fms_cash_flow_allocation (voucher_line_id, account_set_id, tenant_id);
create index fms_cash_flow_allocation_item_fk_idx
  on public.fms_cash_flow_allocation (statement_item_id, account_set_id, tenant_id);

create index fms_posting_rule_line_cash_flow_item_fk_idx
  on public.fms_posting_rule_line (cash_flow_item_id, account_set_id, tenant_id)
  where cash_flow_item_id is not null;

commit;

;
