-- A workflow cancellation or withdrawal must be able to restore a pending
-- waybill cost to draft. Direct status changes remain blocked by the workflow
-- guard trigger; this validator only aligns the domain transition matrix.

create or replace function public.trg_validate_tms_waybill_cost()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_waybill_tenant_id uuid;
  v_waybill_carrier_id uuid;
  v_waybill_driver_id uuid;
  v_actor text;
begin
  select w.tenant_id, w.carrier_id, w.driver_id
    into v_waybill_tenant_id, v_waybill_carrier_id, v_waybill_driver_id
  from public.tms_waybill w
  where w.id = new.waybill_id;

  if not found then
    raise exception '关联运单不存在';
  end if;

  if tg_op = 'INSERT' then
    new.tenant_id := v_waybill_tenant_id;
    new.audit_status := 'draft';
    new.carrier_id := coalesce(new.carrier_id, v_waybill_carrier_id);
    new.driver_id := coalesce(new.driver_id, v_waybill_driver_id);
  elsif new.tenant_id is distinct from old.tenant_id then
    raise exception '费用所属租户不可修改';
  elsif new.waybill_id is distinct from old.waybill_id then
    new.tenant_id := v_waybill_tenant_id;
    new.carrier_id := coalesce(new.carrier_id, v_waybill_carrier_id);
    new.driver_id := coalesce(new.driver_id, v_waybill_driver_id);
  end if;

  if new.tenant_id is distinct from v_waybill_tenant_id then
    raise exception '费用与运单必须属于同一租户';
  end if;

  if new.carrier_id is not null and not exists (
    select 1 from public.tms_carrier c
    where c.id = new.carrier_id and c.tenant_id = new.tenant_id
  ) then
    raise exception '承运商与费用必须属于同一租户';
  end if;

  if new.driver_id is not null and not exists (
    select 1 from public.tms_driver d
    where d.id = new.driver_id and d.tenant_id = new.tenant_id
  ) then
    raise exception '司机与费用必须属于同一租户';
  end if;

  if tg_op = 'UPDATE' then
    if old.audit_status = 'voided' then
      raise exception '已作废费用不可修改';
    end if;

    if old.audit_status in ('pending_review', 'approved') and (
      new.waybill_id is distinct from old.waybill_id
      or new.cost_type is distinct from old.cost_type
      or new.amount is distinct from old.amount
      or new.occurred_on is distinct from old.occurred_on
      or new.payee_name is distinct from old.payee_name
      or new.carrier_id is distinct from old.carrier_id
      or new.driver_id is distinct from old.driver_id
      or new.remark is distinct from old.remark
      or new.attachments is distinct from old.attachments
    ) then
      raise exception '待审核或已审核费用不可修改业务字段';
    end if;

    if new.audit_status is distinct from old.audit_status and not (
      (old.audit_status = 'draft' and new.audit_status in ('pending_review', 'voided'))
      or (old.audit_status = 'pending_review' and new.audit_status in ('approved', 'rejected', 'draft'))
      or (old.audit_status = 'rejected' and new.audit_status in ('draft', 'pending_review', 'voided'))
      or (old.audit_status = 'approved' and new.audit_status = 'voided')
    ) then
      raise exception '不允许的费用审核状态流转：% -> %', old.audit_status, new.audit_status;
    end if;

    v_actor := coalesce(
      nullif(public.get_app_user_display_name(), ''),
      nullif(auth.jwt() ->> 'email', ''),
      'unknown'
    );

    if new.audit_status = 'pending_review' and old.audit_status <> 'pending_review' then
      new.submitted_at := now();
      new.submitted_by := v_actor;
      new.reviewed_at := null;
      new.reviewed_by := null;
      new.review_remark := null;
    elsif new.audit_status in ('approved', 'rejected')
      and new.audit_status is distinct from old.audit_status then
      new.reviewed_at := now();
      new.reviewed_by := v_actor;
    elsif new.audit_status = 'draft'
      and old.audit_status in ('rejected', 'pending_review') then
      new.reviewed_at := null;
      new.reviewed_by := null;
      new.review_remark := null;
    end if;
  end if;

  return new;
end
$function$;;
