-- Customer and address option RPCs are shared by several TMS/FMS workflows. Keep
-- them available to those workflows, but do not expose tenant master data to an
-- authenticated account that owns none of the consuming business menus.
create or replace function app_private.can_access_tms_customer_reference_data()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (
      select 1
      from unnest(array[
        'TmsCustomer',
        'TmsCustomerAddress',
        'TmsContract',
        'TmsCustomerPrice',
        'TmsFavoriteRoute',
        'TmsOrderOpen',
        'FinanceInvoiceManagement',
        'FinanceCashTransaction',
        'FinanceCustomerSettlement'
      ]::text[]) as allowed_menu(menu_name)
      where app_private.can_access_business_menu(allowed_menu.menu_name)
    );
$$;

revoke all on function app_private.can_access_tms_customer_reference_data()
from public, anon, authenticated;
grant execute on function app_private.can_access_tms_customer_reference_data()
to service_role;

create or replace function public.tms_list_customer_options_secure(
  p_exclude_id uuid default null,
  p_include_disabled boolean default false,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
begin
  if not app_private.can_access_tms_customer_reference_data()
     or v_current_tenant_id is null then
    raise exception 'Missing customer reference data permission' using errcode = '42501';
  end if;

  v_target_tenant_id := case
    when app_private.is_platform_super() then coalesce(p_tenant_id, v_current_tenant_id)
    else v_current_tenant_id
  end;

  return coalesce((
    select jsonb_agg(
      app_private.tms_customer_option_to_secure_json(customer_row)
      order by customer_row.customer_name, customer_row.id
    )
    from (
      select customer_record.*
      from public.tms_customer customer_record
      where customer_record.tenant_id = v_target_tenant_id
        and (p_include_disabled or customer_record.enabled)
        and (p_exclude_id is null or customer_record.id <> p_exclude_id)
      order by customer_record.customer_name, customer_record.id
      limit 1000
    ) customer_row
  ), '[]'::jsonb);
end;
$$;

create or replace function public.tms_list_customer_selector_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_keyword text default null,
  p_address_type text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_customer_access jsonb;
  v_can_search_phone boolean;
  v_can_search_address boolean;
  v_limit integer := least(
    200,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_result jsonb;
begin
  if not app_private.can_access_tms_customer_reference_data()
     or v_tenant_id is null then
    raise exception 'Missing customer reference data permission' using errcode = '42501';
  end if;
  if p_address_type is not null and p_address_type not in ('shipping', 'receiving') then
    raise exception 'Invalid customer address type';
  end if;

  v_customer_access := app_private.field_access_map('tms.customer', null);
  v_can_search_phone := coalesce(v_customer_access->>'contactPhone', 'hidden') in ('read', 'edit');
  v_can_search_address := coalesce(v_customer_access->>'addressDetail', 'hidden') in ('read', 'edit');

  with filtered as materialized (
    select customer_row as customer_record
    from public.tms_customer customer_row
    where customer_row.tenant_id = v_tenant_id
      and customer_row.enabled
      and (
        nullif(btrim(p_keyword), '') is null
        or customer_row.customer_name ilike '%' || btrim(p_keyword) || '%'
        or customer_row.customer_code ilike '%' || btrim(p_keyword) || '%'
        or customer_row.contact_name ilike '%' || btrim(p_keyword) || '%'
        or (v_can_search_phone and customer_row.contact_phone ilike '%' || btrim(p_keyword) || '%')
        or (v_can_search_address and customer_row.address_detail ilike '%' || btrim(p_keyword) || '%')
      )
  ), paged as (
    select filtered.customer_record
    from filtered
    order by (filtered.customer_record).create_time desc, (filtered.customer_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  ), shaped as (
    select
      app_private.tms_customer_option_to_secure_json(paged.customer_record) as customer_json,
      address_pick.address_record
    from paged
    left join lateral (
      select address_row as address_record
      from public.tms_customer_address address_row
      where p_address_type is not null
        and address_row.tenant_id = (paged.customer_record).tenant_id
        and address_row.customer_id = (paged.customer_record).id
        and address_row.address_type = p_address_type
      order by address_row.is_default desc, address_row.update_time desc nulls last,
               address_row.create_time desc, address_row.id
      limit 1
    ) address_pick on true
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        case when shaped.address_record is null then shaped.customer_json
        else (
          shaped.customer_json
          || jsonb_build_object(
            'address_id', (shaped.address_record).id,
            'address_type', (shaped.address_record).address_type
          )
          || (
            app_private.tms_customer_address_to_secure_json(shaped.address_record, null)
            - 'id' - 'customer_id' - 'customer' - 'field_access' - 'is_record_owner'
          )
          || jsonb_build_object(
            'field_access', app_private.field_access_map(
              'tms.customer_address',
              (shaped.address_record).created_by_user_id
            ),
            'is_record_owner',
              (shaped.address_record).created_by_user_id = app_private.current_app_user_id()
          )
        ) end
      ) from shaped
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.tms_get_customer_default_address_secure(
  p_customer_id uuid,
  p_address_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_address public.tms_customer_address%rowtype;
begin
  if not app_private.can_access_tms_customer_reference_data()
     or app_private.current_user_tenant_id() is null then
    raise exception 'Missing customer reference data permission' using errcode = '42501';
  end if;
  if p_address_type not in ('shipping', 'receiving') then
    raise exception 'Invalid customer address type';
  end if;

  select * into v_address
  from public.tms_customer_address address_row
  where address_row.tenant_id = app_private.current_user_tenant_id()
    and address_row.customer_id = p_customer_id
    and address_row.address_type = p_address_type
  order by address_row.is_default desc, address_row.update_time desc nulls last,
           address_row.create_time desc, address_row.id
  limit 1;

  if not found then return null; end if;
  return app_private.tms_customer_address_to_secure_json(v_address, null);
end;
$$;

create or replace function public.tms_list_customer_address_options_secure(
  p_customer_id uuid default null,
  p_tenant_id uuid default null,
  p_address_type text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_target_tenant_id uuid;
begin
  if not app_private.can_access_tms_customer_reference_data()
     or v_current_tenant_id is null then
    raise exception 'Missing customer reference data permission' using errcode = '42501';
  end if;
  if p_address_type is not null and p_address_type not in ('shipping', 'receiving') then
    raise exception 'Invalid customer address type';
  end if;

  v_target_tenant_id := case
    when app_private.is_platform_super() then coalesce(p_tenant_id, v_current_tenant_id)
    else v_current_tenant_id
  end;

  return coalesce((
    select jsonb_agg(
      app_private.tms_customer_address_to_secure_json(address_row, null)
      order by address_row.is_default desc, address_row.update_time desc nulls last,
               address_row.create_time desc, address_row.id
    )
    from public.tms_customer_address address_row
    where address_row.tenant_id = v_target_tenant_id
      and (p_customer_id is null or address_row.customer_id = p_customer_id)
      and (p_address_type is null or address_row.address_type = p_address_type)
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.tms_list_customer_options_secure(uuid, boolean, uuid)
from public, anon;
revoke all on function public.tms_list_customer_selector_secure(integer, integer, text, text)
from public, anon;
revoke all on function public.tms_get_customer_default_address_secure(uuid, text)
from public, anon;
revoke all on function public.tms_list_customer_address_options_secure(uuid, uuid, text)
from public, anon;

grant execute on function public.tms_list_customer_options_secure(uuid, boolean, uuid)
to authenticated, service_role;
grant execute on function public.tms_list_customer_selector_secure(integer, integer, text, text)
to authenticated, service_role;
grant execute on function public.tms_get_customer_default_address_secure(uuid, text)
to authenticated, service_role;
grant execute on function public.tms_list_customer_address_options_secure(uuid, uuid, text)
to authenticated, service_role;

;
