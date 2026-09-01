
create or replace function public.generate_fms_profit_loss_carryforward(p_accounting_period_id uuid)
returns public.fms_voucher
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_period public.fms_accounting_period%rowtype;
  v_existing public.fms_voucher%rowtype;
  v_voucher public.fms_voucher%rowtype;
  v_profit_subject_id uuid;
  v_lines jsonb:='[]'::jsonb;
  v_line_no integer:=0;
  v_debit numeric(20,2):=0;
  v_credit numeric(20,2):=0;
  v_amount numeric(20,2);
  v_row record;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可生成损益结转凭证';
  end if;
  select * into v_period
  from public.fms_accounting_period
  where id=p_accounting_period_id
  for update;
  if not found then raise exception using errcode='P0002',message='会计期间不存在'; end if;
  if v_period.status not in ('open','closing') then
    raise exception using errcode='23514',message='仅开放或关账中的期间可生成损益结转凭证';
  end if;

  select * into v_existing
  from public.fms_voucher
  where account_set_id=v_period.account_set_id
    and source_type='period_close'
    and source_id=v_period.id
    and status<>'voided'
  order by create_time desc
  limit 1;
  if found then return v_existing; end if;

  select s.id into v_profit_subject_id
  from public.fms_subject s
  where s.account_set_id=v_period.account_set_id
    and s.subject_code like '4103%'
    and s.is_enabled
    and not exists(
      select 1 from public.fms_subject child
      where child.parent_id=s.id and child.is_enabled
    )
  order by length(s.subject_code),s.subject_code
  limit 1;
  if v_profit_subject_id is null then
    raise exception using errcode='23514',message='缺少可记账的“本年利润（4103）”末级科目';
  end if;

  for v_row in
    select s.id,s.subject_code,s.subject_name,s.category,
           coalesce(sum(l.debit_amount),0)::numeric(20,2) debit_amount,
           coalesce(sum(l.credit_amount),0)::numeric(20,2) credit_amount
    from public.fms_subject s
    join public.fms_voucher_line l on l.subject_id=s.id
    join public.fms_voucher v on v.id=l.voucher_id
    where s.account_set_id=v_period.account_set_id
      and s.category in ('income','expense')
      and v.accounting_period_id=v_period.id
      and v.status in ('posted','reversed')
      and v.source_type<>'period_close'
    group by s.id,s.subject_code,s.subject_name,s.category
    having coalesce(sum(l.debit_amount),0)<>coalesce(sum(l.credit_amount),0)
    order by s.subject_code
  loop
    if v_row.category='income' then
      v_amount:=round(v_row.credit_amount-v_row.debit_amount,2);
      if v_amount>0 then
        v_line_no:=v_line_no+1; v_debit:=v_debit+v_amount;
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'lineNo',v_line_no,'summary','结转收入 · '||v_row.subject_name,
          'subjectId',v_row.id,'debitAmount',v_amount,'creditAmount',0,
          'sourceLineType','period_close_subject','sourceLineId',v_row.id
        ));
      elsif v_amount<0 then
        v_amount:=abs(v_amount); v_line_no:=v_line_no+1; v_credit:=v_credit+v_amount;
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'lineNo',v_line_no,'summary','结转收入借方余额 · '||v_row.subject_name,
          'subjectId',v_row.id,'debitAmount',0,'creditAmount',v_amount,
          'sourceLineType','period_close_subject','sourceLineId',v_row.id
        ));
      end if;
    else
      v_amount:=round(v_row.debit_amount-v_row.credit_amount,2);
      if v_amount>0 then
        v_line_no:=v_line_no+1; v_credit:=v_credit+v_amount;
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'lineNo',v_line_no,'summary','结转成本费用 · '||v_row.subject_name,
          'subjectId',v_row.id,'debitAmount',0,'creditAmount',v_amount,
          'sourceLineType','period_close_subject','sourceLineId',v_row.id
        ));
      elsif v_amount<0 then
        v_amount:=abs(v_amount); v_line_no:=v_line_no+1; v_debit:=v_debit+v_amount;
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
          'lineNo',v_line_no,'summary','结转费用贷方余额 · '||v_row.subject_name,
          'subjectId',v_row.id,'debitAmount',v_amount,'creditAmount',0,
          'sourceLineType','period_close_subject','sourceLineId',v_row.id
        ));
      end if;
    end if;
  end loop;

  if v_line_no=0 then
    raise exception using errcode='23514',message='本期没有需要结转的已记账损益发生额';
  end if;

  v_amount:=round(v_debit-v_credit,2);
  if v_amount>0 then
    v_line_no:=v_line_no+1;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'lineNo',v_line_no,'summary','结转本期净利润',
      'subjectId',v_profit_subject_id,'debitAmount',0,'creditAmount',v_amount,
      'sourceLineType','period_close_profit','sourceLineId',v_period.id
    ));
  elsif v_amount<0 then
    v_line_no:=v_line_no+1; v_amount:=abs(v_amount);
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'lineNo',v_line_no,'summary','结转本期净亏损',
      'subjectId',v_profit_subject_id,'debitAmount',v_amount,'creditAmount',0,
      'sourceLineType','period_close_profit','sourceLineId',v_period.id
    ));
  else
    raise exception using errcode='23514',message='损益结转净额为零，无需生成结转凭证';
  end if;

  perform set_config('app.fms_system_posting','on',true);
  select * into v_voucher from public.save_fms_voucher(jsonb_build_object(
    'accountSetId',v_period.account_set_id,
    'voucherType','closing',
    'voucherDate',v_period.end_date,
    'summary',concat(v_period.fiscal_year,'年第',v_period.period_no,'期损益结转'),
    'sourceType','period_close',
    'sourceId',v_period.id,
    'sourceNo',concat('PL-',v_period.fiscal_year,'-',lpad(v_period.period_no::text,2,'0')),
    'attachments','[]'::jsonb,
    'lines',v_lines
  ));
  select * into v_voucher
  from public.transition_fms_voucher(v_voucher.id,'submit',null,null);
  return v_voucher;
end;
$function$;

create or replace function public.act_fms_period_close_run(
  p_run_id uuid,
  p_action text,
  p_reason text default null
)
returns public.fms_period_close_run
language plpgsql
set search_path to ''
as $function$
declare
  v_run public.fms_period_close_run%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_actor text:=coalesce(auth.jwt()->>'email',auth.uid()::text,'system');
  v_issue_count bigint;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可执行结账或反结账';
  end if;
  select * into v_run from public.fms_period_close_run where id=p_run_id for update;
  if not found then raise exception using errcode='P0002',message='关账批次不存在'; end if;
  select * into v_period from public.fms_accounting_period
  where id=v_run.accounting_period_id for update;

  if p_action='close' and v_run.status='ready' then
    if v_run.blocking_count<>0 then
      raise exception using errcode='23514',message='仍有阻断项，不能结账';
    end if;

    select count(*) into v_issue_count
    from public.fms_posting_event e
    where e.account_set_id=v_period.account_set_id
      and e.event_date between v_period.start_date and v_period.end_date
      and e.status not in ('generated','reversed','ignored');
    if v_issue_count>0 then
      raise exception using errcode='23514',
        message=format('仍有 %s 个业务自动入账事件未完成，请先在自动入账中处理',v_issue_count);
    end if;

    select count(*) into v_issue_count
    from public.fms_voucher v
    where v.accounting_period_id=v_period.id
      and v.status not in ('posted','reversed','voided');
    if v_issue_count>0 then
      raise exception using errcode='23514',
        message=format('仍有 %s 张凭证未完成记账，请先在凭证中心处理',v_issue_count);
    end if;

    if exists(
      select 1
      from public.fms_voucher_line l
      join public.fms_voucher v on v.id=l.voucher_id
      join public.fms_subject s on s.id=l.subject_id
      where v.accounting_period_id=v_period.id
        and v.status in ('posted','reversed')
        and v.source_type<>'period_close'
        and s.category in ('income','expense')
        and l.debit_amount<>l.credit_amount
    ) and not exists(
      select 1 from public.fms_voucher v
      where v.accounting_period_id=v_period.id
        and v.source_type='period_close'
        and v.status in ('posted','reversed')
    ) then
      raise exception using errcode='23514',
        message='本期存在损益发生额，请先生成并记账损益结转凭证';
    end if;

    v_period:=public.set_fms_accounting_period_status(v_period.id,'closed',null);
    update public.fms_period_close_run
    set status='closed',completed_at=now(),completed_by=v_actor
    where id=v_run.id returning * into v_run;
  elsif p_action='cancel' and v_run.status in ('checking','ready') then
    if nullif(btrim(p_reason),'') is null then
      raise exception using errcode='23502',message='取消关账必须填写原因';
    end if;
    v_period:=public.set_fms_accounting_period_status(v_period.id,'open',null);
    update public.fms_period_close_run
    set status='cancelled',cancelled_at=now(),cancelled_by=v_actor,cancel_reason=btrim(p_reason)
    where id=v_run.id returning * into v_run;
  elsif p_action='reopen' and v_run.status='closed' then
    if nullif(btrim(p_reason),'') is null then
      raise exception using errcode='23502',message='反结账必须填写原因';
    end if;
    v_period:=public.set_fms_accounting_period_status(v_period.id,'open',p_reason);
    update public.fms_period_close_run
    set status='cancelled',cancelled_at=now(),cancelled_by=v_actor,
        cancel_reason='[反结账] '||btrim(p_reason)
    where id=v_run.id returning * into v_run;
  else
    raise exception using errcode='23514',message='当前关账状态不允许执行该操作';
  end if;
  return v_run;
end;
$function$;

revoke all on function public.generate_fms_profit_loss_carryforward(uuid) from public;
grant execute on function public.generate_fms_profit_loss_carryforward(uuid) to authenticated;
;
