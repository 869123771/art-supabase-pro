create or replace function public.get_tms_customer_delete_dependencies(p_customer_ids uuid[])
returns table (
  customer_id uuid,
  dependency_code text,
  dependency_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  with requested_customer as (
    select distinct unnest(coalesce(p_customer_ids, '{}'::uuid[])) as customer_id
  )
  select source.customer_id, source.dependency_code, count(*)::bigint as dependency_count
  from (
    select allocation.customer_id, 'cash_allocation'::text as dependency_code
    from public.tms_cash_allocation allocation
    join requested_customer requested on requested.customer_id = allocation.customer_id

    union all

    select transaction.customer_id, 'cash_transaction'::text
    from public.tms_cash_transaction transaction
    join requested_customer requested on requested.customer_id = transaction.customer_id

    union all

    select price.customer_id, 'customer_price'::text
    from public.tms_customer_price price
    join requested_customer requested on requested.customer_id = price.customer_id

    union all

    select statement.customer_id, 'customer_statement'::text
    from public.tms_customer_statement statement
    join requested_customer requested on requested.customer_id = statement.customer_id

    union all

    select statement_item.customer_id, 'customer_statement_item'::text
    from public.tms_customer_statement_item statement_item
    join requested_customer requested on requested.customer_id = statement_item.customer_id

    union all

    select invoice.customer_id, 'invoice'::text
    from public.tms_invoice invoice
    join requested_customer requested on requested.customer_id = invoice.customer_id
  ) source
  group by source.customer_id, source.dependency_code
  order by source.customer_id, source.dependency_code;
$$;

comment on function public.get_tms_customer_delete_dependencies(uuid[]) is
  'Returns tenant-scoped restrictive dependencies that must be handled before deleting customers.';

revoke all on function public.get_tms_customer_delete_dependencies(uuid[]) from public, anon;
grant execute on function public.get_tms_customer_delete_dependencies(uuid[]) to authenticated;;
