begin;

create table public.fms_fund_transfer (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  transfer_no text not null,
  source_account_id uuid not null,
  target_account_id uuid not null,
  transfer_date date not null,
  amount numeric(18, 2) not null,
  fee_amount numeric(18, 2) not null default 0,
  purpose text not null,
  bank_reference text,
  status text not null default 'draft',
  submitted_at timestamptz,
  submitted_by text,
  reviewed_at timestamptz,
  reviewed_by text,
  review_remark text,
  completed_at timestamptz,
  completed_by text,
  reversed_at timestamptz,
  reversed_by text,
  reversal_reason text,
  version integer not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_fund_transfer_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set (id, tenant_id) on delete restrict,
  constraint fms_fund_transfer_source_account_fkey
    foreign key (source_account_id, account_set_id, tenant_id)
    references public.fms_fund_account (id, account_set_id, tenant_id) on delete restrict,
  constraint fms_fund_transfer_target_account_fkey
    foreign key (target_account_id, account_set_id, tenant_id)
    references public.fms_fund_account (id, account_set_id, tenant_id) on delete restrict,
  constraint fms_fund_transfer_scope_no_key unique (account_set_id, transfer_no),
  constraint fms_fund_transfer_accounts_check check (source_account_id <> target_account_id),
  constraint fms_fund_transfer_amount_check check (amount > 0),
  constraint fms_fund_transfer_fee_check check (fee_amount >= 0),
  constraint fms_fund_transfer_purpose_check check (btrim(purpose) <> ''),
  constraint fms_fund_transfer_status_check check (
    status in ('draft', 'pending_review', 'approved', 'rejected', 'completed', 'reversed')
  ),
  constraint fms_fund_transfer_version_check check (version > 0)
);

create table public.fms_fund_transfer_action (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  transfer_id uuid not null,
  action text not null,
  from_status text,
  to_status text not null,
  action_remark text,
  action_by text not null,
  action_time timestamptz not null default now(),
  constraint fms_fund_transfer_action_transfer_fkey
    foreign key (transfer_id) references public.fms_fund_transfer (id) on delete cascade,
  constraint fms_fund_transfer_action_action_check check (
    action in ('create', 'edit', 'submit', 'approve', 'reject', 'execute', 'reverse')
  )
);

create index fms_fund_transfer_list_idx
  on public.fms_fund_transfer (tenant_id, account_set_id, status, transfer_date desc, create_time desc);
create index fms_fund_transfer_source_fk_idx
  on public.fms_fund_transfer (source_account_id, account_set_id, tenant_id);
create index fms_fund_transfer_target_fk_idx
  on public.fms_fund_transfer (target_account_id, account_set_id, tenant_id);
create index fms_fund_transfer_action_transfer_idx
  on public.fms_fund_transfer_action (transfer_id, action_time desc);
create index fms_fund_transfer_action_tenant_idx
  on public.fms_fund_transfer_action (tenant_id, action_time desc);

drop trigger if exists fms_fund_transfer_create_audit on public.fms_fund_transfer;
create trigger fms_fund_transfer_create_audit
before insert on public.fms_fund_transfer
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists fms_fund_transfer_update_audit on public.fms_fund_transfer;
create trigger fms_fund_transfer_update_audit
before update on public.fms_fund_transfer
for each row execute function public.trg_set_update_time_and_by();

alter table public.fms_fund_transfer enable row level security;
alter table public.fms_fund_transfer_action enable row level security;

create policy fms_fund_transfer_tenant_select on public.fms_fund_transfer
for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_fund_transfer_super_insert on public.fms_fund_transfer
for insert to authenticated with check ((select app_private.is_platform_super()));
create policy fms_fund_transfer_super_update on public.fms_fund_transfer
for update to authenticated using ((select app_private.is_platform_super()))
with check ((select app_private.is_platform_super()));
create policy fms_fund_transfer_super_delete on public.fms_fund_transfer
for delete to authenticated using ((select app_private.is_platform_super()));

create policy fms_fund_transfer_action_tenant_select on public.fms_fund_transfer_action
for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_fund_transfer_action_super_insert on public.fms_fund_transfer_action
for insert to authenticated with check ((select app_private.is_platform_super()));

grant select, insert, update, delete on public.fms_fund_transfer to authenticated;
grant all on public.fms_fund_transfer to service_role;
grant select, insert on public.fms_fund_transfer_action to authenticated;
grant all on public.fms_fund_transfer_action to service_role;

create or replace view public.fms_fund_transfer_summary
with (security_invoker = true)
as
select
  t.*,
  source.account_code as source_account_code,
  source.account_name as source_account_name,
  source.account_no_masked as source_account_no_masked,
  target.account_code as target_account_code,
  target.account_name as target_account_name,
  target.account_no_masked as target_account_no_masked,
  c.currency_code,
  c.currency_name,
  c.symbol as currency_symbol
from public.fms_fund_transfer t
join public.fms_fund_account source on source.id = t.source_account_id
join public.fms_fund_account target on target.id = t.target_account_id
join public.fms_currency c on c.id = source.currency_id;

grant select on public.fms_fund_transfer_summary to authenticated, service_role;

create or replace function app_private.validate_fms_fund_transfer_accounts(
  p_source_account_id uuid,
  p_target_account_id uuid
)
returns table (
  tenant_id uuid,
  account_set_id uuid,
  currency_id uuid,
  source_available_balance numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source public.fms_fund_account_summary%rowtype;
  v_target public.fms_fund_account%rowtype;
begin
  if p_source_account_id is null or p_target_account_id is null
    or p_source_account_id = p_target_account_id then
    raise exception using errcode = '23514', message = '转出账户和转入账户必须不同';
  end if;
  select * into v_source
  from public.fms_fund_account_summary
  where id = p_source_account_id and status = 'active';
  select * into v_target
  from public.fms_fund_account
  where id = p_target_account_id and status = 'active';
  if v_source.id is null or v_target.id is null then
    raise exception using errcode = '23503', message = '转出或转入账户不存在、已冻结或已关闭';
  end if;
  if v_source.tenant_id <> v_target.tenant_id
    or v_source.account_set_id <> v_target.account_set_id then
    raise exception using errcode = '23514', message = '内部调拨必须在同一账套内完成';
  end if;
  if v_source.currency_id <> v_target.currency_id then
    raise exception using errcode = '23514', message = '内部调拨暂不支持跨币种，跨币种请使用购结汇业务';
  end if;
  return query select v_source.tenant_id, v_source.account_set_id,
    v_source.currency_id, v_source.available_balance;
end;
$$;

create or replace function app_private.log_fms_fund_transfer_action(
  p_transfer public.fms_fund_transfer,
  p_action text,
  p_from_status text,
  p_remark text default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.fms_fund_transfer_action (
    tenant_id, transfer_id, action, from_status, to_status, action_remark, action_by
  ) values (
    p_transfer.tenant_id,
    p_transfer.id,
    p_action,
    p_from_status,
    p_transfer.status,
    nullif(btrim(p_remark), ''),
    coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'system')
  )
$$;

create or replace function public.save_fms_fund_transfer(p_payload jsonb)
returns public.fms_fund_transfer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_scope record;
  v_record public.fms_fund_transfer%rowtype;
  v_old_status text;
  v_expected_version integer := nullif(p_payload ->> 'version', '')::integer;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护资金调拨单';
  end if;
  if coalesce(nullif(p_payload ->> 'amount', '')::numeric, 0) <= 0
    or coalesce(nullif(p_payload ->> 'feeAmount', '')::numeric, 0) < 0 then
    raise exception using errcode = '23514', message = '调拨金额必须大于零且手续费不能为负数';
  end if;
  if nullif(btrim(p_payload ->> 'purpose'), '') is null then
    raise exception using errcode = '23514', message = '请填写调拨用途';
  end if;
  select * into v_scope
  from app_private.validate_fms_fund_transfer_accounts(
    (p_payload ->> 'sourceAccountId')::uuid,
    (p_payload ->> 'targetAccountId')::uuid
  );

  if v_id is null then
    insert into public.fms_fund_transfer (
      tenant_id, account_set_id, transfer_no, source_account_id, target_account_id,
      transfer_date, amount, fee_amount, purpose, bank_reference
    ) values (
      v_scope.tenant_id,
      v_scope.account_set_id,
      coalesce(nullif(btrim(p_payload ->> 'transferNo'), ''),
        'ZJDB' || to_char(clock_timestamp(), 'YYYYMMDD') || '-'
          || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
      (p_payload ->> 'sourceAccountId')::uuid,
      (p_payload ->> 'targetAccountId')::uuid,
      coalesce(nullif(p_payload ->> 'transferDate', '')::date, current_date),
      round((p_payload ->> 'amount')::numeric, 2),
      round(coalesce(nullif(p_payload ->> 'feeAmount', '')::numeric, 0), 2),
      btrim(p_payload ->> 'purpose'),
      nullif(btrim(p_payload ->> 'bankReference'), '')
    ) returning * into v_record;
    perform app_private.log_fms_fund_transfer_action(v_record, 'create', null, null);
  else
    select * into v_record from public.fms_fund_transfer where id = v_id for update;
    if not found then raise exception using errcode = 'P0002', message = '资金调拨单不存在'; end if;
    if v_record.status not in ('draft', 'rejected') then
      raise exception using errcode = '23514', message = '仅草稿或已驳回的调拨单可以编辑';
    end if;
    if v_expected_version is not null and v_record.version <> v_expected_version then
      raise exception using errcode = '40001', message = '调拨单已被其他人修改，请刷新后重试';
    end if;
    if v_record.tenant_id <> v_scope.tenant_id
      or v_record.account_set_id <> v_scope.account_set_id then
      raise exception using errcode = '23514', message = '不能跨租户或跨账套修改调拨单';
    end if;
    v_old_status := v_record.status;
    update public.fms_fund_transfer set
      source_account_id = (p_payload ->> 'sourceAccountId')::uuid,
      target_account_id = (p_payload ->> 'targetAccountId')::uuid,
      transfer_date = coalesce(nullif(p_payload ->> 'transferDate', '')::date, transfer_date),
      amount = round((p_payload ->> 'amount')::numeric, 2),
      fee_amount = round(coalesce(nullif(p_payload ->> 'feeAmount', '')::numeric, 0), 2),
      purpose = btrim(p_payload ->> 'purpose'),
      bank_reference = nullif(btrim(p_payload ->> 'bankReference'), ''),
      status = 'draft',
      review_remark = null,
      version = version + 1
    where id = v_id returning * into v_record;
    perform app_private.log_fms_fund_transfer_action(v_record, 'edit', v_old_status, null);
  end if;
  return v_record;
end;
$$;

create or replace function public.transition_fms_fund_transfer(
  p_transfer_id uuid,
  p_action text,
  p_remark text default null,
  p_execution_date date default null,
  p_expected_version integer default null
)
returns public.fms_fund_transfer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.fms_fund_transfer%rowtype;
  v_old_status text;
  v_scope record;
  v_source_entry public.fms_fund_ledger_entry%rowtype;
  v_target_entry public.fms_fund_ledger_entry%rowtype;
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'system');
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行资金调拨审批与入账';
  end if;
  select * into v_record from public.fms_fund_transfer where id = p_transfer_id for update;
  if not found then raise exception using errcode = 'P0002', message = '资金调拨单不存在'; end if;
  if p_expected_version is not null and v_record.version <> p_expected_version then
    raise exception using errcode = '40001', message = '调拨单已被其他人处理，请刷新后重试';
  end if;
  v_old_status := v_record.status;

  if p_action = 'submit' then
    if v_record.status not in ('draft', 'rejected') then
      raise exception using errcode = '23514', message = '当前状态不能提交审批';
    end if;
    update public.fms_fund_transfer set
      status = 'pending_review', submitted_at = now(), submitted_by = v_actor,
      review_remark = null, version = version + 1
    where id = p_transfer_id returning * into v_record;
  elsif p_action = 'approve' then
    if v_record.status <> 'pending_review' then
      raise exception using errcode = '23514', message = '仅待审批调拨单可以通过';
    end if;
    update public.fms_fund_transfer set
      status = 'approved', reviewed_at = now(), reviewed_by = v_actor,
      review_remark = nullif(btrim(p_remark), ''), version = version + 1
    where id = p_transfer_id returning * into v_record;
  elsif p_action = 'reject' then
    if v_record.status <> 'pending_review' then
      raise exception using errcode = '23514', message = '仅待审批调拨单可以驳回';
    end if;
    if nullif(btrim(p_remark), '') is null then
      raise exception using errcode = '23514', message = '驳回时必须填写原因';
    end if;
    update public.fms_fund_transfer set
      status = 'rejected', reviewed_at = now(), reviewed_by = v_actor,
      review_remark = btrim(p_remark), version = version + 1
    where id = p_transfer_id returning * into v_record;
  elsif p_action = 'execute' then
    if v_record.status <> 'approved' then
      raise exception using errcode = '23514', message = '仅审批通过的调拨单可以执行入账';
    end if;
    select * into v_scope
    from app_private.validate_fms_fund_transfer_accounts(
      v_record.source_account_id, v_record.target_account_id
    );
    if v_scope.source_available_balance < v_record.amount + v_record.fee_amount then
      raise exception using errcode = '23514', message = '转出账户可用余额不足';
    end if;
    perform app_private.post_fms_fund_ledger_entry(
      v_record.source_account_id,
      coalesce(p_execution_date, v_record.transfer_date),
      'outflow', v_record.amount + v_record.fee_amount, 'fund_transfer',
      v_record.id, v_record.transfer_no,
      '资金调拨转出 · ' || v_record.transfer_no
        || case when v_record.fee_amount > 0 then '（含手续费）' else '' end,
      null, v_record.bank_reference
    );
    perform app_private.post_fms_fund_ledger_entry(
      v_record.target_account_id,
      coalesce(p_execution_date, v_record.transfer_date),
      'inflow', v_record.amount, 'fund_transfer',
      v_record.id, v_record.transfer_no,
      '资金调拨转入 · ' || v_record.transfer_no,
      null, v_record.bank_reference
    );
    update public.fms_fund_transfer set
      status = 'completed', completed_at = now(), completed_by = v_actor,
      version = version + 1
    where id = p_transfer_id returning * into v_record;
  elsif p_action = 'reverse' then
    if v_record.status <> 'completed' then
      raise exception using errcode = '23514', message = '仅已完成的调拨单可以冲销';
    end if;
    if nullif(btrim(p_remark), '') is null then
      raise exception using errcode = '23514', message = '冲销时必须填写原因';
    end if;
    select * into v_source_entry from public.fms_fund_ledger_entry
    where fund_account_id = v_record.source_account_id
      and source_type = 'fund_transfer' and source_id = v_record.id
      and direction = 'outflow' and status = 'posted' for update;
    select * into v_target_entry from public.fms_fund_ledger_entry
    where fund_account_id = v_record.target_account_id
      and source_type = 'fund_transfer' and source_id = v_record.id
      and direction = 'inflow' and status = 'posted' for update;
    if v_source_entry.id is null or v_target_entry.id is null then
      raise exception using errcode = 'P0002', message = '未找到可冲销的原始资金流水';
    end if;
    perform app_private.post_fms_fund_ledger_entry(
      v_record.source_account_id, coalesce(p_execution_date, current_date),
      'inflow', v_source_entry.amount, 'fund_transfer', v_record.id,
      v_record.transfer_no, '资金调拨冲销 · ' || v_record.transfer_no,
      null, v_record.bank_reference, v_source_entry.id
    );
    perform app_private.post_fms_fund_ledger_entry(
      v_record.target_account_id, coalesce(p_execution_date, current_date),
      'outflow', v_target_entry.amount, 'fund_transfer', v_record.id,
      v_record.transfer_no, '资金调拨冲销 · ' || v_record.transfer_no,
      null, v_record.bank_reference, v_target_entry.id
    );
    update public.fms_fund_transfer set
      status = 'reversed', reversed_at = now(), reversed_by = v_actor,
      reversal_reason = btrim(p_remark), version = version + 1
    where id = p_transfer_id returning * into v_record;
  else
    raise exception using errcode = '22023', message = '不支持的调拨操作';
  end if;

  perform app_private.log_fms_fund_transfer_action(v_record, p_action, v_old_status, p_remark);
  return v_record;
end;
$$;

create or replace function public.delete_fms_fund_transfer(p_transfer_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可删除资金调拨单';
  end if;
  select status into v_status from public.fms_fund_transfer where id = p_transfer_id for update;
  if not found then raise exception using errcode = 'P0002', message = '资金调拨单不存在'; end if;
  if v_status not in ('draft', 'rejected') then
    raise exception using errcode = '23514', message = '仅草稿或已驳回的调拨单可以删除';
  end if;
  delete from public.fms_fund_transfer where id = p_transfer_id;
  return p_transfer_id;
end;
$$;

revoke all on function app_private.validate_fms_fund_transfer_accounts(uuid, uuid)
  from public, anon, authenticated;
revoke all on function app_private.log_fms_fund_transfer_action(
  public.fms_fund_transfer, text, text, text
) from public, anon, authenticated;

revoke execute on function public.save_fms_fund_transfer(jsonb) from public, anon;
revoke execute on function public.transition_fms_fund_transfer(uuid, text, text, date, integer)
  from public, anon;
revoke execute on function public.delete_fms_fund_transfer(uuid) from public, anon;

grant execute on function public.save_fms_fund_transfer(jsonb) to authenticated, service_role;
grant execute on function public.transition_fms_fund_transfer(uuid, text, text, date, integer)
  to authenticated, service_role;
grant execute on function public.delete_fms_fund_transfer(uuid) to authenticated, service_role;

commit;

;
