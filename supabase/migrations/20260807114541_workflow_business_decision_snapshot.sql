
create or replace function app_private.workflow_attachment_list(p_value jsonb)
returns jsonb
language sql
immutable
set search_path=''
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'name',coalesce(nullif(x->>'name',''),nullif(x->>'fileName',''),nullif(x->>'originalName',''),'附件'),
    'url',coalesce(nullif(x->>'url',''),nullif(x->>'fileUrl',''),nullif(x->>'downloadUrl','')),
    'fileType',coalesce(x->>'fileType',x->>'type'),
    'fileSize',coalesce(x->>'fileSize',x->>'size')
  )), '[]'::jsonb)
  from jsonb_array_elements(case when jsonb_typeof(p_value)='array' then p_value else '[]'::jsonb end) x
  where coalesce(nullif(x->>'url',''),nullif(x->>'fileUrl',''),nullif(x->>'downloadUrl','')) is not null
$function$;

create or replace function public.get_workflow_business_snapshot(p_instance_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $function$
declare
  v_i public.wf_instance;
  v_r record;
  v_result jsonb;
  v_metrics jsonb := '[]'::jsonb;
  v_fields jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_attachments jsonb := '[]'::jsonb;
  v_subtitle text;
  v_business_no text;
  v_status text;
  v_route text;
begin
  if (select auth.uid()) is null or not app_private.can_view_workflow_instance(p_instance_id) then
    raise exception '无权查看该审批业务信息' using errcode='42501';
  end if;
  select * into v_i from public.wf_instance where id=p_instance_id;
  if not found then raise exception '审批实例不存在'; end if;

  if v_i.business_type='tms_waybill_cost' then
    select c.*,w.waybill_no into v_r from public.tms_waybill_cost c
      left join public.tms_waybill w on w.id=c.waybill_id where c.id=v_i.business_id;
    if not found then v_warnings:=jsonb_build_array('业务原单已删除，当前仅展示流程快照'); else
      v_business_no:=v_r.waybill_no; v_status:=v_r.audit_status;
      v_subtitle:=concat_ws(' · ',v_r.cost_type,v_r.payee_name);
      v_metrics:=jsonb_build_array(
        jsonb_build_object('label','费用金额','value','¥ '||to_char(coalesce(v_r.amount,0),'FM999,999,990.00'),'tone','warning'),
        jsonb_build_object('label','发生日期','value',coalesce(v_r.occurred_on::text,'--'),'tone','info'));
      v_fields:=jsonb_build_array(
        jsonb_build_object('label','运单号','value',coalesce(v_r.waybill_no,'--')),
        jsonb_build_object('label','费用类型','value',coalesce(v_r.cost_type,'--')),
        jsonb_build_object('label','收款方','value',coalesce(v_r.payee_name,'--')),
        jsonb_build_object('label','备注','value',coalesce(v_r.remark,'--')));
      v_attachments:=app_private.workflow_attachment_list(v_r.attachments);
      v_route:='/tms-transportation/finance-management/waybill-cost';
    end if;

  elsif v_i.business_type='tms_invoice' then
    select * into v_r from public.tms_invoice where id=v_i.business_id;
    if not found then v_warnings:=jsonb_build_array('业务原单已删除，当前仅展示流程快照'); else
      v_business_no:=coalesce(v_r.invoice_no,v_r.invoice_record_no); v_status:=v_r.status;
      v_subtitle:=concat_ws(' · ',v_r.counterparty_name_snapshot,v_r.invoice_type);
      v_metrics:=jsonb_build_array(
        jsonb_build_object('label','含税金额','value','¥ '||to_char(coalesce(v_r.total_amount,0),'FM999,999,990.00'),'tone','warning'),
        jsonb_build_object('label','税额','value','¥ '||to_char(coalesce(v_r.tax_amount,0),'FM999,999,990.00'),'tone','info'),
        jsonb_build_object('label','税率','value',coalesce(v_r.tax_rate::text,'--')||'%','tone','info'));
      v_fields:=jsonb_build_array(
        jsonb_build_object('label','发票号码','value',coalesce(v_r.invoice_no,'--')),
        jsonb_build_object('label','开票方向','value',coalesce(v_r.direction,'--')),
        jsonb_build_object('label','发票抬头','value',coalesce(v_r.invoice_title,'--')),
        jsonb_build_object('label','开票日期','value',coalesce(v_r.issue_date::text,'--')));
      v_attachments:=app_private.workflow_attachment_list(v_r.attachments);
      v_route:='/tms-transportation/finance-management/invoice-management';
    end if;

  elsif v_i.business_type in ('tms_carrier_statement','tms_customer_statement') then
    if v_i.business_type='tms_carrier_statement' then
      select s.*,
        (select coalesce(sum(x.line_amount),0) from public.tms_carrier_statement_item x where x.statement_id=s.id and x.is_active) total_amount,
        (select count(*) from public.tms_carrier_statement_item x where x.statement_id=s.id and x.is_active) item_count
      into v_r from public.tms_carrier_statement s where s.id=v_i.business_id;
      v_route:='/tms-transportation/finance-management/carrier-settlement';
    else
      select s.*,
        (select coalesce(sum(x.line_amount),0) from public.tms_customer_statement_item x where x.statement_id=s.id and x.is_active) total_amount,
        (select count(*) from public.tms_customer_statement_item x where x.statement_id=s.id and x.is_active) item_count
      into v_r from public.tms_customer_statement s where s.id=v_i.business_id;
      v_route:='/tms-transportation/finance-management/customer-settlement';
    end if;
    if not found then v_warnings:=jsonb_build_array('业务原单已删除，当前仅展示流程快照'); else
      v_business_no:=v_r.statement_no; v_status:=v_r.status;
      v_subtitle:=case when v_i.business_type='tms_carrier_statement'
        then v_r.carrier_name_snapshot else v_r.customer_name_snapshot end;
      v_metrics:=jsonb_build_array(
        jsonb_build_object('label','对账金额','value','¥ '||to_char(coalesce(v_r.total_amount,0),'FM999,999,990.00'),'tone','warning'),
        jsonb_build_object('label','有效明细','value',v_r.item_count::text||' 条','tone','primary'),
        jsonb_build_object('label','已结算','value','¥ '||to_char(coalesce(v_r.settled_amount,0),'FM999,999,990.00'),'tone','success'));
      v_fields:=jsonb_build_array(
        jsonb_build_object('label','对账单号','value',coalesce(v_r.statement_no,'--')),
        jsonb_build_object('label','账期开始','value',coalesce(v_r.period_start::text,'--')),
        jsonb_build_object('label','账期结束','value',coalesce(v_r.period_end::text,'--')),
        jsonb_build_object('label','备注','value',coalesce(v_r.remark,'--')));
    end if;

  elsif v_i.business_type='tms_contract' then
    select * into v_r from public.tms_contract where id=v_i.business_id;
    if not found then v_warnings:=jsonb_build_array('业务原单已删除，当前仅展示流程快照'); else
      v_business_no:=v_r.contract_no; v_status:=v_r.contract_status; v_subtitle:=v_r.contract_name;
      v_metrics:=jsonb_build_array(
        jsonb_build_object('label','合同金额','value','¥ '||to_char(coalesce(v_r.contract_amount,0),'FM999,999,990.00'),'tone','warning'),
        jsonb_build_object('label','签订时间','value',coalesce(v_r.sign_time::date::text,'--'),'tone','info'));
      v_fields:=jsonb_build_array(
        jsonb_build_object('label','合同编号','value',coalesce(v_r.contract_no,'--')),
        jsonb_build_object('label','计费方式','value',coalesce(v_r.billing_method,'--')),
        jsonb_build_object('label','经办人','value',coalesce(v_r.handler,'--')),
        jsonb_build_object('label','联系人','value',coalesce(v_r.contact_name,'--')));
      v_attachments:=app_private.workflow_attachment_list(v_r.attachments);
      v_route:='/tms-transportation/basic-data/contract-detail/'||v_i.business_id::text;
    end if;

  elsif v_i.business_type='vehicle_archive' then
    select * into v_r from public.vehicle_archive where id=v_i.business_id;
    if not found then v_warnings:=jsonb_build_array('业务原单已删除，当前仅展示流程快照'); else
      v_business_no:=v_r.plate_no; v_status:=v_r.audit_status;
      v_subtitle:=concat_ws(' · ',v_r.company_name,v_r.brand_model);
      v_metrics:=jsonb_build_array(
        jsonb_build_object('label','核定载质量','value',coalesce(v_r.approved_load_mass::text,'--')||' kg','tone','primary'),
        jsonb_build_object('label','车辆类型','value',coalesce(v_r.vehicle_type,'--'),'tone','info'));
      v_fields:=jsonb_build_array(
        jsonb_build_object('label','车牌号','value',coalesce(v_r.plate_no,'--')),
        jsonb_build_object('label','VIN','value',coalesce(v_r.vin,'--')),
        jsonb_build_object('label','所属公司','value',coalesce(v_r.company_name,'--')),
        jsonb_build_object('label','营运类型','value',coalesce(v_r.operation_type,'--')));
      v_attachments:=app_private.workflow_attachment_list(v_r.attachments);
      v_route:='/vehicle-manage-system/archive-manage/vehicle-archive-detail/'||v_i.business_id::text;
    end if;
  else
    select coalesce(jsonb_agg(jsonb_build_object('label',key,'value',value::text)),'[]'::jsonb)
      into v_fields from jsonb_each(coalesce(v_i.context_snapshot,'{}'::jsonb));
  end if;

  if v_i.status='running' and not exists(
    select 1 from public.wf_task t where t.instance_id=v_i.id and t.status='pending'
  ) then
    v_warnings:=v_warnings||jsonb_build_array('流程运行中但当前没有待办任务，请联系审批管理员检查流程条件。');
  end if;

  v_result:=jsonb_build_object(
    'instanceId',v_i.id,'businessType',v_i.business_type,'businessId',v_i.business_id,
    'title',v_i.business_title,'subtitle',v_subtitle,'businessNo',v_business_no,
    'status',v_status,'routePath',v_route,'metrics',v_metrics,'fields',v_fields,
    'warnings',v_warnings,'attachments',v_attachments);
  return v_result;
end;
$function$;

revoke all on function app_private.workflow_attachment_list(jsonb) from public,anon,authenticated;
revoke all on function public.get_workflow_business_snapshot(uuid) from public,anon;
grant execute on function public.get_workflow_business_snapshot(uuid) to authenticated;
;
