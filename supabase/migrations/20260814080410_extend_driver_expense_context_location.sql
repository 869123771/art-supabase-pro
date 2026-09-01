create or replace function public.tms_get_driver_waybill_expense_context(
  p_waybill_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_driver_id uuid := app_private.current_user_driver_id();
  v_waybill public.tms_waybill;
  v_items jsonb;
  v_records jsonb;
  v_stats jsonb;
begin
  if (select auth.uid()) is null or v_user_id is null or v_tenant_id is null then
    raise exception '当前登录用户未绑定业务账号' using errcode = '42501';
  end if;
  if not (select app_private.is_driver_user()) or v_driver_id is null then
    raise exception '当前账号未绑定有效司机档案' using errcode = '42501';
  end if;

  select w.*
  into v_waybill
  from public.tms_waybill w
  where w.id = p_waybill_id
    and w.tenant_id = v_tenant_id
    and w.driver_id = v_driver_id;

  if not found then
    raise exception '运单不存在或未分配给当前司机' using errcode = '42501';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', i.id,
        'item_code', i.item_code,
        'item_name', i.item_name,
        'parent_name', p.item_name,
        'business_category', i.business_category
      )
      order by coalesce(p.sort, 0), i.sort, i.item_name
    ),
    '[]'::jsonb
  )
  into v_items
  from public.tms_expense_item i
  left join public.tms_expense_item p
    on p.id = i.parent_id
   and p.tenant_id = i.tenant_id
  where i.tenant_id = v_tenant_id
    and i.is_enabled
    and i.is_selectable
    and i.reimbursement_allowed;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'cost_no', c.cost_no,
        'expense_item_id', c.expense_item_id,
        'expense_item_name', i.item_name,
        'expense_parent_name', p.item_name,
        'amount', c.amount,
        'occurred_on', c.occurred_on,
        'attachments', c.attachments,
        'audit_status', c.audit_status,
        'submitted_at', c.submitted_at,
        'reviewed_at', c.reviewed_at,
        'reviewed_by', c.reviewed_by,
        'review_remark', c.review_remark,
        'settlement_status', c.settlement_status,
        'paid_at', c.paid_at,
        'provider_name', c.provider_name,
        'payee_name', c.payee_name,
        'payment_channel', c.payment_channel,
        'invoice_no', c.invoice_no,
        'expense_location', c.expense_location,
        'expense_longitude', c.expense_longitude,
        'expense_latitude', c.expense_latitude,
        'expense_coordinate_system', c.expense_coordinate_system,
        'remark', c.remark,
        'source_id', c.source_id,
        'create_time', c.create_time,
        'update_time', c.update_time
      )
      order by c.create_time desc
    ),
    '[]'::jsonb
  )
  into v_records
  from public.tms_waybill_cost c
  join public.tms_expense_item i
    on i.id = c.expense_item_id
   and i.tenant_id = c.tenant_id
  left join public.tms_expense_item p
    on p.id = i.parent_id
   and p.tenant_id = i.tenant_id
  where c.tenant_id = v_tenant_id
    and c.waybill_id = p_waybill_id
    and c.driver_id = v_driver_id
    and c.reporter_user_id = v_user_id
    and c.source_type = 'driver_report';

  select jsonb_build_object(
    'report_count', count(*) filter (where c.audit_status <> 'voided'),
    'total_amount', coalesce(sum(c.amount) filter (where c.audit_status <> 'voided'), 0),
    'pending_count', count(*) filter (where c.audit_status = 'pending_review'),
    'approved_amount', coalesce(sum(c.amount) filter (where c.audit_status = 'approved'), 0)
  )
  into v_stats
  from public.tms_waybill_cost c
  where c.tenant_id = v_tenant_id
    and c.waybill_id = p_waybill_id
    and c.driver_id = v_driver_id
    and c.reporter_user_id = v_user_id
    and c.source_type = 'driver_report';

  return jsonb_build_object(
    'waybill', jsonb_build_object(
      'id', v_waybill.id,
      'waybill_no', v_waybill.waybill_no,
      'status', v_waybill.status,
      'origin_city', v_waybill.origin_city,
      'destination_city', v_waybill.destination_city,
      'shipper_address', v_waybill.shipper_address,
      'receiver_address', v_waybill.receiver_address
    ),
    'can_report', v_waybill.status in (
      'accepted', 'loading', 'transporting', 'unloading', 'signed', 'completed'
    ),
    'expense_items', v_items,
    'records', v_records,
    'stats', v_stats
  );
end;
$$;

comment on function public.tms_get_driver_waybill_expense_context(uuid) is
  'Returns the assigned driver expense form context, including persisted expense coordinates for rejected-report editing.';

;
