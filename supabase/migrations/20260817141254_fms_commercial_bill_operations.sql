begin;

create or replace function public.save_fms_commercial_bill(p_payload jsonb)
returns public.fms_commercial_bill
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_bill public.fms_commercial_bill%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护商业票据';
  end if;

  select * into v_account_set
  from public.fms_account_set
  where id = nullif(p_payload ->> 'accountSetId', '')::uuid;
  if not found then
    raise exception using errcode = 'P0002', message = '账套不存在';
  end if;
  if v_account_set.status <> 'active' then
    raise exception using errcode = '23514', message = '仅启用中的账套可维护商业票据';
  end if;

  if v_id is null then
    insert into public.fms_commercial_bill (
      tenant_id, account_set_id, bill_no, external_bill_no, direction, bill_type,
      drawer_name, payee_name, acceptor_name, counterparty_name,
      issue_date, due_date, face_amount, currency_code, transferable,
      source_type, source_id, source_no, attachment_ids, remark
    ) values (
      v_account_set.tenant_id, v_account_set.id, btrim(p_payload ->> 'billNo'),
      nullif(btrim(p_payload ->> 'externalBillNo'), ''),
      p_payload ->> 'direction', p_payload ->> 'billType',
      btrim(p_payload ->> 'drawerName'), btrim(p_payload ->> 'payeeName'),
      btrim(p_payload ->> 'acceptorName'), nullif(btrim(p_payload ->> 'counterpartyName'), ''),
      (p_payload ->> 'issueDate')::date, (p_payload ->> 'dueDate')::date,
      (p_payload ->> 'faceAmount')::numeric,
      upper(coalesce(nullif(p_payload ->> 'currencyCode', ''), v_account_set.base_currency_code)),
      coalesce((p_payload ->> 'transferable')::boolean, true),
      nullif(p_payload ->> 'sourceType', ''), nullif(p_payload ->> 'sourceId', '')::uuid,
      nullif(p_payload ->> 'sourceNo', ''), coalesce(p_payload -> 'attachmentIds', '[]'::jsonb),
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_bill;
  else
    select * into v_bill
    from public.fms_commercial_bill
    where id = v_id
    for update;
    if not found then
      raise exception using errcode = 'P0002', message = '商业票据不存在';
    end if;
    if v_bill.status <> 'draft' then
      raise exception using errcode = '23514', message = '仅草稿票据允许编辑';
    end if;
    if v_bill.account_set_id <> v_account_set.id then
      raise exception using errcode = '23514', message = '票据所属账套不可变更';
    end if;

    update public.fms_commercial_bill set
      bill_no = btrim(p_payload ->> 'billNo'),
      external_bill_no = nullif(btrim(p_payload ->> 'externalBillNo'), ''),
      direction = p_payload ->> 'direction',
      bill_type = p_payload ->> 'billType',
      drawer_name = btrim(p_payload ->> 'drawerName'),
      payee_name = btrim(p_payload ->> 'payeeName'),
      acceptor_name = btrim(p_payload ->> 'acceptorName'),
      counterparty_name = nullif(btrim(p_payload ->> 'counterpartyName'), ''),
      issue_date = (p_payload ->> 'issueDate')::date,
      due_date = (p_payload ->> 'dueDate')::date,
      face_amount = (p_payload ->> 'faceAmount')::numeric,
      currency_code = upper(coalesce(nullif(p_payload ->> 'currencyCode', ''), currency_code)),
      transferable = coalesce((p_payload ->> 'transferable')::boolean, transferable),
      source_type = nullif(p_payload ->> 'sourceType', ''),
      source_id = nullif(p_payload ->> 'sourceId', '')::uuid,
      source_no = nullif(p_payload ->> 'sourceNo', ''),
      attachment_ids = coalesce(p_payload -> 'attachmentIds', attachment_ids),
      remark = nullif(btrim(p_payload ->> 'remark'), ''),
      version = version + 1
    where id = v_id
    returning * into v_bill;
  end if;

  return v_bill;
end;
$$;

create or replace function public.delete_fms_commercial_bill(p_bill_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可删除商业票据';
  end if;
  delete from public.fms_commercial_bill
  where id = p_bill_id and status = 'draft';
  if not found then
    raise exception using errcode = '23514', message = '票据不存在或当前状态不允许删除';
  end if;
end;
$$;

create or replace function public.act_fms_commercial_bill(
  p_bill_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns public.fms_commercial_bill
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_bill public.fms_commercial_bill%rowtype;
  v_event_type text;
  v_target_status text;
  v_event_date date := coalesce(nullif(p_payload ->> 'eventDate', '')::date, current_date);
  v_amount numeric(20, 2);
  v_event_id uuid;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行票据流转';
  end if;

  select * into v_bill
  from public.fms_commercial_bill
  where id = p_bill_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = '商业票据不存在';
  end if;

  if p_action in ('receive', 'issue') then
    if v_bill.status <> 'draft' then
      raise exception using errcode = '23514', message = '仅草稿票据可确认收票或出票';
    end if;
    if (p_action = 'receive' and v_bill.direction <> 'receivable')
      or (p_action = 'issue' and v_bill.direction <> 'payable') then
      raise exception using errcode = '23514', message = '票据方向与操作不匹配';
    end if;
    v_event_type := case when p_action = 'receive' then 'received' else 'issued' end;
    v_target_status := 'held';
    v_amount := v_bill.face_amount;
  elsif p_action in ('endorse', 'discount', 'settle') then
    if v_bill.status <> 'held' then
      raise exception using errcode = '23514', message = '仅持有中的票据可背书、贴现或结算';
    end if;
    if p_action = 'endorse' and not v_bill.transferable then
      raise exception using errcode = '23514', message = '当前票据不允许背书转让';
    end if;
    if p_action = 'discount' and v_bill.direction <> 'receivable' then
      raise exception using errcode = '23514', message = '仅应收票据允许贴现';
    end if;
    v_event_type := case p_action
      when 'endorse' then 'endorsed'
      when 'discount' then 'discounted'
      else 'settled'
    end;
    v_target_status := case p_action
      when 'endorse' then 'endorsed'
      when 'discount' then 'discounted'
      else 'settled'
    end;
    v_amount := v_bill.face_amount - v_bill.settled_amount;
    if nullif(p_payload ->> 'amount', '') is not null
      and (p_payload ->> 'amount')::numeric <> v_amount then
      raise exception using errcode = '23514', message = '当前版本仅支持全额背书、贴现或结算';
    end if;
  elsif p_action = 'cancel' then
    if v_bill.status not in ('draft', 'held') then
      raise exception using errcode = '23514', message = '当前票据状态不允许取消';
    end if;
    if nullif(btrim(p_payload ->> 'remark'), '') is null then
      raise exception using errcode = '23502', message = '取消票据必须填写原因';
    end if;
    v_event_type := 'cancelled';
    v_target_status := 'cancelled';
    v_amount := 0;
  else
    raise exception using errcode = '22023', message = '不支持的票据操作';
  end if;

  insert into public.fms_commercial_bill_event (
    tenant_id, account_set_id, bill_id, event_type, event_date, amount,
    counterparty_name, fund_account_id, reference_no, remark
  ) values (
    v_bill.tenant_id, v_bill.account_set_id, v_bill.id, v_event_type, v_event_date, v_amount,
    coalesce(nullif(btrim(p_payload ->> 'counterpartyName'), ''), v_bill.counterparty_name),
    nullif(p_payload ->> 'fundAccountId', '')::uuid,
    nullif(btrim(p_payload ->> 'referenceNo'), ''),
    nullif(btrim(p_payload ->> 'remark'), '')
  ) returning id into v_event_id;

  update public.fms_commercial_bill set
    status = v_target_status,
    settled_amount = case
      when v_target_status in ('endorsed', 'discounted', 'settled') then face_amount
      else settled_amount
    end,
    remark = case
      when p_action = 'cancel' then concat_ws(E'\n', nullif(remark, ''), '[取消原因] ' || btrim(p_payload ->> 'remark'))
      else remark
    end,
    version = version + 1
  where id = v_bill.id
  returning * into v_bill;

  perform app_private.enqueue_fms_posting_event(
    v_bill.tenant_id,
    'commercial_bill',
    v_event_type,
    v_bill.id,
    v_bill.bill_no,
    v_event_date,
    concat('商业票据', ' · ', v_bill.bill_no, ' · ', v_event_type),
    jsonb_build_object(
      'gross_amount', v_amount,
      'direction', v_bill.direction,
      'bill_type', v_bill.bill_type,
      'bill_id', v_bill.id,
      'bill_event_id', v_event_id,
      'counterparty_name', v_bill.counterparty_name,
      'fund_account_id', nullif(p_payload ->> 'fundAccountId', ''),
      'reference_no', nullif(p_payload ->> 'referenceNo', '')
    )
  );

  return v_bill;
end;
$$;

create or replace function public.fms_commercial_bill_summary(p_account_set_id uuid)
returns table (
  total_count bigint,
  active_count bigint,
  receivable_outstanding numeric,
  payable_outstanding numeric,
  due_within_30_days bigint,
  overdue_count bigint
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    count(*),
    count(*) filter (where b.status in ('draft', 'held')),
    coalesce(sum(b.face_amount - b.settled_amount) filter (
      where b.direction = 'receivable' and b.status in ('draft', 'held')
    ), 0),
    coalesce(sum(b.face_amount - b.settled_amount) filter (
      where b.direction = 'payable' and b.status in ('draft', 'held')
    ), 0),
    count(*) filter (
      where b.status = 'held' and b.due_date between current_date and current_date + 30
    ),
    count(*) filter (where b.status = 'held' and b.due_date < current_date)
  from public.fms_commercial_bill b
  where b.account_set_id = p_account_set_id
$$;

revoke execute on function public.save_fms_commercial_bill(jsonb) from public, anon;
revoke execute on function public.delete_fms_commercial_bill(uuid) from public, anon;
revoke execute on function public.act_fms_commercial_bill(uuid, text, jsonb) from public, anon;
revoke execute on function public.fms_commercial_bill_summary(uuid) from public, anon;
grant execute on function public.save_fms_commercial_bill(jsonb) to authenticated, service_role;
grant execute on function public.delete_fms_commercial_bill(uuid) to authenticated, service_role;
grant execute on function public.act_fms_commercial_bill(uuid, text, jsonb) to authenticated, service_role;
grant execute on function public.fms_commercial_bill_summary(uuid) to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000160'::uuid,'commercial_bill:received','应收票据确认收票',20,'success'),
    ('c2000000-0000-4000-8000-000000000161'::uuid,'commercial_bill:issued','应付票据确认出票',21,'primary'),
    ('c2000000-0000-4000-8000-000000000162'::uuid,'commercial_bill:endorsed','商业票据背书转让',22,'warning'),
    ('c2000000-0000-4000-8000-000000000163'::uuid,'commercial_bill:discounted','应收票据贴现',23,'success'),
    ('c2000000-0000-4000-8000-000000000164'::uuid,'commercial_bill:settled','商业票据到期结算',24,'success'),
    ('c2000000-0000-4000-8000-000000000165'::uuid,'commercial_bill:cancelled','商业票据取消',25,'info')
  ) as i(id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select i.id, 'b2000000-0000-4000-8000-000000000013'::uuid,
  i.value, '1', i.value, i.label, i.sort, i.tag_type,
  '624944977@qq.com', '624944977@qq.com', p.id
from platform_tenant p cross join dictionary_items i
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, status = excluded.status,
  value = excluded.value, label = excluded.label, sort = excluded.sort,
  tag_type = excluded.tag_type, update_by = excluded.update_by, update_time = now();

commit;

;
