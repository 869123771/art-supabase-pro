create or replace function app_private.assert_fms_fund_account_scope(
  p_fund_account_id uuid,
  p_tenant_id uuid,
  p_account_set_id uuid,
  p_base_currency_only boolean default true
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if p_fund_account_id is null then
    raise exception using errcode = '23502', message = '必须选择实际资金账户';
  end if;

  if not exists (
    select 1
    from public.fms_fund_account fa
    join public.fms_currency c on c.id = fa.currency_id
    where fa.id = p_fund_account_id
      and fa.tenant_id = p_tenant_id
      and fa.account_set_id = p_account_set_id
      and fa.status = 'active'
      and c.tenant_id = p_tenant_id
      and c.account_set_id = p_account_set_id
      and c.is_enabled
      and (not p_base_currency_only or c.is_base)
  ) then
    raise exception using
      errcode = '23503',
      message = '资金账户不属于当前核算主体、本位币不一致或账户不可用';
  end if;
end;
$function$;

create or replace function public.act_fms_commercial_bill(
  p_bill_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns public.fms_commercial_bill
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_bill public.fms_commercial_bill%rowtype;
  v_event_type text;
  v_posting_event_code text;
  v_target_status text;
  v_event_date date := coalesce(nullif(p_payload ->> 'eventDate', '')::date, current_date);
  v_amount numeric(20, 2);
  v_event_id uuid;
  v_fund_account_id uuid := nullif(p_payload ->> 'fundAccountId', '')::uuid;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行票据流转';
  end if;

  select *
  into v_bill
  from public.fms_commercial_bill
  where id = p_bill_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = '商业票据不存在';
  end if;

  if p_action in ('receive', 'issue') then
    if v_bill.status <> 'draft' then
      raise exception using errcode = '23514', message = '仅草稿票据可确认收票或出票';
    end if;
    if (p_action = 'receive' and v_bill.direction <> 'receivable')
      or (p_action = 'issue' and v_bill.direction <> 'payable') then
      raise exception using errcode = '23514', message = '票据方向与操作不匹配';
    end if;
    v_event_type := case when p_action = 'receive' then 'received' else 'issued' end;
    v_posting_event_code := v_event_type;
    v_target_status := 'held';
    v_amount := v_bill.face_amount;
  elsif p_action in ('endorse', 'discount', 'settle') then
    if v_bill.status <> 'held' then
      raise exception using errcode = '23514', message = '仅持有中的票据可背书、贴现或结算';
    end if;
    if p_action = 'endorse' and not v_bill.transferable then
      raise exception using errcode = '23514', message = '当前票据不允许背书转让';
    end if;
    if p_action = 'discount' and v_bill.direction <> 'receivable' then
      raise exception using errcode = '23514', message = '仅应收票据允许贴现';
    end if;
    v_event_type := case p_action
      when 'endorse' then 'endorsed'
      when 'discount' then 'discounted'
      else 'settled'
    end;
    v_posting_event_code := v_event_type;
    v_target_status := v_event_type;
    v_amount := v_bill.face_amount - v_bill.settled_amount;
    if nullif(p_payload ->> 'amount', '') is not null
      and (p_payload ->> 'amount')::numeric <> v_amount then
      raise exception using errcode = '23514', message = '当前版本仅支持全额背书、贴现或结算';
    end if;
    if p_action in ('discount', 'settle') then
      if v_fund_account_id is null then
        raise exception using errcode = '23502', message = '贴现或到期结算必须选择实际资金账户';
      end if;
      perform app_private.assert_fms_fund_account_scope(
        v_fund_account_id,
        v_bill.tenant_id,
        v_bill.account_set_id,
        true
      );
    end if;
  elsif p_action = 'cancel' then
    if v_bill.status not in ('draft', 'held') then
      raise exception using errcode = '23514', message = '当前票据状态不允许取消';
    end if;
    if nullif(btrim(p_payload ->> 'remark'), '') is null then
      raise exception using errcode = '23502', message = '取消票据必须填写原因';
    end if;
    v_event_type := 'cancelled';
    v_posting_event_code := 'voided';
    v_target_status := 'cancelled';
    v_amount := 0;
  else
    raise exception using errcode = '22023', message = '不支持的票据操作';
  end if;

  insert into public.fms_commercial_bill_event (
    tenant_id, account_set_id, bill_id, event_type, event_date, amount,
    counterparty_name, fund_account_id, reference_no, remark
  ) values (
    v_bill.tenant_id,
    v_bill.account_set_id,
    v_bill.id,
    v_event_type,
    v_event_date,
    v_amount,
    coalesce(nullif(btrim(p_payload ->> 'counterpartyName'), ''), v_bill.counterparty_name),
    v_fund_account_id,
    nullif(btrim(p_payload ->> 'referenceNo'), ''),
    nullif(btrim(p_payload ->> 'remark'), '')
  ) returning id into v_event_id;

  update public.fms_commercial_bill
  set
    status = v_target_status,
    settled_amount = case
      when v_target_status in ('endorsed', 'discounted', 'settled') then face_amount
      else settled_amount
    end,
    remark = case
      when p_action = 'cancel'
        then concat_ws(E'\n', nullif(remark, ''), '[取消原因] ' || btrim(p_payload ->> 'remark'))
      else remark
    end,
    version = version + 1
  where id = v_bill.id
  returning * into v_bill;

  if p_action in ('discount', 'settle') then
    perform app_private.post_fms_fund_ledger_entry(
      v_fund_account_id,
      v_event_date,
      case
        when p_action = 'discount' or v_bill.direction = 'receivable' then 'inflow'
        else 'outflow'
      end,
      v_amount,
      'commercial_bill',
      v_bill.id,
      v_bill.bill_no,
      concat(
        case
          when p_action = 'discount' then '票据贴现'
          when v_bill.direction = 'receivable' then '应收票据到期收款'
          else '应付票据到期付款'
        end,
        ' · ',
        v_bill.bill_no
      ),
      v_bill.counterparty_name,
      nullif(btrim(p_payload ->> 'referenceNo'), '')
    );
  end if;

  perform app_private.enqueue_fms_posting_event(
    v_bill.tenant_id,
    'commercial_bill',
    v_posting_event_code,
    v_bill.id,
    v_bill.bill_no,
    v_event_date,
    concat('商业票据', ' · ', v_bill.bill_no, ' · ', v_event_type),
    jsonb_build_object(
      'gross_amount', v_amount,
      'direction', v_bill.direction,
      'bill_type', v_bill.bill_type,
      'bill_id', v_bill.id,
      'bill_event_id', v_event_id,
      'counterparty_name', v_bill.counterparty_name,
      'fund_account_id', nullif(p_payload ->> 'fundAccountId', ''),
      'reference_no', nullif(p_payload ->> 'referenceNo', '')
    )
  );

  return v_bill;
end;
$function$;

create or replace function public.act_fms_payroll_run(
  p_run_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns public.fms_payroll_run
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.fms_payroll_run%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'system');
  v_action_date date := coalesce(nullif(p_payload ->> 'actionDate', '')::date, current_date);
  v_fund_account_id uuid := nullif(p_payload ->> 'fundAccountId', '')::uuid;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行薪资操作';
  end if;

  select * into v_run
  from public.fms_payroll_run
  where id = p_run_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = '薪资批次不存在';
  end if;

  select * into v_period
  from public.fms_accounting_period
  where id = v_run.accounting_period_id;

  if p_action = 'approve' and v_run.status = 'calculated' then
    if v_run.employee_count = 0 then
      raise exception using errcode = '23514', message = '薪资批次没有员工明细';
    end if;
    update public.fms_payroll_run
    set status = 'approved', approved_at = now(), approved_by = v_actor
    where id = v_run.id
    returning * into v_run;

    perform app_private.enqueue_fms_posting_event(
      v_run.tenant_id,
      'payroll',
      'accrued',
      v_run.id,
      v_run.run_no,
      v_period.end_date,
      concat(to_char(v_run.payroll_month, 'YYYY-MM'), ' 薪资计提'),
      jsonb_build_object(
        'gross_amount', v_run.gross_amount + v_run.employer_cost_amount,
        'run_id', v_run.id,
        'salary_gross_amount', v_run.gross_amount,
        'deduction_amount', v_run.deduction_amount,
        'employer_cost_amount', v_run.employer_cost_amount,
        'net_amount', v_run.net_amount
      )
    );
  elsif p_action = 'pay' and v_run.status = 'approved' then
    if v_fund_account_id is null then
      raise exception using errcode = '23502', message = '确认发放薪资必须选择实际扣款账户';
    end if;
    perform app_private.assert_fms_fund_account_scope(
      v_fund_account_id,
      v_run.tenant_id,
      v_run.account_set_id,
      true
    );

    update public.fms_payroll_run
    set status = 'paid', paid_at = now()
    where id = v_run.id
    returning * into v_run;

    perform app_private.post_fms_fund_ledger_entry(
      v_fund_account_id,
      v_action_date,
      'outflow',
      v_run.net_amount,
      'payroll',
      v_run.id,
      v_run.run_no,
      concat(to_char(v_run.payroll_month, 'YYYY-MM'), ' 薪资发放'),
      null,
      nullif(btrim(p_payload ->> 'referenceNo'), '')
    );

    perform app_private.enqueue_fms_posting_event(
      v_run.tenant_id,
      'payroll',
      'paid',
      v_run.id,
      v_run.run_no,
      v_action_date,
      concat(to_char(v_run.payroll_month, 'YYYY-MM'), ' 薪资发放'),
      jsonb_build_object(
        'gross_amount', v_run.net_amount,
        'run_id', v_run.id,
        'fund_account_id', nullif(p_payload ->> 'fundAccountId', ''),
        'reference_no', nullif(p_payload ->> 'referenceNo', '')
      )
    );
  elsif p_action = 'cancel' and v_run.status in ('draft', 'calculated') then
    if nullif(btrim(p_payload ->> 'reason'), '') is null then
      raise exception using errcode = '23502', message = '取消薪资批次必须填写原因';
    end if;
    update public.fms_payroll_run
    set
      status = 'cancelled',
      remark = concat_ws(E'\n', remark, '[取消] ' || btrim(p_payload ->> 'reason'))
    where id = v_run.id
    returning * into v_run;
  else
    raise exception using errcode = '23514', message = '当前薪资批次状态不允许执行该操作';
  end if;

  return v_run;
end;
$function$;

create or replace function public.act_fms_tax_period(
  p_tax_period_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns public.fms_tax_period
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.fms_tax_period%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'system');
  v_action_date date := coalesce(nullif(p_payload ->> 'actionDate', '')::date, current_date);
  v_fund_account_id uuid := nullif(p_payload ->> 'fundAccountId', '')::uuid;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行税务操作';
  end if;

  select * into v_row
  from public.fms_tax_period
  where id = p_tax_period_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = '税务期间不存在';
  end if;

  select * into v_period
  from public.fms_accounting_period
  where id = v_row.accounting_period_id;

  if p_action = 'review' and v_row.status = 'calculated' then
    update public.fms_tax_period
    set status = 'reviewed'
    where id = v_row.id
    returning * into v_row;

    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id,
      'tax',
      'reviewed',
      v_row.id,
      v_row.tax_type,
      v_period.end_date,
      concat(v_period.fiscal_year, '年第', v_period.period_no, '期 ', v_row.tax_type, ' 税费计提'),
      jsonb_build_object(
        'gross_amount', v_row.payable_amount,
        'tax_period_id', v_row.id,
        'tax_type', v_row.tax_type,
        'output_tax_amount', v_row.output_tax_amount,
        'input_tax_amount', v_row.input_tax_amount
      )
    );
  elsif p_action = 'file' and v_row.status = 'reviewed' then
    if nullif(btrim(p_payload ->> 'filingReference'), '') is null then
      raise exception using errcode = '23502', message = '申报必须填写申报凭证号';
    end if;
    update public.fms_tax_period
    set
      status = 'filed',
      filing_reference = btrim(p_payload ->> 'filingReference'),
      filed_at = now(),
      filed_by = v_actor
    where id = v_row.id
    returning * into v_row;
  elsif p_action = 'pay' and v_row.status = 'filed' then
    if v_fund_account_id is null then
      raise exception using errcode = '23502', message = '确认缴税必须选择实际扣款账户';
    end if;
    perform app_private.assert_fms_fund_account_scope(
      v_fund_account_id,
      v_row.tenant_id,
      v_row.account_set_id,
      true
    );

    update public.fms_tax_period
    set status = 'paid', paid_at = now()
    where id = v_row.id
    returning * into v_row;

    perform app_private.post_fms_fund_ledger_entry(
      v_fund_account_id,
      v_action_date,
      'outflow',
      v_row.payable_amount,
      'tax',
      v_row.id,
      concat(v_period.fiscal_year, '-', lpad(v_period.period_no::text, 2, '0'), '-', v_row.tax_type),
      concat(v_period.fiscal_year, '年第', v_period.period_no, '期 ', v_row.tax_type, ' 税费缴纳'),
      null,
      nullif(btrim(p_payload ->> 'referenceNo'), '')
    );

    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id,
      'tax',
      'paid',
      v_row.id,
      v_row.tax_type,
      v_action_date,
      concat(v_period.fiscal_year, '年第', v_period.period_no, '期 ', v_row.tax_type, ' 税费缴纳'),
      jsonb_build_object(
        'gross_amount', v_row.payable_amount,
        'tax_period_id', v_row.id,
        'tax_type', v_row.tax_type,
        'fund_account_id', nullif(p_payload ->> 'fundAccountId', ''),
        'reference_no', nullif(p_payload ->> 'referenceNo', '')
      )
    );
  elsif p_action = 'cancel' and v_row.status in ('draft', 'calculated') then
    if nullif(btrim(p_payload ->> 'reason'), '') is null then
      raise exception using errcode = '23502', message = '取消税务期间必须填写原因';
    end if;
    update public.fms_tax_period
    set
      status = 'cancelled',
      remark = concat_ws(E'\n', remark, '[取消] ' || btrim(p_payload ->> 'reason'))
    where id = v_row.id
    returning * into v_row;
  else
    raise exception using errcode = '23514', message = '当前税务期间状态不允许执行该操作';
  end if;

  return v_row;
end;
$function$;;
