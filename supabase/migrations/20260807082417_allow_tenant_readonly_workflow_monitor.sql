-- Allow authenticated users to observe workflow operations inside their own tenant.
-- Cross-tenant reads and every monitor-side mutation remain platform-super only.

create or replace function app_private.search_workflow_instances_for_monitor(
  p_keyword text default null,
  p_business_type text default null,
  p_status text default null,
  p_sla_status text default null,
  p_from integer default 0,
  p_to integer default 19
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1), 100);
  v_result jsonb;
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后查看审批监控' using errcode = '42501';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception '当前账号未关联有效租户' using errcode = '42501';
  end if;
  if nullif(p_status, '') is not null
     and p_status not in ('running', 'approved', 'rejected', 'withdrawn', 'cancelled') then
    raise exception '无效的流程状态';
  end if;
  if nullif(p_sla_status, '') is not null and p_sla_status not in ('normal', 'overdue') then
    raise exception '无效的时效状态';
  end if;

  with scoped as (
    select
      i as instance_record,
      d.name as definition_name,
      d.code as definition_code,
      v.version_no,
      coalesce(task_stats.pending_task_count, 0) as pending_task_count,
      task_stats.nearest_due_at,
      coalesce(task_stats.is_overdue, false) as is_overdue,
      round(
        (extract(epoch from (coalesce(i.finished_at, now()) - i.started_at)) / 3600)::numeric,
        1
      ) as duration_hours
    from public.wf_instance i
    join public.wf_definition d on d.id = i.definition_id
    join public.wf_version v on v.id = i.version_id
    left join lateral (
      select
        count(*)::integer as pending_task_count,
        min(t.due_at) as nearest_due_at,
        bool_or(t.due_at < now()) filter (where t.due_at is not null) as is_overdue
      from public.wf_task t
      where t.instance_id = i.id and t.status = 'pending'
    ) task_stats on true
    where v_is_platform_super or i.tenant_id = v_tenant_id
  ), filtered as (
    select
      to_jsonb(instance_record) || jsonb_build_object(
        'definition_name', definition_name,
        'definition_code', definition_code,
        'version_no', version_no,
        'pending_task_count', pending_task_count,
        'nearest_due_at', nearest_due_at,
        'is_overdue', is_overdue,
        'duration_hours', duration_hours
      ) as record,
      (instance_record).started_at as started_at
    from scoped
    where (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or (instance_record).business_title ilike '%' || btrim(p_keyword) || '%'
      or (instance_record).business_id::text ilike '%' || btrim(p_keyword) || '%'
      or (instance_record).initiator_name_snapshot ilike '%' || btrim(p_keyword) || '%'
      or definition_name ilike '%' || btrim(p_keyword) || '%'
    )
      and (nullif(p_business_type, '') is null or (instance_record).business_type = p_business_type)
      and (nullif(p_status, '') is null or (instance_record).status = p_status)
      and (
        nullif(p_sla_status, '') is null
        or (p_sla_status = 'overdue' and is_overdue)
        or (p_sla_status = 'normal' and not is_overdue)
      )
  ), page_rows as (
    select record, started_at
    from filtered
    order by started_at desc
    offset v_from limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((select jsonb_agg(record order by started_at desc) from page_rows), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function app_private.get_workflow_monitor_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后查看审批监控' using errcode = '42501';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception '当前账号未关联有效租户' using errcode = '42501';
  end if;

  with scoped as (
    select
      i.status,
      i.started_at,
      i.finished_at,
      exists (
        select 1 from public.wf_task t
        where t.instance_id = i.id
          and t.status = 'pending'
          and t.due_at < now()
      ) as is_overdue
    from public.wf_instance i
    where v_is_platform_super or i.tenant_id = v_tenant_id
  )
  select jsonb_build_object(
    'running_count', count(*) filter (where status = 'running'),
    'overdue_count', count(*) filter (where status = 'running' and is_overdue),
    'approved_30d_count', count(*) filter (
      where status = 'approved' and finished_at >= now() - interval '30 days'
    ),
    'rejected_30d_count', count(*) filter (
      where status = 'rejected' and finished_at >= now() - interval '30 days'
    ),
    'cancelled_30d_count', count(*) filter (
      where status = 'cancelled' and finished_at >= now() - interval '30 days'
    ),
    'average_duration_hours', coalesce(round((avg(
      extract(epoch from (finished_at - started_at)) / 3600
    ) filter (where finished_at is not null))::numeric, 1), 0)
  ) into v_result
  from scoped;

  return v_result;
end;
$$;

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
  v_is_platform_super boolean := (select app_private.is_platform_super());
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后查看审批回调' using errcode = '42501';
  end if;
  if not v_is_platform_super and v_tenant_id is null then
    raise exception '当前账号未关联有效租户' using errcode = '42501';
  end if;
  if p_status is not null
     and p_status not in ('pending', 'processing', 'retry_wait', 'succeeded', 'dead_letter') then
    raise exception '审批回调状态筛选值不合法';
  end if;

  select jsonb_build_object(
    'summary', (
      select jsonb_build_object(
        'pending', count(*) filter (where o.status = 'pending'),
        'processing', count(*) filter (where o.status = 'processing'),
        'retryWait', count(*) filter (where o.status = 'retry_wait'),
        'succeeded', count(*) filter (where o.status = 'succeeded'),
        'deadLetter', count(*) filter (where o.status = 'dead_letter')
      )
      from public.wf_business_callback_outbox o
      where v_is_platform_super or o.tenant_id = v_tenant_id
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
        where (v_is_platform_super or o.tenant_id = v_tenant_id)
          and (p_status is null or o.status = p_status)
        order by o.create_time desc, o.id desc
        limit greatest(1, least(coalesce(p_limit, 50), 200))
      ) item
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function app_private.cancel_workflow_instance(
  p_instance_id uuid,
  p_comment text,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select app_private.current_app_user_id());
  v_instance public.wf_instance;
  v_actor_name text;
  v_existing_instance_id uuid;
  v_comment text := btrim(coalesce(p_comment, ''));
begin
  if (select auth.uid()) is null or v_user_id is null
     or not (select app_private.is_platform_super()) then
    raise exception '仅平台超级管理员可以终止审批流程' using errcode = '42501';
  end if;
  if char_length(v_comment) < 4 then raise exception '终止原因至少填写4个字符'; end if;
  if char_length(v_comment) > 500 then raise exception '终止原因不能超过500个字符'; end if;

  select * into v_instance
  from public.wf_instance i
  where i.id = p_instance_id
  for update;
  if not found then raise exception '流程实例不存在或无权访问'; end if;

  if nullif(p_idempotency_key, '') is not null then
    select a.instance_id into v_existing_instance_id
    from public.wf_action a
    where a.tenant_id = v_instance.tenant_id
      and a.idempotency_key = p_idempotency_key;
    if found then
      if v_existing_instance_id <> p_instance_id then raise exception '幂等键已被其他流程使用'; end if;
      return p_instance_id;
    end if;
  end if;

  if v_instance.status <> 'running' then raise exception '流程已结束，不能再次终止'; end if;

  select coalesce(nullif(nick_name, ''), nullif(user_name, ''), user_email, id::text)
  into v_actor_name
  from public.sys_user
  where id = v_user_id;

  update public.wf_task
  set status = 'cancelled',
      handled_at = now(),
      comment = '流程管理员终止：' || v_comment
  where instance_id = p_instance_id and status = 'pending';

  update public.wf_instance
  set status = 'cancelled',
      current_node_key = null,
      current_node_name = null,
      finished_at = now(),
      finish_comment = v_comment,
      row_version = row_version + 1
  where id = p_instance_id;

  insert into public.wf_action(
    instance_id, action, actor_user_id, actor_name_snapshot, comment,
    metadata, idempotency_key, tenant_id
  ) values (
    p_instance_id, 'cancel', v_user_id, v_actor_name, v_comment,
    jsonb_build_object('source', 'workflow_monitor', 'operatorType', 'platform_super'),
    nullif(p_idempotency_key, ''), v_instance.tenant_id
  );

  perform app_private.apply_workflow_business_status(
    v_instance.business_type, v_instance.business_id, 'cancelled', v_actor_name, v_comment
  );
  return p_instance_id;
end;
$$;

drop policy if exists tenant_readonly_select on public.wf_instance;
create policy tenant_readonly_select
on public.wf_instance
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

drop policy if exists tenant_readonly_select on public.wf_task;
create policy tenant_readonly_select
on public.wf_task
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

drop policy if exists tenant_readonly_select on public.wf_action;
create policy tenant_readonly_select
on public.wf_action
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

drop policy if exists platform_super_callback_outbox_select
  on public.wf_business_callback_outbox;
drop policy if exists tenant_readonly_select
  on public.wf_business_callback_outbox;
create policy tenant_readonly_select
on public.wf_business_callback_outbox
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

drop policy if exists platform_super_callback_attempt_select
  on public.wf_business_callback_attempt;
drop policy if exists tenant_readonly_select
  on public.wf_business_callback_attempt;
create policy tenant_readonly_select
on public.wf_business_callback_attempt
for select
to authenticated
using (
  exists (
    select 1
    from public.wf_business_callback_outbox o
    where o.id = outbox_id
      and (
        (select app_private.is_platform_super())
        or o.tenant_id = (select app_private.current_user_tenant_id())
      )
  )
);

-- Keep Data API exposure explicit under the 2026 Supabase grant defaults.
grant select on table public.wf_instance,
  public.wf_task,
  public.wf_action,
  public.wf_business_callback_outbox,
  public.wf_business_callback_attempt to authenticated;

revoke all on function app_private.search_workflow_instances_for_monitor(text, text, text, text, integer, integer),
  app_private.get_workflow_monitor_summary(),
  app_private.get_workflow_callback_outbox(text, integer),
  app_private.cancel_workflow_instance(uuid, text, text)
  from public, anon, authenticated;

grant execute on function app_private.search_workflow_instances_for_monitor(text, text, text, text, integer, integer),
  app_private.get_workflow_monitor_summary(),
  app_private.get_workflow_callback_outbox(text, integer),
  app_private.cancel_workflow_instance(uuid, text, text)
  to authenticated, service_role;

;
