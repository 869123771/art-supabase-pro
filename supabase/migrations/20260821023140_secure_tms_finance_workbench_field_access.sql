-- Finance workbench aggregates are cross-record metrics and therefore do not use
-- record-owner overrides. Access is resolved from role/user field grants on the
-- workbench resource itself, while every aggregate remains explicitly tenant-scoped.

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_finance_workbench;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_finance_workbench(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.finance_workbench', '财务工作台',
    'FinanceWorkbench', null,
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'customerSettlementAmounts', '客户应收与回款指标',
      'hidden', 'amount', false, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'carrierSettlementAmounts', '承运商应付与付款指标',
      'hidden', 'amount', false, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'cashFlowAmounts', '收付款资金指标',
      'hidden', 'amount', false, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'invoiceAmounts', '发票金额与匹配指标',
      'hidden', 'amount', false, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'paymentApplicationAmounts', '付款申请金额指标',
      'hidden', 'amount', false, 50, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'operatingAmounts', '运输收入、成本与毛利指标',
      'hidden', 'amount', false, 60, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

-- Preserve the current workbench experience for roles that already own the menu.
-- Tenant administrators can tighten these grants from the field-permission matrix.
insert into public.sys_role_field_permission (
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id,
  role_menu.role_id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'FinanceWorkbench'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'tms.finance_workbench'
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function public.tms_get_finance_workbench_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb;
  v_data jsonb;
begin
  if not app_private.can_execute_business_action('FinanceWorkbench', null, null, false) then
    raise exception 'Missing finance workbench permission' using errcode = '42501';
  end if;

  v_access := app_private.field_access_map('tms.finance_workbench', null);

  select jsonb_build_object(
    'customer_receivable_balance', coalesce((
      select sum(summary_row.outstanding_amount)
      from public.tms_customer_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status in ('confirmed', 'partially_settled')
    ), 0)::numeric(14, 2),
    'carrier_payable_balance', coalesce((
      select sum(summary_row.outstanding_amount)
      from public.tms_carrier_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status in ('confirmed', 'partially_settled')
    ), 0)::numeric(14, 2),
    'month_receipt_amount', coalesce((
      select sum(transaction_row.amount)
      from public.tms_cash_transaction_summary transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.direction = 'receipt'
        and transaction_row.status <> 'voided'
        and date_trunc('month', transaction_row.transaction_date::timestamp) =
          date_trunc('month', current_date::timestamp)
    ), 0)::numeric(14, 2),
    'month_payment_amount', coalesce((
      select sum(transaction_row.amount)
      from public.tms_cash_transaction_summary transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.direction = 'payment'
        and transaction_row.status <> 'voided'
        and date_trunc('month', transaction_row.transaction_date::timestamp) =
          date_trunc('month', current_date::timestamp)
    ), 0)::numeric(14, 2),
    'month_revenue_amount', coalesce((
      select sum(profit_row.receivable_amount)
      from public.tms_waybill_profit profit_row
      where profit_row.tenant_id = v_tenant_id
        and date_trunc('month', coalesce(profit_row.completed_at, profit_row.create_time)) =
          date_trunc('month', current_date::timestamp)
    ), 0)::numeric(14, 2),
    'month_cost_amount', coalesce((
      select sum(profit_row.total_cost_amount)
      from public.tms_waybill_profit profit_row
      where profit_row.tenant_id = v_tenant_id
        and date_trunc('month', coalesce(profit_row.completed_at, profit_row.create_time)) =
          date_trunc('month', current_date::timestamp)
    ), 0)::numeric(14, 2),
    'month_gross_profit', coalesce((
      select sum(profit_row.gross_profit)
      from public.tms_waybill_profit profit_row
      where profit_row.tenant_id = v_tenant_id
        and date_trunc('month', coalesce(profit_row.completed_at, profit_row.create_time)) =
          date_trunc('month', current_date::timestamp)
    ), 0)::numeric(14, 2),
    'receipt_completion_rate', coalesce((
      select round(
        100::numeric * sum(summary_row.settled_amount) /
          nullif(sum(summary_row.statement_amount), 0),
        2
      )
      from public.tms_customer_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status in ('confirmed', 'partially_settled', 'settled')
    ), 0)::numeric(7, 2),
    'payment_completion_rate', coalesce((
      select round(
        100::numeric * sum(summary_row.settled_amount) /
          nullif(sum(summary_row.statement_amount), 0),
        2
      )
      from public.tms_carrier_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status in ('confirmed', 'partially_settled', 'settled')
    ), 0)::numeric(7, 2),
    'invoice_match_rate', coalesce((
      select round(
        100::numeric * sum(invoice_row.linked_amount) /
          nullif(sum(invoice_row.total_amount), 0),
        2
      )
      from public.tms_invoice_summary invoice_row
      where invoice_row.tenant_id = v_tenant_id
        and invoice_row.status <> 'voided'
    ), 0)::numeric(7, 2),
    'cost_approval_rate', coalesce((
      select round(
        100::numeric * count(*) filter (where cost_row.audit_status = 'approved') /
          nullif(count(*) filter (where cost_row.audit_status <> 'voided'), 0),
        2
      )
      from public.tms_waybill_cost cost_row
      where cost_row.tenant_id = v_tenant_id
    ), 0)::numeric(7, 2),
    'pending_customer_statement_count', (
      select count(*)::integer
      from public.tms_customer_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status = 'pending_review'
    ),
    'pending_customer_statement_amount', coalesce((
      select sum(summary_row.statement_amount)
      from public.tms_customer_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status = 'pending_review'
    ), 0)::numeric(14, 2),
    'pending_carrier_statement_count', (
      select count(*)::integer
      from public.tms_carrier_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status = 'pending_review'
    ),
    'pending_carrier_statement_amount', coalesce((
      select sum(summary_row.statement_amount)
      from public.tms_carrier_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status = 'pending_review'
    ), 0)::numeric(14, 2),
    'pending_cost_count', (
      select count(*)::integer
      from public.tms_waybill_cost cost_row
      where cost_row.tenant_id = v_tenant_id
        and cost_row.audit_status = 'pending_review'
    ),
    'pending_cost_amount', coalesce((
      select sum(cost_row.amount)
      from public.tms_waybill_cost cost_row
      where cost_row.tenant_id = v_tenant_id
        and cost_row.audit_status = 'pending_review'
    ), 0)::numeric(14, 2),
    'unallocated_receipt_count', (
      select count(*)::integer
      from public.tms_cash_transaction_summary transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.direction = 'receipt'
        and transaction_row.status in ('pending_allocation', 'partially_allocated')
    ),
    'unallocated_receipt_amount', coalesce((
      select sum(transaction_row.unallocated_amount)
      from public.tms_cash_transaction_summary transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.direction = 'receipt'
        and transaction_row.status in ('pending_allocation', 'partially_allocated')
    ), 0)::numeric(14, 2),
    'unallocated_payment_count', (
      select count(*)::integer
      from public.tms_cash_transaction_summary transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.direction = 'payment'
        and transaction_row.status in ('pending_allocation', 'partially_allocated')
    ),
    'unallocated_payment_amount', coalesce((
      select sum(transaction_row.unallocated_amount)
      from public.tms_cash_transaction_summary transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.direction = 'payment'
        and transaction_row.status in ('pending_allocation', 'partially_allocated')
    ), 0)::numeric(14, 2),
    'draft_invoice_count', (
      select count(*)::integer
      from public.tms_invoice_summary invoice_row
      where invoice_row.tenant_id = v_tenant_id
        and invoice_row.status = 'draft'
    ),
    'draft_invoice_amount', coalesce((
      select sum(invoice_row.total_amount)
      from public.tms_invoice_summary invoice_row
      where invoice_row.tenant_id = v_tenant_id
        and invoice_row.status = 'draft'
    ), 0)::numeric(14, 2),
    'pending_invoice_count', (
      select count(*)::integer
      from public.tms_invoice_summary invoice_row
      where invoice_row.tenant_id = v_tenant_id
        and invoice_row.status = 'pending_review'
    ),
    'pending_invoice_amount', coalesce((
      select sum(invoice_row.total_amount)
      from public.tms_invoice_summary invoice_row
      where invoice_row.tenant_id = v_tenant_id
        and invoice_row.status = 'pending_review'
    ), 0)::numeric(14, 2),
    'pending_payment_application_count', (
      select count(*)::integer
      from public.tms_carrier_payment_application application_row
      where application_row.tenant_id = v_tenant_id
        and application_row.status = 'pending_review'
    ),
    'pending_payment_application_amount', coalesce((
      select sum(application_row.amount)
      from public.tms_carrier_payment_application application_row
      where application_row.tenant_id = v_tenant_id
        and application_row.status = 'pending_review'
    ), 0)::numeric(14, 2),
    'approved_unpaid_payment_count', (
      select count(*)::integer
      from public.tms_carrier_payment_application application_row
      where application_row.tenant_id = v_tenant_id
        and application_row.status = 'approved'
    ),
    'approved_unpaid_payment_amount', coalesce((
      select sum(application_row.amount)
      from public.tms_carrier_payment_application application_row
      where application_row.tenant_id = v_tenant_id
        and application_row.status = 'approved'
    ), 0)::numeric(14, 2),
    'unapproved_payment_count', (
      select count(*)::integer
      from public.tms_cash_transaction_summary transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.direction = 'payment'
        and transaction_row.status <> 'voided'
        and transaction_row.payment_application_id is null
    ),
    'unapproved_payment_amount', coalesce((
      select sum(transaction_row.amount)
      from public.tms_cash_transaction_summary transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.direction = 'payment'
        and transaction_row.status <> 'voided'
        and transaction_row.payment_application_id is null
    ), 0)::numeric(14, 2),
    'overdue_receivable_count', (
      select count(*)::integer
      from public.tms_customer_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status in ('confirmed', 'partially_settled')
        and summary_row.outstanding_amount > 0
        and summary_row.period_end < current_date - 30
    ),
    'overdue_receivable_amount', coalesce((
      select sum(summary_row.outstanding_amount)
      from public.tms_customer_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status in ('confirmed', 'partially_settled')
        and summary_row.outstanding_amount > 0
        and summary_row.period_end < current_date - 30
    ), 0)::numeric(14, 2),
    'uninvoiced_receivable_count', (
      select count(*)::integer
      from public.tms_customer_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status in ('confirmed', 'partially_settled', 'settled')
        and greatest(
          summary_row.statement_amount - coalesce((
            select sum(link_row.linked_amount)
            from public.tms_invoice_statement_link link_row
            join public.tms_invoice invoice_row
              on invoice_row.id = link_row.invoice_id
             and invoice_row.tenant_id = v_tenant_id
            where link_row.tenant_id = v_tenant_id
              and link_row.customer_statement_id = summary_row.id
              and invoice_row.direction = 'output'
              and invoice_row.status <> 'voided'
          ), 0),
          0
        ) > 0
    ),
    'uninvoiced_receivable_amount', coalesce((
      select sum(greatest(
        summary_row.statement_amount - coalesce((
          select sum(link_row.linked_amount)
          from public.tms_invoice_statement_link link_row
          join public.tms_invoice invoice_row
            on invoice_row.id = link_row.invoice_id
           and invoice_row.tenant_id = v_tenant_id
          where link_row.tenant_id = v_tenant_id
            and link_row.customer_statement_id = summary_row.id
            and invoice_row.direction = 'output'
            and invoice_row.status <> 'voided'
        ), 0),
        0
      ))
      from public.tms_customer_statement_summary summary_row
      where summary_row.tenant_id = v_tenant_id
        and summary_row.status in ('confirmed', 'partially_settled', 'settled')
    ), 0)::numeric(14, 2)
  ) into v_data;

  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'customer_receivable_balance', 'receipt_completion_rate',
      'pending_customer_statement_amount', 'overdue_receivable_amount',
      'uninvoiced_receivable_amount'
    ]::text[],
    coalesce(v_access->>'customerSettlementAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'carrier_payable_balance', 'payment_completion_rate',
      'pending_carrier_statement_amount'
    ]::text[],
    coalesce(v_access->>'carrierSettlementAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'month_receipt_amount', 'month_payment_amount',
      'unallocated_receipt_amount', 'unallocated_payment_amount',
      'unapproved_payment_amount'
    ]::text[],
    coalesce(v_access->>'cashFlowAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['invoice_match_rate', 'draft_invoice_amount', 'pending_invoice_amount']::text[],
    coalesce(v_access->>'invoiceAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['pending_payment_application_amount', 'approved_unpaid_payment_amount']::text[],
    coalesce(v_access->>'paymentApplicationAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'month_revenue_amount', 'month_cost_amount', 'month_gross_profit',
      'cost_approval_rate', 'pending_cost_amount'
    ]::text[],
    coalesce(v_access->>'operatingAmounts', 'hidden')
  );

  return v_data || jsonb_build_object('field_access', v_access);
end;
$$;

revoke select on public.tms_finance_workbench from public, anon, authenticated;
revoke select on public.tms_finance_exception_summary from public, anon, authenticated;
grant select on public.tms_finance_workbench to service_role;
grant select on public.tms_finance_exception_summary to service_role;

revoke all on function public.tms_get_finance_workbench_secure() from public, anon;
grant execute on function public.tms_get_finance_workbench_secure()
  to authenticated, service_role;

do $$
begin
  if has_table_privilege('authenticated', 'public.tms_finance_workbench', 'SELECT') then
    raise exception 'authenticated must not read tms_finance_workbench directly';
  end if;
  if has_table_privilege('authenticated', 'public.tms_finance_exception_summary', 'SELECT') then
    raise exception 'authenticated must not read tms_finance_exception_summary directly';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.tms_get_finance_workbench_secure()', 'EXECUTE'
  ) then
    raise exception 'authenticated must execute tms_get_finance_workbench_secure';
  end if;
end;
$$;

;
