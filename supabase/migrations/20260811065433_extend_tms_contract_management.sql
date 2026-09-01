create or replace function app_private.is_valid_contract_transport_details(p_details jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when jsonb_typeof(p_details) <> 'array' then false
    else not exists (
      select 1
      from jsonb_array_elements(p_details) as detail(item)
      where jsonb_typeof(detail.item) <> 'object'
        or nullif(btrim(detail.item ->> 'cargoDescription'), '') is null
        or nullif(btrim(detail.item ->> 'cargoCode'), '') is null
        or nullif(btrim(detail.item ->> 'unit'), '') is null
        or not (detail.item ? 'contractQuantity')
        or jsonb_typeof(detail.item -> 'contractQuantity') <> 'number'
        or (detail.item ->> 'contractQuantity')::numeric < 0
        or not (detail.item ? 'transportUnitPrice')
        or jsonb_typeof(detail.item -> 'transportUnitPrice') <> 'number'
        or (detail.item ->> 'transportUnitPrice')::numeric < 0
        or not (detail.item ? 'freight')
        or jsonb_typeof(detail.item -> 'freight') <> 'number'
        or (detail.item ->> 'freight')::numeric < 0
        or (
          detail.item ? 'cargoId'
          and jsonb_typeof(detail.item -> 'cargoId') not in ('string', 'null')
        )
    )
  end;
$$;

alter table public.tms_contract
  add column if not exists paper_contract_no text,
  add column if not exists mnemonic_code text,
  add column if not exists contract_category text not null default 'annual_framework',
  add column if not exists transport_mode text not null default 'road',
  add column if not exists business_contract_type text not null default 'carrier',
  add column if not exists customer_id uuid,
  add column if not exists customer_signatory text,
  add column if not exists transport_unit_price numeric(18, 4),
  add column if not exists road_consumption_rate numeric(7, 4),
  add column if not exists loss_deduction_price numeric(18, 4),
  add column if not exists effective_date date,
  add column if not exists expiry_date date,
  add column if not exists is_completed boolean not null default false,
  add column if not exists agreed_transport_quantity numeric(18, 4),
  add column if not exists transport_route text,
  add column if not exists shipper_name text,
  add column if not exists payer_name text,
  add column if not exists consignee_name text,
  add column if not exists special_transport_requirements text,
  add column if not exists other_deduction_terms text,
  add column if not exists transport_details jsonb not null default '[]'::jsonb;

alter table public.tms_contract alter column carrier_id drop not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_customer_id_fkey'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_customer_id_fkey
      foreign key (customer_id) references public.tms_customer(id) on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_business_type_check'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_business_type_check
      check (business_contract_type in ('customer', 'carrier'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_party_check'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_party_check
      check (
        (business_contract_type = 'carrier' and carrier_id is not null and customer_id is null)
        or
        (business_contract_type = 'customer' and customer_id is not null and carrier_id is null)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_category_check'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_category_check
      check (contract_category in ('annual_framework', 'project', 'single_transport', 'temporary', 'other'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_transport_mode_check'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_transport_mode_check
      check (transport_mode in ('road', 'rail', 'air', 'water', 'multimodal'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_transport_unit_price_nonnegative'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_transport_unit_price_nonnegative
      check (transport_unit_price is null or transport_unit_price >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_road_consumption_rate_range'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_road_consumption_rate_range
      check (road_consumption_rate is null or road_consumption_rate between 0 and 100);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_loss_deduction_price_nonnegative'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_loss_deduction_price_nonnegative
      check (loss_deduction_price is null or loss_deduction_price >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_agreed_quantity_nonnegative'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_agreed_quantity_nonnegative
      check (agreed_transport_quantity is null or agreed_transport_quantity >= 0);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_effective_expiry_check'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_effective_expiry_check
      check (effective_date is null or expiry_date is null or expiry_date >= effective_date);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_contract'::regclass
      and conname = 'tms_contract_transport_details_check'
  ) then
    alter table public.tms_contract
      add constraint tms_contract_transport_details_check
      check (app_private.is_valid_contract_transport_details(transport_details));
  end if;
end;
$$;

create index if not exists idx_tms_contract_tenant_customer
  on public.tms_contract (tenant_id, customer_id)
  where customer_id is not null;

create index if not exists idx_tms_contract_tenant_business_type
  on public.tms_contract (tenant_id, business_contract_type);

comment on column public.tms_contract.business_contract_type is
  '合同相对方类型：customer=客户/货主端，carrier=承运商';
comment on column public.tms_contract.transport_unit_price is
  '合同级默认运输单价；运输明细可按货物覆盖';
comment on column public.tms_contract.agreed_transport_quantity is
  '合同级约定运输总量，不强制等于多计量单位明细之和';
comment on column public.tms_contract.transport_details is
  '运输合同明细 JSONB 数组，保存货物快照、合同数量、计量单位、运输单价和运费';

with contract_parent as (
  select id, tenant_id from public.sys_dict_type where code = 'tmsContract'
), inserted as (
  insert into public.sys_dict_type (
    name, code, create_by, update_by, tenant_id, parent_id, node_type, sort, remark
  )
  select '合同类别', 'tmsContractCategory', '624944977@qq.com', '624944977@qq.com',
    contract_parent.tenant_id, contract_parent.id, 'dictionary', 20, '运输合同类别'
  from contract_parent
  where not exists (select 1 from public.sys_dict_type where code = 'tmsContractCategory')
  returning id, tenant_id
), dict_type as (
  select id, tenant_id from inserted
  union all
  select id, tenant_id from public.sys_dict_type where code = 'tmsContractCategory'
)
insert into public.sys_dictionary (
  type_id, code, value, label, status, create_by, update_by, tenant_id, tag_type, sort
)
select dict_type.id, item.code, item.value, item.label, '1', '624944977@qq.com',
  '624944977@qq.com', dict_type.tenant_id, item.tag_type, item.sort
from dict_type
cross join (values
  ('tmsContractCategoryAnnualFramework', 'annual_framework', '年度框架合同', 'primary', 10),
  ('tmsContractCategoryProject', 'project', '项目合同', 'success', 20),
  ('tmsContractCategorySingleTransport', 'single_transport', '单次运输合同', 'warning', 30),
  ('tmsContractCategoryTemporary', 'temporary', '临时合同', 'info', 40),
  ('tmsContractCategoryOther', 'other', '其他合同', 'info', 50)
) as item(code, value, label, tag_type, sort)
where not exists (
  select 1 from public.sys_dictionary d
  where d.type_id = dict_type.id and d.value = item.value
);

with contract_parent as (
  select id, tenant_id from public.sys_dict_type where code = 'tmsContract'
), inserted as (
  insert into public.sys_dict_type (
    name, code, create_by, update_by, tenant_id, parent_id, node_type, sort, remark
  )
  select '业务合同分类', 'tmsContractBusinessType', '624944977@qq.com', '624944977@qq.com',
    contract_parent.tenant_id, contract_parent.id, 'dictionary', 30, '合同相对方分类'
  from contract_parent
  where not exists (select 1 from public.sys_dict_type where code = 'tmsContractBusinessType')
  returning id, tenant_id
), dict_type as (
  select id, tenant_id from inserted
  union all
  select id, tenant_id from public.sys_dict_type where code = 'tmsContractBusinessType'
)
insert into public.sys_dictionary (
  type_id, code, value, label, status, create_by, update_by, tenant_id, tag_type, sort
)
select dict_type.id, item.code, item.value, item.label, '1', '624944977@qq.com',
  '624944977@qq.com', dict_type.tenant_id, item.tag_type, item.sort
from dict_type
cross join (values
  ('tmsContractBusinessTypeCustomer', 'customer', '企业/货主端合同', 'primary', 10),
  ('tmsContractBusinessTypeCarrier', 'carrier', '承运商合同', 'success', 20)
) as item(code, value, label, tag_type, sort)
where not exists (
  select 1 from public.sys_dictionary d
  where d.type_id = dict_type.id and d.value = item.value
);

with contract_parent as (
  select id, tenant_id from public.sys_dict_type where code = 'tmsContract'
), inserted as (
  insert into public.sys_dict_type (
    name, code, create_by, update_by, tenant_id, parent_id, node_type, sort, remark
  )
  select '运输方式', 'tmsContractTransportMode', '624944977@qq.com', '624944977@qq.com',
    contract_parent.tenant_id, contract_parent.id, 'dictionary', 40, '运输合同运输方式'
  from contract_parent
  where not exists (select 1 from public.sys_dict_type where code = 'tmsContractTransportMode')
  returning id, tenant_id
), dict_type as (
  select id, tenant_id from inserted
  union all
  select id, tenant_id from public.sys_dict_type where code = 'tmsContractTransportMode'
)
insert into public.sys_dictionary (
  type_id, code, value, label, status, create_by, update_by, tenant_id, tag_type, sort
)
select dict_type.id, item.code, item.value, item.label, '1', '624944977@qq.com',
  '624944977@qq.com', dict_type.tenant_id, item.tag_type, item.sort
from dict_type
cross join (values
  ('tmsContractTransportModeRoad', 'road', '公路', 'primary', 10),
  ('tmsContractTransportModeRail', 'rail', '铁路', 'success', 20),
  ('tmsContractTransportModeAir', 'air', '空运', 'warning', 30),
  ('tmsContractTransportModeWater', 'water', '水运', 'info', 40),
  ('tmsContractTransportModeMultimodal', 'multimodal', '多式联运', 'primary', 50)
) as item(code, value, label, tag_type, sort)
where not exists (
  select 1 from public.sys_dictionary d
  where d.type_id = dict_type.id and d.value = item.value
);

create or replace function app_private.trg_enrich_contract_workflow_context()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contract record;
begin
  if new.business_type <> 'tms_contract' then
    return new;
  end if;

  select
    c.business_contract_type,
    c.contract_category,
    c.transport_mode,
    c.customer_id,
    c.carrier_id,
    c.effective_date,
    c.expiry_date,
    c.is_completed,
    coalesce(customer.customer_name, carrier.company_name) as party_name
  into v_contract
  from public.tms_contract c
  left join public.tms_customer customer on customer.id = c.customer_id
  left join public.tms_carrier carrier on carrier.id = c.carrier_id
  where c.id = new.business_id and c.tenant_id = new.tenant_id;

  if not found then
    raise exception '合同不存在或无权提交审批';
  end if;

  new.context_snapshot := coalesce(new.context_snapshot, '{}'::jsonb) || jsonb_build_object(
    'businessContractType', v_contract.business_contract_type,
    'contractCategory', v_contract.contract_category,
    'transportMode', v_contract.transport_mode,
    'customerId', v_contract.customer_id,
    'carrierId', v_contract.carrier_id,
    'partyName', v_contract.party_name,
    'effectiveDate', v_contract.effective_date,
    'expiryDate', v_contract.expiry_date,
    'isCompleted', v_contract.is_completed
  );
  return new;
end;
$$;

drop trigger if exists wf_instance_validate_contract_context on public.wf_instance;
create trigger wf_instance_validate_contract_context
before insert on public.wf_instance
for each row execute function app_private.trg_enrich_contract_workflow_context();

create or replace function app_private.get_contract_workflow_snapshot(p_instance_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_instance public.wf_instance;
  v_contract record;
  v_warnings jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null or not app_private.can_view_workflow_instance(p_instance_id) then
    raise exception '无权查看该审批业务信息' using errcode = '42501';
  end if;

  select * into v_instance from public.wf_instance where id = p_instance_id;
  if not found then raise exception '审批实例不存在'; end if;

  select
    c.*,
    coalesce(customer.customer_name, carrier.company_name) as party_name
  into v_contract
  from public.tms_contract c
  left join public.tms_customer customer on customer.id = c.customer_id
  left join public.tms_carrier carrier on carrier.id = c.carrier_id
  where c.id = v_instance.business_id and c.tenant_id = v_instance.tenant_id;

  if not found then
    v_warnings := jsonb_build_array('业务原单已删除，当前仅展示流程快照');
    return jsonb_build_object(
      'instanceId', v_instance.id,
      'businessType', v_instance.business_type,
      'businessId', v_instance.business_id,
      'title', v_instance.business_title,
      'warnings', v_warnings,
      'metrics', '[]'::jsonb,
      'fields', '[]'::jsonb,
      'attachments', '[]'::jsonb
    );
  end if;

  return jsonb_build_object(
    'instanceId', v_instance.id,
    'businessType', v_instance.business_type,
    'businessId', v_instance.business_id,
    'title', v_instance.business_title,
    'subtitle', v_contract.contract_name,
    'businessNo', v_contract.contract_no,
    'status', v_contract.contract_status,
    'routePath', '/tms-transportation/basic-data/contract-detail/' || v_instance.business_id::text,
    'metrics', jsonb_build_array(
      jsonb_build_object('label', '合同金额', 'value', '¥ ' || to_char(coalesce(v_contract.contract_amount, 0), 'FM999,999,990.00'), 'tone', 'warning'),
      jsonb_build_object('label', '生效日期', 'value', coalesce(v_contract.effective_date::text, '--'), 'tone', 'info'),
      jsonb_build_object('label', '运输明细', 'value', jsonb_array_length(v_contract.transport_details)::text || ' 条', 'tone', 'primary')
    ),
    'fields', jsonb_build_array(
      jsonb_build_object('label', '合同编号', 'value', coalesce(v_contract.contract_no, '--')),
      jsonb_build_object('label', '合同相对方', 'value', coalesce(v_contract.party_name, '--')),
      jsonb_build_object('label', '业务合同分类', 'value', coalesce(v_contract.business_contract_type, '--')),
      jsonb_build_object('label', '合同类别', 'value', coalesce(v_contract.contract_category, '--')),
      jsonb_build_object('label', '运输方式', 'value', coalesce(v_contract.transport_mode, '--')),
      jsonb_build_object('label', '计费方式', 'value', coalesce(v_contract.billing_method, '--')),
      jsonb_build_object('label', '经办人', 'value', coalesce(v_contract.handler, '--')),
      jsonb_build_object('label', '有效期', 'value', concat_ws(' 至 ', v_contract.effective_date::text, v_contract.expiry_date::text))
    ),
    'warnings', v_warnings,
    'attachments', app_private.workflow_attachment_list(v_contract.attachments)
  );
end;
$$;

create or replace function app_private.get_workflow_business_snapshot_v2(p_instance_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_type text;
begin
  select business_type into v_type from public.wf_instance where id = p_instance_id;
  if v_type = 'tms_carrier_payment_application' then
    return app_private.get_carrier_payment_application_workflow_snapshot(p_instance_id);
  elsif v_type = 'tms_contract' then
    return app_private.get_contract_workflow_snapshot(p_instance_id);
  end if;
  return app_private.get_workflow_business_snapshot(p_instance_id);
end;
$$;

create or replace function app_private.validate_workflow_business_config(
  p_business_type text,
  p_config jsonb
)
returns void
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_node jsonb;
  v_operator text;
  v_field text;
  v_allowed_fields text[];
begin
  perform app_private.validate_workflow_config(p_config);
  if p_config ? 'allowAutoApprove' and jsonb_typeof(p_config -> 'allowAutoApprove') <> 'boolean' then
    raise exception '全条件未命中策略必须是布尔值';
  end if;
  v_allowed_fields := case p_business_type
    when 'tms_waybill_cost' then array['amount','costType','payeeName','waybillNo','occurredOn']
    when 'tms_in_transit_expense' then array['amount','expenseType','waybillNo','plateNo','driverName','occurredOn']
    when 'tms_expense_reimbursement' then array['amount','reimbursementNo','paymentMethod','itemCount','waybillCount','plannedPaymentDate']
    when 'tms_invoice' then array['direction','invoiceType','invoiceNo','totalAmount','taxRate','counterpartyName']
    when 'tms_carrier_payment_application' then array['amount','applicationNo','carrierId','carrierName','plannedPaymentDate','statementCount']
    when 'tms_carrier_statement' then array['statementNo','statementAmount','carrierId','carrierName','costCount','settledAmount']
    when 'tms_customer_statement' then array['statementNo','statementAmount','customerId','customerName','waybillCount','settledAmount']
    when 'tms_contract' then array[
      'contractNo','contractAmount','businessContractType','contractCategory','transportMode',
      'customerId','carrierId','partyName','billingMethod','signTime','effectiveDate','expiryDate',
      'isCompleted','handler'
    ]
    when 'vehicle_archive' then array['plateNo','companyName','vehicleType','approvedLoadMass','operationType','isNewEnergy']
    else null end;
  for v_node in select value from jsonb_array_elements(p_config -> 'nodes') loop
    v_operator := coalesce(v_node #>> '{condition,operator}', 'always');
    if v_operator <> 'always' then
      v_field := btrim(coalesce(v_node #>> '{condition,field}', ''));
      if v_field = '' then raise exception '节点“%”必须选择条件字段', v_node ->> 'name'; end if;
      if v_allowed_fields is not null and not (v_field = any(v_allowed_fields)) then
        raise exception '节点“%”使用了业务类型 % 不支持的条件字段 %',
          v_node ->> 'name', p_business_type, v_field;
      end if;
      if v_operator = 'in' and (
        jsonb_typeof(v_node #> '{condition,value}') <> 'array'
        or jsonb_array_length(v_node #> '{condition,value}') = 0
      ) then
        raise exception '节点“%”的“属于”比较值必须是非空数组', v_node ->> 'name';
      end if;
    end if;
  end loop;
end;
$$;

create or replace function public.get_tms_customer_delete_dependencies(p_customer_ids uuid[])
returns table(customer_id uuid, dependency_code text, dependency_count bigint)
language sql
stable
set search_path = ''
as $$
  with requested_customer as (
    select distinct unnest(coalesce(p_customer_ids, '{}'::uuid[])) as customer_id
  )
  select source.customer_id, source.dependency_code, count(*)::bigint as dependency_count
  from (
    select allocation.customer_id, 'cash_allocation'::text as dependency_code
    from public.tms_cash_allocation allocation
    join requested_customer requested on requested.customer_id = allocation.customer_id
    union all
    select transaction.customer_id, 'cash_transaction'::text
    from public.tms_cash_transaction transaction
    join requested_customer requested on requested.customer_id = transaction.customer_id
    union all
    select price.customer_id, 'customer_price'::text
    from public.tms_customer_price price
    join requested_customer requested on requested.customer_id = price.customer_id
    union all
    select statement.customer_id, 'customer_statement'::text
    from public.tms_customer_statement statement
    join requested_customer requested on requested.customer_id = statement.customer_id
    union all
    select statement_item.customer_id, 'customer_statement_item'::text
    from public.tms_customer_statement_item statement_item
    join requested_customer requested on requested.customer_id = statement_item.customer_id
    union all
    select invoice.customer_id, 'invoice'::text
    from public.tms_invoice invoice
    join requested_customer requested on requested.customer_id = invoice.customer_id
    union all
    select contract.customer_id, 'contract'::text
    from public.tms_contract contract
    join requested_customer requested on requested.customer_id = contract.customer_id
  ) source
  group by source.customer_id, source.dependency_code
  order by source.customer_id, source.dependency_code;
$$;

create or replace function public.get_tms_customer_delete_dependency_details(p_customer_ids uuid[])
returns table(
  customer_id uuid,
  dependency_code text,
  record_id uuid,
  target_id uuid,
  record_no text,
  record_summary text,
  record_status text,
  record_amount numeric,
  created_at timestamptz
)
language sql
stable
set search_path = ''
as $$
  with requested_customer as (
    select distinct unnest(coalesce(p_customer_ids, '{}'::uuid[])) as customer_id
  )
  select details.*
  from (
    select allocation.customer_id, 'cash_allocation'::text, allocation.id,
      allocation.transaction_id, coalesce(transaction.transaction_no, allocation.id::text),
      statement.statement_no, case when allocation.is_active then 'active' else 'reversed' end,
      allocation.allocated_amount, allocation.create_time
    from public.tms_cash_allocation allocation
    join requested_customer requested on requested.customer_id = allocation.customer_id
    left join public.tms_cash_transaction transaction on transaction.id = allocation.transaction_id
    left join public.tms_customer_statement statement on statement.id = allocation.statement_id
    union all
    select transaction.customer_id, 'cash_transaction'::text, transaction.id, transaction.id,
      transaction.transaction_no, transaction.bank_reference, transaction.status,
      transaction.amount, transaction.create_time
    from public.tms_cash_transaction transaction
    join requested_customer requested on requested.customer_id = transaction.customer_id
    union all
    select price.customer_id, 'customer_price'::text, price.id, price.id,
      concat_ws(' → ', nullif(price.origin_region, ''), nullif(price.destination_region, '')),
      price.billing_method, null::text, price.total_fee, price.create_time
    from public.tms_customer_price price
    join requested_customer requested on requested.customer_id = price.customer_id
    union all
    select statement.customer_id, 'customer_statement'::text, statement.id, statement.id,
      statement.statement_no, concat(statement.period_start::text, ' 至 ', statement.period_end::text),
      statement.status, statement.settled_amount, statement.create_time
    from public.tms_customer_statement statement
    join requested_customer requested on requested.customer_id = statement.customer_id
    union all
    select statement_item.customer_id, 'customer_statement_item'::text, statement_item.id,
      statement_item.statement_id,
      coalesce(statement_item.waybill_no_snapshot, statement_item.order_no_snapshot, statement_item.id::text),
      statement.statement_no, case when statement_item.is_active then 'active' else 'inactive' end,
      statement_item.line_amount, statement_item.create_time
    from public.tms_customer_statement_item statement_item
    join requested_customer requested on requested.customer_id = statement_item.customer_id
    left join public.tms_customer_statement statement on statement.id = statement_item.statement_id
    union all
    select invoice.customer_id, 'invoice'::text, invoice.id, invoice.id,
      coalesce(nullif(invoice.invoice_no, ''), invoice.invoice_record_no), invoice.invoice_record_no,
      invoice.status, invoice.total_amount, invoice.create_time
    from public.tms_invoice invoice
    join requested_customer requested on requested.customer_id = invoice.customer_id
    union all
    select contract.customer_id, 'contract'::text, contract.id, contract.id,
      coalesce(nullif(contract.contract_no, ''), contract.id::text), contract.contract_name,
      contract.contract_status, contract.contract_amount, contract.create_time
    from public.tms_contract contract
    join requested_customer requested on requested.customer_id = contract.customer_id
  ) details(
    customer_id, dependency_code, record_id, target_id, record_no, record_summary,
    record_status, record_amount, created_at
  )
  order by details.customer_id, details.dependency_code, details.created_at desc, details.record_id;
$$;
;
