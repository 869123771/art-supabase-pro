-- Bounds privileged array RPC inputs so one authenticated request cannot create
-- an unexpectedly large transaction or amplify dependency scans.

create or replace function app_private.assert_uuid_array_limit(
  p_values uuid[],
  p_label text,
  p_limit integer default 500,
  p_allow_empty boolean default true
)
returns integer
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_count integer := coalesce(pg_catalog.cardinality(p_values), 0);
  v_limit integer := greatest(coalesce(p_limit, 500), 1);
begin
  if not coalesce(p_allow_empty, true) and v_count = 0 then
    raise exception '% cannot be empty', coalesce(nullif(btrim(p_label), ''), 'Batch input')
      using errcode = '22023';
  end if;

  if v_count > v_limit then
    raise exception '% supports at most % records per request',
      coalesce(nullif(btrim(p_label), ''), 'Batch input'), v_limit
      using errcode = '22023';
  end if;

  return v_count;
end;
$$;

revoke all on function app_private.assert_uuid_array_limit(uuid[], text, integer, boolean)
  from public, anon, authenticated;

create or replace function public.tms_delete_orders_secure(p_order_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  perform app_private.assert_uuid_array_limit(p_order_ids, 'Order batch deletion', 500, true);

  foreach v_id in array coalesce(p_order_ids, array[]::uuid[]) loop
    perform public.tms_delete_order_secure(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.tms_delete_orders_secure(uuid[]) from public, anon;
grant execute on function public.tms_delete_orders_secure(uuid[]) to authenticated;

create or replace function public.tms_cancel_waybill_orders_secure(p_order_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer := 0;
begin
  perform app_private.assert_uuid_array_limit(p_order_ids, 'Waybill cancellation', 500, true);

  foreach v_id in array coalesce(p_order_ids, array[]::uuid[]) loop
    perform public.tms_cancel_waybill_order_secure(v_id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.tms_cancel_waybill_orders_secure(uuid[]) from public, anon;
grant execute on function public.tms_cancel_waybill_orders_secure(uuid[]) to authenticated;

create or replace function public.tms_create_customer_statement_secure(
  p_customer_id uuid,
  p_period_start date,
  p_period_end date,
  p_waybill_ids uuid[],
  p_remark text default null,
  p_statement_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCustomerSettlement', 'FinanceCustomerSettlement:Add', null, false
  ) then
    raise exception 'Missing customer statement create permission' using errcode = '42501';
  end if;

  perform app_private.assert_uuid_array_limit(p_waybill_ids, 'Customer statement', 500, false);

  return public.create_tms_customer_statement(
    p_customer_id,
    p_period_start,
    p_period_end,
    p_waybill_ids,
    p_remark,
    p_statement_no
  );
end;
$$;

revoke all on function public.tms_create_customer_statement_secure(
  uuid, date, date, uuid[], text, text
) from public, anon;
grant execute on function public.tms_create_customer_statement_secure(
  uuid, date, date, uuid[], text, text
) to authenticated;

create or replace function public.tms_create_carrier_statement_secure(
  p_carrier_id uuid,
  p_period_start date,
  p_period_end date,
  p_cost_ids uuid[],
  p_remark text default null,
  p_statement_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCarrierSettlement', 'FinanceCarrierSettlement:Add', null, false
  ) then
    raise exception 'Missing carrier statement create permission' using errcode = '42501';
  end if;

  perform app_private.assert_uuid_array_limit(p_cost_ids, 'Carrier statement', 500, false);

  return public.create_tms_carrier_statement(
    p_carrier_id,
    p_period_start,
    p_period_end,
    p_cost_ids,
    p_remark,
    p_statement_no
  );
end;
$$;

revoke all on function public.tms_create_carrier_statement_secure(
  uuid, date, date, uuid[], text, text
) from public, anon;
grant execute on function public.tms_create_carrier_statement_secure(
  uuid, date, date, uuid[], text, text
) to authenticated;

create or replace function app_private.assert_customer_delete_scope(p_customer_ids uuid[])
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'TmsCustomer', 'TmsCustomer:Delete', null, false
  ) then
    raise exception 'Missing customer delete permission' using errcode = '42501';
  end if;

  perform app_private.assert_uuid_array_limit(p_customer_ids, 'Customer dependency analysis', 500, false);

  if not app_private.is_platform_super() and exists (
    select 1
    from unnest(p_customer_ids) requested(customer_id)
    left join public.tms_customer customer_row
      on customer_row.id = requested.customer_id
     and customer_row.tenant_id = v_tenant_id
    where customer_row.id is null
  ) then
    raise exception '无权读取或清理其他租户的客户依赖' using errcode = '42501';
  end if;
end;
$$;

revoke all on function app_private.assert_customer_delete_scope(uuid[])
  from public, anon, authenticated;

comment on function app_private.assert_uuid_array_limit(uuid[], text, integer, boolean) is
  'Internal fail-fast guard for bounded UUID-array RPC inputs.';
comment on function public.tms_delete_orders_secure(uuid[]) is
  'Deletes at most 500 permission-checked orders per authenticated request.';
comment on function public.tms_cancel_waybill_orders_secure(uuid[]) is
  'Cancels at most 500 permission-checked waybill orders per authenticated request.';

;
