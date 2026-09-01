begin;

create or replace function public.save_fms_payroll_run(p_payload jsonb)
returns public.fms_payroll_run
language plpgsql security invoker set search_path = '' as $$
declare
  v_id uuid := nullif(p_payload ->> 'id','')::uuid;
  v_period public.fms_accounting_period%rowtype;
  v_row public.fms_payroll_run%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可维护薪资批次';
  end if;
  select * into v_period from public.fms_accounting_period
  where id=nullif(p_payload ->> 'accountingPeriodId','')::uuid;
  if not found or v_period.status<>'open' then
    raise exception using errcode='23514',message='请选择开放中的会计期间';
  end if;
  if v_id is null then
    insert into public.fms_payroll_run(
      tenant_id,account_set_id,accounting_period_id,run_no,payroll_month,
      salary_expense_subject_id,salary_payable_subject_id,tax_payable_subject_id,
      social_security_payable_subject_id,remark
    ) values(
      v_period.tenant_id,v_period.account_set_id,v_period.id,'',date_trunc('month',v_period.end_date)::date,
      nullif(p_payload ->> 'salaryExpenseSubjectId','')::uuid,
      nullif(p_payload ->> 'salaryPayableSubjectId','')::uuid,
      nullif(p_payload ->> 'taxPayableSubjectId','')::uuid,
      nullif(p_payload ->> 'socialSecurityPayableSubjectId','')::uuid,
      nullif(btrim(p_payload ->> 'remark'),'')
    ) returning * into v_row;
  else
    select * into v_row from public.fms_payroll_run where id=v_id for update;
    if not found then raise exception using errcode='P0002',message='薪资批次不存在'; end if;
    if v_row.status not in ('draft','calculated') then
      raise exception using errcode='23514',message='当前薪资批次不允许编辑';
    end if;
    if v_row.accounting_period_id<>v_period.id then
      raise exception using errcode='23514',message='薪资批次会计期间不可变更';
    end if;
    update public.fms_payroll_run set
      salary_expense_subject_id=nullif(p_payload ->> 'salaryExpenseSubjectId','')::uuid,
      salary_payable_subject_id=nullif(p_payload ->> 'salaryPayableSubjectId','')::uuid,
      tax_payable_subject_id=nullif(p_payload ->> 'taxPayableSubjectId','')::uuid,
      social_security_payable_subject_id=nullif(p_payload ->> 'socialSecurityPayableSubjectId','')::uuid,
      remark=nullif(btrim(p_payload ->> 'remark'),'')
    where id=v_id returning * into v_row;
  end if;
  return v_row;
end;
$$;

create or replace function public.save_fms_payroll_line(p_run_id uuid,p_payload jsonb)
returns public.fms_payroll_line
language plpgsql security invoker set search_path = '' as $$
declare
  v_run public.fms_payroll_run%rowtype;
  v_employee public.hr_employee%rowtype;
  v_line public.fms_payroll_line%rowtype;
  v_gross numeric(20,2):=coalesce(nullif(p_payload ->> 'grossAmount','')::numeric,0);
  v_deduction numeric(20,2):=coalesce(nullif(p_payload ->> 'deductionAmount','')::numeric,0);
  v_employer numeric(20,2):=coalesce(nullif(p_payload ->> 'employerCostAmount','')::numeric,0);
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可维护薪资明细';
  end if;
  select * into v_run from public.fms_payroll_run where id=p_run_id for update;
  if not found or v_run.status not in ('draft','calculated') then
    raise exception using errcode='23514',message='薪资批次不存在或当前状态不允许编辑';
  end if;
  select * into v_employee from public.hr_employee
  where id=nullif(p_payload ->> 'employeeId','')::uuid and tenant_id=v_run.tenant_id;
  if not found then raise exception using errcode='23503',message='员工不存在或不属于当前租户'; end if;
  if v_deduction>v_gross then raise exception using errcode='23514',message='扣款金额不能超过应发金额'; end if;

  insert into public.fms_payroll_line(
    tenant_id,account_set_id,run_id,employee_id,employee_no_snapshot,employee_name_snapshot,
    department_name_snapshot,earning_items,deduction_items,employer_cost_items,
    gross_amount,deduction_amount,employer_cost_amount,net_amount,remark
  ) values(
    v_run.tenant_id,v_run.account_set_id,v_run.id,v_employee.id,v_employee.employee_no,v_employee.employee_name,
    null,coalesce(p_payload -> 'earningItems','{}'::jsonb),coalesce(p_payload -> 'deductionItems','{}'::jsonb),
    coalesce(p_payload -> 'employerCostItems','{}'::jsonb),v_gross,v_deduction,v_employer,v_gross-v_deduction,
    nullif(btrim(p_payload ->> 'remark'),'')
  ) on conflict(run_id,employee_id) do update set
    employee_no_snapshot=excluded.employee_no_snapshot,employee_name_snapshot=excluded.employee_name_snapshot,
    department_name_snapshot=excluded.department_name_snapshot,earning_items=excluded.earning_items,
    deduction_items=excluded.deduction_items,employer_cost_items=excluded.employer_cost_items,
    gross_amount=excluded.gross_amount,deduction_amount=excluded.deduction_amount,
    employer_cost_amount=excluded.employer_cost_amount,net_amount=excluded.net_amount,remark=excluded.remark
  returning * into v_line;

  update public.fms_payroll_run r set
    employee_count=x.employee_count,gross_amount=x.gross_amount,deduction_amount=x.deduction_amount,
    employer_cost_amount=x.employer_cost_amount,net_amount=x.net_amount,
    status=case when x.employee_count>0 then 'calculated' else 'draft' end,
    calculated_at=case when x.employee_count>0 then now() else null end
  from (
    select count(*)::integer employee_count,coalesce(sum(gross_amount),0)::numeric gross_amount,
      coalesce(sum(deduction_amount),0)::numeric deduction_amount,
      coalesce(sum(employer_cost_amount),0)::numeric employer_cost_amount,
      coalesce(sum(net_amount),0)::numeric net_amount
    from public.fms_payroll_line where run_id=v_run.id
  ) x where r.id=v_run.id;
  return v_line;
end;
$$;

create or replace function public.delete_fms_payroll_line(p_line_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare v_run_id uuid;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可删除薪资明细';
  end if;
  select l.run_id into v_run_id from public.fms_payroll_line l join public.fms_payroll_run r on r.id=l.run_id
  where l.id=p_line_id and r.status in ('draft','calculated') for update of r;
  if not found then raise exception using errcode='23514',message='薪资明细不存在或当前状态不允许删除'; end if;
  delete from public.fms_payroll_line where id=p_line_id;
  update public.fms_payroll_run r set
    employee_count=x.employee_count,gross_amount=x.gross_amount,deduction_amount=x.deduction_amount,
    employer_cost_amount=x.employer_cost_amount,net_amount=x.net_amount,
    status=case when x.employee_count>0 then 'calculated' else 'draft' end,
    calculated_at=case when x.employee_count>0 then now() else null end
  from (
    select count(*)::integer employee_count,coalesce(sum(gross_amount),0)::numeric gross_amount,
      coalesce(sum(deduction_amount),0)::numeric deduction_amount,
      coalesce(sum(employer_cost_amount),0)::numeric employer_cost_amount,
      coalesce(sum(net_amount),0)::numeric net_amount
    from public.fms_payroll_line where run_id=v_run_id
  ) x where r.id=v_run_id;
end;
$$;

create or replace function public.act_fms_payroll_run(p_run_id uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns public.fms_payroll_run
language plpgsql security definer set search_path = '' as $$
declare
  v_run public.fms_payroll_run%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_actor text:=coalesce(auth.jwt()->>'email',auth.uid()::text,'system');
  v_action_date date:=coalesce(nullif(p_payload ->> 'actionDate','')::date,current_date);
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可执行薪资操作';
  end if;
  select * into v_run from public.fms_payroll_run where id=p_run_id for update;
  if not found then raise exception using errcode='P0002',message='薪资批次不存在'; end if;
  select * into v_period from public.fms_accounting_period where id=v_run.accounting_period_id;
  if p_action='approve' and v_run.status='calculated' then
    if v_run.employee_count=0 then raise exception using errcode='23514',message='薪资批次没有员工明细'; end if;
    update public.fms_payroll_run set status='approved',approved_at=now(),approved_by=v_actor
    where id=v_run.id returning * into v_run;
    perform app_private.enqueue_fms_posting_event(
      v_run.tenant_id,'payroll','accrued',v_run.id,v_run.run_no,v_period.end_date,
      concat(to_char(v_run.payroll_month,'YYYY-MM'),' 薪资计提'),
      jsonb_build_object('gross_amount',v_run.gross_amount+v_run.employer_cost_amount,'run_id',v_run.id,
        'salary_gross_amount',v_run.gross_amount,'deduction_amount',v_run.deduction_amount,
        'employer_cost_amount',v_run.employer_cost_amount,'net_amount',v_run.net_amount)
    );
  elsif p_action='pay' and v_run.status='approved' then
    update public.fms_payroll_run set status='paid',paid_at=now() where id=v_run.id returning * into v_run;
    perform app_private.enqueue_fms_posting_event(
      v_run.tenant_id,'payroll','paid',v_run.id,v_run.run_no,v_action_date,
      concat(to_char(v_run.payroll_month,'YYYY-MM'),' 薪资发放'),
      jsonb_build_object('gross_amount',v_run.net_amount,'run_id',v_run.id,
        'fund_account_id',nullif(p_payload ->> 'fundAccountId',''),'reference_no',nullif(p_payload ->> 'referenceNo',''))
    );
  elsif p_action='cancel' and v_run.status in ('draft','calculated') then
    if nullif(btrim(p_payload ->> 'reason'),'') is null then
      raise exception using errcode='23502',message='取消薪资批次必须填写原因';
    end if;
    update public.fms_payroll_run set status='cancelled',remark=concat_ws(E'\n',remark,'[取消] '||btrim(p_payload ->> 'reason'))
    where id=v_run.id returning * into v_run;
  else
    raise exception using errcode='23514',message='当前薪资批次状态不允许执行该操作';
  end if;
  return v_run;
end;
$$;

create or replace function public.fms_payroll_summary(p_account_set_id uuid)
returns table(run_count bigint,employee_count bigint,gross_amount numeric,net_amount numeric,pending_count bigint)
language sql stable security invoker set search_path = '' as $$
  select count(*),coalesce(sum(employee_count),0),coalesce(sum(gross_amount),0),coalesce(sum(net_amount),0),
    count(*) filter(where status in ('draft','calculated','approved'))
  from public.fms_payroll_run where account_set_id=p_account_set_id and status<>'cancelled'
$$;

create or replace function public.save_fms_tax_period(p_payload jsonb)
returns public.fms_tax_period
language plpgsql security invoker set search_path = '' as $$
declare
  v_id uuid:=nullif(p_payload ->> 'id','')::uuid;
  v_period public.fms_accounting_period%rowtype;
  v_row public.fms_tax_period%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可维护税务期间';
  end if;
  select * into v_period from public.fms_accounting_period where id=nullif(p_payload ->> 'accountingPeriodId','')::uuid;
  if not found or v_period.status<>'open' then raise exception using errcode='23514',message='请选择开放中的会计期间'; end if;
  if v_id is null then
    insert into public.fms_tax_period(
      tenant_id,account_set_id,accounting_period_id,tax_type,transferable_input_amount,adjustment_amount,remark
    ) values(
      v_period.tenant_id,v_period.account_set_id,v_period.id,p_payload ->> 'taxType',
      coalesce(nullif(p_payload ->> 'transferableInputAmount','')::numeric,0),
      coalesce(nullif(p_payload ->> 'adjustmentAmount','')::numeric,0),nullif(btrim(p_payload ->> 'remark'),'')
    ) returning * into v_row;
  else
    select * into v_row from public.fms_tax_period where id=v_id for update;
    if not found then raise exception using errcode='P0002',message='税务期间不存在'; end if;
    if v_row.status not in ('draft','calculated') then raise exception using errcode='23514',message='当前税务期间不允许编辑'; end if;
    update public.fms_tax_period set
      transferable_input_amount=coalesce(nullif(p_payload ->> 'transferableInputAmount','')::numeric,transferable_input_amount),
      adjustment_amount=coalesce(nullif(p_payload ->> 'adjustmentAmount','')::numeric,adjustment_amount),
      remark=nullif(btrim(p_payload ->> 'remark'),'') where id=v_id returning * into v_row;
  end if;
  return v_row;
end;
$$;

create or replace function public.save_fms_tax_ledger_line(p_tax_period_id uuid,p_payload jsonb)
returns public.fms_tax_ledger_line
language plpgsql security invoker set search_path = '' as $$
declare
  v_id uuid:=nullif(p_payload ->> 'id','')::uuid;
  v_period public.fms_tax_period%rowtype;
  v_line public.fms_tax_ledger_line%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可维护税务台账';
  end if;
  select * into v_period from public.fms_tax_period where id=p_tax_period_id for update;
  if not found or v_period.status not in ('draft','calculated') then
    raise exception using errcode='23514',message='税务期间不存在或当前状态不允许编辑';
  end if;
  if v_id is null then
    insert into public.fms_tax_ledger_line(
      tenant_id,account_set_id,tax_period_id,source_type,source_id,source_no,occurred_on,direction,
      taxable_amount,tax_rate,tax_amount,is_deductible,remark
    ) values(
      v_period.tenant_id,v_period.account_set_id,v_period.id,btrim(p_payload ->> 'sourceType'),
      nullif(p_payload ->> 'sourceId','')::uuid,nullif(btrim(p_payload ->> 'sourceNo'),''),
      (p_payload ->> 'occurredOn')::date,p_payload ->> 'direction',
      coalesce(nullif(p_payload ->> 'taxableAmount','')::numeric,0),nullif(p_payload ->> 'taxRate','')::numeric,
      (p_payload ->> 'taxAmount')::numeric,coalesce((p_payload ->> 'isDeductible')::boolean,true),
      nullif(btrim(p_payload ->> 'remark'),'')
    ) returning * into v_line;
  else
    update public.fms_tax_ledger_line set
      source_type=btrim(p_payload ->> 'sourceType'),source_id=nullif(p_payload ->> 'sourceId','')::uuid,
      source_no=nullif(btrim(p_payload ->> 'sourceNo'),''),occurred_on=(p_payload ->> 'occurredOn')::date,
      direction=p_payload ->> 'direction',taxable_amount=coalesce(nullif(p_payload ->> 'taxableAmount','')::numeric,0),
      tax_rate=nullif(p_payload ->> 'taxRate','')::numeric,tax_amount=(p_payload ->> 'taxAmount')::numeric,
      is_deductible=coalesce((p_payload ->> 'isDeductible')::boolean,true),remark=nullif(btrim(p_payload ->> 'remark'),'')
    where id=v_id and tax_period_id=v_period.id returning * into v_line;
    if not found then raise exception using errcode='P0002',message='税务台账明细不存在'; end if;
  end if;

  update public.fms_tax_period t set
    output_tax_amount=x.output_amount,input_tax_amount=x.input_amount,
    payable_amount=greatest(x.output_amount-x.deductible_input-t.transferable_input_amount+t.adjustment_amount,0),
    status=case when x.line_count>0 then 'calculated' else 'draft' end
  from (
    select count(*) line_count,
      coalesce(sum(tax_amount) filter(where direction='output'),0)::numeric output_amount,
      coalesce(sum(tax_amount) filter(where direction='input'),0)::numeric input_amount,
      coalesce(sum(tax_amount) filter(where direction='input' and is_deductible),0)::numeric deductible_input
    from public.fms_tax_ledger_line where tax_period_id=v_period.id
  ) x where t.id=v_period.id;
  return v_line;
end;
$$;

create or replace function public.delete_fms_tax_ledger_line(p_line_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
declare v_period_id uuid;
begin
  if not (select app_private.is_platform_super()) then raise exception using errcode='42501',message='仅平台超级管理员可删除税务台账'; end if;
  select l.tax_period_id into v_period_id from public.fms_tax_ledger_line l join public.fms_tax_period t on t.id=l.tax_period_id
  where l.id=p_line_id and t.status in ('draft','calculated') for update of t;
  if not found then raise exception using errcode='23514',message='税务台账不存在或当前状态不允许删除'; end if;
  delete from public.fms_tax_ledger_line where id=p_line_id;
  update public.fms_tax_period t set
    output_tax_amount=x.output_amount,input_tax_amount=x.input_amount,
    payable_amount=greatest(x.output_amount-x.deductible_input-t.transferable_input_amount+t.adjustment_amount,0),
    status=case when x.line_count>0 then 'calculated' else 'draft' end
  from (
    select count(*) line_count,coalesce(sum(tax_amount) filter(where direction='output'),0)::numeric output_amount,
      coalesce(sum(tax_amount) filter(where direction='input'),0)::numeric input_amount,
      coalesce(sum(tax_amount) filter(where direction='input' and is_deductible),0)::numeric deductible_input
    from public.fms_tax_ledger_line where tax_period_id=v_period_id
  ) x where t.id=v_period_id;
end;
$$;

create or replace function public.act_fms_tax_period(p_tax_period_id uuid,p_action text,p_payload jsonb default '{}'::jsonb)
returns public.fms_tax_period
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.fms_tax_period%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_actor text:=coalesce(auth.jwt()->>'email',auth.uid()::text,'system');
  v_action_date date:=coalesce(nullif(p_payload ->> 'actionDate','')::date,current_date);
begin
  if not (select app_private.is_platform_super()) then raise exception using errcode='42501',message='仅平台超级管理员可执行税务操作'; end if;
  select * into v_row from public.fms_tax_period where id=p_tax_period_id for update;
  if not found then raise exception using errcode='P0002',message='税务期间不存在'; end if;
  select * into v_period from public.fms_accounting_period where id=v_row.accounting_period_id;
  if p_action='review' and v_row.status='calculated' then
    update public.fms_tax_period set status='reviewed' where id=v_row.id returning * into v_row;
    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id,'tax','reviewed',v_row.id,v_row.tax_type,v_period.end_date,
      concat(v_period.fiscal_year,'年第',v_period.period_no,'期 ',v_row.tax_type,' 税费计提'),
      jsonb_build_object('gross_amount',v_row.payable_amount,'tax_period_id',v_row.id,'tax_type',v_row.tax_type,
        'output_tax_amount',v_row.output_tax_amount,'input_tax_amount',v_row.input_tax_amount)
    );
  elsif p_action='file' and v_row.status='reviewed' then
    if nullif(btrim(p_payload ->> 'filingReference'),'') is null then
      raise exception using errcode='23502',message='申报必须填写申报凭证号';
    end if;
    update public.fms_tax_period set status='filed',filing_reference=btrim(p_payload ->> 'filingReference'),
      filed_at=now(),filed_by=v_actor where id=v_row.id returning * into v_row;
  elsif p_action='pay' and v_row.status='filed' then
    update public.fms_tax_period set status='paid',paid_at=now() where id=v_row.id returning * into v_row;
    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id,'tax','paid',v_row.id,v_row.tax_type,v_action_date,
      concat(v_period.fiscal_year,'年第',v_period.period_no,'期 ',v_row.tax_type,' 税费缴纳'),
      jsonb_build_object('gross_amount',v_row.payable_amount,'tax_period_id',v_row.id,'tax_type',v_row.tax_type,
        'fund_account_id',nullif(p_payload ->> 'fundAccountId',''),'reference_no',nullif(p_payload ->> 'referenceNo',''))
    );
  elsif p_action='cancel' and v_row.status in ('draft','calculated') then
    if nullif(btrim(p_payload ->> 'reason'),'') is null then raise exception using errcode='23502',message='取消税务期间必须填写原因'; end if;
    update public.fms_tax_period set status='cancelled',remark=concat_ws(E'\n',remark,'[取消] '||btrim(p_payload ->> 'reason'))
    where id=v_row.id returning * into v_row;
  else
    raise exception using errcode='23514',message='当前税务期间状态不允许执行该操作';
  end if;
  return v_row;
end;
$$;

create or replace function public.fms_tax_summary(p_account_set_id uuid)
returns table(period_count bigint,output_tax_amount numeric,input_tax_amount numeric,payable_amount numeric,pending_count bigint)
language sql stable security invoker set search_path = '' as $$
  select count(*),coalesce(sum(output_tax_amount),0),coalesce(sum(input_tax_amount),0),coalesce(sum(payable_amount),0),
    count(*) filter(where status in ('draft','calculated','reviewed','filed'))
  from public.fms_tax_period where account_set_id=p_account_set_id and status<>'cancelled'
$$;

revoke execute on function public.save_fms_payroll_run(jsonb) from public,anon;
revoke execute on function public.save_fms_payroll_line(uuid,jsonb) from public,anon;
revoke execute on function public.delete_fms_payroll_line(uuid) from public,anon;
revoke execute on function public.act_fms_payroll_run(uuid,text,jsonb) from public,anon;
revoke execute on function public.fms_payroll_summary(uuid) from public,anon;
revoke execute on function public.save_fms_tax_period(jsonb) from public,anon;
revoke execute on function public.save_fms_tax_ledger_line(uuid,jsonb) from public,anon;
revoke execute on function public.delete_fms_tax_ledger_line(uuid) from public,anon;
revoke execute on function public.act_fms_tax_period(uuid,text,jsonb) from public,anon;
revoke execute on function public.fms_tax_summary(uuid) from public,anon;
grant execute on function public.save_fms_payroll_run(jsonb) to authenticated,service_role;
grant execute on function public.save_fms_payroll_line(uuid,jsonb) to authenticated,service_role;
grant execute on function public.delete_fms_payroll_line(uuid) to authenticated,service_role;
grant execute on function public.act_fms_payroll_run(uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.fms_payroll_summary(uuid) to authenticated,service_role;
grant execute on function public.save_fms_tax_period(jsonb) to authenticated,service_role;
grant execute on function public.save_fms_tax_ledger_line(uuid,jsonb) to authenticated,service_role;
grant execute on function public.delete_fms_tax_ledger_line(uuid) to authenticated,service_role;
grant execute on function public.act_fms_tax_period(uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.fms_tax_summary(uuid) to authenticated,service_role;

with platform_tenant as(select id from public.sys_tenant where builtin_type='platform' limit 1),items as(
  select * from(values
    ('c2000000-0000-4000-8000-000000000169'::uuid,'payroll:accrued','薪资计提',29,'primary'),
    ('c2000000-0000-4000-8000-000000000170'::uuid,'payroll:paid','薪资发放',30,'success'),
    ('c2000000-0000-4000-8000-000000000171'::uuid,'tax:reviewed','税费计提复核',31,'primary'),
    ('c2000000-0000-4000-8000-000000000172'::uuid,'tax:paid','税费缴纳',32,'success')
  )i(id,value,label,sort,tag_type)
)
insert into public.sys_dictionary(id,type_id,code,status,value,label,sort,tag_type,create_by,update_by,tenant_id)
select i.id,'b2000000-0000-4000-8000-000000000013'::uuid,i.value,'1',i.value,i.label,i.sort,i.tag_type,
  '624944977@qq.com','624944977@qq.com',p.id from platform_tenant p cross join items i
on conflict(id) do update set type_id=excluded.type_id,code=excluded.code,status=excluded.status,value=excluded.value,
 label=excluded.label,sort=excluded.sort,tag_type=excluded.tag_type,update_by=excluded.update_by,update_time=now();

commit;

;
