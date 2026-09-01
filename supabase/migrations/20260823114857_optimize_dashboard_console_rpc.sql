
create or replace function public.get_dashboard_console(
  p_period text default 'month',
  p_reference_date date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_period text := lower(coalesce(nullif(btrim(p_period), ''), 'month'));
  v_today date := coalesce(p_reference_date, (now() at time zone 'Asia/Shanghai')::date);
  v_period_start_date date;
  v_period_end_date date;
  v_today_start timestamptz;
  v_today_end timestamptz;
  v_period_start timestamptz;
  v_period_end timestamptz;
  v_trend_unit text;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_is_platform_super boolean := app_private.is_platform_super();
  v_can_read_tms boolean := app_private.can_read_tms_order_scope('dashboard');
  v_can_read_vms boolean := app_private.can_access_vms_vehicle_reference_data();
  v_tms_field_access jsonb := '{}'::jsonb;
  v_can_read_freight boolean := false;
  v_tms_metrics jsonb := jsonb_build_object(
    'today_order_count', 0,
    'today_freight_amount', 0,
    'pending_dispatch_count', 0,
    'in_transit_count', 0,
    'completed_today_count', 0
  );
  v_vehicle_metrics jsonb := jsonb_build_object(
    'vehicle_count', 0,
    'operating_vehicle_count', 0,
    'pending_audit_vehicle_count', 0
  );
  v_status_counts jsonb := jsonb_build_object(
    'pending_load', 0,
    'pending_order', 0,
    'transporting', 0,
    'signed', 0,
    'completed', 0
  );
  v_trend jsonb := '[]'::jsonb;
  v_transit_orders jsonb := '[]'::jsonb;
  v_recent_orders jsonb := '[]'::jsonb;
  v_insurance_count bigint := 0;
  v_inspection_count bigint := 0;
  v_maintenance_count bigint := 0;
  v_part_count bigint := 0;
  v_vehicle_reminder_count bigint := 0;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  if v_period not in ('today', 'week', 'month', 'year') then
    raise exception 'Unsupported dashboard period' using errcode = '22023';
  end if;

  if not v_can_read_tms and not v_can_read_vms then
    raise exception 'Missing dashboard read permission' using errcode = '42501';
  end if;

  v_period_start_date := case v_period
    when 'today' then v_today
    when 'week' then v_today - ((extract(isodow from v_today)::integer) - 1)
    when 'month' then date_trunc('month', v_today)::date
    else date_trunc('year', v_today)::date
  end;
  v_period_end_date := case v_period
    when 'today' then v_period_start_date + 1
    when 'week' then v_period_start_date + 7
    when 'month' then (v_period_start_date + interval '1 month')::date
    else (v_period_start_date + interval '1 year')::date
  end;
  v_trend_unit := case
    when v_period = 'today' then 'hour'
    when v_period = 'year' then 'month'
    else 'day'
  end;
  v_today_start := v_today::timestamp at time zone 'Asia/Shanghai';
  v_today_end := (v_today + 1)::timestamp at time zone 'Asia/Shanghai';
  v_period_start := v_period_start_date::timestamp at time zone 'Asia/Shanghai';
  v_period_end := v_period_end_date::timestamp at time zone 'Asia/Shanghai';

  if v_can_read_tms then
    v_tms_field_access := app_private.field_access_map('tms.order', null);
    v_can_read_freight :=
      coalesce(v_tms_field_access->>'freightAmounts', 'hidden') in ('read', 'edit');

    select jsonb_build_object(
      'today_order_count',
        count(*) filter (
          where order_row.create_time >= v_today_start
            and order_row.create_time < v_today_end
        ),
      'today_freight_amount',
        case
          when v_can_read_freight then coalesce(sum(order_row.total_fee) filter (
            where order_row.create_time >= v_today_start
              and order_row.create_time < v_today_end
          ), 0)
          else 0
        end,
      'pending_dispatch_count',
        count(*) filter (where order_row.dispatch_status = 'pending'),
      'in_transit_count',
        count(*) filter (where order_row.order_status = 'transporting'),
      'completed_today_count',
        count(*) filter (
          where order_row.order_status = 'completed'
            and order_row.signed_at >= v_today_start
            and order_row.signed_at < v_today_end
        )
    )
    into v_tms_metrics
    from public.tms_order order_row
    where v_is_platform_super or order_row.tenant_id = v_tenant_id;

    select jsonb_build_object(
      'pending_load', count(*) filter (where order_row.order_status = 'pending_load'),
      'pending_order', count(*) filter (where order_row.order_status = 'pending_order'),
      'transporting', count(*) filter (where order_row.order_status = 'transporting'),
      'signed', count(*) filter (where order_row.order_status = 'signed'),
      'completed', count(*) filter (where order_row.order_status = 'completed')
    )
    into v_status_counts
    from public.tms_order order_row
    where (v_is_platform_super or order_row.tenant_id = v_tenant_id)
      and order_row.create_time >= v_period_start
      and order_row.create_time < v_period_end;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'date',
            case
              when v_period = 'today' then to_char(trend_row.bucket, 'YYYY-MM-DD HH24')
              when v_period = 'year' then to_char(trend_row.bucket, 'YYYY-MM')
              else to_char(trend_row.bucket, 'YYYY-MM-DD')
            end,
          'order_count', trend_row.order_count,
          'freight_amount', trend_row.freight_amount
        )
        order by trend_row.bucket
      ),
      '[]'::jsonb
    )
    into v_trend
    from (
      select
        date_trunc(v_trend_unit, order_row.create_time at time zone 'Asia/Shanghai') as bucket,
        count(*) as order_count,
        case
          when v_can_read_freight then coalesce(sum(order_row.total_fee), 0)
          else 0
        end as freight_amount
      from public.tms_order order_row
      where (v_is_platform_super or order_row.tenant_id = v_tenant_id)
        and order_row.create_time >= v_period_start
        and order_row.create_time < v_period_end
      group by 1
    ) trend_row;

    select coalesce(
      jsonb_agg(
        app_private.tms_order_to_secure_json(
          transit_row.order_record,
          'tms.order',
          null,
          null
        )
        order by (transit_row.order_record).create_time desc, (transit_row.order_record).id
      ),
      '[]'::jsonb
    )
    into v_transit_orders
    from (
      select order_row as order_record
      from public.tms_order order_row
      where (v_is_platform_super or order_row.tenant_id = v_tenant_id)
        and order_row.order_status = 'transporting'
      order by order_row.create_time desc, order_row.id
      limit 6
    ) transit_row;

    select coalesce(
      jsonb_agg(
        app_private.tms_order_to_secure_json(
          recent_row.order_record,
          'tms.order',
          null,
          null
        )
        order by (recent_row.order_record).create_time desc, (recent_row.order_record).id
      ),
      '[]'::jsonb
    )
    into v_recent_orders
    from (
      select order_row as order_record
      from public.tms_order order_row
      where v_is_platform_super or order_row.tenant_id = v_tenant_id
      order by order_row.create_time desc, order_row.id
      limit 6
    ) recent_row;
  end if;

  if v_can_read_vms then
    select jsonb_build_object(
      'vehicle_count', count(*),
      'operating_vehicle_count',
        count(*) filter (where vehicle_row.operation_status = 'operating'),
      'pending_audit_vehicle_count',
        count(*) filter (where vehicle_row.audit_status = 'pending')
    )
    into v_vehicle_metrics
    from public.vehicle_archive vehicle_row
    where v_is_platform_super or vehicle_row.tenant_id = v_tenant_id;

    select
      count(*) filter (
        where insurance_row.commercial_expire_date is not null
          and insurance_row.commercial_expire_date <= v_today + 30
      )
      + count(*) filter (
        where insurance_row.compulsory_expire_date is not null
          and insurance_row.compulsory_expire_date <= v_today + 30
      )
    into v_insurance_count
    from public.vehicle_insurance insurance_row
    where v_is_platform_super or insurance_row.tenant_id = v_tenant_id;

    select count(*)
    into v_inspection_count
    from public.vehicle_inspection inspection_row
    where (v_is_platform_super or inspection_row.tenant_id = v_tenant_id)
      and inspection_row.expire_date is not null
      and inspection_row.expire_date <= v_today + 30;

    with latest_maintenance as (
      select ranked.*
      from (
        select
          maintenance_row.*,
          row_number() over (
            partition by
              maintenance_row.tenant_id,
              coalesce(maintenance_row.vehicle_id::text, maintenance_row.plate_no)
            order by maintenance_row.start_time desc, maintenance_row.create_time desc
          ) as row_no
        from public.vehicle_maintenance_record maintenance_row
        where (v_is_platform_super or maintenance_row.tenant_id = v_tenant_id)
          and maintenance_row.maintenance_type = 'maintenance'
      ) ranked
      where ranked.row_no = 1
    )
    select count(*)
    into v_maintenance_count
    from latest_maintenance maintenance_row
    left join lateral (
      select coalesce(
        mileage_row.end_mileage,
        mileage_row.running_mileage,
        mileage_row.start_mileage
      ) as current_mileage
      from public.vehicle_mileage_record mileage_row
      where mileage_row.tenant_id = maintenance_row.tenant_id
        and (
          mileage_row.vehicle_id = maintenance_row.vehicle_id
          or (
            maintenance_row.vehicle_id is null
            and mileage_row.plate_no = maintenance_row.plate_no
          )
        )
      order by coalesce(
        mileage_row.end_time,
        mileage_row.start_time,
        mileage_row.create_time
      ) desc
      limit 1
    ) latest_mileage on true
    left join lateral (
      select coalesce(
        mileage_row.end_mileage,
        mileage_row.running_mileage,
        mileage_row.start_mileage
      ) as maintenance_mileage
      from public.vehicle_mileage_record mileage_row
      where mileage_row.tenant_id = maintenance_row.tenant_id
        and (
          mileage_row.vehicle_id = maintenance_row.vehicle_id
          or (
            maintenance_row.vehicle_id is null
            and mileage_row.plate_no = maintenance_row.plate_no
          )
        )
        and coalesce(
          mileage_row.end_time,
          mileage_row.start_time,
          mileage_row.create_time
        ) <= maintenance_row.start_time
      order by coalesce(
        mileage_row.end_time,
        mileage_row.start_time,
        mileage_row.create_time
      ) desc
      limit 1
    ) maintenance_mileage on true
    where (maintenance_row.start_time + interval '6 months')::date < v_today
      or (
        latest_mileage.current_mileage is not null
        and maintenance_mileage.maintenance_mileage is not null
        and latest_mileage.current_mileage >= maintenance_mileage.maintenance_mileage + 5000
      );

    select count(*)
    into v_part_count
    from public.vehicle_part_usage part_row
    where (v_is_platform_super or part_row.tenant_id = v_tenant_id)
      and part_row.service_years_enabled is true
      and part_row.enable_date is not null
      and part_row.service_years is not null
      and (
        (
          part_row.enable_date + make_interval(years => part_row.service_years)
        )::date < v_today
        or (
          part_row.service_mileage_enabled is true
          and part_row.used_mileage is not null
          and part_row.service_mileage is not null
          and part_row.used_mileage >= part_row.service_mileage
        )
      );

    select count(*)
    into v_vehicle_reminder_count
    from public.vehicle_archive vehicle_row
    where (v_is_platform_super or vehicle_row.tenant_id = v_tenant_id)
      and vehicle_row.audit_status = 'approved'
      and vehicle_row.start_use_date is not null
      and vehicle_row.service_years is not null
      and (
        vehicle_row.start_use_date + make_interval(years => vehicle_row.service_years)
      )::date <= v_today + 30;
  end if;

  return v_tms_metrics
    || v_vehicle_metrics
    || jsonb_build_object(
      'trend', v_trend,
      'status_counts', v_status_counts,
      'transit_orders', v_transit_orders,
      'recent_orders', v_recent_orders,
      'reminders', jsonb_build_array(
        jsonb_build_object(
          'key', 'insurance',
          'label', '保险到期',
          'count', v_insurance_count,
          'severity', 'danger'
        ),
        jsonb_build_object(
          'key', 'inspection',
          'label', '年检到期',
          'count', v_inspection_count,
          'severity', 'danger'
        ),
        jsonb_build_object(
          'key', 'maintenance',
          'label', '保养逾期',
          'count', v_maintenance_count,
          'severity', 'warning'
        ),
        jsonb_build_object(
          'key', 'part',
          'label', '配件寿命',
          'count', v_part_count,
          'severity', 'warning'
        ),
        jsonb_build_object(
          'key', 'vehicle',
          'label', '车辆临期',
          'count', v_vehicle_reminder_count,
          'severity', 'warning'
        )
      )
    );
end;
$function$;

comment on function public.get_dashboard_console(text, date)
  is 'Returns the tenant-scoped operations dashboard in one secure read request.';

revoke all on function public.get_dashboard_console(text, date) from public;
revoke all on function public.get_dashboard_console(text, date) from anon;
grant execute on function public.get_dashboard_console(text, date) to authenticated;
grant execute on function public.get_dashboard_console(text, date) to service_role;
;
