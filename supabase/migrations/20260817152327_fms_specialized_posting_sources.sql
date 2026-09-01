begin;

alter table public.fms_posting_event
  drop constraint fms_posting_event_source_check;

alter table public.fms_posting_event
  add constraint fms_posting_event_source_check check (
    source_type in (
      'customer_statement', 'carrier_statement', 'customer_receipt', 'carrier_payment',
      'invoice', 'expense_reimbursement', 'waybill_cost', 'system',
      'commercial_bill', 'fixed_asset', 'asset_depreciation', 'payroll', 'tax',
      'period_close'
    )
  );

commit;;
