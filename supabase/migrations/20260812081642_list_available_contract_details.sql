create or replace function public.tms_list_available_contract_details(p_keyword text default null)
returns table (
  key text,
  contract_id uuid,
  contract_no text,
  contract_name text,
  effective_date date,
  expiry_date date,
  cargo_id uuid,
  cargo_description text,
  cargo_code text,
  contract_quantity numeric,
  unit text,
  transport_unit_price numeric,
  freight numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    contract.id::text || ':' || coalesce(detail.value ->> 'cargoId', detail.value ->> 'cargoCode', detail.ordinality::text),
    contract.id,
    contract.contract_no,
    contract.contract_name,
    contract.effective_date,
    contract.expiry_date,
    nullif(detail.value ->> 'cargoId', '')::uuid,
    detail.value ->> 'cargoDescription',
    detail.value ->> 'cargoCode',
    coalesce(nullif(detail.value ->> 'contractQuantity', '')::numeric, 0),
    detail.value ->> 'unit',
    coalesce(nullif(detail.value ->> 'transportUnitPrice', '')::numeric, 0),
    coalesce(nullif(detail.value ->> 'freight', '')::numeric, 0)
  from public.tms_contract as contract
  cross join lateral jsonb_array_elements(contract.transport_details) with ordinality as detail(value, ordinality)
  where contract.contract_status = 'approved'
    and contract.is_completed = false
    and (contract.effective_date is null or contract.effective_date <= current_date)
    and (contract.expiry_date is null or contract.expiry_date >= current_date)
    and nullif(btrim(detail.value ->> 'cargoDescription'), '') is not null
    and (
      nullif(btrim(p_keyword), '') is null
      or contract.contract_no ilike '%' || btrim(p_keyword) || '%'
      or contract.contract_name ilike '%' || btrim(p_keyword) || '%'
      or detail.value ->> 'cargoDescription' ilike '%' || btrim(p_keyword) || '%'
      or detail.value ->> 'cargoCode' ilike '%' || btrim(p_keyword) || '%'
    )
  order by contract.create_time desc, detail.ordinality;
$$;

revoke all on function public.tms_list_available_contract_details(text) from public;
grant execute on function public.tms_list_available_contract_details(text) to authenticated;;
