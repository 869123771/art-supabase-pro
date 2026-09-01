alter table public.tms_contract
  drop constraint tms_contract_party_check;

alter table public.tms_contract
  add constraint tms_contract_party_check
  check (
    (
      business_contract_type = 'carrier'
      and customer_id is not null
      and carrier_id is null
    )
    or
    (
      business_contract_type = 'customer'
      and carrier_id is not null
      and customer_id is null
    )
  );

comment on constraint tms_contract_party_check on public.tms_contract is
  'business_contract_type identifies the initiating side; the selected contract party must be the opposite side.';;
