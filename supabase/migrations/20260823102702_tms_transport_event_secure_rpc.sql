create or replace function public.tms_list_transport_events_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_event_type text default null,
  p_keyword text default null,
  p_event_start timestamptz default null,
  p_event_end timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if not coalesce(app_private.has_permission('TmsTransportEvent:View'), false) then
    raise exception 'Missing transport event view permission' using errcode = '42501';
  end if;

  with filtered as materialized (
    select event_row, waybill_row
    from public.tms_waybill_event event_row
    join public.tms_waybill waybill_row on waybill_row.id = event_row.waybill_id
    where (app_private.is_platform_super() or event_row.tenant_id = v_tenant_id)
      and waybill_row.tenant_id = event_row.tenant_id
      and (p_event_type is null or event_row.event_type = p_event_type)
      and (p_event_start is null or event_row.event_time >= p_event_start)
      and (p_event_end is null or event_row.event_time <= p_event_end)
      and (
        nullif(btrim(p_keyword), '') is null
        or event_row.event_type ilike '%' || btrim(p_keyword) || '%'
        or event_row.operator_name ilike '%' || btrim(p_keyword) || '%'
        or event_row.location_text ilike '%' || btrim(p_keyword) || '%'
        or event_row.remark ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select filtered.event_row, filtered.waybill_row
    from filtered
    order by (filtered.event_row).event_time desc, (filtered.event_row).id desc
    offset greatest(coalesce(p_from, 0), 0)
    limit least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1), 500)
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', (paged.event_row).id,
          'tenantId', (paged.event_row).tenant_id,
          'waybillId', (paged.event_row).waybill_id,
          'eventType', (paged.event_row).event_type,
          'eventTime', (paged.event_row).event_time,
          'operatorName', (paged.event_row).operator_name,
          'locationText', (paged.event_row).location_text,
          'remark', (paged.event_row).remark,
          'createTime', (paged.event_row).create_time,
          'delayed', (
            (paged.waybill_row).status = any(array['pending','accepted','loading','transporting','unloading'])
            and (paged.waybill_row).planned_unload_time is not null
            and (paged.waybill_row).planned_unload_time < now()
          ),
          'waybill', jsonb_build_object(
            'id', (paged.waybill_row).id,
            'waybillNo', (paged.waybill_row).waybill_no,
            'status', (paged.waybill_row).status,
            'originCity', (paged.waybill_row).origin_city,
            'destinationCity', (paged.waybill_row).destination_city,
            'plannedUnloadTime', (paged.waybill_row).planned_unload_time
          )
        ) order by (paged.event_row).event_time desc, (paged.event_row).id desc
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'overview', jsonb_build_object(
      'eventCount7d', (
        select count(*) from public.tms_waybill_event event_row
        where (app_private.is_platform_super() or event_row.tenant_id = v_tenant_id)
          and event_row.event_time >= now() - interval '7 days'
      ),
      'activeWaybillCount', (
        select count(*) from public.tms_waybill waybill_row
        where (app_private.is_platform_super() or waybill_row.tenant_id = v_tenant_id)
          and waybill_row.status = any(array['pending','accepted','loading','transporting','unloading'])
      ),
      'delayedWaybillCount', (
        select count(*) from public.tms_waybill waybill_row
        where (app_private.is_platform_super() or waybill_row.tenant_id = v_tenant_id)
          and waybill_row.status = any(array['pending','accepted','loading','transporting','unloading'])
          and waybill_row.planned_unload_time is not null
          and waybill_row.planned_unload_time < now()
      ),
      'exceptionEventCount', (
        select count(*) from public.tms_waybill_event event_row
        where (app_private.is_platform_super() or event_row.tenant_id = v_tenant_id)
          and event_row.event_type = 'status_changed'
          and event_row.event_time >= now() - interval '7 days'
      )
    )
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.tms_list_transport_events_secure(integer, integer, text, text, timestamptz, timestamptz) from public, anon;
grant execute on function public.tms_list_transport_events_secure(integer, integer, text, text, timestamptz, timestamptz) to authenticated, service_role;

;
