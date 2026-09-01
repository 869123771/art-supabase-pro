create or replace function public.tms_accept_waybill(p_order_id uuid)
returns void
language plpgsql
set search_path to 'public'
as $$
declare
  v_order public.tms_order%rowtype;
  v_waybill public.tms_waybill%rowtype;
  v_accepted_at timestamptz;
begin
  select *
  into v_order
  from public.tms_order
  where id = p_order_id;

  if not found then
    raise exception '订单不存在或当前用户无权访问';
  end if;

  select *
  into v_waybill
  from public.tms_waybill
  where order_id = v_order.id
     or (
       order_id is null
       and tenant_id = v_order.tenant_id
       and waybill_no = v_order.order_no
     )
  for update;

  if not found then
    raise exception '未找到关联的司机运单';
  end if;

  if v_waybill.status <> 'pending' then
    raise exception '只有待接单运单可以确认接单';
  end if;

  v_accepted_at := coalesce(v_waybill.accepted_at, now());

  update public.tms_waybill
  set status = 'accepted',
      accepted_at = v_accepted_at
  where id = v_waybill.id;

  insert into public.tms_waybill_event (
    tenant_id,
    waybill_id,
    event_type,
    event_time,
    operator_name,
    location_text,
    payload
  )
  values (
    v_waybill.tenant_id,
    v_waybill.id,
    'accepted',
    v_accepted_at,
    'Web端确认接单',
    concat_ws(' - ', v_waybill.origin_city, v_waybill.destination_city),
    jsonb_build_object('action', 'accept', 'source', 'web')
  );
end;
$$;
revoke all on function public.tms_accept_waybill(uuid) from public, anon;
grant execute on function public.tms_accept_waybill(uuid) to authenticated, service_role;
