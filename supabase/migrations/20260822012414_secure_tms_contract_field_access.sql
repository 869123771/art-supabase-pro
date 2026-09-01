-- Make TMS contract field protection reproducible and tenant scoped.
-- Existing menu and button permission definitions are intentionally unchanged.

alter table public.tms_contract
  add column if not exists created_by_user_id uuid;

update public.tms_contract contract_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = contract_row.tenant_id
    and (
      user_row.auth_user_id::text = contract_row.create_by
      or lower(user_row.user_email) = lower(contract_row.create_by)
    )
  order by
    case when user_row.auth_user_id::text = contract_row.create_by then 0 else 1 end,
    user_row.create_time,
    user_row.id
  limit 1
)
where contract_row.created_by_user_id is null;

do $$
begin
  if exists (
    select 1 from public.tms_contract where created_by_user_id is null
  ) then
    raise exception 'Cannot secure TMS contracts: existing rows have no resolvable creator';
  end if;
end;
$$;

alter table public.tms_contract
  alter column created_by_user_id set not null;

create index if not exists idx_tms_contract_creator_tenant_fk
  on public.tms_contract(created_by_user_id, tenant_id);

create index if not exists idx_tms_contract_tenant_creator
  on public.tms_contract(tenant_id, created_by_user_id, create_time desc);

alter table public.tms_contract
  drop constraint if exists tms_contract_creator_tenant_fkey;
alter table public.tms_contract
  add constraint tms_contract_creator_tenant_fkey
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on update restrict
  on delete restrict;

create or replace function app_private.set_tms_contract_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    if (select auth.uid()) is not null then
      if v_current_user_id is null then
        raise exception 'Authenticated application user not found' using errcode = '42501';
      end if;
      new.created_by_user_id := v_current_user_id;
    elsif new.created_by_user_id is null then
      raise exception 'Contract creator identity is required';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Contract creator identity is immutable' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists tms_contract_creator_identity on public.tms_contract;
create trigger tms_contract_creator_identity
before insert or update of created_by_user_id on public.tms_contract
for each row execute function app_private.set_tms_contract_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_tms_contract_recovery;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_tms_contract_recovery(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.contract', '运输合同', 'TmsContract',
    'created_by_user_id', '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sensitive, enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'contractAmount', '合同金额',
      'hidden', 'amount', true, true, true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'transportUnitPrice', '运输单价',
      'hidden', 'amount', true, true, true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'roadConsumptionRate', '路耗标准',
      'hidden', 'amount', true, true, true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'lossDeductionPrice', '亏扣价',
      'hidden', 'amount', true, true, true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'transportDetailsPricing', '明细单价与运费',
      'hidden', 'amount', true, true, true, 50, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'partyContactPhone', '相对方联系电话',
      'hidden', 'phone', false, true, true, 60, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'attachments', '合同附件',
      'hidden', 'none', true, true, true, 70, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sensitive = true,
        enabled = true,
        sort = excluded.sort,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

-- Preserve the pre-rollout behavior for roles that can already open the page.
insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id,
  role_menu.role_id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'TmsContract'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'tms.contract'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.assert_tms_contract_payload_keys(p_payload jsonb)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_invalid_keys text[];
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Contract payload must be a JSON object';
  end if;

  select array_agg(payload_key order by payload_key)
    into v_invalid_keys
  from jsonb_object_keys(p_payload) payload_key
  where payload_key <> all(array[
    'contract_no', 'contract_name', 'paper_contract_no', 'mnemonic_code',
    'contract_category', 'transport_mode', 'business_contract_type', 'customer_id',
    'carrier_id', 'contact_name', 'waybill_no', 'customer_signatory', 'billing_method',
    'contract_amount', 'transport_unit_price', 'road_consumption_rate',
    'loss_deduction_price', 'sign_time', 'effective_date', 'expiry_date',
    'is_completed', 'agreed_transport_quantity', 'transport_route', 'shipper_name',
    'payer_name', 'consignee_name', 'special_transport_requirements',
    'other_deduction_terms', 'handler', 'contract_description', 'transport_details',
    'attachments'
  ]::text[]);

  if v_invalid_keys is not null then
    raise exception 'Contract payload contains protected or unknown fields: %',
      array_to_string(v_invalid_keys, ', ');
  end if;
end;
$$;

create or replace function app_private.assert_tms_contract_reference_scope(
  p_tenant_id uuid,
  p_customer_id uuid,
  p_carrier_id uuid,
  p_transport_details jsonb
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_customer_id is not null and not exists (
    select 1
    from public.tms_customer customer_row
    where customer_row.id = p_customer_id
      and customer_row.tenant_id = p_tenant_id
  ) then
    raise exception 'Contract customer is outside the current tenant';
  end if;

  if p_carrier_id is not null and not exists (
    select 1
    from public.tms_carrier carrier_row
    where carrier_row.id = p_carrier_id
      and carrier_row.tenant_id = p_tenant_id
  ) then
    raise exception 'Contract carrier is outside the current tenant';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_transport_details, '[]'::jsonb)) detail(item)
    where nullif(detail.item->>'cargo_id', '') is not null
      and not exists (
        select 1
        from public.tms_cargo cargo_row
        where cargo_row.id = (detail.item->>'cargo_id')::uuid
          and cargo_row.tenant_id = p_tenant_id
      )
  ) then
    raise exception 'Contract cargo detail is outside the current tenant';
  end if;
end;
$$;

create or replace function app_private.tms_contract_transport_pricing(p_details jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'transport_unit_price', detail.item->'transport_unit_price',
        'freight', detail.item->'freight'
      )
      order by detail.ordinality
    ),
    '[]'::jsonb
  )
  from jsonb_array_elements(coalesce(p_details, '[]'::jsonb))
    with ordinality detail(item, ordinality);
$$;

create or replace function app_private.tms_contract_to_secure_json(
  p_contract public.tms_contract,
  p_base_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(
    p_base_access,
    app_private.field_access_map('tms.contract', null)
  );
  v_owner_overlay jsonb := '{}'::jsonb;
  v_data jsonb;
  v_level text;
  v_transport_details jsonb;
  v_customer jsonb;
  v_carrier jsonb;
  v_phone text;
begin
  if p_contract.created_by_user_id = app_private.current_app_user_id()
     and not app_private.is_platform_super() then
    select coalesce(jsonb_object_agg(field_row.field_key, 'edit'), '{}'::jsonb)
      into v_owner_overlay
    from public.sys_permission_resource resource_row
    join public.sys_permission_field field_row
      on field_row.resource_id = resource_row.id
     and field_row.tenant_id = resource_row.tenant_id
    where resource_row.tenant_id = app_private.current_user_tenant_id()
      and resource_row.resource_key = 'tms.contract'
      and resource_row.enabled is true
      and field_row.enabled is true
      and field_row.sensitive is true
      and field_row.owner_override_enabled is true;

    v_access := v_access || v_owner_overlay;
  end if;

  v_data := to_jsonb(p_contract) - 'tenant_id' - 'created_by_user_id';

  v_level := coalesce(v_access->>'contractAmount', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'contract_amount';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{contract_amount}', to_jsonb('***'::text));
  end if;

  v_level := coalesce(v_access->>'transportUnitPrice', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'transport_unit_price';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{transport_unit_price}', to_jsonb('***'::text));
  end if;

  v_level := coalesce(v_access->>'roadConsumptionRate', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'road_consumption_rate';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{road_consumption_rate}', to_jsonb('***'::text));
  end if;

  v_level := coalesce(v_access->>'lossDeductionPrice', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'loss_deduction_price';
  elsif v_level = 'masked' then
    v_data := jsonb_set(v_data, '{loss_deduction_price}', to_jsonb('***'::text));
  end if;

  v_level := coalesce(v_access->>'transportDetailsPricing', 'hidden');
  select coalesce(
    jsonb_agg(
      case
        when v_level = 'hidden' then detail.item - 'transport_unit_price' - 'freight'
        when v_level = 'masked' then
          jsonb_set(
            jsonb_set(detail.item, '{transport_unit_price}', to_jsonb('***'::text)),
            '{freight}',
            to_jsonb('***'::text)
          )
        else detail.item
      end
      order by detail.ordinality
    ),
    '[]'::jsonb
  )
    into v_transport_details
  from jsonb_array_elements(coalesce(p_contract.transport_details, '[]'::jsonb))
    with ordinality detail(item, ordinality);
  v_data := jsonb_set(v_data, '{transport_details}', v_transport_details);

  v_level := coalesce(v_access->>'attachments', 'hidden');
  if v_level in ('hidden', 'masked') then
    v_data := v_data - 'attachments';
  end if;

  -- A referenced party phone belongs to customer/carrier master data. It deliberately
  -- does not inherit the contract-owner override; the explicit field rule still applies.
  v_level := coalesce(v_access->>'partyContactPhone', 'hidden');

  if p_contract.customer_id is not null then
    select
      jsonb_build_object(
        'id', customer_row.id,
        'customer_code', customer_row.customer_code,
        'customer_name', customer_row.customer_name,
        'contact_name', customer_row.contact_name
      ),
      customer_row.contact_phone
      into v_customer, v_phone
    from public.tms_customer customer_row
    where customer_row.id = p_contract.customer_id
      and customer_row.tenant_id = p_contract.tenant_id;

    if v_customer is not null and v_level in ('read', 'edit') then
      v_customer := v_customer || jsonb_build_object('contact_phone', v_phone);
      v_data := jsonb_set(
        v_data,
        '{party_contact_phone}',
        coalesce(to_jsonb(v_phone), 'null'::jsonb),
        true
      );
    elsif v_customer is not null and v_level = 'masked' then
      v_customer := v_customer || jsonb_build_object(
        'contact_phone',
        app_private.mask_permission_value(v_phone, 'phone')
      );
      v_data := jsonb_set(
        v_data,
        '{party_contact_phone}',
        coalesce(
          to_jsonb(app_private.mask_permission_value(v_phone, 'phone')),
          'null'::jsonb
        ),
        true
      );
    end if;
  end if;

  v_phone := null;
  if p_contract.carrier_id is not null then
    select
      jsonb_build_object(
        'id', carrier_row.id,
        'carrier_code', carrier_row.carrier_code,
        'company_name', carrier_row.company_name,
        'contact_name', carrier_row.contact_name
      ),
      carrier_row.contact_phone
      into v_carrier, v_phone
    from public.tms_carrier carrier_row
    where carrier_row.id = p_contract.carrier_id
      and carrier_row.tenant_id = p_contract.tenant_id;

    if v_carrier is not null and v_level in ('read', 'edit') then
      v_carrier := v_carrier || jsonb_build_object('contact_phone', v_phone);
      v_data := jsonb_set(
        v_data,
        '{party_contact_phone}',
        coalesce(to_jsonb(v_phone), 'null'::jsonb),
        true
      );
    elsif v_carrier is not null and v_level = 'masked' then
      v_carrier := v_carrier || jsonb_build_object(
        'contact_phone',
        app_private.mask_permission_value(v_phone, 'phone')
      );
      v_data := jsonb_set(
        v_data,
        '{party_contact_phone}',
        coalesce(
          to_jsonb(app_private.mask_permission_value(v_phone, 'phone')),
          'null'::jsonb
        ),
        true
      );
    end if;
  end if;

  return v_data || jsonb_build_object(
    'customer', v_customer,
    'carrier', v_carrier,
    'field_access', v_access,
    'is_record_owner', p_contract.created_by_user_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.tms_list_contracts_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_contract_status text default null,
  p_business_contract_type text default null,
  p_contract_category text default null,
  p_customer_id uuid default null,
  p_carrier_id uuid default null,
  p_billing_method text default null,
  p_keyword text default null,
  p_create_time_from timestamptz default null,
  p_create_time_to timestamptz default null,
  p_record_id uuid default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_permission text := case
    when p_purpose = 'export' then 'TmsContract:Export'
    else 'TmsContract:View'
  end;
  v_limit integer;
  v_base_access jsonb;
  v_result jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid contract read purpose';
  end if;

  if not app_private.can_execute_tms_contract_action(v_permission, null, false) then
    raise exception 'Missing contract read permission' using errcode = '42501';
  end if;

  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.contract', null);

  with filtered as materialized (
    select contract_row as contract_record
    from public.tms_contract contract_row
    where (app_private.is_platform_super() or contract_row.tenant_id = v_tenant_id)
      and (p_record_id is null or contract_row.id = p_record_id)
      and (p_ids is null or contract_row.id = any(p_ids))
      and (p_contract_status is null or contract_row.contract_status = p_contract_status)
      and (
        p_business_contract_type is null
        or contract_row.business_contract_type = p_business_contract_type
      )
      and (p_contract_category is null or contract_row.contract_category = p_contract_category)
      and (p_customer_id is null or contract_row.customer_id = p_customer_id)
      and (p_carrier_id is null or contract_row.carrier_id = p_carrier_id)
      and (p_billing_method is null or contract_row.billing_method = p_billing_method)
      and (p_create_time_from is null or contract_row.create_time >= p_create_time_from)
      and (p_create_time_to is null or contract_row.create_time <= p_create_time_to)
      and (
        nullif(btrim(p_keyword), '') is null
        or contract_row.contract_name ilike '%' || btrim(p_keyword) || '%'
        or contract_row.contract_no ilike '%' || btrim(p_keyword) || '%'
        or contract_row.paper_contract_no ilike '%' || btrim(p_keyword) || '%'
        or contract_row.mnemonic_code ilike '%' || btrim(p_keyword) || '%'
        or contract_row.contact_name ilike '%' || btrim(p_keyword) || '%'
        or contract_row.transport_route ilike '%' || btrim(p_keyword) || '%'
        or contract_row.handler ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select filtered.contract_record
    from filtered
    order by (filtered.contract_record).create_time desc, (filtered.contract_record).id
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        app_private.tms_contract_to_secure_json(paged.contract_record, v_base_access)
        order by (paged.contract_record).create_time desc, (paged.contract_record).id
      )
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'fieldAccess', v_base_access
  )
    into v_result;

  return v_result;
end;
$$;

create or replace function public.tms_get_contract_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_contract public.tms_contract%rowtype;
begin
  select * into v_contract
  from public.tms_contract contract_row
  where contract_row.id = p_id
    and (app_private.is_platform_super() or contract_row.tenant_id = v_tenant_id);

  if not found then
    return null;
  end if;

  if not app_private.can_execute_tms_contract_action(
    'TmsContract:View',
    v_contract.created_by_user_id,
    true
  ) then
    raise exception 'Missing contract detail permission' using errcode = '42501';
  end if;

  return app_private.tms_contract_to_secure_json(v_contract, null);
end;
$$;

create or replace function public.tms_create_contract_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_input public.tms_contract%rowtype;
  v_contract_id uuid;
begin
  if not app_private.can_execute_tms_contract_action('TmsContract:Add', null, false) then
    raise exception 'Missing contract create permission' using errcode = '42501';
  end if;

  perform app_private.assert_tms_contract_payload_keys(p_payload);
  select * into v_input
  from jsonb_populate_record(null::public.tms_contract, p_payload);

  perform app_private.assert_tms_contract_reference_scope(
    v_tenant_id,
    v_input.customer_id,
    v_input.carrier_id,
    coalesce(v_input.transport_details, '[]'::jsonb)
  );

  insert into public.tms_contract (
    contract_no, contract_name, contract_status, carrier_id, contact_name, waybill_no,
    billing_method, contract_amount, sign_time, handler, contract_description,
    attachments, tenant_id, paper_contract_no, mnemonic_code, contract_category,
    transport_mode, business_contract_type, customer_id, customer_signatory,
    transport_unit_price, road_consumption_rate, loss_deduction_price, effective_date,
    expiry_date, is_completed, agreed_transport_quantity, transport_route, shipper_name,
    payer_name, consignee_name, special_transport_requirements, other_deduction_terms,
    transport_details
  ) values (
    nullif(v_input.contract_no, ''), v_input.contract_name, 'draft', v_input.carrier_id,
    v_input.contact_name, v_input.waybill_no, v_input.billing_method,
    v_input.contract_amount, v_input.sign_time, v_input.handler,
    v_input.contract_description, coalesce(v_input.attachments, '[]'::jsonb), v_tenant_id,
    v_input.paper_contract_no, v_input.mnemonic_code,
    coalesce(v_input.contract_category, 'annual_framework'),
    coalesce(v_input.transport_mode, 'road'),
    coalesce(v_input.business_contract_type, 'carrier'),
    v_input.customer_id, v_input.customer_signatory, v_input.transport_unit_price,
    v_input.road_consumption_rate, v_input.loss_deduction_price, v_input.effective_date,
    v_input.expiry_date, coalesce(v_input.is_completed, false),
    v_input.agreed_transport_quantity, v_input.transport_route, v_input.shipper_name,
    v_input.payer_name, v_input.consignee_name, v_input.special_transport_requirements,
    v_input.other_deduction_terms, coalesce(v_input.transport_details, '[]'::jsonb)
  )
  returning id into v_contract_id;

  return v_contract_id;
end;
$$;

create or replace function public.tms_update_contract_secure(p_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_old public.tms_contract%rowtype;
  v_candidate public.tms_contract%rowtype;
  v_updated public.tms_contract%rowtype;
begin
  select * into v_old
  from public.tms_contract contract_row
  where contract_row.id = p_id
    and (app_private.is_platform_super() or contract_row.tenant_id = v_tenant_id)
  for update;

  if not found then
    raise exception 'Contract not found or access denied';
  end if;

  if not app_private.can_execute_tms_contract_action(
    'TmsContract:Edit',
    v_old.created_by_user_id,
    true
  ) then
    raise exception 'Missing contract edit permission' using errcode = '42501';
  end if;

  if v_old.contract_status not in ('draft', 'rejected') then
    raise exception 'Only draft or rejected contracts can be edited';
  end if;

  perform app_private.assert_tms_contract_payload_keys(p_payload);
  select * into v_candidate
  from jsonb_populate_record(v_old, p_payload);

  perform app_private.assert_tms_contract_reference_scope(
    v_old.tenant_id,
    v_candidate.customer_id,
    v_candidate.carrier_id,
    v_candidate.transport_details
  );

  if v_candidate.contract_amount is distinct from v_old.contract_amount
     and app_private.resolve_field_access(
       'tms.contract', 'contractAmount', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for contract amount' using errcode = '42501';
  end if;

  if v_candidate.transport_unit_price is distinct from v_old.transport_unit_price
     and app_private.resolve_field_access(
       'tms.contract', 'transportUnitPrice', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for transport unit price' using errcode = '42501';
  end if;

  if v_candidate.road_consumption_rate is distinct from v_old.road_consumption_rate
     and app_private.resolve_field_access(
       'tms.contract', 'roadConsumptionRate', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for road consumption rate' using errcode = '42501';
  end if;

  if v_candidate.loss_deduction_price is distinct from v_old.loss_deduction_price
     and app_private.resolve_field_access(
       'tms.contract', 'lossDeductionPrice', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for loss deduction price' using errcode = '42501';
  end if;

  if app_private.tms_contract_transport_pricing(v_candidate.transport_details)
       is distinct from app_private.tms_contract_transport_pricing(v_old.transport_details)
     and app_private.resolve_field_access(
       'tms.contract', 'transportDetailsPricing', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for contract detail pricing' using errcode = '42501';
  end if;

  if v_candidate.attachments is distinct from v_old.attachments
     and app_private.resolve_field_access(
       'tms.contract', 'attachments', v_old.created_by_user_id
     ) <> 'edit' then
    raise exception 'No edit permission for contract attachments' using errcode = '42501';
  end if;

  update public.tms_contract
  set contract_no = v_candidate.contract_no,
      contract_name = v_candidate.contract_name,
      carrier_id = v_candidate.carrier_id,
      contact_name = v_candidate.contact_name,
      waybill_no = v_candidate.waybill_no,
      billing_method = v_candidate.billing_method,
      contract_amount = v_candidate.contract_amount,
      sign_time = v_candidate.sign_time,
      handler = v_candidate.handler,
      contract_description = v_candidate.contract_description,
      attachments = v_candidate.attachments,
      paper_contract_no = v_candidate.paper_contract_no,
      mnemonic_code = v_candidate.mnemonic_code,
      contract_category = v_candidate.contract_category,
      transport_mode = v_candidate.transport_mode,
      business_contract_type = v_candidate.business_contract_type,
      customer_id = v_candidate.customer_id,
      customer_signatory = v_candidate.customer_signatory,
      transport_unit_price = v_candidate.transport_unit_price,
      road_consumption_rate = v_candidate.road_consumption_rate,
      loss_deduction_price = v_candidate.loss_deduction_price,
      effective_date = v_candidate.effective_date,
      expiry_date = v_candidate.expiry_date,
      is_completed = v_candidate.is_completed,
      agreed_transport_quantity = v_candidate.agreed_transport_quantity,
      transport_route = v_candidate.transport_route,
      shipper_name = v_candidate.shipper_name,
      payer_name = v_candidate.payer_name,
      consignee_name = v_candidate.consignee_name,
      special_transport_requirements = v_candidate.special_transport_requirements,
      other_deduction_terms = v_candidate.other_deduction_terms,
      transport_details = v_candidate.transport_details
  where id = v_old.id
  returning * into v_updated;

  return app_private.tms_contract_to_secure_json(v_updated, null);
end;
$$;

create or replace function public.tms_list_available_contract_details(p_keyword text default null)
returns table(
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
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_tms_contract_action('TmsContract:View', null, false) then
    raise exception 'Missing contract detail selector permission' using errcode = '42501';
  end if;

  return query
  select
    contract.id::text || ':' || detail.ordinality::text,
    contract.id,
    contract.contract_no,
    contract.contract_name,
    contract.effective_date,
    contract.expiry_date,
    nullif(detail.value->>'cargo_id', '')::uuid,
    detail.value->>'cargo_description',
    detail.value->>'cargo_code',
    coalesce(nullif(detail.value->>'contract_quantity', '')::numeric, 0),
    detail.value->>'unit',
    case
      when app_private.resolve_field_access(
        'tms.contract', 'transportDetailsPricing', contract.created_by_user_id
      ) in ('read', 'edit')
      then coalesce(nullif(detail.value->>'transport_unit_price', '')::numeric, 0)
      else null
    end,
    case
      when app_private.resolve_field_access(
        'tms.contract', 'transportDetailsPricing', contract.created_by_user_id
      ) in ('read', 'edit')
      then coalesce(nullif(detail.value->>'freight', '')::numeric, 0)
      else null
    end
  from public.tms_contract contract
  cross join lateral jsonb_array_elements(contract.transport_details)
    with ordinality detail(value, ordinality)
  where (app_private.is_platform_super() or contract.tenant_id = app_private.current_user_tenant_id())
    and contract.contract_status = 'approved'
    and contract.is_completed = false
    and (contract.effective_date is null or contract.effective_date <= current_date)
    and (contract.expiry_date is null or contract.expiry_date >= current_date)
    and nullif(btrim(detail.value->>'cargo_description'), '') is not null
    and (
      nullif(btrim(p_keyword), '') is null
      or contract.contract_no ilike '%' || btrim(p_keyword) || '%'
      or contract.contract_name ilike '%' || btrim(p_keyword) || '%'
      or detail.value->>'cargo_description' ilike '%' || btrim(p_keyword) || '%'
      or detail.value->>'cargo_code' ilike '%' || btrim(p_keyword) || '%'
    )
  order by contract.create_time desc, detail.ordinality;
end;
$$;

create or replace function public.tms_delete_contract_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_contract public.tms_contract%rowtype;
begin
  select * into v_contract
  from public.tms_contract contract_row
  where contract_row.id = p_id
    and (app_private.is_platform_super() or contract_row.tenant_id = v_tenant_id)
  for update;

  if not found then
    return false;
  end if;

  if not app_private.can_execute_tms_contract_action(
    'TmsContract:Delete',
    v_contract.created_by_user_id,
    true
  ) then
    raise exception 'Missing contract delete permission' using errcode = '42501';
  end if;

  if v_contract.contract_status not in ('draft', 'rejected') then
    raise exception 'Only draft or rejected contracts can be deleted';
  end if;

  delete from public.tms_contract where id = v_contract.id;
  return true;
end;
$$;

create or replace function public.tms_delete_contracts_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_deleted integer := 0;
begin
  if coalesce(cardinality(p_ids), 0) > 500 then
    raise exception 'A maximum of 500 contracts can be deleted at once';
  end if;

  foreach v_id in array coalesce(p_ids, array[]::uuid[]) loop
    if public.tms_delete_contract_secure(v_id) then
      v_deleted := v_deleted + 1;
    end if;
  end loop;

  return v_deleted;
end;
$$;

create or replace function public.tms_import_contracts_secure(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_item jsonb;
  v_existing public.tms_contract%rowtype;
  v_id uuid;
  v_ids jsonb := '[]'::jsonb;
  v_count integer := 0;
begin
  if not app_private.can_execute_tms_contract_action('TmsContract:Import', null, false) then
    raise exception 'Missing contract import permission' using errcode = '42501';
  end if;

  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'Contract import payload must be a JSON array';
  end if;

  if jsonb_array_length(p_rows) > 1000 then
    raise exception 'A maximum of 1000 contracts can be imported at once';
  end if;

  for v_item in select value from jsonb_array_elements(p_rows) loop
    v_existing := null;
    if nullif(v_item->>'contract_no', '') is not null then
      select * into v_existing
      from public.tms_contract contract_row
      where contract_row.tenant_id = v_tenant_id
        and contract_row.contract_no = v_item->>'contract_no'
      for update;
    end if;

    if v_existing.id is null then
      v_id := public.tms_create_contract_secure(v_item);
    else
      perform public.tms_update_contract_secure(v_existing.id, v_item - 'contract_no');
      v_id := v_existing.id;
    end if;

    v_ids := v_ids || to_jsonb(v_id);
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('count', v_count, 'ids', v_ids);
end;
$$;

-- Raw table access would bypass omission and masking, so authenticated clients use RPCs only.
revoke select, insert, update, delete on public.tms_contract from anon, authenticated;

revoke all on function app_private.set_tms_contract_creator_identity() from public, anon, authenticated;
revoke all on function app_private.assert_tms_contract_payload_keys(jsonb) from public, anon, authenticated;
revoke all on function app_private.assert_tms_contract_reference_scope(uuid, uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function app_private.tms_contract_transport_pricing(jsonb)
  from public, anon, authenticated;
revoke all on function app_private.tms_contract_to_secure_json(public.tms_contract, jsonb)
  from public, anon, authenticated;
revoke all on function app_private.seed_field_permission_catalog_before_tms_contract_recovery(uuid)
  from public, anon, authenticated;
revoke all on function app_private.seed_field_permission_catalog(uuid)
  from public, anon, authenticated;

revoke all on function public.tms_list_contracts_secure(
  integer, integer, text, text, text, uuid, uuid, text, text,
  timestamptz, timestamptz, uuid, uuid[], text
) from public, anon;
revoke all on function public.tms_get_contract_secure(uuid) from public, anon;
revoke all on function public.tms_create_contract_secure(jsonb) from public, anon;
revoke all on function public.tms_update_contract_secure(uuid, jsonb) from public, anon;
revoke all on function public.tms_delete_contract_secure(uuid) from public, anon;
revoke all on function public.tms_delete_contracts_secure(uuid[]) from public, anon;
revoke all on function public.tms_import_contracts_secure(jsonb) from public, anon;
revoke all on function public.tms_list_available_contract_details(text) from public, anon;

grant execute on function public.tms_list_contracts_secure(
  integer, integer, text, text, text, uuid, uuid, text, text,
  timestamptz, timestamptz, uuid, uuid[], text
) to authenticated, service_role;
grant execute on function public.tms_get_contract_secure(uuid) to authenticated, service_role;
grant execute on function public.tms_create_contract_secure(jsonb) to authenticated, service_role;
grant execute on function public.tms_update_contract_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.tms_delete_contract_secure(uuid) to authenticated, service_role;
grant execute on function public.tms_delete_contracts_secure(uuid[]) to authenticated, service_role;
grant execute on function public.tms_import_contracts_secure(jsonb) to authenticated, service_role;
grant execute on function public.tms_list_available_contract_details(text)
  to authenticated, service_role;

;
