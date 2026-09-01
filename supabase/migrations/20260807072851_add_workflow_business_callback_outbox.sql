-- Transactional Outbox for approval-to-business status callbacks.
-- Approval runtime stays authoritative; business projections are retried without
-- rolling back an already accepted workflow transition.

create table public.wf_business_callback_outbox (
  id uuid primary key default gen_random_uuid(),
  event_no bigint generated always as identity unique,
  tenant_id uuid not null references public.sys_tenant(id) on delete restrict,
  instance_id uuid not null references public.wf_instance(id) on delete restrict,
  business_type text not null,
  business_id uuid not null,
  target_status text not null,
  actor_name text not null,
  callback_comment text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'pending',
  attempt_count integer not null default 0,
  max_attempts integer not null default 8,
  next_attempt_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  processed_at timestamptz,
  last_error_code text,
  last_error text,
  manual_retry_count integer not null default 0,
  create_time timestamptz not null default now(),
  update_time timestamptz,
  create_by text,
  update_by text,
  constraint wf_business_callback_outbox_status_check check (
    status in ('pending', 'processing', 'retry_wait', 'succeeded', 'dead_letter')
  ),
  constraint wf_business_callback_outbox_target_status_check check (
    target_status in ('running', 'approved', 'rejected', 'withdrawn', 'cancelled')
  ),
  constraint wf_business_callback_outbox_attempt_count_check check (attempt_count >= 0),
  constraint wf_business_callback_outbox_max_attempts_check check (max_attempts between 1 and 30),
  constraint wf_business_callback_outbox_payload_object_check check (jsonb_typeof(payload) = 'object'),
  constraint wf_business_callback_outbox_instance_status_unique unique (instance_id, target_status)
);
comment on table public.wf_business_callback_outbox is
  'Transactional workflow business callback events with retry, dead-letter, and manual compensation state.';
create index wf_business_callback_outbox_dispatch_idx
  on public.wf_business_callback_outbox(next_attempt_at, create_time, id)
  where status in ('pending', 'retry_wait');
create index wf_business_callback_outbox_monitor_idx
  on public.wf_business_callback_outbox(status, update_time desc nulls last, create_time desc);
create index wf_business_callback_outbox_business_idx
  on public.wf_business_callback_outbox(tenant_id, business_type, business_id, create_time desc);
create table public.wf_business_callback_attempt (
  id uuid primary key default gen_random_uuid(),
  outbox_id uuid not null references public.wf_business_callback_outbox(id) on delete restrict,
  attempt_no integer not null,
  outcome text not null,
  worker_name text not null,
  error_code text,
  error_message text,
  duration_ms integer not null default 0,
  create_time timestamptz not null default now(),
  constraint wf_business_callback_attempt_outcome_check check (outcome in ('succeeded', 'failed')),
  constraint wf_business_callback_attempt_no_check check (attempt_no > 0),
  constraint wf_business_callback_attempt_duration_check check (duration_ms >= 0),
  constraint wf_business_callback_attempt_unique unique (outbox_id, attempt_no)
);
comment on table public.wf_business_callback_attempt is
  'Append-only delivery audit for workflow business callback attempts.';
create index wf_business_callback_attempt_outbox_time_idx
  on public.wf_business_callback_attempt(outbox_id, create_time desc);
create trigger wf_business_callback_outbox_create_audit
before insert on public.wf_business_callback_outbox
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger wf_business_callback_outbox_update_audit
before update on public.wf_business_callback_outbox
for each row execute function public.trg_set_update_time_and_by();
create or replace function app_private.trg_protect_workflow_callback_attempt()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception '审批业务回调投递记录不可修改或删除';
end;
$$;
revoke all on function app_private.trg_protect_workflow_callback_attempt()
  from public, anon, authenticated;
create trigger wf_business_callback_attempt_protect
before update or delete on public.wf_business_callback_attempt
for each row execute function app_private.trg_protect_workflow_callback_attempt();
alter table public.wf_business_callback_outbox enable row level security;
alter table public.wf_business_callback_attempt enable row level security;
create policy platform_super_callback_outbox_select
on public.wf_business_callback_outbox
for select
to authenticated
using ((select app_private.is_platform_super()));
create policy platform_super_callback_attempt_select
on public.wf_business_callback_attempt
for select
to authenticated
using (
  (select app_private.is_platform_super())
  and exists (
    select 1
    from public.wf_business_callback_outbox o
    where o.id = outbox_id
  )
);
revoke all on table public.wf_business_callback_outbox,
  public.wf_business_callback_attempt from public, anon, authenticated;
grant select on table public.wf_business_callback_outbox,
  public.wf_business_callback_attempt to authenticated;
grant all on table public.wf_business_callback_outbox,
  public.wf_business_callback_attempt to service_role;
-- Direct adapter router. Add a guarded branch here for each integrated business
-- aggregate; unknown business types intentionally complete as no-op projections.
create or replace function app_private.execute_workflow_business_callback(
  p_business_type text,
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.set_config('app.workflow_engine', 'on', true);

  if p_business_type = 'tms_waybill_cost' then
    update public.tms_waybill_cost
    set audit_status = case p_status
          when 'running' then 'pending_review'
          when 'approved' then 'approved'
          when 'rejected' then 'rejected'
          when 'withdrawn' then 'draft'
          when 'cancelled' then 'draft'
          else audit_status end,
        submitted_at = case when p_status = 'running' then now() else submitted_at end,
        submitted_by = case when p_status = 'running' then p_actor else submitted_by end,
        reviewed_at = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected') then now()
          else reviewed_at end,
        reviewed_by = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected') then p_actor
          else reviewed_by end,
        review_remark = case
          when p_status = 'running' then null
          when p_status in ('approved', 'rejected', 'cancelled')
            then nullif(btrim(coalesce(p_comment, '')), '')
          else review_remark end
    where id = p_business_id;

    if not found then
      raise exception '运单费用不存在或已被删除';
    end if;
  end if;
end;
$$;
revoke all on function app_private.execute_workflow_business_callback(text, uuid, text, text, text)
  from public, anon, authenticated;
create or replace function app_private.attempt_workflow_business_callback(
  p_outbox_id uuid,
  p_worker_name text default 'workflow-inline'
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event public.wf_business_callback_outbox;
  v_attempt_no integer;
  v_started_at timestamptz := clock_timestamp();
  v_error_code text;
  v_error_message text;
begin
  select *
  into v_event
  from public.wf_business_callback_outbox o
  where o.id = p_outbox_id
  for update;

  if not found then
    raise exception '审批业务回调事件不存在';
  end if;

  if v_event.status = 'succeeded' then
    return 'succeeded';
  end if;

  if v_event.status = 'dead_letter' then
    return 'dead_letter';
  end if;

  if exists (
    select 1
    from public.wf_business_callback_outbox earlier
    where earlier.instance_id = v_event.instance_id
      and earlier.event_no < v_event.event_no
      and earlier.status <> 'succeeded'
  ) then
    return 'blocked_by_predecessor';
  end if;

  select coalesce(max(a.attempt_no), 0) + 1
  into v_attempt_no
  from public.wf_business_callback_attempt a
  where a.outbox_id = v_event.id;

  update public.wf_business_callback_outbox
  set status = 'processing',
      attempt_count = attempt_count + 1,
      locked_at = now(),
      locked_by = coalesce(nullif(btrim(p_worker_name), ''), 'workflow-worker'),
      last_error_code = null,
      last_error = null
  where id = v_event.id
  returning * into v_event;

  begin
    perform app_private.execute_workflow_business_callback(
      v_event.business_type,
      v_event.business_id,
      v_event.target_status,
      v_event.actor_name,
      v_event.callback_comment
    );

    insert into public.wf_business_callback_attempt(
      outbox_id, attempt_no, outcome, worker_name, duration_ms
    ) values (
      v_event.id,
      v_attempt_no,
      'succeeded',
      v_event.locked_by,
      greatest(0, extract(milliseconds from clock_timestamp() - v_started_at)::integer)
    );

    update public.wf_business_callback_outbox
    set status = 'succeeded',
        processed_at = now(),
        next_attempt_at = now(),
        locked_at = null,
        locked_by = null,
        last_error_code = null,
        last_error = null
    where id = v_event.id;

    return 'succeeded';
  exception
    when others then
      get stacked diagnostics
        v_error_code = returned_sqlstate,
        v_error_message = message_text;

      insert into public.wf_business_callback_attempt(
        outbox_id, attempt_no, outcome, worker_name,
        error_code, error_message, duration_ms
      ) values (
        v_event.id,
        v_attempt_no,
        'failed',
        v_event.locked_by,
        v_error_code,
        left(v_error_message, 2000),
        greatest(0, extract(milliseconds from clock_timestamp() - v_started_at)::integer)
      );

      update public.wf_business_callback_outbox
      set status = case
            when v_event.attempt_count >= v_event.max_attempts then 'dead_letter'
            else 'retry_wait'
          end,
          next_attempt_at = case
            when v_event.attempt_count >= v_event.max_attempts then now()
            else now() + make_interval(
              secs => least(3600, 60 * power(2, least(v_event.attempt_count - 1, 6))::integer)
            )
          end,
          locked_at = null,
          locked_by = null,
          last_error_code = v_error_code,
          last_error = left(v_error_message, 2000)
      where id = v_event.id;

      return case
        when v_event.attempt_count >= v_event.max_attempts then 'dead_letter'
        else 'retry_wait'
      end;
  end;
end;
$$;
revoke all on function app_private.attempt_workflow_business_callback(uuid, text)
  from public, anon, authenticated;
grant execute on function app_private.attempt_workflow_business_callback(uuid, text)
  to service_role;
-- Existing engine call sites keep this stable function signature. The callback
-- is attempted immediately for backward-compatible UX, while failures are
-- captured for asynchronous retry instead of aborting the approval transaction.
create or replace function app_private.apply_workflow_business_status(
  p_business_type text,
  p_business_id uuid,
  p_status text,
  p_actor text,
  p_comment text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_instance public.wf_instance;
  v_outbox_id uuid;
begin
  select *
  into v_instance
  from public.wf_instance i
  where i.business_type = p_business_type
    and i.business_id = p_business_id
  order by i.create_time desc, i.id desc
  limit 1;

  if not found then
    raise exception '审批业务回调无法定位流程实例';
  end if;

  insert into public.wf_business_callback_outbox(
    tenant_id,
    instance_id,
    business_type,
    business_id,
    target_status,
    actor_name,
    callback_comment,
    payload,
    create_by,
    update_by
  ) values (
    v_instance.tenant_id,
    v_instance.id,
    p_business_type,
    p_business_id,
    p_status,
    coalesce(nullif(btrim(p_actor), ''), '系统'),
    nullif(btrim(coalesce(p_comment, '')), ''),
    jsonb_build_object(
      'instanceId', v_instance.id,
      'businessType', p_business_type,
      'businessId', p_business_id,
      'targetStatus', p_status
    ),
    coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'workflow-engine'),
    coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text, 'workflow-engine')
  )
  on conflict (instance_id, target_status) do nothing
  returning id into v_outbox_id;

  if v_outbox_id is null then
    select o.id into v_outbox_id
    from public.wf_business_callback_outbox o
    where o.instance_id = v_instance.id
      and o.target_status = p_status;
  end if;

  perform app_private.attempt_workflow_business_callback(v_outbox_id, 'workflow-inline');
end;
$$;
revoke all on function app_private.apply_workflow_business_status(text, uuid, text, text, text)
  from public, anon, authenticated;
create or replace function app_private.process_workflow_business_callbacks(
  p_batch_size integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event record;
  v_result text;
  v_processed integer := 0;
  v_succeeded integer := 0;
  v_retry_wait integer := 0;
  v_dead_letter integer := 0;
begin
  for v_event in
    select o.id
    from public.wf_business_callback_outbox o
    where o.status in ('pending', 'retry_wait')
      and o.next_attempt_at <= now()
      and not exists (
        select 1
        from public.wf_business_callback_outbox earlier
        where earlier.instance_id = o.instance_id
          and earlier.event_no < o.event_no
          and earlier.status <> 'succeeded'
      )
    order by o.next_attempt_at, o.event_no
    limit greatest(1, least(coalesce(p_batch_size, 100), 500))
    for update skip locked
  loop
    v_result := app_private.attempt_workflow_business_callback(
      v_event.id,
      'workflow-outbox-cron'
    );
    v_processed := v_processed + 1;
    v_succeeded := v_succeeded + case when v_result = 'succeeded' then 1 else 0 end;
    v_retry_wait := v_retry_wait + case when v_result = 'retry_wait' then 1 else 0 end;
    v_dead_letter := v_dead_letter + case when v_result = 'dead_letter' then 1 else 0 end;
  end loop;

  return jsonb_build_object(
    'processed', v_processed,
    'succeeded', v_succeeded,
    'retryWait', v_retry_wait,
    'deadLetter', v_dead_letter
  );
end;
$$;
revoke all on function app_private.process_workflow_business_callbacks(integer)
  from public, anon, authenticated;
grant execute on function app_private.process_workflow_business_callbacks(integer)
  to service_role;
create or replace function app_private.get_workflow_callback_outbox(
  p_status text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null or not (select app_private.is_platform_super()) then
    raise exception '当前账号没有审批回调监控权限' using errcode = '42501';
  end if;

  if p_status is not null
     and p_status not in ('pending', 'processing', 'retry_wait', 'succeeded', 'dead_letter') then
    raise exception '审批回调状态筛选值不合法';
  end if;

  select jsonb_build_object(
    'summary', jsonb_build_object(
      'pending', count(*) filter (where o.status = 'pending'),
      'processing', count(*) filter (where o.status = 'processing'),
      'retryWait', count(*) filter (where o.status = 'retry_wait'),
      'succeeded', count(*) filter (where o.status = 'succeeded'),
      'deadLetter', count(*) filter (where o.status = 'dead_letter')
    ),
    'items', coalesce((
      select jsonb_agg(to_jsonb(item) order by item."createTime" desc)
      from (
        select o.id,
               o.event_no as "eventNo",
               o.tenant_id as "tenantId",
               t.tenant_name as "tenantName",
               o.instance_id as "instanceId",
               i.business_title as "businessTitle",
               o.business_type as "businessType",
               o.business_id as "businessId",
               o.target_status as "targetStatus",
               o.status,
               o.attempt_count as "attemptCount",
               o.max_attempts as "maxAttempts",
               o.manual_retry_count as "manualRetryCount",
               o.next_attempt_at as "nextAttemptAt",
               o.processed_at as "processedAt",
               o.last_error_code as "lastErrorCode",
               o.last_error as "lastError",
               o.create_time as "createTime",
               coalesce((
                 select count(*) from public.wf_business_callback_attempt a
                 where a.outbox_id = o.id
               ), 0) as "totalAttempts"
        from public.wf_business_callback_outbox o
        join public.wf_instance i on i.id = o.instance_id
        left join public.sys_tenant t on t.id = o.tenant_id
        where (p_status is null or o.status = p_status)
        order by o.create_time desc, o.id desc
        limit greatest(1, least(coalesce(p_limit, 50), 200))
      ) item
    ), '[]'::jsonb)
  )
  into v_result
  from public.wf_business_callback_outbox o;

  return v_result;
end;
$$;
revoke all on function app_private.get_workflow_callback_outbox(text, integer)
  from public, anon, authenticated;
grant execute on function app_private.get_workflow_callback_outbox(text, integer)
  to authenticated, service_role;
create or replace function app_private.retry_workflow_business_callback(
  p_outbox_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result text;
begin
  if (select auth.uid()) is null or not (select app_private.is_platform_super()) then
    raise exception '当前账号没有审批回调补偿权限' using errcode = '42501';
  end if;

  update public.wf_business_callback_outbox
  set status = 'pending',
      attempt_count = 0,
      next_attempt_at = now(),
      processed_at = null,
      locked_at = null,
      locked_by = null,
      manual_retry_count = manual_retry_count + 1,
      last_error_code = null,
      last_error = null
  where id = p_outbox_id
    and status in ('retry_wait', 'dead_letter');

  if not found then
    raise exception '仅失败重试中或死信状态的回调允许人工补偿';
  end if;

  v_result := app_private.attempt_workflow_business_callback(
    p_outbox_id,
    'workflow-manual:' || auth.uid()::text
  );

  return jsonb_build_object('id', p_outbox_id, 'status', v_result);
end;
$$;
revoke all on function app_private.retry_workflow_business_callback(uuid)
  from public, anon, authenticated;
grant execute on function app_private.retry_workflow_business_callback(uuid)
  to authenticated, service_role;
create or replace function public.get_workflow_callback_outbox(
  p_status text default null,
  p_limit integer default 50
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.get_workflow_callback_outbox(p_status, p_limit)
$$;
create or replace function public.retry_workflow_business_callback(
  p_outbox_id uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select app_private.retry_workflow_business_callback(p_outbox_id)
$$;
revoke all on function public.get_workflow_callback_outbox(text, integer),
  public.retry_workflow_business_callback(uuid) from public, anon;
grant execute on function public.get_workflow_callback_outbox(text, integer),
  public.retry_workflow_business_callback(uuid) to authenticated, service_role;
do $$
declare
  v_job_id bigint;
begin
  for v_job_id in
    select jobid
    from cron.job
    where jobname = 'workflow-business-callback-outbox'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'workflow-business-callback-outbox',
    '* * * * *',
    'select app_private.process_workflow_business_callbacks(100);'
  );
end;
$$;
