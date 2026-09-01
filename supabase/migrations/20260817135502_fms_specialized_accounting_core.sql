begin;

create table public.fms_commercial_bill (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  bill_no text not null,
  external_bill_no text,
  direction text not null,
  bill_type text not null,
  status text not null default 'draft',
  drawer_name text not null,
  payee_name text not null,
  acceptor_name text not null,
  counterparty_name text,
  issue_date date not null,
  due_date date not null,
  face_amount numeric(20, 2) not null,
  settled_amount numeric(20, 2) not null default 0,
  currency_code text not null default 'CNY',
  transferable boolean not null default true,
  source_type text,
  source_id uuid,
  source_no text,
  attachment_ids jsonb not null default '[]'::jsonb,
  remark text,
  version bigint not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_commercial_bill_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_commercial_bill_direction_check
    check (direction in ('receivable', 'payable')),
  constraint fms_commercial_bill_type_check
    check (bill_type in ('bank_acceptance', 'commercial_acceptance', 'digital')),
  constraint fms_commercial_bill_status_check
    check (status in ('draft', 'held', 'endorsed', 'discounted', 'settled', 'cancelled')),
  constraint fms_commercial_bill_dates_check check (issue_date <= due_date),
  constraint fms_commercial_bill_amount_check
    check (face_amount > 0 and settled_amount >= 0 and settled_amount <= face_amount),
  constraint fms_commercial_bill_currency_format check (currency_code ~ '^[A-Z]{3}$'),
  constraint fms_commercial_bill_no_not_blank check (btrim(bill_no) <> ''),
  constraint fms_commercial_bill_party_not_blank check (
    btrim(drawer_name) <> '' and btrim(payee_name) <> '' and btrim(acceptor_name) <> ''
  ),
  constraint fms_commercial_bill_version_check check (version > 0),
  constraint fms_commercial_bill_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_commercial_bill_scope_no_key unique (account_set_id, bill_no)
);

create index fms_commercial_bill_lookup_idx
  on public.fms_commercial_bill (tenant_id, account_set_id, direction, status, due_date);
create index fms_commercial_bill_source_idx
  on public.fms_commercial_bill (tenant_id, source_type, source_id)
  where source_id is not null;

create table public.fms_commercial_bill_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  bill_id uuid not null,
  event_type text not null,
  event_date date not null,
  amount numeric(20, 2) not null,
  counterparty_name text,
  fund_account_id uuid,
  reference_no text,
  voucher_id uuid,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_commercial_bill_event_bill_fkey
    foreign key (bill_id, account_set_id, tenant_id)
    references public.fms_commercial_bill(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_commercial_bill_event_fund_account_fkey
    foreign key (fund_account_id, account_set_id, tenant_id)
    references public.fms_fund_account(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_commercial_bill_event_voucher_fkey
    foreign key (voucher_id, account_set_id, tenant_id)
    references public.fms_voucher(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_commercial_bill_event_type_check
    check (event_type in ('received', 'issued', 'endorsed', 'discounted', 'settled', 'cancelled')),
  constraint fms_commercial_bill_event_amount_check check (amount >= 0),
  constraint fms_commercial_bill_event_id_scope_key unique (id, account_set_id, tenant_id)
);

create index fms_commercial_bill_event_bill_idx
  on public.fms_commercial_bill_event (tenant_id, account_set_id, bill_id, event_date desc);

create table public.fms_asset_category (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  category_code text not null,
  category_name text not null,
  depreciation_method text not null default 'straight_line',
  default_useful_life_months integer not null,
  default_residual_rate numeric(7, 4) not null default 0,
  asset_subject_id uuid,
  accumulated_depreciation_subject_id uuid,
  depreciation_expense_subject_id uuid,
  disposal_subject_id uuid,
  is_enabled boolean not null default true,
  sort integer not null default 100,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_asset_category_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_asset_category_asset_subject_fkey
    foreign key (asset_subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_asset_category_accumulated_subject_fkey
    foreign key (accumulated_depreciation_subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_asset_category_expense_subject_fkey
    foreign key (depreciation_expense_subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_asset_category_disposal_subject_fkey
    foreign key (disposal_subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_asset_category_method_check check (depreciation_method in ('straight_line')),
  constraint fms_asset_category_life_check check (default_useful_life_months between 1 and 1200),
  constraint fms_asset_category_residual_rate_check
    check (default_residual_rate >= 0 and default_residual_rate < 1),
  constraint fms_asset_category_sort_check check (sort between 0 and 9999),
  constraint fms_asset_category_code_not_blank check (btrim(category_code) <> ''),
  constraint fms_asset_category_name_not_blank check (btrim(category_name) <> ''),
  constraint fms_asset_category_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_asset_category_scope_code_key unique (account_set_id, category_code)
);

create index fms_asset_category_lookup_idx
  on public.fms_asset_category (tenant_id, account_set_id, is_enabled, sort);

create table public.fms_fixed_asset (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  category_id uuid not null,
  asset_no text not null,
  asset_name text not null,
  status text not null default 'draft',
  acquisition_date date not null,
  ready_for_use_date date not null,
  depreciation_start_date date not null,
  original_value numeric(20, 2) not null,
  residual_value numeric(20, 2) not null default 0,
  useful_life_months integer not null,
  depreciated_months integer not null default 0,
  accumulated_depreciation numeric(20, 2) not null default 0,
  impairment_amount numeric(20, 2) not null default 0,
  department_id uuid,
  employee_id uuid,
  location text,
  specification text,
  serial_no text,
  source_type text,
  source_id uuid,
  source_no text,
  disposal_date date,
  disposal_amount numeric(20, 2),
  disposal_reason text,
  remark text,
  version bigint not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_fixed_asset_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_fixed_asset_category_fkey
    foreign key (category_id, account_set_id, tenant_id)
    references public.fms_asset_category(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_fixed_asset_employee_fkey
    foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint fms_fixed_asset_status_check
    check (status in ('draft', 'active', 'suspended', 'disposed')),
  constraint fms_fixed_asset_dates_check
    check (acquisition_date <= ready_for_use_date and ready_for_use_date <= depreciation_start_date),
  constraint fms_fixed_asset_value_check check (
    original_value > 0 and residual_value >= 0 and residual_value < original_value
    and accumulated_depreciation >= 0 and impairment_amount >= 0
    and accumulated_depreciation + impairment_amount <= original_value - residual_value
  ),
  constraint fms_fixed_asset_life_check
    check (useful_life_months between 1 and 1200 and depreciated_months between 0 and useful_life_months),
  constraint fms_fixed_asset_disposal_check check (
    (status <> 'disposed' and disposal_date is null and disposal_amount is null)
    or (status = 'disposed' and disposal_date is not null and disposal_amount is not null and disposal_amount >= 0)
  ),
  constraint fms_fixed_asset_no_not_blank check (btrim(asset_no) <> ''),
  constraint fms_fixed_asset_name_not_blank check (btrim(asset_name) <> ''),
  constraint fms_fixed_asset_version_check check (version > 0),
  constraint fms_fixed_asset_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_fixed_asset_scope_no_key unique (account_set_id, asset_no)
);

create index fms_fixed_asset_lookup_idx
  on public.fms_fixed_asset (tenant_id, account_set_id, status, category_id, depreciation_start_date);
create index fms_fixed_asset_employee_idx
  on public.fms_fixed_asset (tenant_id, employee_id) where employee_id is not null;

create table public.fms_asset_depreciation_run (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  accounting_period_id uuid not null,
  run_no text not null,
  status text not null default 'draft',
  asset_count integer not null default 0,
  total_amount numeric(20, 2) not null default 0,
  voucher_id uuid,
  calculated_at timestamptz,
  posted_at timestamptz,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_asset_depreciation_run_period_fkey
    foreign key (accounting_period_id, account_set_id, tenant_id)
    references public.fms_accounting_period(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_asset_depreciation_run_voucher_fkey
    foreign key (voucher_id, account_set_id, tenant_id)
    references public.fms_voucher(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_asset_depreciation_run_status_check
    check (status in ('draft', 'calculated', 'posted', 'cancelled')),
  constraint fms_asset_depreciation_run_totals_check check (asset_count >= 0 and total_amount >= 0),
  constraint fms_asset_depreciation_run_no_not_blank check (btrim(run_no) <> ''),
  constraint fms_asset_depreciation_run_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_asset_depreciation_run_period_key unique (accounting_period_id),
  constraint fms_asset_depreciation_run_scope_no_key unique (account_set_id, run_no)
);

create table public.fms_asset_depreciation_line (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  run_id uuid not null,
  asset_id uuid not null,
  opening_accumulated_depreciation numeric(20, 2) not null,
  depreciation_amount numeric(20, 2) not null,
  closing_accumulated_depreciation numeric(20, 2) not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_asset_depreciation_line_run_fkey
    foreign key (run_id, account_set_id, tenant_id)
    references public.fms_asset_depreciation_run(id, account_set_id, tenant_id) on delete cascade,
  constraint fms_asset_depreciation_line_asset_fkey
    foreign key (asset_id, account_set_id, tenant_id)
    references public.fms_fixed_asset(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_asset_depreciation_line_amount_check check (
    opening_accumulated_depreciation >= 0 and depreciation_amount >= 0
    and closing_accumulated_depreciation = opening_accumulated_depreciation + depreciation_amount
  ),
  constraint fms_asset_depreciation_line_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_asset_depreciation_line_run_asset_key unique (run_id, asset_id)
);

create index fms_asset_depreciation_line_run_idx
  on public.fms_asset_depreciation_line (tenant_id, account_set_id, run_id);

create table public.fms_payroll_run (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  accounting_period_id uuid not null,
  run_no text not null,
  payroll_month date not null,
  status text not null default 'draft',
  employee_count integer not null default 0,
  gross_amount numeric(20, 2) not null default 0,
  deduction_amount numeric(20, 2) not null default 0,
  employer_cost_amount numeric(20, 2) not null default 0,
  net_amount numeric(20, 2) not null default 0,
  salary_expense_subject_id uuid,
  salary_payable_subject_id uuid,
  tax_payable_subject_id uuid,
  social_security_payable_subject_id uuid,
  voucher_id uuid,
  calculated_at timestamptz,
  approved_at timestamptz,
  approved_by text,
  paid_at timestamptz,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_payroll_run_period_fkey
    foreign key (accounting_period_id, account_set_id, tenant_id)
    references public.fms_accounting_period(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_payroll_run_salary_expense_fkey
    foreign key (salary_expense_subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_payroll_run_salary_payable_fkey
    foreign key (salary_payable_subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_payroll_run_tax_payable_fkey
    foreign key (tax_payable_subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_payroll_run_social_payable_fkey
    foreign key (social_security_payable_subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_payroll_run_voucher_fkey
    foreign key (voucher_id, account_set_id, tenant_id)
    references public.fms_voucher(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_payroll_run_status_check
    check (status in ('draft', 'calculated', 'approved', 'paid', 'cancelled')),
  constraint fms_payroll_run_month_check check (payroll_month = date_trunc('month', payroll_month)::date),
  constraint fms_payroll_run_totals_check check (
    employee_count >= 0 and gross_amount >= 0 and deduction_amount >= 0
    and employer_cost_amount >= 0 and net_amount >= 0
    and net_amount <= gross_amount
  ),
  constraint fms_payroll_run_no_not_blank check (btrim(run_no) <> ''),
  constraint fms_payroll_run_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_payroll_run_period_key unique (accounting_period_id),
  constraint fms_payroll_run_scope_no_key unique (account_set_id, run_no)
);

create table public.fms_payroll_line (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  run_id uuid not null,
  employee_id uuid not null,
  employee_no_snapshot text not null,
  employee_name_snapshot text not null,
  department_name_snapshot text,
  earning_items jsonb not null default '{}'::jsonb,
  deduction_items jsonb not null default '{}'::jsonb,
  employer_cost_items jsonb not null default '{}'::jsonb,
  gross_amount numeric(20, 2) not null,
  deduction_amount numeric(20, 2) not null,
  employer_cost_amount numeric(20, 2) not null,
  net_amount numeric(20, 2) not null,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_payroll_line_run_fkey
    foreign key (run_id, account_set_id, tenant_id)
    references public.fms_payroll_run(id, account_set_id, tenant_id) on delete cascade,
  constraint fms_payroll_line_employee_fkey
    foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint fms_payroll_line_amount_check check (
    gross_amount >= 0 and deduction_amount >= 0 and employer_cost_amount >= 0
    and net_amount >= 0 and net_amount = gross_amount - deduction_amount
  ),
  constraint fms_payroll_line_employee_snapshot_check
    check (btrim(employee_no_snapshot) <> '' and btrim(employee_name_snapshot) <> ''),
  constraint fms_payroll_line_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_payroll_line_run_employee_key unique (run_id, employee_id)
);

create index fms_payroll_line_run_idx
  on public.fms_payroll_line (tenant_id, account_set_id, run_id);

create table public.fms_tax_period (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  accounting_period_id uuid not null,
  tax_type text not null,
  status text not null default 'draft',
  output_tax_amount numeric(20, 2) not null default 0,
  input_tax_amount numeric(20, 2) not null default 0,
  transferable_input_amount numeric(20, 2) not null default 0,
  adjustment_amount numeric(20, 2) not null default 0,
  payable_amount numeric(20, 2) not null default 0,
  filing_reference text,
  filed_at timestamptz,
  filed_by text,
  paid_at timestamptz,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_tax_period_period_fkey
    foreign key (accounting_period_id, account_set_id, tenant_id)
    references public.fms_accounting_period(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_tax_period_type_check
    check (tax_type in ('vat', 'surcharge', 'corporate_income_tax', 'stamp_duty', 'other')),
  constraint fms_tax_period_status_check
    check (status in ('draft', 'calculated', 'reviewed', 'filed', 'paid', 'cancelled')),
  constraint fms_tax_period_amount_check check (
    output_tax_amount >= 0 and input_tax_amount >= 0 and transferable_input_amount >= 0
    and payable_amount >= 0
  ),
  constraint fms_tax_period_filing_check check (
    status not in ('filed', 'paid')
    or (nullif(btrim(filing_reference), '') is not null and filed_at is not null)
  ),
  constraint fms_tax_period_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_tax_period_scope_key unique (accounting_period_id, tax_type)
);

create index fms_tax_period_lookup_idx
  on public.fms_tax_period (tenant_id, account_set_id, status, tax_type);

create table public.fms_tax_ledger_line (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  tax_period_id uuid not null,
  source_type text not null,
  source_id uuid,
  source_no text,
  occurred_on date not null,
  direction text not null,
  taxable_amount numeric(20, 2) not null default 0,
  tax_rate numeric(9, 6),
  tax_amount numeric(20, 2) not null,
  is_deductible boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_tax_ledger_line_period_fkey
    foreign key (tax_period_id, account_set_id, tenant_id)
    references public.fms_tax_period(id, account_set_id, tenant_id) on delete cascade,
  constraint fms_tax_ledger_line_direction_check check (direction in ('output', 'input', 'adjustment')),
  constraint fms_tax_ledger_line_amount_check check (
    taxable_amount >= 0 and tax_amount >= 0 and (tax_rate is null or tax_rate >= 0)
  ),
  constraint fms_tax_ledger_line_source_not_blank check (btrim(source_type) <> ''),
  constraint fms_tax_ledger_line_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_tax_ledger_line_source_key unique (tax_period_id, source_type, source_id)
);

create index fms_tax_ledger_line_period_idx
  on public.fms_tax_ledger_line (tenant_id, account_set_id, tax_period_id, occurred_on);

create table public.fms_period_close_run (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  accounting_period_id uuid not null,
  run_no text not null,
  status text not null default 'checking',
  passed_count integer not null default 0,
  warning_count integer not null default 0,
  blocking_count integer not null default 0,
  profit_loss_voucher_id uuid,
  year_end_voucher_id uuid,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  completed_by text,
  cancelled_at timestamptz,
  cancelled_by text,
  cancel_reason text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_period_close_run_period_fkey
    foreign key (accounting_period_id, account_set_id, tenant_id)
    references public.fms_accounting_period(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_period_close_run_profit_voucher_fkey
    foreign key (profit_loss_voucher_id, account_set_id, tenant_id)
    references public.fms_voucher(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_period_close_run_year_end_voucher_fkey
    foreign key (year_end_voucher_id, account_set_id, tenant_id)
    references public.fms_voucher(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_period_close_run_status_check
    check (status in ('checking', 'ready', 'closed', 'cancelled')),
  constraint fms_period_close_run_counts_check
    check (passed_count >= 0 and warning_count >= 0 and blocking_count >= 0),
  constraint fms_period_close_run_no_not_blank check (btrim(run_no) <> ''),
  constraint fms_period_close_run_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_period_close_run_period_key unique (accounting_period_id),
  constraint fms_period_close_run_scope_no_key unique (account_set_id, run_no)
);

create table public.fms_period_close_check (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  close_run_id uuid not null,
  check_code text not null,
  check_name text not null,
  status text not null,
  is_blocking boolean not null default true,
  issue_count integer not null default 0,
  summary text not null,
  detail jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now(),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_period_close_check_run_fkey
    foreign key (close_run_id, account_set_id, tenant_id)
    references public.fms_period_close_run(id, account_set_id, tenant_id) on delete cascade,
  constraint fms_period_close_check_code_check check (
    check_code in (
      'opening_balance', 'voucher_posting', 'voucher_sequence', 'trial_balance',
      'treasury_reconciliation', 'asset_depreciation', 'payroll_accrual',
      'tax_review', 'profit_loss_carryforward'
    )
  ),
  constraint fms_period_close_check_status_check check (status in ('passed', 'warning', 'blocked')),
  constraint fms_period_close_check_issue_count_check check (issue_count >= 0),
  constraint fms_period_close_check_name_not_blank check (btrim(check_name) <> ''),
  constraint fms_period_close_check_summary_not_blank check (btrim(summary) <> ''),
  constraint fms_period_close_check_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_period_close_check_run_code_key unique (close_run_id, check_code)
);

create index fms_period_close_check_run_idx
  on public.fms_period_close_check (tenant_id, account_set_id, close_run_id, status);

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fms_commercial_bill', 'fms_commercial_bill_event',
    'fms_asset_category', 'fms_fixed_asset',
    'fms_asset_depreciation_run', 'fms_asset_depreciation_line',
    'fms_payroll_run', 'fms_payroll_line',
    'fms_tax_period', 'fms_tax_ledger_line',
    'fms_period_close_run', 'fms_period_close_check'
  ] loop
    execute format(
      'create trigger %I before insert on public.%I for each row execute function public.trg_set_create_time_and_by(''true'', ''true'')',
      v_table || '_create_audit', v_table
    );
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.trg_set_update_time_and_by()',
      v_table || '_update_audit', v_table
    );
    execute format('alter table public.%I enable row level security', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))',
      v_table || '_tenant_select', v_table
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select app_private.is_platform_super()))',
      v_table || '_platform_insert', v_table
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select app_private.is_platform_super())) with check ((select app_private.is_platform_super()))',
      v_table || '_platform_update', v_table
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((select app_private.is_platform_super()))',
      v_table || '_platform_delete', v_table
    );
    execute format('grant select, insert, update, delete on public.%I to authenticated', v_table);
    execute format('grant all on public.%I to service_role', v_table);
  end loop;
end;
$$;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_types as (
  select * from (values
    ('b2000000-0000-4000-8000-000000000030'::uuid, '票据方向', 'fmsBillDirection', 230, '应收票据与应付票据方向'),
    ('b2000000-0000-4000-8000-000000000031'::uuid, '票据类型', 'fmsBillType', 231, '商业汇票介质和承兑类型'),
    ('b2000000-0000-4000-8000-000000000032'::uuid, '票据状态', 'fmsBillStatus', 232, '商业汇票生命周期状态'),
    ('b2000000-0000-4000-8000-000000000033'::uuid, '票据事件', 'fmsBillEventType', 233, '商业汇票流转事件'),
    ('b2000000-0000-4000-8000-000000000034'::uuid, '固定资产状态', 'fmsAssetStatus', 234, '固定资产卡片生命周期状态'),
    ('b2000000-0000-4000-8000-000000000035'::uuid, '折旧方法', 'fmsDepreciationMethod', 235, '固定资产折旧计算方法'),
    ('b2000000-0000-4000-8000-000000000036'::uuid, '折旧批次状态', 'fmsDepreciationRunStatus', 236, '月度折旧批次生命周期'),
    ('b2000000-0000-4000-8000-000000000037'::uuid, '薪资批次状态', 'fmsPayrollRunStatus', 237, '薪资计提和支付生命周期'),
    ('b2000000-0000-4000-8000-000000000038'::uuid, '税种', 'fmsTaxType', 238, '税务台账支持的税种'),
    ('b2000000-0000-4000-8000-000000000039'::uuid, '税务期间状态', 'fmsTaxPeriodStatus', 239, '税务测算、复核、申报和缴纳状态'),
    ('b2000000-0000-4000-8000-000000000040'::uuid, '税务台账方向', 'fmsTaxLedgerDirection', 240, '销项、进项和调整方向'),
    ('b2000000-0000-4000-8000-000000000041'::uuid, '关账批次状态', 'fmsPeriodCloseRunStatus', 241, '月末关账批次生命周期'),
    ('b2000000-0000-4000-8000-000000000042'::uuid, '关账检查项', 'fmsPeriodCloseCheckCode', 242, '月末关账标准检查清单'),
    ('b2000000-0000-4000-8000-000000000043'::uuid, '关账检查状态', 'fmsPeriodCloseCheckStatus', 243, '关账检查通过、警告和阻断状态')
  ) as t(id, name, code, sort, remark)
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
)
select t.id, t.name, t.code, '1', '624944977@qq.com', '624944977@qq.com',
  p.id, 'dictionary', t.sort, t.remark
from platform_tenant p cross join dictionary_types t
on conflict (id) do update set
  name = excluded.name, code = excluded.code, status = excluded.status,
  sort = excluded.sort, remark = excluded.remark,
  update_by = excluded.update_by, update_time = now();

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000301'::uuid,'b2000000-0000-4000-8000-000000000030'::uuid,'receivable','应收票据',1,'success'),
    ('c2000000-0000-4000-8000-000000000302'::uuid,'b2000000-0000-4000-8000-000000000030'::uuid,'payable','应付票据',2,'warning'),
    ('c2000000-0000-4000-8000-000000000311'::uuid,'b2000000-0000-4000-8000-000000000031'::uuid,'bank_acceptance','银行承兑汇票',1,'primary'),
    ('c2000000-0000-4000-8000-000000000312'::uuid,'b2000000-0000-4000-8000-000000000031'::uuid,'commercial_acceptance','商业承兑汇票',2,'warning'),
    ('c2000000-0000-4000-8000-000000000313'::uuid,'b2000000-0000-4000-8000-000000000031'::uuid,'digital','数字化票据',3,'success'),
    ('c2000000-0000-4000-8000-000000000321'::uuid,'b2000000-0000-4000-8000-000000000032'::uuid,'draft','草稿',1,'info'),
    ('c2000000-0000-4000-8000-000000000322'::uuid,'b2000000-0000-4000-8000-000000000032'::uuid,'held','持有中',2,'primary'),
    ('c2000000-0000-4000-8000-000000000323'::uuid,'b2000000-0000-4000-8000-000000000032'::uuid,'endorsed','已背书',3,'warning'),
    ('c2000000-0000-4000-8000-000000000324'::uuid,'b2000000-0000-4000-8000-000000000032'::uuid,'discounted','已贴现',4,'success'),
    ('c2000000-0000-4000-8000-000000000325'::uuid,'b2000000-0000-4000-8000-000000000032'::uuid,'settled','已结清',5,'success'),
    ('c2000000-0000-4000-8000-000000000326'::uuid,'b2000000-0000-4000-8000-000000000032'::uuid,'cancelled','已取消',6,'info'),
    ('c2000000-0000-4000-8000-000000000331'::uuid,'b2000000-0000-4000-8000-000000000033'::uuid,'received','收票',1,'success'),
    ('c2000000-0000-4000-8000-000000000332'::uuid,'b2000000-0000-4000-8000-000000000033'::uuid,'issued','出票',2,'primary'),
    ('c2000000-0000-4000-8000-000000000333'::uuid,'b2000000-0000-4000-8000-000000000033'::uuid,'endorsed','背书转让',3,'warning'),
    ('c2000000-0000-4000-8000-000000000334'::uuid,'b2000000-0000-4000-8000-000000000033'::uuid,'discounted','贴现',4,'success'),
    ('c2000000-0000-4000-8000-000000000335'::uuid,'b2000000-0000-4000-8000-000000000033'::uuid,'settled','到期结算',5,'success'),
    ('c2000000-0000-4000-8000-000000000336'::uuid,'b2000000-0000-4000-8000-000000000033'::uuid,'cancelled','取消',6,'info'),
    ('c2000000-0000-4000-8000-000000000341'::uuid,'b2000000-0000-4000-8000-000000000034'::uuid,'draft','草稿',1,'info'),
    ('c2000000-0000-4000-8000-000000000342'::uuid,'b2000000-0000-4000-8000-000000000034'::uuid,'active','使用中',2,'success'),
    ('c2000000-0000-4000-8000-000000000343'::uuid,'b2000000-0000-4000-8000-000000000034'::uuid,'suspended','暂停折旧',3,'warning'),
    ('c2000000-0000-4000-8000-000000000344'::uuid,'b2000000-0000-4000-8000-000000000034'::uuid,'disposed','已处置',4,'info'),
    ('c2000000-0000-4000-8000-000000000351'::uuid,'b2000000-0000-4000-8000-000000000035'::uuid,'straight_line','年限平均法',1,'primary'),
    ('c2000000-0000-4000-8000-000000000361'::uuid,'b2000000-0000-4000-8000-000000000036'::uuid,'draft','草稿',1,'info'),
    ('c2000000-0000-4000-8000-000000000362'::uuid,'b2000000-0000-4000-8000-000000000036'::uuid,'calculated','已计提',2,'primary'),
    ('c2000000-0000-4000-8000-000000000363'::uuid,'b2000000-0000-4000-8000-000000000036'::uuid,'posted','已入账',3,'success'),
    ('c2000000-0000-4000-8000-000000000364'::uuid,'b2000000-0000-4000-8000-000000000036'::uuid,'cancelled','已取消',4,'info'),
    ('c2000000-0000-4000-8000-000000000371'::uuid,'b2000000-0000-4000-8000-000000000037'::uuid,'draft','草稿',1,'info'),
    ('c2000000-0000-4000-8000-000000000372'::uuid,'b2000000-0000-4000-8000-000000000037'::uuid,'calculated','已计算',2,'primary'),
    ('c2000000-0000-4000-8000-000000000373'::uuid,'b2000000-0000-4000-8000-000000000037'::uuid,'approved','已审批',3,'warning'),
    ('c2000000-0000-4000-8000-000000000374'::uuid,'b2000000-0000-4000-8000-000000000037'::uuid,'paid','已发放',4,'success'),
    ('c2000000-0000-4000-8000-000000000375'::uuid,'b2000000-0000-4000-8000-000000000037'::uuid,'cancelled','已取消',5,'info'),
    ('c2000000-0000-4000-8000-000000000381'::uuid,'b2000000-0000-4000-8000-000000000038'::uuid,'vat','增值税',1,'primary'),
    ('c2000000-0000-4000-8000-000000000382'::uuid,'b2000000-0000-4000-8000-000000000038'::uuid,'surcharge','税金及附加',2,'warning'),
    ('c2000000-0000-4000-8000-000000000383'::uuid,'b2000000-0000-4000-8000-000000000038'::uuid,'corporate_income_tax','企业所得税',3,'success'),
    ('c2000000-0000-4000-8000-000000000384'::uuid,'b2000000-0000-4000-8000-000000000038'::uuid,'stamp_duty','印花税',4,'info'),
    ('c2000000-0000-4000-8000-000000000385'::uuid,'b2000000-0000-4000-8000-000000000038'::uuid,'other','其他税费',5,'info'),
    ('c2000000-0000-4000-8000-000000000391'::uuid,'b2000000-0000-4000-8000-000000000039'::uuid,'draft','草稿',1,'info'),
    ('c2000000-0000-4000-8000-000000000392'::uuid,'b2000000-0000-4000-8000-000000000039'::uuid,'calculated','已测算',2,'primary'),
    ('c2000000-0000-4000-8000-000000000393'::uuid,'b2000000-0000-4000-8000-000000000039'::uuid,'reviewed','已复核',3,'warning'),
    ('c2000000-0000-4000-8000-000000000394'::uuid,'b2000000-0000-4000-8000-000000000039'::uuid,'filed','已申报',4,'success'),
    ('c2000000-0000-4000-8000-000000000395'::uuid,'b2000000-0000-4000-8000-000000000039'::uuid,'paid','已缴纳',5,'success'),
    ('c2000000-0000-4000-8000-000000000396'::uuid,'b2000000-0000-4000-8000-000000000039'::uuid,'cancelled','已取消',6,'info'),
    ('c2000000-0000-4000-8000-000000000401'::uuid,'b2000000-0000-4000-8000-000000000040'::uuid,'output','销项',1,'warning'),
    ('c2000000-0000-4000-8000-000000000402'::uuid,'b2000000-0000-4000-8000-000000000040'::uuid,'input','进项',2,'success'),
    ('c2000000-0000-4000-8000-000000000403'::uuid,'b2000000-0000-4000-8000-000000000040'::uuid,'adjustment','调整',3,'primary'),
    ('c2000000-0000-4000-8000-000000000411'::uuid,'b2000000-0000-4000-8000-000000000041'::uuid,'checking','检查中',1,'primary'),
    ('c2000000-0000-4000-8000-000000000412'::uuid,'b2000000-0000-4000-8000-000000000041'::uuid,'ready','可结账',2,'success'),
    ('c2000000-0000-4000-8000-000000000413'::uuid,'b2000000-0000-4000-8000-000000000041'::uuid,'closed','已结账',3,'info'),
    ('c2000000-0000-4000-8000-000000000414'::uuid,'b2000000-0000-4000-8000-000000000041'::uuid,'cancelled','已取消',4,'info'),
    ('c2000000-0000-4000-8000-000000000421'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'opening_balance','期初平衡',1,'primary'),
    ('c2000000-0000-4000-8000-000000000422'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'voucher_posting','凭证过账',2,'primary'),
    ('c2000000-0000-4000-8000-000000000423'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'voucher_sequence','凭证断号',3,'info'),
    ('c2000000-0000-4000-8000-000000000424'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'trial_balance','试算平衡',4,'primary'),
    ('c2000000-0000-4000-8000-000000000425'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'treasury_reconciliation','资金对账',5,'success'),
    ('c2000000-0000-4000-8000-000000000426'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'asset_depreciation','资产折旧',6,'warning'),
    ('c2000000-0000-4000-8000-000000000427'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'payroll_accrual','薪资计提',7,'warning'),
    ('c2000000-0000-4000-8000-000000000428'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'tax_review','税务复核',8,'warning'),
    ('c2000000-0000-4000-8000-000000000429'::uuid,'b2000000-0000-4000-8000-000000000042'::uuid,'profit_loss_carryforward','损益结转',9,'danger'),
    ('c2000000-0000-4000-8000-000000000431'::uuid,'b2000000-0000-4000-8000-000000000043'::uuid,'passed','通过',1,'success'),
    ('c2000000-0000-4000-8000-000000000432'::uuid,'b2000000-0000-4000-8000-000000000043'::uuid,'warning','警告',2,'warning'),
    ('c2000000-0000-4000-8000-000000000433'::uuid,'b2000000-0000-4000-8000-000000000043'::uuid,'blocked','阻断',3,'danger')
  ) as i(id, type_id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select i.id, i.type_id, i.value, '1', i.value, i.label, i.sort, i.tag_type,
  '624944977@qq.com', '624944977@qq.com', p.id
from platform_tenant p cross join dictionary_items i
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, status = excluded.status,
  value = excluded.value, label = excluded.label, sort = excluded.sort,
  tag_type = excluded.tag_type, update_by = excluded.update_by, update_time = now();

commit;

;
