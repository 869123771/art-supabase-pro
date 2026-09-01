
create or replace function app_private.trg_require_workflow_for_finance_review()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_requires_workflow boolean:=false; v_label text;
begin
  if new.status is not distinct from old.status then return new; end if;
  if tg_table_name='tms_invoice' then
    v_requires_workflow:=new.status in ('pending_review','issued','certified') or old.status='pending_review';
    v_label:='发票';
  elsif tg_table_name='tms_carrier_statement' then
    v_requires_workflow:=new.status in ('pending_review','confirmed') or old.status='pending_review';
    v_label:='承运商对账单';
  elsif tg_table_name='tms_customer_statement' then
    v_requires_workflow:=new.status in ('pending_review','confirmed') or old.status='pending_review';
    v_label:='客户对账单';
  else
    v_requires_workflow:=new.status='pending_review' or old.status='pending_review';
    v_label:='财务单据';
  end if;
  if v_requires_workflow
    and coalesce(pg_catalog.current_setting('app.workflow_engine',true),'')<>'on' then
    raise exception '%审批状态必须通过审批中心流转',v_label;
  end if;
  return new;
end;$function$;

create or replace function app_private.trg_require_workflow_initial_review_state()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if coalesce(pg_catalog.current_setting('app.workflow_engine',true),'')='on' then return new; end if;
  if tg_table_name='tms_contract' and new.contract_status in ('pending','approved','rejected') then
    raise exception '新合同必须先保存为草稿，再通过审批中心提交';
  elsif tg_table_name='tms_waybill_cost' and new.audit_status in ('pending_review','approved','rejected') then
    raise exception '新费用必须先保存为草稿，再通过审批中心提交';
  elsif tg_table_name='tms_invoice' and new.status in ('pending_review','issued','certified') then
    raise exception '新发票必须先保存为草稿，再通过审批中心提交';
  elsif tg_table_name in ('tms_customer_statement','tms_carrier_statement')
    and new.status in ('pending_review','confirmed') then
    raise exception '新对账单必须先保存为草稿，再通过审批中心提交';
  elsif tg_table_name='vehicle_archive' and new.audit_status in ('approved','rejected') then
    raise exception '新车辆档案必须先进入待审核，再通过审批中心处理';
  end if;
  return new;
end;$function$;

drop trigger if exists tms_contract_workflow_initial_state on public.tms_contract;
create trigger tms_contract_workflow_initial_state before insert on public.tms_contract
for each row execute function app_private.trg_require_workflow_initial_review_state();
drop trigger if exists tms_waybill_cost_workflow_initial_state on public.tms_waybill_cost;
create trigger tms_waybill_cost_workflow_initial_state before insert on public.tms_waybill_cost
for each row execute function app_private.trg_require_workflow_initial_review_state();
drop trigger if exists tms_invoice_workflow_initial_state on public.tms_invoice;
create trigger tms_invoice_workflow_initial_state before insert on public.tms_invoice
for each row execute function app_private.trg_require_workflow_initial_review_state();
drop trigger if exists tms_customer_statement_workflow_initial_state on public.tms_customer_statement;
create trigger tms_customer_statement_workflow_initial_state before insert on public.tms_customer_statement
for each row execute function app_private.trg_require_workflow_initial_review_state();
drop trigger if exists tms_carrier_statement_workflow_initial_state on public.tms_carrier_statement;
create trigger tms_carrier_statement_workflow_initial_state before insert on public.tms_carrier_statement
for each row execute function app_private.trg_require_workflow_initial_review_state();
drop trigger if exists vehicle_archive_workflow_initial_state on public.vehicle_archive;
create trigger vehicle_archive_workflow_initial_state before insert on public.vehicle_archive
for each row execute function app_private.trg_require_workflow_initial_review_state();

revoke all on function app_private.trg_require_workflow_initial_review_state() from public,anon,authenticated;
;
