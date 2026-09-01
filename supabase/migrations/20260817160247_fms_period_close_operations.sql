begin;

create or replace function public.run_fms_period_close_checks(p_accounting_period_id uuid)
returns public.fms_period_close_run
language plpgsql security invoker set search_path = '' as $$
declare
  v_period public.fms_accounting_period%rowtype;
  v_run public.fms_period_close_run%rowtype;
  v_issue_count bigint;
  v_debit numeric;
  v_credit numeric;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可执行月末关账检查';
  end if;
  select * into v_period from public.fms_accounting_period where id=p_accounting_period_id for update;
  if not found or v_period.status not in ('open','closing') then
    raise exception using errcode='23514',message='仅开放或关账中的会计期间可执行检查';
  end if;
  if v_period.status='open' then
    v_period:=public.set_fms_accounting_period_status(v_period.id,'closing',null);
  end if;

  select * into v_run from public.fms_period_close_run where accounting_period_id=v_period.id for update;
  if found and v_run.status='closed' then
    raise exception using errcode='23514',message='本期已结账，不能重复执行关账检查';
  elsif found then
    delete from public.fms_period_close_check where close_run_id=v_run.id;
    update public.fms_period_close_run set status='checking',passed_count=0,warning_count=0,
      blocking_count=0,completed_at=null,completed_by=null,cancelled_at=null,cancelled_by=null,cancel_reason=null
    where id=v_run.id returning * into v_run;
  else
    insert into public.fms_period_close_run(tenant_id,account_set_id,accounting_period_id,run_no)
    values(v_period.tenant_id,v_period.account_set_id,v_period.id,'') returning * into v_run;
  end if;

  select count(*) into v_issue_count
  from public.fms_opening_balance b
  where b.account_set_id=v_period.account_set_id and b.fiscal_year=v_period.fiscal_year
    and not exists(
      select 1 from public.fms_opening_balance_control c
      where c.account_set_id=b.account_set_id and c.fiscal_year=b.fiscal_year and c.status='confirmed'
    );
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'opening_balance','期初余额确认',
    case when v_issue_count=0 then 'passed' else 'blocked' end,true,v_issue_count,
    case when v_issue_count=0 then '期初余额已确认或本年度无期初数据' else '存在未确认的期初余额' end,
    jsonb_build_object('fiscalYear',v_period.fiscal_year)
  );

  select count(*) into v_issue_count from public.fms_voucher
  where accounting_period_id=v_period.id and status not in ('posted','reversed','voided');
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'voucher_posting','凭证记账完整性',
    case when v_issue_count=0 then 'passed' else 'blocked' end,true,v_issue_count,
    case when v_issue_count=0 then '本期凭证均已完成记账或终止处理' else '存在未记账凭证' end,'{}'::jsonb
  );

  select count(*) into v_issue_count from public.fms_voucher
  where accounting_period_id=v_period.id and status not in ('voided') and nullif(btrim(voucher_no),'') is null;
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'voucher_sequence','凭证编号连续性',
    case when v_issue_count=0 then 'passed' else 'blocked' end,true,v_issue_count,
    case when v_issue_count=0 then '本期凭证编号完整' else '存在缺失编号的凭证' end,'{}'::jsonb
  );

  select coalesce(sum(total_debit),0),coalesce(sum(total_credit),0) into v_debit,v_credit
  from public.fms_voucher where accounting_period_id=v_period.id and status='posted';
  v_issue_count:=case when v_debit=v_credit then 0 else 1 end;
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'trial_balance','试算平衡',
    case when v_issue_count=0 then 'passed' else 'blocked' end,true,v_issue_count,
    case when v_issue_count=0 then '本期借贷发生额平衡' else '本期借贷发生额不平衡' end,
    jsonb_build_object('debit',v_debit,'credit',v_credit,'difference',v_debit-v_credit)
  );

  select count(*) into v_issue_count from public.fms_bank_reconciliation_batch
  where account_set_id=v_period.account_set_id and statement_end_date between v_period.start_date and v_period.end_date
    and status not in ('reconciled','voided');
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'treasury_reconciliation','资金对账完成度',
    case when v_issue_count=0 then 'passed' else 'blocked' end,true,v_issue_count,
    case when v_issue_count=0 then '本期银行对账批次均已完成' else '存在未完成的银行对账批次' end,'{}'::jsonb
  );

  select count(*) into v_issue_count from public.fms_fixed_asset a
  where a.account_set_id=v_period.account_set_id and a.status='active' and a.depreciation_start_date<=v_period.end_date
    and a.depreciated_months<a.useful_life_months
    and not exists(select 1 from public.fms_asset_depreciation_run r where r.accounting_period_id=v_period.id and r.status='posted');
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'asset_depreciation','固定资产折旧',
    case when v_issue_count=0 then 'passed' else 'blocked' end,true,v_issue_count,
    case when v_issue_count=0 then '本期无待计提资产或折旧已确认' else '存在应计提但尚未确认折旧的资产' end,'{}'::jsonb
  );

  select count(*) into v_issue_count from public.hr_employee e
  where e.tenant_id=v_period.tenant_id and e.employment_status='active'
    and not exists(select 1 from public.fms_payroll_run r where r.accounting_period_id=v_period.id and r.status in ('approved','paid'));
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'payroll_accrual','薪资计提',
    case when v_issue_count=0 then 'passed' else 'warning' end,false,v_issue_count,
    case when v_issue_count=0 then '本期薪资已计提或当前无在职员工' else '当前有在职员工，但本期未发现已审批薪资批次' end,'{}'::jsonb
  );

  select count(*) into v_issue_count from public.fms_tax_period
  where accounting_period_id=v_period.id and status not in ('reviewed','filed','paid','cancelled');
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'tax_review','税务复核',
    case when v_issue_count=0 then 'passed' else 'blocked' end,true,v_issue_count,
    case when v_issue_count=0 then '本期税务期间均已复核或无税务数据' else '存在尚未复核的税务期间' end,'{}'::jsonb
  );

  select count(*) into v_issue_count from public.fms_subject s
  where s.account_set_id=v_period.account_set_id and s.category in ('income','expense') and s.is_enabled
    and not exists(
      select 1 from public.fms_voucher v where v.accounting_period_id=v_period.id
        and v.source_type='period_close' and v.status='posted'
    );
  insert into public.fms_period_close_check(
    tenant_id,account_set_id,close_run_id,check_code,check_name,status,is_blocking,issue_count,summary,detail
  ) values(
    v_period.tenant_id,v_period.account_set_id,v_run.id,'profit_loss_carryforward','损益结转复核',
    case when v_issue_count=0 then 'passed' else 'warning' end,false,v_issue_count,
    case when v_issue_count=0 then '无需损益结转或已存在结转凭证' else '请确认本期损益科目已按企业口径完成结转' end,
    jsonb_build_object('profitLossSubjectCount',v_issue_count)
  );

  update public.fms_period_close_run r set
    passed_count=x.passed_count,warning_count=x.warning_count,blocking_count=x.blocking_count,
    status=case when x.blocking_count=0 then 'ready' else 'checking' end
  from (
    select count(*) filter(where status='passed')::integer passed_count,
      count(*) filter(where status='warning')::integer warning_count,
      count(*) filter(where status='blocked')::integer blocking_count
    from public.fms_period_close_check where close_run_id=v_run.id
  ) x where r.id=v_run.id returning r.* into v_run;
  return v_run;
end;
$$;

create or replace function public.act_fms_period_close_run(p_run_id uuid,p_action text,p_reason text default null)
returns public.fms_period_close_run
language plpgsql security invoker set search_path = '' as $$
declare
  v_run public.fms_period_close_run%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_actor text:=coalesce(auth.jwt()->>'email',auth.uid()::text,'system');
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可执行结账或反结账';
  end if;
  select * into v_run from public.fms_period_close_run where id=p_run_id for update;
  if not found then raise exception using errcode='P0002',message='关账批次不存在'; end if;
  select * into v_period from public.fms_accounting_period where id=v_run.accounting_period_id for update;

  if p_action='close' and v_run.status='ready' then
    if v_run.blocking_count<>0 then raise exception using errcode='23514',message='仍有阻断项，不能结账'; end if;
    v_period:=public.set_fms_accounting_period_status(v_period.id,'closed',null);
    update public.fms_period_close_run set status='closed',completed_at=now(),completed_by=v_actor
    where id=v_run.id returning * into v_run;
  elsif p_action='cancel' and v_run.status in ('checking','ready') then
    if nullif(btrim(p_reason),'') is null then raise exception using errcode='23502',message='取消关账必须填写原因'; end if;
    v_period:=public.set_fms_accounting_period_status(v_period.id,'open',null);
    update public.fms_period_close_run set status='cancelled',cancelled_at=now(),cancelled_by=v_actor,cancel_reason=btrim(p_reason)
    where id=v_run.id returning * into v_run;
  elsif p_action='reopen' and v_run.status='closed' then
    if nullif(btrim(p_reason),'') is null then raise exception using errcode='23502',message='反结账必须填写原因'; end if;
    v_period:=public.set_fms_accounting_period_status(v_period.id,'open',p_reason);
    update public.fms_period_close_run set status='cancelled',cancelled_at=now(),cancelled_by=v_actor,cancel_reason='[反结账] '||btrim(p_reason)
    where id=v_run.id returning * into v_run;
  else
    raise exception using errcode='23514',message='当前关账状态不允许执行该操作';
  end if;
  return v_run;
end;
$$;

create or replace function public.fms_period_close_summary(p_account_set_id uuid)
returns table(period_count bigint,closed_count bigint,checking_count bigint,blocking_count bigint,latest_completed_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select count(*),count(*) filter(where status='closed'),count(*) filter(where status in ('checking','ready')),
    coalesce(sum(blocking_count) filter(where status in ('checking','ready')),0),max(completed_at)
  from public.fms_period_close_run where account_set_id=p_account_set_id
$$;

revoke execute on function public.run_fms_period_close_checks(uuid) from public,anon;
revoke execute on function public.act_fms_period_close_run(uuid,text,text) from public,anon;
revoke execute on function public.fms_period_close_summary(uuid) from public,anon;
grant execute on function public.run_fms_period_close_checks(uuid) to authenticated,service_role;
grant execute on function public.act_fms_period_close_run(uuid,text,text) to authenticated,service_role;
grant execute on function public.fms_period_close_summary(uuid) to authenticated,service_role;

commit;

;
