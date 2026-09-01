create or replace function public.get_tms_customer_delete_safe_cleanup_candidates(
  p_customer_ids uuid[]
)
returns table (
  customer_id uuid,
  dependency_code text,
  record_id uuid
)
language sql
stable
security invoker
set search_path = ''
as $$
  with requested_customer as (
    select distinct unnest(coalesce(p_customer_ids, '{}'::uuid[])) as customer_id
  )
  select candidates.*
  from (
    select invoice.customer_id, 'invoice'::text as dependency_code, invoice.id as record_id
    from public.tms_invoice invoice
    join requested_customer requested on requested.customer_id = invoice.customer_id
    where invoice.status = 'draft'

    union all

    select statement.customer_id, 'customer_statement'::text, statement.id
    from public.tms_customer_statement statement
    join requested_customer requested on requested.customer_id = statement.customer_id
    where statement.status = 'draft'
      and not exists (
        select 1
        from public.tms_cash_allocation allocation
        where allocation.statement_id = statement.id
      )
      and not exists (
        select 1
        from public.tms_invoice_statement_link link
        join public.tms_invoice invoice on invoice.id = link.invoice_id
        where link.customer_statement_id = statement.id
          and invoice.status <> 'draft'
      )

    union all

    select price.customer_id, 'customer_price'::text, price.id
    from public.tms_customer_price price
    join requested_customer requested on requested.customer_id = price.customer_id
  ) candidates
  order by candidates.customer_id, candidates.dependency_code, candidates.record_id;
$$;

comment on function public.get_tms_customer_delete_safe_cleanup_candidates(uuid[]) is
  'Returns tenant-scoped draft or configuration records that can be safely removed before deleting customers.';

revoke all on function public.get_tms_customer_delete_safe_cleanup_candidates(uuid[]) from public, anon;
grant execute on function public.get_tms_customer_delete_safe_cleanup_candidates(uuid[]) to authenticated;

create or replace function public.cleanup_tms_customer_safe_delete_dependencies(
  p_customer_ids uuid[]
)
returns table (
  dependency_code text,
  deleted_count bigint
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  deleted_invoice_count bigint := 0;
  deleted_statement_count bigint := 0;
  deleted_price_count bigint := 0;
begin
  delete from public.tms_invoice invoice
  where invoice.customer_id = any(coalesce(p_customer_ids, '{}'::uuid[]))
    and invoice.status = 'draft';
  get diagnostics deleted_invoice_count = row_count;

  delete from public.tms_customer_statement statement
  where statement.customer_id = any(coalesce(p_customer_ids, '{}'::uuid[]))
    and statement.status = 'draft'
    and not exists (
      select 1
      from public.tms_cash_allocation allocation
      where allocation.statement_id = statement.id
    )
    and not exists (
      select 1
      from public.tms_invoice_statement_link link
      where link.customer_statement_id = statement.id
    );
  get diagnostics deleted_statement_count = row_count;

  delete from public.tms_customer_price price
  where price.customer_id = any(coalesce(p_customer_ids, '{}'::uuid[]));
  get diagnostics deleted_price_count = row_count;

  return query
  values
    ('invoice'::text, deleted_invoice_count),
    ('customer_statement'::text, deleted_statement_count),
    ('customer_price'::text, deleted_price_count);
end;
$$;

comment on function public.cleanup_tms_customer_safe_delete_dependencies(uuid[]) is
  'Atomically removes tenant-scoped draft invoices, unallocated draft statements, and customer price configurations before customer deletion.';

revoke all on function public.cleanup_tms_customer_safe_delete_dependencies(uuid[]) from public, anon;
grant execute on function public.cleanup_tms_customer_safe_delete_dependencies(uuid[]) to authenticated;;
