-- Convert FMS maintenance from platform-super-only access to tenant-scoped RBAC.
-- Platform super remains an implicit override through app_private.has_permission().

create or replace function app_private.has_fms_operation_permission(
  p_rpc_name text,
  p_action text default null,
  p_is_new boolean default null
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_permission text;
begin
  case p_rpc_name
    when 'act_fms_asset_depreciation_run' then
      v_permission := 'FinanceFixedAsset:Depreciation';
    when 'act_fms_commercial_bill' then
      v_permission := case lower(p_action)
        when 'receive' then 'FinanceCommercialBill:Receive'
        when 'issue' then 'FinanceCommercialBill:Issue'
        when 'endorse' then 'FinanceCommercialBill:Endorse'
        when 'discount' then 'FinanceCommercialBill:Discount'
        when 'settle' then 'FinanceCommercialBill:Settle'
        when 'cancel' then 'FinanceCommercialBill:Cancel'
      end;
    when 'act_fms_fixed_asset' then
      v_permission := case lower(p_action)
        when 'activate' then 'FinanceFixedAsset:Activate'
        when 'suspend' then 'FinanceFixedAsset:Suspend'
        when 'resume' then 'FinanceFixedAsset:Resume'
        when 'dispose' then 'FinanceFixedAsset:Dispose'
      end;
    when 'act_fms_payroll_run' then
      v_permission := case lower(p_action)
        when 'approve' then 'FinancePayroll:Approve'
        when 'pay' then 'FinancePayroll:Pay'
        when 'cancel' then 'FinancePayroll:Cancel'
      end;
    when 'act_fms_period_close_run' then
      v_permission := case lower(p_action)
        when 'close' then 'FinancePeriodClose:Close'
        when 'cancel' then 'FinancePeriodClose:Cancel'
        when 'reopen' then 'FinancePeriodClose:Reopen'
      end;
    when 'act_fms_tax_period' then
      v_permission := case lower(p_action)
        when 'review' then 'FinanceTaxManagement:Review'
        when 'file' then 'FinanceTaxManagement:File'
        when 'pay' then 'FinanceTaxManagement:Pay'
        when 'cancel' then 'FinanceTaxManagement:Cancel'
      end;
    when 'auto_match_fms_bank_reconciliation' then
      v_permission := 'FinanceBankReconciliation:AutoMatch';
    when 'calculate_fms_asset_depreciation' then
      v_permission := 'FinanceFixedAsset:Depreciation';
    when 'delete_fms_asset_category' then
      v_permission := 'FinanceFixedAsset:ManageCategory';
    when 'delete_fms_auxiliary_type' then
      v_permission := 'FinanceAccountingAuxiliary:DeleteType';
    when 'delete_fms_commercial_bill' then
      v_permission := 'FinanceCommercialBill:Delete';
    when 'delete_fms_fixed_asset' then
      v_permission := 'FinanceFixedAsset:Delete';
    when 'delete_fms_fund_account' then
      v_permission := 'FinanceFundAccount:Delete';
    when 'delete_fms_fund_transfer' then
      v_permission := 'FinanceFundTransfer:Delete';
    when 'delete_fms_payroll_line' then
      v_permission := 'FinancePayroll:Edit';
    when 'delete_fms_posting_rule' then
      v_permission := 'FinanceAutoPosting:Delete';
    when 'delete_fms_tax_ledger_line' then
      v_permission := 'FinanceTaxManagement:Edit';
    when 'delete_fms_voucher_template' then
      v_permission := 'FinanceVoucherTemplate:Delete';
    when 'generate_fms_profit_loss_carryforward' then
      v_permission := 'FinancePeriodClose:Carryforward';
    when 'ignore_fms_bank_statement_line' then
      v_permission := 'FinanceBankReconciliation:Ignore';
    when 'import_fms_bank_reconciliation' then
      v_permission := 'FinanceBankReconciliation:Add';
    when 'initialize_fms_accounting_defaults' then
      v_permission := 'FinanceAccountingSubject:Initialize';
    when 'initialize_fms_financial_statement_items_base' then
      v_permission := 'FinanceFinancialReports:EditConfig';
    when 'match_fms_bank_statement_line' then
      v_permission := 'FinanceBankReconciliation:Match';
    when 'process_pending_fms_posting_events' then
      v_permission := 'FinanceAutoPosting:ProcessPending';
    when 'retry_fms_posting_event' then
      v_permission := 'FinanceAutoPosting:Retry';
    when 'run_fms_period_close_checks' then
      return app_private.has_permission('FinancePeriodClose:Add')
        or app_private.has_permission('FinancePeriodClose:Recheck');
    when 'save_fms_account_set' then
      v_permission := case when p_is_new
        then 'FinanceAccountSet:Add' else 'FinanceAccountSet:Edit' end;
    when 'save_fms_asset_category' then
      v_permission := 'FinanceFixedAsset:ManageCategory';
    when 'save_fms_cash_flow_allocations' then
      v_permission := 'FinanceVoucherCenter:Edit';
    when 'save_fms_commercial_bill' then
      v_permission := case when p_is_new
        then 'FinanceCommercialBill:Add' else 'FinanceCommercialBill:Edit' end;
    when 'save_fms_financial_statement_formulas' then
      v_permission := 'FinanceFinancialReports:EditConfig';
    when 'save_fms_financial_statement_item' then
      v_permission := 'FinanceFinancialReports:EditConfig';
    when 'save_fms_financial_statement_mappings' then
      v_permission := 'FinanceFinancialReports:EditConfig';
    when 'save_fms_fixed_asset' then
      v_permission := case when p_is_new
        then 'FinanceFixedAsset:Add' else 'FinanceFixedAsset:Edit' end;
    when 'save_fms_fund_account' then
      v_permission := case when p_is_new
        then 'FinanceFundAccount:Add' else 'FinanceFundAccount:Edit' end;
    when 'save_fms_fund_transfer' then
      v_permission := case when p_is_new
        then 'FinanceFundTransfer:Add' else 'FinanceFundTransfer:Edit' end;
    when 'save_fms_opening_balance' then
      v_permission := case when p_is_new
        then 'FinanceOpeningBalance:Add' else 'FinanceOpeningBalance:Edit' end;
    when 'save_fms_payroll_line' then
      return app_private.has_permission('FinancePayroll:Edit')
        or app_private.has_permission('FinancePayroll:Calculate');
    when 'save_fms_payroll_run' then
      v_permission := case when p_is_new
        then 'FinancePayroll:Add' else 'FinancePayroll:Edit' end;
    when 'save_fms_posting_rule' then
      v_permission := case when p_is_new
        then 'FinanceAutoPosting:Add' else 'FinanceAutoPosting:Edit' end;
    when 'save_fms_subject' then
      v_permission := case when p_is_new
        then 'FinanceAccountingSubject:Add' else 'FinanceAccountingSubject:Edit' end;
    when 'save_fms_tax_ledger_line' then
      return app_private.has_permission('FinanceTaxManagement:Edit')
        or app_private.has_permission('FinanceTaxManagement:Calculate');
    when 'save_fms_tax_period' then
      v_permission := case when p_is_new
        then 'FinanceTaxManagement:Add' else 'FinanceTaxManagement:Edit' end;
    when 'save_fms_voucher' then
      v_permission := case when p_is_new
        then 'FinanceVoucherCenter:Add' else 'FinanceVoucherCenter:Edit' end;
    when 'save_fms_voucher_template' then
      v_permission := case when p_is_new
        then 'FinanceVoucherTemplate:Add' else 'FinanceVoucherTemplate:Edit' end;
    when 'set_fms_account_set_status' then
      v_permission := case lower(p_action)
        when 'active' then 'FinanceAccountSet:Active'
        when 'suspended' then 'FinanceAccountSet:Suspended'
        when 'archived' then 'FinanceAccountSet:Archived'
      end;
    when 'set_fms_accounting_period_status' then
      v_permission := 'FinanceAccountSet:ManagePeriod';
    when 'set_fms_opening_balance_status' then
      v_permission := case lower(p_action)
        when 'confirmed' then 'FinanceOpeningBalance:Confirm'
        when 'draft' then 'FinanceOpeningBalance:Reopen'
      end;
    when 'sync_fms_auxiliary_items' then
      v_permission := 'FinanceAccountingAuxiliary:Sync';
    when 'transition_fms_bank_reconciliation' then
      v_permission := case lower(p_action)
        when 'complete' then 'FinanceBankReconciliation:Complete'
        when 'void' then 'FinanceBankReconciliation:Void'
      end;
    when 'transition_fms_fund_transfer' then
      v_permission := case lower(p_action)
        when 'submit' then 'FinanceFundTransfer:Submit'
        when 'approve' then 'FinanceFundTransfer:Approve'
        when 'reject' then 'FinanceFundTransfer:Reject'
        when 'execute' then 'FinanceFundTransfer:Execute'
        when 'reverse' then 'FinanceFundTransfer:Reverse'
      end;
    when 'transition_fms_voucher' then
      v_permission := case lower(p_action)
        when 'submit' then 'FinanceVoucherCenter:Submit'
        when 'approve' then 'FinanceVoucherCenter:Approve'
        when 'reject' then 'FinanceVoucherCenter:Reject'
        when 'post' then 'FinanceVoucherCenter:Post'
        when 'void' then 'FinanceVoucherCenter:Void'
        when 'reverse' then 'FinanceVoucherCenter:Reverse'
      end;
    when 'unmatch_fms_bank_statement_line' then
      v_permission := 'FinanceBankReconciliation:Unmatch';
    else
      return false;
  end case;

  return v_permission is not null and app_private.has_permission(v_permission);
end;
$function$;

revoke all on function app_private.has_fms_operation_permission(text, text, boolean) from public;

-- Rewrite only the leading platform-super guard in each public FMS mutation RPC.
-- Existing validation and state-transition code remains intact.
do $migration$
declare
  mapping_record record;
  function_record record;
  function_definition text;
  patched_definition text;
begin
  for mapping_record in
    select *
    from (values
      ('act_fms_asset_depreciation_run', $expression$app_private.has_fms_operation_permission('act_fms_asset_depreciation_run', p_action, null)$expression$),
      ('act_fms_commercial_bill', $expression$app_private.has_fms_operation_permission('act_fms_commercial_bill', p_action, null)$expression$),
      ('act_fms_fixed_asset', $expression$app_private.has_fms_operation_permission('act_fms_fixed_asset', p_action, null)$expression$),
      ('act_fms_payroll_run', $expression$app_private.has_fms_operation_permission('act_fms_payroll_run', p_action, null)$expression$),
      ('act_fms_period_close_run', $expression$app_private.has_fms_operation_permission('act_fms_period_close_run', p_action, null)$expression$),
      ('act_fms_tax_period', $expression$app_private.has_fms_operation_permission('act_fms_tax_period', p_action, null)$expression$),
      ('auto_match_fms_bank_reconciliation', $expression$app_private.has_fms_operation_permission('auto_match_fms_bank_reconciliation', null, null)$expression$),
      ('calculate_fms_asset_depreciation', $expression$app_private.has_fms_operation_permission('calculate_fms_asset_depreciation', null, null)$expression$),
      ('delete_fms_asset_category', $expression$app_private.has_fms_operation_permission('delete_fms_asset_category', null, null)$expression$),
      ('delete_fms_auxiliary_type', $expression$app_private.has_fms_operation_permission('delete_fms_auxiliary_type', null, null)$expression$),
      ('delete_fms_commercial_bill', $expression$app_private.has_fms_operation_permission('delete_fms_commercial_bill', null, null)$expression$),
      ('delete_fms_fixed_asset', $expression$app_private.has_fms_operation_permission('delete_fms_fixed_asset', null, null)$expression$),
      ('delete_fms_fund_account', $expression$app_private.has_fms_operation_permission('delete_fms_fund_account', null, null)$expression$),
      ('delete_fms_fund_transfer', $expression$app_private.has_fms_operation_permission('delete_fms_fund_transfer', null, null)$expression$),
      ('delete_fms_payroll_line', $expression$app_private.has_fms_operation_permission('delete_fms_payroll_line', null, null)$expression$),
      ('delete_fms_posting_rule', $expression$app_private.has_fms_operation_permission('delete_fms_posting_rule', null, null)$expression$),
      ('delete_fms_tax_ledger_line', $expression$app_private.has_fms_operation_permission('delete_fms_tax_ledger_line', null, null)$expression$),
      ('delete_fms_voucher_template', $expression$app_private.has_fms_operation_permission('delete_fms_voucher_template', null, null)$expression$),
      ('generate_fms_profit_loss_carryforward', $expression$app_private.has_fms_operation_permission('generate_fms_profit_loss_carryforward', null, null)$expression$),
      ('ignore_fms_bank_statement_line', $expression$app_private.has_fms_operation_permission('ignore_fms_bank_statement_line', null, null)$expression$),
      ('import_fms_bank_reconciliation', $expression$app_private.has_fms_operation_permission('import_fms_bank_reconciliation', null, null)$expression$),
      ('initialize_fms_accounting_defaults', $expression$app_private.has_fms_operation_permission('initialize_fms_accounting_defaults', null, null)$expression$),
      ('initialize_fms_financial_statement_items_base', $expression$app_private.has_fms_operation_permission('initialize_fms_financial_statement_items_base', null, null)$expression$),
      ('match_fms_bank_statement_line', $expression$app_private.has_fms_operation_permission('match_fms_bank_statement_line', null, null)$expression$),
      ('process_pending_fms_posting_events', $expression$app_private.has_fms_operation_permission('process_pending_fms_posting_events', null, null)$expression$),
      ('retry_fms_posting_event', $expression$app_private.has_fms_operation_permission('retry_fms_posting_event', null, null)$expression$),
      ('run_fms_period_close_checks', $expression$app_private.has_fms_operation_permission('run_fms_period_close_checks', null, null)$expression$),
      ('save_fms_account_set', $expression$app_private.has_fms_operation_permission('save_fms_account_set', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_asset_category', $expression$app_private.has_fms_operation_permission('save_fms_asset_category', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_cash_flow_allocations', $expression$app_private.has_fms_operation_permission('save_fms_cash_flow_allocations', null, null)$expression$),
      ('save_fms_commercial_bill', $expression$app_private.has_fms_operation_permission('save_fms_commercial_bill', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_financial_statement_formulas', $expression$app_private.has_fms_operation_permission('save_fms_financial_statement_formulas', null, null)$expression$),
      ('save_fms_financial_statement_item', $expression$app_private.has_fms_operation_permission('save_fms_financial_statement_item', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_financial_statement_mappings', $expression$app_private.has_fms_operation_permission('save_fms_financial_statement_mappings', null, null)$expression$),
      ('save_fms_fixed_asset', $expression$app_private.has_fms_operation_permission('save_fms_fixed_asset', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_fund_account', $expression$app_private.has_fms_operation_permission('save_fms_fund_account', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_fund_transfer', $expression$app_private.has_fms_operation_permission('save_fms_fund_transfer', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_opening_balance', $expression$app_private.has_fms_operation_permission('save_fms_opening_balance', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_payroll_line', $expression$app_private.has_fms_operation_permission('save_fms_payroll_line', null, null)$expression$),
      ('save_fms_payroll_run', $expression$app_private.has_fms_operation_permission('save_fms_payroll_run', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_posting_rule', $expression$app_private.has_fms_operation_permission('save_fms_posting_rule', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_subject', $expression$app_private.has_fms_operation_permission('save_fms_subject', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_tax_ledger_line', $expression$app_private.has_fms_operation_permission('save_fms_tax_ledger_line', null, null)$expression$),
      ('save_fms_tax_period', $expression$app_private.has_fms_operation_permission('save_fms_tax_period', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_voucher', $expression$app_private.has_fms_operation_permission('save_fms_voucher', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('save_fms_voucher_template', $expression$app_private.has_fms_operation_permission('save_fms_voucher_template', null, nullif(p_payload ->> 'id', '') is null)$expression$),
      ('set_fms_account_set_status', $expression$app_private.has_fms_operation_permission('set_fms_account_set_status', p_status, null)$expression$),
      ('set_fms_accounting_period_status', $expression$app_private.has_fms_operation_permission('set_fms_accounting_period_status', p_status, null)$expression$),
      ('set_fms_opening_balance_status', $expression$app_private.has_fms_operation_permission('set_fms_opening_balance_status', p_status, null)$expression$),
      ('sync_fms_auxiliary_items', $expression$app_private.has_fms_operation_permission('sync_fms_auxiliary_items', null, null)$expression$),
      ('transition_fms_bank_reconciliation', $expression$app_private.has_fms_operation_permission('transition_fms_bank_reconciliation', p_action, null)$expression$),
      ('transition_fms_fund_transfer', $expression$app_private.has_fms_operation_permission('transition_fms_fund_transfer', p_action, null)$expression$),
      ('transition_fms_voucher', $expression$app_private.has_fms_operation_permission('transition_fms_voucher', p_action, null)$expression$),
      ('unmatch_fms_bank_statement_line', $expression$app_private.has_fms_operation_permission('unmatch_fms_bank_statement_line', null, null)$expression$)
    ) as mapping(rpc_name, permission_expression)
  loop
    select p.oid, p.oid::regprocedure as signature, pg_get_functiondef(p.oid) as definition
      into function_record
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = mapping_record.rpc_name;

    if function_record.oid is null then
      raise exception 'FMS permission migration function not found: %', mapping_record.rpc_name;
    end if;

    function_definition := function_record.definition;
    patched_definition := replace(
      function_definition,
      'app_private.is_platform_super()',
      mapping_record.permission_expression
    );
    patched_definition := regexp_replace(
      patched_definition,
      '''仅平台超级管理员可[^'']*''',
      '''当前角色缺少对应业务按钮权限''',
      'g'
    );

    if patched_definition = function_definition then
      raise exception 'FMS platform-super guard not found: %', mapping_record.rpc_name;
    end if;

    if mapping_record.rpc_name = 'process_pending_fms_posting_events' then
      patched_definition := replace(
        patched_definition,
        $source$where status in ('pending', 'pending_configuration', 'failed')
    order by event_date, create_time$source$,
        $source$where status in ('pending', 'pending_configuration', 'failed')
      and (
        app_private.is_platform_super()
        or tenant_id = app_private.current_user_tenant_id()
      )
    order by event_date, create_time$source$
      );
    end if;

    execute patched_definition;
    execute format('alter function %s security definer', function_record.signature);
    execute format(
      'alter function %s set search_path = public, app_private, pg_temp',
      function_record.signature
    );
  end loop;
end;
$migration$;

-- SECURITY DEFINER RPCs must still fail closed on cross-tenant writes.
create or replace function app_private.guard_fms_tenant_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_tenant_id uuid;
  v_old_tenant_id uuid;
  v_new_tenant_id uuid;
begin
  if auth.uid() is null or app_private.is_platform_super() then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_current_tenant_id := app_private.current_user_tenant_id();
  if v_current_tenant_id is null then
    raise exception using errcode = '42501', message = '当前用户缺少有效租户上下文';
  end if;

  if tg_op <> 'INSERT' then
    v_old_tenant_id := nullif(to_jsonb(old) ->> 'tenant_id', '')::uuid;
    if v_old_tenant_id is distinct from v_current_tenant_id then
      raise exception using errcode = '42501', message = '禁止修改其他租户的财务数据';
    end if;
  end if;

  if tg_op <> 'DELETE' then
    v_new_tenant_id := nullif(to_jsonb(new) ->> 'tenant_id', '')::uuid;
    if v_new_tenant_id is distinct from v_current_tenant_id then
      raise exception using errcode = '42501', message = '禁止向其他租户写入财务数据';
    end if;
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

revoke all on function app_private.guard_fms_tenant_write() from public;

do $migration$
declare
  table_record record;
  trigger_name text;
begin
  for table_record in
    select c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and c.relname like 'fms\_%' escape '\'
      and exists (
        select 1
        from pg_attribute a
        where a.attrelid = c.oid
          and a.attname = 'tenant_id'
          and a.attnum > 0
          and not a.attisdropped
      )
  loop
    trigger_name := left(table_record.table_name || '_tenant_write_guard', 63);
    execute format('drop trigger if exists %I on public.%I', trigger_name, table_record.table_name);
    execute format(
      'create trigger %I before insert or update or delete on public.%I '
      || 'for each row execute function app_private.guard_fms_tenant_write()',
      trigger_name,
      table_record.table_name
    );
  end loop;
end;
$migration$;

-- Direct base-data writes used by Supabase providers keep operation-specific RBAC.
drop policy if exists fms_subject_business_insert on public.fms_subject;
create policy fms_subject_business_insert on public.fms_subject
for insert to authenticated
with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingSubject:Add')
);

drop policy if exists fms_subject_business_update on public.fms_subject;
create policy fms_subject_business_update on public.fms_subject
for update to authenticated
using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('FinanceAccountingSubject:Edit')
    or app_private.has_permission('FinanceAccountingSubject:Toggle')
  )
)
with check (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('FinanceAccountingSubject:Edit')
    or app_private.has_permission('FinanceAccountingSubject:Toggle')
  )
);

drop policy if exists fms_auxiliary_type_business_insert on public.fms_auxiliary_type;
create policy fms_auxiliary_type_business_insert on public.fms_auxiliary_type
for insert to authenticated
with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingAuxiliary:AddType')
);

drop policy if exists fms_auxiliary_type_business_update on public.fms_auxiliary_type;
create policy fms_auxiliary_type_business_update on public.fms_auxiliary_type
for update to authenticated
using (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingAuxiliary:EditType')
)
with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingAuxiliary:EditType')
);

drop policy if exists fms_auxiliary_type_business_delete on public.fms_auxiliary_type;
create policy fms_auxiliary_type_business_delete on public.fms_auxiliary_type
for delete to authenticated
using (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingAuxiliary:DeleteType')
);

drop policy if exists fms_auxiliary_item_business_insert on public.fms_auxiliary_item;
create policy fms_auxiliary_item_business_insert on public.fms_auxiliary_item
for insert to authenticated
with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingAuxiliary:Add')
);

drop policy if exists fms_auxiliary_item_business_update on public.fms_auxiliary_item;
create policy fms_auxiliary_item_business_update on public.fms_auxiliary_item
for update to authenticated
using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('FinanceAccountingAuxiliary:Edit')
    or app_private.has_permission('FinanceAccountingAuxiliary:Toggle')
  )
)
with check (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('FinanceAccountingAuxiliary:Edit')
    or app_private.has_permission('FinanceAccountingAuxiliary:Toggle')
  )
);

drop policy if exists fms_currency_business_insert on public.fms_currency;
create policy fms_currency_business_insert on public.fms_currency
for insert to authenticated
with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingCurrency:AddCurrency')
);

drop policy if exists fms_currency_business_update on public.fms_currency;
create policy fms_currency_business_update on public.fms_currency
for update to authenticated
using (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('FinanceAccountingCurrency:EditCurrency')
    or app_private.has_permission('FinanceAccountingCurrency:Toggle')
  )
)
with check (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('FinanceAccountingCurrency:EditCurrency')
    or app_private.has_permission('FinanceAccountingCurrency:Toggle')
  )
);

drop policy if exists fms_exchange_rate_business_insert on public.fms_exchange_rate;
create policy fms_exchange_rate_business_insert on public.fms_exchange_rate
for insert to authenticated
with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingCurrency:Add')
);

drop policy if exists fms_exchange_rate_business_update on public.fms_exchange_rate;
create policy fms_exchange_rate_business_update on public.fms_exchange_rate
for update to authenticated
using (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingCurrency:Edit')
)
with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceAccountingCurrency:Edit')
);

drop policy if exists fms_opening_balance_business_delete on public.fms_opening_balance;
create policy fms_opening_balance_business_delete on public.fms_opening_balance
for delete to authenticated
using (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('FinanceOpeningBalance:Delete')
);

-- Address geofence maintenance is a normal TMS business permission, not a super-only setting.
create or replace function app_private.guard_tms_address_geofence_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_geofence_changed boolean;
begin
  v_geofence_changed := case
    when tg_op = 'INSERT' then
      coalesce(new.geofence_enabled, false)
      or new.geofence_radius_m is not null
      or new.geofence_updated_at is not null
    else
      new.geofence_enabled is distinct from old.geofence_enabled
      or new.geofence_radius_m is distinct from old.geofence_radius_m
      or new.geofence_updated_at is distinct from old.geofence_updated_at
  end;

  if v_geofence_changed
     and not app_private.has_permission('TmsCustomerAddress:Geofence') then
    raise exception using errcode = '42501', message = '当前角色未获维护地址围栏权限';
  end if;

  if auth.uid() is not null
     and not app_private.is_platform_super()
     and new.tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception using errcode = '42501', message = '禁止维护其他租户的地址围栏';
  end if;

  return new;
end;
$function$;

revoke all on function app_private.guard_tms_address_geofence_write() from public;

;
