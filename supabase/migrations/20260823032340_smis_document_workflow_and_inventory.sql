begin;

create table if not exists public.smis_business_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.sys_tenant(id) on delete restrict,
  record_id uuid not null references public.smis_business_record(id) on delete cascade,
  action text not null,
  from_status text not null,
  to_status text not null,
  comment text,
  operator_id uuid references public.sys_user(id) on delete set null,
  operator_name text,
  create_time timestamptz not null default now(),
  constraint smis_business_event_action_chk
    check (action = any(array['created', 'updated', 'submit', 'approve', 'reject', 'start', 'complete', 'cancel', 'reopen', 'transfer']::text[])),
  constraint smis_business_event_comment_chk
    check (comment is null or length(comment) <= 1000)
);

comment on table public.smis_business_event is
  'Tenant-scoped immutable audit timeline for SMIS document workflows.';

create index if not exists idx_smis_business_event_record_time
  on public.smis_business_event (record_id, create_time desc);
create index if not exists idx_smis_business_event_tenant_time
  on public.smis_business_event (tenant_id, create_time desc);

create table if not exists public.smis_exam_attempt (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.sys_tenant(id) on delete restrict,
  exam_record_id uuid not null references public.smis_business_record(id) on delete cascade,
  user_id uuid not null references public.sys_user(id) on delete restrict,
  attempt_no integer not null,
  status text not null default 'in_progress',
  answers jsonb not null default '{}'::jsonb,
  score numeric(8, 2),
  passed boolean,
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  constraint smis_exam_attempt_status_chk check (status = any(array['in_progress', 'submitted']::text[])),
  constraint smis_exam_attempt_answers_object_chk check (jsonb_typeof(answers) = 'object'),
  constraint smis_exam_attempt_number_chk check (attempt_no > 0),
  constraint smis_exam_attempt_user_number_uk unique (exam_record_id, user_id, attempt_no)
);

comment on table public.smis_exam_attempt is
  'Tenant-scoped exam attempts. Answers are scored by a server-side RPC against the published paper snapshot.';

create index if not exists idx_smis_exam_attempt_user_time
  on public.smis_exam_attempt (tenant_id, user_id, started_at desc);

alter table public.smis_business_event enable row level security;
alter table public.smis_business_event force row level security;
alter table public.smis_exam_attempt enable row level security;
alter table public.smis_exam_attempt force row level security;

drop policy if exists smis_business_record_tenant_select on public.smis_business_record;
create policy smis_business_record_tenant_select
on public.smis_business_record
for select
to authenticated
using (
  tenant_id = app_private.smis_current_tenant_id()
  and app_private.smis_has_permission('SmisCatalog:View')
);

drop policy if exists smis_business_event_tenant_select on public.smis_business_event;
create policy smis_business_event_tenant_select
on public.smis_business_event
for select
to authenticated
using (
  tenant_id = app_private.smis_current_tenant_id()
  and app_private.smis_has_permission('SmisCatalog:View')
);

drop policy if exists smis_exam_attempt_tenant_select on public.smis_exam_attempt;
create policy smis_exam_attempt_tenant_select
on public.smis_exam_attempt
for select
to authenticated
using (
  tenant_id = app_private.smis_current_tenant_id()
  and (
    user_id = app_private.smis_current_user_id()
    or app_private.smis_has_permission('SmisCatalog:Approve')
  )
);

revoke all on table public.smis_business_event from anon, authenticated;
grant select on table public.smis_business_event to authenticated;
grant all on table public.smis_business_event to service_role;
revoke all on table public.smis_exam_attempt from anon, authenticated;
grant select on table public.smis_exam_attempt to authenticated;
grant all on table public.smis_exam_attempt to service_role;

create or replace function public.smis_save_business_record(p_payload jsonb)
returns public.smis_business_record
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := app_private.smis_current_user_id();
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_record_id uuid := nullif(p_payload->>'id', '')::uuid;
  v_module_code text := nullif(btrim(p_payload->>'module_code'), '');
  v_status text := coalesce(nullif(btrim(p_payload->>'status'), ''), 'draft');
  v_previous_status text;
  v_waste_code text := nullif(btrim(p_payload->'payload'->>'waste_code'), '');
  v_quantity numeric := nullif(p_payload->'payload'->>'quantity', '')::numeric;
  v_unit text := coalesce(nullif(btrim(p_payload->'payload'->>'unit'), ''), '千克');
  v_requested_kg numeric;
  v_available_kg numeric;
  v_result public.smis_business_record;
begin
  if v_user_id is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;

  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'SMIS business payload must be a JSON object';
  end if;

  if not (v_module_code = any(app_private.smis_supported_module_codes())) then
    raise exception 'Unsupported SMIS module code: %', coalesce(v_module_code, '<empty>');
  end if;

  if v_module_code = any(array['hazardous-waste-inbound', 'hazardous-waste-outbound']::text[]) then
    if v_waste_code is null or v_quantity is null or v_quantity <= 0 then
      raise exception 'Hazardous-waste transactions require a waste code and a positive quantity';
    end if;
    if v_unit <> all(array['千克', '吨']::text[]) then
      raise exception 'Unsupported hazardous-waste unit: %', v_unit;
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(v_tenant_id::text || ':' || v_waste_code, 0)
    );
    v_requested_kg := v_quantity * case when v_unit = '吨' then 1000 else 1 end;

    if v_module_code = 'hazardous-waste-outbound' then
      select coalesce(sum(
        case
          when source.module_code = 'hazardous-waste-inbound'
            then (source.payload->>'quantity')::numeric
                 * case when source.payload->>'unit' = '吨' then 1000 else 1 end
          else -1 * (source.payload->>'quantity')::numeric
                 * case when source.payload->>'unit' = '吨' then 1000 else 1 end
        end
      ), 0)
      into v_available_kg
      from public.smis_business_record source
      where source.tenant_id = v_tenant_id
        and source.module_code = any(array['hazardous-waste-inbound', 'hazardous-waste-outbound']::text[])
        and source.payload->>'waste_code' = v_waste_code
        and source.status <> 'disabled'
        and (v_record_id is null or source.id <> v_record_id);

      if v_requested_kg > v_available_kg then
        raise exception 'Insufficient hazardous-waste stock. Available: % kg, requested: % kg',
          v_available_kg, v_requested_kg;
      end if;
    end if;
  end if;

  if v_record_id is null then
    if not app_private.smis_has_permission('SmisCatalog:Add') then
      raise exception 'Missing permission: SmisCatalog:Add';
    end if;

    insert into public.smis_business_record (
      tenant_id, module_code, record_no, title, status, owner_name,
      business_date, payload, created_by
    )
    values (
      v_tenant_id,
      v_module_code,
      nullif(btrim(p_payload->>'record_no'), ''),
      nullif(btrim(p_payload->>'title'), ''),
      v_status,
      nullif(btrim(p_payload->>'owner_name'), ''),
      nullif(p_payload->>'business_date', '')::timestamptz,
      coalesce(p_payload->'payload', '{}'::jsonb),
      v_user_id
    )
    returning * into v_result;

    insert into public.smis_business_event (
      tenant_id, record_id, action, from_status, to_status, operator_id, operator_name
    ) values (
      v_tenant_id, v_result.id, 'created', v_result.status, v_result.status,
      v_user_id, nullif(btrim(p_payload->>'owner_name'), '')
    );
  else
    if not app_private.smis_has_permission('SmisCatalog:Edit') then
      raise exception 'Missing permission: SmisCatalog:Edit';
    end if;

    select target.status into v_previous_status
    from public.smis_business_record target
    where target.id = v_record_id and target.tenant_id = v_tenant_id
    for update;

    if v_previous_status is null then
      raise exception 'SMIS business record was not found in the current tenant';
    end if;
    if v_previous_status <> v_status then
      raise exception 'Use the workflow transition API to change a business status';
    end if;

    update public.smis_business_record target
    set module_code = v_module_code,
        record_no = nullif(btrim(p_payload->>'record_no'), ''),
        title = nullif(btrim(p_payload->>'title'), ''),
        owner_name = nullif(btrim(p_payload->>'owner_name'), ''),
        business_date = nullif(p_payload->>'business_date', '')::timestamptz,
        payload = coalesce(p_payload->'payload', '{}'::jsonb),
        update_time = now()
    where target.id = v_record_id
      and target.tenant_id = v_tenant_id
    returning * into v_result;

    insert into public.smis_business_event (
      tenant_id, record_id, action, from_status, to_status, operator_id
    ) values (
      v_tenant_id, v_result.id, 'updated', v_result.status, v_result.status, v_user_id
    );
  end if;

  return v_result;
end;
$$;

create or replace function public.smis_transition_business_record(
  p_record_id uuid,
  p_action text,
  p_comment text default null
)
returns public.smis_business_record
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := app_private.smis_current_user_id();
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_action text := lower(btrim(p_action));
  v_from_status text;
  v_to_status text;
  v_required_permission text;
  v_operator_name text;
  v_result public.smis_business_record;
begin
  if v_user_id is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;
  if p_comment is not null and length(p_comment) > 1000 then
    raise exception 'Workflow comments must not exceed 1000 characters';
  end if;

  select target.status into v_from_status
  from public.smis_business_record target
  where target.id = p_record_id and target.tenant_id = v_tenant_id
  for update;

  if v_from_status is null then
    raise exception 'SMIS business record was not found in the current tenant';
  end if;

  case v_action
    when 'submit' then
      v_required_permission := 'SmisCatalog:Submit';
      if v_from_status <> 'draft' then raise exception 'Only drafts can be submitted'; end if;
      v_to_status := 'pending';
    when 'approve' then
      v_required_permission := 'SmisCatalog:Approve';
      if v_from_status <> 'pending' then raise exception 'Only pending records can be approved'; end if;
      v_to_status := 'active';
    when 'reject' then
      v_required_permission := 'SmisCatalog:Approve';
      if v_from_status <> 'pending' then raise exception 'Only pending records can be rejected'; end if;
      v_to_status := 'draft';
    when 'start' then
      v_required_permission := 'SmisCatalog:Execute';
      if v_from_status <> 'active' then raise exception 'Only approved records can be started'; end if;
      v_to_status := 'active';
    when 'complete' then
      v_required_permission := 'SmisCatalog:Execute';
      if v_from_status <> 'active' then raise exception 'Only active records can be completed'; end if;
      v_to_status := 'completed';
    when 'cancel' then
      v_required_permission := 'SmisCatalog:Execute';
      if v_from_status = 'completed' then raise exception 'Completed records cannot be cancelled'; end if;
      v_to_status := 'disabled';
    when 'reopen' then
      v_required_permission := 'SmisCatalog:Approve';
      if v_from_status <> all(array['completed', 'disabled']::text[]) then
        raise exception 'Only completed or cancelled records can be reopened';
      end if;
      v_to_status := 'active';
    when 'transfer' then
      v_required_permission := 'SmisCatalog:Execute';
      if v_from_status <> 'active' then raise exception 'Only active records can be transferred'; end if;
      if nullif(btrim(p_comment), '') is null then raise exception 'A transfer note is required'; end if;
      v_to_status := 'active';
    else
      raise exception 'Unsupported SMIS workflow action: %', p_action;
  end case;

  if not app_private.smis_has_permission(v_required_permission) then
    raise exception 'Missing permission: %', v_required_permission;
  end if;

  select coalesce(nullif(btrim(user_row.nick_name), ''), user_row.user_name)
  into v_operator_name
  from public.sys_user user_row where user_row.id = v_user_id;

  update public.smis_business_record target
  set status = v_to_status,
      payload = jsonb_set(target.payload, '{workflow_status}', to_jsonb(v_to_status), true),
      update_time = now()
  where target.id = p_record_id and target.tenant_id = v_tenant_id
  returning * into v_result;

  insert into public.smis_business_event (
    tenant_id, record_id, action, from_status, to_status, comment, operator_id, operator_name
  ) values (
    v_tenant_id, p_record_id, v_action, v_from_status, v_to_status,
    nullif(btrim(p_comment), ''), v_user_id, v_operator_name
  );

  return v_result;
end;
$$;

create or replace function public.smis_get_hazardous_waste_stock()
returns table (
  waste_code text,
  waste_name text,
  unit text,
  inbound_quantity numeric,
  outbound_quantity numeric,
  available_quantity numeric,
  last_transaction_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.smis_has_permission('SmisCatalog:View') then
    raise exception 'Missing permission: SmisCatalog:View';
  end if;

  return query
  with transactions as (
    select
      source.payload->>'waste_code' as code,
      coalesce(source.payload->>'waste_name', source.title) as name,
      (source.payload->>'quantity')::numeric
        * case when source.payload->>'unit' = '吨' then 1000 else 1 end as quantity_kg,
      source.module_code,
      source.business_date,
      source.update_time
    from public.smis_business_record source
    where source.tenant_id = app_private.smis_current_tenant_id()
      and source.module_code = any(array['hazardous-waste-inbound', 'hazardous-waste-outbound']::text[])
      and source.status <> 'disabled'
      and source.payload ? 'waste_code'
      and source.payload ? 'quantity'
  )
  select
    transactions.code,
    max(transactions.name),
    '千克'::text,
    coalesce(sum(transactions.quantity_kg) filter (where transactions.module_code = 'hazardous-waste-inbound'), 0),
    coalesce(sum(transactions.quantity_kg) filter (where transactions.module_code = 'hazardous-waste-outbound'), 0),
    coalesce(sum(
      case when transactions.module_code = 'hazardous-waste-inbound'
        then transactions.quantity_kg else -transactions.quantity_kg end
    ), 0),
    max(coalesce(transactions.business_date, transactions.update_time))
  from transactions
  group by transactions.code
  order by transactions.code;
end;
$$;

create or replace function public.smis_start_exam_attempt(p_exam_record_id uuid)
returns public.smis_exam_attempt
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := app_private.smis_current_user_id();
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_attempt_limit integer;
  v_attempt_count integer;
  v_next_attempt integer;
  v_payload jsonb;
  v_result public.smis_exam_attempt;
begin
  if v_user_id is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;
  if not app_private.smis_has_permission('SmisCatalog:TakeExam') then
    raise exception 'Missing permission: SmisCatalog:TakeExam';
  end if;

  select exam.payload into v_payload
  from public.smis_business_record exam
  where exam.id = p_exam_record_id
    and exam.tenant_id = v_tenant_id
    and exam.module_code = 'exam-management'
    and exam.status = 'active';

  if v_payload is null then
    raise exception 'The exam was not found, is not published, or belongs to another tenant';
  end if;
  if jsonb_typeof(v_payload->'detail_rows') <> 'array'
     or jsonb_array_length(v_payload->'detail_rows') = 0 then
    raise exception 'The published exam does not contain any questions';
  end if;

  select attempt.* into v_result
  from public.smis_exam_attempt attempt
  where attempt.exam_record_id = p_exam_record_id
    and attempt.user_id = v_user_id
    and attempt.status = 'in_progress'
  order by attempt.attempt_no desc
  limit 1;
  if v_result.id is not null then return v_result; end if;

  v_attempt_limit := greatest(coalesce(nullif(v_payload->>'attempt_limit', '')::integer, 1), 1);
  select count(*), coalesce(max(attempt.attempt_no), 0) + 1
    into v_attempt_count, v_next_attempt
  from public.smis_exam_attempt attempt
  where attempt.exam_record_id = p_exam_record_id and attempt.user_id = v_user_id;

  if v_attempt_count >= v_attempt_limit then
    raise exception 'The maximum number of exam attempts (%) has been reached', v_attempt_limit;
  end if;

  insert into public.smis_exam_attempt (
    tenant_id, exam_record_id, user_id, attempt_no
  ) values (
    v_tenant_id, p_exam_record_id, v_user_id, v_next_attempt
  ) returning * into v_result;

  return v_result;
end;
$$;

create or replace function public.smis_submit_exam_attempt(
  p_attempt_id uuid,
  p_answers jsonb
)
returns public.smis_exam_attempt
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := app_private.smis_current_user_id();
  v_tenant_id uuid := app_private.smis_current_tenant_id();
  v_attempt public.smis_exam_attempt;
  v_exam_payload jsonb;
  v_question jsonb;
  v_question_no text;
  v_correct_answer text;
  v_user_answer text;
  v_score numeric := 0;
  v_passing_score numeric;
  v_duration_minutes integer;
  v_result public.smis_exam_attempt;
begin
  if v_user_id is null or v_tenant_id is null then
    raise exception 'Authentication and an active tenant are required';
  end if;
  if not app_private.smis_has_permission('SmisCatalog:TakeExam') then
    raise exception 'Missing permission: SmisCatalog:TakeExam';
  end if;
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Exam answers must be a JSON object';
  end if;

  select attempt.* into v_attempt
  from public.smis_exam_attempt attempt
  where attempt.id = p_attempt_id
    and attempt.tenant_id = v_tenant_id
    and attempt.user_id = v_user_id
  for update;

  if v_attempt.id is null then raise exception 'Exam attempt was not found'; end if;
  if v_attempt.status <> 'in_progress' then raise exception 'The exam attempt was already submitted'; end if;

  select exam.payload into v_exam_payload
  from public.smis_business_record exam
  where exam.id = v_attempt.exam_record_id and exam.tenant_id = v_tenant_id;

  v_duration_minutes := greatest(coalesce(nullif(v_exam_payload->>'duration_minutes', '')::integer, 60), 1);
  if now() > v_attempt.started_at + pg_catalog.make_interval(mins => v_duration_minutes + 5) then
    raise exception 'The exam submission window has expired';
  end if;

  for v_question in select value from jsonb_array_elements(v_exam_payload->'detail_rows')
  loop
    v_question_no := nullif(btrim(v_question->>'question_no'), '');
    v_correct_answer := lower(regexp_replace(coalesce(v_question->>'correct_answer', ''), '\\s+', '', 'g'));
    v_user_answer := lower(regexp_replace(coalesce(p_answers->>v_question_no, ''), '\\s+', '', 'g'));
    if v_question_no is not null and v_correct_answer <> '' and v_user_answer = v_correct_answer then
      v_score := v_score + greatest(coalesce(nullif(v_question->>'score', '')::numeric, 0), 0);
    end if;
  end loop;

  v_passing_score := greatest(coalesce(nullif(v_exam_payload->>'passing_score', '')::numeric, 60), 0);
  update public.smis_exam_attempt target
  set status = 'submitted',
      answers = p_answers,
      score = v_score,
      passed = v_score >= v_passing_score,
      submitted_at = now()
  where target.id = p_attempt_id
  returning * into v_result;

  return v_result;
end;
$$;

revoke all on function public.smis_save_business_record(jsonb) from public, anon;
revoke all on function public.smis_transition_business_record(uuid, text, text) from public, anon;
revoke all on function public.smis_get_hazardous_waste_stock() from public, anon;
revoke all on function public.smis_start_exam_attempt(uuid) from public, anon;
revoke all on function public.smis_submit_exam_attempt(uuid, jsonb) from public, anon;
grant execute on function public.smis_save_business_record(jsonb) to authenticated, service_role;
grant execute on function public.smis_transition_business_record(uuid, text, text) to authenticated, service_role;
grant execute on function public.smis_get_hazardous_waste_stock() to authenticated, service_role;
grant execute on function public.smis_start_exam_attempt(uuid) to authenticated, service_role;
grant execute on function public.smis_submit_exam_attempt(uuid, jsonb) to authenticated, service_role;

insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by
)
values
  ('5a150000-0000-4000-8000-000000000121', '5a150000-0000-4000-8000-000000000001', 'SmisCatalog:Submit', '', '', '{"title":"提交业务单"}'::jsonb, 922, 'button', 'smis', 'smis-doc-v1'),
  ('5a150000-0000-4000-8000-000000000122', '5a150000-0000-4000-8000-000000000001', 'SmisCatalog:Approve', '', '', '{"title":"审批业务单"}'::jsonb, 923, 'button', 'smis', 'smis-doc-v1'),
  ('5a150000-0000-4000-8000-000000000123', '5a150000-0000-4000-8000-000000000001', 'SmisCatalog:Execute', '', '', '{"title":"执行业务单"}'::jsonb, 924, 'button', 'smis', 'smis-doc-v1'),
  ('5a150000-0000-4000-8000-000000000124', '5a150000-0000-4000-8000-000000000001', 'SmisCatalog:Print', '', '', '{"title":"打印业务单"}'::jsonb, 925, 'button', 'smis', 'smis-doc-v1'),
  ('5a150000-0000-4000-8000-000000000125', '5a150000-0000-4000-8000-000000000001', 'SmisCatalog:TakeExam', '', '', '{"title":"参加在线考试"}'::jsonb, 926, 'button', 'smis', 'smis-doc-v1')
on conflict (id) do update
set parent_id = excluded.parent_id,
    name = excluded.name,
    path = excluded.path,
    component = excluded.component,
    meta = excluded.meta,
    sort = excluded.sort,
    type = excluded.type,
    app_code = excluded.app_code,
    create_by = excluded.create_by;

commit;

;
