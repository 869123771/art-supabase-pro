
alter table public.fms_fund_ledger_entry
  drop constraint if exists fms_fund_ledger_source_check;

alter table public.fms_fund_ledger_entry
  add constraint fms_fund_ledger_source_check
  check (
    source_type = any (
      array[
        'customer_receipt'::text,
        'carrier_payment'::text,
        'expense_payment'::text,
        'fund_transfer'::text,
        'commercial_bill'::text,
        'payroll'::text,
        'tax'::text,
        'fixed_asset'::text,
        'manual_adjustment'::text,
        'opening'::text
      ]
    )
  );

do $migration$
declare
  v_definition text;
  v_marker text;
  v_replacement text;
begin
  select pg_get_functiondef('public.act_fms_commercial_bill(uuid,text,jsonb)'::regprocedure)
  into v_definition;

  v_marker := E'  perform app_private.enqueue_fms_posting_event(\n';
  v_replacement := $replacement$
  if p_action in ('discount', 'settle') then
    if nullif(p_payload ->> 'fundAccountId', '') is null then
      raise exception using errcode = '23502', message = '贴现或到期结算必须选择实际资金账户';
    end if;
    perform app_private.post_fms_fund_ledger_entry(
      (p_payload ->> 'fundAccountId')::uuid,
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
$replacement$;

  if position(v_marker in v_definition) = 0 then
    raise exception 'act_fms_commercial_bill posting marker did not match expected definition';
  end if;
  execute replace(v_definition, v_marker, v_replacement);

  select pg_get_functiondef('public.act_fms_payroll_run(uuid,text,jsonb)'::regprocedure)
  into v_definition;
  v_marker := $marker$
    update public.fms_payroll_run set status='paid',paid_at=now() where id=v_run.id returning * into v_run;
    perform app_private.enqueue_fms_posting_event(
$marker$;
  v_replacement := $replacement$
    if nullif(p_payload ->> 'fundAccountId','') is null then
      raise exception using errcode='23502',message='确认发放薪资必须选择实际扣款账户';
    end if;
    update public.fms_payroll_run set status='paid',paid_at=now() where id=v_run.id returning * into v_run;
    perform app_private.post_fms_fund_ledger_entry(
      (p_payload ->> 'fundAccountId')::uuid,
      v_action_date,
      'outflow',
      v_run.net_amount,
      'payroll',
      v_run.id,
      v_run.run_no,
      concat(to_char(v_run.payroll_month,'YYYY-MM'),' 薪资发放'),
      null,
      nullif(btrim(p_payload ->> 'referenceNo'),'')
    );
    perform app_private.enqueue_fms_posting_event(
$replacement$;
  if position(v_marker in v_definition) = 0 then
    raise exception 'act_fms_payroll_run pay marker did not match expected definition';
  end if;
  execute replace(v_definition, v_marker, v_replacement);

  select pg_get_functiondef('public.act_fms_tax_period(uuid,text,jsonb)'::regprocedure)
  into v_definition;
  v_marker := $marker$
    update public.fms_tax_period set status='paid',paid_at=now() where id=v_row.id returning * into v_row;
    perform app_private.enqueue_fms_posting_event(
$marker$;
  v_replacement := $replacement$
    if nullif(p_payload ->> 'fundAccountId','') is null then
      raise exception using errcode='23502',message='确认缴税必须选择实际扣款账户';
    end if;
    update public.fms_tax_period set status='paid',paid_at=now() where id=v_row.id returning * into v_row;
    perform app_private.post_fms_fund_ledger_entry(
      (p_payload ->> 'fundAccountId')::uuid,
      v_action_date,
      'outflow',
      v_row.payable_amount,
      'tax',
      v_row.id,
      concat(v_period.fiscal_year,'-',lpad(v_period.period_no::text,2,'0'),'-',v_row.tax_type),
      concat(v_period.fiscal_year,'年第',v_period.period_no,'期 ',v_row.tax_type,' 税费缴纳'),
      null,
      nullif(btrim(p_payload ->> 'referenceNo'),'')
    );
    perform app_private.enqueue_fms_posting_event(
$replacement$;
  if position(v_marker in v_definition) = 0 then
    raise exception 'act_fms_tax_period pay marker did not match expected definition';
  end if;
  execute replace(v_definition, v_marker, v_replacement);
end
$migration$;
;
