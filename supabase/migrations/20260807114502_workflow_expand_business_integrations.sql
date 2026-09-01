
create or replace function app_private.trg_validate_workflow_business_start()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row record;
begin
  if new.business_type = 'tms_invoice' then
    select i.status, i.direction, i.invoice_type, i.invoice_no, i.total_amount,
           i.tax_rate, i.counterparty_name_snapshot, i.tenant_id
    into v_row from public.tms_invoice i
    where i.id = new.business_id and i.tenant_id = new.tenant_id for update;
    if not found then raise exception '发票不存在或无权提交审批'; end if;
    if v_row.status <> 'draft' then raise exception '当前发票状态不允许提交审批'; end if;
    if nullif(btrim(coalesce(v_row.invoice_no, '')), '') is null then
      raise exception '提交审批前必须填写发票号码';
    end if;
    new.context_snapshot := coalesce(new.context_snapshot, '{}'::jsonb) ||
      jsonb_build_object('direction',v_row.direction,'invoiceType',v_row.invoice_type,
        'invoiceNo',v_row.invoice_no,'totalAmount',v_row.total_amount,'taxRate',v_row.tax_rate,
        'counterpartyName',v_row.counterparty_name_snapshot);

  elsif new.business_type = 'tms_waybill_cost' then
    select c.audit_status, c.amount, c.cost_type, c.payee_name, c.occurred_on,
           c.attachments, c.tenant_id, w.waybill_no
    into v_row from public.tms_waybill_cost c
    left join public.tms_waybill w on w.id=c.waybill_id
    where c.id=new.business_id and c.tenant_id=new.tenant_id for update of c;
    if not found then raise exception '运单费用不存在或无权提交审批'; end if;
    if v_row.audit_status not in ('draft','rejected') then
      raise exception '当前费用状态不允许提交审批';
    end if;
    if coalesce(v_row.amount,0) <= 0 then raise exception '费用金额必须大于 0'; end if;
    new.context_snapshot := coalesce(new.context_snapshot,'{}'::jsonb) ||
      jsonb_build_object('amount',v_row.amount,'costType',v_row.cost_type,
        'payeeName',v_row.payee_name,'occurredOn',v_row.occurred_on,'waybillNo',v_row.waybill_no);

  elsif new.business_type in ('tms_carrier_statement','tms_customer_statement') then
    if new.business_type = 'tms_carrier_statement' then
      select s.status,s.statement_no,s.carrier_id,s.carrier_name_snapshot as party_name,
             s.settled_amount,s.tenant_id,
             (select coalesce(sum(i.line_amount),0) from public.tms_carrier_statement_item i
               where i.statement_id=s.id and i.is_active) amount,
             (select count(*) from public.tms_carrier_statement_item i
               where i.statement_id=s.id and i.is_active) item_count
      into v_row from public.tms_carrier_statement s
      where s.id=new.business_id and s.tenant_id=new.tenant_id for update;
      if not found then raise exception '承运商对账单不存在或无权提交审批'; end if;
      if v_row.status <> 'draft' then raise exception '当前承运商对账单状态不允许提交审批'; end if;
      if v_row.item_count=0 then raise exception '承运商对账单没有有效费用明细，不能提交审批'; end if;
      new.context_snapshot := coalesce(new.context_snapshot,'{}'::jsonb) ||
        jsonb_build_object('statementNo',v_row.statement_no,'statementAmount',v_row.amount,
          'carrierId',v_row.carrier_id,'carrierName',v_row.party_name,
          'costCount',v_row.item_count,'settledAmount',v_row.settled_amount);
    else
      select s.status,s.statement_no,s.customer_id,s.customer_name_snapshot as party_name,
             s.settled_amount,s.tenant_id,
             (select coalesce(sum(i.line_amount),0) from public.tms_customer_statement_item i
               where i.statement_id=s.id and i.is_active) amount,
             (select count(*) from public.tms_customer_statement_item i
               where i.statement_id=s.id and i.is_active) item_count
      into v_row from public.tms_customer_statement s
      where s.id=new.business_id and s.tenant_id=new.tenant_id for update;
      if not found then raise exception '客户对账单不存在或无权提交审批'; end if;
      if v_row.status <> 'draft' then raise exception '当前客户对账单状态不允许提交审批'; end if;
      if v_row.item_count=0 then raise exception '客户对账单没有有效运单明细，不能提交审批'; end if;
      new.context_snapshot := coalesce(new.context_snapshot,'{}'::jsonb) ||
        jsonb_build_object('statementNo',v_row.statement_no,'statementAmount',v_row.amount,
          'customerId',v_row.customer_id,'customerName',v_row.party_name,
          'waybillCount',v_row.item_count,'settledAmount',v_row.settled_amount);
    end if;

  elsif new.business_type = 'tms_contract' then
    select c.contract_status,c.contract_no,c.contract_amount,c.carrier_id,c.billing_method,
           c.sign_time,c.handler,c.attachments,c.tenant_id
    into v_row from public.tms_contract c
    where c.id=new.business_id and c.tenant_id=new.tenant_id for update;
    if not found then raise exception '合同不存在或无权提交审批'; end if;
    if v_row.contract_status not in ('draft','rejected','pending') then
      raise exception '当前合同状态不允许提交审批';
    end if;
    if nullif(btrim(coalesce(v_row.contract_no,'')),'') is null then
      raise exception '提交审批前必须填写合同编号';
    end if;
    new.context_snapshot := coalesce(new.context_snapshot,'{}'::jsonb) ||
      jsonb_build_object('contractNo',v_row.contract_no,'contractAmount',v_row.contract_amount,
        'carrierId',v_row.carrier_id,'billingMethod',v_row.billing_method,
        'signTime',v_row.sign_time,'handler',v_row.handler);

  elsif new.business_type = 'vehicle_archive' then
    select v.audit_status,v.plate_no,v.company_name,v.vehicle_type,v.approved_load_mass,
           v.operation_type,v.is_new_energy,v.attachments,v.tenant_id
    into v_row from public.vehicle_archive v
    where v.id=new.business_id and v.tenant_id=new.tenant_id for update;
    if not found then raise exception '车辆档案不存在或无权提交审批'; end if;
    if v_row.audit_status not in ('pending','rejected') then
      raise exception '当前车辆档案状态不允许提交审批';
    end if;
    if nullif(btrim(coalesce(v_row.plate_no,'')),'') is null then
      raise exception '提交审批前必须填写车牌号';
    end if;
    new.context_snapshot := coalesce(new.context_snapshot,'{}'::jsonb) ||
      jsonb_build_object('plateNo',v_row.plate_no,'companyName',v_row.company_name,
        'vehicleType',v_row.vehicle_type,'approvedLoadMass',v_row.approved_load_mass,
        'operationType',v_row.operation_type,'isNewEnergy',v_row.is_new_energy);
  end if;
  return new;
end;
$function$;

create or replace function app_private.execute_workflow_business_callback(
  p_business_type text,p_business_id uuid,p_status text,p_actor text,p_comment text
) returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare v_invoice_direction text;
begin
  perform pg_catalog.set_config('app.workflow_engine','on',true);
  if p_business_type='tms_waybill_cost' then
    update public.tms_waybill_cost set
      audit_status=case p_status when 'running' then 'pending_review' when 'approved' then 'approved'
        when 'rejected' then 'rejected' when 'withdrawn' then 'draft' when 'cancelled' then 'draft'
        else audit_status end,
      submitted_at=case when p_status='running' then now() else submitted_at end,
      submitted_by=case when p_status='running' then p_actor else submitted_by end,
      reviewed_at=case when p_status='running' then null when p_status in ('approved','rejected') then now() else reviewed_at end,
      reviewed_by=case when p_status='running' then null when p_status in ('approved','rejected') then p_actor else reviewed_by end,
      review_remark=case when p_status='running' then null when p_status in ('approved','rejected','cancelled')
        then nullif(btrim(coalesce(p_comment,'')),'') else review_remark end
    where id=p_business_id;
    if not found then raise exception '运单费用不存在或已被删除'; end if;

  elsif p_business_type='tms_invoice' then
    select direction into v_invoice_direction from public.tms_invoice where id=p_business_id;
    if not found then raise exception '发票不存在或已被删除'; end if;
    update public.tms_invoice set
      status=case p_status when 'running' then 'pending_review'
        when 'approved' then case when v_invoice_direction='output' then 'issued' else 'certified' end
        when 'rejected' then 'draft' when 'withdrawn' then 'draft' when 'cancelled' then 'draft' else status end,
      submitted_at=case when p_status='running' then now() else submitted_at end,
      submitted_by=case when p_status='running' then p_actor else submitted_by end,
      reviewed_at=case when p_status='running' then null when p_status in ('approved','rejected','withdrawn','cancelled') then now() else reviewed_at end,
      reviewed_by=case when p_status='running' then null when p_status in ('approved','rejected','withdrawn','cancelled') then p_actor else reviewed_by end,
      review_remark=case when p_status='running' then null when p_status in ('approved','rejected','withdrawn','cancelled')
        then nullif(btrim(coalesce(p_comment,'')),'') else review_remark end
    where id=p_business_id;

  elsif p_business_type in ('tms_carrier_statement','tms_customer_statement') then
    if p_business_type='tms_carrier_statement' then
      update public.tms_carrier_statement set
        status=case p_status when 'running' then 'pending_review' when 'approved' then 'confirmed'
          when 'rejected' then 'draft' when 'withdrawn' then 'draft' when 'cancelled' then 'draft' else status end,
        submitted_at=case when p_status='running' then now() else submitted_at end,
        submitted_by=case when p_status='running' then p_actor else submitted_by end,
        reviewed_at=case when p_status='running' then null when p_status in ('approved','rejected') then now() else reviewed_at end,
        reviewed_by=case when p_status='running' then null when p_status in ('approved','rejected') then p_actor else reviewed_by end,
        review_remark=case when p_status='running' then null else nullif(btrim(coalesce(p_comment,'')),'') end
      where id=p_business_id;
    else
      update public.tms_customer_statement set
        status=case p_status when 'running' then 'pending_review' when 'approved' then 'confirmed'
          when 'rejected' then 'draft' when 'withdrawn' then 'draft' when 'cancelled' then 'draft' else status end,
        submitted_at=case when p_status='running' then now() else submitted_at end,
        submitted_by=case when p_status='running' then p_actor else submitted_by end,
        reviewed_at=case when p_status='running' then null when p_status in ('approved','rejected') then now() else reviewed_at end,
        reviewed_by=case when p_status='running' then null when p_status in ('approved','rejected') then p_actor else reviewed_by end,
        review_remark=case when p_status='running' then null else nullif(btrim(coalesce(p_comment,'')),'') end
      where id=p_business_id;
    end if;
    if not found then raise exception '对账单不存在或已被删除'; end if;

  elsif p_business_type='tms_contract' then
    update public.tms_contract set
      contract_status=case p_status when 'running' then 'pending' when 'approved' then 'approved'
        when 'rejected' then 'rejected' when 'withdrawn' then 'draft' when 'cancelled' then 'draft'
        else contract_status end
    where id=p_business_id;
    if not found then raise exception '合同不存在或已被删除'; end if;

  elsif p_business_type='vehicle_archive' then
    update public.vehicle_archive set
      audit_status=case p_status when 'running' then 'pending' when 'approved' then 'approved'
        when 'rejected' then 'rejected' when 'withdrawn' then 'pending' when 'cancelled' then 'pending'
        else audit_status end,
      audit_time=case when p_status in ('approved','rejected') then now() else audit_time end,
      audit_by=case when p_status in ('approved','rejected') then p_actor else audit_by end,
      audit_remark=case when p_status in ('approved','rejected','cancelled')
        then nullif(btrim(coalesce(p_comment,'')),'') else audit_remark end
    where id=p_business_id;
    if not found then raise exception '车辆档案不存在或已被删除'; end if;
  end if;
end;
$function$;

create or replace function app_private.trg_require_workflow_for_contract_review()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if new.contract_status is distinct from old.contract_status
    and (new.contract_status in ('pending','approved','rejected')
      or old.contract_status in ('pending','rejected'))
    and coalesce(pg_catalog.current_setting('app.workflow_engine',true),'')<>'on' then
    raise exception '合同审批状态必须通过审批中心流转';
  end if;
  return new;
end;$function$;

create or replace function app_private.trg_require_workflow_for_vehicle_review()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if new.audit_status is distinct from old.audit_status
    and (new.audit_status in ('approved','rejected') or old.audit_status='rejected')
    and coalesce(pg_catalog.current_setting('app.workflow_engine',true),'')<>'on' then
    raise exception '车辆档案审核状态必须通过审批中心流转';
  end if;
  return new;
end;$function$;

drop trigger if exists tms_customer_statement_require_workflow_review on public.tms_customer_statement;
create trigger tms_customer_statement_require_workflow_review
before update of status on public.tms_customer_statement
for each row execute function app_private.trg_require_workflow_for_finance_review();

drop trigger if exists tms_contract_require_workflow_review on public.tms_contract;
create trigger tms_contract_require_workflow_review
before update of contract_status on public.tms_contract
for each row execute function app_private.trg_require_workflow_for_contract_review();

drop trigger if exists vehicle_archive_require_workflow_review on public.vehicle_archive;
create trigger vehicle_archive_require_workflow_review
before update of audit_status on public.vehicle_archive
for each row execute function app_private.trg_require_workflow_for_vehicle_review();

revoke all on function app_private.trg_require_workflow_for_contract_review() from public,anon,authenticated;
revoke all on function app_private.trg_require_workflow_for_vehicle_review() from public,anon,authenticated;
;
