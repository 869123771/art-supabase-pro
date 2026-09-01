-- A reimbursement is an auditable document for exactly one waybill. The RPC keeps
-- validation, snapshot insertion and source-cost reservation in one transaction.
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
  v_user_id uuid := app_private.current_app_user_id();
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);
  v_actor_name text;
  v_id uuid;
  v_selected_count integer;
  v_eligible_count integer;
  v_waybill_count integer;
  v_total numeric(14,2);
begin
  if auth.uid() is null or v_tenant_id is null or v_user_id is null then
    raise exception '请登录后操作';
  end if;
  if (select app_private.is_driver_user()) then
    raise exception '司机账号仅可查看本人费用，不能生成费用报销单';
  end if;
  if coalesce(array_length(p_cost_ids, 1), 0) = 0 then
    raise exception '请选择要转报销的运单费用';
  end if;
  if nullif(btrim(coalesce(p_payee_name, '')), '') is null then
    raise exception '请填写收款人';
  end if;
  if p_planned_payment_date is null then
    raise exception '请选择计划付款日期';
  end if;
  if p_payment_method not in ('bank_transfer', 'cash', 'wechat', 'alipay', 'other') then
    raise exception '付款方式不正确';
  end if;
  if jsonb_typeof(coalesce(p_basis_urls, '[]'::jsonb)) <> 'array' then
    raise exception '报销依据格式不正确';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant_id::text || ':expense-reimbursement', 841331)
  );
  perform 1
  from public.tms_waybill_cost
  where id = any(p_cost_ids) and tenant_id = v_tenant_id
  order by id
  for update;

  select count(*)::integer, count(distinct c.waybill_id)::integer
  into v_selected_count, v_waybill_count
  from public.tms_waybill_cost c
  where c.id = any(p_cost_ids)
    and c.tenant_id = v_tenant_id;

  if v_selected_count <> cardinality(p_cost_ids) then
    raise exception '所选费用不存在、重复或无权访问，请刷新后重新选择';
  end if;
  if v_waybill_count <> 1 then
    raise exception '一张费用报销单只能包含同一个运单的费用';
  end if;

  select count(*)::integer, coalesce(sum(c.amount), 0)::numeric(14,2)
  into v_eligible_count, v_total
  from public.tms_waybill_cost c
  join public.tms_expense_item item on item.id = c.expense_item_id
  where c.id = any(p_cost_ids)
    and c.tenant_id = v_tenant_id
    and c.audit_status = 'approved'
    and c.settlement_status = 'unsettled'
    and c.reimbursement_id is null
    and c.expense_payment_id is null
    and item.reimbursement_allowed;

  if v_eligible_count <> cardinality(p_cost_ids) then
    raise exception '仅已审核、未结算且允许报销的运单费用可以转换，请刷新后重试';
  end if;

  select coalesce(nullif(nick_name, ''), nullif(user_name, ''), user_email, id::text)
  into v_actor_name
  from public.sys_user
  where id = v_user_id;

  insert into public.tms_expense_reimbursement(
    tenant_id,
    reimbursement_no,
    applicant_user_id,
    applicant_name_snapshot,
    payee_name,
    payee_bank,
    payee_account,
    planned_payment_date,
    payment_method,
    total_amount,
    basis_urls,
    remark,
    create_by,
    update_by
  ) values (
    v_tenant_id,
    '',
    v_user_id,
    v_actor_name,
    btrim(p_payee_name),
    nullif(btrim(coalesce(p_payee_bank, '')), ''),
    nullif(btrim(coalesce(p_payee_account, '')), ''),
    p_planned_payment_date,
    p_payment_method,
    v_total,
    coalesce(p_basis_urls, '[]'::jsonb),
    nullif(btrim(coalesce(p_remark, '')), ''),
    v_actor,
    v_actor
  )
  returning id into v_id;

  insert into public.tms_expense_reimbursement_item(
    tenant_id,
    reimbursement_id,
    cost_id,
    waybill_id,
    cost_no_snapshot,
    waybill_no_snapshot,
    expense_item_name_snapshot,
    amount_snapshot,
    occurred_on_snapshot,
    create_by,
    update_by
  )
  select
    c.tenant_id,
    v_id,
    c.id,
    c.waybill_id,
    c.cost_no,
    c.waybill_no_snapshot,
    item.item_name,
    c.amount,
    c.occurred_on,
    v_actor,
    v_actor
  from public.tms_waybill_cost c
  join public.tms_expense_item item on item.id = c.expense_item_id
  where c.id = any(p_cost_ids)
    and c.tenant_id = v_tenant_id;

  update public.tms_waybill_cost
  set reimbursement_id = v_id,
      settlement_status = 'pending_payment'
  where id = any(p_cost_ids)
    and tenant_id = v_tenant_id;

  return v_id;
end;
$$;

revoke all on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) from public, anon;
grant execute on function public.create_tms_expense_reimbursement(
  uuid[], text, text, text, date, text, jsonb, text
) to authenticated;

-- Add a first-class navigation entry while reusing the canonical reimbursement
-- workspace already hosted by the waybill-cost component.
insert into public.sys_menu(
  id,
  parent_id,
  name,
  path,
  component,
  meta,
  sort,
  type,
  create_by,
  update_by
)
select
  gen_random_uuid(),
  finance.id,
  'TmsExpenseReimbursement',
  'expense-reimbursement',
  '/tms-transportation/finance-center/waybill-cost',
  jsonb_build_object(
    'icon', 'ri:refund-2-line',
    'title', '费用报销单',
    'is_enable', true,
    'keep_alive', true
  ),
  8,
  'menu',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_menu finance
where finance.name = 'TmsFinanceCenter'
  and not exists (
    select 1 from public.sys_menu existing
    where existing.name = 'TmsExpenseReimbursement'
  );

update public.sys_menu
set sort = case name
  when 'TmsWaybillProfit' then 9
  when 'TmsExpenseItem' then 10
  else sort
end,
update_by = '624944977@qq.com',
update_time = now()
where name in ('TmsWaybillProfit', 'TmsExpenseItem');

insert into public.sys_role_menu(
  id,
  role_id,
  menu_id,
  permission,
  tenant_id,
  create_by,
  update_by
)
select
  gen_random_uuid(),
  source.role_id,
  target.id,
  source.permission,
  source.tenant_id,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu source
join public.sys_menu source_menu on source_menu.id = source.menu_id
cross join public.sys_menu target
where source_menu.name = 'TmsWaybillCost'
  and target.name = 'TmsExpenseReimbursement'
on conflict (role_id, menu_id) do nothing;

;
