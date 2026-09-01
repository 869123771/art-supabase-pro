-- Enterprise workflow due reminders and overdue escalation scheduler.
-- Delivery is event-backed and idempotent; pg_cron only invokes the private processor.

create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;
create table public.wf_task_reminder_event (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.wf_task(id) on delete cascade,
  instance_id uuid not null references public.wf_instance(id) on delete cascade,
  event_type text not null,
  status text not null default 'pending',
  scheduled_at timestamptz not null,
  due_at timestamptz not null,
  attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  next_retry_at timestamptz,
  delivered_at timestamptz,
  recipient_user_ids uuid[] not null default '{}'::uuid[],
  error_message text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null,
  constraint wf_task_reminder_event_type_check
    check (event_type in ('due_soon', 'overdue', 'manager_escalation')),
  constraint wf_task_reminder_status_check
    check (status in ('pending', 'delivered', 'failed')),
  constraint wf_task_reminder_attempt_count_check
    check (attempt_count between 0 and 10),
  constraint wf_task_reminder_task_event_unique unique (task_id, event_type)
);
create index wf_task_reminder_retry_idx
  on public.wf_task_reminder_event(status, next_retry_at, scheduled_at)
  where status in ('pending', 'failed') and attempt_count < 10;
create index wf_task_reminder_tenant_time_idx
  on public.wf_task_reminder_event(tenant_id, create_time desc);
create index wf_task_reminder_instance_idx
  on public.wf_task_reminder_event(instance_id, create_time desc);
create trigger wf_task_reminder_create_audit
before insert on public.wf_task_reminder_event
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger wf_task_reminder_update_audit
before update on public.wf_task_reminder_event
for each row execute function public.trg_set_update_time_and_by();
alter table public.wf_task_reminder_event enable row level security;
create policy workflow_manager_reminder_select
on public.wf_task_reminder_event
for select
to authenticated
using (
  (select app_private.can_manage_workflow())
  and (
    (select app_private.is_platform_super())
    or tenant_id = (select app_private.current_user_tenant_id())
  )
);
revoke all on table public.wf_task_reminder_event from public, anon, authenticated;
grant select on table public.wf_task_reminder_event to authenticated;
grant all on table public.wf_task_reminder_event to service_role;
comment on table public.wf_task_reminder_event is
  'Idempotent delivery ledger for due-soon, overdue, and manager escalation workflow reminders.';
create or replace function app_private.validate_workflow_config(p_config jsonb)
returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_node jsonb;
  v_count integer;
  v_due_hours integer;
  v_reminder_minutes integer;
  v_escalate_hours integer;
begin
  if p_config is null or jsonb_typeof(p_config) <> 'object'
     or jsonb_typeof(p_config -> 'nodes') <> 'array' then
    raise exception '流程配置必须包含 nodes 数组';
  end if;
  v_count := jsonb_array_length(p_config -> 'nodes');
  if v_count < 1 or v_count > 30 then
    raise exception '审批节点数量必须在 1 到 30 之间';
  end if;
  if (select count(distinct node ->> 'key') from jsonb_array_elements(p_config -> 'nodes') node) <> v_count then
    raise exception '审批节点标识不能重复';
  end if;
  if (select count(distinct (node ->> 'order')::integer) from jsonb_array_elements(p_config -> 'nodes') node) <> v_count then
    raise exception '审批节点顺序不能重复';
  end if;

  for v_node in select value from jsonb_array_elements(p_config -> 'nodes') loop
    if btrim(coalesce(v_node ->> 'key', '')) = ''
       or (v_node ->> 'key') !~ '^[A-Za-z][A-Za-z0-9_-]{1,39}$'
       or btrim(coalesce(v_node ->> 'name', '')) = '' then
      raise exception '节点标识或名称不正确';
    end if;
    if coalesce(v_node ->> 'approvalMode', '') not in ('any', 'all') then
      raise exception '节点 % 的审批方式不正确', v_node ->> 'name';
    end if;
    if coalesce(v_node #>> '{assignee,type}', '') not in ('users', 'roles', 'initiator') then
      raise exception '节点 % 的审批人类型不正确', v_node ->> 'name';
    end if;
    if (v_node #>> '{assignee,type}') = 'users'
       and coalesce(jsonb_array_length(v_node #> '{assignee,userIds}'), 0) = 0 then
      raise exception '节点 % 必须选择审批人', v_node ->> 'name';
    end if;
    if (v_node #>> '{assignee,type}') = 'roles'
       and coalesce(jsonb_array_length(v_node #> '{assignee,roleCodes}'), 0) = 0 then
      raise exception '节点 % 必须选择审批角色', v_node ->> 'name';
    end if;
    if coalesce(v_node #>> '{condition,operator}', 'always') not in
       ('always', 'eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'in', 'contains', 'not_empty') then
      raise exception '节点 % 的条件运算符不受支持', v_node ->> 'name';
    end if;

    if coalesce(v_node ->> 'dueHours', '') !~ '^[0-9]+$' then
      raise exception '节点 % 的审批时限必须是整数小时', v_node ->> 'name';
    end if;
    v_due_hours := (v_node ->> 'dueHours')::integer;
    if v_due_hours < 1 or v_due_hours > 720 then
      raise exception '节点 % 的审批时限必须在 1 到 720 小时之间', v_node ->> 'name';
    end if;

    if coalesce(v_node ->> 'reminderBeforeMinutes', '60') !~ '^[0-9]+$' then
      raise exception '节点 % 的到期前提醒必须是整数分钟', v_node ->> 'name';
    end if;
    v_reminder_minutes := coalesce((v_node ->> 'reminderBeforeMinutes')::integer, 60);
    if v_reminder_minutes < 0 or v_reminder_minutes > v_due_hours * 60 then
      raise exception '节点 % 的到期前提醒不能超过审批时限', v_node ->> 'name';
    end if;

    if coalesce(v_node ->> 'escalationEnabled', 'true') not in ('true', 'false') then
      raise exception '节点 % 的超时升级开关不正确', v_node ->> 'name';
    end if;
    if coalesce(v_node ->> 'escalateAfterHours', '4') !~ '^[0-9]+$' then
      raise exception '节点 % 的升级时间必须是整数小时', v_node ->> 'name';
    end if;
    v_escalate_hours := coalesce((v_node ->> 'escalateAfterHours')::integer, 4);
    if v_escalate_hours < 1 or v_escalate_hours > 720 then
      raise exception '节点 % 的升级时间必须在 1 到 720 小时之间', v_node ->> 'name';
    end if;
  end loop;
end;
$$;
revoke all on function app_private.validate_workflow_config(jsonb)
  from public, anon, authenticated;
grant execute on function app_private.validate_workflow_config(jsonb) to service_role;
create or replace function app_private.process_workflow_task_reminders(
  p_limit integer default 200
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 200), 1), 1000);
  v_event public.wf_task_reminder_event;
  v_task public.wf_task;
  v_instance public.wf_instance;
  v_recipient record;
  v_recipient_ids uuid[];
  v_delivered integer := 0;
  v_failed integer := 0;
  v_created integer := 0;
  v_rows integer := 0;
  v_title text;
  v_content text;
  v_source_type text;
  v_severity text;
begin
  -- Existing published versions without the new fields inherit safe defaults.
  with task_config as (
    select
      t.id as task_id,
      t.instance_id,
      t.tenant_id,
      t.due_at,
      case
        when coalesce(node.value ->> 'reminderBeforeMinutes', '60') ~ '^[0-9]+$'
          then (coalesce(node.value ->> 'reminderBeforeMinutes', '60'))::integer
        else 60
      end as reminder_before_minutes
    from public.wf_task t
    join public.wf_instance i on i.id = t.instance_id and i.status = 'running'
    join public.wf_version v on v.id = i.version_id
    join lateral jsonb_array_elements(v.config -> 'nodes') node(value)
      on node.value ->> 'key' = t.node_key
    where t.status = 'pending' and t.due_at is not null
  )
  insert into public.wf_task_reminder_event(
    task_id, instance_id, event_type, scheduled_at, due_at, tenant_id
  )
  select
    task_id,
    instance_id,
    'due_soon',
    due_at - make_interval(mins => reminder_before_minutes),
    due_at,
    tenant_id
  from task_config
  where reminder_before_minutes > 0
    and now() >= due_at - make_interval(mins => reminder_before_minutes)
    and now() < due_at
  on conflict (task_id, event_type) do nothing;
  get diagnostics v_rows = row_count;
  v_created := v_created + v_rows;

  insert into public.wf_task_reminder_event(
    task_id, instance_id, event_type, scheduled_at, due_at, tenant_id
  )
  select t.id, t.instance_id, 'overdue', t.due_at, t.due_at, t.tenant_id
  from public.wf_task t
  join public.wf_instance i on i.id = t.instance_id and i.status = 'running'
  where t.status = 'pending' and t.due_at is not null and now() >= t.due_at
  on conflict (task_id, event_type) do nothing;
  get diagnostics v_rows = row_count;
  v_created := v_created + v_rows;

  with task_config as (
    select
      t.id as task_id,
      t.instance_id,
      t.tenant_id,
      t.due_at,
      coalesce(node.value ->> 'escalationEnabled', 'true') = 'true' as escalation_enabled,
      case
        when coalesce(node.value ->> 'escalateAfterHours', '4') ~ '^[0-9]+$'
          then (coalesce(node.value ->> 'escalateAfterHours', '4'))::integer
        else 4
      end as escalate_after_hours
    from public.wf_task t
    join public.wf_instance i on i.id = t.instance_id and i.status = 'running'
    join public.wf_version v on v.id = i.version_id
    join lateral jsonb_array_elements(v.config -> 'nodes') node(value)
      on node.value ->> 'key' = t.node_key
    where t.status = 'pending' and t.due_at is not null
  )
  insert into public.wf_task_reminder_event(
    task_id, instance_id, event_type, scheduled_at, due_at, tenant_id
  )
  select
    task_id,
    instance_id,
    'manager_escalation',
    due_at + make_interval(hours => escalate_after_hours),
    due_at,
    tenant_id
  from task_config
  where escalation_enabled
    and now() >= due_at + make_interval(hours => escalate_after_hours)
  on conflict (task_id, event_type) do nothing;
  get diagnostics v_rows = row_count;
  v_created := v_created + v_rows;

  for v_event in
    select e.*
    from public.wf_task_reminder_event e
    join public.wf_task t on t.id = e.task_id and t.status = 'pending'
    join public.wf_instance i on i.id = e.instance_id and i.status = 'running'
    where e.status in ('pending', 'failed')
      and e.attempt_count < 10
      and e.scheduled_at <= now()
      and (e.next_retry_at is null or e.next_retry_at <= now())
    order by e.scheduled_at, e.create_time
    for update of e skip locked
    limit v_limit
  loop
    update public.wf_task_reminder_event
    set attempt_count = attempt_count + 1,
        last_attempt_at = now(),
        error_message = null
    where id = v_event.id
    returning * into v_event;

    begin
      select * into strict v_task from public.wf_task where id = v_event.task_id;
      select * into strict v_instance from public.wf_instance where id = v_event.instance_id;
      v_recipient_ids := '{}'::uuid[];

      if v_event.event_type = 'due_soon' then
        v_title := '审批即将到期：' || v_instance.business_title;
        v_content := '“' || v_task.node_name || '”节点将于 '
          || to_char(v_task.due_at at time zone 'Asia/Shanghai', 'YYYY-MM-DD HH24:MI')
          || ' 到期，请及时处理。';
        v_source_type := 'workflow_task_due_soon';
        v_severity := 'warning';

        perform app_private.enqueue_user_notification(
          v_task.assignee_user_id, v_task.tenant_id, 'todo', v_title, v_content,
          v_severity, v_source_type, v_event.id, v_instance.business_type,
          v_instance.business_id, v_instance.id, '/workflow/workbench',
          jsonb_build_object('tab', 'pending', 'instanceId', v_instance.id)
        );
        v_recipient_ids := array[v_task.assignee_user_id];
      elsif v_event.event_type = 'overdue' then
        v_title := '审批已超时：' || v_instance.business_title;
        v_content := '“' || v_task.node_name || '”节点已超过处理时限，请立即处理。';
        v_source_type := 'workflow_task_overdue';
        v_severity := 'danger';

        perform app_private.enqueue_user_notification(
          v_task.assignee_user_id, v_task.tenant_id, 'todo', v_title, v_content,
          v_severity, v_source_type, v_event.id, v_instance.business_type,
          v_instance.business_id, v_instance.id, '/workflow/workbench',
          jsonb_build_object('tab', 'pending', 'instanceId', v_instance.id)
        );
        v_recipient_ids := array[v_task.assignee_user_id];
      else
        v_title := '审批超时升级：' || v_instance.business_title;
        v_content := v_task.assignee_name_snapshot || ' 负责的“'
          || v_task.node_name || '”节点已长时间超时，请管理员介入。';
        v_source_type := 'workflow_task_manager_escalation';
        v_severity := 'danger';

        for v_recipient in
          select u.id
          from public.sys_user u
          where u.tenant_id = v_task.tenant_id
            and u.status = '1'
            and coalesce(u.user_roles, '{}'::text[])
              && array['R_ADMIN', 'YQ_ADMIN']::text[]
          order by u.id
        loop
          perform app_private.enqueue_user_notification(
            v_recipient.id, v_task.tenant_id, 'message', v_title, v_content,
            v_severity, v_source_type, v_event.id, v_instance.business_type,
            v_instance.business_id, v_instance.id, '/workflow/monitor',
            jsonb_build_object('instanceId', v_instance.id, 'slaStatus', 'overdue')
          );
          v_recipient_ids := array_append(v_recipient_ids, v_recipient.id);
        end loop;

        if cardinality(v_recipient_ids) = 0 then
          raise exception '当前租户没有可用的审批管理员';
        end if;
      end if;

      update public.wf_task_reminder_event
      set status = 'delivered',
          delivered_at = now(),
          next_retry_at = null,
          recipient_user_ids = v_recipient_ids,
          error_message = null
      where id = v_event.id;
      v_delivered := v_delivered + 1;
    exception when others then
      update public.wf_task_reminder_event
      set status = 'failed',
          next_retry_at = case when attempt_count < 10
            then now() + make_interval(mins => least(15 * attempt_count, 120))
            else null end,
          error_message = left(sqlerrm, 1000)
      where id = v_event.id;
      v_failed := v_failed + 1;
    end;
  end loop;

  return jsonb_build_object(
    'createdCount', v_created,
    'deliveredCount', v_delivered,
    'failedCount', v_failed
  );
end;
$$;
revoke all on function app_private.process_workflow_task_reminders(integer)
  from public, anon, authenticated;
grant execute on function app_private.process_workflow_task_reminders(integer)
  to service_role;
create or replace function app_private.trg_sync_workflow_task_notification()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'pending' and new.status <> 'pending' then
    update public.sys_notification n
    set is_read = true,
        read_at = coalesce(n.read_at, now())
    where n.recipient_user_id = new.assignee_user_id
      and n.category = 'todo'
      and n.is_read = false
      and (
        (n.source_type = 'workflow_task' and n.source_id = new.id)
        or (
          n.source_type in ('workflow_task_due_soon', 'workflow_task_overdue')
          and n.source_id in (
            select e.id from public.wf_task_reminder_event e where e.task_id = new.id
          )
        )
      );

    update public.sys_notification n
    set is_read = true,
        read_at = coalesce(n.read_at, now())
    where n.category = 'message'
      and n.source_type = 'workflow_task_manager_escalation'
      and n.is_read = false
      and n.source_id in (
        select e.id from public.wf_task_reminder_event e where e.task_id = new.id
      );
  end if;
  return new;
end;
$$;
revoke all on function app_private.trg_sync_workflow_task_notification()
  from public, anon, authenticated;
do $$
declare
  v_job_id bigint;
begin
  select jobid into v_job_id
  from cron.job
  where jobname = 'workflow-task-reminders';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'workflow-task-reminders',
    '*/5 * * * *',
    $job$select app_private.process_workflow_task_reminders(200);$job$
  );
end;
$$;
