begin;

create index if not exists fms_commercial_bill_account_set_fk_idx
  on public.fms_commercial_bill(account_set_id,tenant_id);
create index if not exists fms_commercial_bill_event_bill_fk_idx
  on public.fms_commercial_bill_event(bill_id,account_set_id,tenant_id);
create index if not exists fms_commercial_bill_event_fund_account_fk_idx
  on public.fms_commercial_bill_event(fund_account_id,account_set_id,tenant_id) where fund_account_id is not null;
create index if not exists fms_commercial_bill_event_voucher_fk_idx
  on public.fms_commercial_bill_event(voucher_id,account_set_id,tenant_id) where voucher_id is not null;

create index if not exists fms_asset_category_account_set_fk_idx
  on public.fms_asset_category(account_set_id,tenant_id);
create index if not exists fms_asset_category_asset_subject_fk_idx
  on public.fms_asset_category(asset_subject_id,account_set_id,tenant_id) where asset_subject_id is not null;
create index if not exists fms_asset_category_accumulated_subject_fk_idx
  on public.fms_asset_category(accumulated_depreciation_subject_id,account_set_id,tenant_id)
  where accumulated_depreciation_subject_id is not null;
create index if not exists fms_asset_category_expense_subject_fk_idx
  on public.fms_asset_category(depreciation_expense_subject_id,account_set_id,tenant_id)
  where depreciation_expense_subject_id is not null;
create index if not exists fms_asset_category_disposal_subject_fk_idx
  on public.fms_asset_category(disposal_subject_id,account_set_id,tenant_id) where disposal_subject_id is not null;

create index if not exists fms_fixed_asset_account_set_fk_idx
  on public.fms_fixed_asset(account_set_id,tenant_id);
create index if not exists fms_fixed_asset_category_fk_idx
  on public.fms_fixed_asset(category_id,account_set_id,tenant_id);
create index if not exists fms_fixed_asset_employee_fk_idx
  on public.fms_fixed_asset(employee_id,tenant_id) where employee_id is not null;

create index if not exists fms_asset_depreciation_run_period_fk_idx
  on public.fms_asset_depreciation_run(accounting_period_id,account_set_id,tenant_id);
create index if not exists fms_asset_depreciation_run_voucher_fk_idx
  on public.fms_asset_depreciation_run(voucher_id,account_set_id,tenant_id) where voucher_id is not null;
create index if not exists fms_asset_depreciation_line_run_fk_idx
  on public.fms_asset_depreciation_line(run_id,account_set_id,tenant_id);
create index if not exists fms_asset_depreciation_line_asset_fk_idx
  on public.fms_asset_depreciation_line(asset_id,account_set_id,tenant_id);

create index if not exists fms_payroll_run_period_fk_idx
  on public.fms_payroll_run(accounting_period_id,account_set_id,tenant_id);
create index if not exists fms_payroll_run_salary_expense_fk_idx
  on public.fms_payroll_run(salary_expense_subject_id,account_set_id,tenant_id) where salary_expense_subject_id is not null;
create index if not exists fms_payroll_run_salary_payable_fk_idx
  on public.fms_payroll_run(salary_payable_subject_id,account_set_id,tenant_id) where salary_payable_subject_id is not null;
create index if not exists fms_payroll_run_tax_payable_fk_idx
  on public.fms_payroll_run(tax_payable_subject_id,account_set_id,tenant_id) where tax_payable_subject_id is not null;
create index if not exists fms_payroll_run_social_payable_fk_idx
  on public.fms_payroll_run(social_security_payable_subject_id,account_set_id,tenant_id)
  where social_security_payable_subject_id is not null;
create index if not exists fms_payroll_run_voucher_fk_idx
  on public.fms_payroll_run(voucher_id,account_set_id,tenant_id) where voucher_id is not null;
create index if not exists fms_payroll_line_run_fk_idx
  on public.fms_payroll_line(run_id,account_set_id,tenant_id);
create index if not exists fms_payroll_line_employee_fk_idx
  on public.fms_payroll_line(employee_id,tenant_id);

create index if not exists fms_tax_period_period_fk_idx
  on public.fms_tax_period(accounting_period_id,account_set_id,tenant_id);
create index if not exists fms_tax_ledger_line_period_fk_idx
  on public.fms_tax_ledger_line(tax_period_id,account_set_id,tenant_id);

create index if not exists fms_period_close_run_period_fk_idx
  on public.fms_period_close_run(accounting_period_id,account_set_id,tenant_id);
create index if not exists fms_period_close_run_profit_voucher_fk_idx
  on public.fms_period_close_run(profit_loss_voucher_id,account_set_id,tenant_id) where profit_loss_voucher_id is not null;
create index if not exists fms_period_close_run_year_end_voucher_fk_idx
  on public.fms_period_close_run(year_end_voucher_id,account_set_id,tenant_id) where year_end_voucher_id is not null;
create index if not exists fms_period_close_check_run_fk_idx
  on public.fms_period_close_check(close_run_id,account_set_id,tenant_id);

commit;

;
