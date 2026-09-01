create or replace function app_private.trg_validate_workflow_business_start()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invoice record;
  v_statement record;
begin
  if new.business_type = 'tms_invoice' then
    select i.status, i.direction, i.invoice_type, i.invoice_no,
           i.total_amount, i.tenant_id
    into v_invoice
    from public.tms_invoice i
    where i.id = new.business_id
      and i.tenant_id = new.tenant_id
    for update;

    if not found then raise exception '发票不存在或无权提交审批'; end if;
    if v_invoice.status <> 'draft' then
      raise exception '当前发票状态不允许提交审批';
    end if;
    if nullif(btrim(coalesce(v_invoice.invoice_no, '')), '') is null then
      raise exception '提交审批前必须填写发票号码';
    end if;

    new.context_snapshot := coalesce(new.context_snapshot, '{}'::jsonb)
      || jsonb_build_object(
        'direction', v_invoice.direction,
        'invoiceType', v_invoice.invoice_type,
        'invoiceNo', v_invoice.invoice_no,
        'totalAmount', v_invoice.total_amount
      );
  elsif new.business_type = 'tms_carrier_statement' then
    select s.status, s.statement_no, s.carrier_id, s.tenant_id,
           (
             select coalesce(sum(i.line_amount), 0)
             from public.tms_carrier_statement_item i
             where i.statement_id = s.id and i.is_active
           ) as statement_amount,
           (
             select count(*)
             from public.tms_carrier_statement_item i
             where i.statement_id = s.id and i.is_active
           ) as active_item_count
    into v_statement
    from public.tms_carrier_statement s
    where s.id = new.business_id
      and s.tenant_id = new.tenant_id
    for update;

    if not found then
      raise exception '承运商对账单不存在或无权提交审批';
    end if;
    if v_statement.status <> 'draft' then
      raise exception '当前承运商对账单状态不允许提交审批';
    end if;
    if coalesce(v_statement.active_item_count, 0) = 0 then
      raise exception '承运商对账单没有有效费用明细，不能提交审批';
    end if;

    new.context_snapshot := coalesce(new.context_snapshot, '{}'::jsonb)
      || jsonb_build_object(
        'statementNo', v_statement.statement_no,
        'statementAmount', v_statement.statement_amount,
        'carrierId', v_statement.carrier_id,
        'costCount', v_statement.active_item_count
      );
  end if;

  return new;
end;
$$;
revoke all on function app_private.trg_validate_workflow_business_start()
  from public, anon, authenticated;
