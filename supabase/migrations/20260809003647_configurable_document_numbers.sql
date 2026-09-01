-- Configurable, tenant-scoped document and master-data numbering.

create table if not exists public.sys_document_number_rule (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete cascade,
  rule_key text not null,
  rule_name text not null,
  category text not null,
  target_table text not null,
  target_column text not null,
  auto_enabled boolean not null default true,
  template text not null,
  reset_cycle text not null default 'month',
  sequence_start bigint not null default 1,
  timezone text not null default 'Asia/Shanghai',
  rule_version integer not null default 1,
  manual_required boolean not null default true,
  builtin boolean not null default true,
  enabled boolean not null default true,
  remark text,
  create_by text not null default coalesce(nullif(auth.jwt() ->> 'email', ''), 'system'),
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_document_number_rule_tenant_key_uk unique (tenant_id, rule_key),
  constraint sys_document_number_rule_category_ck
    check (category in ('business_document', 'master_data', 'vehicle')),
  constraint sys_document_number_rule_reset_cycle_ck
    check (reset_cycle in ('none', 'year', 'month', 'day')),
  constraint sys_document_number_rule_sequence_start_ck check (sequence_start between 1 and 999999999999),
  constraint sys_document_number_rule_version_ck check (rule_version >= 1),
  constraint sys_document_number_rule_key_ck check (rule_key ~ '^[a-z][a-z0-9_.]*$')
);

comment on table public.sys_document_number_rule is '租户级单据与基础资料编号规则';
comment on column public.sys_document_number_rule.template is '支持日期令牌与且仅一个 {SEQ:n} 流水号令牌';
comment on column public.sys_document_number_rule.rule_version is '格式变更自动递增，以隔离历史计数器';

create table if not exists public.sys_document_number_counter (
  id uuid primary key default gen_random_uuid(),
  rule_id uuid not null references public.sys_document_number_rule(id) on delete cascade,
  tenant_id uuid not null references public.sys_tenant(id) on delete cascade,
  rule_version integer not null,
  period_key text not null,
  current_value bigint not null,
  create_by text not null default coalesce(nullif(auth.jwt() ->> 'email', ''), 'system'),
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint sys_document_number_counter_scope_uk
    unique (rule_id, tenant_id, rule_version, period_key),
  constraint sys_document_number_counter_value_ck check (current_value >= 1)
);

comment on table public.sys_document_number_counter is '编号规则周期计数器，由数据库取号函数原子维护';

create index if not exists idx_document_number_rule_list
  on public.sys_document_number_rule (tenant_id, category, auto_enabled, rule_name);
create index if not exists idx_document_number_counter_rule
  on public.sys_document_number_counter (rule_id, rule_version, period_key);

create or replace function app_private.trg_validate_document_number_rule()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_seq_count integer;
  v_sample text;
begin
  new.rule_key := lower(btrim(new.rule_key));
  new.rule_name := btrim(new.rule_name);
  new.target_table := lower(btrim(new.target_table));
  new.target_column := lower(btrim(new.target_column));
  new.template := btrim(new.template);
  new.timezone := btrim(new.timezone);
  new.remark := nullif(btrim(coalesce(new.remark, '')), '');

  select count(*) into v_seq_count
  from regexp_matches(new.template, '\{SEQ:[1-9][0-9]?\}', 'g');
  if v_seq_count <> 1 then
    raise exception '编号模板必须且只能包含一个流水号令牌，例如 {SEQ:3}';
  end if;

  v_sample := new.template;
  v_sample := replace(v_sample, '{YYYYMMDD}', '20991231');
  v_sample := replace(v_sample, '{YYYYMM}', '209912');
  v_sample := replace(v_sample, '{YYMM}', '9912');
  v_sample := replace(v_sample, '{YYYY}', '2099');
  v_sample := replace(v_sample, '{YY}', '99');
  v_sample := replace(v_sample, '{MM}', '12');
  v_sample := replace(v_sample, '{DD}', '31');
  v_sample := regexp_replace(v_sample, '\{SEQ:[1-9][0-9]?\}', '999999999999');
  if v_sample ~ '[{}]' then
    raise exception '编号模板包含不支持的令牌';
  end if;
  if length(v_sample) > 50 then
    raise exception '编号模板生成结果不能超过 50 个字符';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone) then
    raise exception '无效时区：%', new.timezone;
  end if;

  if tg_op = 'UPDATE' then
    if new.rule_key is distinct from old.rule_key
       or new.target_table is distinct from old.target_table
       or new.target_column is distinct from old.target_column
       or new.category is distinct from old.category
       or new.builtin is distinct from old.builtin
       or new.manual_required is distinct from old.manual_required then
      raise exception '内置编号规则的标识、目标字段和业务分类不允许修改';
    end if;
    if new.template is distinct from old.template
       or new.reset_cycle is distinct from old.reset_cycle
       or new.sequence_start is distinct from old.sequence_start
       or new.timezone is distinct from old.timezone then
      new.rule_version := old.rule_version + 1;
    else
      new.rule_version := old.rule_version;
    end if;
  end if;
  return new;
end;
$function$;

create or replace function app_private.document_number_period_key(
  p_reset_cycle text,
  p_now timestamptz,
  p_timezone text
)
returns text
language sql
stable
set search_path to ''
as $function$
  select case p_reset_cycle
    when 'year' then to_char(p_now at time zone p_timezone, 'YYYY')
    when 'month' then to_char(p_now at time zone p_timezone, 'YYYYMM')
    when 'day' then to_char(p_now at time zone p_timezone, 'YYYYMMDD')
    else ''
  end
$function$;

create or replace function app_private.next_document_number(p_rule_key text, p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rule public.sys_document_number_rule;
  v_now timestamptz := clock_timestamp();
  v_period_key text;
  v_sequence bigint;
  v_width integer;
  v_result text;
begin
  if p_tenant_id is null then
    raise exception '生成编号时缺少租户';
  end if;
  if auth.uid() is not null
     and not app_private.is_platform_super()
     and p_tenant_id is distinct from app_private.current_user_tenant_id() then
    raise exception '无权为其他租户生成编号';
  end if;

  select * into v_rule
  from public.sys_document_number_rule
  where tenant_id = p_tenant_id and rule_key = p_rule_key and enabled;
  if not found then
    raise exception '未找到已启用的编号规则：%', p_rule_key;
  end if;
  if not v_rule.auto_enabled then
    raise exception '编号规则 % 已切换为手工填写', v_rule.rule_name;
  end if;

  v_period_key := app_private.document_number_period_key(
    v_rule.reset_cycle, v_now, v_rule.timezone
  );
  insert into public.sys_document_number_counter (
    rule_id, tenant_id, rule_version, period_key, current_value, create_by, update_by
  ) values (
    v_rule.id, p_tenant_id, v_rule.rule_version, v_period_key, v_rule.sequence_start,
    coalesce(nullif(auth.jwt() ->> 'email', ''), 'number-engine'),
    coalesce(nullif(auth.jwt() ->> 'email', ''), 'number-engine')
  )
  on conflict (rule_id, tenant_id, rule_version, period_key)
  do update set
    current_value = public.sys_document_number_counter.current_value + 1,
    update_time = now(),
    update_by = coalesce(nullif(auth.jwt() ->> 'email', ''), 'number-engine')
  returning current_value into v_sequence;

  v_width := substring(v_rule.template from '\{SEQ:([1-9][0-9]?)\}')::integer;
  if length(v_sequence::text) > v_width then
    raise exception '编号规则 % 的 % 位流水号已用尽，请调整模板', v_rule.rule_name, v_width;
  end if;

  v_result := v_rule.template;
  v_result := replace(v_result, '{YYYYMMDD}', to_char(v_now at time zone v_rule.timezone, 'YYYYMMDD'));
  v_result := replace(v_result, '{YYYYMM}', to_char(v_now at time zone v_rule.timezone, 'YYYYMM'));
  v_result := replace(v_result, '{YYMM}', to_char(v_now at time zone v_rule.timezone, 'YYMM'));
  v_result := replace(v_result, '{YYYY}', to_char(v_now at time zone v_rule.timezone, 'YYYY'));
  v_result := replace(v_result, '{YY}', to_char(v_now at time zone v_rule.timezone, 'YY'));
  v_result := replace(v_result, '{MM}', to_char(v_now at time zone v_rule.timezone, 'MM'));
  v_result := replace(v_result, '{DD}', to_char(v_now at time zone v_rule.timezone, 'DD'));
  return regexp_replace(v_result, '\{SEQ:[1-9][0-9]?\}', lpad(v_sequence::text, v_width, '0'));
end;
$function$;

create or replace function app_private.trg_assign_configurable_number()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_rule public.sys_document_number_rule;
  v_tenant_id uuid;
  v_current text;
  v_value text;
begin
  v_tenant_id := coalesce(new.tenant_id, app_private.current_user_tenant_id());
  select * into v_rule
  from public.sys_document_number_rule
  where tenant_id = v_tenant_id and rule_key = tg_argv[0] and enabled;
  if not found then
    raise exception '未找到已启用的编号规则：%', tg_argv[0];
  end if;

  v_current := nullif(btrim(coalesce(to_jsonb(new) ->> tg_argv[1], '')), '');
  if v_rule.auto_enabled then
    v_value := app_private.next_document_number(tg_argv[0], v_tenant_id);
  else
    v_value := v_current;
    if v_rule.manual_required and v_value is null then
      raise exception '%未启用自动编码，请手工填写', v_rule.rule_name;
    end if;
  end if;
  new := jsonb_populate_record(new, jsonb_build_object(tg_argv[1], v_value));
  return new;
end;
$function$;

drop trigger if exists sys_document_number_rule_validate on public.sys_document_number_rule;
create trigger sys_document_number_rule_validate
before insert or update on public.sys_document_number_rule
for each row execute function app_private.trg_validate_document_number_rule();
drop trigger if exists sys_document_number_rule_create_audit on public.sys_document_number_rule;
create trigger sys_document_number_rule_create_audit
before insert on public.sys_document_number_rule
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists sys_document_number_rule_update_audit on public.sys_document_number_rule;
create trigger sys_document_number_rule_update_audit
before update on public.sys_document_number_rule
for each row execute function public.trg_set_update_time_and_by();

alter table public.sys_document_number_rule enable row level security;
alter table public.sys_document_number_counter enable row level security;

drop policy if exists document_number_rule_select on public.sys_document_number_rule;
create policy document_number_rule_select on public.sys_document_number_rule
for select to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
drop policy if exists document_number_rule_insert on public.sys_document_number_rule;
create policy document_number_rule_insert on public.sys_document_number_rule
for insert to authenticated
with check ((select app_private.is_platform_super()));
drop policy if exists document_number_rule_update on public.sys_document_number_rule;
create policy document_number_rule_update on public.sys_document_number_rule
for update to authenticated
using ((select app_private.is_platform_super()))
with check ((select app_private.is_platform_super()));
drop policy if exists document_number_rule_delete on public.sys_document_number_rule;
create policy document_number_rule_delete on public.sys_document_number_rule
for delete to authenticated
using ((select app_private.is_platform_super()) and not builtin);

drop policy if exists document_number_counter_select on public.sys_document_number_counter;
create policy document_number_counter_select on public.sys_document_number_counter
for select to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

revoke all on public.sys_document_number_rule from anon;
revoke all on public.sys_document_number_counter from anon;
grant select on public.sys_document_number_rule to authenticated;
grant update (auto_enabled, template, reset_cycle, sequence_start, timezone, enabled, remark)
  on public.sys_document_number_rule to authenticated;
grant select on public.sys_document_number_counter to authenticated;
revoke all on function app_private.next_document_number(text, uuid) from public, anon, authenticated;

create or replace function app_private.seed_document_number_rules(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  insert into public.sys_document_number_rule (
    tenant_id, rule_key, rule_name, category, target_table, target_column,
    auto_enabled, template, reset_cycle, sequence_start, timezone,
    manual_required, builtin, enabled, remark, create_by, update_by
  )
  select p_tenant_id, x.rule_key, x.rule_name, x.category, x.target_table, x.target_column,
         true, x.template, x.reset_cycle, 1, 'Asia/Shanghai',
         x.manual_required, true, true, x.remark, 'number-engine', 'number-engine'
  from (values
    ('tms.order', '运输订单号', 'business_document', 'tms_order', 'order_no', 'YD{YYYYMM}-{SEQ:3}', 'month', true, '运单沿用订单号，不单独取号'),
    ('tms.order_cargo', '订单货号', 'business_document', 'tms_order', 'cargo_no', 'HH{YYYYMM}-{SEQ:3}', 'month', false, '订单级内部货号'),
    ('tms.contract', '合同编号', 'business_document', 'tms_contract', 'contract_no', 'HT{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.carrier_payment_application', '承运商付款申请号', 'business_document', 'tms_carrier_payment_application', 'application_no', 'FK{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.carrier_statement', '承运商对账单号', 'business_document', 'tms_carrier_statement', 'statement_no', 'CYSDZ{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.customer_statement', '客户对账单号', 'business_document', 'tms_customer_statement', 'statement_no', 'KHDZ{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.cash_transaction', '收支流水号', 'business_document', 'tms_cash_transaction', 'transaction_no', 'SZ{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.expense_payment', '费用付款单号', 'business_document', 'tms_expense_payment', 'payment_no', 'FYZF{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.expense_reimbursement', '费用报销单号', 'business_document', 'tms_expense_reimbursement', 'reimbursement_no', 'FYBX{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.in_transit_expense', '在途费用单号', 'business_document', 'tms_in_transit_expense', 'expense_no', 'ZTFY{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('tms.invoice_record', '开票登记号', 'business_document', 'tms_invoice', 'invoice_record_no', 'FPDJ{YYYYMM}-{SEQ:4}', 'month', true, '发票代码和发票号码属于外部法定号码，不在本规则内'),
    ('tms.receipt_exception', '回单异常工单号', 'business_document', 'tms_receipt_exception_work_order', 'work_order_no', 'HDYC{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('master.customer', '客户编码', 'master_data', 'tms_customer', 'customer_code', 'KH{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('master.carrier', '承运商编码', 'master_data', 'tms_carrier', 'carrier_code', 'CYS{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('master.cargo', '货物编码', 'master_data', 'tms_cargo', 'cargo_code', 'HW{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('master.station', '站点编码', 'master_data', 'tms_station', 'station_code', 'ZD{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('vehicle.archive_self', '车辆自编号', 'vehicle', 'vehicle_archive', 'self_no', 'ZBH{YYYYMM}-{SEQ:4}', 'month', false, '车牌号、车架号等外部标识不在本规则内'),
    ('vehicle.inspection', '车辆年检单号', 'vehicle', 'vehicle_inspection', 'inspection_no', 'NJ{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('vehicle.maintenance', '车辆维修单号', 'vehicle', 'vehicle_maintenance_record', 'maintenance_no', 'WX{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('vehicle.part', '配件编码', 'vehicle', 'vehicle_parts', 'part_code', 'LP{YYYYMM}-{SEQ:4}', 'month', true, null),
    ('vehicle.part_category', '配件分类编码', 'vehicle', 'vehicle_parts_category', 'category_code', 'LPLB{YYYYMM}-{SEQ:3}', 'month', true, null),
    ('vehicle.routine_inspection', '车辆例检单号', 'vehicle', 'vehicle_routine_inspection_record', 'routine_inspection_no', 'LJ{YYYYMM}-{SEQ:4}', 'month', true, null)
  ) as x(rule_key, rule_name, category, target_table, target_column, template, reset_cycle, manual_required, remark)
  on conflict (tenant_id, rule_key) do nothing;
end;
$function$;

select app_private.seed_document_number_rules(id) from public.sys_tenant;

create or replace function app_private.trg_seed_document_number_rules_for_tenant()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  perform app_private.seed_document_number_rules(new.id);
  return new;
end;
$function$;

drop trigger if exists sys_tenant_seed_document_number_rules on public.sys_tenant;
create trigger sys_tenant_seed_document_number_rules
after insert on public.sys_tenant
for each row execute function app_private.trg_seed_document_number_rules_for_tenant();

-- Replace legacy defaults and number triggers with the shared engine.
alter table public.tms_cargo alter column cargo_code drop default;
alter table public.tms_carrier alter column carrier_code drop default;
alter table public.tms_carrier_payment_application alter column application_no drop default;
alter table public.tms_carrier_statement alter column statement_no drop default;
alter table public.tms_cash_transaction alter column transaction_no drop default;
alter table public.tms_contract alter column contract_no drop default;
alter table public.tms_customer alter column customer_code drop default;
alter table public.tms_customer_statement alter column statement_no drop default;
alter table public.tms_invoice alter column invoice_record_no drop default;
alter table public.tms_receipt_exception_work_order alter column work_order_no drop default;

drop trigger if exists tms_expense_payment_number on public.tms_expense_payment;
drop trigger if exists tms_expense_reimbursement_number on public.tms_expense_reimbursement;

create or replace function app_private.trg_prepare_tms_in_transit_expense()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_waybill record;
begin
  select w.tenant_id, w.order_id, w.waybill_no, w.driver_id,
         coalesce(d.driver_name, o.dispatch_driver_name) driver_name,
         coalesce(d.phone, o.dispatch_driver_phone) driver_phone,
         o.order_no, o.dispatch_plate_no,
         concat_ws(' → ', nullif(w.origin_city, ''), nullif(w.destination_city, '')) route_name
  into v_waybill
  from public.tms_waybill w
  left join public.tms_order o on o.id = w.order_id and o.tenant_id = w.tenant_id
  left join public.tms_driver d on d.id = w.driver_id
  where w.id = new.waybill_id;
  if not found then raise exception '关联运单不存在'; end if;
  if new.tenant_id is distinct from v_waybill.tenant_id then raise exception '费用与运单不属于同一租户'; end if;
  new.order_id := v_waybill.order_id;
  new.driver_id := v_waybill.driver_id;
  new.waybill_no_snapshot := v_waybill.waybill_no;
  new.order_no_snapshot := v_waybill.order_no;
  new.plate_no_snapshot := v_waybill.dispatch_plate_no;
  new.driver_name_snapshot := v_waybill.driver_name;
  new.driver_phone_snapshot := v_waybill.driver_phone;
  new.route_snapshot := v_waybill.route_name;
  new.amount := round(new.amount, 2);
  new.provider_name := nullif(btrim(coalesce(new.provider_name, '')), '');
  new.payee_name := nullif(btrim(coalesce(new.payee_name, '')), '');
  new.payment_channel := nullif(btrim(coalesce(new.payment_channel, '')), '');
  new.invoice_no := nullif(btrim(coalesce(new.invoice_no, '')), '');
  new.meter_no := nullif(btrim(coalesce(new.meter_no, '')), '');
  new.expense_location := nullif(btrim(coalesce(new.expense_location, '')), '');
  new.description := nullif(btrim(coalesce(new.description, '')), '');
  return new;
end;
$function$;

do $block$
declare
  x record;
begin
  for x in select * from (values
    ('tms_order','tms.order','order_no'),
    ('tms_order','tms.order_cargo','cargo_no'),
    ('tms_contract','tms.contract','contract_no'),
    ('tms_carrier_payment_application','tms.carrier_payment_application','application_no'),
    ('tms_carrier_statement','tms.carrier_statement','statement_no'),
    ('tms_customer_statement','tms.customer_statement','statement_no'),
    ('tms_cash_transaction','tms.cash_transaction','transaction_no'),
    ('tms_expense_payment','tms.expense_payment','payment_no'),
    ('tms_expense_reimbursement','tms.expense_reimbursement','reimbursement_no'),
    ('tms_in_transit_expense','tms.in_transit_expense','expense_no'),
    ('tms_invoice','tms.invoice_record','invoice_record_no'),
    ('tms_receipt_exception_work_order','tms.receipt_exception','work_order_no'),
    ('tms_customer','master.customer','customer_code'),
    ('tms_carrier','master.carrier','carrier_code'),
    ('tms_cargo','master.cargo','cargo_code'),
    ('tms_station','master.station','station_code'),
    ('vehicle_archive','vehicle.archive_self','self_no'),
    ('vehicle_inspection','vehicle.inspection','inspection_no'),
    ('vehicle_maintenance_record','vehicle.maintenance','maintenance_no'),
    ('vehicle_parts','vehicle.part','part_code'),
    ('vehicle_parts_category','vehicle.part_category','category_code'),
    ('vehicle_routine_inspection_record','vehicle.routine_inspection','routine_inspection_no')
  ) as v(table_name, rule_key, column_name)
  loop
    execute format('drop trigger if exists document_number_%I on public.%I', x.column_name, x.table_name);
    execute format(
      'create trigger document_number_%I before insert on public.%I for each row execute function app_private.trg_assign_configurable_number(%L, %L)',
      x.column_name, x.table_name, x.rule_key, x.column_name
    );
  end loop;
end;
$block$;

-- Dictionaries used by the configuration UI.
with platform as (
  select id from public.sys_tenant where lower(tenant_code)='platform' limit 1
)
insert into public.sys_dict_type (name, code, status, create_by, update_by, tenant_id, node_type, sort)
select '编号规则分类', 'documentNumberCategory', '1', '624944977@qq.com', '624944977@qq.com', id, 'dictionary', 81
from platform
on conflict (code) do nothing;

with platform as (
  select id from public.sys_tenant where lower(tenant_code)='platform' limit 1
)
insert into public.sys_dict_type (name, code, status, create_by, update_by, tenant_id, node_type, sort)
select '编号重置周期', 'documentNumberResetCycle', '1', '624944977@qq.com', '624944977@qq.com', id, 'dictionary', 82
from platform
on conflict (code) do nothing;

with dict_type as (
  select id,tenant_id from public.sys_dict_type where code='documentNumberCategory'
)
insert into public.sys_dictionary (type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type)
select d.id, x.code, '1', '624944977@qq.com', '624944977@qq.com', x.value, x.label, x.sort, d.tenant_id, x.tag_type
from dict_type d cross join (values
  ('documentNumberCategoryBusiness','business_document','业务单据',1::bigint,'primary'),
  ('documentNumberCategoryMaster','master_data','基础资料',2::bigint,'success'),
  ('documentNumberCategoryVehicle','vehicle','车辆管理',3::bigint,'warning')
) as x(code,value,label,sort,tag_type)
where not exists (select 1 from public.sys_dictionary e where e.type_id=d.id and e.value=x.value);

with dict_type as (
  select id,tenant_id from public.sys_dict_type where code='documentNumberResetCycle'
)
insert into public.sys_dictionary (type_id, code, status, create_by, update_by, value, label, sort, tenant_id, tag_type)
select d.id, x.code, '1', '624944977@qq.com', '624944977@qq.com', x.value, x.label, x.sort, d.tenant_id, x.tag_type
from dict_type d cross join (values
  ('documentNumberResetNone','none','不重置',1::bigint,'info'),
  ('documentNumberResetYear','year','每年重置',2::bigint,'primary'),
  ('documentNumberResetMonth','month','每月重置',3::bigint,'success'),
  ('documentNumberResetDay','day','每日重置',4::bigint,'warning')
) as x(code,value,label,sort,tag_type)
where not exists (select 1 from public.sys_dictionary e where e.type_id=d.id and e.value=x.value);

-- Platform-super configuration menu. Role assignments mirror the existing system-param menu.
with parent_menu as (
  select id from public.sys_menu where name='System' limit 1
)
insert into public.sys_menu (name,path,component,meta,sort,create_by,update_by,parent_id,type)
select 'DocumentNumberRule','document-number','/system/document-number',
       '{"icon":"ri:hashtag","roles":["R_SUPER"],"title":"编号规则","authList":[{"title":"编辑","authMark":"edit"}],"keepAlive":true}'::jsonb,
       6,'624944977@qq.com','624944977@qq.com',id,'menu'
from parent_menu
where not exists (select 1 from public.sys_menu where name='DocumentNumberRule');

with source_menu as (
  select id from public.sys_menu where name='SystemParam' limit 1
), target_menu as (
  select id from public.sys_menu where name='DocumentNumberRule' limit 1
)
insert into public.sys_role_menu (role_id,menu_id,permission,create_by,update_by,tenant_id)
select rm.role_id,tm.id,rm.permission,'624944977@qq.com','624944977@qq.com',rm.tenant_id
from public.sys_role_menu rm cross join target_menu tm
where rm.menu_id=(select id from source_menu)
  and not exists (
    select 1 from public.sys_role_menu existing
    where existing.role_id=rm.role_id and existing.menu_id=tm.id
  );

;
