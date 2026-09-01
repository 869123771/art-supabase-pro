begin;

create table public.fms_voucher_number_counter (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  fiscal_year smallint not null,
  period_no smallint not null,
  voucher_type text not null,
  current_value bigint not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_voucher_counter_account_set_fkey foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_voucher_counter_period_check check (period_no between 1 and 12),
  constraint fms_voucher_counter_year_check check (fiscal_year between 1900 and 2999),
  constraint fms_voucher_counter_value_check check (current_value >= 0),
  constraint fms_voucher_counter_scope_key unique (account_set_id, fiscal_year, period_no, voucher_type)
);

create table public.fms_voucher (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  accounting_period_id uuid not null,
  voucher_no text not null,
  voucher_type text not null default 'general',
  voucher_date date not null,
  fiscal_year smallint not null,
  period_no smallint not null,
  status text not null default 'draft',
  source_type text not null default 'manual',
  source_id uuid,
  source_no text,
  summary text not null,
  attachments jsonb not null default '[]'::jsonb,
  total_debit numeric(20, 2) not null default 0,
  total_credit numeric(20, 2) not null default 0,
  line_count integer not null default 0,
  submitted_at timestamptz,
  submitted_by text,
  reviewed_at timestamptz,
  reviewed_by text,
  review_comment text,
  posted_at timestamptz,
  posted_by text,
  voided_at timestamptz,
  voided_by text,
  void_reason text,
  reversed_at timestamptz,
  reversed_by text,
  reversal_reason text,
  reversal_voucher_id uuid,
  version bigint not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_voucher_account_set_fkey foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_voucher_period_fkey foreign key (accounting_period_id, account_set_id, tenant_id)
    references public.fms_accounting_period(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_voucher_reversal_fkey foreign key (reversal_voucher_id)
    references public.fms_voucher(id) on delete restrict,
  constraint fms_voucher_no_not_blank check (btrim(voucher_no) <> ''),
  constraint fms_voucher_summary_not_blank check (btrim(summary) <> ''),
  constraint fms_voucher_type_check check (voucher_type in (
    'general', 'receipt', 'payment', 'transfer', 'adjustment', 'closing', 'reversal'
  )),
  constraint fms_voucher_status_check check (status in (
    'draft', 'pending_review', 'approved', 'rejected', 'posted', 'reversed', 'voided'
  )),
  constraint fms_voucher_source_check check (source_type in (
    'manual', 'customer_statement', 'carrier_statement', 'customer_receipt',
    'carrier_payment', 'invoice', 'expense_reimbursement', 'waybill_cost', 'system', 'reversal'
  )),
  constraint fms_voucher_source_pair_check check (
    (source_type = 'manual' and source_id is null) or source_type <> 'manual'
  ),
  constraint fms_voucher_attachments_array_check check (jsonb_typeof(attachments) = 'array'),
  constraint fms_voucher_amount_check check (total_debit >= 0 and total_credit >= 0),
  constraint fms_voucher_line_count_check check (line_count >= 0),
  constraint fms_voucher_version_check check (version > 0),
  constraint fms_voucher_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_voucher_scope_no_key unique (account_set_id, voucher_no)
);

create unique index fms_voucher_source_uidx
  on public.fms_voucher (account_set_id, source_type, source_id)
  where source_id is not null;
create index fms_voucher_list_idx
  on public.fms_voucher (tenant_id, account_set_id, voucher_date desc, voucher_no desc);
create index fms_voucher_period_status_idx
  on public.fms_voucher (account_set_id, accounting_period_id, status);
create index fms_voucher_source_lookup_idx
  on public.fms_voucher (tenant_id, source_type, source_id);

create table public.fms_voucher_line (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  voucher_id uuid not null,
  line_no smallint not null,
  summary text not null,
  subject_id uuid not null,
  subject_code_snapshot text not null,
  subject_name_snapshot text not null,
  auxiliary_values jsonb not null default '{}'::jsonb,
  currency_id uuid,
  currency_code_snapshot text,
  exchange_rate numeric(20, 10) not null default 1,
  original_amount numeric(20, 2) not null default 0,
  quantity numeric(20, 6) not null default 0,
  unit_name_snapshot text,
  debit_amount numeric(20, 2) not null default 0,
  credit_amount numeric(20, 2) not null default 0,
  source_line_type text,
  source_line_id uuid,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_voucher_line_voucher_fkey foreign key (voucher_id, account_set_id, tenant_id)
    references public.fms_voucher(id, account_set_id, tenant_id) on delete cascade,
  constraint fms_voucher_line_subject_fkey foreign key (subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_voucher_line_currency_fkey foreign key (currency_id, account_set_id, tenant_id)
    references public.fms_currency(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_voucher_line_number_check check (line_no between 1 and 9999),
  constraint fms_voucher_line_summary_check check (btrim(summary) <> ''),
  constraint fms_voucher_line_auxiliary_check check (jsonb_typeof(auxiliary_values) = 'object'),
  constraint fms_voucher_line_exchange_rate_check check (exchange_rate > 0),
  constraint fms_voucher_line_amount_check check (
    debit_amount >= 0 and credit_amount >= 0 and original_amount >= 0 and quantity >= 0
  ),
  constraint fms_voucher_line_direction_check check (
    (debit_amount > 0 and credit_amount = 0) or (credit_amount > 0 and debit_amount = 0)
  ),
  constraint fms_voucher_line_scope_key unique (voucher_id, line_no)
);

create index fms_voucher_line_subject_idx
  on public.fms_voucher_line (tenant_id, account_set_id, subject_id, voucher_id);
create index fms_voucher_line_currency_idx
  on public.fms_voucher_line (currency_id) where currency_id is not null;

create table public.fms_voucher_action (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  voucher_id uuid not null,
  action text not null,
  from_status text,
  to_status text,
  reason text,
  actor text not null,
  action_time timestamptz not null default now(),
  snapshot jsonb not null default '{}'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  constraint fms_voucher_action_voucher_fkey foreign key (voucher_id, account_set_id, tenant_id)
    references public.fms_voucher(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_voucher_action_check check (action in (
    'create', 'save', 'submit', 'approve', 'reject', 'post', 'void', 'reverse', 'reversal_create'
  )),
  constraint fms_voucher_action_snapshot_check check (jsonb_typeof(snapshot) = 'object')
);

create index fms_voucher_action_timeline_idx
  on public.fms_voucher_action (tenant_id, voucher_id, action_time, id);

create table public.fms_voucher_template (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  template_code text not null,
  template_name text not null,
  voucher_type text not null default 'general',
  summary text,
  is_enabled boolean not null default true,
  sort integer not null default 100,
  remark text,
  version bigint not null default 1,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_voucher_template_account_set_fkey foreign key (account_set_id, tenant_id)
    references public.fms_account_set(id, tenant_id) on delete restrict,
  constraint fms_voucher_template_code_check check (template_code ~ '^[A-Z0-9_-]{2,30}$'),
  constraint fms_voucher_template_name_check check (btrim(template_name) <> ''),
  constraint fms_voucher_template_type_check check (voucher_type in (
    'general', 'receipt', 'payment', 'transfer', 'adjustment', 'closing'
  )),
  constraint fms_voucher_template_sort_check check (sort between 0 and 9999),
  constraint fms_voucher_template_scope_key unique (account_set_id, template_code),
  constraint fms_voucher_template_id_scope_key unique (id, account_set_id, tenant_id)
);

create table public.fms_voucher_template_line (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  account_set_id uuid not null,
  template_id uuid not null,
  line_no smallint not null,
  summary text,
  subject_id uuid not null,
  entry_direction text not null,
  default_amount numeric(20, 2) not null default 0,
  auxiliary_values jsonb not null default '{}'::jsonb,
  currency_id uuid,
  exchange_rate numeric(20, 10) not null default 1,
  quantity numeric(20, 6) not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_voucher_template_line_template_fkey foreign key (template_id, account_set_id, tenant_id)
    references public.fms_voucher_template(id, account_set_id, tenant_id) on delete cascade,
  constraint fms_voucher_template_line_subject_fkey foreign key (subject_id, account_set_id, tenant_id)
    references public.fms_subject(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_voucher_template_line_currency_fkey foreign key (currency_id, account_set_id, tenant_id)
    references public.fms_currency(id, account_set_id, tenant_id) on delete restrict,
  constraint fms_voucher_template_line_number_check check (line_no between 1 and 9999),
  constraint fms_voucher_template_line_direction_check check (entry_direction in ('debit', 'credit')),
  constraint fms_voucher_template_line_amount_check check (
    default_amount >= 0 and exchange_rate > 0 and quantity >= 0
  ),
  constraint fms_voucher_template_line_auxiliary_check check (jsonb_typeof(auxiliary_values) = 'object'),
  constraint fms_voucher_template_line_scope_key unique (template_id, line_no)
);

create index fms_voucher_template_list_idx
  on public.fms_voucher_template (tenant_id, account_set_id, is_enabled, sort, template_code);
create index fms_voucher_template_line_subject_idx
  on public.fms_voucher_template_line (subject_id);
create index fms_voucher_template_line_currency_idx
  on public.fms_voucher_template_line (currency_id) where currency_id is not null;

create or replace function app_private.next_fms_voucher_no(
  p_tenant_id uuid,
  p_account_set_id uuid,
  p_fiscal_year smallint,
  p_period_no smallint,
  p_voucher_type text
)
returns text
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_sequence bigint;
  v_prefix text;
begin
  insert into public.fms_voucher_number_counter (
    tenant_id, account_set_id, fiscal_year, period_no, voucher_type, current_value
  ) values (p_tenant_id, p_account_set_id, p_fiscal_year, p_period_no, p_voucher_type, 1)
  on conflict (account_set_id, fiscal_year, period_no, voucher_type)
  do update set current_value = public.fms_voucher_number_counter.current_value + 1
  returning current_value into v_sequence;

  v_prefix := case p_voucher_type
    when 'receipt' then '收'
    when 'payment' then '付'
    when 'transfer' then '转'
    when 'adjustment' then '调'
    when 'closing' then '结'
    when 'reversal' then '冲'
    else '记'
  end;
  return format('%s-%s%s-%s', v_prefix, p_fiscal_year, lpad(p_period_no::text, 2, '0'), lpad(v_sequence::text, 6, '0'));
end;
$$;

create or replace function app_private.refresh_fms_voucher_totals(p_voucher_id uuid)
returns void
language sql
security invoker
set search_path = ''
as $$
  update public.fms_voucher v
  set total_debit = totals.debit,
      total_credit = totals.credit,
      line_count = totals.line_count
  from (
    select coalesce(sum(line.debit_amount), 0)::numeric(20, 2) as debit,
      coalesce(sum(line.credit_amount), 0)::numeric(20, 2) as credit,
      count(*)::integer as line_count
    from public.fms_voucher_line line
    where line.voucher_id = p_voucher_id
  ) totals
  where v.id = p_voucher_id
$$;

create or replace function app_private.guard_fms_voucher_header()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_period public.fms_accounting_period%rowtype;
begin
  if tg_op = 'DELETE' then
    if old.status <> 'draft' then
      raise exception using errcode = '23514', message = '仅草稿凭证允许删除';
    end if;
    return old;
  end if;

  select * into v_period
  from public.fms_accounting_period p
  where p.id = new.accounting_period_id
    and p.account_set_id = new.account_set_id
    and p.tenant_id = new.tenant_id
    and new.voucher_date between p.start_date and p.end_date;
  if not found then
    raise exception using errcode = '23503', message = '凭证日期不属于指定账套的会计期间';
  end if;
  new.fiscal_year := v_period.fiscal_year;
  new.period_no := v_period.period_no;
  new.voucher_no := btrim(new.voucher_no);
  new.summary := btrim(new.summary);

  if tg_op = 'UPDATE' then
    if old.status in ('posted', 'reversed', 'voided') and not (
      old.status = 'posted' and new.status = 'reversed'
      and new.reversal_voucher_id is not null
      and new.account_set_id = old.account_set_id
      and new.accounting_period_id = old.accounting_period_id
      and new.voucher_no = old.voucher_no
      and new.voucher_date = old.voucher_date
      and new.total_debit = old.total_debit
      and new.total_credit = old.total_credit
      and new.line_count = old.line_count
    ) then
      raise exception using errcode = '23514', message = '已过账、已冲销或已作废凭证不可修改';
    end if;
    if old.status not in ('draft', 'rejected') and (
      new.account_set_id <> old.account_set_id
      or new.accounting_period_id <> old.accounting_period_id
      or new.voucher_date <> old.voucher_date
      or new.voucher_type <> old.voucher_type
      or new.source_type <> old.source_type
      or new.source_id is distinct from old.source_id
    ) then
      raise exception using errcode = '23514', message = '凭证提交后不可变更核算范围、日期、类别或业务来源';
    end if;
    if new.status <> old.status and not (
      (old.status in ('draft', 'rejected') and new.status in ('pending_review', 'voided'))
      or (old.status = 'pending_review' and new.status in ('approved', 'rejected'))
      or (old.status = 'approved' and new.status in ('posted', 'voided'))
      or (old.status = 'posted' and new.status = 'reversed')
    ) then
      raise exception using errcode = '23514', message = '不支持当前凭证状态流转';
    end if;
    new.version := old.version + 1;
  end if;
  return new;
end;
$$;

create trigger trg_fms_voucher_header_guard
before insert or update or delete on public.fms_voucher
for each row execute function app_private.guard_fms_voucher_header();

create or replace function app_private.guard_fms_voucher_line()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_voucher public.fms_voucher%rowtype;
  v_subject public.fms_subject%rowtype;
  v_currency public.fms_currency%rowtype;
  v_amount numeric;
begin
  select * into v_voucher
  from public.fms_voucher v
  where v.id = case when tg_op = 'DELETE' then old.voucher_id else new.voucher_id end
  for update;
  if not found then
    raise exception using errcode = '23503', message = '所属凭证不存在';
  end if;
  if v_voucher.status not in ('draft', 'rejected') then
    raise exception using errcode = '23514', message = '仅草稿或已驳回凭证允许修改分录';
  end if;
  if tg_op = 'DELETE' then return old; end if;

  if new.account_set_id <> v_voucher.account_set_id or new.tenant_id <> v_voucher.tenant_id then
    raise exception using errcode = '23514', message = '凭证分录核算范围与凭证不一致';
  end if;
  select * into v_subject
  from public.fms_subject s
  where s.id = new.subject_id and s.account_set_id = new.account_set_id
    and s.tenant_id = new.tenant_id and s.is_enabled;
  if not found or exists (select 1 from public.fms_subject child where child.parent_id = new.subject_id) then
    raise exception using errcode = '23503', message = '凭证分录必须使用当前账套的启用末级科目';
  end if;
  new.subject_code_snapshot := v_subject.subject_code;
  new.subject_name_snapshot := v_subject.subject_name;
  new.unit_name_snapshot := v_subject.unit_name;

  if not v_subject.allow_quantity and new.quantity <> 0 then
    raise exception using errcode = '23514', message = '当前科目未启用数量核算';
  end if;
  if exists (
    select 1 from public.fms_subject_auxiliary_type config
    where config.subject_id = v_subject.id and config.is_required
      and nullif(new.auxiliary_values ->> config.auxiliary_type_id::text, '') is null
  ) then
    raise exception using errcode = '23502', message = '请完整填写科目要求的辅助核算项目';
  end if;
  if exists (
    select 1
    from jsonb_each_text(new.auxiliary_values) provided(type_id, item_id)
    left join public.fms_subject_auxiliary_type config
      on config.subject_id = v_subject.id and config.auxiliary_type_id = provided.type_id::uuid
    left join public.fms_auxiliary_item item
      on item.id = provided.item_id::uuid and item.auxiliary_type_id = provided.type_id::uuid
      and item.account_set_id = new.account_set_id and item.tenant_id = new.tenant_id and item.is_enabled
    where config.id is null or item.id is null
  ) then
    raise exception using errcode = '23503', message = '辅助核算维度或项目无效';
  end if;

  v_amount := greatest(new.debit_amount, new.credit_amount);
  if new.currency_id is null then
    if new.original_amount <> 0 or new.exchange_rate <> 1 then
      raise exception using errcode = '23514', message = '未选择外币时原币金额必须为零且汇率必须为一';
    end if;
    new.currency_code_snapshot := null;
  else
    if not v_subject.allow_foreign_currency then
      raise exception using errcode = '23514', message = '当前科目未启用外币核算';
    end if;
    select * into v_currency from public.fms_currency c
    where c.id = new.currency_id and c.account_set_id = new.account_set_id
      and c.tenant_id = new.tenant_id and c.is_enabled and not c.is_base;
    if not found then
      raise exception using errcode = '23503', message = '核算外币不存在、已停用或不是外币';
    end if;
    if new.original_amount <= 0 or abs(round(new.original_amount * new.exchange_rate, 2) - v_amount) > 0.01 then
      raise exception using errcode = '23514', message = '外币原币金额、汇率与本位币金额不一致';
    end if;
    new.currency_code_snapshot := v_currency.currency_code;
  end if;
  return new;
end;
$$;

create trigger trg_fms_voucher_line_guard
before insert or update or delete on public.fms_voucher_line
for each row execute function app_private.guard_fms_voucher_line();

create or replace function app_private.guard_fms_voucher_action()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op <> 'INSERT' then
    raise exception using errcode = '23514', message = '凭证操作日志为追加式审计记录，不可修改或删除';
  end if;
  return new;
end;
$$;

create trigger trg_fms_voucher_action_guard
before insert or update or delete on public.fms_voucher_action
for each row execute function app_private.guard_fms_voucher_action();

create or replace function app_private.assert_fms_voucher_ready(p_voucher_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_voucher public.fms_voucher%rowtype;
begin
  perform app_private.refresh_fms_voucher_totals(p_voucher_id);
  select * into v_voucher from public.fms_voucher where id = p_voucher_id;
  if v_voucher.line_count < 2 then
    raise exception using errcode = '23514', message = '凭证至少需要两条分录';
  end if;
  if v_voucher.total_debit <= 0 or v_voucher.total_debit <> v_voucher.total_credit then
    raise exception using errcode = '23514', message = '凭证借贷金额必须大于零且保持平衡';
  end if;
  if not exists (
    select 1 from public.fms_accounting_period p
    where p.id = v_voucher.accounting_period_id and p.status = 'open'
      and v_voucher.voucher_date between p.start_date and p.end_date
  ) then
    raise exception using errcode = '23514', message = '凭证所属会计期间未开放';
  end if;
  if exists (
    select 1 from public.fms_voucher_line line
    left join public.fms_subject subject on subject.id = line.subject_id and subject.is_enabled
    where line.voucher_id = p_voucher_id
      and (subject.id is null or exists (select 1 from public.fms_subject child where child.parent_id = line.subject_id))
  ) then
    raise exception using errcode = '23514', message = '凭证包含已停用、无效或非末级科目';
  end if;
end;
$$;

create or replace function public.save_fms_voucher(p_payload jsonb)
returns public.fms_voucher
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_voucher public.fms_voucher%rowtype;
  v_line jsonb;
  v_date date := coalesce(nullif(p_payload ->> 'voucherDate', '')::date, current_date);
  v_type text := coalesce(nullif(p_payload ->> 'voucherType', ''), 'general');
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'unknown');
  v_action text;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护会计凭证';
  end if;
  select * into v_account_set from public.fms_account_set
  where id = (p_payload ->> 'accountSetId')::uuid and status = 'active';
  if not found then
    raise exception using errcode = '23503', message = '账套不存在或未启用';
  end if;
  select * into v_period from public.fms_accounting_period
  where account_set_id = v_account_set.id and v_date between start_date and end_date;
  if not found then
    raise exception using errcode = '23503', message = '凭证日期没有对应会计期间';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'lines', '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = '凭证分录必须为数组';
  end if;

  if v_id is null then
    insert into public.fms_voucher (
      tenant_id, account_set_id, accounting_period_id, voucher_no, voucher_type,
      voucher_date, fiscal_year, period_no, status, source_type, source_id, source_no,
      summary, attachments
    ) values (
      v_account_set.tenant_id, v_account_set.id, v_period.id,
      app_private.next_fms_voucher_no(v_account_set.tenant_id, v_account_set.id, v_period.fiscal_year, v_period.period_no, v_type),
      v_type, v_date, v_period.fiscal_year, v_period.period_no, 'draft',
      coalesce(nullif(p_payload ->> 'sourceType', ''), 'manual'),
      nullif(p_payload ->> 'sourceId', '')::uuid, nullif(btrim(p_payload ->> 'sourceNo'), ''),
      btrim(p_payload ->> 'summary'), coalesce(p_payload -> 'attachments', '[]'::jsonb)
    ) returning * into v_voucher;
    v_action := 'create';
  else
    select * into v_voucher from public.fms_voucher
    where id = v_id and account_set_id = v_account_set.id for update;
    if not found then raise exception using errcode = 'P0002', message = '凭证不存在'; end if;
    if v_voucher.status not in ('draft', 'rejected') then
      raise exception using errcode = '23514', message = '仅草稿或已驳回凭证允许修改';
    end if;
    update public.fms_voucher set
      accounting_period_id = v_period.id, voucher_type = v_type, voucher_date = v_date,
      fiscal_year = v_period.fiscal_year, period_no = v_period.period_no,
      source_type = coalesce(nullif(p_payload ->> 'sourceType', ''), 'manual'),
      source_id = nullif(p_payload ->> 'sourceId', '')::uuid,
      source_no = nullif(btrim(p_payload ->> 'sourceNo'), ''),
      summary = btrim(p_payload ->> 'summary'),
      attachments = coalesce(p_payload -> 'attachments', '[]'::jsonb)
    where id = v_id returning * into v_voucher;
    delete from public.fms_voucher_line where voucher_id = v_id;
    v_action := 'save';
  end if;

  for v_line in select value from jsonb_array_elements(coalesce(p_payload -> 'lines', '[]'::jsonb)) loop
    insert into public.fms_voucher_line (
      tenant_id, account_set_id, voucher_id, line_no, summary, subject_id,
      subject_code_snapshot, subject_name_snapshot, auxiliary_values, currency_id,
      exchange_rate, original_amount, quantity, debit_amount, credit_amount,
      source_line_type, source_line_id
    ) values (
      v_voucher.tenant_id, v_voucher.account_set_id, v_voucher.id,
      coalesce(nullif(v_line ->> 'lineNo', '')::smallint, 1),
      btrim(coalesce(nullif(v_line ->> 'summary', ''), v_voucher.summary)),
      (v_line ->> 'subjectId')::uuid, '', '',
      coalesce(v_line -> 'auxiliaryValues', '{}'::jsonb),
      nullif(v_line ->> 'currencyId', '')::uuid,
      coalesce(nullif(v_line ->> 'exchangeRate', '')::numeric, 1),
      coalesce(nullif(v_line ->> 'originalAmount', '')::numeric, 0),
      coalesce(nullif(v_line ->> 'quantity', '')::numeric, 0),
      coalesce(nullif(v_line ->> 'debitAmount', '')::numeric, 0),
      coalesce(nullif(v_line ->> 'creditAmount', '')::numeric, 0),
      nullif(v_line ->> 'sourceLineType', ''), nullif(v_line ->> 'sourceLineId', '')::uuid
    );
  end loop;
  perform app_private.refresh_fms_voucher_totals(v_voucher.id);
  select * into v_voucher from public.fms_voucher where id = v_voucher.id;
  insert into public.fms_voucher_action (
    tenant_id, account_set_id, voucher_id, action, from_status, to_status, actor, snapshot
  ) values (
    v_voucher.tenant_id, v_voucher.account_set_id, v_voucher.id, v_action,
    v_voucher.status, v_voucher.status, v_actor,
    jsonb_build_object('version', v_voucher.version, 'lineCount', v_voucher.line_count,
      'totalDebit', v_voucher.total_debit, 'totalCredit', v_voucher.total_credit)
  );
  return v_voucher;
end;
$$;

create or replace function public.transition_fms_voucher(
  p_voucher_id uuid,
  p_action text,
  p_reason text default null,
  p_action_date date default null
)
returns public.fms_voucher
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_voucher public.fms_voucher%rowtype;
  v_result public.fms_voucher%rowtype;
  v_reversal public.fms_voucher%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_from_status text;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'unknown');
  v_date date;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行凭证审核与过账操作';
  end if;
  select * into v_voucher from public.fms_voucher where id = p_voucher_id for update;
  if not found then raise exception using errcode = 'P0002', message = '凭证不存在'; end if;
  v_from_status := v_voucher.status;

  if p_action = 'submit' then
    if v_voucher.status not in ('draft', 'rejected') then raise exception using errcode = '23514', message = '当前凭证不可提交'; end if;
    perform app_private.assert_fms_voucher_ready(v_voucher.id);
    update public.fms_voucher set status = 'pending_review', submitted_at = now(), submitted_by = v_actor,
      review_comment = null where id = v_voucher.id returning * into v_result;
  elsif p_action = 'approve' then
    if v_voucher.status <> 'pending_review' then raise exception using errcode = '23514', message = '仅待审核凭证可审核通过'; end if;
    update public.fms_voucher set status = 'approved', reviewed_at = now(), reviewed_by = v_actor,
      review_comment = nullif(btrim(p_reason), '') where id = v_voucher.id returning * into v_result;
  elsif p_action = 'reject' then
    if v_voucher.status <> 'pending_review' then raise exception using errcode = '23514', message = '仅待审核凭证可驳回'; end if;
    if nullif(btrim(p_reason), '') is null then raise exception using errcode = '23502', message = '驳回必须填写原因'; end if;
    update public.fms_voucher set status = 'rejected', reviewed_at = now(), reviewed_by = v_actor,
      review_comment = btrim(p_reason) where id = v_voucher.id returning * into v_result;
  elsif p_action = 'post' then
    if v_voucher.status <> 'approved' then raise exception using errcode = '23514', message = '仅已审核凭证可过账'; end if;
    perform app_private.assert_fms_voucher_ready(v_voucher.id);
    update public.fms_voucher set status = 'posted', posted_at = now(), posted_by = v_actor
    where id = v_voucher.id returning * into v_result;
  elsif p_action = 'void' then
    if v_voucher.status not in ('draft', 'rejected', 'approved') then raise exception using errcode = '23514', message = '当前凭证不可作废'; end if;
    if nullif(btrim(p_reason), '') is null then raise exception using errcode = '23502', message = '作废必须填写原因'; end if;
    update public.fms_voucher set status = 'voided', voided_at = now(), voided_by = v_actor,
      void_reason = btrim(p_reason) where id = v_voucher.id returning * into v_result;
  elsif p_action = 'reverse' then
    if v_voucher.status <> 'posted' then raise exception using errcode = '23514', message = '仅已过账凭证可冲销'; end if;
    if nullif(btrim(p_reason), '') is null then raise exception using errcode = '23502', message = '冲销必须填写原因'; end if;
    v_date := coalesce(p_action_date, current_date);
    select * into v_period from public.fms_accounting_period
    where account_set_id = v_voucher.account_set_id and status = 'open'
      and v_date between start_date and end_date;
    if not found then raise exception using errcode = '23514', message = '冲销日期没有开放的会计期间'; end if;
    insert into public.fms_voucher (
      tenant_id, account_set_id, accounting_period_id, voucher_no, voucher_type,
      voucher_date, fiscal_year, period_no, status, source_type, source_id, source_no,
      summary, submitted_at, submitted_by, reviewed_at, reviewed_by, posted_at, posted_by
    ) values (
      v_voucher.tenant_id, v_voucher.account_set_id, v_period.id,
      app_private.next_fms_voucher_no(v_voucher.tenant_id, v_voucher.account_set_id, v_period.fiscal_year, v_period.period_no, 'reversal'),
      'reversal', v_date, v_period.fiscal_year, v_period.period_no, 'draft', 'reversal',
      v_voucher.id, v_voucher.voucher_no, '冲销：' || v_voucher.summary,
      now(), v_actor, now(), v_actor, now(), v_actor
    ) returning * into v_reversal;
    insert into public.fms_voucher_line (
      tenant_id, account_set_id, voucher_id, line_no, summary, subject_id,
      subject_code_snapshot, subject_name_snapshot, auxiliary_values, currency_id,
      currency_code_snapshot, exchange_rate, original_amount, quantity, unit_name_snapshot,
      debit_amount, credit_amount, source_line_type, source_line_id
    ) select
      tenant_id, account_set_id, v_reversal.id, line_no, '冲销：' || summary, subject_id,
      subject_code_snapshot, subject_name_snapshot, auxiliary_values, currency_id,
      currency_code_snapshot, exchange_rate, original_amount, quantity, unit_name_snapshot,
      credit_amount, debit_amount, 'voucher_line', id
    from public.fms_voucher_line where voucher_id = v_voucher.id order by line_no;
    perform app_private.refresh_fms_voucher_totals(v_reversal.id);
    update public.fms_voucher set status = 'pending_review' where id = v_reversal.id;
    update public.fms_voucher set status = 'approved' where id = v_reversal.id;
    update public.fms_voucher set status = 'posted' where id = v_reversal.id returning * into v_reversal;
    update public.fms_voucher set status = 'reversed', reversed_at = now(), reversed_by = v_actor,
      reversal_reason = btrim(p_reason), reversal_voucher_id = v_reversal.id
    where id = v_voucher.id returning * into v_result;
    insert into public.fms_voucher_action (
      tenant_id, account_set_id, voucher_id, action, from_status, to_status, reason, actor, snapshot
    ) values (
      v_reversal.tenant_id, v_reversal.account_set_id, v_reversal.id, 'reversal_create', 'draft', 'posted',
      btrim(p_reason), v_actor, jsonb_build_object('originalVoucherId', v_voucher.id, 'originalVoucherNo', v_voucher.voucher_no)
    );
  else
    raise exception using errcode = '22023', message = '不支持的凭证操作';
  end if;

  insert into public.fms_voucher_action (
    tenant_id, account_set_id, voucher_id, action, from_status, to_status, reason, actor, snapshot
  ) values (
    v_result.tenant_id, v_result.account_set_id, v_result.id, p_action,
    v_from_status, v_result.status, nullif(btrim(p_reason), ''), v_actor,
    jsonb_build_object('version', v_result.version, 'voucherNo', v_result.voucher_no)
  );
  return v_result;
end;
$$;

create or replace function public.fms_voucher_summary(p_account_set_id uuid)
returns table (
  account_set_id uuid,
  draft_count bigint,
  pending_review_count bigint,
  approved_count bigint,
  posted_count bigint,
  reversed_count bigint,
  current_period_posted_amount numeric
)
language sql
stable
security invoker
set search_path = ''
as $$
  select a.id,
    count(v.id) filter (where v.status in ('draft', 'rejected')),
    count(v.id) filter (where v.status = 'pending_review'),
    count(v.id) filter (where v.status = 'approved'),
    count(v.id) filter (where v.status = 'posted'),
    count(v.id) filter (where v.status = 'reversed'),
    coalesce(sum(v.total_debit) filter (
      where v.status in ('posted', 'reversed') and current_date between p.start_date and p.end_date
    ), 0)
  from public.fms_account_set a
  left join public.fms_voucher v on v.account_set_id = a.id
  left join public.fms_accounting_period p on p.id = v.accounting_period_id
  where a.id = p_account_set_id
  group by a.id
$$;

create or replace function public.save_fms_voucher_template(p_payload jsonb)
returns public.fms_voucher_template
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_template public.fms_voucher_template%rowtype;
  v_line jsonb;
  v_subject public.fms_subject%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护凭证模板';
  end if;
  select * into v_account_set from public.fms_account_set where id = (p_payload ->> 'accountSetId')::uuid;
  if not found then raise exception using errcode = '23503', message = '账套不存在'; end if;
  if v_id is null then
    insert into public.fms_voucher_template (
      tenant_id, account_set_id, template_code, template_name, voucher_type,
      summary, is_enabled, sort, remark
    ) values (
      v_account_set.tenant_id, v_account_set.id, upper(btrim(p_payload ->> 'templateCode')),
      btrim(p_payload ->> 'templateName'), coalesce(nullif(p_payload ->> 'voucherType', ''), 'general'),
      nullif(btrim(p_payload ->> 'summary'), ''), coalesce((p_payload ->> 'isEnabled')::boolean, true),
      coalesce(nullif(p_payload ->> 'sort', '')::integer, 100), nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_template;
  else
    update public.fms_voucher_template set
      template_code = upper(btrim(p_payload ->> 'templateCode')),
      template_name = btrim(p_payload ->> 'templateName'),
      voucher_type = coalesce(nullif(p_payload ->> 'voucherType', ''), voucher_type),
      summary = nullif(btrim(p_payload ->> 'summary'), ''),
      is_enabled = coalesce((p_payload ->> 'isEnabled')::boolean, is_enabled),
      sort = coalesce(nullif(p_payload ->> 'sort', '')::integer, sort),
      remark = nullif(btrim(p_payload ->> 'remark'), ''), version = version + 1
    where id = v_id and account_set_id = v_account_set.id returning * into v_template;
    if not found then raise exception using errcode = 'P0002', message = '凭证模板不存在'; end if;
    delete from public.fms_voucher_template_line where template_id = v_template.id;
  end if;

  for v_line in select value from jsonb_array_elements(coalesce(p_payload -> 'lines', '[]'::jsonb)) loop
    select * into v_subject from public.fms_subject
    where id = (v_line ->> 'subjectId')::uuid and account_set_id = v_template.account_set_id and is_enabled;
    if not found or exists (select 1 from public.fms_subject child where child.parent_id = v_subject.id) then
      raise exception using errcode = '23503', message = '模板分录必须使用启用末级科目';
    end if;
    insert into public.fms_voucher_template_line (
      tenant_id, account_set_id, template_id, line_no, summary, subject_id,
      entry_direction, default_amount, auxiliary_values, currency_id, exchange_rate, quantity
    ) values (
      v_template.tenant_id, v_template.account_set_id, v_template.id,
      coalesce(nullif(v_line ->> 'lineNo', '')::smallint, 1), nullif(btrim(v_line ->> 'summary'), ''),
      v_subject.id, v_line ->> 'entryDirection', coalesce(nullif(v_line ->> 'defaultAmount', '')::numeric, 0),
      coalesce(v_line -> 'auxiliaryValues', '{}'::jsonb), nullif(v_line ->> 'currencyId', '')::uuid,
      coalesce(nullif(v_line ->> 'exchangeRate', '')::numeric, 1),
      coalesce(nullif(v_line ->> 'quantity', '')::numeric, 0)
    );
  end loop;
  if not exists (select 1 from public.fms_voucher_template_line where template_id = v_template.id) then
    raise exception using errcode = '23514', message = '凭证模板至少需要一条分录';
  end if;
  return v_template;
end;
$$;

create or replace function public.delete_fms_voucher_template(p_template_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可删除凭证模板';
  end if;
  delete from public.fms_voucher_template where id = p_template_id;
  if not found then raise exception using errcode = 'P0002', message = '凭证模板不存在'; end if;
end;
$$;

create or replace function app_private.guard_fms_accounting_usage()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_table_name = 'fms_account_set' then
    if new.base_currency_code is distinct from old.base_currency_code
      and exists (select 1 from public.fms_voucher v where v.account_set_id = old.id) then
      raise exception using errcode = '23514', message = '账套已有凭证，不可变更本位币';
    end if;
  elsif tg_table_name = 'fms_subject' then
    if exists (select 1 from public.fms_voucher_line line where line.subject_id = old.id)
      and (new.parent_id is distinct from old.parent_id
        or new.subject_code <> old.subject_code
        or new.category <> old.category
        or new.balance_direction <> old.balance_direction
        or new.allow_quantity <> old.allow_quantity
        or new.allow_foreign_currency <> old.allow_foreign_currency) then
      raise exception using errcode = '23514', message = '科目已有凭证分录，不可变更编码、层级或核心核算属性';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_fms_account_set_accounting_usage
before update on public.fms_account_set
for each row execute function app_private.guard_fms_accounting_usage();
create trigger trg_fms_subject_accounting_usage
before update on public.fms_subject
for each row execute function app_private.guard_fms_accounting_usage();

create or replace function app_private.guard_fms_period_vouchers()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status in ('closing', 'closed') and old.status is distinct from new.status
    and exists (
      select 1 from public.fms_voucher v
      where v.accounting_period_id = old.id
        and v.status in ('draft', 'pending_review', 'approved', 'rejected')
    ) then
    raise exception using errcode = '23514', message = '会计期间仍有未过账凭证，不能进入结账或关闭状态';
  end if;
  return new;
end;
$$;

create trigger trg_fms_period_voucher_guard
before update of status on public.fms_accounting_period
for each row execute function app_private.guard_fms_period_vouchers();

create or replace function app_private.guard_fms_subject_auxiliary_write()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_subject_id uuid;
begin
  v_subject_id := case when tg_op = 'DELETE' then old.subject_id else new.subject_id end;
  if exists (select 1 from public.fms_opening_balance b where b.subject_id = v_subject_id)
    or exists (select 1 from public.fms_voucher_line line where line.subject_id = v_subject_id) then
    raise exception using errcode = '23514', message = '科目已有期初余额或凭证分录，不能变更辅助核算配置';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fms_voucher_number_counter', 'fms_voucher', 'fms_voucher_line',
    'fms_voucher_template', 'fms_voucher_template_line'
  ] loop
    execute format('create trigger %I before insert on public.%I for each row execute function public.trg_set_create_time_and_by(''true'', ''true'')', v_table || '_create_audit', v_table);
    execute format('create trigger %I before update on public.%I for each row execute function public.trg_set_update_time_and_by()', v_table || '_update_audit', v_table);
    execute format('alter table public.%I enable row level security', v_table);
    execute format('create policy %I on public.%I for select to authenticated using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))', v_table || '_tenant_select', v_table);
    execute format('create policy %I on public.%I for insert to authenticated with check ((select app_private.is_platform_super()))', v_table || '_platform_insert', v_table);
    execute format('create policy %I on public.%I for update to authenticated using ((select app_private.is_platform_super())) with check ((select app_private.is_platform_super()))', v_table || '_platform_update', v_table);
    execute format('create policy %I on public.%I for delete to authenticated using ((select app_private.is_platform_super()))', v_table || '_platform_delete', v_table);
    execute format('grant select, insert, update, delete on public.%I to authenticated', v_table);
    execute format('grant all on public.%I to service_role', v_table);
  end loop;
end;
$$;

alter table public.fms_voucher_action enable row level security;
create policy fms_voucher_action_tenant_select on public.fms_voucher_action
  for select to authenticated using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()));
create policy fms_voucher_action_platform_insert on public.fms_voucher_action
  for insert to authenticated with check ((select app_private.is_platform_super()));
grant select, insert on public.fms_voucher_action to authenticated;
grant all on public.fms_voucher_action to service_role;

revoke all on function app_private.next_fms_voucher_no(uuid, uuid, smallint, smallint, text) from public;
revoke all on function app_private.refresh_fms_voucher_totals(uuid) from public;
revoke all on function app_private.guard_fms_voucher_header() from public;
revoke all on function app_private.guard_fms_voucher_line() from public;
revoke all on function app_private.guard_fms_voucher_action() from public;
revoke all on function app_private.assert_fms_voucher_ready(uuid) from public;
revoke all on function app_private.guard_fms_accounting_usage() from public;
revoke all on function app_private.guard_fms_period_vouchers() from public;
revoke execute on function public.save_fms_voucher(jsonb) from public, anon;
revoke execute on function public.transition_fms_voucher(uuid, text, text, date) from public, anon;
revoke execute on function public.fms_voucher_summary(uuid) from public, anon;
revoke execute on function public.save_fms_voucher_template(jsonb) from public, anon;
revoke execute on function public.delete_fms_voucher_template(uuid) from public, anon;
grant execute on function public.save_fms_voucher(jsonb) to authenticated, service_role;
grant execute on function public.transition_fms_voucher(uuid, text, text, date) to authenticated, service_role;
grant execute on function public.fms_voucher_summary(uuid) to authenticated, service_role;
grant execute on function public.save_fms_voucher_template(jsonb) to authenticated, service_role;
grant execute on function public.delete_fms_voucher_template(uuid) to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, tenant_id, node_type, sort, remark
)
select item.id, item.name, item.code, '1', '624944977@qq.com', '624944977@qq.com',
  platform_tenant.id, 'dictionary', item.sort, item.remark
from platform_tenant
cross join (values
  ('b2000000-0000-4000-8000-000000000010'::uuid, '凭证状态', 'fmsVoucherStatus', 210, '会计凭证生命周期'),
  ('b2000000-0000-4000-8000-000000000011'::uuid, '凭证类型', 'fmsVoucherType', 211, '会计凭证分类'),
  ('b2000000-0000-4000-8000-000000000012'::uuid, '凭证来源', 'fmsVoucherSourceType', 212, '会计凭证业务来源')
) as item(id, name, code, sort, remark)
on conflict (id) do update set
  name = excluded.name, code = excluded.code, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type = 'platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000071'::uuid, 'b2000000-0000-4000-8000-000000000010'::uuid, 'draft', '草稿', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000072'::uuid, 'b2000000-0000-4000-8000-000000000010'::uuid, 'pending_review', '待审核', 2, 'warning'),
    ('c2000000-0000-4000-8000-000000000073'::uuid, 'b2000000-0000-4000-8000-000000000010'::uuid, 'approved', '已审核', 3, 'primary'),
    ('c2000000-0000-4000-8000-000000000074'::uuid, 'b2000000-0000-4000-8000-000000000010'::uuid, 'rejected', '已驳回', 4, 'danger'),
    ('c2000000-0000-4000-8000-000000000075'::uuid, 'b2000000-0000-4000-8000-000000000010'::uuid, 'posted', '已过账', 5, 'success'),
    ('c2000000-0000-4000-8000-000000000076'::uuid, 'b2000000-0000-4000-8000-000000000010'::uuid, 'reversed', '已冲销', 6, 'warning'),
    ('c2000000-0000-4000-8000-000000000077'::uuid, 'b2000000-0000-4000-8000-000000000010'::uuid, 'voided', '已作废', 7, 'info'),
    ('c2000000-0000-4000-8000-000000000081'::uuid, 'b2000000-0000-4000-8000-000000000011'::uuid, 'general', '记账凭证', 1, 'primary'),
    ('c2000000-0000-4000-8000-000000000082'::uuid, 'b2000000-0000-4000-8000-000000000011'::uuid, 'receipt', '收款凭证', 2, 'success'),
    ('c2000000-0000-4000-8000-000000000083'::uuid, 'b2000000-0000-4000-8000-000000000011'::uuid, 'payment', '付款凭证', 3, 'warning'),
    ('c2000000-0000-4000-8000-000000000084'::uuid, 'b2000000-0000-4000-8000-000000000011'::uuid, 'transfer', '转账凭证', 4, 'info'),
    ('c2000000-0000-4000-8000-000000000085'::uuid, 'b2000000-0000-4000-8000-000000000011'::uuid, 'adjustment', '调整凭证', 5, 'danger'),
    ('c2000000-0000-4000-8000-000000000086'::uuid, 'b2000000-0000-4000-8000-000000000011'::uuid, 'closing', '结转凭证', 6, 'warning'),
    ('c2000000-0000-4000-8000-000000000087'::uuid, 'b2000000-0000-4000-8000-000000000011'::uuid, 'reversal', '冲销凭证', 7, 'info'),
    ('c2000000-0000-4000-8000-000000000091'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'manual', '手工录入', 1, 'info'),
    ('c2000000-0000-4000-8000-000000000092'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'customer_statement', '客户对账单', 2, 'primary'),
    ('c2000000-0000-4000-8000-000000000093'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'carrier_statement', '承运商对账单', 3, 'success'),
    ('c2000000-0000-4000-8000-000000000094'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'customer_receipt', '客户收款', 4, 'success'),
    ('c2000000-0000-4000-8000-000000000095'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'carrier_payment', '承运商付款', 5, 'warning'),
    ('c2000000-0000-4000-8000-000000000096'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'invoice', '发票', 6, 'primary'),
    ('c2000000-0000-4000-8000-000000000097'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'expense_reimbursement', '费用报销', 7, 'danger'),
    ('c2000000-0000-4000-8000-000000000098'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'waybill_cost', '运单费用', 8, 'warning'),
    ('c2000000-0000-4000-8000-000000000099'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'system', '系统生成', 9, 'info'),
    ('c2000000-0000-4000-8000-000000000100'::uuid, 'b2000000-0000-4000-8000-000000000012'::uuid, 'reversal', '冲销生成', 10, 'info')
  ) as values_table(id, type_id, value, label, sort, tag_type)
)
insert into public.sys_dictionary (
  id, type_id, code, status, value, label, sort, tag_type, create_by, update_by, tenant_id
)
select item.id, item.type_id, item.value, '1', item.value, item.label, item.sort, item.tag_type,
  '624944977@qq.com', '624944977@qq.com', platform_tenant.id
from platform_tenant cross join dictionary_items item
on conflict (id) do update set
  type_id = excluded.type_id, code = excluded.code, status = excluded.status,
  value = excluded.value, label = excluded.label, sort = excluded.sort,
  tag_type = excluded.tag_type, update_by = excluded.update_by, update_time = now();

insert into public.sys_menu (
  id, parent_id, name, path, component, type, sort, meta, create_by, update_by
)
values
  (
    'a1000000-0000-4000-8000-000000000017'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'FinanceVoucherCenter', 'voucher-center', '/fms/voucher-center', 'menu', 18,
    jsonb_build_object('icon', 'ri:file-list-3-line', 'title', '凭证中心', 'is_enable', true, 'keep_alive', true),
    '624944977@qq.com', '624944977@qq.com'
  ),
  (
    'a1000000-0000-4000-8000-000000000018'::uuid,
    'a1000000-0000-4000-8000-000000000001'::uuid,
    'FinanceVoucherTemplate', 'voucher-template', '/fms/voucher-template', 'menu', 19,
    jsonb_build_object('icon', 'ri:file-copy-2-line', 'title', '凭证模板', 'is_enable', true, 'keep_alive', true),
    '624944977@qq.com', '624944977@qq.com'
  )
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, path = excluded.path,
  component = excluded.component, type = excluded.type, sort = excluded.sort,
  meta = excluded.meta, update_by = excluded.update_by, update_time = now();

insert into public.sys_role_menu (role_id, menu_id, tenant_id, permission, create_by, update_by)
select rm.role_id, menu.id, rm.tenant_id, '{}'::jsonb, '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu rm
cross join (values
  ('a1000000-0000-4000-8000-000000000017'::uuid),
  ('a1000000-0000-4000-8000-000000000018'::uuid)
) as menu(id)
where rm.menu_id = 'a1000000-0000-4000-8000-000000000001'::uuid
on conflict (role_id, menu_id) do nothing;

commit;

;
