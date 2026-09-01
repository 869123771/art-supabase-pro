-- Close AI read paths that need transport amounts after raw sensitive columns
-- were revoked from authenticated users.

create or replace function public.tms_list_carrier_waybills_secure(
  p_carrier_id uuid,
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_access jsonb := app_private.field_access_map('tms.waybill', null);
  v_result jsonb;
begin
  if p_carrier_id is null then
    raise exception 'Carrier is required';
  end if;

  if not app_private.can_execute_business_action(
    'TmsCarrierDetail',
    'TmsCarrierDetail:AiAnalyze',
    p_carrier_id,
    false
  ) then
    raise exception 'Missing carrier performance permission' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.tms_carrier carrier_row
    where carrier_row.id = p_carrier_id
      and (app_private.is_platform_super() or carrier_row.tenant_id = v_tenant_id)
  ) then
    return jsonb_build_object(
      'records', '[]'::jsonb,
      'total', 0,
      'fieldAccess', v_access
    );
  end if;

  with filtered as materialized (
    select waybill_row as waybill_record
    from public.tms_waybill waybill_row
    where waybill_row.carrier_id = p_carrier_id
      and (app_private.is_platform_super() or waybill_row.tenant_id = v_tenant_id)
  ), paged as (
    select filtered.waybill_record
    from filtered
    order by (filtered.waybill_record).create_time desc, (filtered.waybill_record).id
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_waybill_to_secure_json(paged.waybill_record, null)
        order by (paged.waybill_record).create_time desc, (paged.waybill_record).id
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_access
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.tms_list_carrier_waybills_secure(uuid, integer)
  from public, anon;
grant execute on function public.tms_list_carrier_waybills_secure(uuid, integer)
  to authenticated;


;
