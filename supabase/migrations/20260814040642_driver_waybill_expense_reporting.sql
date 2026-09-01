-- Driver expense reporting reuses the canonical tms_waybill_cost ledger and
-- workflow. Drivers can only read their own reports; all writes go through the
-- guarded RPC below so Web finance behavior remains unchanged.

create or replace function app_private.is_driver_user()
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
      and u.deleted_at is null
      and u.user_type = '2'
  );
$$;

revoke all on function app_private.is_driver_user() from public;
grant execute on function app_private.is_driver_user() to authenticated, service_role;

drop policy if exists tms_expense_item_tenant_insert on public.tms_expense_item;
create policy tms_expense_item_tenant_insert
on public.tms_expense_item
for insert
to authenticated
with check (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and not (select app_private.is_driver_user())
  )
);

drop policy if exists tms_expense_item_tenant_update on public.tms_expense_item;
create policy tms_expense_item_tenant_update
on public.tms_expense_item
for update
to authenticated
using (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and not (select app_private.is_driver_user())
  )
)
with check (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and not (select app_private.is_driver_user())
  )
);

drop policy if exists tms_expense_item_tenant_delete on public.tms_expense_item;
create policy tms_expense_item_tenant_delete
on public.tms_expense_item
for delete
to authenticated
using (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and not (select app_private.is_driver_user())
  )
);

drop policy if exists tms_waybill_cost_tenant_select on public.tms_waybill_cost;
create policy tms_waybill_cost_tenant_select
on public.tms_waybill_cost
for select
to authenticated
using (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      not (select app_private.is_driver_user())
      or (
        source_type = 'driver_report'
        and reporter_user_id = (select app_private.current_app_user_id())
        and driver_id = (select app_private.current_user_driver_id())
        and (select app_private.can_access_assigned_waybill(waybill_id))
      )
    )
  )
);

drop policy if exists tms_waybill_cost_tenant_insert on public.tms_waybill_cost;
create policy tms_waybill_cost_tenant_insert
on public.tms_waybill_cost
for insert
to authenticated
with check (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and not (select app_private.is_driver_user())
    and audit_status = 'draft'
    and exists (
      select 1
      from public.tms_waybill w
      where w.id = tms_waybill_cost.waybill_id
        and w.tenant_id = (select app_private.current_user_tenant_id())
    )
  )
);

drop policy if exists tms_waybill_cost_tenant_update on public.tms_waybill_cost;
create policy tms_waybill_cost_tenant_update
on public.tms_waybill_cost
for update
to authenticated
using (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and not (select app_private.is_driver_user())
    and audit_status <> 'voided'
  )
)
with check (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and not (select app_private.is_driver_user())
  )
);

drop policy if exists tms_waybill_cost_tenant_delete on public.tms_waybill_cost;
create policy tms_waybill_cost_tenant_delete
on public.tms_waybill_cost
for delete
to authenticated
using (
  app_private.is_platform_super()
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and not (select app_private.is_driver_user())
    and audit_status in ('draft', 'rejected')
  )
);

create or replace function public.start_workflow(
  p_business_type text,
  p_business_id uuid,
  p_business_title text,
  p_context jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
begin
  if (select app_private.is_driver_user()) then
    raise exception '司机端请通过对应的业务上报入口提交审批'
      using errcode = '42501';
  end if;

  return app_private.start_workflow(
    p_business_type,
    p_business_id,
    p_business_title,
    p_context,
    p_idempotency_key
  );
end;
$$;

create or replace function public.tms_get_driver_waybill_expense_context(
  p_waybill_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_driver_id uuid := app_private.current_user_driver_id();
  v_waybill public.tms_waybill;
  v_items jsonb;
  v_records jsonb;
  v_stats jsonb;
begin
  if (select auth.uid()) is null or v_user_id is null or v_tenant_id is null then
    raise exception '当前登录用户未绑定业务账号' using errcode = '42501';
  end if;
  if not (select app_private.is_driver_user()) or v_driver_id is null then
    raise exception '当前账号未绑定有效司机档案' using errcode = '42501';
  end if;

  select w.*
  into v_waybill
  from public.tms_waybill w
  where w.id = p_waybill_id
    and w.tenant_id = v_tenant_id
    and w.driver_id = v_driver_id;

  if not found then
    raise exception '运单不存在或未分配给当前司机' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'item_code', i.item_code,
        'item_name', i.item_name,
        'parent_name', p.item_name,
        'business_category', i.business_category
      )
      order by coalesce(p.sort, 0), i.sort, i.item_name
    ),
    '[]'::jsonb
  )
  into v_items
  from public.tms_expense_item i
  left join public.tms_expense_item p
    on p.id = i.parent_id
   and p.tenant_id = i.tenant_id
  where i.tenant_id = v_tenant_id
    and i.is_enabled
    and i.is_selectable
    and i.reimbursement_allowed;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'cost_no', c.cost_no,
        'expense_item_id', c.expense_item_id,
        'expense_item_name', i.item_name,
        'expense_parent_name', p.item_name,
        'amount', c.amount,
        'occurred_on', c.occurred_on,
        'attachments', c.attachments,
        'audit_status', c.audit_status,
        'submitted_at', c.submitted_at,
        'reviewed_at', c.reviewed_at,
        'reviewed_by', c.reviewed_by,
        'review_remark', c.review_remark,
        'settlement_status', c.settlement_status,
        'paid_at', c.paid_at,
        'provider_name', c.provider_name,
        'payee_name', c.payee_name,
        'payment_channel', c.payment_channel,
        'invoice_no', c.invoice_no,
        'expense_location', c.expense_location,
        'remark', c.remark,
        'source_id', c.source_id,
        'create_time', c.create_time,
        'update_time', c.update_time
      )
      order by c.create_time desc
    ),
    '[]'::jsonb
  )
  into v_records
  from public.tms_waybill_cost c
  join public.tms_expense_item i
    on i.id = c.expense_item_id
   and i.tenant_id = c.tenant_id
  left join public.tms_expense_item p
    on p.id = i.parent_id
   and p.tenant_id = i.tenant_id
  where c.tenant_id = v_tenant_id
    and c.waybill_id = p_waybill_id
    and c.driver_id = v_driver_id
    and c.reporter_user_id = v_user_id
    and c.source_type = 'driver_report';

  select jsonb_build_object(
    'report_count', count(*) filter (where c.audit_status <> 'voided'),
    'total_amount', coalesce(sum(c.amount) filter (where c.audit_status <> 'voided'), 0),
    'pending_count', count(*) filter (where c.audit_status = 'pending_review'),
    'approved_amount', coalesce(sum(c.amount) filter (where c.audit_status = 'approved'), 0)
  )
  into v_stats
  from public.tms_waybill_cost c
  where c.tenant_id = v_tenant_id
    and c.waybill_id = p_waybill_id
    and c.driver_id = v_driver_id
    and c.reporter_user_id = v_user_id
    and c.source_type = 'driver_report';

  return jsonb_build_object(
    'waybill', jsonb_build_object(
      'id', v_waybill.id,
      'waybill_no', v_waybill.waybill_no,
      'status', v_waybill.status,
      'origin_city', v_waybill.origin_city,
      'destination_city', v_waybill.destination_city,
      'shipper_address', v_waybill.shipper_address,
      'receiver_address', v_waybill.receiver_address
    ),
    'can_report', v_waybill.status in (
      'accepted', 'loading', 'transporting', 'unloading', 'signed', 'completed'
    ),
    'expense_items', v_items,
    'records', v_records,
    'stats', v_stats
  );
end;
$$;

create or replace function public.tms_submit_driver_waybill_expense(
  p_waybill_id uuid,
  p_expense_item_id uuid,
  p_amount numeric,
  p_occurred_on date,
  p_attachments jsonb,
  p_idempotency_key text,
  p_cost_id uuid default null,
  p_provider_name text default null,
  p_payee_name text default null,
  p_payment_channel text default null,
  p_invoice_no text default null,
  p_expense_location text default null,
  p_expense_longitude numeric default null,
  p_expense_latitude numeric default null,
  p_expense_coordinate_system text default null,
  p_remark text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_driver_id uuid := app_private.current_user_driver_id();
  v_actor text := coalesce(nullif((select auth.jwt()) ->> 'email', ''), (select auth.uid())::text);
  v_waybill public.tms_waybill;
  v_item public.tms_expense_item;
  v_cost public.tms_waybill_cost;
  v_cost_id uuid;
  v_source_id uuid;
  v_storage_prefix text := 'waybill-expenses/' || (select auth.uid())::text || '/' || p_waybill_id::text || '/';
  v_public_url_prefix constant text := 'https://ckbftoopuyophiebamwy.supabase.co/storage/v1/object/public/attachments/';
begin
  if (select auth.uid()) is null or v_user_id is null or v_tenant_id is null then
    raise exception '当前登录用户未绑定业务账号' using errcode = '42501';
  end if;
  if not (select app_private.is_driver_user()) or v_driver_id is null then
    raise exception '当前账号未绑定有效司机档案' using errcode = '42501';
  end if;

  select w.*
  into v_waybill
  from public.tms_waybill w
  where w.id = p_waybill_id
    and w.tenant_id = v_tenant_id
    and w.driver_id = v_driver_id
  for update;

  if not found then
    raise exception '运单不存在或未分配给当前司机' using errcode = '42501';
  end if;
  if v_waybill.status not in (
    'accepted', 'loading', 'transporting', 'unloading', 'signed', 'completed'
  ) then
    raise exception '当前运单状态不允许上报费用';
  end if;

  select i.*
  into v_item
  from public.tms_expense_item i
  where i.id = p_expense_item_id
    and i.tenant_id = v_tenant_id
    and i.is_enabled
    and i.is_selectable
    and i.reimbursement_allowed;

  if not found then
    raise exception '请选择可报销且已启用的末级费用项目';
  end if;
  if p_amount is null or p_amount <= 0 or p_amount > 99999999.99 then
    raise exception '费用金额必须大于 0 且不超过 99999999.99 元';
  end if;
  if p_occurred_on is null or p_occurred_on > current_date then
    raise exception '费用发生日期不能为空或晚于今天';
  end if;
  if p_idempotency_key is null
     or length(btrim(p_idempotency_key)) < 8
     or length(btrim(p_idempotency_key)) > 160 then
    raise exception '提交标识无效，请刷新页面后重试';
  end if;
  if jsonb_typeof(p_attachments) <> 'array'
     or jsonb_array_length(p_attachments) < 1
     or jsonb_array_length(p_attachments) > 5 then
    raise exception '请上传 1 至 5 张费用凭证';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_attachments) x(value)
    where jsonb_typeof(x.value) <> 'string'
       or (x.value #>> '{}') not like v_public_url_prefix || v_storage_prefix || '%'
       or not exists (
         select 1
         from storage.objects o
         where o.bucket_id = 'attachments'
           and o.name = substring((x.value #>> '{}') from length(v_public_url_prefix) + 1)
           and o.name like v_storage_prefix || '%'
           and o.owner = (select auth.uid())
       )
  ) then
    raise exception '费用凭证无效，请重新上传';
  end if;
  if (p_expense_longitude is null) <> (p_expense_latitude is null) then
    raise exception '费用地点经纬度必须同时填写';
  end if;
  if p_expense_longitude is not null
     and (p_expense_longitude < -180 or p_expense_longitude > 180
       or p_expense_latitude < -90 or p_expense_latitude > 90) then
    raise exception '费用地点经纬度超出有效范围';
  end if;
  if p_expense_coordinate_system is not null
     and p_expense_coordinate_system not in ('gcj02', 'wgs84', 'bd09') then
    raise exception '费用地点坐标系无效';
  end if;
  if length(coalesce(p_provider_name, '')) > 100
     or length(coalesce(p_payee_name, '')) > 100
     or length(coalesce(p_payment_channel, '')) > 50
     or length(coalesce(p_invoice_no, '')) > 100
     or length(coalesce(p_expense_location, '')) > 300
     or length(coalesce(p_remark, '')) > 500 then
    raise exception '费用说明内容过长，请精简后提交';
  end if;

  if p_cost_id is null then
    v_source_id := md5(
      v_tenant_id::text || ':' || (select auth.uid())::text || ':' || btrim(p_idempotency_key)
    )::uuid;

    select c.*
    into v_cost
    from public.tms_waybill_cost c
    where c.tenant_id = v_tenant_id
      and c.source_type = 'driver_report'
      and c.source_id = v_source_id;

    if found then
      if v_cost.waybill_id <> p_waybill_id
         or v_cost.driver_id <> v_driver_id
         or v_cost.reporter_user_id <> v_user_id then
        raise exception '提交标识冲突，请刷新页面后重试';
      end if;
      return v_cost.id;
    end if;

    insert into public.tms_waybill_cost (
      tenant_id,
      waybill_id,
      cost_type,
      amount,
      occurred_on,
      payee_name,
      driver_id,
      remark,
      attachments,
      audit_status,
      source_type,
      source_id,
      reporter_user_id,
      expense_item_id,
      provider_name,
      payment_channel,
      invoice_no,
      expense_location,
      expense_longitude,
      expense_latitude,
      expense_coordinate_system,
      expense_coordinate_source,
      expense_coordinate_status,
      create_by,
      update_by
    ) values (
      v_tenant_id,
      p_waybill_id,
      v_item.business_category,
      round(p_amount, 2),
      p_occurred_on,
      nullif(btrim(p_payee_name), ''),
      v_driver_id,
      nullif(btrim(p_remark), ''),
      p_attachments,
      'draft',
      'driver_report',
      v_source_id,
      v_user_id,
      p_expense_item_id,
      nullif(btrim(p_provider_name), ''),
      nullif(btrim(p_payment_channel), ''),
      nullif(btrim(p_invoice_no), ''),
      nullif(btrim(p_expense_location), ''),
      p_expense_longitude,
      p_expense_latitude,
      p_expense_coordinate_system,
      case when p_expense_longitude is null then null else 'browser' end,
      case when p_expense_longitude is null then 'pending' else 'located' end,
      v_actor,
      v_actor
    )
    returning id into v_cost_id;
  else
    select c.*
    into v_cost
    from public.tms_waybill_cost c
    where c.id = p_cost_id
      and c.tenant_id = v_tenant_id
      and c.waybill_id = p_waybill_id
      and c.driver_id = v_driver_id
      and c.reporter_user_id = v_user_id
      and c.source_type = 'driver_report'
    for update;

    if not found then
      raise exception '费用记录不存在或不属于当前司机' using errcode = '42501';
    end if;

    if v_cost.audit_status not in ('draft', 'rejected') then
      if exists (
        select 1
        from public.wf_instance wi
        join public.wf_action wa on wa.instance_id = wi.id
        where wi.tenant_id = v_tenant_id
          and wi.business_type = 'tms_waybill_cost'
          and wi.business_id = v_cost.id
          and wa.idempotency_key = btrim(p_idempotency_key)
      ) then
        return v_cost.id;
      end if;
      raise exception '当前费用状态不允许修改或重新提交';
    end if;

    update public.tms_waybill_cost
    set expense_item_id = p_expense_item_id,
        amount = round(p_amount, 2),
        occurred_on = p_occurred_on,
        payee_name = nullif(btrim(p_payee_name), ''),
        provider_name = nullif(btrim(p_provider_name), ''),
        payment_channel = nullif(btrim(p_payment_channel), ''),
        invoice_no = nullif(btrim(p_invoice_no), ''),
        expense_location = nullif(btrim(p_expense_location), ''),
        expense_longitude = p_expense_longitude,
        expense_latitude = p_expense_latitude,
        expense_coordinate_system = p_expense_coordinate_system,
        expense_coordinate_source = case when p_expense_longitude is null then null else 'browser' end,
        expense_coordinate_status = case when p_expense_longitude is null then 'pending' else 'located' end,
        remark = nullif(btrim(p_remark), ''),
        attachments = p_attachments,
        update_by = v_actor,
        update_time = now()
    where id = v_cost.id;

    v_cost_id := v_cost.id;
  end if;

  perform app_private.start_workflow(
    'tms_waybill_cost',
    v_cost_id,
    '司机费用上报 · ' || v_waybill.waybill_no || ' · ' || v_item.item_name,
    jsonb_build_object(
      'source', 'driver_app',
      'driverId', v_driver_id,
      'expenseItemId', v_item.id,
      'expenseItemName', v_item.item_name
    ),
    btrim(p_idempotency_key)
  );

  return v_cost_id;
end;
$$;

revoke all on function public.tms_get_driver_waybill_expense_context(uuid) from public, anon;
grant execute on function public.tms_get_driver_waybill_expense_context(uuid) to authenticated;

revoke all on function public.tms_submit_driver_waybill_expense(
  uuid, uuid, numeric, date, jsonb, text, uuid, text, text, text, text, text,
  numeric, numeric, text, text
) from public, anon;
grant execute on function public.tms_submit_driver_waybill_expense(
  uuid, uuid, numeric, date, jsonb, text, uuid, text, text, text, text, text,
  numeric, numeric, text, text
) to authenticated;

comment on function public.tms_get_driver_waybill_expense_context(uuid)
is 'Returns driver-scoped expense items, waybill context, and the current driver own expense reports.';

comment on function public.tms_submit_driver_waybill_expense(
  uuid, uuid, numeric, date, jsonb, text, uuid, text, text, text, text, text,
  numeric, numeric, text, text
)
is 'Creates or resubmits a driver-owned waybill expense and starts the canonical tms_waybill_cost approval workflow.';

;
