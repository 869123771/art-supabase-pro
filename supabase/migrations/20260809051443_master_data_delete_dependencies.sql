create or replace function public.get_master_data_delete_dependency_details(
  p_resource_type text,
  p_resource_ids uuid[]
)
returns table (
  resource_id uuid,
  dependency_code text,
  record_id uuid,
  target_id uuid,
  record_no text,
  record_summary text,
  record_status text,
  record_amount numeric,
  created_at timestamptz,
  cleanup_allowed boolean
)
language sql
stable
security invoker
set search_path = ''
as $$
  with requested as (
    select distinct unnest(coalesce(p_resource_ids, '{}'::uuid[])) as resource_id
  )
  select details.*
  from (
    select price.carrier_id, 'carrier_price'::text, price.id, price.id,
      concat_ws(' -> ', nullif(price.origin_region, ''), nullif(price.destination_region, '')),
      price.billing_method, null::text, price.total_fee, price.create_time, true
    from public.tms_carrier_price price
    join requested on requested.resource_id = price.carrier_id
    where p_resource_type = 'carrier'

    union all

    select contract.carrier_id, 'contract', contract.id, contract.id,
      coalesce(nullif(contract.contract_no, ''), contract.id::text), contract.contract_name,
      contract.contract_status, contract.contract_amount, contract.create_time, false
    from public.tms_contract contract
    join requested on requested.resource_id = contract.carrier_id
    where p_resource_type = 'carrier'

    union all

    select driver.carrier_id, 'driver', driver.id, driver.id,
      driver.driver_name, driver.phone, case when driver.enabled then 'enabled' else 'disabled' end,
      null::numeric, driver.create_time, false
    from public.tms_driver driver
    join requested on requested.resource_id = driver.carrier_id
    where p_resource_type = 'carrier'

    union all

    select waybill.carrier_id, 'waybill', waybill.id, waybill.id,
      waybill.waybill_no, concat_ws(' -> ', waybill.origin_city, waybill.destination_city),
      waybill.status, waybill.freight_amount, waybill.create_time, false
    from public.tms_waybill waybill
    join requested on requested.resource_id = waybill.carrier_id
    where p_resource_type = 'carrier'

    union all

    select statement.carrier_id, 'carrier_statement', statement.id, statement.id,
      statement.statement_no, concat(statement.period_start::text, ' - ', statement.period_end::text),
      statement.status, statement.settled_amount, statement.create_time, false
    from public.tms_carrier_statement statement
    join requested on requested.resource_id = statement.carrier_id
    where p_resource_type = 'carrier'

    union all

    select item.carrier_id, 'carrier_statement_item', item.id, item.statement_id,
      coalesce(nullif(item.waybill_no_snapshot, ''), item.id::text), item.cost_type_snapshot,
      case when item.is_active then 'active' else 'inactive' end,
      item.line_amount, item.create_time, false
    from public.tms_carrier_statement_item item
    join requested on requested.resource_id = item.carrier_id
    where p_resource_type = 'carrier'

    union all

    select application.carrier_id, 'payment_application', application.id, application.id,
      application.application_no, application.planned_payment_date::text,
      application.status, application.amount, application.create_time, false
    from public.tms_carrier_payment_application application
    join requested on requested.resource_id = application.carrier_id
    where p_resource_type = 'carrier'

    union all

    select item.carrier_id, 'payment_application_item', item.id, item.application_id,
      coalesce(nullif(item.statement_no_snapshot, ''), item.id::text), null::text,
      null::text, item.applied_amount, item.create_time, false
    from public.tms_carrier_payment_application_item item
    join requested on requested.resource_id = item.carrier_id
    where p_resource_type = 'carrier'

    union all

    select allocation.carrier_id, 'carrier_cash_allocation', allocation.id, allocation.transaction_id,
      coalesce(transaction.transaction_no, allocation.id::text), statement.statement_no,
      case when allocation.is_active then 'active' else 'reversed' end,
      allocation.allocated_amount, allocation.create_time, false
    from public.tms_carrier_cash_allocation allocation
    join requested on requested.resource_id = allocation.carrier_id
    left join public.tms_cash_transaction transaction on transaction.id = allocation.transaction_id
    left join public.tms_carrier_statement statement on statement.id = allocation.statement_id
    where p_resource_type = 'carrier'

    union all

    select transaction.carrier_id, 'carrier_cash_transaction', transaction.id, transaction.id,
      transaction.transaction_no, transaction.bank_reference, transaction.status,
      transaction.amount, transaction.create_time, false
    from public.tms_cash_transaction transaction
    join requested on requested.resource_id = transaction.carrier_id
    where p_resource_type = 'carrier'

    union all

    select invoice.carrier_id, 'carrier_invoice', invoice.id, invoice.id,
      coalesce(nullif(invoice.invoice_no, ''), invoice.invoice_record_no), invoice.invoice_record_no,
      invoice.status, invoice.total_amount, invoice.create_time, false
    from public.tms_invoice invoice
    join requested on requested.resource_id = invoice.carrier_id
    where p_resource_type = 'carrier'

    union all

    select waybill.driver_id, 'driver_waybill', waybill.id, waybill.id,
      waybill.waybill_no, concat_ws(' -> ', waybill.origin_city, waybill.destination_city),
      waybill.status, waybill.freight_amount, waybill.create_time, false
    from public.tms_waybill waybill
    join requested on requested.resource_id = waybill.driver_id
    where p_resource_type = 'driver'

    union all

    select waybill.cargo_id, 'cargo_waybill', waybill.id, waybill.id,
      waybill.waybill_no, concat_ws(' -> ', waybill.origin_city, waybill.destination_city),
      waybill.status, waybill.freight_amount, waybill.create_time, false
    from public.tms_waybill waybill
    join requested on requested.resource_id = waybill.cargo_id
    where p_resource_type = 'cargo'

    union all

    select requested.resource_id, 'address_waybill', waybill.id, waybill.id,
      waybill.waybill_no, concat_ws(' -> ', waybill.origin_city, waybill.destination_city),
      waybill.status, waybill.freight_amount, waybill.create_time, false
    from public.tms_waybill waybill
    join requested on requested.resource_id in (waybill.shipper_address_id, waybill.receiver_address_id)
    where p_resource_type = 'customer_address'

    union all

    select waybill.vehicle_id, 'vehicle_waybill', waybill.id, waybill.id,
      waybill.waybill_no, concat_ws(' -> ', waybill.origin_city, waybill.destination_city),
      waybill.status, waybill.freight_amount, waybill.create_time, false
    from public.tms_waybill waybill
    join requested on requested.resource_id = waybill.vehicle_id
    where p_resource_type = 'vehicle'

    union all

    select work_order.vehicle_id, 'vehicle_reminder_work_order', work_order.id, work_order.id,
      coalesce(nullif(work_order.source_key, ''), work_order.id::text), work_order.title,
      work_order.status, null::numeric, work_order.create_time,
      work_order.status in ('cancelled', 'resolved', 'closed')
    from public.vehicle_reminder_work_order work_order
    join requested on requested.resource_id = work_order.vehicle_id
    where p_resource_type = 'vehicle'
  ) details(
    resource_id,
    dependency_code,
    record_id,
    target_id,
    record_no,
    record_summary,
    record_status,
    record_amount,
    created_at,
    cleanup_allowed
  )
  order by details.resource_id, details.cleanup_allowed desc, details.dependency_code,
    details.created_at desc, details.record_id;
$$;

comment on function public.get_master_data_delete_dependency_details(text, uuid[]) is
  'Returns tenant-scoped exact blocking records for supported master-data deletion workflows.';

revoke all on function public.get_master_data_delete_dependency_details(text, uuid[]) from public, anon;
grant execute on function public.get_master_data_delete_dependency_details(text, uuid[]) to authenticated;

create or replace function public.cleanup_master_data_delete_dependencies(
  p_resource_type text,
  p_resource_ids uuid[],
  p_dependency_code text,
  p_record_ids uuid[]
)
returns bigint
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  deleted_count bigint := 0;
begin
  if coalesce(array_length(p_resource_ids, 1), 0) = 0
    or coalesce(array_length(p_record_ids, 1), 0) = 0 then
    return 0;
  end if;

  if p_resource_type = 'carrier' and p_dependency_code = 'carrier_price' then
    delete from public.tms_carrier_price price
    where price.carrier_id = any(p_resource_ids)
      and price.id = any(p_record_ids);
    get diagnostics deleted_count = row_count;
    return deleted_count;
  end if;

  if p_resource_type = 'vehicle' and p_dependency_code = 'vehicle_reminder_work_order' then
    delete from public.vehicle_reminder_work_order work_order
    where work_order.vehicle_id = any(p_resource_ids)
      and work_order.id = any(p_record_ids)
      and work_order.status in ('cancelled', 'resolved', 'closed');
    get diagnostics deleted_count = row_count;
    return deleted_count;
  end if;

  raise exception 'unsupported safe cleanup: % / %', p_resource_type, p_dependency_code
    using errcode = '22023';
end;
$$;

comment on function public.cleanup_master_data_delete_dependencies(text, uuid[], text, uuid[]) is
  'Deletes only explicitly selected configuration or terminal-state records approved for safe cleanup.';

revoke all on function public.cleanup_master_data_delete_dependencies(text, uuid[], text, uuid[]) from public, anon;
grant execute on function public.cleanup_master_data_delete_dependencies(text, uuid[], text, uuid[]) to authenticated;

;
