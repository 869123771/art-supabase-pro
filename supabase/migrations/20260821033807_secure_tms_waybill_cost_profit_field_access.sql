-- Waybill costs and derived profitability are financial records. Direct Data API
-- access is replaced by tenant-scoped, field-aware RPCs shared by pages, exports,
-- workflow snapshots, reimbursements and AI evidence readers.

alter table public.tms_waybill_cost
  add column if not exists created_by_user_id uuid;

update public.tms_waybill_cost cost_row
set created_by_user_id = coalesce(
  (
    select user_row.id
    from public.sys_user user_row
    where user_row.id = cost_row.reporter_user_id
      and user_row.tenant_id = cost_row.tenant_id
    limit 1
  ),
  (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = cost_row.tenant_id
      and lower(user_row.user_email) = lower(cost_row.create_by)
    order by user_row.create_time, user_row.id
    limit 1
  ),
  (
    select user_row.id
    from public.sys_user user_row
    join public.sys_role role_row
      on role_row.tenant_id = user_row.tenant_id
     and role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
    where user_row.tenant_id = cost_row.tenant_id
      and role_row.builtin_type in ('tenant_admin', 'platform_super')
      and user_row.status = '1'
      and user_row.deleted_at is null
    order by
      case role_row.builtin_type when 'tenant_admin' then 0 else 1 end,
      user_row.create_time,
      user_row.id
    limit 1
  ),
  (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = cost_row.tenant_id
      and user_row.deleted_at is null
    order by user_row.create_time, user_row.id
    limit 1
  )
)
where cost_row.created_by_user_id is null;

do $$
begin
  if exists (
    select 1 from public.tms_waybill_cost where created_by_user_id is null
  ) then
    raise exception 'Unable to backfill tms_waybill_cost.created_by_user_id';
  end if;
end;
$$;

create or replace function public.tms_save_waybill_cost_secure(
  p_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_existing public.tms_waybill_cost%rowtype;
  v_saved public.tms_waybill_cost%rowtype;
  v_payload jsonb := coalesce(p_payload, '{}'::jsonb);
  v_access jsonb := jsonb_build_object(
    'costAmounts', 'edit',
    'paymentDetails', 'edit',
    'driverPhone', 'edit',
    'expenseLocation', 'edit',
    'expenseEvidence', 'edit'
  );
  v_amount numeric;
  v_quantity numeric;
  v_unit_price numeric;
  v_provider_name text;
  v_payee_name text;
  v_payment_channel text;
  v_invoice_no text;
  v_meter_no text;
  v_expense_location text;
  v_expense_region text;
  v_expense_region_adcode text;
  v_expense_longitude numeric;
  v_expense_latitude numeric;
  v_expense_coordinate_system text;
  v_expense_coordinate_source text;
  v_expense_coordinate_status text;
  v_expense_geocode_provider text;
  v_expense_geocoded_at timestamptz;
  v_attachments jsonb;
  v_latest_ocr_run_id uuid;
  v_ocr_artifact_id uuid;
  v_ocr_status text;
begin
  if v_tenant_id is null or v_user_id is null then
    raise exception '请登录后操作' using errcode = '42501';
  end if;
  if jsonb_typeof(v_payload) <> 'object' then
    raise exception '运单费用参数格式不正确';
  end if;

  if p_id is null then
    if not app_private.can_execute_business_action(
      'FinanceWaybillCost', 'FinanceWaybillCost:Add', null, false
    ) then
      raise exception 'Missing waybill cost create permission' using errcode = '42501';
    end if;

    v_amount := nullif(v_payload->>'amount', '')::numeric;
    v_quantity := nullif(v_payload->>'quantity', '')::numeric;
    v_unit_price := nullif(v_payload->>'unit_price', '')::numeric;
    v_provider_name := nullif(btrim(coalesce(v_payload->>'provider_name', '')), '');
    v_payee_name := nullif(btrim(coalesce(v_payload->>'payee_name', '')), '');
    v_payment_channel := nullif(btrim(coalesce(v_payload->>'payment_channel', '')), '');
    v_invoice_no := nullif(btrim(coalesce(v_payload->>'invoice_no', '')), '');
    v_meter_no := nullif(btrim(coalesce(v_payload->>'meter_no', '')), '');
    v_expense_location := nullif(btrim(coalesce(v_payload->>'expense_location', '')), '');
    v_expense_region := nullif(btrim(coalesce(v_payload->>'expense_region', '')), '');
    v_expense_region_adcode := nullif(btrim(coalesce(v_payload->>'expense_region_adcode', '')), '');
    v_expense_longitude := nullif(v_payload->>'expense_longitude', '')::numeric;
    v_expense_latitude := nullif(v_payload->>'expense_latitude', '')::numeric;
    v_expense_coordinate_system := nullif(btrim(coalesce(v_payload->>'expense_coordinate_system', '')), '');
    v_expense_coordinate_source := nullif(btrim(coalesce(v_payload->>'expense_coordinate_source', '')), '');
    v_expense_coordinate_status := coalesce(nullif(btrim(v_payload->>'expense_coordinate_status'), ''), 'pending');
    v_expense_geocode_provider := nullif(btrim(coalesce(v_payload->>'expense_geocode_provider', '')), '');
    v_expense_geocoded_at := nullif(v_payload->>'expense_geocoded_at', '')::timestamptz;
    v_attachments := coalesce(v_payload->'attachments', '[]'::jsonb);
    v_latest_ocr_run_id := nullif(v_payload->>'latest_ocr_run_id', '')::uuid;
    v_ocr_artifact_id := nullif(v_payload->>'ocr_artifact_id', '')::uuid;
    v_ocr_status := coalesce(nullif(v_payload->>'ocr_status', ''), 'not_started');
  else
    if not app_private.can_execute_business_action(
      'FinanceWaybillCost', 'FinanceWaybillCost:Edit', null, false
    ) then
      raise exception 'Missing waybill cost edit permission' using errcode = '42501';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(p_id::text, 841341));
    select cost_row.* into v_existing
    from public.tms_waybill_cost cost_row
    where cost_row.id = p_id and cost_row.tenant_id = v_tenant_id
    for update;
    if not found then
      raise exception '运单费用不存在或无权访问';
    end if;
    if v_existing.audit_status not in ('draft', 'rejected')
       or v_existing.settlement_status <> 'unsettled'
       or v_existing.reimbursement_id is not null
       or v_existing.expense_payment_id is not null then
      raise exception '当前运单费用状态不允许编辑';
    end if;

    v_access := app_private.field_access_map(
      'tms.waybill_cost', v_existing.created_by_user_id
    );

    if coalesce(v_access->>'costAmounts', 'hidden') = 'edit' then
      v_amount := nullif(v_payload->>'amount', '')::numeric;
      v_quantity := nullif(v_payload->>'quantity', '')::numeric;
      v_unit_price := nullif(v_payload->>'unit_price', '')::numeric;
    else
      v_amount := v_existing.amount;
      v_quantity := v_existing.quantity;
      v_unit_price := v_existing.unit_price;
    end if;

    if coalesce(v_access->>'paymentDetails', 'hidden') = 'edit' then
      v_provider_name := nullif(btrim(coalesce(v_payload->>'provider_name', '')), '');
      v_payee_name := nullif(btrim(coalesce(v_payload->>'payee_name', '')), '');
      v_payment_channel := nullif(btrim(coalesce(v_payload->>'payment_channel', '')), '');
      v_invoice_no := nullif(btrim(coalesce(v_payload->>'invoice_no', '')), '');
      v_meter_no := nullif(btrim(coalesce(v_payload->>'meter_no', '')), '');
    else
      v_provider_name := v_existing.provider_name;
      v_payee_name := v_existing.payee_name;
      v_payment_channel := v_existing.payment_channel;
      v_invoice_no := v_existing.invoice_no;
      v_meter_no := v_existing.meter_no;
    end if;

    if coalesce(v_access->>'expenseLocation', 'hidden') = 'edit' then
      v_expense_location := nullif(btrim(coalesce(v_payload->>'expense_location', '')), '');
      v_expense_region := nullif(btrim(coalesce(v_payload->>'expense_region', '')), '');
      v_expense_region_adcode := nullif(btrim(coalesce(v_payload->>'expense_region_adcode', '')), '');
      v_expense_longitude := nullif(v_payload->>'expense_longitude', '')::numeric;
      v_expense_latitude := nullif(v_payload->>'expense_latitude', '')::numeric;
      v_expense_coordinate_system := nullif(btrim(coalesce(v_payload->>'expense_coordinate_system', '')), '');
      v_expense_coordinate_source := nullif(btrim(coalesce(v_payload->>'expense_coordinate_source', '')), '');
      v_expense_coordinate_status := coalesce(nullif(btrim(v_payload->>'expense_coordinate_status'), ''), 'pending');
      v_expense_geocode_provider := nullif(btrim(coalesce(v_payload->>'expense_geocode_provider', '')), '');
      v_expense_geocoded_at := nullif(v_payload->>'expense_geocoded_at', '')::timestamptz;
    else
      v_expense_location := v_existing.expense_location;
      v_expense_region := v_existing.expense_region;
      v_expense_region_adcode := v_existing.expense_region_adcode;
      v_expense_longitude := v_existing.expense_longitude;
      v_expense_latitude := v_existing.expense_latitude;
      v_expense_coordinate_system := v_existing.expense_coordinate_system;
      v_expense_coordinate_source := v_existing.expense_coordinate_source;
      v_expense_coordinate_status := v_existing.expense_coordinate_status;
      v_expense_geocode_provider := v_existing.expense_geocode_provider;
      v_expense_geocoded_at := v_existing.expense_geocoded_at;
    end if;

    if coalesce(v_access->>'expenseEvidence', 'hidden') = 'edit' then
      v_attachments := coalesce(v_payload->'attachments', '[]'::jsonb);
      v_latest_ocr_run_id := nullif(v_payload->>'latest_ocr_run_id', '')::uuid;
      v_ocr_artifact_id := nullif(v_payload->>'ocr_artifact_id', '')::uuid;
      v_ocr_status := coalesce(nullif(v_payload->>'ocr_status', ''), 'not_started');
    else
      v_attachments := v_existing.attachments;
      v_latest_ocr_run_id := v_existing.latest_ocr_run_id;
      v_ocr_artifact_id := v_existing.ocr_artifact_id;
      v_ocr_status := v_existing.ocr_status;
    end if;
  end if;

  if v_amount is null or v_amount <= 0 then
    raise exception '费用金额必须大于 0';
  end if;
  if jsonb_typeof(v_attachments) <> 'array' then
    raise exception '费用附件格式不正确';
  end if;

  if p_id is null then
    insert into public.tms_waybill_cost (
      tenant_id, waybill_id, expense_item_id, amount, occurred_on,
      quantity, unit_price, provider_name, payee_name, payment_channel,
      invoice_no, meter_no, expense_location, expense_region,
      expense_region_adcode, expense_longitude, expense_latitude,
      expense_coordinate_system, expense_coordinate_source,
      expense_coordinate_status, expense_geocode_provider, expense_geocoded_at,
      carrier_id, driver_id, remark, attachments, reporter_user_id,
      latest_ocr_run_id, ocr_artifact_id, ocr_status, created_by_user_id
    ) values (
      v_tenant_id,
      nullif(v_payload->>'waybill_id', '')::uuid,
      nullif(v_payload->>'expense_item_id', '')::uuid,
      v_amount,
      coalesce(nullif(v_payload->>'occurred_on', '')::date, current_date),
      v_quantity, v_unit_price, v_provider_name, v_payee_name, v_payment_channel,
      v_invoice_no, v_meter_no, v_expense_location, v_expense_region,
      v_expense_region_adcode, v_expense_longitude, v_expense_latitude,
      v_expense_coordinate_system, v_expense_coordinate_source,
      v_expense_coordinate_status, v_expense_geocode_provider, v_expense_geocoded_at,
      nullif(v_payload->>'carrier_id', '')::uuid,
      nullif(v_payload->>'driver_id', '')::uuid,
      nullif(btrim(coalesce(v_payload->>'remark', '')), ''),
      v_attachments,
      nullif(v_payload->>'reporter_user_id', '')::uuid,
      v_latest_ocr_run_id, v_ocr_artifact_id, v_ocr_status, v_user_id
    ) returning * into v_saved;
  else
    update public.tms_waybill_cost
    set waybill_id = coalesce(nullif(v_payload->>'waybill_id', '')::uuid, waybill_id),
        expense_item_id = coalesce(nullif(v_payload->>'expense_item_id', '')::uuid, expense_item_id),
        amount = v_amount,
        occurred_on = coalesce(nullif(v_payload->>'occurred_on', '')::date, occurred_on),
        quantity = v_quantity,
        unit_price = v_unit_price,
        provider_name = v_provider_name,
        payee_name = v_payee_name,
        payment_channel = v_payment_channel,
        invoice_no = v_invoice_no,
        meter_no = v_meter_no,
        expense_location = v_expense_location,
        expense_region = v_expense_region,
        expense_region_adcode = v_expense_region_adcode,
        expense_longitude = v_expense_longitude,
        expense_latitude = v_expense_latitude,
        expense_coordinate_system = v_expense_coordinate_system,
        expense_coordinate_source = v_expense_coordinate_source,
        expense_coordinate_status = v_expense_coordinate_status,
        expense_geocode_provider = v_expense_geocode_provider,
        expense_geocoded_at = v_expense_geocoded_at,
        carrier_id = nullif(v_payload->>'carrier_id', '')::uuid,
        driver_id = nullif(v_payload->>'driver_id', '')::uuid,
        remark = nullif(btrim(coalesce(v_payload->>'remark', '')), ''),
        attachments = v_attachments,
        latest_ocr_run_id = v_latest_ocr_run_id,
        ocr_artifact_id = v_ocr_artifact_id,
        ocr_status = v_ocr_status
    where id = p_id and tenant_id = v_tenant_id
    returning * into v_saved;
  end if;

  return app_private.tms_waybill_cost_to_secure_json(
    app_private.tms_waybill_cost_raw_json(v_saved.id),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.tms_delete_waybill_cost_secure(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cost public.tms_waybill_cost%rowtype;
begin
  select cost_row.* into v_cost
  from public.tms_waybill_cost cost_row
  where cost_row.id = p_id and cost_row.tenant_id = v_tenant_id
  for update;
  if not found then raise exception '运单费用不存在或无权访问'; end if;
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', 'FinanceWaybillCost:Delete', null, false
  ) then
    raise exception 'Missing waybill cost delete permission' using errcode = '42501';
  end if;
  if v_cost.audit_status not in ('draft', 'rejected')
     or v_cost.settlement_status <> 'unsettled'
     or v_cost.reimbursement_id is not null
     or v_cost.expense_payment_id is not null then
    raise exception '当前运单费用状态不允许删除';
  end if;
  delete from public.tms_waybill_cost where id = p_id and tenant_id = v_tenant_id;
  return p_id;
end;
$$;

create or replace function public.tms_void_waybill_cost_secure(
  p_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cost public.tms_waybill_cost%rowtype;
begin
  select cost_row.* into v_cost
  from public.tms_waybill_cost cost_row
  where cost_row.id = p_id and cost_row.tenant_id = v_tenant_id
  for update;
  if not found then raise exception '运单费用不存在或无权访问'; end if;
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', 'FinanceWaybillCost:Delete', null, false
  ) then
    raise exception 'Missing waybill cost void permission' using errcode = '42501';
  end if;
  if v_cost.audit_status not in ('draft', 'rejected', 'approved')
     or v_cost.settlement_status <> 'unsettled'
     or v_cost.reimbursement_id is not null
     or v_cost.expense_payment_id is not null then
    raise exception '当前运单费用状态不允许作废';
  end if;
  update public.tms_waybill_cost
  set audit_status = 'voided', review_remark = nullif(btrim(coalesce(p_reason, '')), '')
  where id = p_id and tenant_id = v_tenant_id;
  return p_id;
end;
$$;

create or replace function public.validate_tms_waybill_cost_submission_secure(p_cost_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cost public.tms_waybill_cost%rowtype;
begin
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', 'FinanceWaybillCost:Submit', null, false
  ) then
    raise exception 'Missing waybill cost submit permission' using errcode = '42501';
  end if;
  select cost_row.* into v_cost
  from public.tms_waybill_cost cost_row
  where cost_row.id = p_cost_id and cost_row.tenant_id = v_tenant_id;
  if not found then raise exception '运单费用不存在或无权访问'; end if;
  if v_cost.audit_status not in ('draft', 'rejected') then
    raise exception '当前运单费用状态不允许提交审批';
  end if;
  if app_private.resolve_field_access(
    'tms.waybill_cost', 'costAmounts', v_cost.created_by_user_id
  ) not in ('read', 'edit') then
    raise exception '当前字段权限不足，无法读取费用金额并提交审批'
      using errcode = '42501';
  end if;
  return true;
end;
$$;

create or replace function public.start_workflow(
  p_business_type text,
  p_business_id uuid,
  p_business_title text,
  p_context jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_instance_id uuid;
begin
  if app_private.is_driver_user() then
    raise exception '司机端请通过对应的业务上报入口提交审批'
      using errcode = '42501';
  end if;
  if p_business_type = 'tms_waybill_cost' then
    perform public.validate_tms_waybill_cost_submission_secure(p_business_id);
  end if;
  v_instance_id := app_private.start_workflow(
    p_business_type, p_business_id, p_business_title, p_context, p_idempotency_key
  );
  if p_business_type = 'tms_waybill_cost' then
    update public.wf_instance
    set context_snapshot = coalesce(context_snapshot, '{}'::jsonb) - 'amount'
    where id = v_instance_id
      and business_type = 'tms_waybill_cost'
      and tenant_id = app_private.current_user_tenant_id();
  end if;
  return v_instance_id;
end;
$$;

create or replace function public.create_tms_expense_reimbursement(
  p_cost_ids uuid[],
  p_payee_name text,
  p_payee_bank text,
  p_payee_account text,
  p_planned_payment_date date,
  p_payment_method text,
  p_basis_urls jsonb default '[]'::jsonb,
  p_remark text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', 'FinanceWaybillCost:Convert', null, false
  ) then
    raise exception 'Missing waybill cost convert permission' using errcode = '42501';
  end if;
  if coalesce(array_length(p_cost_ids, 1), 0) = 0 then
    raise exception '请选择要转报销的运单费用';
  end if;
  if exists (
    select 1
    from unnest(p_cost_ids) requested(cost_id)
    left join public.tms_waybill_cost cost_row
      on cost_row.id = requested.cost_id and cost_row.tenant_id = v_tenant_id
    where cost_row.id is null
       or app_private.resolve_field_access(
         'tms.waybill_cost', 'costAmounts', cost_row.created_by_user_id
       ) not in ('read', 'edit')
  ) then
    raise exception '当前字段权限不足，无法读取所选费用金额并转报销'
      using errcode = '42501';
  end if;
  return app_private.create_tms_expense_reimbursement(
    p_cost_ids, p_payee_name, p_payee_bank, p_payee_account,
    p_planned_payment_date, p_payment_method, p_basis_urls, p_remark
  );
end;
$$;

alter table public.tms_waybill_cost
  alter column created_by_user_id set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.tms_waybill_cost'::regclass
      and conname = 'tms_waybill_cost_created_by_user_tenant_fkey'
  ) then
    alter table public.tms_waybill_cost
      add constraint tms_waybill_cost_created_by_user_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user(id, tenant_id)
      on update restrict
      on delete restrict;
  end if;
end;
$$;

create index if not exists tms_waybill_cost_tenant_creator_idx
  on public.tms_waybill_cost (tenant_id, created_by_user_id);

create index if not exists tms_waybill_cost_creator_tenant_idx
  on public.tms_waybill_cost (created_by_user_id, tenant_id);

create or replace function app_private.set_tms_waybill_cost_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := app_private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    if v_user_id is not null then
      new.created_by_user_id := v_user_id;
    elsif new.created_by_user_id is null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and (
          user_row.id = new.reporter_user_id
          or lower(user_row.user_email) = lower(new.create_by)
        )
      order by case when user_row.id = new.reporter_user_id then 0 else 1 end,
               user_row.create_time,
               user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve waybill cost creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Waybill cost creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists tms_waybill_cost_creator_identity on public.tms_waybill_cost;
create trigger tms_waybill_cost_creator_identity
before insert or update of created_by_user_id on public.tms_waybill_cost
for each row execute function app_private.set_tms_waybill_cost_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_waybill_cost_profit;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_waybill_cost_profit(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.waybill_cost', '运单费用',
    'FinanceWaybillCost', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'costAmounts', '费用金额、数量与单价',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'paymentDetails', '服务商、收款方与票据编号',
      'hidden', 'none', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'driverPhone', '司机联系电话',
      'hidden', 'phone', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'expenseLocation', '费用详细地点与坐标',
      'hidden', 'address', true, 40, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'expenseEvidence', '费用票据与 OCR 依据',
      'hidden', 'none', true, 50, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.waybill_profit', '运单利润',
    'FinanceWaybillProfit', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'receivableAmounts', '订单应收金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'costAmounts', '承运运费与总成本',
      'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'profitAmounts', '毛利额与毛利率',
      'hidden', 'amount', true, 30, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

insert into public.sys_role_field_permission (
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
 and (
   (resource_row.resource_key = 'tms.waybill_cost' and menu_row.name = 'FinanceWaybillCost')
   or
   (resource_row.resource_key = 'tms.waybill_profit' and menu_row.name = 'FinanceWaybillProfit')
 )
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key in ('tms.waybill_cost', 'tms.waybill_profit')
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.tms_waybill_cost_raw_json(p_cost_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select
    (to_jsonb(cost_row) - 'tenant_id' - 'created_by_user_id') ||
    jsonb_build_object(
      'expense_item', case when item_row.id is null then null else jsonb_build_object(
        'id', item_row.id,
        'item_code', item_row.item_code,
        'item_name', item_row.item_name,
        'business_category', item_row.business_category,
        'is_selectable', item_row.is_selectable,
        'reimbursement_allowed', item_row.reimbursement_allowed,
        'is_enabled', item_row.is_enabled
      ) end,
      'reimbursement', case when reimbursement_row.id is null then null else jsonb_build_object(
        'id', reimbursement_row.id,
        'reimbursement_no', reimbursement_row.reimbursement_no,
        'status', reimbursement_row.status
      ) end,
      'expense_payment', case when payment_row.id is null then null else jsonb_build_object(
        'id', payment_row.id,
        'payment_no', payment_row.payment_no,
        'payment_date', payment_row.payment_date,
        'bank_reference', payment_row.bank_reference
      ) end,
      'waybill', case when waybill_row.id is null then null else jsonb_build_object(
        'id', waybill_row.id,
        'waybill_no', waybill_row.waybill_no,
        'status', waybill_row.status,
        'order_id', waybill_row.order_id,
        'carrier_id', waybill_row.carrier_id,
        'driver_id', waybill_row.driver_id,
        'origin_city', waybill_row.origin_city,
        'destination_city', waybill_row.destination_city,
        'carrier', case when carrier_row.id is null then null else jsonb_build_object(
          'id', carrier_row.id, 'company_name', carrier_row.company_name
        ) end,
        'driver', case when driver_row.id is null then null else jsonb_build_object(
          'id', driver_row.id, 'driver_name', driver_row.driver_name
        ) end,
        'order', case when order_row.id is null then null else jsonb_build_object(
          'id', order_row.id,
          'order_no', order_row.order_no,
          'dispatch_plate_no', order_row.dispatch_plate_no,
          'dispatch_driver_name', order_row.dispatch_driver_name,
          'origin_station', order_row.origin_station,
          'destination_station', order_row.destination_station
        ) end
      ) end
    )
  from public.tms_waybill_cost cost_row
  left join public.tms_expense_item item_row on item_row.id = cost_row.expense_item_id
  left join public.tms_expense_reimbursement reimbursement_row
    on reimbursement_row.id = cost_row.reimbursement_id
  left join public.tms_expense_payment payment_row
    on payment_row.id = cost_row.expense_payment_id
  left join public.tms_waybill waybill_row on waybill_row.id = cost_row.waybill_id
  left join public.tms_carrier carrier_row on carrier_row.id = waybill_row.carrier_id
  left join public.tms_driver driver_row on driver_row.id = waybill_row.driver_id
  left join public.tms_order order_row on order_row.id = waybill_row.order_id
  where cost_row.id = p_cost_id
    and cost_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.tms_waybill_cost_to_secure_json(
  p_cost jsonb,
  p_owner_id uuid,
  p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(
    p_access,
    app_private.field_access_map('tms.waybill_cost', p_owner_id)
  );
  v_data jsonb := coalesce(p_cost, '{}'::jsonb)
    - 'tenant_id'
    - 'created_by_user_id';
  v_level text;
  v_payment jsonb;
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['amount', 'quantity', 'unit_price']::text[],
    coalesce(v_access->>'costAmounts', 'hidden')
  );

  v_level := coalesce(v_access->>'paymentDetails', 'hidden');
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'provider_name', 'payee_name', 'payment_channel', 'invoice_no', 'meter_no'
    ]::text[],
    v_level
  );
  v_payment := v_data->'expense_payment';
  if jsonb_typeof(v_payment) = 'object' and v_payment ? 'bank_reference' then
    if v_level = 'hidden' then
      v_payment := v_payment - 'bank_reference';
    elsif v_level = 'masked' then
      v_payment := jsonb_set(
        v_payment,
        '{bank_reference}',
        to_jsonb(app_private.mask_permission_value(
          v_payment->>'bank_reference', 'bank_account'
        )),
        true
      );
    end if;
    v_data := jsonb_set(v_data, '{expense_payment}', v_payment, true);
  end if;

  v_level := coalesce(v_access->>'driverPhone', 'hidden');
  if v_level = 'hidden' then
    v_data := v_data - 'driver_phone_snapshot';
  elsif v_level = 'masked' and v_data ? 'driver_phone_snapshot' then
    v_data := jsonb_set(
      v_data,
      '{driver_phone_snapshot}',
      to_jsonb(app_private.mask_permission_value(v_data->>'driver_phone_snapshot', 'phone')),
      true
    );
  end if;

  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'expense_location', 'expense_region', 'expense_region_adcode',
      'expense_longitude', 'expense_latitude', 'expense_coordinate_system',
      'expense_coordinate_source', 'expense_coordinate_status',
      'expense_geocode_provider', 'expense_geocoded_at'
    ]::text[],
    coalesce(v_access->>'expenseLocation', 'hidden')
  );

  v_level := coalesce(v_access->>'expenseEvidence', 'hidden');
  v_data := app_private.apply_jsonb_document_access(
    v_data,
    array['attachments']::text[],
    v_level
  );
  if v_level not in ('read', 'edit') then
    v_data := v_data - 'latest_ocr_run_id' - 'ocr_artifact_id';
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.tms_list_waybill_costs_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_record_id uuid default null,
  p_order_id uuid default null,
  p_waybill_id uuid default null,
  p_carrier_id uuid default null,
  p_expense_item_id uuid default null,
  p_cost_type text default null,
  p_audit_status text default null,
  p_settlement_status text default null,
  p_occurred_on_start date default null,
  p_occurred_on_end date default null,
  p_keyword text default null,
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
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1),
    case when p_purpose = 'export' then 10000 else 200 end
  );
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map('tms.waybill_cost', null);
  v_row record;
begin
  if p_purpose = 'export' then
    if not app_private.can_execute_business_action(
      'FinanceWaybillCost', 'FinanceWaybillCost:Export', null, false
    ) then
      raise exception 'Missing waybill cost export permission' using errcode = '42501';
    end if;
  elsif not app_private.can_execute_business_action(
    'FinanceWaybillCost', null, null, false
  ) then
    raise exception 'Missing waybill cost menu permission' using errcode = '42501';
  end if;

  select count(*)::integer
  into v_total
  from public.tms_waybill_cost cost_row
  left join public.tms_waybill waybill_row on waybill_row.id = cost_row.waybill_id
  left join public.tms_order order_row on order_row.id = waybill_row.order_id
  where cost_row.tenant_id = v_tenant_id
    and (p_record_id is null or cost_row.id = p_record_id)
    and (p_order_id is null or order_row.id = p_order_id)
    and (p_waybill_id is null or cost_row.waybill_id = p_waybill_id)
    and (p_carrier_id is null or cost_row.carrier_id = p_carrier_id)
    and (p_expense_item_id is null or cost_row.expense_item_id = p_expense_item_id)
    and (p_cost_type is null or cost_row.cost_type = p_cost_type)
    and (p_audit_status is null or cost_row.audit_status = p_audit_status)
    and (p_settlement_status is null or cost_row.settlement_status = p_settlement_status)
    and (p_occurred_on_start is null or cost_row.occurred_on >= p_occurred_on_start)
    and (p_occurred_on_end is null or cost_row.occurred_on <= p_occurred_on_end)
    and (p_ids is null or cost_row.id = any(p_ids))
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or cost_row.cost_no ilike '%' || btrim(p_keyword) || '%'
      or cost_row.payee_name ilike '%' || btrim(p_keyword) || '%'
      or cost_row.provider_name ilike '%' || btrim(p_keyword) || '%'
      or cost_row.invoice_no ilike '%' || btrim(p_keyword) || '%'
      or cost_row.waybill_no_snapshot ilike '%' || btrim(p_keyword) || '%'
      or cost_row.order_no_snapshot ilike '%' || btrim(p_keyword) || '%'
      or cost_row.plate_no_snapshot ilike '%' || btrim(p_keyword) || '%'
      or cost_row.driver_name_snapshot ilike '%' || btrim(p_keyword) || '%'
      or cost_row.remark ilike '%' || btrim(p_keyword) || '%'
      or waybill_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
      or order_row.order_no ilike '%' || btrim(p_keyword) || '%'
    );

  for v_row in
    select cost_row.id, cost_row.created_by_user_id
    from public.tms_waybill_cost cost_row
    left join public.tms_waybill waybill_row on waybill_row.id = cost_row.waybill_id
    left join public.tms_order order_row on order_row.id = waybill_row.order_id
    where cost_row.tenant_id = v_tenant_id
      and (p_record_id is null or cost_row.id = p_record_id)
      and (p_order_id is null or order_row.id = p_order_id)
      and (p_waybill_id is null or cost_row.waybill_id = p_waybill_id)
      and (p_carrier_id is null or cost_row.carrier_id = p_carrier_id)
      and (p_expense_item_id is null or cost_row.expense_item_id = p_expense_item_id)
      and (p_cost_type is null or cost_row.cost_type = p_cost_type)
      and (p_audit_status is null or cost_row.audit_status = p_audit_status)
      and (p_settlement_status is null or cost_row.settlement_status = p_settlement_status)
      and (p_occurred_on_start is null or cost_row.occurred_on >= p_occurred_on_start)
      and (p_occurred_on_end is null or cost_row.occurred_on <= p_occurred_on_end)
      and (p_ids is null or cost_row.id = any(p_ids))
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or cost_row.cost_no ilike '%' || btrim(p_keyword) || '%'
        or cost_row.payee_name ilike '%' || btrim(p_keyword) || '%'
        or cost_row.provider_name ilike '%' || btrim(p_keyword) || '%'
        or cost_row.invoice_no ilike '%' || btrim(p_keyword) || '%'
        or cost_row.waybill_no_snapshot ilike '%' || btrim(p_keyword) || '%'
        or cost_row.order_no_snapshot ilike '%' || btrim(p_keyword) || '%'
        or cost_row.plate_no_snapshot ilike '%' || btrim(p_keyword) || '%'
        or cost_row.driver_name_snapshot ilike '%' || btrim(p_keyword) || '%'
        or cost_row.remark ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
        or order_row.order_no ilike '%' || btrim(p_keyword) || '%'
      )
    order by cost_row.occurred_on desc, cost_row.create_time desc, cost_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.tms_waybill_cost_to_secure_json(
        app_private.tms_waybill_cost_raw_json(v_row.id),
        v_row.created_by_user_id
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', coalesce(v_total, 0),
    'field_access', v_base_access
  );
end;
$$;

create or replace function public.tms_get_waybill_cost_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_raw jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', 'FinanceWaybillCost:View', null, false
  ) then
    raise exception 'Missing waybill cost view permission' using errcode = '42501';
  end if;
  select created_by_user_id into v_owner_id
  from public.tms_waybill_cost
  where id = p_id and tenant_id = app_private.current_user_tenant_id();
  if not found then return null; end if;
  v_raw := app_private.tms_waybill_cost_raw_json(p_id);
  return app_private.tms_waybill_cost_to_secure_json(v_raw, v_owner_id);
end;
$$;

create or replace function public.tms_get_waybill_cost_overview_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb;
  v_data jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', null, null, false
  ) then
    raise exception 'Missing waybill cost menu permission' using errcode = '42501';
  end if;
  v_access := app_private.field_access_map('tms.waybill_cost', null);
  select jsonb_build_object(
    'total_count', count(*)::integer,
    'pending_review_count', count(*) filter (
      where cost_row.audit_status = 'pending_review'
    )::integer,
    'approved_unconverted_count', count(*) filter (
      where cost_row.audit_status = 'approved'
        and cost_row.settlement_status = 'unsettled'
        and item_row.reimbursement_allowed
    )::integer,
    'pending_payment_amount', coalesce(sum(cost_row.amount) filter (
      where cost_row.settlement_status = 'pending_payment'
    ), 0)::numeric(14, 2),
    'paid_amount', coalesce(sum(cost_row.amount) filter (
      where cost_row.settlement_status = 'paid'
    ), 0)::numeric(14, 2)
  ) into v_data
  from public.tms_waybill_cost cost_row
  join public.tms_expense_item item_row on item_row.id = cost_row.expense_item_id
  where cost_row.tenant_id = v_tenant_id
    and cost_row.audit_status <> 'voided';
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['pending_payment_amount', 'paid_amount']::text[],
    coalesce(v_access->>'costAmounts', 'hidden')
  );
  return v_data || jsonb_build_object('field_access', v_access);
end;
$$;

create or replace function public.tms_list_waybill_cost_options_secure(
  p_from integer default 0,
  p_to integer default 99,
  p_keyword text default null,
  p_order_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 99) - v_from + 1, 1), 500);
  v_total integer;
  v_records jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', null, null, false
  ) then
    raise exception 'Missing waybill cost menu permission' using errcode = '42501';
  end if;
  select count(*)::integer into v_total
  from public.tms_waybill waybill_row
  left join public.tms_order order_row on order_row.id = waybill_row.order_id
  where waybill_row.tenant_id = v_tenant_id
    and waybill_row.status <> 'cancelled'
    and (p_order_id is null or waybill_row.order_id = p_order_id)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or waybill_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
      or waybill_row.origin_city ilike '%' || btrim(p_keyword) || '%'
      or waybill_row.destination_city ilike '%' || btrim(p_keyword) || '%'
      or order_row.order_no ilike '%' || btrim(p_keyword) || '%'
      or order_row.dispatch_plate_no ilike '%' || btrim(p_keyword) || '%'
      or order_row.dispatch_driver_name ilike '%' || btrim(p_keyword) || '%'
    );
  select coalesce(jsonb_agg(option_row.data order by option_row.create_time desc), '[]'::jsonb)
  into v_records
  from (
    select waybill_row.create_time, jsonb_build_object(
      'id', waybill_row.id,
      'waybill_no', waybill_row.waybill_no,
      'status', waybill_row.status,
      'order_id', waybill_row.order_id,
      'carrier_id', waybill_row.carrier_id,
      'driver_id', waybill_row.driver_id,
      'origin_city', waybill_row.origin_city,
      'destination_city', waybill_row.destination_city,
      'completed_at', waybill_row.completed_at,
      'carrier', case when carrier_row.id is null then null else jsonb_build_object(
        'id', carrier_row.id, 'company_name', carrier_row.company_name
      ) end,
      'driver', case when driver_row.id is null then null else jsonb_build_object(
        'id', driver_row.id, 'driver_name', driver_row.driver_name
      ) end,
      'order', case when order_row.id is null then null else jsonb_build_object(
        'id', order_row.id,
        'order_no', order_row.order_no,
        'dispatch_plate_no', order_row.dispatch_plate_no,
        'dispatch_driver_name', order_row.dispatch_driver_name,
        'origin_station', order_row.origin_station,
        'destination_station', order_row.destination_station
      ) end
    ) data
    from public.tms_waybill waybill_row
    left join public.tms_order order_row on order_row.id = waybill_row.order_id
    left join public.tms_carrier carrier_row on carrier_row.id = waybill_row.carrier_id
    left join public.tms_driver driver_row on driver_row.id = waybill_row.driver_id
    where waybill_row.tenant_id = v_tenant_id
      and waybill_row.status <> 'cancelled'
      and (p_order_id is null or waybill_row.order_id = p_order_id)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or waybill_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.origin_city ilike '%' || btrim(p_keyword) || '%'
        or waybill_row.destination_city ilike '%' || btrim(p_keyword) || '%'
        or order_row.order_no ilike '%' || btrim(p_keyword) || '%'
        or order_row.dispatch_plate_no ilike '%' || btrim(p_keyword) || '%'
        or order_row.dispatch_driver_name ilike '%' || btrim(p_keyword) || '%'
      )
    order by waybill_row.create_time desc, waybill_row.id
    offset v_from limit v_limit
  ) option_row;
  return jsonb_build_object('records', v_records, 'total', coalesce(v_total, 0));
end;
$$;

create or replace function app_private.tms_waybill_profit_to_secure_json(
  p_profit jsonb,
  p_owner_id uuid,
  p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(
    p_access, app_private.field_access_map('tms.waybill_profit', p_owner_id)
  );
  v_data jsonb := coalesce(p_profit, '{}'::jsonb) - 'tenant_id' - 'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data, array['receivable_amount']::text[],
    coalesce(v_access->>'receivableAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'carrier_payable_amount', 'other_cost_amount', 'total_cost_amount'
    ]::text[],
    coalesce(v_access->>'costAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data, array['gross_profit', 'gross_margin']::text[],
    coalesce(v_access->>'profitAmounts', 'hidden')
  );
  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.tms_list_waybill_profits_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_keyword text default null,
  p_waybill_status text default null,
  p_completed_at_start timestamptz default null,
  p_completed_at_end timestamptz default null,
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
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1),
    case when p_purpose = 'export' then 10000 else 200 end
  );
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map('tms.waybill_profit', null);
  v_row record;
begin
  if p_purpose = 'export' then
    if not app_private.can_execute_business_action(
      'FinanceWaybillProfit', 'FinanceWaybillProfit:Export', null, false
    ) then
      raise exception 'Missing waybill profit export permission' using errcode = '42501';
    end if;
  elsif not app_private.can_execute_business_action(
    'FinanceWaybillProfit', null, null, false
  ) then
    raise exception 'Missing waybill profit menu permission' using errcode = '42501';
  end if;

  select count(*)::integer into v_total
  from public.tms_waybill_profit profit_row
  where profit_row.tenant_id = v_tenant_id
    and (p_waybill_status is null or profit_row.waybill_status = p_waybill_status)
    and (p_completed_at_start is null or profit_row.completed_at >= p_completed_at_start)
    and (p_completed_at_end is null or profit_row.completed_at <= p_completed_at_end)
    and (p_ids is null or profit_row.id = any(p_ids))
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or profit_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
      or profit_row.customer_name ilike '%' || btrim(p_keyword) || '%'
      or profit_row.carrier_name ilike '%' || btrim(p_keyword) || '%'
      or profit_row.plate_no ilike '%' || btrim(p_keyword) || '%'
      or profit_row.driver_name ilike '%' || btrim(p_keyword) || '%'
    );

  for v_row in
    select profit_row.*, waybill_row.created_by_user_id
    from public.tms_waybill_profit profit_row
    join public.tms_waybill waybill_row
      on waybill_row.id = profit_row.waybill_id
     and waybill_row.tenant_id = profit_row.tenant_id
    where profit_row.tenant_id = v_tenant_id
      and (p_waybill_status is null or profit_row.waybill_status = p_waybill_status)
      and (p_completed_at_start is null or profit_row.completed_at >= p_completed_at_start)
      and (p_completed_at_end is null or profit_row.completed_at <= p_completed_at_end)
      and (p_ids is null or profit_row.id = any(p_ids))
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or profit_row.waybill_no ilike '%' || btrim(p_keyword) || '%'
        or profit_row.customer_name ilike '%' || btrim(p_keyword) || '%'
        or profit_row.carrier_name ilike '%' || btrim(p_keyword) || '%'
        or profit_row.plate_no ilike '%' || btrim(p_keyword) || '%'
        or profit_row.driver_name ilike '%' || btrim(p_keyword) || '%'
      )
    order by profit_row.create_time desc, profit_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.tms_waybill_profit_to_secure_json(
        to_jsonb(v_row) - 'created_by_user_id', v_row.created_by_user_id
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', coalesce(v_total, 0),
    'field_access', v_base_access
  );
end;
$$;

create or replace function public.tms_get_waybill_profit_ai_evidence_secure(
  p_limit integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'FinanceWaybillProfit', 'FinanceWaybillProfit:AiProfitAnalysis', null, false
  ) then
    raise exception 'Missing waybill profit AI permission' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(permitted) - 'created_by_user_id'
      order by permitted.create_time desc, permitted.id)
    from (
      select profit_row.*, waybill_row.created_by_user_id
      from public.tms_waybill_profit profit_row
      join public.tms_waybill waybill_row
        on waybill_row.id = profit_row.waybill_id
       and waybill_row.tenant_id = profit_row.tenant_id
      where profit_row.tenant_id = v_tenant_id
        and profit_row.waybill_status <> 'cancelled'
        and app_private.resolve_field_access(
          'tms.waybill_profit', 'receivableAmounts', waybill_row.created_by_user_id
        ) in ('read', 'edit')
        and app_private.resolve_field_access(
          'tms.waybill_profit', 'costAmounts', waybill_row.created_by_user_id
        ) in ('read', 'edit')
        and app_private.resolve_field_access(
          'tms.waybill_profit', 'profitAmounts', waybill_row.created_by_user_id
        ) in ('read', 'edit')
      order by profit_row.create_time desc, profit_row.id
      limit least(300, greatest(coalesce(p_limit, 300), 1))
    ) permitted
  ), '[]'::jsonb);
end;
$$;

create or replace function public.tms_get_waybill_cost_ai_evidence_secure(p_cost_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_cost public.tms_waybill_cost%rowtype;
  v_access jsonb;
  v_cost_json jsonb;
  v_siblings jsonb;
  v_references jsonb;
  v_profit jsonb;
  v_profit_owner uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', 'FinanceWaybillCost:AiAudit', null, false
  ) then
    raise exception 'Missing waybill cost AI audit permission' using errcode = '42501';
  end if;
  select cost_row.* into v_cost
  from public.tms_waybill_cost cost_row
  where cost_row.id = p_cost_id and cost_row.tenant_id = v_tenant_id;
  if not found then return null; end if;
  v_access := app_private.field_access_map('tms.waybill_cost', v_cost.created_by_user_id);
  if coalesce(v_access->>'costAmounts', 'hidden') not in ('read', 'edit')
     or coalesce(v_access->>'paymentDetails', 'hidden') not in ('read', 'edit')
     or coalesce(v_access->>'expenseEvidence', 'hidden') not in ('read', 'edit') then
    raise exception '当前字段权限不足，无法读取费用金额、收款信息或票据依据进行 AI 审核'
      using errcode = '42501';
  end if;

  select (to_jsonb(v_cost) - 'tenant_id' - 'created_by_user_id') || jsonb_build_object(
    'waybill', jsonb_build_object(
      'id', waybill_row.id,
      'waybill_no', waybill_row.waybill_no,
      'origin_city', waybill_row.origin_city,
      'destination_city', waybill_row.destination_city,
      'order', case when order_row.id is null then null else jsonb_build_object(
        'id', order_row.id,
        'origin_station', order_row.origin_station,
        'destination_station', order_row.destination_station
      ) end
    )
  ) into v_cost_json
  from public.tms_waybill waybill_row
  left join public.tms_order order_row on order_row.id = waybill_row.order_id
  where waybill_row.id = v_cost.waybill_id and waybill_row.tenant_id = v_tenant_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', sibling.id,
    'waybill_id', sibling.waybill_id,
    'cost_type', sibling.cost_type,
    'amount', sibling.amount,
    'occurred_on', sibling.occurred_on,
    'payee_name', case
      when app_private.resolve_field_access(
        'tms.waybill_cost', 'paymentDetails', sibling.created_by_user_id
      ) in ('read', 'edit') then sibling.payee_name else null end,
    'audit_status', sibling.audit_status
  ) order by sibling.occurred_on desc, sibling.id), '[]'::jsonb)
  into v_siblings
  from public.tms_waybill_cost sibling
  where sibling.tenant_id = v_tenant_id
    and sibling.waybill_id = v_cost.waybill_id
    and app_private.resolve_field_access(
      'tms.waybill_cost', 'costAmounts', sibling.created_by_user_id
    ) in ('read', 'edit');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', reference_row.id, 'amount', reference_row.amount
  ) order by reference_row.occurred_on desc, reference_row.id), '[]'::jsonb)
  into v_references
  from (
    select cost_row.*
    from public.tms_waybill_cost cost_row
    where cost_row.tenant_id = v_tenant_id
      and cost_row.cost_type = v_cost.cost_type
      and cost_row.audit_status = 'approved'
      and app_private.resolve_field_access(
        'tms.waybill_cost', 'costAmounts', cost_row.created_by_user_id
      ) in ('read', 'edit')
    order by cost_row.occurred_on desc, cost_row.id
    limit 100
  ) reference_row;

  select waybill_row.created_by_user_id into v_profit_owner
  from public.tms_waybill waybill_row
  where waybill_row.id = v_cost.waybill_id and waybill_row.tenant_id = v_tenant_id;
  if app_private.resolve_field_access(
       'tms.waybill_profit', 'receivableAmounts', v_profit_owner
     ) in ('read', 'edit')
     and app_private.resolve_field_access(
       'tms.waybill_profit', 'costAmounts', v_profit_owner
     ) in ('read', 'edit')
     and app_private.resolve_field_access(
       'tms.waybill_profit', 'profitAmounts', v_profit_owner
     ) in ('read', 'edit') then
    select to_jsonb(profit_row) - 'tenant_id' into v_profit
    from public.tms_waybill_profit profit_row
    where profit_row.tenant_id = v_tenant_id
      and profit_row.waybill_id = v_cost.waybill_id;
  end if;

  return jsonb_build_object(
    'cost', v_cost_json,
    'sibling_costs', v_siblings,
    'reference_costs', v_references,
    'profit', v_profit
  );
end;
$$;

create or replace function public.tms_list_carrier_cost_ai_evidence_secure(
  p_carrier_id uuid,
  p_limit integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'TmsCarrierDetail', 'TmsCarrierDetail:AiAnalyze', null, false
  ) then
    raise exception 'Missing carrier AI analyze permission' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.tms_carrier carrier_row
    where carrier_row.id = p_carrier_id and carrier_row.tenant_id = v_tenant_id
  ) then
    raise exception '承运商不存在或无权访问';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', permitted.id,
      'waybill_id', permitted.waybill_id,
      'amount', permitted.amount,
      'audit_status', permitted.audit_status,
      'occurred_on', permitted.occurred_on,
      'create_time', permitted.create_time
    ) order by permitted.create_time desc, permitted.id)
    from (
      select cost_row.*
      from public.tms_waybill_cost cost_row
      where cost_row.tenant_id = v_tenant_id
        and cost_row.carrier_id = p_carrier_id
        and app_private.resolve_field_access(
          'tms.waybill_cost', 'costAmounts', cost_row.created_by_user_id
        ) in ('read', 'edit')
      order by cost_row.create_time desc, cost_row.id
      limit least(300, greatest(coalesce(p_limit, 300), 1))
    ) permitted
  ), '[]'::jsonb);
end;
$$;

create or replace function app_private.get_waybill_cost_workflow_snapshot(
  p_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_instance public.wf_instance%rowtype;
  v_cost record;
  v_access jsonb;
  v_amount_level text;
  v_payment_level text;
  v_evidence_level text;
  v_metrics jsonb := '[]'::jsonb;
  v_fields jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_attachments jsonb := '[]'::jsonb;
begin
  if auth.uid() is null or not app_private.can_view_workflow_instance(p_instance_id) then
    raise exception '无权查看该审批业务信息' using errcode = '42501';
  end if;
  select instance_row.* into v_instance
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;
  if not found then raise exception '审批实例不存在'; end if;

  select
    cost_row.*,
    waybill_row.waybill_no,
    item_row.item_name as expense_item_label
  into v_cost
  from public.tms_waybill_cost cost_row
  left join public.tms_waybill waybill_row
    on waybill_row.id = cost_row.waybill_id
   and waybill_row.tenant_id = cost_row.tenant_id
  left join public.tms_expense_item item_row
    on item_row.id = cost_row.expense_item_id
   and item_row.tenant_id = cost_row.tenant_id
  where cost_row.id = v_instance.business_id
    and cost_row.tenant_id = v_instance.tenant_id;

  if not found then
    return jsonb_build_object(
      'instanceId', v_instance.id,
      'businessType', v_instance.business_type,
      'businessId', v_instance.business_id,
      'title', v_instance.business_title,
      'subtitle', null,
      'businessNo', null,
      'status', null,
      'routePath', '/tms-transportation/finance-center/waybill-cost',
      'metrics', '[]'::jsonb,
      'fields', '[]'::jsonb,
      'warnings', jsonb_build_array('业务原单已删除，当前仅展示流程基本信息'),
      'attachments', '[]'::jsonb
    );
  end if;

  v_access := app_private.field_access_map(
    'tms.waybill_cost', v_cost.created_by_user_id
  );
  v_amount_level := coalesce(v_access->>'costAmounts', 'hidden');
  v_payment_level := coalesce(v_access->>'paymentDetails', 'hidden');
  v_evidence_level := coalesce(v_access->>'expenseEvidence', 'hidden');

  if v_amount_level <> 'hidden' then
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object(
      'label', '费用金额',
      'value', case
        when v_amount_level = 'masked' then '***'
        else '¥ ' || to_char(coalesce(v_cost.amount, 0), 'FM999,999,990.00')
      end,
      'tone', 'warning'
    ));
    if v_amount_level = 'masked' then
      v_warnings := v_warnings || jsonb_build_array('费用金额已按字段权限脱敏');
    end if;
  end if;
  v_metrics := v_metrics || jsonb_build_array(jsonb_build_object(
    'label', '发生日期',
    'value', coalesce(v_cost.occurred_on::text, '--'),
    'tone', 'info'
  ));

  v_fields := jsonb_build_array(
    jsonb_build_object('label', '运单号', 'value', coalesce(v_cost.waybill_no, '--')),
    jsonb_build_object('label', '费用项目', 'value', coalesce(v_cost.expense_item_label, '--')),
    jsonb_build_object('label', '备注', 'value', coalesce(v_cost.remark, '--'))
  );
  if v_payment_level <> 'hidden' then
    v_fields := v_fields || jsonb_build_array(jsonb_build_object(
      'label', '收款方',
      'value', case
        when v_payment_level = 'masked' then '***'
        else coalesce(v_cost.payee_name, '--')
      end
    ));
  end if;
  if v_evidence_level in ('read', 'edit') then
    v_attachments := app_private.workflow_attachment_list(v_cost.attachments);
  elsif jsonb_array_length(coalesce(v_cost.attachments, '[]'::jsonb)) > 0 then
    v_warnings := v_warnings || jsonb_build_array('费用票据已按字段权限隐藏');
  end if;

  return jsonb_build_object(
    'instanceId', v_instance.id,
    'businessType', v_instance.business_type,
    'businessId', v_instance.business_id,
    'title', v_instance.business_title,
    'subtitle', concat_ws(' · ', v_cost.expense_item_label,
      case when v_payment_level in ('read', 'edit') then v_cost.payee_name else null end),
    'businessNo', coalesce(v_cost.cost_no, v_cost.waybill_no),
    'status', v_cost.audit_status,
    'routePath', '/tms-transportation/finance-center/waybill-cost',
    'metrics', v_metrics,
    'fields', v_fields,
    'warnings', v_warnings,
    'attachments', v_attachments
  );
end;
$$;

create or replace function app_private.get_workflow_business_snapshot_v2(
  p_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_business_id uuid;
  v_snapshot jsonb;
  v_ocr record;
  v_access jsonb;
  v_include_ocr boolean := true;
begin
  select instance_row.business_type, instance_row.business_id
  into v_type, v_business_id
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;

  if v_type = 'tms_carrier_payment_application' then
    v_snapshot := app_private.get_carrier_payment_application_workflow_snapshot(
      p_instance_id
    );
    select app_private.field_access_map(
      'tms.carrier_payment_application', application_row.created_by_user_id
    ) into v_access
    from public.tms_carrier_payment_application application_row
    where application_row.id = v_business_id;
    v_include_ocr := found
      and coalesce(v_access->>'applicationAmounts', 'hidden') in ('read', 'edit')
      and coalesce(v_access->>'basisEvidence', 'hidden') in ('read', 'edit');
  elsif v_type = 'tms_waybill_cost' then
    v_snapshot := app_private.get_waybill_cost_workflow_snapshot(p_instance_id);
    select app_private.field_access_map(
      'tms.waybill_cost', cost_row.created_by_user_id
    ) into v_access
    from public.tms_waybill_cost cost_row
    where cost_row.id = v_business_id;
    v_include_ocr := found
      and coalesce(v_access->>'costAmounts', 'hidden') in ('read', 'edit')
      and coalesce(v_access->>'paymentDetails', 'hidden') in ('read', 'edit')
      and coalesce(v_access->>'expenseLocation', 'hidden') in ('read', 'edit')
      and coalesce(v_access->>'expenseEvidence', 'hidden') in ('read', 'edit');
  elsif v_type = 'tms_contract' then
    v_snapshot := app_private.get_contract_workflow_snapshot(p_instance_id);
  else
    v_snapshot := app_private.get_workflow_business_snapshot(p_instance_id);
  end if;

  if v_include_ocr then
    select
      artifact_row.id,
      artifact_row.raw_ocr_text,
      artifact_row.create_time
    into v_ocr
    from public.ai_artifact_review artifact_row
    where artifact_row.entity_type = v_type
      and artifact_row.entity_id = v_business_id
      and artifact_row.status = 'applied'
    order by artifact_row.reviewed_at desc nulls last, artifact_row.create_time desc
    limit 1;
    if found then
      v_snapshot := v_snapshot || jsonb_build_object(
        'ocrEvidence', jsonb_build_object(
          'artifactId', v_ocr.id,
          'rawText', coalesce(v_ocr.raw_ocr_text, ''),
          'capturedAt', v_ocr.create_time
        )
      );
    end if;
  end if;
  return v_snapshot;
end;
$$;

revoke select, insert, update, delete on table public.tms_waybill_cost
  from public, anon, authenticated;
revoke select on table public.tms_waybill_cost_overview
  from public, anon, authenticated;
revoke select on table public.tms_waybill_profit
  from public, anon, authenticated;

grant select, insert, update, delete on table public.tms_waybill_cost to service_role;
grant select on table public.tms_waybill_cost_overview to service_role;
grant select on table public.tms_waybill_profit to service_role;

revoke all on function public.tms_list_waybill_costs_secure(
  integer, integer, uuid, uuid, uuid, uuid, uuid, text, text, text,
  date, date, text, uuid[], text
) from public, anon;
revoke all on function public.tms_get_waybill_cost_secure(uuid) from public, anon;
revoke all on function public.tms_get_waybill_cost_overview_secure() from public, anon;
revoke all on function public.tms_list_waybill_cost_options_secure(
  integer, integer, text, uuid
) from public, anon;
revoke all on function public.tms_save_waybill_cost_secure(uuid, jsonb) from public, anon;
revoke all on function public.tms_delete_waybill_cost_secure(uuid) from public, anon;
revoke all on function public.tms_void_waybill_cost_secure(uuid, text) from public, anon;
revoke all on function public.validate_tms_waybill_cost_submission_secure(uuid)
  from public, anon;
revoke all on function public.tms_list_waybill_profits_secure(
  integer, integer, text, text, timestamptz, timestamptz, uuid[], text
) from public, anon;
revoke all on function public.tms_get_waybill_profit_ai_evidence_secure(integer)
  from public, anon;
revoke all on function public.tms_get_waybill_cost_ai_evidence_secure(uuid)
  from public, anon;
revoke all on function public.tms_list_carrier_cost_ai_evidence_secure(uuid, integer)
  from public, anon;

grant execute on function public.tms_list_waybill_costs_secure(
  integer, integer, uuid, uuid, uuid, uuid, uuid, text, text, text,
  date, date, text, uuid[], text
) to authenticated, service_role;
grant execute on function public.tms_get_waybill_cost_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_get_waybill_cost_overview_secure()
  to authenticated, service_role;
grant execute on function public.tms_list_waybill_cost_options_secure(
  integer, integer, text, uuid
) to authenticated, service_role;
grant execute on function public.tms_save_waybill_cost_secure(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.tms_delete_waybill_cost_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_void_waybill_cost_secure(uuid, text)
  to authenticated, service_role;
grant execute on function public.validate_tms_waybill_cost_submission_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_list_waybill_profits_secure(
  integer, integer, text, text, timestamptz, timestamptz, uuid[], text
) to authenticated, service_role;
grant execute on function public.tms_get_waybill_profit_ai_evidence_secure(integer)
  to authenticated, service_role;
grant execute on function public.tms_get_waybill_cost_ai_evidence_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_list_carrier_cost_ai_evidence_secure(uuid, integer)
  to authenticated, service_role;

revoke all on function public.start_workflow(text, uuid, text, jsonb, text)
  from public, anon;
grant execute on function public.start_workflow(text, uuid, text, jsonb, text)
  to authenticated, service_role;
revoke all on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) from public, anon;
grant execute on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) to authenticated, service_role;

do $$
begin
  if exists (
    select 1 from public.tms_waybill_cost where created_by_user_id is null
  ) then
    raise exception 'Waybill cost creator backfill is incomplete';
  end if;
  if (
    select count(*)
    from public.sys_permission_resource resource_row
    join public.sys_permission_field field_row
      on field_row.resource_id = resource_row.id
     and field_row.tenant_id = resource_row.tenant_id
    where resource_row.resource_key = 'tms.waybill_cost'
      and field_row.enabled
  ) < (select count(*) * 5 from public.sys_tenant) then
    raise exception 'Waybill cost field permission catalog is incomplete';
  end if;
  if (
    select count(*)
    from public.sys_permission_resource resource_row
    join public.sys_permission_field field_row
      on field_row.resource_id = resource_row.id
     and field_row.tenant_id = resource_row.tenant_id
    where resource_row.resource_key = 'tms.waybill_profit'
      and field_row.enabled
  ) < (select count(*) * 3 from public.sys_tenant) then
    raise exception 'Waybill profit field permission catalog is incomplete';
  end if;
end;
$$;

;
