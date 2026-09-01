create or replace function app_private.act_workflow_by_business(
  p_business_type text,
  p_business_id uuid,
  p_action text,
  p_comment text,
  p_idempotency_key text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task_id uuid;
  v_user_id uuid := (select app_private.current_app_user_id());
  v_tenant_id uuid := (select app_private.current_user_tenant_id());
begin
  if (select auth.uid()) is null or v_user_id is null then
    raise exception '当前登录用户未绑定业务账号';
  end if;

  select t.id into v_task_id
  from public.wf_task t
  join public.wf_instance i on i.id = t.instance_id
  where i.tenant_id = v_tenant_id
    and i.business_type = p_business_type
    and i.business_id = p_business_id
    and i.status = 'running'
    and t.status = 'pending'
    and t.assignee_user_id = v_user_id
    and t.node_key = i.current_node_key
  order by t.create_time
  limit 1
  for update of t;

  if not found then
    raise exception '当前用户没有该业务单据的待审批任务';
  end if;

  return app_private.act_workflow_task(
    v_task_id,
    p_action,
    p_comment,
    p_idempotency_key
  );
end;
$$;
revoke execute on function app_private.act_workflow_by_business(text, uuid, text, text, text)
  from public, anon;
grant execute on function app_private.act_workflow_by_business(text, uuid, text, text, text)
  to authenticated, service_role;
create or replace function public.act_workflow_by_business(
  p_business_type text,
  p_business_id uuid,
  p_action text,
  p_comment text default null,
  p_idempotency_key text default null
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select app_private.act_workflow_by_business(
    p_business_type,
    p_business_id,
    p_action,
    p_comment,
    p_idempotency_key
  )
$$;
revoke all on function public.act_workflow_by_business(text, uuid, text, text, text)
  from public, anon;
grant execute on function public.act_workflow_by_business(text, uuid, text, text, text)
  to authenticated, service_role;
