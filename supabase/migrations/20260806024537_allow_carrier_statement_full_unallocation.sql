-- Reversing the only active allocation moves a fully settled statement directly
-- back to confirmed. The carrier state machine must allow the same transition as
-- the customer statement state machine.
create or replace function public.trg_validate_tms_carrier_statement()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_carrier_tenant_id uuid;
  v_carrier_name text;
  v_actor text;
begin
  select c.tenant_id, c.company_name
    into v_carrier_tenant_id, v_carrier_name
  from public.tms_carrier c
  where c.id = new.carrier_id;

  if not found then
    raise exception '对账承运商不存在';
  end if;
  if new.period_start > new.period_end then
    raise exception '账期开始日期不能晚于结束日期';
  end if;

  if tg_op = 'INSERT' then
    new.tenant_id := v_carrier_tenant_id;
    new.carrier_name_snapshot := v_carrier_name;
    new.status := 'draft';
    new.settled_amount := 0;
    new.submitted_at := null;
    new.submitted_by := null;
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.review_remark := null;
    new.voided_at := null;
    new.voided_by := null;
    new.void_reason := null;
    return new;
  end if;

  if old.status = 'voided' then
    raise exception '已作废承运商对账单不可修改';
  end if;
  if new.tenant_id is distinct from old.tenant_id
     or new.statement_no is distinct from old.statement_no
     or new.carrier_id is distinct from old.carrier_id
     or new.carrier_name_snapshot is distinct from old.carrier_name_snapshot
     or new.period_start is distinct from old.period_start
     or new.period_end is distinct from old.period_end then
    raise exception '对账单承运商、账期和单号不可修改';
  end if;
  if new.settled_amount is distinct from old.settled_amount and pg_trigger_depth() <= 1 then
    raise exception '已结金额只能由付款核销流程更新';
  end if;

  new.submitted_at := old.submitted_at;
  new.submitted_by := old.submitted_by;
  new.reviewed_at := old.reviewed_at;
  new.reviewed_by := old.reviewed_by;
  new.voided_at := old.voided_at;
  new.voided_by := old.voided_by;

  if new.status is distinct from old.status and not (
    (old.status = 'draft' and new.status in ('pending_review', 'voided'))
    or (old.status = 'pending_review' and new.status in ('draft', 'confirmed', 'voided'))
    or (old.status = 'confirmed' and new.status in ('partially_settled', 'settled', 'voided'))
    or (old.status = 'partially_settled' and new.status in ('confirmed', 'settled', 'voided'))
    or (old.status = 'settled' and new.status in ('confirmed', 'partially_settled', 'voided'))
  ) then
    raise exception '不允许的承运商对账单状态流转：% -> %', old.status, new.status;
  end if;

  v_actor := coalesce(
    nullif(public.get_app_user_display_name(), ''),
    nullif(auth.jwt() ->> 'email', ''),
    'unknown'
  );
  if new.status = 'pending_review' and old.status <> 'pending_review' then
    new.submitted_at := now();
    new.submitted_by := v_actor;
    new.reviewed_at := null;
    new.reviewed_by := null;
    new.review_remark := null;
  elsif old.status = 'pending_review' and new.status = 'confirmed' then
    new.reviewed_at := now();
    new.reviewed_by := v_actor;
  elsif old.status = 'pending_review' and new.status = 'draft' then
    if btrim(coalesce(new.review_remark, '')) = '' then
      raise exception '驳回原因不能为空';
    end if;
    new.reviewed_at := now();
    new.reviewed_by := v_actor;
  elsif new.status = 'voided' then
    if btrim(coalesce(new.void_reason, '')) = '' then
      raise exception '作废原因不能为空';
    end if;
    new.voided_at := now();
    new.voided_by := v_actor;
  end if;
  return new;
end;
$function$;;
