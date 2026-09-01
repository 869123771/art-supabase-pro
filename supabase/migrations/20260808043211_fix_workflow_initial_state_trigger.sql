
create or replace function app_private.trg_require_workflow_initial_review_state()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(pg_catalog.current_setting('app.workflow_engine', true), '') = 'on' then
    return new;
  end if;

  if tg_table_name = 'tms_contract' then
    if new.contract_status in ('pending', 'approved', 'rejected') then
      raise exception '新合同必须先保存为草稿，再通过审批中心提交';
    end if;
  elsif tg_table_name = 'tms_waybill_cost' then
    if new.audit_status in ('pending_review', 'approved', 'rejected') then
      raise exception '新费用必须先保存为草稿，再通过审批中心提交';
    end if;
  elsif tg_table_name = 'tms_invoice' then
    if new.status in ('pending_review', 'issued', 'certified') then
      raise exception '新发票必须先保存为草稿，再通过审批中心提交';
    end if;
  elsif tg_table_name in ('tms_customer_statement', 'tms_carrier_statement') then
    if new.status in ('pending_review', 'confirmed') then
      raise exception '新对账单必须先保存为草稿，再通过审批中心提交';
    end if;
  elsif tg_table_name = 'vehicle_archive' then
    if new.audit_status in ('approved', 'rejected') then
      raise exception '新车辆档案必须先进入待审核，再通过审批中心处理';
    end if;
  end if;

  return new;
end;
$$;

comment on function app_private.trg_require_workflow_initial_review_state() is
  'Enforces draft-first workflow states without reading fields from unrelated trigger tables.';
;
