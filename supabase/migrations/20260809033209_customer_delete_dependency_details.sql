create or replace function public.get_tms_customer_delete_dependency_details(p_customer_ids uuid[])
returns table (
  customer_id uuid,
  dependency_code text,
  record_id uuid,
  target_id uuid,
  record_no text,
  record_summary text,
  record_status text,
  record_amount numeric,
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  with requested_customer as (
    select distinct unnest(coalesce(p_customer_ids, '{}'::uuid[])) as customer_id
  )
  select details.*
  from (
    select
      allocation.customer_id,
      'cash_allocation'::text as dependency_code,
      allocation.id as record_id,
      allocation.transaction_id as target_id,
      coalesce(transaction.transaction_no, allocation.id::text) as record_no,
      statement.statement_no as record_summary,
      case when allocation.is_active then 'active' else 'reversed' end as record_status,
      allocation.allocated_amount as record_amount,
      allocation.create_time as created_at
    from public.tms_cash_allocation allocation
    join requested_customer requested on requested.customer_id = allocation.customer_id
    left join public.tms_cash_transaction transaction on transaction.id = allocation.transaction_id
    left join public.tms_customer_statement statement on statement.id = allocation.statement_id

    union all

    select
      transaction.customer_id,
      'cash_transaction'::text,
      transaction.id,
      transaction.id,
      transaction.transaction_no,
      transaction.bank_reference,
      transaction.status,
      transaction.amount,
      transaction.create_time
    from public.tms_cash_transaction transaction
    join requested_customer requested on requested.customer_id = transaction.customer_id

    union all

    select
      price.customer_id,
      'customer_price'::text,
      price.id,
      price.id,
      concat_ws(' → ', nullif(price.origin_region, ''), nullif(price.destination_region, '')),
      price.billing_method,
      null::text,
      price.total_fee,
      price.create_time
    from public.tms_customer_price price
    join requested_customer requested on requested.customer_id = price.customer_id

    union all

    select
      statement.customer_id,
      'customer_statement'::text,
      statement.id,
      statement.id,
      statement.statement_no,
      concat(statement.period_start::text, ' 至 ', statement.period_end::text),
      statement.status,
      statement.settled_amount,
      statement.create_time
    from public.tms_customer_statement statement
    join requested_customer requested on requested.customer_id = statement.customer_id

    union all

    select
      statement_item.customer_id,
      'customer_statement_item'::text,
      statement_item.id,
      statement_item.statement_id,
      coalesce(statement_item.waybill_no_snapshot, statement_item.order_no_snapshot, statement_item.id::text),
      statement.statement_no,
      case when statement_item.is_active then 'active' else 'inactive' end,
      statement_item.line_amount,
      statement_item.create_time
    from public.tms_customer_statement_item statement_item
    join requested_customer requested on requested.customer_id = statement_item.customer_id
    left join public.tms_customer_statement statement on statement.id = statement_item.statement_id

    union all

    select
      invoice.customer_id,
      'invoice'::text,
      invoice.id,
      invoice.id,
      coalesce(nullif(invoice.invoice_no, ''), invoice.invoice_record_no),
      invoice.invoice_record_no,
      invoice.status,
      invoice.total_amount,
      invoice.create_time
    from public.tms_invoice invoice
    join requested_customer requested on requested.customer_id = invoice.customer_id
  ) details
  order by details.customer_id, details.dependency_code, details.created_at desc, details.record_id;
$$;

comment on function public.get_tms_customer_delete_dependency_details(uuid[]) is
  'Returns tenant-scoped record details for dependencies that block customer deletion.';

revoke all on function public.get_tms_customer_delete_dependency_details(uuid[]) from public, anon;
grant execute on function public.get_tms_customer_delete_dependency_details(uuid[]) to authenticated;;
