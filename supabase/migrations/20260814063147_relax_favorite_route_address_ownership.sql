create or replace function app_private.validate_tms_favorite_route_refs()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'app_private'
as $function$
declare
  customer_tenant_id uuid;
  origin_record record;
  destination_record record;
begin
  select customer.tenant_id
    into customer_tenant_id
  from public.tms_customer customer
  where customer.id = new.customer_id;

  select address.tenant_id, address.address_type
    into origin_record
  from public.tms_customer_address address
  where address.id = new.origin_address_id;

  select address.tenant_id, address.address_type
    into destination_record
  from public.tms_customer_address address
  where address.id = new.destination_address_id;

  if customer_tenant_id is null
    or customer_tenant_id <> new.tenant_id
    or origin_record.tenant_id is null
    or origin_record.tenant_id <> new.tenant_id
    or origin_record.address_type <> 'shipping'
    or destination_record.tenant_id is null
    or destination_record.tenant_id <> new.tenant_id
    or destination_record.address_type <> 'receiving'
  then
    raise exception 'Favorite route customer and addresses must belong to the same tenant and use shipping/receiving endpoints.'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

comment on function app_private.validate_tms_favorite_route_refs() is
  'Validates favorite-route tenant ownership and shipping/receiving endpoint types; endpoints may be customer-owned or shared addresses.';;
