create or replace function app_private.current_user_driver_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select d.id
  from public.sys_user u
  join public.tms_driver d
    on d.tenant_id = u.tenant_id
   and d.phone = u.user_phone
   and d.enabled
  where u.auth_user_id = (select auth.uid())
    and u.status = '1'
  order by d.create_time desc
  limit 1;
$$;
create or replace function app_private.can_manage_tms()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.sys_user u
    where u.auth_user_id = (select auth.uid())
      and u.status = '1'
      and (
        coalesce(u.user_roles, '{}'::text[])
          && array['R_SUPER', 'R_ADMIN', 'YQ_ADMIN']::text[]
        or (
          'R_REGISTER' = any(coalesce(u.user_roles, '{}'::text[]))
          and (select app_private.current_user_driver_id()) is null
        )
      )
  );
$$;
create or replace function app_private.can_access_assigned_waybill(p_waybill_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.tms_waybill w
    where w.id = p_waybill_id
      and w.tenant_id = (select app_private.current_user_tenant_id())
      and w.driver_id = (select app_private.current_user_driver_id())
  );
$$;
revoke execute on function app_private.current_user_driver_id() from public, anon;
revoke execute on function app_private.can_manage_tms() from public, anon;
revoke execute on function app_private.can_access_assigned_waybill(uuid) from public, anon;
grant execute on function app_private.current_user_driver_id() to authenticated, service_role;
grant execute on function app_private.can_manage_tms() to authenticated, service_role;
grant execute on function app_private.can_access_assigned_waybill(uuid) to authenticated, service_role;
drop policy if exists tenant_insert on public.tms_order;
create policy tenant_insert on public.tms_order
for insert to authenticated
with check (
  (select app_private.can_manage_tms())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (
    shipping_customer_id is null
    or exists (
      select 1 from public.tms_customer customer
      where customer.id = shipping_customer_id
        and (
          (select app_private.is_platform_super())
          or customer.tenant_id = (select app_private.current_user_tenant_id())
        )
    )
  )
  and (
    receiving_customer_id is null
    or exists (
      select 1 from public.tms_customer customer
      where customer.id = receiving_customer_id
        and (
          (select app_private.is_platform_super())
          or customer.tenant_id = (select app_private.current_user_tenant_id())
        )
    )
  )
);
drop policy if exists tenant_update on public.tms_order;
create policy tenant_update on public.tms_order
for update to authenticated
using (
  (select app_private.can_manage_tms())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
)
with check (
  (select app_private.can_manage_tms())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
  and (
    shipping_customer_id is null
    or exists (
      select 1 from public.tms_customer customer
      where customer.id = shipping_customer_id
        and (
          (select app_private.is_platform_super())
          or customer.tenant_id = (select app_private.current_user_tenant_id())
        )
    )
  )
  and (
    receiving_customer_id is null
    or exists (
      select 1 from public.tms_customer customer
      where customer.id = receiving_customer_id
        and (
          (select app_private.is_platform_super())
          or customer.tenant_id = (select app_private.current_user_tenant_id())
        )
    )
  )
);
drop policy if exists tenant_delete on public.tms_order;
create policy tenant_delete on public.tms_order
for delete to authenticated
using (
  (select app_private.can_manage_tms())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists tms_waybill_tenant_insert on public.tms_waybill;
create policy tms_waybill_tenant_insert on public.tms_waybill
for insert to authenticated
with check (
  (select app_private.can_manage_tms())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists tms_waybill_tenant_update on public.tms_waybill;
create policy tms_waybill_tenant_update on public.tms_waybill
for update to authenticated
using (
  (
    (select app_private.can_manage_tms())
    or driver_id = (select app_private.current_user_driver_id())
  )
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
)
with check (
  (
    (select app_private.can_manage_tms())
    or driver_id = (select app_private.current_user_driver_id())
  )
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists tms_waybill_tenant_delete on public.tms_waybill;
create policy tms_waybill_tenant_delete on public.tms_waybill
for delete to authenticated
using (
  (select app_private.can_manage_tms())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
create or replace function public.trg_guard_tms_waybill_driver_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select app_private.can_manage_tms()) then
    return new;
  end if;

  if old.driver_id is distinct from (select app_private.current_user_driver_id()) then
    raise exception '司机只能维护分配给自己的运单';
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.order_id is distinct from old.order_id
     or new.waybill_no is distinct from old.waybill_no
     or new.carrier_id is distinct from old.carrier_id
     or new.driver_id is distinct from old.driver_id
     or new.vehicle_id is distinct from old.vehicle_id
     or new.cargo_id is distinct from old.cargo_id
     or new.shipper_address_id is distinct from old.shipper_address_id
     or new.receiver_address_id is distinct from old.receiver_address_id
     or new.origin_city is distinct from old.origin_city
     or new.destination_city is distinct from old.destination_city
     or new.shipper_name is distinct from old.shipper_name
     or new.shipper_phone is distinct from old.shipper_phone
     or new.shipper_address is distinct from old.shipper_address
     or new.receiver_name is distinct from old.receiver_name
     or new.receiver_phone is distinct from old.receiver_phone
     or new.receiver_address is distinct from old.receiver_address
     or new.planned_load_time is distinct from old.planned_load_time
     or new.planned_unload_time is distinct from old.planned_unload_time
     or new.cargo_name is distinct from old.cargo_name
     or new.cargo_type is distinct from old.cargo_type
     or new.cargo_weight_ton is distinct from old.cargo_weight_ton
     or new.cargo_volume_m3 is distinct from old.cargo_volume_m3
     or new.cargo_quantity is distinct from old.cargo_quantity
     or new.freight_amount is distinct from old.freight_amount then
    raise exception '司机无权修改运单主数据或计费字段';
  end if;

  return new;
end;
$$;
revoke execute on function public.trg_guard_tms_waybill_driver_update()
  from public, anon, authenticated, service_role;
drop trigger if exists tms_waybill_guard_driver_update on public.tms_waybill;
create trigger tms_waybill_guard_driver_update
before update on public.tms_waybill
for each row execute function public.trg_guard_tms_waybill_driver_update();
create or replace function public.trg_sync_order_terminal_status_from_waybill()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order_status text;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then
    return new;
  end if;

  v_order_status := case new.status
    when 'pending' then 'pending_order'
    when 'accepted' then 'pending_pickup'
    when 'loading' then 'pending_pickup'
    when 'transporting' then 'transporting'
    when 'unloading' then 'transporting'
    when 'signed' then 'signed'
    when 'completed' then 'completed'
    when 'cancelled' then 'cancelled'
  end;

  if v_order_status is null then
    return new;
  end if;

  update public.tms_order
  set order_status = v_order_status
  where (new.order_id is not null and id = new.order_id)
     or (
       new.order_id is null
       and tenant_id = new.tenant_id
       and order_no = new.waybill_no
     );

  return new;
end;
$$;
revoke execute on function public.trg_sync_order_terminal_status_from_waybill()
  from public, anon, authenticated, service_role;
drop policy if exists tms_waybill_event_tenant_insert on public.tms_waybill_event;
create policy tms_waybill_event_tenant_insert on public.tms_waybill_event
for insert to authenticated
with check (
  (
    (select app_private.can_manage_tms())
    or (select app_private.can_access_assigned_waybill(waybill_id))
  )
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists tms_waybill_event_tenant_update on public.tms_waybill_event;
create policy tms_waybill_event_tenant_update on public.tms_waybill_event
for update to authenticated
using (
  (
    (select app_private.can_manage_tms())
    or (select app_private.can_access_assigned_waybill(waybill_id))
  )
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
)
with check (
  (
    (select app_private.can_manage_tms())
    or (select app_private.can_access_assigned_waybill(waybill_id))
  )
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists tms_waybill_event_tenant_delete on public.tms_waybill_event;
create policy tms_waybill_event_tenant_delete on public.tms_waybill_event
for delete to authenticated
using (
  (select app_private.can_manage_tms())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists tms_waybill_proof_tenant_insert on public.tms_waybill_proof;
create policy tms_waybill_proof_tenant_insert on public.tms_waybill_proof
for insert to authenticated
with check (
  (
    (select app_private.can_manage_tms())
    or (select app_private.can_access_assigned_waybill(waybill_id))
  )
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists tms_waybill_proof_tenant_update on public.tms_waybill_proof;
create policy tms_waybill_proof_tenant_update on public.tms_waybill_proof
for update to authenticated
using (
  (
    (select app_private.can_manage_tms())
    or (select app_private.can_access_assigned_waybill(waybill_id))
  )
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
)
with check (
  (
    (select app_private.can_manage_tms())
    or (select app_private.can_access_assigned_waybill(waybill_id))
  )
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
drop policy if exists tms_waybill_proof_tenant_delete on public.tms_waybill_proof;
create policy tms_waybill_proof_tenant_delete on public.tms_waybill_proof
for delete to authenticated
using (
  (select app_private.can_manage_tms())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
