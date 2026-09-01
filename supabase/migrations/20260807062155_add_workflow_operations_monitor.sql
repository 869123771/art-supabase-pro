-- Enterprise workflow operations monitor.
-- Adds tenant-scoped operational reads and an audited administrator cancellation path.

create index if not exists wf_task_pending_due_idx
  on public.wf_task(tenant_id, due_at, instance_id)
  where status = 'pending' and due_at is not null;
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
    if not found then raise exception '运单费用不存在或已被删除'; end if;
  end if;
end;
$$;
revoke execute on function app_private.apply_workflow_business_status(text, uuid, text, text, text)
  from public, anon, authenticated;
create or replace function app_private.trg_require_workflow_for_cost_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.audit_status is distinct from old.audit_status
     and (
       new.audit_status in ('pending_review', 'approved', 'rejected')
       or (old.audit_status in ('pending_review', 'rejected') and new.audit_status = 'draft')
     )
     and coalesce(pg_catalog.current_setting('app.workflow_engine', true), '') <> 'on' then
    raise exception '费用审批状态必须通过审批中心流转';
  end if;
  return new;
end;
$$;
revoke execute on function app_private.trg_require_workflow_for_cost_review()
  from public, anon, authenticated;
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
begin
  if (select auth.uid()) is null or not (select app_private.can_manage_workflow()) then
    raise exception '当前账号没有审批监控权限' using errcode = '42501';
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
    where (select app_private.is_platform_super())
       or i.tenant_id = (select app_private.current_user_tenant_id())
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
revoke all on function app_private.search_workflow_instances_for_monitor(text, text, text, text, integer, integer)
  from public, anon, authenticated;
grant execute on function app_private.search_workflow_instances_for_monitor(text, text, text, text, integer, integer)
  to authenticated, service_role;
create or replace function app_private.get_workflow_monitor_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null or not (select app_private.can_manage_workflow()) then
    raise exception '当前账号没有审批监控权限' using errcode = '42501';
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
    where (select app_private.is_platform_super())
       or i.tenant_id = (select app_private.current_user_tenant_id())
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
revoke all on function app_private.get_workflow_monitor_summary()
  from public, anon, authenticated;
grant execute on function app_private.get_workflow_monitor_summary()
  to authenticated, service_role;
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
     or not (select app_private.can_manage_workflow()) then
    raise exception '当前账号没有终止审批流程的权限' using errcode = '42501';
  end if;
  if char_length(v_comment) < 4 then raise exception '终止原因至少填写4个字符'; end if;
  if char_length(v_comment) > 500 then raise exception '终止原因不能超过500个字符'; end if;

  select * into v_instance
  from public.wf_instance i
  where i.id = p_instance_id
    and (
      (select app_private.is_platform_super())
      or i.tenant_id = (select app_private.current_user_tenant_id())
    )
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
    jsonb_build_object('source', 'workflow_monitor', 'operatorType', 'administrator'),
    nullif(p_idempotency_key, ''), v_instance.tenant_id
  );

  perform app_private.apply_workflow_business_status(
    v_instance.business_type, v_instance.business_id, 'cancelled', v_actor_name, v_comment
  );
  return p_instance_id;
end;
$$;
revoke all on function app_private.cancel_workflow_instance(uuid, text, text)
  from public, anon, authenticated;
grant execute on function app_private.cancel_workflow_instance(uuid, text, text)
  to authenticated, service_role;
create or replace function public.search_workflow_instances_for_monitor(
  p_keyword text default null,
  p_business_type text default null,
  p_status text default null,
  p_sla_status text default null,
  p_from integer default 0,
  p_to integer default 19
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select app_private.search_workflow_instances_for_monitor(
    p_keyword, p_business_type, p_status, p_sla_status, p_from, p_to
  )
$$;
create or replace function public.get_workflow_monitor_summary()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$ select app_private.get_workflow_monitor_summary() $$;
create or replace function public.cancel_workflow_instance(
  p_instance_id uuid,
  p_comment text,
  p_idempotency_key text default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$ select app_private.cancel_workflow_instance(p_instance_id, p_comment, p_idempotency_key) $$;
revoke all on function public.search_workflow_instances_for_monitor(text, text, text, text, integer, integer)
  from public, anon;
revoke all on function public.get_workflow_monitor_summary() from public, anon;
revoke all on function public.cancel_workflow_instance(uuid, text, text) from public, anon;
grant execute on function public.search_workflow_instances_for_monitor(text, text, text, text, integer, integer)
  to authenticated, service_role;
grant execute on function public.get_workflow_monitor_summary() to authenticated, service_role;
grant execute on function public.cancel_workflow_instance(uuid, text, text)
  to authenticated, service_role;
with platform as (select id from public.sys_tenant where tenant_code = 'platform' limit 1),
parent as (select id from public.sys_dict_type where code = 'workflowEngine' limit 1)
insert into public.sys_dict_type(
  id, parent_id, name, code, status, node_type, sort, tenant_id, create_by, update_by
)
select gen_random_uuid(), parent.id, '流程时效状态', 'workflowSlaStatus', '1', 'dictionary', 9,
  platform.id, '624944977@qq.com', '624944977@qq.com'
from platform cross join parent
where not exists (select 1 from public.sys_dict_type where code = 'workflowSlaStatus');
with rows(value, label, sort, tag_type) as (values
  ('normal', '时效正常', 1, 'success'),
  ('overdue', '已超时', 2, 'danger')
), platform as (select id from public.sys_tenant where tenant_code = 'platform' limit 1),
dict_type as (select id from public.sys_dict_type where code = 'workflowSlaStatus' limit 1)
insert into public.sys_dictionary(
  id, type_id, code, status, value, label, sort, tag_type, tenant_id, create_by, update_by
)
select gen_random_uuid(), dict_type.id, 'workflowSlaStatus_' || rows.value, '1', rows.value,
  rows.label, rows.sort, rows.tag_type, platform.id, '624944977@qq.com', '624944977@qq.com'
from rows cross join platform cross join dict_type
where not exists (
  select 1 from public.sys_dictionary d
  where d.type_id = dict_type.id and d.value = rows.value
);
insert into public.sys_menu(id, parent_id, name, path, component, meta, sort, type, create_by, update_by)
select gen_random_uuid(), p.id, 'WorkflowMonitor', 'monitor', '/workflow/monitor', jsonb_build_object(
  'icon', 'ri:pulse-line',
  'title', '审批监控',
  'roles', jsonb_build_array('R_SUPER', 'R_ADMIN', 'YQ_ADMIN'),
  'is_hide', false,
  'is_enable', true,
  'keep_alive', true,
  'authList', jsonb_build_array(
    jsonb_build_object('title', '终止流程', 'authMark', 'cancel')
  )
), 3, 'menu', '624944977@qq.com', '624944977@qq.com'
from public.sys_menu p
where p.name = 'WorkflowCenter'
  and not exists (select 1 from public.sys_menu where name = 'WorkflowMonitor');
insert into public.sys_role_menu(id, role_id, menu_id, permission, create_by, update_by, tenant_id)
select gen_random_uuid(), r.id, m.id, '{}'::jsonb, '624944977@qq.com', '624944977@qq.com', r.tenant_id
from public.sys_role r cross join public.sys_menu m
where r.enabled
  and r.role_code in ('R_SUPER', 'R_ADMIN', 'YQ_ADMIN')
  and m.name = 'WorkflowMonitor'
on conflict (role_id, menu_id) do nothing;
