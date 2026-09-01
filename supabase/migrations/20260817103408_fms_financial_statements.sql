begin;

create table public.fms_financial_statement_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  statement_type text not null,
  parent_id uuid,
  item_code text not null,
  item_name text not null,
  line_no integer not null,
  item_level smallint not null default 1,
  display_style text not null default 'normal',
  is_enabled boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_financial_statement_item_scope_key
    unique (id, account_set_id, tenant_id),
  constraint fms_financial_statement_item_code_key
    unique (account_set_id, statement_type, item_code),
  constraint fms_financial_statement_item_line_key
    unique (account_set_id, statement_type, line_no),
  constraint fms_financial_statement_item_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set (id, tenant_id) on delete cascade,
  constraint fms_financial_statement_item_parent_fkey
    foreign key (parent_id, account_set_id, tenant_id)
    references public.fms_financial_statement_item (id, account_set_id, tenant_id)
    on delete restrict,
  constraint fms_financial_statement_item_type_check check (
    statement_type in ('balance_sheet', 'income_statement', 'cash_flow_statement')
  ),
  constraint fms_financial_statement_item_code_check check (btrim(item_code) <> ''),
  constraint fms_financial_statement_item_name_check check (btrim(item_name) <> ''),
  constraint fms_financial_statement_item_line_check check (line_no > 0),
  constraint fms_financial_statement_item_level_check check (item_level between 1 and 8),
  constraint fms_financial_statement_item_style_check check (
    display_style in ('normal', 'subtotal', 'total')
  )
);

create table public.fms_financial_statement_mapping (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  statement_item_id uuid not null,
  subject_id uuid not null,
  mapping_direction text not null,
  factor numeric(12, 6) not null default 1,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_financial_statement_mapping_item_subject_key
    unique (statement_item_id, subject_id, mapping_direction),
  constraint fms_financial_statement_mapping_item_fkey
    foreign key (statement_item_id, account_set_id, tenant_id)
    references public.fms_financial_statement_item (id, account_set_id, tenant_id)
    on delete cascade,
  constraint fms_financial_statement_mapping_subject_fkey
    foreign key (subject_id, account_set_id, tenant_id)
    references public.fms_subject (id, account_set_id, tenant_id)
    on delete restrict,
  constraint fms_financial_statement_mapping_direction_check check (
    mapping_direction in ('debit', 'credit', 'net_debit', 'net_credit')
  ),
  constraint fms_financial_statement_mapping_factor_check check (
    factor <> 0 and abs(factor) <= 1000
  )
);

create index fms_financial_statement_item_list_idx
  on public.fms_financial_statement_item (
    tenant_id, account_set_id, statement_type, is_enabled, line_no
  );
create index fms_financial_statement_item_parent_idx
  on public.fms_financial_statement_item (parent_id)
  where parent_id is not null;
create index fms_financial_statement_mapping_item_idx
  on public.fms_financial_statement_mapping (statement_item_id);
create index fms_financial_statement_mapping_subject_idx
  on public.fms_financial_statement_mapping (subject_id);

create trigger fms_financial_statement_item_create_audit
before insert on public.fms_financial_statement_item
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger fms_financial_statement_item_update_audit
before update on public.fms_financial_statement_item
for each row execute function public.trg_set_update_time_and_by();

create trigger fms_financial_statement_mapping_create_audit
before insert on public.fms_financial_statement_mapping
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger fms_financial_statement_mapping_update_audit
before update on public.fms_financial_statement_mapping
for each row execute function public.trg_set_update_time_and_by();

alter table public.fms_financial_statement_item enable row level security;
alter table public.fms_financial_statement_mapping enable row level security;

create policy fms_financial_statement_item_tenant_select
on public.fms_financial_statement_item for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_financial_statement_item_super_insert
on public.fms_financial_statement_item for insert to authenticated with check (
  (select app_private.is_platform_super())
);
create policy fms_financial_statement_item_super_update
on public.fms_financial_statement_item for update to authenticated using (
  (select app_private.is_platform_super())
) with check ((select app_private.is_platform_super()));
create policy fms_financial_statement_item_super_delete
on public.fms_financial_statement_item for delete to authenticated using (
  (select app_private.is_platform_super())
);

create policy fms_financial_statement_mapping_tenant_select
on public.fms_financial_statement_mapping for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_financial_statement_mapping_super_insert
on public.fms_financial_statement_mapping for insert to authenticated with check (
  (select app_private.is_platform_super())
);
create policy fms_financial_statement_mapping_super_update
on public.fms_financial_statement_mapping for update to authenticated using (
  (select app_private.is_platform_super())
) with check ((select app_private.is_platform_super()));
create policy fms_financial_statement_mapping_super_delete
on public.fms_financial_statement_mapping for delete to authenticated using (
  (select app_private.is_platform_super())
);

grant select, insert, update, delete on public.fms_financial_statement_item to authenticated;
grant select, insert, update, delete on public.fms_financial_statement_mapping to authenticated;
grant all on public.fms_financial_statement_item to service_role;
grant all on public.fms_financial_statement_mapping to service_role;

create or replace function public.initialize_fms_financial_statement_items(
  p_account_set_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_tenant_id uuid;
  v_inserted integer := 0;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可初始化财务报表项目';
  end if;

  select account_set.tenant_id into v_tenant_id
  from public.fms_account_set account_set
  where account_set.id = p_account_set_id;
  if not found then
    raise exception using errcode = 'P0002', message = '账套不存在';
  end if;

  insert into public.fms_financial_statement_item (
    tenant_id, account_set_id, statement_type, item_code, item_name,
    line_no, item_level, display_style, remark
  )
  select v_tenant_id, p_account_set_id, template.statement_type,
    template.item_code, template.item_name, template.line_no,
    template.item_level, template.display_style, '企业会计准则通用报表项目'
  from (values
    ('balance_sheet','BS001','流动资产',10,1,'subtotal'),
    ('balance_sheet','BS010','货币资金',20,2,'normal'),
    ('balance_sheet','BS020','应收票据及应收账款',30,2,'normal'),
    ('balance_sheet','BS030','预付款项',40,2,'normal'),
    ('balance_sheet','BS040','其他应收款',50,2,'normal'),
    ('balance_sheet','BS050','存货',60,2,'normal'),
    ('balance_sheet','BS060','其他流动资产',70,2,'normal'),
    ('balance_sheet','BS099','流动资产合计',80,1,'subtotal'),
    ('balance_sheet','BS100','非流动资产',90,1,'subtotal'),
    ('balance_sheet','BS110','长期股权投资',100,2,'normal'),
    ('balance_sheet','BS120','固定资产',110,2,'normal'),
    ('balance_sheet','BS130','在建工程',120,2,'normal'),
    ('balance_sheet','BS140','无形资产',130,2,'normal'),
    ('balance_sheet','BS150','长期待摊费用',140,2,'normal'),
    ('balance_sheet','BS160','递延所得税资产',150,2,'normal'),
    ('balance_sheet','BS190','非流动资产合计',160,1,'subtotal'),
    ('balance_sheet','BS199','资产总计',170,1,'total'),
    ('balance_sheet','BS200','流动负债',180,1,'subtotal'),
    ('balance_sheet','BS210','短期借款',190,2,'normal'),
    ('balance_sheet','BS220','应付票据及应付账款',200,2,'normal'),
    ('balance_sheet','BS230','合同负债及预收款项',210,2,'normal'),
    ('balance_sheet','BS240','应付职工薪酬',220,2,'normal'),
    ('balance_sheet','BS250','应交税费',230,2,'normal'),
    ('balance_sheet','BS260','其他应付款',240,2,'normal'),
    ('balance_sheet','BS290','流动负债合计',250,1,'subtotal'),
    ('balance_sheet','BS300','非流动负债',260,1,'subtotal'),
    ('balance_sheet','BS310','长期借款',270,2,'normal'),
    ('balance_sheet','BS320','租赁负债',280,2,'normal'),
    ('balance_sheet','BS330','递延收益',290,2,'normal'),
    ('balance_sheet','BS390','非流动负债合计',300,1,'subtotal'),
    ('balance_sheet','BS399','负债合计',310,1,'total'),
    ('balance_sheet','BS400','所有者权益',320,1,'subtotal'),
    ('balance_sheet','BS410','实收资本（或股本）',330,2,'normal'),
    ('balance_sheet','BS420','资本公积',340,2,'normal'),
    ('balance_sheet','BS430','盈余公积',350,2,'normal'),
    ('balance_sheet','BS440','未分配利润',360,2,'normal'),
    ('balance_sheet','BS490','所有者权益合计',370,1,'subtotal'),
    ('balance_sheet','BS499','负债和所有者权益总计',380,1,'total'),
    ('income_statement','IS010','一、营业收入',10,1,'subtotal'),
    ('income_statement','IS020','减：营业成本',20,1,'normal'),
    ('income_statement','IS030','税金及附加',30,1,'normal'),
    ('income_statement','IS040','销售费用',40,1,'normal'),
    ('income_statement','IS050','管理费用',50,1,'normal'),
    ('income_statement','IS060','研发费用',60,1,'normal'),
    ('income_statement','IS070','财务费用',70,1,'normal'),
    ('income_statement','IS080','加：其他收益',80,1,'normal'),
    ('income_statement','IS090','投资收益',90,1,'normal'),
    ('income_statement','IS100','信用减值损失',100,1,'normal'),
    ('income_statement','IS110','资产减值损失',110,1,'normal'),
    ('income_statement','IS120','资产处置收益',120,1,'normal'),
    ('income_statement','IS199','二、营业利润',130,1,'subtotal'),
    ('income_statement','IS210','加：营业外收入',140,1,'normal'),
    ('income_statement','IS220','减：营业外支出',150,1,'normal'),
    ('income_statement','IS299','三、利润总额',160,1,'subtotal'),
    ('income_statement','IS310','减：所得税费用',170,1,'normal'),
    ('income_statement','IS399','四、净利润',180,1,'total'),
    ('cash_flow_statement','CF010','一、经营活动产生的现金流量',10,1,'subtotal'),
    ('cash_flow_statement','CF020','销售商品、提供劳务收到的现金',20,2,'normal'),
    ('cash_flow_statement','CF030','收到的税费返还',30,2,'normal'),
    ('cash_flow_statement','CF040','收到其他与经营活动有关的现金',40,2,'normal'),
    ('cash_flow_statement','CF050','购买商品、接受劳务支付的现金',50,2,'normal'),
    ('cash_flow_statement','CF060','支付给职工以及为职工支付的现金',60,2,'normal'),
    ('cash_flow_statement','CF070','支付的各项税费',70,2,'normal'),
    ('cash_flow_statement','CF080','支付其他与经营活动有关的现金',80,2,'normal'),
    ('cash_flow_statement','CF099','经营活动产生的现金流量净额',90,1,'subtotal'),
    ('cash_flow_statement','CF100','二、投资活动产生的现金流量',100,1,'subtotal'),
    ('cash_flow_statement','CF110','收回投资收到的现金',110,2,'normal'),
    ('cash_flow_statement','CF120','取得投资收益收到的现金',120,2,'normal'),
    ('cash_flow_statement','CF130','处置长期资产收回的现金净额',130,2,'normal'),
    ('cash_flow_statement','CF140','购建长期资产支付的现金',140,2,'normal'),
    ('cash_flow_statement','CF150','投资支付的现金',150,2,'normal'),
    ('cash_flow_statement','CF199','投资活动产生的现金流量净额',160,1,'subtotal'),
    ('cash_flow_statement','CF200','三、筹资活动产生的现金流量',170,1,'subtotal'),
    ('cash_flow_statement','CF210','吸收投资收到的现金',180,2,'normal'),
    ('cash_flow_statement','CF220','取得借款收到的现金',190,2,'normal'),
    ('cash_flow_statement','CF230','偿还债务支付的现金',200,2,'normal'),
    ('cash_flow_statement','CF240','分配股利、利润或偿付利息支付的现金',210,2,'normal'),
    ('cash_flow_statement','CF299','筹资活动产生的现金流量净额',220,1,'subtotal'),
    ('cash_flow_statement','CF399','四、现金及现金等价物净增加额',230,1,'total')
  ) as template(statement_type, item_code, item_name, line_no, item_level, display_style)
  on conflict (account_set_id, statement_type, item_code) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

create or replace function public.fms_financial_statement_report(
  p_account_set_id uuid,
  p_statement_type text,
  p_fiscal_year integer,
  p_period_from integer default 1,
  p_period_to integer default 12
)
returns table (
  item_id uuid,
  parent_id uuid,
  item_code text,
  item_name text,
  line_no integer,
  item_level smallint,
  display_style text,
  is_leaf boolean,
  primary_amount numeric,
  secondary_amount numeric,
  mapping_count bigint
)
language plpgsql
stable
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  if p_statement_type not in ('balance_sheet', 'income_statement', 'cash_flow_statement') then
    raise exception using errcode = '22023', message = '财务报表类型不正确';
  end if;
  if p_fiscal_year not between 1900 and 9999
     or p_period_from not between 1 and 12
     or p_period_to not between p_period_from and 12 then
    raise exception using errcode = '22023', message = '会计年度或期间范围不正确';
  end if;

  select account_set.tenant_id into v_tenant_id
  from public.fms_account_set account_set
  where account_set.id = p_account_set_id
    and ((select app_private.is_platform_super())
      or account_set.tenant_id = (select app_private.current_user_tenant_id()));
  if not found then
    raise exception using errcode = '42501', message = '无权查看该账套';
  end if;

  return query
  with recursive enabled_items as (
    select item.id, item.parent_id, item.item_code, item.item_name,
      item.line_no, item.item_level, item.display_style
    from public.fms_financial_statement_item item
    where item.account_set_id = p_account_set_id
      and item.tenant_id = v_tenant_id
      and item.statement_type = p_statement_type
      and item.is_enabled
  ), item_closure(root_id, child_id) as (
    select item.id, item.id from enabled_items item
    union all
    select closure.root_id, child.id
    from item_closure closure
    join enabled_items child on child.parent_id = closure.child_id
  ), subject_balance as (
    select *
    from public.fms_subject_balance_report(
      p_account_set_id, p_fiscal_year, p_period_from, p_period_to, null, false
    )
  ), direct_amount as (
    select mapping.statement_item_id,
      sum((case
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'debit'
          then balance.opening_debit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'credit'
          then balance.opening_credit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'net_debit'
          then balance.opening_debit - balance.opening_credit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'net_credit'
          then balance.opening_credit - balance.opening_debit
        when mapping.mapping_direction = 'debit' then balance.period_debit
        when mapping.mapping_direction = 'credit' then balance.period_credit
        when mapping.mapping_direction = 'net_debit'
          then balance.period_debit - balance.period_credit
        else balance.period_credit - balance.period_debit
      end) * mapping.factor) as primary_amount,
      sum((case
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'debit'
          then balance.ending_debit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'credit'
          then balance.ending_credit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'net_debit'
          then balance.ending_debit - balance.ending_credit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'net_credit'
          then balance.ending_credit - balance.ending_debit
        when mapping.mapping_direction = 'debit' then balance.year_to_date_debit
        when mapping.mapping_direction = 'credit' then balance.year_to_date_credit
        when mapping.mapping_direction = 'net_debit'
          then balance.year_to_date_debit - balance.year_to_date_credit
        else balance.year_to_date_credit - balance.year_to_date_debit
      end) * mapping.factor) as secondary_amount,
      count(*) as mapping_count
    from public.fms_financial_statement_mapping mapping
    join subject_balance balance on balance.subject_id = mapping.subject_id
    join enabled_items item on item.id = mapping.statement_item_id
    where mapping.account_set_id = p_account_set_id
      and mapping.tenant_id = v_tenant_id
    group by mapping.statement_item_id
  ), rolled_amount as (
    select closure.root_id,
      coalesce(sum(amount.primary_amount), 0) as primary_amount,
      coalesce(sum(amount.secondary_amount), 0) as secondary_amount,
      coalesce(sum(amount.mapping_count), 0)::bigint as mapping_count
    from item_closure closure
    left join direct_amount amount on amount.statement_item_id = closure.child_id
    group by closure.root_id
  )
  select item.id, item.parent_id, item.item_code, item.item_name,
    item.line_no, item.item_level, item.display_style,
    not exists (select 1 from enabled_items child where child.parent_id = item.id),
    round(coalesce(amount.primary_amount, 0), 2),
    round(coalesce(amount.secondary_amount, 0), 2),
    coalesce(amount.mapping_count, 0)
  from enabled_items item
  left join rolled_amount amount on amount.root_id = item.id
  order by item.line_no;
end;
$$;

revoke all on function public.initialize_fms_financial_statement_items(uuid)
  from public, anon, authenticated;
grant execute on function public.initialize_fms_financial_statement_items(uuid)
  to authenticated, service_role;
revoke all on function public.fms_financial_statement_report(uuid, text, integer, integer, integer)
  from public, anon, authenticated;
grant execute on function public.fms_financial_statement_report(uuid, text, integer, integer, integer)
  to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
)
select dictionary.id, dictionary.name, dictionary.code, '1',
  '624944977@qq.com', '624944977@qq.com', platform_tenant.id,
  'dictionary', dictionary.sort, dictionary.remark
from platform_tenant
cross join (values
  ('b2000000-0000-4000-8000-000000000027'::uuid, '财务报表类型', 'fmsFinancialStatementType', 227, '企业财务报表分类'),
  ('b2000000-0000-4000-8000-000000000028'::uuid, '报表取数方向', 'fmsStatementMappingDirection', 228, '报表项目科目取数方向'),
  ('b2000000-0000-4000-8000-000000000029'::uuid, '报表行样式', 'fmsStatementDisplayStyle', 229, '财务报表项目展示层级')
) as dictionary(id, name, code, sort, remark)
on conflict (id) do update set
  name = excluded.name,
  code = excluded.code,
  status = excluded.status,
  update_by = excluded.update_by,
  update_time = now(),
  remark = excluded.remark;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000201'::uuid, 'b2000000-0000-4000-8000-000000000027'::uuid, 'balance_sheet', '资产负债表', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000202'::uuid, 'b2000000-0000-4000-8000-000000000027'::uuid, 'income_statement', '利润表', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000203'::uuid, 'b2000000-0000-4000-8000-000000000027'::uuid, 'cash_flow_statement', '现金流量表', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000211'::uuid, 'b2000000-0000-4000-8000-000000000028'::uuid, 'debit', '借方取数', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000212'::uuid, 'b2000000-0000-4000-8000-000000000028'::uuid, 'credit', '贷方取数', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000213'::uuid, 'b2000000-0000-4000-8000-000000000028'::uuid, 'net_debit', '借方净额', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000214'::uuid, 'b2000000-0000-4000-8000-000000000028'::uuid, 'net_credit', '贷方净额', 4, 'danger'),
    ('c2000000-0000-4000-8000-000000000221'::uuid, 'b2000000-0000-4000-8000-000000000029'::uuid, 'normal', '普通行', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000222'::uuid, 'b2000000-0000-4000-8000-000000000029'::uuid, 'subtotal', '小计行', 2, 'primary'),
    ('c2000000-0000-4000-8000-000000000223'::uuid, 'b2000000-0000-4000-8000-000000000029'::uuid, 'total', '合计行', 3, 'success')
  ) as values_table(id, type_id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select item.id, item.type_id, item.value, '1', item.value, item.label,
  item.sort, item.tag_type, '624944977@qq.com', '624944977@qq.com', platform_tenant.id
from platform_tenant cross join dictionary_items item
on conflict (id) do update set
  type_id = excluded.type_id,
  code = excluded.code,
  status = excluded.status,
  value = excluded.value,
  label = excluded.label,
  sort = excluded.sort,
  tag_type = excluded.tag_type,
  update_by = excluded.update_by,
  update_time = now();

commit;

;
