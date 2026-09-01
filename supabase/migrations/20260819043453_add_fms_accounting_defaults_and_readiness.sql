
create or replace function public.fms_accounting_readiness(p_account_set_id uuid)
returns jsonb
language plpgsql
stable
set search_path to ''
as $function$
declare
  v_set public.fms_account_set%rowtype;
  v_missing_subjects jsonb;
  v_missing_rules jsonb;
  v_subject_count integer;
  v_rule_count integer;
  v_statement_item_count integer;
  v_statement_mapping_count integer;
  v_open_period_count integer;
  v_fund_account_count integer;
begin
  select * into v_set
  from public.fms_account_set
  where id=p_account_set_id
    and (
      (select app_private.is_platform_super())
      or tenant_id=(select app_private.current_user_tenant_id())
    );
  if not found then
    raise exception using errcode='42501',message='无权查看该账套核算就绪度';
  end if;

  select count(*)::integer into v_subject_count
  from public.fms_subject where account_set_id=v_set.id and is_enabled;

  with required(code) as (
    values
      ('100201'),('112101'),('112299'),('160101'),('160201'),('160301'),
      ('220101'),('220201'),('221101'),('221102'),('222101'),
      ('600101'),('630101'),('640101'),('660201'),('671101'),('680101')
  )
  select coalesce(jsonb_agg(code order by code),'[]'::jsonb)
  into v_missing_subjects
  from required r
  where not exists (
    select 1 from public.fms_subject s
    where s.account_set_id=v_set.id and s.subject_code=r.code and s.is_enabled
  );

  select count(*)::integer into v_rule_count
  from public.fms_posting_rule
  where account_set_id=v_set.id and is_enabled;

  with required(code) as (
    values
      ('CUSTOMER_STATEMENT_CONFIRMED'),('CARRIER_STATEMENT_CONFIRMED'),
      ('CUSTOMER_RECEIPT_RECORDED'),('CARRIER_PAYMENT_RECORDED'),
      ('INVOICE_OUTPUT_ISSUED'),('INVOICE_INPUT_CERTIFIED'),
      ('EXPENSE_REIMBURSEMENT_PAID'),('WAYBILL_COST_APPROVED'),
      ('COMMERCIAL_BILL_RECEIVED'),('COMMERCIAL_BILL_ISSUED'),
      ('COMMERCIAL_BILL_ENDORSED'),('COMMERCIAL_BILL_DISCOUNTED'),
      ('COMMERCIAL_BILL_SETTLED_RECEIVABLE'),('COMMERCIAL_BILL_SETTLED_PAYABLE'),
      ('FIXED_ASSET_ACTIVATED'),('FIXED_ASSET_DISPOSED'),
      ('ASSET_DEPRECIATION_POSTED'),('PAYROLL_ACCRUED'),('PAYROLL_PAID'),
      ('TAX_REVIEWED'),('TAX_PAID')
  )
  select coalesce(jsonb_agg(code order by code),'[]'::jsonb)
  into v_missing_rules
  from required r
  where not exists (
    select 1 from public.fms_posting_rule pr
    where pr.account_set_id=v_set.id and pr.rule_code=r.code and pr.is_enabled
  );

  select count(*)::integer into v_statement_item_count
  from public.fms_financial_statement_item
  where account_set_id=v_set.id and is_enabled;
  select count(*)::integer into v_statement_mapping_count
  from public.fms_financial_statement_mapping where account_set_id=v_set.id;
  select count(*)::integer into v_open_period_count
  from public.fms_accounting_period
  where account_set_id=v_set.id and status='open';
  select count(*)::integer into v_fund_account_count
  from public.fms_fund_account
  where account_set_id=v_set.id and status='active';

  return jsonb_build_object(
    'accountSetId',v_set.id,
    'accountSetStatus',v_set.status,
    'subjectCount',v_subject_count,
    'missingSubjectCodes',v_missing_subjects,
    'postingRuleCount',v_rule_count,
    'missingPostingRuleCodes',v_missing_rules,
    'statementItemCount',v_statement_item_count,
    'statementMappingCount',v_statement_mapping_count,
    'openPeriodCount',v_open_period_count,
    'fundAccountCount',v_fund_account_count,
    'foundationReady',
      jsonb_array_length(v_missing_subjects)=0
      and jsonb_array_length(v_missing_rules)=0
      and v_statement_item_count>0
      and v_statement_mapping_count>0
      and v_open_period_count>0,
    'transactionReady',
      jsonb_array_length(v_missing_subjects)=0
      and jsonb_array_length(v_missing_rules)=0
      and v_open_period_count>0
      and v_fund_account_count>0
  );
end;
$function$;

create or replace function public.initialize_fms_accounting_defaults(p_account_set_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_set public.fms_account_set%rowtype;
  v_actor text:=coalesce(auth.jwt()->>'email',auth.uid()::text,'system');
  v_subjects_inserted integer:=0;
  v_rules_inserted integer:=0;
  v_mappings_inserted integer:=0;
  v_rows integer:=0;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode='42501',message='仅平台超级管理员可初始化核算基础';
  end if;
  select * into v_set from public.fms_account_set where id=p_account_set_id for update;
  if not found then raise exception using errcode='P0002',message='账套不存在'; end if;
  if v_set.status='archived' then
    raise exception using errcode='23514',message='归档账套不能重新初始化';
  end if;

  insert into public.fms_subject(
    tenant_id,account_set_id,subject_code,subject_name,category,balance_direction,
    is_system,is_enabled,cash_flow_required,sort,remark,create_by,update_by
  )
  select v_set.tenant_id,v_set.id,x.code,x.name,x.category,x.direction,
         true,true,x.cash_flow_required,x.sort,'系统核心核算科目',v_actor,v_actor
  from (values
    ('1001','库存现金','asset','debit',true,10),
    ('1002','银行存款','asset','debit',true,20),
    ('1121','应收票据','asset','debit',false,30),
    ('1122','应收账款','asset','debit',false,40),
    ('1123','预付账款','asset','debit',false,50),
    ('1221','其他应收款','asset','debit',false,60),
    ('1601','固定资产','asset','debit',false,70),
    ('1602','累计折旧','asset','credit',false,80),
    ('1603','固定资产减值准备','asset','credit',false,90),
    ('2001','短期借款','liability','credit',false,100),
    ('2201','应付票据','liability','credit',false,110),
    ('2202','应付账款','liability','credit',false,120),
    ('2211','应付职工薪酬','liability','credit',false,130),
    ('2221','应交税费','liability','credit',false,140),
    ('2241','其他应付款','liability','credit',false,150),
    ('4001','实收资本','equity','credit',false,160),
    ('4103','本年利润','equity','credit',false,170),
    ('4104','利润分配','equity','credit',false,180),
    ('6001','主营业务收入','income','credit',false,200),
    ('6051','其他业务收入','income','credit',false,210),
    ('6301','营业外收入','income','credit',false,220),
    ('6401','主营业务成本','expense','debit',false,230),
    ('6402','其他业务成本','expense','debit',false,240),
    ('6601','销售费用','expense','debit',false,250),
    ('6602','管理费用','expense','debit',false,260),
    ('6603','财务费用','expense','debit',false,270),
    ('6711','营业外支出','expense','debit',false,280),
    ('6801','所得税费用','expense','debit',false,290)
  ) as x(code,name,category,direction,cash_flow_required,sort)
  on conflict(account_set_id,subject_code) do nothing;
  get diagnostics v_rows=row_count;
  v_subjects_inserted:=v_subjects_inserted+v_rows;

  insert into public.fms_subject(
    tenant_id,account_set_id,parent_id,subject_code,subject_name,category,balance_direction,
    is_system,is_enabled,cash_flow_required,sort,remark,create_by,update_by
  )
  select v_set.tenant_id,v_set.id,parent.id,x.code,x.name,parent.category,parent.balance_direction,
         true,true,x.cash_flow_required,x.sort,'系统自动入账明细科目',v_actor,v_actor
  from (values
    ('1002','100201','自动入账银行存款',true,21),
    ('1121','112101','自动入账应收票据',false,31),
    ('1122','112299','自动入账应收款',false,49),
    ('1601','160101','固定资产明细',false,71),
    ('1602','160201','累计折旧明细',false,81),
    ('1603','160301','资产减值准备明细',false,91),
    ('2201','220101','自动入账应付票据',false,111),
    ('2202','220201','自动入账应付款',false,121),
    ('2211','221101','应付工资',false,131),
    ('2211','221102','社会保险费',false,132),
    ('2221','222101','自动入账应交税费',false,141),
    ('6001','600101','运输服务收入',false,201),
    ('6301','630101','资产处置收益',false,221),
    ('6401','640101','运输服务成本',false,231),
    ('6602','660201','日常管理费用',false,261),
    ('6711','671101','资产处置损失',false,281),
    ('6801','680101','所得税费用明细',false,291)
  ) as x(parent_code,code,name,cash_flow_required,sort)
  join public.fms_subject parent
    on parent.account_set_id=v_set.id and parent.subject_code=x.parent_code
  on conflict(account_set_id,subject_code) do nothing;
  get diagnostics v_rows=row_count;
  v_subjects_inserted:=v_subjects_inserted+v_rows;

  update public.fms_subject
  set cash_flow_required=true,update_by=v_actor,update_time=now()
  where account_set_id=v_set.id and subject_code in ('1001','1002','100201')
    and not cash_flow_required;

  perform public.initialize_fms_financial_statement_items(v_set.id);

  with mapping_seed(item_code,subject_code,direction,factor) as (
    values
      ('BS010','1001','net_debit',1::numeric),('BS010','1002','net_debit',1),
      ('BS020','1121','net_debit',1),('BS020','1122','net_debit',1),
      ('BS030','1123','net_debit',1),('BS040','1221','net_debit',1),
      ('BS120','1601','net_debit',1),('BS120','1602','net_credit',-1),
      ('BS120','1603','net_credit',-1),('BS210','2001','net_credit',1),
      ('BS220','2201','net_credit',1),('BS220','2202','net_credit',1),
      ('BS240','2211','net_credit',1),('BS250','2221','net_credit',1),
      ('BS260','2241','net_credit',1),('BS410','4001','net_credit',1),
      ('BS440','4103','net_credit',1),('BS440','4104','net_credit',1),
      ('IS010','6001','credit',1),('IS010','6051','credit',1),
      ('IS020','6401','debit',1),('IS020','6402','debit',1),
      ('IS040','6601','debit',1),('IS050','6602','debit',1),
      ('IS070','6603','debit',1),('IS210','6301','credit',1),
      ('IS220','6711','debit',1),('IS310','6801','debit',1)
  )
  insert into public.fms_financial_statement_mapping(
    tenant_id,account_set_id,statement_item_id,subject_id,mapping_direction,
    factor,remark,create_by,update_by
  )
  select v_set.tenant_id,v_set.id,item.id,subject.id,m.direction,m.factor,
         '系统核心科目默认映射',v_actor,v_actor
  from mapping_seed m
  join public.fms_financial_statement_item item
    on item.account_set_id=v_set.id and item.item_code=m.item_code
  join public.fms_subject subject
    on subject.account_set_id=v_set.id and subject.subject_code=m.subject_code
  on conflict(statement_item_id,subject_id) do nothing;
  get diagnostics v_mappings_inserted=row_count;

  with rule_seed(rule_code,rule_name,source_type,event_code,voucher_type,match_conditions,priority) as (
    values
      ('CUSTOMER_STATEMENT_CONFIRMED','客户对账确认','customer_statement','confirmed','general','{}'::jsonb,100),
      ('CARRIER_STATEMENT_CONFIRMED','承运商对账确认','carrier_statement','confirmed','general','{}'::jsonb,100),
      ('CUSTOMER_RECEIPT_RECORDED','客户收款登记','customer_receipt','recorded','receipt','{}'::jsonb,100),
      ('CARRIER_PAYMENT_RECORDED','承运商付款登记','carrier_payment','recorded','payment','{}'::jsonb,100),
      ('INVOICE_OUTPUT_ISSUED','销项发票开具','invoice','output_issued','general','{}'::jsonb,100),
      ('INVOICE_INPUT_CERTIFIED','进项发票认证','invoice','input_certified','general','{}'::jsonb,100),
      ('EXPENSE_REIMBURSEMENT_PAID','费用报销付款','expense_reimbursement','paid','payment','{}'::jsonb,100),
      ('WAYBILL_COST_APPROVED','运单费用审核','waybill_cost','approved','general','{}'::jsonb,100),
      ('COMMERCIAL_BILL_RECEIVED','应收票据确认收票','commercial_bill','received','general','{}'::jsonb,100),
      ('COMMERCIAL_BILL_ISSUED','应付票据确认出票','commercial_bill','issued','general','{}'::jsonb,100),
      ('COMMERCIAL_BILL_ENDORSED','商业票据背书','commercial_bill','endorsed','general','{}'::jsonb,100),
      ('COMMERCIAL_BILL_DISCOUNTED','应收票据贴现','commercial_bill','discounted','receipt','{}'::jsonb,100),
      ('COMMERCIAL_BILL_SETTLED_RECEIVABLE','应收票据到期结算','commercial_bill','settled','receipt','{"direction":"receivable"}'::jsonb,110),
      ('COMMERCIAL_BILL_SETTLED_PAYABLE','应付票据到期结算','commercial_bill','settled','payment','{"direction":"payable"}'::jsonb,110),
      ('FIXED_ASSET_ACTIVATED','固定资产转固','fixed_asset','activated','general','{}'::jsonb,100),
      ('FIXED_ASSET_DISPOSED','固定资产处置','fixed_asset','disposed','general','{}'::jsonb,100),
      ('ASSET_DEPRECIATION_POSTED','固定资产折旧确认','asset_depreciation','posted','adjustment','{}'::jsonb,100),
      ('PAYROLL_ACCRUED','薪资计提','payroll','accrued','general','{}'::jsonb,100),
      ('PAYROLL_PAID','薪资发放','payroll','paid','payment','{}'::jsonb,100),
      ('TAX_REVIEWED','税费计提复核','tax','reviewed','general','{}'::jsonb,100),
      ('TAX_PAID','税费缴纳','tax','paid','payment','{}'::jsonb,100)
  )
  insert into public.fms_posting_rule(
    tenant_id,account_set_id,rule_code,rule_name,source_type,event_code,
    voucher_type,submission_mode,match_conditions,priority,is_enabled,remark,create_by,update_by
  )
  select v_set.tenant_id,v_set.id,r.rule_code,r.rule_name,r.source_type,r.event_code,
         r.voucher_type,'pending_review',r.match_conditions,r.priority,true,
         '系统核心业务默认制证规则',v_actor,v_actor
  from rule_seed r
  on conflict(account_set_id,rule_code) do nothing;
  get diagnostics v_rules_inserted=row_count;

  with line_seed(rule_code,line_no,direction,amount_key,subject_code,cash_item_code,summary) as (
    values
      ('CUSTOMER_STATEMENT_CONFIRMED',1,'debit','gross_amount','112299',null,'确认客户应收'),
      ('CUSTOMER_STATEMENT_CONFIRMED',2,'credit','gross_amount','600101',null,'确认运输收入'),
      ('CARRIER_STATEMENT_CONFIRMED',1,'debit','gross_amount','640101',null,'确认运输成本'),
      ('CARRIER_STATEMENT_CONFIRMED',2,'credit','gross_amount','220201',null,'确认承运商应付'),
      ('CUSTOMER_RECEIPT_RECORDED',1,'debit','gross_amount','100201','CF020','客户收款'),
      ('CUSTOMER_RECEIPT_RECORDED',2,'credit','gross_amount','112299',null,'核销客户应收'),
      ('CARRIER_PAYMENT_RECORDED',1,'debit','gross_amount','220201',null,'核销承运商应付'),
      ('CARRIER_PAYMENT_RECORDED',2,'credit','gross_amount','100201','CF050','承运商付款'),
      ('INVOICE_OUTPUT_ISSUED',1,'debit','gross_amount','112299',null,'销项发票应收'),
      ('INVOICE_OUTPUT_ISSUED',2,'credit','net_amount','600101',null,'销项不含税收入'),
      ('INVOICE_OUTPUT_ISSUED',3,'credit','tax_amount','222101',null,'销项税额'),
      ('INVOICE_INPUT_CERTIFIED',1,'debit','net_amount','640101',null,'进项不含税成本'),
      ('INVOICE_INPUT_CERTIFIED',2,'debit','tax_amount','222101',null,'可抵扣进项税额'),
      ('INVOICE_INPUT_CERTIFIED',3,'credit','gross_amount','220201',null,'进项发票应付'),
      ('EXPENSE_REIMBURSEMENT_PAID',1,'debit','gross_amount','660201',null,'费用报销'),
      ('EXPENSE_REIMBURSEMENT_PAID',2,'credit','gross_amount','100201','CF080','报销付款'),
      ('WAYBILL_COST_APPROVED',1,'debit','gross_amount','640101',null,'运单成本'),
      ('WAYBILL_COST_APPROVED',2,'credit','gross_amount','220201',null,'运单费用应付'),
      ('COMMERCIAL_BILL_RECEIVED',1,'debit','gross_amount','112101',null,'确认应收票据'),
      ('COMMERCIAL_BILL_RECEIVED',2,'credit','gross_amount','112299',null,'应收账款转票据'),
      ('COMMERCIAL_BILL_ISSUED',1,'debit','gross_amount','220201',null,'应付账款转票据'),
      ('COMMERCIAL_BILL_ISSUED',2,'credit','gross_amount','220101',null,'确认应付票据'),
      ('COMMERCIAL_BILL_ENDORSED',1,'debit','gross_amount','220201',null,'票据背书清偿应付'),
      ('COMMERCIAL_BILL_ENDORSED',2,'credit','gross_amount','112101',null,'转出应收票据'),
      ('COMMERCIAL_BILL_DISCOUNTED',1,'debit','gross_amount','100201','CF040','票据贴现收款'),
      ('COMMERCIAL_BILL_DISCOUNTED',2,'credit','gross_amount','112101',null,'转出应收票据'),
      ('COMMERCIAL_BILL_SETTLED_RECEIVABLE',1,'debit','gross_amount','100201','CF020','应收票据到期收款'),
      ('COMMERCIAL_BILL_SETTLED_RECEIVABLE',2,'credit','gross_amount','112101',null,'结清应收票据'),
      ('COMMERCIAL_BILL_SETTLED_PAYABLE',1,'debit','gross_amount','220101',null,'结清应付票据'),
      ('COMMERCIAL_BILL_SETTLED_PAYABLE',2,'credit','gross_amount','100201','CF050','应付票据到期付款'),
      ('FIXED_ASSET_ACTIVATED',1,'debit','original_value','160101',null,'固定资产转固'),
      ('FIXED_ASSET_ACTIVATED',2,'credit','original_value','220201',null,'固定资产购置应付'),
      ('FIXED_ASSET_DISPOSED',1,'debit','gross_amount','100201','CF130','资产处置收款'),
      ('FIXED_ASSET_DISPOSED',2,'debit','accumulated_depreciation','160201',null,'转销累计折旧'),
      ('FIXED_ASSET_DISPOSED',3,'debit','impairment_amount','160301',null,'转销资产减值'),
      ('FIXED_ASSET_DISPOSED',4,'debit','disposal_loss','671101',null,'确认资产处置损失'),
      ('FIXED_ASSET_DISPOSED',5,'credit','original_value','160101',null,'转销固定资产原值'),
      ('FIXED_ASSET_DISPOSED',6,'credit','disposal_gain','630101',null,'确认资产处置收益'),
      ('ASSET_DEPRECIATION_POSTED',1,'debit','gross_amount','660201',null,'计提固定资产折旧'),
      ('ASSET_DEPRECIATION_POSTED',2,'credit','gross_amount','160201',null,'累计折旧'),
      ('PAYROLL_ACCRUED',1,'debit','salary_gross_amount','660201',null,'计提应发薪资'),
      ('PAYROLL_ACCRUED',2,'debit','employer_cost_amount','660201',null,'计提企业人工成本'),
      ('PAYROLL_ACCRUED',3,'credit','net_amount','221101',null,'应付实发工资'),
      ('PAYROLL_ACCRUED',4,'credit','deduction_amount','222101',null,'代扣税费'),
      ('PAYROLL_ACCRUED',5,'credit','employer_cost_amount','221102',null,'应付企业社保'),
      ('PAYROLL_PAID',1,'debit','gross_amount','221101',null,'发放工资'),
      ('PAYROLL_PAID',2,'credit','gross_amount','100201','CF060','工资付款'),
      ('TAX_REVIEWED',1,'debit','gross_amount','680101',null,'计提税费'),
      ('TAX_REVIEWED',2,'credit','gross_amount','222101',null,'应交税费'),
      ('TAX_PAID',1,'debit','gross_amount','222101',null,'缴纳税费'),
      ('TAX_PAID',2,'credit','gross_amount','100201','CF070','税费付款')
  ), empty_rules as (
    select r.id,r.rule_code
    from public.fms_posting_rule r
    where r.account_set_id=v_set.id
      and exists(select 1 from line_seed s where s.rule_code=r.rule_code)
      and not exists(select 1 from public.fms_posting_rule_line l where l.rule_id=r.id)
  )
  insert into public.fms_posting_rule_line(
    tenant_id,account_set_id,rule_id,line_no,direction,amount_key,amount_multiplier,
    subject_id,cash_flow_item_id,summary,auxiliary_bindings,create_by,update_by
  )
  select v_set.tenant_id,v_set.id,r.id,s.line_no,s.direction,s.amount_key,1,
         subject.id,cash_item.id,s.summary,'{}'::jsonb,v_actor,v_actor
  from line_seed s
  join empty_rules r on r.rule_code=s.rule_code
  join public.fms_subject subject
    on subject.account_set_id=v_set.id and subject.subject_code=s.subject_code
  left join public.fms_financial_statement_item cash_item
    on cash_item.account_set_id=v_set.id and cash_item.item_code=s.cash_item_code;

  return public.fms_accounting_readiness(v_set.id)
    || jsonb_build_object(
      'subjectsInserted',v_subjects_inserted,
      'rulesInserted',v_rules_inserted,
      'statementMappingsInserted',v_mappings_inserted
    );
end;
$function$;

revoke all on function public.fms_accounting_readiness(uuid) from public;
revoke all on function public.initialize_fms_accounting_defaults(uuid) from public;
grant execute on function public.fms_accounting_readiness(uuid) to authenticated;
grant execute on function public.initialize_fms_accounting_defaults(uuid) to authenticated;
;
