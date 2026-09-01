begin;

alter table public.fms_financial_statement_item
  add column cash_flow_direction text;

alter table public.fms_financial_statement_item
  add constraint fms_financial_statement_item_cash_direction_check check (
    cash_flow_direction is null or cash_flow_direction in ('receipt', 'payment')
  );

alter table public.fms_voucher_line
  add constraint fms_voucher_line_scope_unique unique (id, account_set_id, tenant_id);

create table public.fms_cash_flow_allocation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  voucher_line_id uuid not null,
  statement_item_id uuid not null,
  flow_direction text not null,
  amount numeric(20, 2) not null,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_cash_flow_allocation_line_item_key
    unique (voucher_line_id, statement_item_id),
  constraint fms_cash_flow_allocation_line_fkey
    foreign key (voucher_line_id, account_set_id, tenant_id)
    references public.fms_voucher_line (id, account_set_id, tenant_id)
    on delete cascade,
  constraint fms_cash_flow_allocation_item_fkey
    foreign key (statement_item_id, account_set_id, tenant_id)
    references public.fms_financial_statement_item (id, account_set_id, tenant_id)
    on delete restrict,
  constraint fms_cash_flow_allocation_direction_check
    check (flow_direction in ('receipt', 'payment')),
  constraint fms_cash_flow_allocation_amount_check check (amount > 0)
);

create index fms_cash_flow_allocation_report_idx
  on public.fms_cash_flow_allocation (tenant_id, account_set_id, statement_item_id);
create index fms_cash_flow_allocation_line_idx
  on public.fms_cash_flow_allocation (voucher_line_id);

create or replace function app_private.guard_fms_cash_flow_allocation()
returns trigger
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_line public.fms_voucher_line%rowtype;
  v_item public.fms_financial_statement_item%rowtype;
  v_subject public.fms_subject%rowtype;
  v_line_amount numeric(20, 2);
  v_allocated numeric(20, 2);
begin
  select * into v_line from public.fms_voucher_line where id = new.voucher_line_id;
  select * into v_item from public.fms_financial_statement_item where id = new.statement_item_id;
  select * into v_subject from public.fms_subject where id = v_line.subject_id;

  if v_line.id is null or v_item.id is null
     or v_line.account_set_id <> new.account_set_id
     or v_item.account_set_id <> new.account_set_id
     or v_line.tenant_id <> new.tenant_id
     or v_item.tenant_id <> new.tenant_id then
    raise exception using errcode = '23503', message = '现金流量归集记录不属于当前账套';
  end if;
  if not coalesce(v_subject.cash_flow_required, false) then
    raise exception using errcode = '23514', message = '仅现金及现金等价物科目分录需要现金流量归集';
  end if;
  if v_item.statement_type <> 'cash_flow_statement'
     or v_item.calculation_method <> 'mapping'
     or v_item.cash_flow_direction is null
     or not v_item.is_enabled then
    raise exception using errcode = '23514', message = '现金流量项目必须为已启用的直接取数行';
  end if;

  new.flow_direction := case when v_line.debit_amount > 0 then 'receipt' else 'payment' end;
  v_line_amount := greatest(v_line.debit_amount, v_line.credit_amount);
  select coalesce(sum(allocation.amount), 0) into v_allocated
  from public.fms_cash_flow_allocation allocation
  where allocation.voucher_line_id = new.voucher_line_id
    and (tg_op = 'INSERT' or allocation.id <> new.id);
  if v_allocated + new.amount > v_line_amount then
    raise exception using errcode = '23514', message = '现金流量归集金额不能超过分录金额';
  end if;
  return new;
end;
$$;

create trigger fms_cash_flow_allocation_guard
before insert or update on public.fms_cash_flow_allocation
for each row execute function app_private.guard_fms_cash_flow_allocation();

create trigger fms_cash_flow_allocation_create_audit
before insert on public.fms_cash_flow_allocation
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger fms_cash_flow_allocation_update_audit
before update on public.fms_cash_flow_allocation
for each row execute function public.trg_set_update_time_and_by();

create or replace function app_private.copy_fms_reversal_cash_flow_allocation()
returns trigger
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
begin
  if new.source_line_type = 'voucher_line' and new.source_line_id is not null then
    insert into public.fms_cash_flow_allocation (
      tenant_id, account_set_id, voucher_line_id, statement_item_id,
      flow_direction, amount, remark
    )
    select new.tenant_id, new.account_set_id, new.id, allocation.statement_item_id,
      case allocation.flow_direction when 'receipt' then 'payment' else 'receipt' end,
      allocation.amount, '冲销凭证自动继承现金流量归集'
    from public.fms_cash_flow_allocation allocation
    where allocation.voucher_line_id = new.source_line_id;
  end if;
  return new;
end;
$$;

create trigger fms_voucher_line_copy_cash_flow_allocation
after insert on public.fms_voucher_line
for each row execute function app_private.copy_fms_reversal_cash_flow_allocation();

alter table public.fms_cash_flow_allocation enable row level security;

create policy fms_cash_flow_allocation_tenant_select
on public.fms_cash_flow_allocation for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_cash_flow_allocation_super_insert
on public.fms_cash_flow_allocation for insert to authenticated with check (
  (select app_private.is_platform_super())
);
create policy fms_cash_flow_allocation_super_update
on public.fms_cash_flow_allocation for update to authenticated using (
  (select app_private.is_platform_super())
) with check ((select app_private.is_platform_super()));
create policy fms_cash_flow_allocation_super_delete
on public.fms_cash_flow_allocation for delete to authenticated using (
  (select app_private.is_platform_super())
);

grant select, insert, update, delete on public.fms_cash_flow_allocation to authenticated;
grant all on public.fms_cash_flow_allocation to service_role;

create or replace function public.save_fms_cash_flow_allocations(
  p_voucher_id uuid,
  p_allocations jsonb
)
returns integer
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_voucher public.fms_voucher%rowtype;
  v_allocation jsonb;
  v_count integer := 0;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护现金流量归集';
  end if;
  if jsonb_typeof(coalesce(p_allocations, '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = '现金流量归集参数必须为数组';
  end if;

  select * into v_voucher from public.fms_voucher where id = p_voucher_id for update;
  if not found then
    raise exception using errcode = 'P0002', message = '凭证不存在';
  end if;
  if v_voucher.status not in ('draft', 'rejected') then
    raise exception using errcode = '23514', message = '仅草稿或已驳回凭证允许维护现金流量归集';
  end if;

  delete from public.fms_cash_flow_allocation allocation
  using public.fms_voucher_line line
  where allocation.voucher_line_id = line.id
    and line.voucher_id = p_voucher_id;

  for v_allocation in
    select value from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
  loop
    insert into public.fms_cash_flow_allocation (
      tenant_id, account_set_id, voucher_line_id, statement_item_id,
      flow_direction, amount, remark
    )
    select v_voucher.tenant_id, v_voucher.account_set_id, line.id,
      (v_allocation ->> 'statementItemId')::uuid,
      case when line.debit_amount > 0 then 'receipt' else 'payment' end,
      (v_allocation ->> 'amount')::numeric,
      nullif(btrim(v_allocation ->> 'remark'), '')
    from public.fms_voucher_line line
    where line.id = (v_allocation ->> 'voucherLineId')::uuid
      and line.voucher_id = p_voucher_id;
    if not found then
      raise exception using errcode = '23503', message = '现金流量归集分录不属于当前凭证';
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function app_private.assert_fms_voucher_ready(p_voucher_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_voucher public.fms_voucher%rowtype;
begin
  perform app_private.refresh_fms_voucher_totals(p_voucher_id);
  select * into v_voucher from public.fms_voucher where id = p_voucher_id;
  if v_voucher.line_count < 2 then
    raise exception using errcode = '23514', message = '凭证至少需要两条分录';
  end if;
  if v_voucher.total_debit <= 0 or v_voucher.total_debit <> v_voucher.total_credit then
    raise exception using errcode = '23514', message = '凭证借贷金额必须大于零且保持平衡';
  end if;
  if not exists (
    select 1 from public.fms_accounting_period period
    where period.id = v_voucher.accounting_period_id and period.status = 'open'
      and v_voucher.voucher_date between period.start_date and period.end_date
  ) then
    raise exception using errcode = '23514', message = '凭证所属会计期间未开放';
  end if;
  if exists (
    select 1 from public.fms_voucher_line line
    left join public.fms_subject subject on subject.id = line.subject_id and subject.is_enabled
    where line.voucher_id = p_voucher_id
      and (subject.id is null or exists (
        select 1 from public.fms_subject child where child.parent_id = line.subject_id
      ))
  ) then
    raise exception using errcode = '23514', message = '凭证包含已停用、无效或非末级科目';
  end if;
  if exists (
    select 1
    from public.fms_voucher_line line
    join public.fms_subject subject on subject.id = line.subject_id
    left join lateral (
      select coalesce(sum(allocation.amount), 0) as allocated_amount
      from public.fms_cash_flow_allocation allocation
      where allocation.voucher_line_id = line.id
    ) allocation on true
    where line.voucher_id = p_voucher_id
      and subject.cash_flow_required
      and allocation.allocated_amount <> greatest(line.debit_amount, line.credit_amount)
  ) then
    raise exception using errcode = '23514', message = '现金及现金等价物分录必须完成全额现金流量归集';
  end if;
end;
$$;

do $$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(
    'public.initialize_fms_financial_statement_items(uuid)'::regprocedure
  ) into v_definition;
  v_updated := replace(
    v_definition,
    '  return v_inserted;',
    $body$  update public.fms_financial_statement_item
  set cash_flow_direction = case
    when item_code in ('CF020','CF030','CF040','CF110','CF120','CF130','CF210','CF220') then 'receipt'
    when item_code in ('CF050','CF060','CF070','CF080','CF140','CF150','CF230','CF240') then 'payment'
    else null
  end
  where account_set_id = p_account_set_id
    and statement_type = 'cash_flow_statement';

  return v_inserted;$body$
  );
  if v_updated = v_definition then
    raise exception 'Unable to extend financial statement initialization with cash-flow directions';
  end if;
  execute v_updated;
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
      item.line_no, item.item_level, item.display_style, item.calculation_method,
      item.cash_flow_direction
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
    where p_statement_type <> 'cash_flow_statement'
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
      and p_statement_type <> 'cash_flow_statement'
    group by mapping.statement_item_id
  ), cash_amount as (
    select allocation.statement_item_id,
      sum(case when voucher.period_no between p_period_from and p_period_to
        then allocation.amount * case
          when allocation.flow_direction = item.cash_flow_direction then 1 else -1 end
        else 0 end) as primary_amount,
      sum(allocation.amount * case
        when allocation.flow_direction = item.cash_flow_direction then 1 else -1 end
      ) as secondary_amount,
      count(*) filter (
        where voucher.period_no between p_period_from and p_period_to
      )::bigint as mapping_count
    from public.fms_cash_flow_allocation allocation
    join public.fms_voucher_line line on line.id = allocation.voucher_line_id
    join public.fms_voucher voucher on voucher.id = line.voucher_id
    join enabled_items item on item.id = allocation.statement_item_id
    where p_statement_type = 'cash_flow_statement'
      and allocation.account_set_id = p_account_set_id
      and allocation.tenant_id = v_tenant_id
      and voucher.fiscal_year = p_fiscal_year
      and voucher.period_no between 1 and p_period_to
      and voucher.status in ('posted', 'reversed')
    group by allocation.statement_item_id
  ), direct_amount as (
    select * from mapped_amount
    union all
    select * from cash_amount
  ), formula_amount as (
    select formula.target_item_id,
      sum(coalesce(source_amount.primary_amount, 0) * formula.factor) as primary_amount,
      sum(coalesce(source_amount.secondary_amount, 0) * formula.factor) as secondary_amount,
      sum(coalesce(source_amount.mapping_count, 0))::bigint as mapping_count
    from public.fms_financial_statement_formula formula
    join enabled_items target on target.id = formula.target_item_id
    join enabled_items source on source.id = formula.source_item_id
    left join direct_amount source_amount on source_amount.statement_item_id = formula.source_item_id
    where formula.account_set_id = p_account_set_id
      and formula.tenant_id = v_tenant_id
    group by formula.target_item_id
  )
  select item.id, item.parent_id, item.item_code, item.item_name,
    item.line_no, item.item_level, item.display_style, item.calculation_method,
    item.calculation_method = 'mapping',
    round(case item.calculation_method
      when 'mapping' then coalesce(direct.primary_amount, 0)
      when 'formula' then coalesce(formula.primary_amount, 0)
      else 0 end, 2),
    round(case item.calculation_method
      when 'mapping' then coalesce(direct.secondary_amount, 0)
      when 'formula' then coalesce(formula.secondary_amount, 0)
      else 0 end, 2),
    case item.calculation_method
      when 'mapping' then coalesce(direct.mapping_count, 0)
      when 'formula' then coalesce(formula.mapping_count, 0)
      else 0 end
  from enabled_items item
  left join direct_amount direct on direct.statement_item_id = item.id
  left join formula_amount formula on formula.target_item_id = item.id
  order by item.line_no;
end;
$$;

revoke all on function app_private.guard_fms_cash_flow_allocation()
  from public, anon, authenticated;
revoke all on function app_private.copy_fms_reversal_cash_flow_allocation()
  from public, anon, authenticated;
revoke all on function public.save_fms_cash_flow_allocations(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.save_fms_cash_flow_allocations(uuid, jsonb)
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
select 'b2000000-0000-4000-8000-000000000031'::uuid,
  '现金流量方向', 'fmsCashFlowDirection', '1',
  '624944977@qq.com', '624944977@qq.com', platform_tenant.id,
  'dictionary', 231, '现金流量项目及凭证归集方向'
from platform_tenant
on conflict (id) do update set
  name = excluded.name, code = excluded.code, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000241'::uuid, 'receipt', '现金流入', 1, 'success'),
    ('c2000000-0000-4000-8000-000000000242'::uuid, 'payment', '现金流出', 2, 'warning')
  ) as values_table(id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select item.id, 'b2000000-0000-4000-8000-000000000031'::uuid,
  item.value, '1', item.value, item.label, item.sort, item.tag_type,
  '624944977@qq.com', '624944977@qq.com', platform_tenant.id
from platform_tenant cross join dictionary_items item
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, status = excluded.status,
  value = excluded.value, label = excluded.label, sort = excluded.sort,
  tag_type = excluded.tag_type, update_by = excluded.update_by, update_time = now();

commit;

;
