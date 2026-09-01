begin;

create table public.fms_bank_reconciliation_batch (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  fund_account_id uuid not null,
  batch_no text not null,
  statement_start_date date not null,
  statement_end_date date not null,
  opening_balance numeric(18, 2) not null,
  closing_balance numeric(18, 2) not null,
  imported_file_name text,
  imported_at timestamptz not null default now(),
  imported_by text not null,
  status text not null default 'draft',
  completed_at timestamptz,
  completed_by text,
  voided_at timestamptz,
  voided_by text,
  void_reason text,
  remark text,
  version integer not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_bank_reconciliation_batch_account_fkey
    foreign key (fund_account_id, account_set_id, tenant_id)
    references public.fms_fund_account (id, account_set_id, tenant_id) on delete restrict,
  constraint fms_bank_reconciliation_batch_no_key unique (account_set_id, batch_no),
  constraint fms_bank_reconciliation_batch_dates_check check (
    statement_start_date <= statement_end_date
  ),
  constraint fms_bank_reconciliation_batch_status_check check (
    status in ('draft', 'reconciling', 'reconciled', 'voided')
  ),
  constraint fms_bank_reconciliation_batch_version_check check (version > 0)
);

create table public.fms_bank_statement_line (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  account_set_id uuid not null,
  batch_id uuid not null,
  fund_account_id uuid not null,
  line_no integer not null,
  transaction_date date not null,
  direction text not null,
  amount numeric(18, 2) not null,
  statement_balance numeric(18, 2),
  counterparty_name text,
  counterparty_account_masked text,
  bank_reference text,
  bank_serial_no text,
  bank_memo text,
  import_hash text not null,
  status text not null default 'unmatched',
  ignored_reason text,
  ignored_at timestamptz,
  ignored_by text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_bank_statement_line_batch_fkey
    foreign key (batch_id) references public.fms_bank_reconciliation_batch (id) on delete cascade,
  constraint fms_bank_statement_line_account_fkey
    foreign key (fund_account_id, account_set_id, tenant_id)
    references public.fms_fund_account (id, account_set_id, tenant_id) on delete restrict,
  constraint fms_bank_statement_line_batch_line_key unique (batch_id, line_no),
  constraint fms_bank_statement_line_batch_hash_key unique (batch_id, import_hash),
  constraint fms_bank_statement_line_direction_check check (direction in ('inflow', 'outflow')),
  constraint fms_bank_statement_line_amount_check check (amount > 0),
  constraint fms_bank_statement_line_status_check check (
    status in ('unmatched', 'partial_matched', 'matched', 'ignored')
  )
);

create table public.fms_bank_statement_match (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  statement_line_id uuid not null,
  ledger_entry_id uuid not null,
  matched_amount numeric(18, 2) not null,
  match_type text not null,
  confidence_score numeric(5, 2),
  match_remark text,
  matched_by text not null,
  matched_at timestamptz not null default now(),
  constraint fms_bank_statement_match_line_fkey
    foreign key (statement_line_id) references public.fms_bank_statement_line (id) on delete cascade,
  constraint fms_bank_statement_match_ledger_fkey
    foreign key (ledger_entry_id) references public.fms_fund_ledger_entry (id) on delete restrict,
  constraint fms_bank_statement_match_pair_key unique (statement_line_id, ledger_entry_id),
  constraint fms_bank_statement_match_amount_check check (matched_amount > 0),
  constraint fms_bank_statement_match_type_check check (match_type in ('automatic', 'manual')),
  constraint fms_bank_statement_match_confidence_check check (
    confidence_score is null or confidence_score between 0 and 100
  )
);

create index fms_bank_reconciliation_batch_list_idx
  on public.fms_bank_reconciliation_batch (
    tenant_id, account_set_id, fund_account_id, status, statement_end_date desc
  );
create index fms_bank_reconciliation_batch_account_fk_idx
  on public.fms_bank_reconciliation_batch (fund_account_id, account_set_id, tenant_id);
create index fms_bank_statement_line_list_idx
  on public.fms_bank_statement_line (batch_id, status, transaction_date, line_no);
create index fms_bank_statement_line_account_idx
  on public.fms_bank_statement_line (fund_account_id, transaction_date, direction, amount);
create index fms_bank_statement_line_account_fk_idx
  on public.fms_bank_statement_line (fund_account_id, account_set_id, tenant_id);
create index fms_bank_statement_match_line_idx
  on public.fms_bank_statement_match (statement_line_id, matched_at);
create index fms_bank_statement_match_ledger_idx
  on public.fms_bank_statement_match (ledger_entry_id, matched_at);
create index fms_bank_statement_match_tenant_idx
  on public.fms_bank_statement_match (tenant_id, matched_at desc);

drop trigger if exists fms_bank_reconciliation_batch_create_audit
  on public.fms_bank_reconciliation_batch;
create trigger fms_bank_reconciliation_batch_create_audit
before insert on public.fms_bank_reconciliation_batch
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists fms_bank_reconciliation_batch_update_audit
  on public.fms_bank_reconciliation_batch;
create trigger fms_bank_reconciliation_batch_update_audit
before update on public.fms_bank_reconciliation_batch
for each row execute function public.trg_set_update_time_and_by();
drop trigger if exists fms_bank_statement_line_create_audit on public.fms_bank_statement_line;
create trigger fms_bank_statement_line_create_audit
before insert on public.fms_bank_statement_line
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists fms_bank_statement_line_update_audit on public.fms_bank_statement_line;
create trigger fms_bank_statement_line_update_audit
before update on public.fms_bank_statement_line
for each row execute function public.trg_set_update_time_and_by();

alter table public.fms_bank_reconciliation_batch enable row level security;
alter table public.fms_bank_statement_line enable row level security;
alter table public.fms_bank_statement_match enable row level security;

create policy fms_bank_reconciliation_batch_tenant_select
on public.fms_bank_reconciliation_batch for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_bank_reconciliation_batch_super_insert
on public.fms_bank_reconciliation_batch for insert to authenticated
with check ((select app_private.is_platform_super()));
create policy fms_bank_reconciliation_batch_super_update
on public.fms_bank_reconciliation_batch for update to authenticated
using ((select app_private.is_platform_super())) with check ((select app_private.is_platform_super()));
create policy fms_bank_reconciliation_batch_super_delete
on public.fms_bank_reconciliation_batch for delete to authenticated
using ((select app_private.is_platform_super()));

create policy fms_bank_statement_line_tenant_select
on public.fms_bank_statement_line for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_bank_statement_line_super_insert
on public.fms_bank_statement_line for insert to authenticated
with check ((select app_private.is_platform_super()));
create policy fms_bank_statement_line_super_update
on public.fms_bank_statement_line for update to authenticated
using ((select app_private.is_platform_super())) with check ((select app_private.is_platform_super()));
create policy fms_bank_statement_line_super_delete
on public.fms_bank_statement_line for delete to authenticated
using ((select app_private.is_platform_super()));

create policy fms_bank_statement_match_tenant_select
on public.fms_bank_statement_match for select to authenticated using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy fms_bank_statement_match_super_insert
on public.fms_bank_statement_match for insert to authenticated
with check ((select app_private.is_platform_super()));
create policy fms_bank_statement_match_super_delete
on public.fms_bank_statement_match for delete to authenticated
using ((select app_private.is_platform_super()));

grant select, insert, update, delete on public.fms_bank_reconciliation_batch to authenticated;
grant all on public.fms_bank_reconciliation_batch to service_role;
grant select, insert, update, delete on public.fms_bank_statement_line to authenticated;
grant all on public.fms_bank_statement_line to service_role;
grant select, insert, delete on public.fms_bank_statement_match to authenticated;
grant all on public.fms_bank_statement_match to service_role;

create or replace view public.fms_bank_statement_line_summary
with (security_invoker = true)
as
select
  l.*,
  coalesce(m.matched_amount, 0)::numeric(18, 2) as matched_amount,
  greatest(l.amount - coalesce(m.matched_amount, 0), 0)::numeric(18, 2) as remaining_amount,
  coalesce(m.match_count, 0)::integer as match_count,
  m.match_types,
  m.latest_matched_at
from public.fms_bank_statement_line l
left join lateral (
  select
    sum(x.matched_amount) as matched_amount,
    count(*) as match_count,
    string_agg(distinct x.match_type, ',') as match_types,
    max(x.matched_at) as latest_matched_at
  from public.fms_bank_statement_match x
  where x.statement_line_id = l.id
) m on true;

create or replace view public.fms_bank_reconciliation_batch_summary
with (security_invoker = true)
as
select
  b.*,
  a.account_code,
  a.account_name,
  a.account_no_masked,
  c.currency_code,
  c.symbol as currency_symbol,
  coalesce(l.line_count, 0)::integer as line_count,
  coalesce(l.matched_count, 0)::integer as matched_count,
  coalesce(l.partial_count, 0)::integer as partial_count,
  coalesce(l.ignored_count, 0)::integer as ignored_count,
  coalesce(l.unmatched_count, 0)::integer as unmatched_count,
  coalesce(l.inflow_amount, 0)::numeric(18, 2) as statement_inflow_amount,
  coalesce(l.outflow_amount, 0)::numeric(18, 2) as statement_outflow_amount,
  coalesce(l.matched_amount, 0)::numeric(18, 2) as matched_amount,
  (b.opening_balance + coalesce(l.inflow_amount, 0) - coalesce(l.outflow_amount, 0))::numeric(18, 2)
    as calculated_closing_balance,
  (b.closing_balance - (
    b.opening_balance + coalesce(l.inflow_amount, 0) - coalesce(l.outflow_amount, 0)
  ))::numeric(18, 2) as statement_balance_difference
from public.fms_bank_reconciliation_batch b
join public.fms_fund_account a on a.id = b.fund_account_id
join public.fms_currency c on c.id = a.currency_id
left join lateral (
  select
    count(*) as line_count,
    count(*) filter (where s.status = 'matched') as matched_count,
    count(*) filter (where s.status = 'partial_matched') as partial_count,
    count(*) filter (where s.status = 'ignored') as ignored_count,
    count(*) filter (where s.status = 'unmatched') as unmatched_count,
    sum(case when s.direction = 'inflow' then s.amount else 0 end) as inflow_amount,
    sum(case when s.direction = 'outflow' then s.amount else 0 end) as outflow_amount,
    sum(s.matched_amount) as matched_amount
  from public.fms_bank_statement_line_summary s
  where s.batch_id = b.id
) l on true;

grant select on public.fms_bank_statement_line_summary to authenticated, service_role;
grant select on public.fms_bank_reconciliation_batch_summary to authenticated, service_role;

create or replace function app_private.refresh_fms_bank_statement_line_status(p_line_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_amount numeric;
  v_matched numeric;
begin
  select amount into v_amount from public.fms_bank_statement_line where id = p_line_id for update;
  if not found then return; end if;
  select coalesce(sum(matched_amount), 0) into v_matched
  from public.fms_bank_statement_match where statement_line_id = p_line_id;
  update public.fms_bank_statement_line
  set status = case
    when v_matched = 0 then 'unmatched'
    when v_matched < v_amount then 'partial_matched'
    else 'matched'
  end,
  ignored_reason = null,
  ignored_at = null,
  ignored_by = null
  where id = p_line_id;
end;
$$;

create or replace function public.import_fms_bank_reconciliation(p_payload jsonb)
returns public.fms_bank_reconciliation_batch
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.fms_fund_account%rowtype;
  v_batch public.fms_bank_reconciliation_batch%rowtype;
  v_line jsonb;
  v_line_no integer := 0;
  v_start_date date := (p_payload ->> 'statementStartDate')::date;
  v_end_date date := (p_payload ->> 'statementEndDate')::date;
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'system');
  v_direction text;
  v_amount numeric;
  v_transaction_date date;
  v_hash text;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可导入银行流水';
  end if;
  select * into v_account from public.fms_fund_account
  where id = (p_payload ->> 'fundAccountId')::uuid
    and status = 'active' and reconciliation_enabled;
  if not found then
    raise exception using errcode = '23503', message = '资金账户不存在、不可用或未启用银行对账';
  end if;
  if v_start_date is null or v_end_date is null or v_start_date > v_end_date then
    raise exception using errcode = '23514', message = '银行对账单期间不正确';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'lines', '[]'::jsonb)) <> 'array'
    or jsonb_array_length(coalesce(p_payload -> 'lines', '[]'::jsonb)) = 0 then
    raise exception using errcode = '23514', message = '银行流水不能为空';
  end if;
  if exists (
    select 1 from public.fms_bank_reconciliation_batch b
    where b.fund_account_id = v_account.id and b.status <> 'voided'
      and daterange(b.statement_start_date, b.statement_end_date, '[]')
        && daterange(v_start_date, v_end_date, '[]')
  ) then
    raise exception using errcode = '23505', message = '该资金账户存在期间重叠的有效对账批次';
  end if;

  insert into public.fms_bank_reconciliation_batch (
    tenant_id, account_set_id, fund_account_id, batch_no,
    statement_start_date, statement_end_date, opening_balance, closing_balance,
    imported_file_name, imported_by, status, remark
  ) values (
    v_account.tenant_id,
    v_account.account_set_id,
    v_account.id,
    coalesce(nullif(btrim(p_payload ->> 'batchNo'), ''),
      'YHDZ' || to_char(clock_timestamp(), 'YYYYMMDD') || '-'
        || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))),
    v_start_date,
    v_end_date,
    round((p_payload ->> 'openingBalance')::numeric, 2),
    round((p_payload ->> 'closingBalance')::numeric, 2),
    nullif(btrim(p_payload ->> 'importedFileName'), ''),
    v_actor,
    'reconciling',
    nullif(btrim(p_payload ->> 'remark'), '')
  ) returning * into v_batch;

  for v_line in select value from jsonb_array_elements(p_payload -> 'lines') loop
    v_line_no := v_line_no + 1;
    v_direction := v_line ->> 'direction';
    v_amount := round((v_line ->> 'amount')::numeric, 2);
    v_transaction_date := (v_line ->> 'transactionDate')::date;
    if v_direction not in ('inflow', 'outflow') or coalesce(v_amount, 0) <= 0 then
      raise exception using errcode = '23514',
        message = format('第 %s 行的收支方向或金额不正确', v_line_no);
    end if;
    if v_transaction_date not between v_start_date and v_end_date then
      raise exception using errcode = '23514',
        message = format('第 %s 行的交易日期不在对账期间内', v_line_no);
    end if;
    v_hash := encode(extensions.digest(concat_ws('|',
      v_account.id::text,
      v_transaction_date::text,
      v_direction,
      v_amount::text,
      coalesce(v_line ->> 'bankSerialNo', ''),
      coalesce(v_line ->> 'bankReference', ''),
      coalesce(v_line ->> 'counterpartyName', ''),
      coalesce(v_line ->> 'bankMemo', '')
    ), 'sha256'), 'hex');
    insert into public.fms_bank_statement_line (
      tenant_id, account_set_id, batch_id, fund_account_id, line_no,
      transaction_date, direction, amount, statement_balance,
      counterparty_name, counterparty_account_masked, bank_reference,
      bank_serial_no, bank_memo, import_hash
    ) values (
      v_account.tenant_id, v_account.account_set_id, v_batch.id, v_account.id, v_line_no,
      v_transaction_date, v_direction, v_amount,
      nullif(v_line ->> 'statementBalance', '')::numeric,
      nullif(btrim(v_line ->> 'counterpartyName'), ''),
      app_private.mask_fms_fund_account_no(v_line ->> 'counterpartyAccount'),
      nullif(btrim(v_line ->> 'bankReference'), ''),
      nullif(btrim(v_line ->> 'bankSerialNo'), ''),
      nullif(btrim(v_line ->> 'bankMemo'), ''),
      v_hash
    );
  end loop;
  return v_batch;
end;
$$;

create or replace function public.auto_match_fms_bank_reconciliation(
  p_batch_id uuid,
  p_date_tolerance_days integer default 3
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_batch public.fms_bank_reconciliation_batch%rowtype;
  v_line public.fms_bank_statement_line%rowtype;
  v_candidate_id uuid;
  v_candidate_count integer;
  v_score integer;
  v_matched_count integer := 0;
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'system');
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行自动对账';
  end if;
  if p_date_tolerance_days not between 0 and 30 then
    raise exception using errcode = '22023', message = '日期容差必须在 0 至 30 天之间';
  end if;
  select * into v_batch from public.fms_bank_reconciliation_batch
  where id = p_batch_id for update;
  if not found then raise exception using errcode = 'P0002', message = '银行对账批次不存在'; end if;
  if v_batch.status not in ('draft', 'reconciling') then
    raise exception using errcode = '23514', message = '当前批次不能执行自动匹配';
  end if;

  for v_line in
    select * from public.fms_bank_statement_line
    where batch_id = p_batch_id and status = 'unmatched'
    order by transaction_date, line_no
    for update
  loop
    with scored as (
      select
        e.id,
        50
          + case when e.entry_date = v_line.transaction_date then 30 else 0 end
          + case when v_line.bank_reference is not null
              and e.bank_reference = v_line.bank_reference then 20 else 0 end
          + case when v_line.bank_serial_no is not null
              and e.bank_reference = v_line.bank_serial_no then 15 else 0 end
          + case when v_line.bank_reference is not null
              and e.source_no = v_line.bank_reference then 10 else 0 end as score
      from public.fms_fund_ledger_entry e
      where e.fund_account_id = v_line.fund_account_id
        and e.direction = v_line.direction
        and e.amount = v_line.amount
        and e.entry_date between
          v_line.transaction_date - p_date_tolerance_days
          and v_line.transaction_date + p_date_tolerance_days
        and not exists (
          select 1 from public.fms_bank_statement_match x
          where x.ledger_entry_id = e.id
        )
    ), ranked as (
      select *, dense_rank() over (order by score desc) as score_rank
      from scored
    )
    select (array_agg(id order by id))[1], count(*)::integer, max(score)
      into v_candidate_id, v_candidate_count, v_score
    from ranked
    where score_rank = 1;

    if v_candidate_count = 1 and v_score >= 80 then
      insert into public.fms_bank_statement_match (
        tenant_id, statement_line_id, ledger_entry_id, matched_amount,
        match_type, confidence_score, match_remark, matched_by
      ) values (
        v_line.tenant_id, v_line.id, v_candidate_id, v_line.amount,
        'automatic', least(v_score, 100), '系统按金额、日期及参考号自动匹配', v_actor
      );
      update public.fms_bank_statement_line set status = 'matched' where id = v_line.id;
      v_matched_count := v_matched_count + 1;
    end if;
  end loop;
  update public.fms_bank_reconciliation_batch
  set status = 'reconciling', version = version + 1
  where id = p_batch_id and status = 'draft';
  return v_matched_count;
end;
$$;

create or replace function public.match_fms_bank_statement_line(
  p_statement_line_id uuid,
  p_ledger_entry_id uuid,
  p_matched_amount numeric default null,
  p_remark text default null
)
returns public.fms_bank_statement_match
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line public.fms_bank_statement_line%rowtype;
  v_ledger public.fms_fund_ledger_entry%rowtype;
  v_batch_status text;
  v_line_matched numeric;
  v_ledger_matched numeric;
  v_amount numeric;
  v_record public.fms_bank_statement_match%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可手工匹配银行流水';
  end if;
  select * into v_line from public.fms_bank_statement_line
  where id = p_statement_line_id for update;
  if not found then raise exception using errcode = 'P0002', message = '银行流水不存在'; end if;
  if v_line.status = 'ignored' then
    raise exception using errcode = '23514', message = '已忽略的银行流水不能匹配';
  end if;
  select status into v_batch_status from public.fms_bank_reconciliation_batch
  where id = v_line.batch_id for update;
  if v_batch_status not in ('draft', 'reconciling') then
    raise exception using errcode = '23514', message = '当前批次不能继续匹配';
  end if;
  select * into v_ledger from public.fms_fund_ledger_entry
  where id = p_ledger_entry_id for update;
  if not found then raise exception using errcode = 'P0002', message = '资金流水不存在'; end if;
  if v_ledger.fund_account_id <> v_line.fund_account_id
    or v_ledger.direction <> v_line.direction then
    raise exception using errcode = '23514', message = '银行流水与资金流水的账户或收支方向不一致';
  end if;
  select coalesce(sum(matched_amount), 0) into v_line_matched
  from public.fms_bank_statement_match where statement_line_id = v_line.id;
  select coalesce(sum(matched_amount), 0) into v_ledger_matched
  from public.fms_bank_statement_match where ledger_entry_id = v_ledger.id;
  v_amount := round(coalesce(p_matched_amount,
    least(v_line.amount - v_line_matched, v_ledger.amount - v_ledger_matched)), 2);
  if v_amount <= 0
    or v_line_matched + v_amount > v_line.amount
    or v_ledger_matched + v_amount > v_ledger.amount then
    raise exception using errcode = '23514', message = '匹配金额超过银行流水或资金流水的剩余可匹配金额';
  end if;
  insert into public.fms_bank_statement_match (
    tenant_id, statement_line_id, ledger_entry_id, matched_amount,
    match_type, confidence_score, match_remark, matched_by
  ) values (
    v_line.tenant_id, v_line.id, v_ledger.id, v_amount,
    'manual', null, nullif(btrim(p_remark), ''),
    coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'system')
  ) returning * into v_record;
  perform app_private.refresh_fms_bank_statement_line_status(v_line.id);
  update public.fms_bank_reconciliation_batch
  set status = 'reconciling', version = version + 1
  where id = v_line.batch_id and status = 'draft';
  return v_record;
end;
$$;

create or replace function public.unmatch_fms_bank_statement_line(p_match_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_line_id uuid;
  v_batch_status text;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可撤销银行流水匹配';
  end if;
  select m.statement_line_id, b.status into v_line_id, v_batch_status
  from public.fms_bank_statement_match m
  join public.fms_bank_statement_line l on l.id = m.statement_line_id
  join public.fms_bank_reconciliation_batch b on b.id = l.batch_id
  where m.id = p_match_id for update of m, l, b;
  if not found then raise exception using errcode = 'P0002', message = '匹配记录不存在'; end if;
  if v_batch_status not in ('draft', 'reconciling') then
    raise exception using errcode = '23514', message = '已完成或已作废的批次不能撤销匹配';
  end if;
  delete from public.fms_bank_statement_match where id = p_match_id;
  perform app_private.refresh_fms_bank_statement_line_status(v_line_id);
  return p_match_id;
end;
$$;

create or replace function public.ignore_fms_bank_statement_line(
  p_statement_line_id uuid,
  p_reason text
)
returns public.fms_bank_statement_line
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.fms_bank_statement_line%rowtype;
  v_batch_status text;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可忽略银行流水';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '23514', message = '忽略银行流水必须填写原因';
  end if;
  select * into v_record from public.fms_bank_statement_line
  where id = p_statement_line_id for update;
  if not found then raise exception using errcode = 'P0002', message = '银行流水不存在'; end if;
  select status into v_batch_status from public.fms_bank_reconciliation_batch
  where id = v_record.batch_id for update;
  if v_batch_status not in ('draft', 'reconciling') then
    raise exception using errcode = '23514', message = '当前批次不能忽略流水';
  end if;
  if exists (select 1 from public.fms_bank_statement_match where statement_line_id = v_record.id) then
    raise exception using errcode = '23514', message = '请先撤销已有匹配再忽略流水';
  end if;
  update public.fms_bank_statement_line set
    status = 'ignored', ignored_reason = btrim(p_reason), ignored_at = now(),
    ignored_by = coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'system')
  where id = v_record.id returning * into v_record;
  return v_record;
end;
$$;

create or replace function public.transition_fms_bank_reconciliation(
  p_batch_id uuid,
  p_action text,
  p_reason text default null,
  p_expected_version integer default null
)
returns public.fms_bank_reconciliation_batch
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_record public.fms_bank_reconciliation_batch%rowtype;
  v_summary public.fms_bank_reconciliation_batch_summary%rowtype;
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'system');
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可完成或作废银行对账';
  end if;
  select * into v_record from public.fms_bank_reconciliation_batch
  where id = p_batch_id for update;
  if not found then raise exception using errcode = 'P0002', message = '银行对账批次不存在'; end if;
  if p_expected_version is not null and v_record.version <> p_expected_version then
    raise exception using errcode = '40001', message = '对账批次已被其他人修改，请刷新后重试';
  end if;
  if p_action = 'complete' then
    if v_record.status not in ('draft', 'reconciling') then
      raise exception using errcode = '23514', message = '当前批次不能完成对账';
    end if;
    select * into v_summary from public.fms_bank_reconciliation_batch_summary
    where id = p_batch_id;
    if v_summary.line_count = 0
      or v_summary.unmatched_count > 0
      or v_summary.partial_count > 0 then
      raise exception using errcode = '23514', message = '仍有未匹配或部分匹配的银行流水';
    end if;
    if v_summary.statement_balance_difference <> 0 then
      raise exception using errcode = '23514', message = '对账单期末余额与流水汇总不一致';
    end if;
    update public.fms_bank_reconciliation_batch set
      status = 'reconciled', completed_at = now(), completed_by = v_actor,
      version = version + 1
    where id = p_batch_id returning * into v_record;
  elsif p_action = 'void' then
    if v_record.status not in ('draft', 'reconciling') then
      raise exception using errcode = '23514', message = '仅未完成的对账批次可以作废';
    end if;
    if nullif(btrim(p_reason), '') is null then
      raise exception using errcode = '23514', message = '作废对账批次必须填写原因';
    end if;
    delete from public.fms_bank_statement_match m
    using public.fms_bank_statement_line l
    where m.statement_line_id = l.id and l.batch_id = p_batch_id;
    update public.fms_bank_statement_line
    set status = 'unmatched', ignored_reason = null, ignored_at = null, ignored_by = null
    where batch_id = p_batch_id;
    update public.fms_bank_reconciliation_batch set
      status = 'voided', voided_at = now(), voided_by = v_actor,
      void_reason = btrim(p_reason), version = version + 1
    where id = p_batch_id returning * into v_record;
  else
    raise exception using errcode = '22023', message = '不支持的银行对账操作';
  end if;
  return v_record;
end;
$$;

revoke all on function app_private.refresh_fms_bank_statement_line_status(uuid)
  from public, anon, authenticated;
revoke execute on function public.import_fms_bank_reconciliation(jsonb) from public, anon;
revoke execute on function public.auto_match_fms_bank_reconciliation(uuid, integer)
  from public, anon;
revoke execute on function public.match_fms_bank_statement_line(uuid, uuid, numeric, text)
  from public, anon;
revoke execute on function public.unmatch_fms_bank_statement_line(uuid) from public, anon;
revoke execute on function public.ignore_fms_bank_statement_line(uuid, text) from public, anon;
revoke execute on function public.transition_fms_bank_reconciliation(uuid, text, text, integer)
  from public, anon;

grant execute on function public.import_fms_bank_reconciliation(jsonb)
  to authenticated, service_role;
grant execute on function public.auto_match_fms_bank_reconciliation(uuid, integer)
  to authenticated, service_role;
grant execute on function public.match_fms_bank_statement_line(uuid, uuid, numeric, text)
  to authenticated, service_role;
grant execute on function public.unmatch_fms_bank_statement_line(uuid)
  to authenticated, service_role;
grant execute on function public.ignore_fms_bank_statement_line(uuid, text)
  to authenticated, service_role;
grant execute on function public.transition_fms_bank_reconciliation(uuid, text, text, integer)
  to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_types as (
  select * from (values
    ('b2000000-0000-4000-8000-000000000019'::uuid, '资金账户类型', 'fmsFundAccountType', 219, '银行、现金及数字钱包账户分类'),
    ('b2000000-0000-4000-8000-000000000020'::uuid, '资金账户状态', 'fmsFundAccountStatus', 220, '资金账户生命周期'),
    ('b2000000-0000-4000-8000-000000000021'::uuid, '资金流水方向', 'fmsFundLedgerDirection', 221, '资金流入或流出方向'),
    ('b2000000-0000-4000-8000-000000000022'::uuid, '资金流水来源', 'fmsFundLedgerSourceType', 222, '资金流水业务来源'),
    ('b2000000-0000-4000-8000-000000000023'::uuid, '资金调拨状态', 'fmsFundTransferStatus', 223, '资金调拨审批与执行生命周期'),
    ('b2000000-0000-4000-8000-000000000024'::uuid, '银行对账状态', 'fmsBankReconciliationStatus', 224, '银行对账批次生命周期'),
    ('b2000000-0000-4000-8000-000000000025'::uuid, '银行流水状态', 'fmsBankStatementLineStatus', 225, '银行流水匹配状态'),
    ('b2000000-0000-4000-8000-000000000026'::uuid, '银行匹配方式', 'fmsBankMatchType', 226, '银行流水自动或手工匹配方式')
  ) as t(id, name, code, sort, remark)
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
)
select t.id, t.name, t.code, '1', '624944977@qq.com', '624944977@qq.com',
  p.id, 'dictionary', t.sort, t.remark
from platform_tenant p cross join dictionary_types t
on conflict (id) do update set
  name = excluded.name,
  code = excluded.code,
  status = excluded.status,
  sort = excluded.sort,
  remark = excluded.remark,
  update_by = excluded.update_by,
  update_time = now();

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000181'::uuid, 'b2000000-0000-4000-8000-000000000019'::uuid, 'bank', '银行账户', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000182'::uuid, 'b2000000-0000-4000-8000-000000000019'::uuid, 'cash', '现金账户', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000183'::uuid, 'b2000000-0000-4000-8000-000000000019'::uuid, 'digital_wallet', '数字钱包', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000191'::uuid, 'b2000000-0000-4000-8000-000000000020'::uuid, 'active', '正常', 1, 'success'),
    ('c2000000-0000-4000-8000-000000000192'::uuid, 'b2000000-0000-4000-8000-000000000020'::uuid, 'frozen', '冻结', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000193'::uuid, 'b2000000-0000-4000-8000-000000000020'::uuid, 'closed', '已关闭', 3, 'info'),
    ('c2000000-0000-4000-8000-000000000201'::uuid, 'b2000000-0000-4000-8000-000000000021'::uuid, 'inflow', '流入', 1, 'success'),
    ('c2000000-0000-4000-8000-000000000202'::uuid, 'b2000000-0000-4000-8000-000000000021'::uuid, 'outflow', '流出', 2, 'danger'),
    ('c2000000-0000-4000-8000-000000000211'::uuid, 'b2000000-0000-4000-8000-000000000022'::uuid, 'customer_receipt', '客户收款', 1, 'success'),
    ('c2000000-0000-4000-8000-000000000212'::uuid, 'b2000000-0000-4000-8000-000000000022'::uuid, 'carrier_payment', '承运商付款', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000213'::uuid, 'b2000000-0000-4000-8000-000000000022'::uuid, 'expense_payment', '费用报销付款', 3, 'danger'),
    ('c2000000-0000-4000-8000-000000000214'::uuid, 'b2000000-0000-4000-8000-000000000022'::uuid, 'fund_transfer', '资金调拨', 4, 'primary'),
    ('c2000000-0000-4000-8000-000000000215'::uuid, 'b2000000-0000-4000-8000-000000000022'::uuid, 'manual_adjustment', '手工调整', 5, 'warning'),
    ('c2000000-0000-4000-8000-000000000216'::uuid, 'b2000000-0000-4000-8000-000000000022'::uuid, 'opening', '期初余额', 6, 'info'),
    ('c2000000-0000-4000-8000-000000000221'::uuid, 'b2000000-0000-4000-8000-000000000023'::uuid, 'draft', '草稿', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000222'::uuid, 'b2000000-0000-4000-8000-000000000023'::uuid, 'pending_review', '待审批', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000223'::uuid, 'b2000000-0000-4000-8000-000000000023'::uuid, 'approved', '已审批', 3, 'primary'),
    ('c2000000-0000-4000-8000-000000000224'::uuid, 'b2000000-0000-4000-8000-000000000023'::uuid, 'rejected', '已驳回', 4, 'danger'),
    ('c2000000-0000-4000-8000-000000000225'::uuid, 'b2000000-0000-4000-8000-000000000023'::uuid, 'completed', '已完成', 5, 'success'),
    ('c2000000-0000-4000-8000-000000000226'::uuid, 'b2000000-0000-4000-8000-000000000023'::uuid, 'reversed', '已冲销', 6, 'warning'),
    ('c2000000-0000-4000-8000-000000000231'::uuid, 'b2000000-0000-4000-8000-000000000024'::uuid, 'draft', '草稿', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000232'::uuid, 'b2000000-0000-4000-8000-000000000024'::uuid, 'reconciling', '对账中', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000233'::uuid, 'b2000000-0000-4000-8000-000000000024'::uuid, 'reconciled', '已完成', 3, 'success'),
    ('c2000000-0000-4000-8000-000000000234'::uuid, 'b2000000-0000-4000-8000-000000000024'::uuid, 'voided', '已作废', 4, 'info'),
    ('c2000000-0000-4000-8000-000000000241'::uuid, 'b2000000-0000-4000-8000-000000000025'::uuid, 'unmatched', '未匹配', 1, 'warning'),
    ('c2000000-0000-4000-8000-000000000242'::uuid, 'b2000000-0000-4000-8000-000000000025'::uuid, 'partial_matched', '部分匹配', 2, 'primary'),
    ('c2000000-0000-4000-8000-000000000243'::uuid, 'b2000000-0000-4000-8000-000000000025'::uuid, 'matched', '已匹配', 3, 'success'),
    ('c2000000-0000-4000-8000-000000000244'::uuid, 'b2000000-0000-4000-8000-000000000025'::uuid, 'ignored', '已忽略', 4, 'info'),
    ('c2000000-0000-4000-8000-000000000251'::uuid, 'b2000000-0000-4000-8000-000000000026'::uuid, 'automatic', '自动匹配', 1, 'success'),
    ('c2000000-0000-4000-8000-000000000252'::uuid, 'b2000000-0000-4000-8000-000000000026'::uuid, 'manual', '手工匹配', 2, 'primary')
  ) as i(id, type_id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type,
  create_by, update_by, tenant_id
)
select i.id, i.type_id, i.value, '1', i.value, i.label, i.sort, i.tag_type,
  '624944977@qq.com', '624944977@qq.com', p.id
from platform_tenant p cross join dictionary_items i
on conflict (id) do update set
  type_id = excluded.type_id,
  code = excluded.code,
  status = excluded.status,
  value = excluded.value,
  label = excluded.label,
  sort = excluded.sort,
  tag_type = excluded.tag_type,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_menu (
  id, parent_id, name, path, component, type, sort, meta, create_by, update_by
)
values
  (
    'a1000000-0000-4000-8000-000000000022'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'FinanceTreasury', 'treasury', '', 'folder', 4,
    jsonb_build_object('icon','ri:bank-line','title','资金管理','is_hide',false,
      'is_enable',true,'menu_type','folder','keep_alive',false),
    '624944977@qq.com','624944977@qq.com'
  ),
  (
    'a1000000-0000-4000-8000-000000000023'::uuid,
    'a1000000-0000-4000-8000-000000000022'::uuid,
    'FinanceFundAccount', 'fund-account', '/fms/fund-account/index', 'menu', 1,
    jsonb_build_object('icon','ri:bank-card-line','title','资金账户','is_hide',false,
      'is_enable',true,'menu_type','menu','keep_alive',true),
    '624944977@qq.com','624944977@qq.com'
  ),
  (
    'a1000000-0000-4000-8000-000000000024'::uuid,
    'a1000000-0000-4000-8000-000000000022'::uuid,
    'FinanceFundTransfer', 'fund-transfer', '/fms/fund-transfer/index', 'menu', 2,
    jsonb_build_object('icon','ri:swap-2-line','title','资金调拨','is_hide',false,
      'is_enable',true,'menu_type','menu','keep_alive',true),
    '624944977@qq.com','624944977@qq.com'
  ),
  (
    'a1000000-0000-4000-8000-000000000025'::uuid,
    'a1000000-0000-4000-8000-000000000022'::uuid,
    'FinanceBankReconciliation', 'bank-reconciliation', '/fms/bank-reconciliation/index', 'menu', 3,
    jsonb_build_object('icon','ri:file-search-line','title','银行对账','is_hide',false,
      'is_enable',true,'menu_type','menu','keep_alive',true),
    '624944977@qq.com','624944977@qq.com'
  ),
  (
    'a1000000-0000-4000-8000-000000000026'::uuid,
    'a1000000-0000-4000-8000-000000000022'::uuid,
    'FinanceFundJournal', 'fund-journal', '/fms/fund-journal/index', 'menu', 4,
    jsonb_build_object('icon','ri:book-2-line','title','资金日记账','is_hide',false,
      'is_enable',true,'menu_type','menu','keep_alive',true),
    '624944977@qq.com','624944977@qq.com'
  )
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  path = excluded.path,
  component = excluded.component,
  type = excluded.type,
  sort = excluded.sort,
  meta = excluded.meta,
  update_by = excluded.update_by,
  update_time = now();

with finance_roles as (
  select distinct role_id, tenant_id
  from public.sys_role_menu
  where menu_id = 'a1000000-0000-4000-8000-000000000001'::uuid
)
insert into public.sys_role_menu (
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select r.role_id, m.menu_id, r.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from finance_roles r
cross join (values
  ('a1000000-0000-4000-8000-000000000022'::uuid),
  ('a1000000-0000-4000-8000-000000000023'::uuid),
  ('a1000000-0000-4000-8000-000000000024'::uuid),
  ('a1000000-0000-4000-8000-000000000025'::uuid),
  ('a1000000-0000-4000-8000-000000000026'::uuid)
) as m(menu_id)
on conflict (role_id, menu_id) do nothing;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
)
insert into public.sys_document_number_scene (
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark, tenant_id
)
select * from (
  select 'fms.fund_transfer', '资金调拨单号', '调拨单号', 'business_document',
    'a1000000-0000-4000-8000-000000000024'::uuid, 'fms_fund_transfer', 'transfer_no',
    'ZJDB{YYYYMM}-{SEQ:4}', 'month', true, true, '资金调拨业务编号', p.id
  from platform_tenant p
  union all
  select 'fms.bank_reconciliation', '银行对账批次号', '对账批次号', 'business_document',
    'a1000000-0000-4000-8000-000000000025'::uuid, 'fms_bank_reconciliation_batch', 'batch_no',
    'YHDZ{YYYYMM}-{SEQ:4}', 'month', true, true, '银行对账批次编号', p.id
  from platform_tenant p
) s
on conflict (rule_key) do update set
  rule_name = excluded.rule_name,
  field_label = excluded.field_label,
  category = excluded.category,
  menu_id = excluded.menu_id,
  target_table = excluded.target_table,
  target_column = excluded.target_column,
  default_template = excluded.default_template,
  default_reset_cycle = excluded.default_reset_cycle,
  manual_required = excluded.manual_required,
  enabled = excluded.enabled,
  remark = excluded.remark,
  update_time = now();

insert into public.sys_document_number_rule (
  tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone,
  manual_required, builtin, enabled, remark, create_by, update_by
)
select
  t.id,
  s.rule_key,
  s.rule_name,
  s.category,
  s.target_table,
  s.target_column,
  true,
  s.default_template,
  s.default_reset_cycle,
  1,
  'Asia/Shanghai',
  s.manual_required,
  true,
  true,
  s.remark,
  'number-engine',
  'number-engine'
from public.sys_tenant t
cross join public.sys_document_number_scene s
where s.rule_key in ('fms.fund_transfer', 'fms.bank_reconciliation')
on conflict (tenant_id, rule_key) do nothing;

drop trigger if exists document_number_transfer_no on public.fms_fund_transfer;
create trigger document_number_transfer_no
before insert on public.fms_fund_transfer
for each row execute function app_private.trg_assign_configurable_number(
  'fms.fund_transfer', 'transfer_no'
);

drop trigger if exists document_number_batch_no on public.fms_bank_reconciliation_batch;
create trigger document_number_batch_no
before insert on public.fms_bank_reconciliation_batch
for each row execute function app_private.trg_assign_configurable_number(
  'fms.bank_reconciliation', 'batch_no'
);

commit;

;
