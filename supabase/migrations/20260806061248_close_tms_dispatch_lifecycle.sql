-- Keep the order as the dispatch aggregate and the driver waybill as the
-- authoritative transport-state aggregate. All dispatch mutations are atomic.

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'tms_order_order_status_check'
      and conrelid = 'public.tms_order'::regclass
  ) then
    alter table public.tms_order
      add constraint tms_order_order_status_check
      check (
        order_status in (
          'created',
          'pending_load',
          'pending_order',
          'pending_pickup',
          'transporting',
          'signed',
          'completed',
          'cancelled'
        )
      ) not valid;
  end if;
end
$$;
alter table public.tms_order
  validate constraint tms_order_order_status_check;
create or replace function public.trg_validate_tms_order_status_transition()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.order_status = old.order_status then
    return new;
  end if;

  if (old.order_status = 'created' and new.order_status in ('pending_load', 'cancelled'))
     or (old.order_status = 'pending_load' and new.order_status in ('pending_order', 'cancelled'))
     or (old.order_status = 'pending_order' and new.order_status in ('pending_load', 'pending_pickup', 'cancelled'))
     or (old.order_status = 'pending_pickup' and new.order_status in ('transporting', 'cancelled'))
     or (old.order_status = 'transporting' and new.order_status in ('signed', 'cancelled'))
     or (old.order_status = 'signed' and new.order_status in ('completed', 'cancelled')) then
    return new;
  end if;

  raise exception '订单状态不允许从 % 直接变更为 %', old.order_status, new.order_status;
end;
$$;
revoke execute on function public.trg_validate_tms_order_status_transition() from public, anon, authenticated;
drop trigger if exists tms_order_validate_status_transition on public.tms_order;
create trigger tms_order_validate_status_transition
before update of order_status on public.tms_order
for each row
execute function public.trg_validate_tms_order_status_transition();
create or replace function public.tms_dispatch_orders(
  p_order_ids uuid[],
  p_dispatch jsonb
)
returns setof public.tms_order
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_expected_count integer;
  v_locked_count integer;
  v_tenant_id uuid;
  v_vehicle_id uuid;
  v_driver_id uuid;
  v_departure timestamptz;
  v_arrival timestamptz;
  v_dispatch_by text;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再执行配载';
  end if;

  v_expected_count := coalesce(cardinality(array(select distinct unnest(p_order_ids))), 0);
  if v_expected_count = 0 then
    raise exception '请选择需要配载的订单';
  end if;

  begin
    v_vehicle_id := nullif(p_dispatch ->> 'dispatch_vehicle_id', '')::uuid;
    v_driver_id := nullif(p_dispatch ->> 'dispatch_driver_id', '')::uuid;
    v_departure := nullif(p_dispatch ->> 'planned_departure_time', '')::timestamptz;
    v_arrival := nullif(p_dispatch ->> 'planned_arrival_time', '')::timestamptz;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception '配载车辆、司机或计划时间格式不正确';
  end;

  if v_vehicle_id is null then
    raise exception '配载车辆不能为空';
  end if;
  if v_departure is null or v_arrival is null then
    raise exception '计划发车和到达时间不能为空';
  end if;
  if v_arrival < v_departure then
    raise exception '计划到达时间不能早于计划发车时间';
  end if;

  select count(*), (array_agg(o.tenant_id))[1]
    into v_locked_count, v_tenant_id
  from (
    select id
    from public.tms_order
    where id = any(p_order_ids)
    order by id
    for update
  ) locked
  join public.tms_order o on o.id = locked.id;

  if v_locked_count <> v_expected_count then
    raise exception '部分订单不存在或当前用户无权访问';
  end if;

  if exists (
    select 1
    from public.tms_order
    where id = any(p_order_ids)
      and (order_status <> 'pending_load' or dispatch_status <> 'pending')
  ) then
    raise exception '只有待配载订单可以执行配载';
  end if;

  if exists (
    select 1
    from public.tms_order o
    join public.tms_waybill w
      on w.order_id = o.id
      or (w.order_id is null and w.tenant_id = o.tenant_id and w.waybill_no = o.order_no)
    where o.id = any(p_order_ids)
  ) then
    raise exception '订单已存在关联司机运单，请刷新后重试';
  end if;

  if not exists (
    select 1
    from public.vehicle_archive v
    where v.id = v_vehicle_id
      and v.tenant_id = v_tenant_id
      and v.audit_status = 'approved'
  ) then
    raise exception '车辆不存在、未审核通过或不属于当前租户';
  end if;

  if v_driver_id is not null and not exists (
    select 1
    from public.tms_driver d
    where d.id = v_driver_id
      and d.tenant_id = v_tenant_id
      and d.enabled
  ) then
    raise exception '司机不存在、已停用或不属于当前租户';
  end if;

  select coalesce(u.user_email, (select auth.uid())::text)
    into v_dispatch_by
  from public.sys_user u
  where u.auth_user_id = (select auth.uid())
  limit 1;

  v_dispatch_by := coalesce(v_dispatch_by, (select auth.uid())::text);

  update public.tms_order
  set order_status = 'pending_order',
      dispatch_status = 'loaded',
      dispatch_vehicle_id = v_vehicle_id,
      dispatch_driver_id = v_driver_id,
      dispatch_plate_no = nullif(p_dispatch ->> 'dispatch_plate_no', ''),
      dispatch_vehicle_type = nullif(p_dispatch ->> 'dispatch_vehicle_type', ''),
      dispatch_vehicle_length = nullif(p_dispatch ->> 'dispatch_vehicle_length', ''),
      dispatch_driver_name = nullif(p_dispatch ->> 'dispatch_driver_name', ''),
      dispatch_driver_phone = nullif(p_dispatch ->> 'dispatch_driver_phone', ''),
      planned_departure_time = v_departure,
      planned_arrival_time = v_arrival,
      dispatch_remark = nullif(p_dispatch ->> 'dispatch_remark', ''),
      dispatched_at = now(),
      dispatch_by = v_dispatch_by
  where id = any(p_order_ids);

  insert into public.tms_waybill (
    order_id,
    tenant_id,
    waybill_no,
    status,
    driver_id,
    vehicle_id,
    shipper_address_id,
    receiver_address_id,
    origin_city,
    destination_city,
    shipper_name,
    shipper_phone,
    shipper_address,
    shipper_longitude,
    shipper_latitude,
    receiver_name,
    receiver_phone,
    receiver_address,
    receiver_longitude,
    receiver_latitude,
    planned_load_time,
    planned_unload_time,
    cargo_name,
    cargo_weight_ton,
    cargo_volume_m3,
    cargo_quantity,
    freight_amount,
    route_points,
    remark
  )
  select
    o.id,
    o.tenant_id,
    o.order_no,
    'pending',
    o.dispatch_driver_id,
    o.dispatch_vehicle_id,
    o.shipping_address_id,
    o.receiving_address_id,
    o.origin_station,
    o.destination_station,
    o.shipping_contact_name,
    o.shipping_contact_phone,
    o.shipping_address_detail,
    o.shipping_longitude,
    o.shipping_latitude,
    o.receiving_contact_name,
    o.receiving_contact_phone,
    o.receiving_address_detail,
    o.receiving_longitude,
    o.receiving_latitude,
    o.planned_departure_time,
    o.planned_arrival_time,
    coalesce(
      o.cargo_items -> 0 ->> 'cargo_name',
      o.cargo_items -> 0 ->> 'cargoName',
      o.cargo_no,
      o.order_no
    ),
    round(o.cargo_weight_total / 1000.0, 3),
    o.cargo_volume_total,
    o.cargo_quantity_total::text,
    o.total_fee,
    (case
      when o.shipping_longitude is not null and o.shipping_latitude is not null
      then jsonb_build_array(jsonb_build_object(
        'type', 'shipper',
        'name', o.shipping_contact_name,
        'address', o.shipping_address_detail,
        'longitude', o.shipping_longitude,
        'latitude', o.shipping_latitude,
        'lng', o.shipping_longitude,
        'lat', o.shipping_latitude
      ))
      else '[]'::jsonb
    end)
    ||
    (case
      when o.receiving_longitude is not null and o.receiving_latitude is not null
      then jsonb_build_array(jsonb_build_object(
        'type', 'receiver',
        'name', o.receiving_contact_name,
        'address', o.receiving_address_detail,
        'longitude', o.receiving_longitude,
        'latitude', o.receiving_latitude,
        'lng', o.receiving_longitude,
        'lat', o.receiving_latitude
      ))
      else '[]'::jsonb
    end),
    coalesce(o.dispatch_remark, o.order_remark)
  from public.tms_order o
  where o.id = any(p_order_ids);

  return query
  select o.*
  from public.tms_order o
  where o.id = any(p_order_ids)
  order by o.id;
end;
$$;
revoke execute on function public.tms_dispatch_orders(uuid[], jsonb) from public, anon;
grant execute on function public.tms_dispatch_orders(uuid[], jsonb) to authenticated, service_role;
create or replace function public.tms_revoke_order_dispatch(p_order_ids uuid[])
returns setof public.tms_order
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_expected_count integer;
  v_locked_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再撤销配载';
  end if;

  v_expected_count := coalesce(cardinality(array(select distinct unnest(p_order_ids))), 0);
  if v_expected_count = 0 then
    raise exception '请选择需要撤销配载的订单';
  end if;

  select count(*)
    into v_locked_count
  from (
    select id
    from public.tms_order
    where id = any(p_order_ids)
    order by id
    for update
  ) locked;

  if v_locked_count <> v_expected_count then
    raise exception '部分订单不存在或当前用户无权访问';
  end if;

  if exists (
    select 1
    from public.tms_order o
    left join public.tms_waybill w
      on w.order_id = o.id
      or (w.order_id is null and w.tenant_id = o.tenant_id and w.waybill_no = o.order_no)
    where o.id = any(p_order_ids)
      and (
        o.order_status <> 'pending_order'
        or o.dispatch_status <> 'loaded'
        or w.id is null
        or w.status <> 'pending'
      )
  ) then
    raise exception '司机接单或开始履约后不能撤销配载';
  end if;

  delete from public.tms_waybill w
  using public.tms_order o
  where o.id = any(p_order_ids)
    and (
      w.order_id = o.id
      or (w.order_id is null and w.tenant_id = o.tenant_id and w.waybill_no = o.order_no)
    );

  update public.tms_order
  set order_status = 'pending_load',
      dispatch_status = 'pending',
      dispatch_vehicle_id = null,
      dispatch_driver_id = null,
      dispatch_plate_no = null,
      dispatch_vehicle_type = null,
      dispatch_vehicle_length = null,
      dispatch_driver_name = null,
      dispatch_driver_phone = null,
      planned_departure_time = null,
      planned_arrival_time = null,
      dispatch_remark = null,
      dispatched_at = null,
      dispatch_by = null
  where id = any(p_order_ids);

  return query
  select o.*
  from public.tms_order o
  where o.id = any(p_order_ids)
  order by o.id;
end;
$$;
revoke execute on function public.tms_revoke_order_dispatch(uuid[]) from public, anon;
grant execute on function public.tms_revoke_order_dispatch(uuid[]) to authenticated, service_role;
create or replace function public.tms_delete_order_with_waybill(p_order_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_order public.tms_order%rowtype;
begin
  select *
    into v_order
  from public.tms_order
  where id = p_order_id
  for update;

  if not found then
    raise exception '订单不存在或当前用户无权访问';
  end if;

  if v_order.order_status <> 'pending_load' or v_order.dispatch_status <> 'pending' then
    raise exception '只有尚未配载的订单可以永久删除；已履约订单请保留审计记录';
  end if;

  if exists (
    select 1
    from public.tms_waybill w
    where (
      w.order_id = v_order.id
      or (w.order_id is null and w.tenant_id = v_order.tenant_id and w.waybill_no = v_order.order_no)
    )
      and w.status <> 'pending'
  ) then
    raise exception '关联运单已开始履约，不能永久删除订单';
  end if;

  delete from public.tms_waybill w
  where w.order_id = v_order.id
     or (w.order_id is null and w.tenant_id = v_order.tenant_id and w.waybill_no = v_order.order_no);

  delete from public.tms_order where id = v_order.id;
end;
$$;
revoke execute on function public.tms_delete_order_with_waybill(uuid) from public, anon;
grant execute on function public.tms_delete_order_with_waybill(uuid) to authenticated, service_role;
create or replace function public.tms_delete_orders_with_waybills(p_order_ids uuid[])
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_order_id uuid;
begin
  for v_order_id in
    select distinct id
    from unnest(p_order_ids) as requested(id)
    order by id
  loop
    perform public.tms_delete_order_with_waybill(v_order_id);
  end loop;
end;
$$;
revoke execute on function public.tms_delete_orders_with_waybills(uuid[]) from public, anon;
grant execute on function public.tms_delete_orders_with_waybills(uuid[]) to authenticated, service_role;
create or replace function public.tms_cancel_orders_with_waybills(p_order_ids uuid[])
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_order_id uuid;
begin
  for v_order_id in
    select distinct id
    from unnest(p_order_ids) as requested(id)
    order by id
  loop
    perform public.tms_cancel_order_with_waybill(v_order_id);
  end loop;
end;
$$;
revoke execute on function public.tms_cancel_orders_with_waybills(uuid[]) from public, anon;
grant execute on function public.tms_cancel_orders_with_waybills(uuid[]) to authenticated, service_role;
