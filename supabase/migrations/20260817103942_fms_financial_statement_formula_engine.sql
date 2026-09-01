begin;

alter table public.fms_financial_statement_item
  add column calculation_method text not null default 'mapping';

alter table public.fms_financial_statement_item
  add constraint fms_financial_statement_item_calculation_check check (
    calculation_method in ('mapping', 'formula', 'label')
  );

create table public.fms_financial_statement_formula (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  target_item_id uuid not null,
  source_item_id uuid not null,
  factor numeric(12, 6) not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_financial_statement_formula_edge_key
    unique (target_item_id, source_item_id),
  constraint fms_financial_statement_formula_target_fkey
    foreign key (target_item_id, account_set_id, tenant_id)
    references public.fms_financial_statement_item (id, account_set_id, tenant_id)
    on delete cascade,
  constraint fms_financial_statement_formula_source_fkey
    foreign key (source_item_id, account_set_id, tenant_id)
    references public.fms_financial_statement_item (id, account_set_id, tenant_id)
    on delete restrict,
  constraint fms_financial_statement_formula_distinct_check
    check (target_item_id <> source_item_id),
  constraint fms_financial_statement_formula_factor_check
    check (factor <> 0 and abs(factor) <= 1000)
);

create index fms_financial_statement_formula_target_idx
  on public.fms_financial_statement_formula (target_item_id);
create index fms_financial_statement_formula_source_idx
  on public.fms_financial_statement_formula (source_item_id);

create or replace function app_private.guard_fms_financial_statement_formula()
returns trigger
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_target public.fms_financial_statement_item%rowtype;
  v_source public.fms_financial_statement_item%rowtype;
begin
  select * into v_target
  from public.fms_financial_statement_item
  where id = new.target_item_id;
  select * into v_source
  from public.fms_financial_statement_item
  where id = new.source_item_id;

  if v_target.id is null or v_source.id is null
     or v_target.account_set_id <> new.account_set_id
     or v_source.account_set_id <> new.account_set_id
     or v_target.tenant_id <> new.tenant_id
     or v_source.tenant_id <> new.tenant_id then
    raise exception using errcode = '23503', message = '报表公式项目不属于当前账套';
  end if;
  if v_target.statement_type <> v_source.statement_type then
    raise exception using errcode = '23514', message = '报表公式不允许跨报表取数';
  end if;
  if v_target.calculation_method <> 'formula' then
    raise exception using errcode = '23514', message = '公式目标行的计算方式必须为公式';
  end if;
  if v_source.calculation_method <> 'mapping' then
    raise exception using errcode = '23514', message = '公式来源行必须为直接取数行';
  end if;
  return new;
end;
$$;

create trigger fms_financial_statement_formula_guard
before insert or update on public.fms_financial_statement_formula
for each row execute function app_private.guard_fms_financial_statement_formula();

create trigger fms_financial_statement_formula_create_audit
before insert on public.fms_financial_statement_formula
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger fms_financial_statement_formula_update_audit
before update on public.fms_financial_statement_formula
for each row execute function public.trg_set_update_time_and_by();

alter table public.fms_financial_statement_formula enable row level security;

create policy fms_financial_statement_formula_tenant_select
on public.fms_financial_statement_formula for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_financial_statement_formula_super_insert
on public.fms_financial_statement_formula for insert to authenticated with check (
  (select app_private.is_platform_super())
);
create policy fms_financial_statement_formula_super_update
on public.fms_financial_statement_formula for update to authenticated using (
  (select app_private.is_platform_super())
) with check ((select app_private.is_platform_super()));
create policy fms_financial_statement_formula_super_delete
on public.fms_financial_statement_formula for delete to authenticated using (
  (select app_private.is_platform_super())
);

grant select, insert, update, delete on public.fms_financial_statement_formula to authenticated;
grant all on public.fms_financial_statement_formula to service_role;

alter function public.initialize_fms_financial_statement_items(uuid)
  rename to initialize_fms_financial_statement_items_base;

create or replace function public.initialize_fms_financial_statement_items(
  p_account_set_id uuid
)
returns integer
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_inserted integer;
begin
  v_inserted := public.initialize_fms_financial_statement_items_base(p_account_set_id);

  update public.fms_financial_statement_item
  set calculation_method = case
    when item_code in ('BS001','BS100','BS200','BS300','BS400','CF010','CF100','CF200') then 'label'
    when item_code in (
      'BS099','BS190','BS199','BS290','BS390','BS399','BS490','BS499',
      'IS199','IS299','IS399','CF099','CF199','CF299','CF399'
    ) then 'formula'
    else 'mapping'
  end
  where account_set_id = p_account_set_id;

  insert into public.fms_financial_statement_formula (
    tenant_id, account_set_id, target_item_id, source_item_id, factor
  )
  select target.tenant_id, target.account_set_id, target.id, source.id, edge.factor
  from (values
    ('BS099','BS010',1),('BS099','BS020',1),('BS099','BS030',1),('BS099','BS040',1),('BS099','BS050',1),('BS099','BS060',1),
    ('BS190','BS110',1),('BS190','BS120',1),('BS190','BS130',1),('BS190','BS140',1),('BS190','BS150',1),('BS190','BS160',1),
    ('BS199','BS010',1),('BS199','BS020',1),('BS199','BS030',1),('BS199','BS040',1),('BS199','BS050',1),('BS199','BS060',1),
    ('BS199','BS110',1),('BS199','BS120',1),('BS199','BS130',1),('BS199','BS140',1),('BS199','BS150',1),('BS199','BS160',1),
    ('BS290','BS210',1),('BS290','BS220',1),('BS290','BS230',1),('BS290','BS240',1),('BS290','BS250',1),('BS290','BS260',1),
    ('BS390','BS310',1),('BS390','BS320',1),('BS390','BS330',1),
    ('BS399','BS210',1),('BS399','BS220',1),('BS399','BS230',1),('BS399','BS240',1),('BS399','BS250',1),('BS399','BS260',1),
    ('BS399','BS310',1),('BS399','BS320',1),('BS399','BS330',1),
    ('BS490','BS410',1),('BS490','BS420',1),('BS490','BS430',1),('BS490','BS440',1),
    ('BS499','BS210',1),('BS499','BS220',1),('BS499','BS230',1),('BS499','BS240',1),('BS499','BS250',1),('BS499','BS260',1),
    ('BS499','BS310',1),('BS499','BS320',1),('BS499','BS330',1),('BS499','BS410',1),('BS499','BS420',1),('BS499','BS430',1),('BS499','BS440',1),
    ('IS199','IS010',1),('IS199','IS020',-1),('IS199','IS030',-1),('IS199','IS040',-1),('IS199','IS050',-1),('IS199','IS060',-1),('IS199','IS070',-1),
    ('IS199','IS080',1),('IS199','IS090',1),('IS199','IS100',-1),('IS199','IS110',-1),('IS199','IS120',1),
    ('IS299','IS010',1),('IS299','IS020',-1),('IS299','IS030',-1),('IS299','IS040',-1),('IS299','IS050',-1),('IS299','IS060',-1),('IS299','IS070',-1),
    ('IS299','IS080',1),('IS299','IS090',1),('IS299','IS100',-1),('IS299','IS110',-1),('IS299','IS120',1),('IS299','IS210',1),('IS299','IS220',-1),
    ('IS399','IS010',1),('IS399','IS020',-1),('IS399','IS030',-1),('IS399','IS040',-1),('IS399','IS050',-1),('IS399','IS060',-1),('IS399','IS070',-1),
    ('IS399','IS080',1),('IS399','IS090',1),('IS399','IS100',-1),('IS399','IS110',-1),('IS399','IS120',1),('IS399','IS210',1),('IS399','IS220',-1),('IS399','IS310',-1),
    ('CF099','CF020',1),('CF099','CF030',1),('CF099','CF040',1),('CF099','CF050',-1),('CF099','CF060',-1),('CF099','CF070',-1),('CF099','CF080',-1),
    ('CF199','CF110',1),('CF199','CF120',1),('CF199','CF130',1),('CF199','CF140',-1),('CF199','CF150',-1),
    ('CF299','CF210',1),('CF299','CF220',1),('CF299','CF230',-1),('CF299','CF240',-1),
    ('CF399','CF020',1),('CF399','CF030',1),('CF399','CF040',1),('CF399','CF050',-1),('CF399','CF060',-1),('CF399','CF070',-1),('CF399','CF080',-1),
    ('CF399','CF110',1),('CF399','CF120',1),('CF399','CF130',1),('CF399','CF140',-1),('CF399','CF150',-1),
    ('CF399','CF210',1),('CF399','CF220',1),('CF399','CF230',-1),('CF399','CF240',-1)
  ) as edge(target_code, source_code, factor)
  join public.fms_financial_statement_item target
    on target.account_set_id = p_account_set_id and target.item_code = edge.target_code
  join public.fms_financial_statement_item source
    on source.account_set_id = p_account_set_id
   and source.statement_type = target.statement_type
   and source.item_code = edge.source_code
  on conflict (target_item_id, source_item_id) do update
    set factor = excluded.factor, update_time = now();

  return v_inserted;
end;
$$;

drop function public.fms_financial_statement_report(uuid, text, integer, integer, integer);

create function public.fms_financial_statement_report(
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
  calculation_method text,
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
  with enabled_items as (
    select item.id, item.parent_id, item.item_code, item.item_name,
      item.line_no, item.item_level, item.display_style, item.calculation_method
    from public.fms_financial_statement_item item
    where item.account_set_id = p_account_set_id
      and item.tenant_id = v_tenant_id
      and item.statement_type = p_statement_type
      and item.is_enabled
  ), subject_balance as (
    select *
    from public.fms_subject_balance_report(
      p_account_set_id, p_fiscal_year, p_period_from, p_period_to, null, false
    )
  ), mapped_amount as (
    select mapping.statement_item_id,
      sum((case
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'debit' then balance.opening_debit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'credit' then balance.opening_credit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'net_debit' then balance.opening_debit - balance.opening_credit
        when p_statement_type = 'balance_sheet' then balance.opening_credit - balance.opening_debit
        when mapping.mapping_direction = 'debit' then balance.period_debit
        when mapping.mapping_direction = 'credit' then balance.period_credit
        when mapping.mapping_direction = 'net_debit' then balance.period_debit - balance.period_credit
        else balance.period_credit - balance.period_debit
      end) * mapping.factor) as primary_amount,
      sum((case
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'debit' then balance.ending_debit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'credit' then balance.ending_credit
        when p_statement_type = 'balance_sheet' and mapping.mapping_direction = 'net_debit' then balance.ending_debit - balance.ending_credit
        when p_statement_type = 'balance_sheet' then balance.ending_credit - balance.ending_debit
        when mapping.mapping_direction = 'debit' then balance.year_to_date_debit
        when mapping.mapping_direction = 'credit' then balance.year_to_date_credit
        when mapping.mapping_direction = 'net_debit' then balance.year_to_date_debit - balance.year_to_date_credit
        else balance.year_to_date_credit - balance.year_to_date_debit
      end) * mapping.factor) as secondary_amount,
      count(*)::bigint as mapping_count
    from public.fms_financial_statement_mapping mapping
    join subject_balance balance on balance.subject_id = mapping.subject_id
    join enabled_items item on item.id = mapping.statement_item_id
    where mapping.account_set_id = p_account_set_id
      and mapping.tenant_id = v_tenant_id
      and item.calculation_method = 'mapping'
    group by mapping.statement_item_id
  ), formula_amount as (
    select formula.target_item_id,
      sum(coalesce(source_amount.primary_amount, 0) * formula.factor) as primary_amount,
      sum(coalesce(source_amount.secondary_amount, 0) * formula.factor) as secondary_amount,
      sum(coalesce(source_amount.mapping_count, 0))::bigint as mapping_count
    from public.fms_financial_statement_formula formula
    join enabled_items target on target.id = formula.target_item_id
    join enabled_items source on source.id = formula.source_item_id
    left join mapped_amount source_amount on source_amount.statement_item_id = formula.source_item_id
    where formula.account_set_id = p_account_set_id
      and formula.tenant_id = v_tenant_id
    group by formula.target_item_id
  )
  select item.id, item.parent_id, item.item_code, item.item_name,
    item.line_no, item.item_level, item.display_style, item.calculation_method,
    item.calculation_method = 'mapping',
    round(case item.calculation_method
      when 'mapping' then coalesce(mapped.primary_amount, 0)
      when 'formula' then coalesce(formula.primary_amount, 0)
      else 0 end, 2),
    round(case item.calculation_method
      when 'mapping' then coalesce(mapped.secondary_amount, 0)
      when 'formula' then coalesce(formula.secondary_amount, 0)
      else 0 end, 2),
    case item.calculation_method
      when 'mapping' then coalesce(mapped.mapping_count, 0)
      when 'formula' then coalesce(formula.mapping_count, 0)
      else 0 end
  from enabled_items item
  left join mapped_amount mapped on mapped.statement_item_id = item.id
  left join formula_amount formula on formula.target_item_id = item.id
  order by item.line_no;
end;
$$;

revoke all on function app_private.guard_fms_financial_statement_formula()
  from public, anon, authenticated;
revoke all on function public.initialize_fms_financial_statement_items_base(uuid)
  from public, anon, authenticated;
grant execute on function public.initialize_fms_financial_statement_items_base(uuid)
  to authenticated, service_role;
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
select 'b2000000-0000-4000-8000-000000000030'::uuid,
  '报表计算方式', 'fmsStatementCalculationMethod', '1',
  '624944977@qq.com', '624944977@qq.com', platform_tenant.id,
  'dictionary', 230, '财务报表行计算模型'
from platform_tenant
on conflict (id) do update set
  name = excluded.name, code = excluded.code, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000231'::uuid, 'mapping', '科目取数', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000232'::uuid, 'formula', '公式计算', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000233'::uuid, 'label', '标题行', 3, 'info')
  ) as values_table(id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select item.id, 'b2000000-0000-4000-8000-000000000030'::uuid,
  item.value, '1', item.value, item.label, item.sort, item.tag_type,
  '624944977@qq.com', '624944977@qq.com', platform_tenant.id
from platform_tenant cross join dictionary_items item
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, status = excluded.status,
  value = excluded.value, label = excluded.label, sort = excluded.sort,
  tag_type = excluded.tag_type, update_by = excluded.update_by, update_time = now();

commit;

;
