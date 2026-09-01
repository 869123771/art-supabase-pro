begin;

create or replace function app_private.enqueue_fms_posting_event(
  p_tenant_id uuid,
  p_source_type text,
  p_event_code text,
  p_source_id uuid,
  p_source_no text,
  p_event_date date,
  p_summary text,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_id uuid;
  v_account_set_id uuid;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'system');
begin
  v_account_set_id := app_private.resolve_fms_posting_account_set(p_tenant_id);
  insert into public.fms_posting_event (
    tenant_id, account_set_id, source_type, event_code, source_id, source_no,
    event_date, summary, payload, status, create_by, update_by
  ) values (
    p_tenant_id, v_account_set_id, p_source_type, p_event_code, p_source_id,
    nullif(btrim(p_source_no), ''), p_event_date, btrim(p_summary),
    coalesce(p_payload, '{}'::jsonb),
    case when v_account_set_id is null then 'pending_configuration' else 'pending' end,
    v_actor, v_actor
  )
  on conflict (tenant_id, source_type, event_code, source_id) do update set
    account_set_id = coalesce(public.fms_posting_event.account_set_id, excluded.account_set_id),
    source_no = excluded.source_no,
    event_date = excluded.event_date,
    summary = excluded.summary,
    payload = excluded.payload,
    status = case
      when public.fms_posting_event.status in ('generated', 'reversed', 'ignored')
        then public.fms_posting_event.status
      when coalesce(public.fms_posting_event.account_set_id, excluded.account_set_id) is null
        then 'pending_configuration'
      else 'pending'
    end,
    update_by = excluded.update_by,
    update_time = now()
  returning id into v_event_id;
  perform app_private.process_fms_posting_event(v_event_id, false);
  return v_event_id;
end;
$$;

create or replace function app_private.capture_fms_customer_statement_posting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount numeric;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status = 'confirmed' then
    select coalesce(sum(line_amount), 0) into v_amount
    from public.tms_customer_statement_item where statement_id = new.id and is_active;
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'customer_statement', 'confirmed', new.id, new.statement_no,
      new.period_end, '客户对账确认 · ' || new.statement_no || ' · ' || new.customer_name_snapshot,
      jsonb_build_object(
        'gross_amount', v_amount, 'customer_id', new.customer_id,
        'customer_name', new.customer_name_snapshot, 'period_start', new.period_start,
        'period_end', new.period_end
      )
    );
  elsif new.status = 'voided' then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'customer_statement', 'voided', new.id, new.statement_no,
      current_date, '客户对账单作废 · ' || new.statement_no,
      jsonb_build_object('customer_id', new.customer_id, 'void_reason', new.void_reason)
    );
  end if;
  return new;
end;
$$;

create or replace function app_private.capture_fms_carrier_statement_posting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount numeric;
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status = 'confirmed' then
    select coalesce(sum(line_amount), 0) into v_amount
    from public.tms_carrier_statement_item where statement_id = new.id and is_active;
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'carrier_statement', 'confirmed', new.id, new.statement_no,
      new.period_end, '承运商对账确认 · ' || new.statement_no || ' · ' || new.carrier_name_snapshot,
      jsonb_build_object(
        'gross_amount', v_amount, 'carrier_id', new.carrier_id,
        'carrier_name', new.carrier_name_snapshot, 'period_start', new.period_start,
        'period_end', new.period_end
      )
    );
  elsif new.status = 'voided' then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'carrier_statement', 'voided', new.id, new.statement_no,
      current_date, '承运商对账单作废 · ' || new.statement_no,
      jsonb_build_object('carrier_id', new.carrier_id, 'void_reason', new.void_reason)
    );
  end if;
  return new;
end;
$$;

create or replace function app_private.capture_fms_cash_transaction_posting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_source_type text;
begin
  v_source_type := case when new.direction = 'receipt' then 'customer_receipt' else 'carrier_payment' end;
  if tg_op = 'INSERT' then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, v_source_type, 'recorded', new.id, new.transaction_no,
      new.transaction_date,
      case when new.direction = 'receipt' then '客户收款' else '承运商付款' end
        || ' · ' || new.transaction_no || ' · ' || new.counterparty_name_snapshot,
      jsonb_build_object(
        'gross_amount', new.amount, 'customer_id', new.customer_id,
        'carrier_id', new.carrier_id, 'counterparty_name', new.counterparty_name_snapshot,
        'payment_method', new.payment_method, 'bank_reference', new.bank_reference
      )
    );
  elsif new.status = 'voided' and old.status is distinct from new.status then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, v_source_type, 'voided', new.id, new.transaction_no,
      current_date, '收付款单作废 · ' || new.transaction_no,
      jsonb_build_object(
        'customer_id', new.customer_id, 'carrier_id', new.carrier_id,
        'void_reason', new.void_reason
      )
    );
  end if;
  return new;
end;
$$;

create or replace function app_private.capture_fms_invoice_posting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_code text;
begin
  if new.status is not distinct from old.status then return new; end if;
  if (new.direction = 'output' and new.status = 'issued')
    or (new.direction = 'input' and new.status = 'certified') then
    v_event_code := case when new.direction = 'output' then 'output_issued' else 'input_certified' end;
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'invoice', v_event_code, new.id, new.invoice_record_no,
      new.issue_date,
      case when new.direction = 'output' then '销项发票' else '进项发票' end
        || ' · ' || new.invoice_record_no || ' · ' || new.counterparty_name_snapshot,
      jsonb_build_object(
        'gross_amount', new.total_amount, 'net_amount', new.amount_excluding_tax,
        'tax_amount', new.tax_amount, 'direction', new.direction,
        'customer_id', new.customer_id, 'carrier_id', new.carrier_id,
        'counterparty_name', new.counterparty_name_snapshot,
        'invoice_no', new.invoice_no, 'tax_rate', new.tax_rate
      )
    );
  elsif new.status = 'voided' then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'invoice', 'voided', new.id, new.invoice_record_no,
      current_date, '发票作废 · ' || new.invoice_record_no,
      jsonb_build_object(
        'customer_id', new.customer_id, 'carrier_id', new.carrier_id,
        'void_reason', new.void_reason
      )
    );
  end if;
  return new;
end;
$$;

create or replace function app_private.capture_fms_expense_reimbursement_posting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status is not distinct from old.status then return new; end if;
  if new.status = 'paid' then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'expense_reimbursement', 'paid', new.id, new.reimbursement_no,
      coalesce(new.paid_at::date, current_date),
      '费用报销付款 · ' || new.reimbursement_no || ' · ' || new.payee_name,
      jsonb_build_object(
        'gross_amount', new.total_amount, 'applicant_user_id', new.applicant_user_id,
        'payee_name', new.payee_name, 'payment_method', new.payment_method,
        'payment_reference', new.payment_reference
      )
    );
  elsif new.status = 'cancelled' and old.status = 'paid' then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'expense_reimbursement', 'voided', new.id, new.reimbursement_no,
      current_date, '费用报销付款撤销 · ' || new.reimbursement_no,
      jsonb_build_object('applicant_user_id', new.applicant_user_id)
    );
  end if;
  return new;
end;
$$;

create or replace function app_private.capture_fms_waybill_cost_posting()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.audit_status is not distinct from old.audit_status then return new; end if;
  if new.audit_status = 'approved' then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'waybill_cost', 'approved', new.id, new.cost_no,
      new.occurred_on,
      '运单费用审核 · ' || new.cost_no || ' · ' || new.cost_type,
      jsonb_build_object(
        'gross_amount', new.amount, 'cost_type', new.cost_type,
        'waybill_id', new.waybill_id, 'carrier_id', new.carrier_id,
        'driver_id', new.driver_id, 'expense_item_id', new.expense_item_id,
        'payee_name', new.payee_name, 'waybill_no', new.waybill_no_snapshot
      )
    );
  elsif new.audit_status = 'voided' then
    perform app_private.enqueue_fms_posting_event(
      new.tenant_id, 'waybill_cost', 'voided', new.id, new.cost_no,
      current_date, '运单费用作废 · ' || new.cost_no,
      jsonb_build_object('waybill_id', new.waybill_id, 'cost_type', new.cost_type)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_fms_customer_statement_posting on public.tms_customer_statement;
create trigger trg_fms_customer_statement_posting
after update of status on public.tms_customer_statement
for each row execute function app_private.capture_fms_customer_statement_posting();

drop trigger if exists trg_fms_carrier_statement_posting on public.tms_carrier_statement;
create trigger trg_fms_carrier_statement_posting
after update of status on public.tms_carrier_statement
for each row execute function app_private.capture_fms_carrier_statement_posting();

drop trigger if exists trg_fms_cash_transaction_posting on public.tms_cash_transaction;
create trigger trg_fms_cash_transaction_posting
after insert or update of status on public.tms_cash_transaction
for each row execute function app_private.capture_fms_cash_transaction_posting();

drop trigger if exists trg_fms_invoice_posting on public.tms_invoice;
create trigger trg_fms_invoice_posting
after update of status on public.tms_invoice
for each row execute function app_private.capture_fms_invoice_posting();

drop trigger if exists trg_fms_expense_reimbursement_posting on public.tms_expense_reimbursement;
create trigger trg_fms_expense_reimbursement_posting
after update of status on public.tms_expense_reimbursement
for each row execute function app_private.capture_fms_expense_reimbursement_posting();

drop trigger if exists trg_fms_waybill_cost_posting on public.tms_waybill_cost;
create trigger trg_fms_waybill_cost_posting
after update of audit_status on public.tms_waybill_cost
for each row execute function app_private.capture_fms_waybill_cost_posting();

revoke all on function app_private.enqueue_fms_posting_event(uuid, text, text, uuid, text, date, text, jsonb) from public, anon, authenticated;
revoke all on function app_private.capture_fms_customer_statement_posting() from public, anon, authenticated;
revoke all on function app_private.capture_fms_carrier_statement_posting() from public, anon, authenticated;
revoke all on function app_private.capture_fms_cash_transaction_posting() from public, anon, authenticated;
revoke all on function app_private.capture_fms_invoice_posting() from public, anon, authenticated;
revoke all on function app_private.capture_fms_expense_reimbursement_posting() from public, anon, authenticated;
revoke all on function app_private.capture_fms_waybill_cost_posting() from public, anon, authenticated;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
)
select item.id, item.name, item.code, '1', '624944977@qq.com', '624944977@qq.com',
  platform_tenant.id, 'dictionary', item.sort, item.remark
from platform_tenant
cross join (values
  ('b2000000-0000-4000-8000-000000000013'::uuid, '自动入账业务事件', 'fmsPostingSourceEvent', 213, '可配置的 TMS 自动制证触发事件'),
  ('b2000000-0000-4000-8000-000000000014'::uuid, '自动入账提交模式', 'fmsPostingSubmissionMode', 214, '自动凭证生成后的状态'),
  ('b2000000-0000-4000-8000-000000000015'::uuid, '制证金额口径', 'fmsPostingAmountKey', 215, '制证分录的金额来源'),
  ('b2000000-0000-4000-8000-000000000016'::uuid, '自动入账事件状态', 'fmsPostingEventStatus', 216, '业务事件制证处理状态'),
  ('b2000000-0000-4000-8000-000000000017'::uuid, '运单费用业务类型', 'fmsPostingWaybillCostType', 217, '自动入账规则的运单费用匹配条件')
) as item(id, name, code, sort, remark)
on conflict (id) do update set
  name = excluded.name, code = excluded.code, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000101'::uuid, 'b2000000-0000-4000-8000-000000000013'::uuid, 'customer_statement:confirmed', '客户对账确认', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000102'::uuid, 'b2000000-0000-4000-8000-000000000013'::uuid, 'carrier_statement:confirmed', '承运商对账确认', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000103'::uuid, 'b2000000-0000-4000-8000-000000000013'::uuid, 'customer_receipt:recorded', '客户收款登记', 3, 'success'),
    ('c2000000-0000-4000-8000-000000000104'::uuid, 'b2000000-0000-4000-8000-000000000013'::uuid, 'carrier_payment:recorded', '承运商付款登记', 4, 'warning'),
    ('c2000000-0000-4000-8000-000000000105'::uuid, 'b2000000-0000-4000-8000-000000000013'::uuid, 'invoice:output_issued', '销项发票开具', 5, 'primary'),
    ('c2000000-0000-4000-8000-000000000106'::uuid, 'b2000000-0000-4000-8000-000000000013'::uuid, 'invoice:input_certified', '进项发票认证', 6, 'success'),
    ('c2000000-0000-4000-8000-000000000107'::uuid, 'b2000000-0000-4000-8000-000000000013'::uuid, 'expense_reimbursement:paid', '费用报销付款', 7, 'warning'),
    ('c2000000-0000-4000-8000-000000000108'::uuid, 'b2000000-0000-4000-8000-000000000013'::uuid, 'waybill_cost:approved', '运单费用审核', 8, 'danger'),
    ('c2000000-0000-4000-8000-000000000111'::uuid, 'b2000000-0000-4000-8000-000000000014'::uuid, 'draft', '生成草稿', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000112'::uuid, 'b2000000-0000-4000-8000-000000000014'::uuid, 'pending_review', '生成并提交审核', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000121'::uuid, 'b2000000-0000-4000-8000-000000000015'::uuid, 'gross_amount', '含税 / 业务总额', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000122'::uuid, 'b2000000-0000-4000-8000-000000000015'::uuid, 'net_amount', '不含税金额', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000123'::uuid, 'b2000000-0000-4000-8000-000000000015'::uuid, 'tax_amount', '税额', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000131'::uuid, 'b2000000-0000-4000-8000-000000000016'::uuid, 'pending', '待处理', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000132'::uuid, 'b2000000-0000-4000-8000-000000000016'::uuid, 'processing', '处理中', 2, 'primary'),
    ('c2000000-0000-4000-8000-000000000133'::uuid, 'b2000000-0000-4000-8000-000000000016'::uuid, 'generated', '已生成凭证', 3, 'success'),
    ('c2000000-0000-4000-8000-000000000134'::uuid, 'b2000000-0000-4000-8000-000000000016'::uuid, 'pending_configuration', '待配置', 4, 'warning'),
    ('c2000000-0000-4000-8000-000000000135'::uuid, 'b2000000-0000-4000-8000-000000000016'::uuid, 'failed', '生成失败', 5, 'danger'),
    ('c2000000-0000-4000-8000-000000000136'::uuid, 'b2000000-0000-4000-8000-000000000016'::uuid, 'reversed', '已冲销', 6, 'warning'),
    ('c2000000-0000-4000-8000-000000000137'::uuid, 'b2000000-0000-4000-8000-000000000016'::uuid, 'ignored', '无需处理', 7, 'info'),
    ('c2000000-0000-4000-8000-000000000141'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'carrier_freight', '承运运费', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000142'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'toll', '路桥费', 2, 'info'),
    ('c2000000-0000-4000-8000-000000000143'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'parking', '停车费', 3, 'info'),
    ('c2000000-0000-4000-8000-000000000144'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'fuel', '油费', 4, 'warning'),
    ('c2000000-0000-4000-8000-000000000145'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'loading', '装卸费', 5, 'success'),
    ('c2000000-0000-4000-8000-000000000146'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'waiting', '压车等候费', 6, 'warning'),
    ('c2000000-0000-4000-8000-000000000147'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'driver_expense', '司机报销', 7, 'danger'),
    ('c2000000-0000-4000-8000-000000000148'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'cargo_damage', '货损费用', 8, 'danger'),
    ('c2000000-0000-4000-8000-000000000149'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'other', '其他费用', 9, 'info'),
    ('c2000000-0000-4000-8000-000000000150'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'in_transit_energy', '在途能源', 10, 'warning'),
    ('c2000000-0000-4000-8000-000000000151'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'in_transit_charging', '在途充电', 11, 'success'),
    ('c2000000-0000-4000-8000-000000000152'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'in_transit_gas', '在途加气', 12, 'primary'),
    ('c2000000-0000-4000-8000-000000000153'::uuid, 'b2000000-0000-4000-8000-000000000017'::uuid, 'in_transit_other', '在途其他', 13, 'info')
  ) as values_table(id, type_id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type, create_by, update_by, tenant_id
)
select item.id, item.type_id, item.value, '1', item.value, item.label, item.sort, item.tag_type,
  '624944977@qq.com', '624944977@qq.com', platform_tenant.id
from platform_tenant cross join dictionary_items item
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, status = excluded.status,
  value = excluded.value, label = excluded.label, sort = excluded.sort,
  tag_type = excluded.tag_type, update_by = excluded.update_by, update_time = now();

with accounting_menu as (
  select id from public.sys_menu where name = 'FinanceAccounting' limit 1
)
insert into public.sys_menu (
  id, parent_id, name, path, component, type, sort, meta, create_by, update_by
)
select
  'a1000000-0000-4000-8000-000000000021'::uuid,
  accounting_menu.id,
  'FinanceAutoPosting', 'auto-posting', '/fms/auto-posting', 'menu', 8,
  jsonb_build_object('icon', 'ri:git-merge-line', 'title', '自动入账', 'is_enable', true, 'keep_alive', true),
  '624944977@qq.com', '624944977@qq.com'
from accounting_menu
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, path = excluded.path,
  component = excluded.component, type = excluded.type, sort = excluded.sort,
  meta = excluded.meta, update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu (role_id, menu_id, tenant_id, permission, create_by, update_by)
select rm.role_id, 'a1000000-0000-4000-8000-000000000021'::uuid,
  rm.tenant_id, '{}'::jsonb, '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu rm
join public.sys_menu parent on parent.id = rm.menu_id and parent.name = 'FinanceAccounting'
on conflict (role_id, menu_id) do nothing;

commit;

;
