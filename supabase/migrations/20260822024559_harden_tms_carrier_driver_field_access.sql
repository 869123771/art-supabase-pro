-- Carrier and driver references are consumed by TMS, VMS and a few finance
-- workflows. They may expose only field-authorized values, and callers must own
-- at least one menu that legitimately consumes the reference data.
create or replace function app_private.can_access_tms_carrier_reference_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.sys_menu menu_row
      where menu_row.type = 'menu'
        and (
          menu_row.name = any(array[
            'TmsCarrier',
            'TmsCarrierDetail',
            'TmsDriver',
            'TmsContract',
            'TmsContractDetail',
            'TmsCarrierPrice',
            'TmsCarrierPriceDetail',
            'TmsCarrierPriceEdit',
            'TmsOrderOpen',
            'TmsOrderList',
            'TmsPendingWaybillList',
            'TmsLoadedWaybillList',
            'TmsWaybillDetail',
            'TmsInTransitMonitor',
            'FinanceCarrierSettlement',
            'FinanceCashTransaction',
            'FinanceInvoiceManagement',
            'FinanceCarrierPaymentApplication',
            'FinanceWaybillCost',
            'FinanceWaybillCostDetail',
            'FinanceWaybillProfit'
          ]::text[])
          or menu_row.name like 'Vehicle%'
        )
        and app_private.can_access_business_menu(menu_row.name)
    );
$$;

create or replace function app_private.can_access_tms_driver_reference_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from public.sys_menu menu_row
      where menu_row.type = 'menu'
        and (
          menu_row.name = any(array[
            'TmsDriver',
            'TmsCarrier',
            'TmsCarrierDetail',
            'TmsCarrierPrice',
            'TmsCarrierPriceDetail',
            'TmsCarrierPriceEdit',
            'TmsOrderOpen',
            'TmsOrderList',
            'TmsPendingWaybillList',
            'TmsLoadedWaybillList',
            'TmsWaybillDetail',
            'TmsInTransitMonitor'
          ]::text[])
          or menu_row.name like 'Vehicle%'
        )
        and app_private.can_access_business_menu(menu_row.name)
    );
$$;

create or replace function public.tms_list_carrier_options_secure(
  p_exclude_id uuid default null,
  p_include_disabled boolean default false,
  p_keyword text default null,
  p_ids uuid[] default null,
  p_max_rows integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb;
  v_can_search_phone boolean;
begin
  if not app_private.can_access_tms_carrier_reference_data()
     or v_tenant_id is null then
    raise exception 'Missing carrier reference data permission' using errcode = '42501';
  end if;

  v_access := app_private.field_access_map('tms.carrier', null);
  v_can_search_phone := coalesce(v_access->>'contactPhone', 'hidden') in ('read', 'edit');

  return coalesce((
    select jsonb_agg(
      app_private.tms_carrier_option_to_secure_json(carrier_row)
      order by carrier_row.company_name, carrier_row.id
    )
    from (
      select carrier_record.*
      from public.tms_carrier carrier_record
      where (app_private.is_platform_super() or carrier_record.tenant_id = v_tenant_id)
        and (p_include_disabled or carrier_record.enabled)
        and (p_exclude_id is null or carrier_record.id <> p_exclude_id)
        and (p_ids is null or carrier_record.id = any(p_ids))
        and (
          nullif(btrim(p_keyword), '') is null
          or carrier_record.company_name ilike '%' || btrim(p_keyword) || '%'
          or carrier_record.carrier_code ilike '%' || btrim(p_keyword) || '%'
          or carrier_record.contact_name ilike '%' || btrim(p_keyword) || '%'
          or (
            v_can_search_phone
            and carrier_record.contact_phone ilike '%' || btrim(p_keyword) || '%'
          )
        )
      order by carrier_record.company_name, carrier_record.id
      limit least(greatest(coalesce(p_max_rows, 200), 1), 1000)
    ) carrier_row
  ), '[]'::jsonb);
end;
$$;

create or replace function public.tms_list_driver_options_secure(
  p_carrier_id uuid default null,
  p_driver_name text default null,
  p_driver_type text default null,
  p_ids uuid[] default null,
  p_include_disabled boolean default false,
  p_max_rows integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb;
  v_can_search_phone boolean;
begin
  if not app_private.can_access_tms_driver_reference_data()
     or v_tenant_id is null then
    raise exception 'Missing driver reference data permission' using errcode = '42501';
  end if;

  v_access := app_private.field_access_map('tms.driver', null);
  v_can_search_phone := coalesce(v_access->>'contactPhone', 'hidden') in ('read', 'edit');

  return coalesce((
    select jsonb_agg(
      app_private.tms_driver_option_to_secure_json(driver_row)
      order by driver_row.driver_name, driver_row.id
    )
    from (
      select driver_record.*
      from public.tms_driver driver_record
      where (app_private.is_platform_super() or driver_record.tenant_id = v_tenant_id)
        and (p_include_disabled or driver_record.enabled)
        and (p_carrier_id is null or driver_record.carrier_id = p_carrier_id)
        and (p_driver_type is null or driver_record.driver_type = p_driver_type)
        and (p_ids is null or driver_record.id = any(p_ids))
        and (
          nullif(btrim(p_driver_name), '') is null
          or driver_record.driver_name ilike '%' || btrim(p_driver_name) || '%'
          or (
            v_can_search_phone
            and driver_record.phone ilike '%' || btrim(p_driver_name) || '%'
          )
        )
      order by driver_record.driver_name, driver_record.id
      limit least(greatest(coalesce(p_max_rows, 200), 1), 1000)
    ) driver_row
  ), '[]'::jsonb);
end;
$$;

-- The Edge Function must not query protected master tables directly. This RPC
-- returns only the non-sensitive carrier facts and aggregates needed by the
-- read-only performance assessment.
create or replace function public.tms_get_carrier_performance_context_secure(
  p_carrier_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_carrier public.tms_carrier%rowtype;
  v_statements jsonb;
  v_driver_count integer;
  v_vehicle_count integer;
begin
  if p_carrier_id is null then
    raise exception 'Carrier is required';
  end if;
  if not app_private.can_execute_business_action(
    'TmsCarrierDetail', 'TmsCarrierDetail:AiAnalyze', null, false
  ) then
    raise exception 'Missing carrier AI analyze permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  select * into v_carrier
  from public.tms_carrier carrier_row
  where carrier_row.id = p_carrier_id
    and (app_private.is_platform_super() or carrier_row.tenant_id = v_tenant_id);
  if not found then
    return null;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', statement_row.id,
    'statement_no', statement_row.statement_no,
    'status', statement_row.status,
    'period_start', statement_row.period_start,
    'period_end', statement_row.period_end
  ) order by statement_row.period_end desc, statement_row.id), '[]'::jsonb)
  into v_statements
  from (
    select statement_record.*
    from public.tms_carrier_statement statement_record
    where statement_record.carrier_id = v_carrier.id
      and statement_record.tenant_id = v_carrier.tenant_id
    order by statement_record.period_end desc, statement_record.id
    limit 100
  ) statement_row;

  select count(*) into v_driver_count
  from public.tms_driver driver_row
  where driver_row.carrier_id = v_carrier.id
    and driver_row.tenant_id = v_carrier.tenant_id
    and driver_row.enabled;

  select count(*) into v_vehicle_count
  from public.vehicle_archive vehicle_row
  where vehicle_row.carrier_id = v_carrier.id
    and vehicle_row.tenant_id = v_carrier.tenant_id;

  return jsonb_build_object(
    'carrier', jsonb_build_object(
      'id', v_carrier.id,
      'carrier_code', v_carrier.carrier_code,
      'company_name', v_carrier.company_name,
      'carrier_type', v_carrier.carrier_type,
      'business_license_no', v_carrier.business_license_no,
      'signed_contract', v_carrier.signed_contract,
      'enabled', v_carrier.enabled,
      'create_time', v_carrier.create_time
    ),
    'statements', v_statements,
    'driver_count', coalesce(v_driver_count, 0),
    'vehicle_count', coalesce(v_vehicle_count, 0)
  );
end;
$$;

revoke all on function app_private.can_access_tms_carrier_reference_data()
from public, anon, authenticated;
revoke all on function app_private.can_access_tms_driver_reference_data()
from public, anon, authenticated;
grant execute on function app_private.can_access_tms_carrier_reference_data()
to service_role;
grant execute on function app_private.can_access_tms_driver_reference_data()
to service_role;

revoke all on function public.tms_list_carrier_options_secure(
  uuid, boolean, text, uuid[], integer
) from public, anon;
revoke all on function public.tms_list_driver_options_secure(
  uuid, text, text, uuid[], boolean, integer
) from public, anon;
revoke all on function public.tms_get_carrier_performance_context_secure(uuid)
from public, anon;

grant execute on function public.tms_list_carrier_options_secure(
  uuid, boolean, text, uuid[], integer
) to authenticated, service_role;
grant execute on function public.tms_list_driver_options_secure(
  uuid, text, text, uuid[], boolean, integer
) to authenticated, service_role;
grant execute on function public.tms_get_carrier_performance_context_secure(uuid)
to authenticated, service_role;

;
