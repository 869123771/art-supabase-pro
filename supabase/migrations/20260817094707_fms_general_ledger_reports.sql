begin;

create index if not exists fms_voucher_posted_period_report_idx
  on public.fms_voucher (account_set_id, fiscal_year, period_no, voucher_date, id)
  where status in ('posted', 'reversed');

create or replace function public.fms_subject_balance_report(
  p_account_set_id uuid,
  p_fiscal_year integer,
  p_period_from integer default 1,
  p_period_to integer default 12,
  p_subject_id uuid default null,
  p_hide_zero boolean default false
)
returns table (
  subject_id uuid,
  parent_id uuid,
  subject_code text,
  subject_name text,
  category text,
  balance_direction text,
  subject_level smallint,
  is_leaf boolean,
  opening_debit numeric,
  opening_credit numeric,
  period_debit numeric,
  period_credit numeric,
  year_to_date_debit numeric,
  year_to_date_credit numeric,
  ending_debit numeric,
  ending_credit numeric,
  ending_direction text,
  ending_balance numeric
)
language plpgsql
stable
set search_path = public, app_private, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  if p_fiscal_year not between 1900 and 9999
     or p_period_from not between 1 and 12
     or p_period_to not between p_period_from and 12 then
    raise exception using errcode = '22023', message = '会计年度或期间范围不正确';
  end if;

  select account_set.tenant_id
  into v_tenant_id
  from public.fms_account_set account_set
  where account_set.id = p_account_set_id
    and ((select app_private.is_platform_super())
      or account_set.tenant_id = (select app_private.current_user_tenant_id()));

  if not found then
    raise exception using errcode = '42501', message = '无权查看该账套';
  end if;

  return query
  with recursive subject_base as (
    select subject.id, subject.parent_id, subject.subject_code, subject.subject_name,
      subject.category, subject.balance_direction, subject.level,
      not exists (
        select 1 from public.fms_subject child where child.parent_id = subject.id
      ) as is_leaf
    from public.fms_subject subject
    where subject.account_set_id = p_account_set_id
      and subject.tenant_id = v_tenant_id
  ), subject_closure(root_id, child_id) as (
    select base.id, base.id from subject_base base
    union all
    select closure.root_id, child.id
    from subject_closure closure
    join subject_base child on child.parent_id = closure.child_id
  ), confirmed_opening as (
    select opening.subject_id,
      sum(opening.opening_debit) as opening_debit,
      sum(opening.opening_credit) as opening_credit,
      sum(opening.year_to_date_debit) as opening_ytd_debit,
      sum(opening.year_to_date_credit) as opening_ytd_credit
    from public.fms_opening_balance opening
    join public.fms_opening_balance_control control
      on control.account_set_id = opening.account_set_id
     and control.fiscal_year = opening.fiscal_year
     and control.tenant_id = opening.tenant_id
     and control.status = 'confirmed'
    where opening.account_set_id = p_account_set_id
      and opening.tenant_id = v_tenant_id
      and opening.fiscal_year = p_fiscal_year
    group by opening.subject_id
  ), posted_movement as (
    select line.subject_id,
      sum(line.debit_amount) filter (where voucher.period_no < p_period_from) as prior_debit,
      sum(line.credit_amount) filter (where voucher.period_no < p_period_from) as prior_credit,
      sum(line.debit_amount) filter (
        where voucher.period_no between p_period_from and p_period_to
      ) as period_debit,
      sum(line.credit_amount) filter (
        where voucher.period_no between p_period_from and p_period_to
      ) as period_credit,
      sum(line.debit_amount) filter (where voucher.period_no <= p_period_to) as ytd_debit,
      sum(line.credit_amount) filter (where voucher.period_no <= p_period_to) as ytd_credit
    from public.fms_voucher_line line
    join public.fms_voucher voucher on voucher.id = line.voucher_id
    where voucher.account_set_id = p_account_set_id
      and voucher.tenant_id = v_tenant_id
      and voucher.fiscal_year = p_fiscal_year
      and voucher.status in ('posted', 'reversed')
    group by line.subject_id
  ), rolled as (
    select closure.root_id,
      coalesce(sum(opening.opening_debit), 0) as base_opening_debit,
      coalesce(sum(opening.opening_credit), 0) as base_opening_credit,
      coalesce(sum(opening.opening_ytd_debit), 0) as base_ytd_debit,
      coalesce(sum(opening.opening_ytd_credit), 0) as base_ytd_credit,
      coalesce(sum(movement.prior_debit), 0) as prior_debit,
      coalesce(sum(movement.prior_credit), 0) as prior_credit,
      coalesce(sum(movement.period_debit), 0) as period_debit,
      coalesce(sum(movement.period_credit), 0) as period_credit,
      coalesce(sum(movement.ytd_debit), 0) as ytd_debit,
      coalesce(sum(movement.ytd_credit), 0) as ytd_credit
    from subject_closure closure
    left join confirmed_opening opening on opening.subject_id = closure.child_id
    left join posted_movement movement on movement.subject_id = closure.child_id
    group by closure.root_id
  ), calculated as (
    select base.*,
      rolled.base_opening_debit - rolled.base_opening_credit
        + rolled.prior_debit - rolled.prior_credit as opening_net,
      rolled.period_debit,
      rolled.period_credit,
      rolled.base_ytd_debit + rolled.ytd_debit as ytd_debit,
      rolled.base_ytd_credit + rolled.ytd_credit as ytd_credit,
      rolled.base_opening_debit - rolled.base_opening_credit
        + rolled.ytd_debit - rolled.ytd_credit as ending_net
    from subject_base base
    join rolled on rolled.root_id = base.id
  )
  select calculated.id, calculated.parent_id, calculated.subject_code,
    calculated.subject_name, calculated.category, calculated.balance_direction,
    calculated.level, calculated.is_leaf,
    greatest(calculated.opening_net, 0), greatest(-calculated.opening_net, 0),
    calculated.period_debit, calculated.period_credit,
    calculated.ytd_debit, calculated.ytd_credit,
    greatest(calculated.ending_net, 0), greatest(-calculated.ending_net, 0),
    case when calculated.ending_net > 0 then 'debit'
         when calculated.ending_net < 0 then 'credit'
         else calculated.balance_direction end,
    abs(calculated.ending_net)
  from calculated
  where (p_subject_id is null or calculated.id = p_subject_id)
    and (not p_hide_zero or calculated.opening_net <> 0
      or calculated.period_debit <> 0 or calculated.period_credit <> 0
      or calculated.ending_net <> 0)
  order by calculated.subject_code;
end;
$$;

create or replace function public.fms_general_ledger_report(
  p_account_set_id uuid,
  p_fiscal_year integer,
  p_subject_id uuid,
  p_period_from integer default 1,
  p_period_to integer default 12
)
returns table (
  period_no integer,
  period_start date,
  period_end date,
  opening_direction text,
  opening_balance numeric,
  debit_amount numeric,
  credit_amount numeric,
  year_to_date_debit numeric,
  year_to_date_credit numeric,
  ending_direction text,
  ending_balance numeric,
  voucher_count bigint,
  line_count bigint
)
language plpgsql
stable
set search_path = public, app_private, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
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

  if not exists (
    select 1 from public.fms_subject subject
    where subject.id = p_subject_id and subject.account_set_id = p_account_set_id
  ) then
    raise exception using errcode = '22023', message = '会计科目不属于当前账套';
  end if;

  return query
  with recursive subject_scope(id) as (
    select p_subject_id
    union all
    select child.id from public.fms_subject child
    join subject_scope parent on child.parent_id = parent.id
    where child.account_set_id = p_account_set_id and child.tenant_id = v_tenant_id
  ), period_scope as (
    select series.period_no,
      period.start_date as period_start,
      period.end_date as period_end
    from generate_series(p_period_from, p_period_to) as series(period_no)
    left join public.fms_accounting_period period
      on period.account_set_id = p_account_set_id
     and period.fiscal_year = p_fiscal_year
     and period.period_no = series.period_no
  ), opening as (
    select coalesce(sum(balance.opening_debit - balance.opening_credit), 0) as opening_net,
      coalesce(sum(balance.year_to_date_debit), 0) as opening_ytd_debit,
      coalesce(sum(balance.year_to_date_credit), 0) as opening_ytd_credit
    from public.fms_opening_balance balance
    join subject_scope scope on scope.id = balance.subject_id
    join public.fms_opening_balance_control control
      on control.account_set_id = balance.account_set_id
     and control.fiscal_year = balance.fiscal_year
     and control.tenant_id = balance.tenant_id
     and control.status = 'confirmed'
    where balance.account_set_id = p_account_set_id
      and balance.fiscal_year = p_fiscal_year
  ), movement as (
    select voucher.period_no,
      sum(line.debit_amount) as debit_amount,
      sum(line.credit_amount) as credit_amount,
      count(distinct voucher.id) as voucher_count,
      count(*) as line_count
    from public.fms_voucher voucher
    join public.fms_voucher_line line on line.voucher_id = voucher.id
    join subject_scope scope on scope.id = line.subject_id
    where voucher.account_set_id = p_account_set_id
      and voucher.tenant_id = v_tenant_id
      and voucher.fiscal_year = p_fiscal_year
      and voucher.status in ('posted', 'reversed')
      and voucher.period_no <= p_period_to
    group by voucher.period_no
  ), rows as (
    select period.period_no, period.period_start, period.period_end,
      opening.opening_net
        + coalesce(sum(coalesce(movement.debit_amount, 0) - coalesce(movement.credit_amount, 0))
          over (order by period.period_no rows between unbounded preceding and 1 preceding), 0)
        + coalesce((select sum(coalesce(prior.debit_amount, 0) - coalesce(prior.credit_amount, 0))
          from movement prior where prior.period_no < p_period_from), 0) as period_opening_net,
      coalesce(movement.debit_amount, 0) as debit_amount,
      coalesce(movement.credit_amount, 0) as credit_amount,
      opening.opening_ytd_debit
        + coalesce((select sum(coalesce(ytd.debit_amount, 0)) from movement ytd
          where ytd.period_no <= period.period_no), 0) as ytd_debit,
      opening.opening_ytd_credit
        + coalesce((select sum(coalesce(ytd.credit_amount, 0)) from movement ytd
          where ytd.period_no <= period.period_no), 0) as ytd_credit,
      coalesce(movement.voucher_count, 0) as voucher_count,
      coalesce(movement.line_count, 0) as line_count
    from period_scope period
    cross join opening
    left join movement on movement.period_no = period.period_no
  )
  select rows.period_no, rows.period_start, rows.period_end,
    case when rows.period_opening_net >= 0 then 'debit' else 'credit' end,
    abs(rows.period_opening_net), rows.debit_amount, rows.credit_amount,
    rows.ytd_debit, rows.ytd_credit,
    case when rows.period_opening_net + rows.debit_amount - rows.credit_amount >= 0
      then 'debit' else 'credit' end,
    abs(rows.period_opening_net + rows.debit_amount - rows.credit_amount),
    rows.voucher_count, rows.line_count
  from rows
  order by rows.period_no;
end;
$$;

create or replace function public.fms_subsidiary_ledger_report(
  p_account_set_id uuid,
  p_fiscal_year integer,
  p_subject_id uuid,
  p_period_from integer default 1,
  p_period_to integer default 12,
  p_auxiliary_type_id uuid default null,
  p_auxiliary_item_id uuid default null
)
returns table (
  row_type text,
  voucher_line_id uuid,
  voucher_id uuid,
  voucher_date date,
  period_no integer,
  voucher_no text,
  voucher_type text,
  subject_code text,
  subject_name text,
  summary text,
  auxiliary_display text,
  currency_code text,
  original_amount numeric,
  quantity numeric,
  unit_name text,
  debit_amount numeric,
  credit_amount numeric,
  balance_direction text,
  balance_amount numeric
)
language plpgsql
stable
set search_path = public, app_private, pg_temp
as $$
declare
  v_tenant_id uuid;
begin
  if p_fiscal_year not between 1900 and 9999
     or p_period_from not between 1 and 12
     or p_period_to not between p_period_from and 12 then
    raise exception using errcode = '22023', message = '会计年度或期间范围不正确';
  end if;
  if p_auxiliary_item_id is not null and p_auxiliary_type_id is null then
    raise exception using errcode = '22023', message = '选择辅助项目时必须指定辅助核算类型';
  end if;

  select account_set.tenant_id into v_tenant_id
  from public.fms_account_set account_set
  where account_set.id = p_account_set_id
    and ((select app_private.is_platform_super())
      or account_set.tenant_id = (select app_private.current_user_tenant_id()));
  if not found then
    raise exception using errcode = '42501', message = '无权查看该账套';
  end if;

  if not exists (
    select 1 from public.fms_subject subject
    where subject.id = p_subject_id and subject.account_set_id = p_account_set_id
  ) then
    raise exception using errcode = '22023', message = '会计科目不属于当前账套';
  end if;

  return query
  with recursive subject_scope(id) as (
    select p_subject_id
    union all
    select child.id from public.fms_subject child
    join subject_scope parent on child.parent_id = parent.id
    where child.account_set_id = p_account_set_id and child.tenant_id = v_tenant_id
  ), opening as (
    select coalesce(sum(balance.opening_debit - balance.opening_credit), 0)
      + coalesce((
        select sum(line.debit_amount - line.credit_amount)
        from public.fms_voucher voucher
        join public.fms_voucher_line line on line.voucher_id = voucher.id
        join subject_scope scope on scope.id = line.subject_id
        where voucher.account_set_id = p_account_set_id
          and voucher.tenant_id = v_tenant_id
          and voucher.fiscal_year = p_fiscal_year
          and voucher.status in ('posted', 'reversed')
          and voucher.period_no < p_period_from
          and (p_auxiliary_type_id is null
            or (line.auxiliary_values ? p_auxiliary_type_id::text
              and (p_auxiliary_item_id is null
                or line.auxiliary_values ->> p_auxiliary_type_id::text = p_auxiliary_item_id::text)))
      ), 0) as opening_net
    from public.fms_opening_balance balance
    join subject_scope scope on scope.id = balance.subject_id
    join public.fms_opening_balance_control control
      on control.account_set_id = balance.account_set_id
     and control.fiscal_year = balance.fiscal_year
     and control.tenant_id = balance.tenant_id
     and control.status = 'confirmed'
    where balance.account_set_id = p_account_set_id
      and balance.tenant_id = v_tenant_id
      and balance.fiscal_year = p_fiscal_year
      and (p_auxiliary_type_id is null
        or (balance.auxiliary_values ? p_auxiliary_type_id::text
          and (p_auxiliary_item_id is null
            or balance.auxiliary_values ->> p_auxiliary_type_id::text = p_auxiliary_item_id::text)))
  ), transactions as (
    select line.id as voucher_line_id, voucher.id as voucher_id, voucher.voucher_date,
      voucher.period_no::integer, voucher.voucher_no, voucher.voucher_type,
      line.subject_code_snapshot, line.subject_name_snapshot, line.summary,
      coalesce((
        select string_agg(aux_type.type_name || '：' || aux_item.item_name, '；'
          order by aux_type.sort, aux_item.sort)
        from jsonb_each_text(line.auxiliary_values) value(type_id, item_id)
        join public.fms_auxiliary_type aux_type on aux_type.id = value.type_id::uuid
        join public.fms_auxiliary_item aux_item on aux_item.id = value.item_id::uuid
      ), '') as auxiliary_display,
      line.currency_code_snapshot, line.original_amount, line.quantity,
      line.unit_name_snapshot, line.debit_amount, line.credit_amount
    from public.fms_voucher voucher
    join public.fms_voucher_line line on line.voucher_id = voucher.id
    join subject_scope scope on scope.id = line.subject_id
    where voucher.account_set_id = p_account_set_id
      and voucher.tenant_id = v_tenant_id
      and voucher.fiscal_year = p_fiscal_year
      and voucher.period_no between p_period_from and p_period_to
      and voucher.status in ('posted', 'reversed')
      and (p_auxiliary_type_id is null
        or (line.auxiliary_values ? p_auxiliary_type_id::text
          and (p_auxiliary_item_id is null
            or line.auxiliary_values ->> p_auxiliary_type_id::text = p_auxiliary_item_id::text)))
  ), ledger_rows as (
    select 0 as row_sort, 'opening'::text as row_type, null::uuid as voucher_line_id,
      null::uuid as voucher_id, null::date as voucher_date, p_period_from as period_no,
      null::text as voucher_no, null::text as voucher_type, null::text as subject_code,
      null::text as subject_name, '期初余额'::text as summary,
      null::text as auxiliary_display, null::text as currency_code,
      0::numeric as original_amount, 0::numeric as quantity, null::text as unit_name,
      0::numeric as debit_amount, 0::numeric as credit_amount, opening.opening_net as running_net
    from opening
    union all
    select row_number() over (order by transaction.voucher_date, transaction.voucher_no,
      transaction.voucher_line_id)::integer,
      'transaction', transaction.voucher_line_id, transaction.voucher_id,
      transaction.voucher_date, transaction.period_no, transaction.voucher_no,
      transaction.voucher_type, transaction.subject_code_snapshot,
      transaction.subject_name_snapshot, transaction.summary, transaction.auxiliary_display,
      transaction.currency_code_snapshot, transaction.original_amount, transaction.quantity,
      transaction.unit_name_snapshot, transaction.debit_amount, transaction.credit_amount,
      opening.opening_net + sum(transaction.debit_amount - transaction.credit_amount)
        over (order by transaction.voucher_date, transaction.voucher_no,
          transaction.voucher_line_id rows unbounded preceding)
    from transactions transaction cross join opening
  )
  select ledger_rows.row_type, ledger_rows.voucher_line_id, ledger_rows.voucher_id,
    ledger_rows.voucher_date, ledger_rows.period_no, ledger_rows.voucher_no,
    ledger_rows.voucher_type, ledger_rows.subject_code, ledger_rows.subject_name,
    ledger_rows.summary, ledger_rows.auxiliary_display, ledger_rows.currency_code,
    ledger_rows.original_amount, ledger_rows.quantity, ledger_rows.unit_name,
    ledger_rows.debit_amount, ledger_rows.credit_amount,
    case when ledger_rows.running_net >= 0 then 'debit' else 'credit' end,
    abs(ledger_rows.running_net)
  from ledger_rows
  order by ledger_rows.row_sort;
end;
$$;

grant execute on function public.fms_subject_balance_report(uuid, integer, integer, integer, uuid, boolean)
  to authenticated, service_role;
grant execute on function public.fms_general_ledger_report(uuid, integer, uuid, integer, integer)
  to authenticated, service_role;
grant execute on function public.fms_subsidiary_ledger_report(uuid, integer, uuid, integer, integer, uuid, uuid)
  to authenticated, service_role;

comment on function public.fms_subject_balance_report(uuid, integer, integer, integer, uuid, boolean)
  is '按科目层级汇总已过账及已冲销凭证，输出期初、本期、本年累计和期末余额。';
comment on function public.fms_general_ledger_report(uuid, integer, uuid, integer, integer)
  is '按会计期间输出科目总账月度发生额、累计发生额和滚动余额。';
comment on function public.fms_subsidiary_ledger_report(uuid, integer, uuid, integer, integer, uuid, uuid)
  is '输出科目及可选辅助核算维度的明细账和逐笔滚动余额。';

commit;

;
