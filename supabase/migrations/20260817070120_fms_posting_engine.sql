begin;

create table if not exists public.fms_posting_rule (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  account_set_id uuid not null,
  rule_code text not null,
  rule_name text not null,
  source_type text not null,
  event_code text not null,
  voucher_type text not null default 'general',
  submission_mode text not null default 'pending_review',
  match_conditions jsonb not null default '{}'::jsonb,
  priority integer not null default 100,
  effective_from date,
  effective_to date,
  is_enabled boolean not null default true,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_posting_rule_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set (id, tenant_id) on delete restrict,
  constraint fms_posting_rule_scope_key unique (account_set_id, rule_code),
  constraint fms_posting_rule_id_scope_key unique (id, account_set_id, tenant_id),
  constraint fms_posting_rule_code_check check (rule_code ~ '^[A-Z0-9_-]{2,40}$'),
  constraint fms_posting_rule_name_check check (btrim(rule_name) <> ''),
  constraint fms_posting_rule_source_check check (
    source_type in (
      'customer_statement', 'carrier_statement', 'customer_receipt', 'carrier_payment',
      'invoice', 'expense_reimbursement', 'waybill_cost', 'system'
    )
  ),
  constraint fms_posting_rule_event_check check (btrim(event_code) <> ''),
  constraint fms_posting_rule_voucher_type_check check (
    voucher_type in ('general', 'receipt', 'payment', 'transfer', 'adjustment', 'closing')
  ),
  constraint fms_posting_rule_submission_mode_check check (
    submission_mode in ('draft', 'pending_review')
  ),
  constraint fms_posting_rule_conditions_check check (jsonb_typeof(match_conditions) = 'object'),
  constraint fms_posting_rule_effective_range_check check (
    effective_from is null or effective_to is null or effective_from <= effective_to
  )
);

create table if not exists public.fms_posting_rule_line (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  account_set_id uuid not null,
  rule_id uuid not null references public.fms_posting_rule (id) on delete cascade,
  line_no smallint not null,
  direction text not null,
  amount_key text not null,
  amount_multiplier numeric(18, 6) not null default 1,
  subject_id uuid not null,
  summary text,
  auxiliary_bindings jsonb not null default '{}'::jsonb,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_posting_rule_line_scope_key unique (rule_id, line_no),
  constraint fms_posting_rule_line_rule_scope_fkey
    foreign key (rule_id, account_set_id, tenant_id)
    references public.fms_posting_rule (id, account_set_id, tenant_id) on delete cascade,
  constraint fms_posting_rule_line_subject_scope_fkey
    foreign key (subject_id, account_set_id, tenant_id)
    references public.fms_subject (id, account_set_id, tenant_id) on delete restrict,
  constraint fms_posting_rule_line_no_check check (line_no > 0),
  constraint fms_posting_rule_line_direction_check check (direction in ('debit', 'credit')),
  constraint fms_posting_rule_line_amount_key_check check (
    amount_key in ('gross_amount', 'net_amount', 'tax_amount')
  ),
  constraint fms_posting_rule_line_multiplier_check check (amount_multiplier > 0),
  constraint fms_posting_rule_line_bindings_check check (jsonb_typeof(auxiliary_bindings) = 'object')
);

create table if not exists public.fms_posting_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  account_set_id uuid,
  source_type text not null,
  event_code text not null,
  source_id uuid not null,
  source_no text,
  event_date date not null,
  summary text not null,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  rule_id uuid references public.fms_posting_rule (id) on delete set null,
  origin_voucher_id uuid references public.fms_voucher (id) on delete set null,
  voucher_id uuid references public.fms_voucher (id) on delete set null,
  attempt_count integer not null default 0,
  last_error text,
  processed_at timestamptz,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint fms_posting_event_account_set_fkey
    foreign key (account_set_id, tenant_id)
    references public.fms_account_set (id, tenant_id) on delete restrict,
  constraint fms_posting_event_source_key unique (tenant_id, source_type, event_code, source_id),
  constraint fms_posting_event_source_check check (
    source_type in (
      'customer_statement', 'carrier_statement', 'customer_receipt', 'carrier_payment',
      'invoice', 'expense_reimbursement', 'waybill_cost', 'system'
    )
  ),
  constraint fms_posting_event_status_check check (
    status in (
      'pending', 'processing', 'generated', 'pending_configuration', 'failed',
      'reversed', 'ignored'
    )
  ),
  constraint fms_posting_event_payload_check check (jsonb_typeof(payload) = 'object'),
  constraint fms_posting_event_attempt_check check (attempt_count >= 0)
);

create index if not exists fms_posting_rule_list_idx
  on public.fms_posting_rule (tenant_id, account_set_id, source_type, event_code, is_enabled, priority);
create index if not exists fms_posting_rule_line_subject_idx
  on public.fms_posting_rule_line (subject_id);
create index if not exists fms_posting_event_monitor_idx
  on public.fms_posting_event (tenant_id, status, event_date desc, create_time desc);
create index if not exists fms_posting_event_account_set_idx
  on public.fms_posting_event (account_set_id, status, event_date desc)
  where account_set_id is not null;
create index if not exists fms_posting_event_rule_idx
  on public.fms_posting_event (rule_id)
  where rule_id is not null;
create index if not exists fms_posting_event_origin_voucher_idx
  on public.fms_posting_event (origin_voucher_id)
  where origin_voucher_id is not null;
create index if not exists fms_posting_event_voucher_idx
  on public.fms_posting_event (voucher_id)
  where voucher_id is not null;

alter table public.fms_posting_rule enable row level security;
alter table public.fms_posting_rule_line enable row level security;
alter table public.fms_posting_event enable row level security;

do $$
declare
  v_table text;
begin
  foreach v_table in array array['fms_posting_rule', 'fms_posting_rule_line', 'fms_posting_event'] loop
    execute format(
      'create policy %I on public.%I for select to authenticated using ((select app_private.is_platform_super()) or tenant_id = (select app_private.current_user_tenant_id()))',
      v_table || '_tenant_select', v_table
    );
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((select app_private.is_platform_super()))',
      v_table || '_platform_insert', v_table
    );
    execute format(
      'create policy %I on public.%I for update to authenticated using ((select app_private.is_platform_super())) with check ((select app_private.is_platform_super()))',
      v_table || '_platform_update', v_table
    );
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((select app_private.is_platform_super()))',
      v_table || '_platform_delete', v_table
    );
  end loop;
end;
$$;

create trigger fms_posting_rule_create_audit
before insert on public.fms_posting_rule
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger fms_posting_rule_update_audit
before update on public.fms_posting_rule
for each row execute function public.trg_set_update_time_and_by();
create trigger fms_posting_rule_line_create_audit
before insert on public.fms_posting_rule_line
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger fms_posting_rule_line_update_audit
before update on public.fms_posting_rule_line
for each row execute function public.trg_set_update_time_and_by();

create or replace function app_private.is_fms_system_posting()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(current_setting('app.fms_system_posting', true), '') = 'on'
$$;

revoke all on function app_private.is_fms_system_posting() from public, anon, authenticated;

do $$
declare
  v_signature regprocedure;
  v_definition text;
  v_replaced text;
begin
  foreach v_signature in array array[
    'public.save_fms_voucher(jsonb)'::regprocedure,
    'public.transition_fms_voucher(uuid,text,text,date)'::regprocedure
  ] loop
    select pg_get_functiondef(v_signature) into v_definition;
    v_replaced := replace(
      v_definition,
      'if not (select app_private.is_platform_super()) then',
      'if not ((select app_private.is_platform_super()) or (select app_private.is_fms_system_posting())) then'
    );
    if v_replaced = v_definition then
      raise exception 'Unable to install the FMS system-posting authorization boundary for %', v_signature;
    end if;
    execute v_replaced;
  end loop;
end;
$$;

create or replace function public.save_fms_posting_rule(p_payload jsonb)
returns public.fms_posting_rule
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_rule public.fms_posting_rule%rowtype;
  v_line jsonb;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'unknown');
  v_line_count integer := 0;
  v_debit_count integer := 0;
  v_credit_count integer := 0;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护自动入账规则';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'lines', '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = '制证规则分录必须为数组';
  end if;
  if jsonb_typeof(coalesce(p_payload -> 'matchConditions', '{}'::jsonb)) <> 'object' then
    raise exception using errcode = '22023', message = '匹配条件必须为对象';
  end if;
  select * into v_account_set
  from public.fms_account_set
  where id = (p_payload ->> 'accountSetId')::uuid and status = 'active';
  if not found then
    raise exception using errcode = '23503', message = '账套不存在或未启用';
  end if;

  if v_id is null then
    insert into public.fms_posting_rule (
      tenant_id, account_set_id, rule_code, rule_name, source_type, event_code,
      voucher_type, submission_mode, match_conditions, priority, effective_from,
      effective_to, is_enabled, remark, create_by, update_by
    ) values (
      v_account_set.tenant_id, v_account_set.id, upper(btrim(p_payload ->> 'ruleCode')),
      btrim(p_payload ->> 'ruleName'), p_payload ->> 'sourceType', p_payload ->> 'eventCode',
      coalesce(nullif(p_payload ->> 'voucherType', ''), 'general'),
      coalesce(nullif(p_payload ->> 'submissionMode', ''), 'pending_review'),
      coalesce(p_payload -> 'matchConditions', '{}'::jsonb),
      coalesce(nullif(p_payload ->> 'priority', '')::integer, 100),
      nullif(p_payload ->> 'effectiveFrom', '')::date,
      nullif(p_payload ->> 'effectiveTo', '')::date,
      coalesce((p_payload ->> 'isEnabled')::boolean, true),
      nullif(btrim(p_payload ->> 'remark'), ''), v_actor, v_actor
    ) returning * into v_rule;
  else
    update public.fms_posting_rule set
      rule_code = upper(btrim(p_payload ->> 'ruleCode')),
      rule_name = btrim(p_payload ->> 'ruleName'),
      source_type = p_payload ->> 'sourceType',
      event_code = p_payload ->> 'eventCode',
      voucher_type = coalesce(nullif(p_payload ->> 'voucherType', ''), 'general'),
      submission_mode = coalesce(nullif(p_payload ->> 'submissionMode', ''), 'pending_review'),
      match_conditions = coalesce(p_payload -> 'matchConditions', '{}'::jsonb),
      priority = coalesce(nullif(p_payload ->> 'priority', '')::integer, 100),
      effective_from = nullif(p_payload ->> 'effectiveFrom', '')::date,
      effective_to = nullif(p_payload ->> 'effectiveTo', '')::date,
      is_enabled = coalesce((p_payload ->> 'isEnabled')::boolean, true),
      remark = nullif(btrim(p_payload ->> 'remark'), ''),
      update_by = v_actor,
      update_time = now()
    where id = v_id and account_set_id = v_account_set.id
    returning * into v_rule;
    if not found then
      raise exception using errcode = 'P0002', message = '自动入账规则不存在';
    end if;
    delete from public.fms_posting_rule_line where rule_id = v_rule.id;
  end if;

  for v_line in
    select value from jsonb_array_elements(coalesce(p_payload -> 'lines', '[]'::jsonb))
  loop
    v_line_count := v_line_count + 1;
    if v_line ->> 'direction' = 'debit' then v_debit_count := v_debit_count + 1; end if;
    if v_line ->> 'direction' = 'credit' then v_credit_count := v_credit_count + 1; end if;
    insert into public.fms_posting_rule_line (
      tenant_id, account_set_id, rule_id, line_no, direction, amount_key,
      amount_multiplier, subject_id, summary, auxiliary_bindings, create_by, update_by
    ) values (
      v_rule.tenant_id, v_rule.account_set_id, v_rule.id,
      coalesce(nullif(v_line ->> 'lineNo', '')::smallint, v_line_count),
      v_line ->> 'direction', v_line ->> 'amountKey',
      coalesce(nullif(v_line ->> 'amountMultiplier', '')::numeric, 1),
      (v_line ->> 'subjectId')::uuid,
      nullif(btrim(v_line ->> 'summary'), ''),
      coalesce(v_line -> 'auxiliaryBindings', '{}'::jsonb), v_actor, v_actor
    );
  end loop;
  if v_line_count < 2 or v_debit_count = 0 or v_credit_count = 0 then
    raise exception using errcode = '23514', message = '制证规则至少需要一条借方和一条贷方分录';
  end if;
  return v_rule;
end;
$$;

create or replace function public.delete_fms_posting_rule(p_rule_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可删除自动入账规则';
  end if;
  if exists (select 1 from public.fms_posting_event where rule_id = p_rule_id) then
    raise exception using errcode = '23514', message = '规则已有制证记录，请停用而不要删除';
  end if;
  delete from public.fms_posting_rule where id = p_rule_id;
  if not found then raise exception using errcode = 'P0002', message = '自动入账规则不存在'; end if;
  return p_rule_id;
end;
$$;

create or replace function app_private.resolve_fms_posting_account_set(p_tenant_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_id uuid;
  v_count integer;
begin
  select id into v_id
  from public.fms_account_set
  where tenant_id = p_tenant_id and status = 'active' and is_default
  order by enabled_on, id limit 1;
  if v_id is not null then return v_id; end if;
  select count(*), min(id) into v_count, v_id
  from public.fms_account_set
  where tenant_id = p_tenant_id and status = 'active';
  if v_count = 1 then return v_id; end if;
  return null;
end;
$$;

create or replace function app_private.process_fms_posting_event(
  p_event_id uuid,
  p_force boolean default false
)
returns public.fms_posting_event
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.fms_posting_event%rowtype;
  v_rule public.fms_posting_rule%rowtype;
  v_rule_line public.fms_posting_rule_line%rowtype;
  v_voucher public.fms_voucher%rowtype;
  v_origin public.fms_voucher%rowtype;
  v_lines jsonb := '[]'::jsonb;
  v_auxiliary jsonb;
  v_binding record;
  v_item_id uuid;
  v_external_id uuid;
  v_amount numeric;
  v_line_no integer := 0;
  v_error text;
begin
  select * into v_event from public.fms_posting_event where id = p_event_id for update;
  if not found then raise exception using errcode = 'P0002', message = '自动入账事件不存在'; end if;
  if v_event.status in ('generated', 'reversed', 'ignored') and not p_force then return v_event; end if;

  update public.fms_posting_event set
    status = 'processing', attempt_count = attempt_count + 1,
    last_error = null, update_time = now()
  where id = v_event.id returning * into v_event;

  begin
    if v_event.account_set_id is null then
      v_event.account_set_id := app_private.resolve_fms_posting_account_set(v_event.tenant_id);
      if v_event.account_set_id is null then
        update public.fms_posting_event set status = 'pending_configuration',
          last_error = '当前租户未配置唯一的启用账套或默认账套', update_time = now()
        where id = v_event.id returning * into v_event;
        return v_event;
      end if;
      update public.fms_posting_event set account_set_id = v_event.account_set_id where id = v_event.id;
    end if;

    perform set_config('app.fms_system_posting', 'on', true);

    if v_event.event_code = 'voided' then
      select v.* into v_origin
      from public.fms_posting_event e
      join public.fms_voucher v on v.id = e.voucher_id
      where e.tenant_id = v_event.tenant_id
        and e.source_type = v_event.source_type
        and e.source_id = v_event.source_id
        and e.event_code <> 'voided'
        and e.status = 'generated'
      order by e.processed_at desc nulls last, e.create_time desc
      limit 1;
      if not found then
        update public.fms_posting_event set status = 'ignored',
          last_error = '原业务单据未生成会计凭证，无需冲销', processed_at = now(), update_time = now()
        where id = v_event.id returning * into v_event;
        return v_event;
      end if;
      update public.fms_posting_event set origin_voucher_id = v_origin.id where id = v_event.id;
      if v_origin.status = 'posted' then
        select * into v_voucher from public.transition_fms_voucher(
          v_origin.id, 'reverse', '业务单据已作废：' || v_event.summary, v_event.event_date
        );
        select * into v_voucher from public.fms_voucher where id = v_voucher.reversal_voucher_id;
      elsif v_origin.status = 'pending_review' then
        perform public.transition_fms_voucher(v_origin.id, 'reject', '业务单据已作废', null);
        select * into v_voucher from public.transition_fms_voucher(v_origin.id, 'void', '业务单据已作废', null);
      elsif v_origin.status in ('draft', 'rejected', 'approved') then
        select * into v_voucher from public.transition_fms_voucher(v_origin.id, 'void', '业务单据已作废', null);
      else
        v_voucher := v_origin;
      end if;
      update public.fms_posting_event set status = 'reversed', voucher_id = v_voucher.id,
        processed_at = now(), last_error = null, update_time = now()
      where id = v_event.id returning * into v_event;
      return v_event;
    end if;

    select * into v_voucher
    from public.fms_voucher
    where account_set_id = v_event.account_set_id
      and source_type = v_event.source_type
      and source_id = v_event.source_id
    order by create_time limit 1;
    if found then
      update public.fms_posting_event set status = 'generated', voucher_id = v_voucher.id,
        processed_at = coalesce(processed_at, now()), last_error = null, update_time = now()
      where id = v_event.id returning * into v_event;
      return v_event;
    end if;

    select * into v_rule
    from public.fms_posting_rule r
    where r.account_set_id = v_event.account_set_id
      and r.source_type = v_event.source_type
      and r.event_code = v_event.event_code
      and r.is_enabled
      and (r.effective_from is null or r.effective_from <= v_event.event_date)
      and (r.effective_to is null or r.effective_to >= v_event.event_date)
      and v_event.payload @> r.match_conditions
    order by r.priority desc, r.create_time, r.id
    limit 1;
    if not found then
      update public.fms_posting_event set status = 'pending_configuration',
        last_error = '未找到匹配的自动入账规则', update_time = now()
      where id = v_event.id returning * into v_event;
      return v_event;
    end if;

    for v_rule_line in
      select * from public.fms_posting_rule_line where rule_id = v_rule.id order by line_no
    loop
      if not (v_event.payload ? v_rule_line.amount_key) then
        raise exception '事件缺少金额字段 %', v_rule_line.amount_key;
      end if;
      v_amount := round(coalesce(nullif(v_event.payload ->> v_rule_line.amount_key, '')::numeric, 0)
        * v_rule_line.amount_multiplier, 2);
      if v_amount = 0 then continue; end if;
      v_auxiliary := '{}'::jsonb;
      for v_binding in select key, value from jsonb_each_text(v_rule_line.auxiliary_bindings) loop
        if nullif(v_event.payload ->> v_binding.value, '') is null then continue; end if;
        v_external_id := (v_event.payload ->> v_binding.value)::uuid;
        select id into v_item_id
        from public.fms_auxiliary_item
        where account_set_id = v_event.account_set_id
          and auxiliary_type_id = v_binding.key::uuid
          and external_entity_id = v_external_id
          and is_enabled
        order by sort, id limit 1;
        if not found then
          raise exception '辅助核算项未同步：维度 %, 业务实体 %', v_binding.key, v_external_id;
        end if;
        v_auxiliary := v_auxiliary || jsonb_build_object(v_binding.key, v_item_id);
      end loop;
      v_line_no := v_line_no + 1;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'lineNo', v_line_no,
        'summary', coalesce(v_rule_line.summary, v_event.summary),
        'subjectId', v_rule_line.subject_id,
        'auxiliaryValues', v_auxiliary,
        'debitAmount', case when v_rule_line.direction = 'debit' then v_amount else 0 end,
        'creditAmount', case when v_rule_line.direction = 'credit' then v_amount else 0 end,
        'sourceLineType', 'posting_rule_line',
        'sourceLineId', v_rule_line.id
      ));
    end loop;
    if v_line_no < 2 then raise exception '制证规则生成的有效分录少于两条'; end if;

    select * into v_voucher from public.save_fms_voucher(jsonb_build_object(
      'accountSetId', v_event.account_set_id,
      'voucherType', v_rule.voucher_type,
      'voucherDate', v_event.event_date,
      'summary', v_event.summary,
      'sourceType', v_event.source_type,
      'sourceId', v_event.source_id,
      'sourceNo', v_event.source_no,
      'attachments', '[]'::jsonb,
      'lines', v_lines
    ));
    perform app_private.assert_fms_voucher_ready(v_voucher.id);
    if v_rule.submission_mode = 'pending_review' then
      select * into v_voucher from public.transition_fms_voucher(v_voucher.id, 'submit', null, null);
    end if;
    update public.fms_posting_event set status = 'generated', rule_id = v_rule.id,
      voucher_id = v_voucher.id, processed_at = now(), last_error = null, update_time = now()
    where id = v_event.id returning * into v_event;
    return v_event;
  exception when others then
    get stacked diagnostics v_error = message_text;
    update public.fms_posting_event set status = 'failed', last_error = left(v_error, 1000),
      update_time = now()
    where id = v_event.id returning * into v_event;
    return v_event;
  end;
end;
$$;

create or replace function public.retry_fms_posting_event(p_event_id uuid)
returns public.fms_posting_event
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可重试自动入账事件';
  end if;
  return app_private.process_fms_posting_event(p_event_id, true);
end;
$$;

create or replace function public.process_pending_fms_posting_events(p_limit integer default 50)
returns table (event_id uuid, status text, voucher_id uuid, last_error text)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
  v_result public.fms_posting_event%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可批量处理自动入账事件';
  end if;
  for v_id in
    select id from public.fms_posting_event
    where status in ('pending', 'pending_configuration', 'failed')
    order by event_date, create_time
    limit greatest(1, least(coalesce(p_limit, 50), 500))
  loop
    v_result := app_private.process_fms_posting_event(v_id, true);
    event_id := v_result.id;
    status := v_result.status;
    voucher_id := v_result.voucher_id;
    last_error := v_result.last_error;
    return next;
  end loop;
end;
$$;

revoke all on function app_private.resolve_fms_posting_account_set(uuid) from public, anon, authenticated;
revoke all on function app_private.process_fms_posting_event(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.save_fms_posting_rule(jsonb) from public, anon;
revoke execute on function public.delete_fms_posting_rule(uuid) from public, anon;
revoke execute on function public.retry_fms_posting_event(uuid) from public, anon;
revoke execute on function public.process_pending_fms_posting_events(integer) from public, anon;
grant execute on function public.save_fms_posting_rule(jsonb) to authenticated, service_role;
grant execute on function public.delete_fms_posting_rule(uuid) to authenticated, service_role;
grant execute on function public.retry_fms_posting_event(uuid) to authenticated, service_role;
grant execute on function public.process_pending_fms_posting_events(integer) to authenticated, service_role;

commit;

;
