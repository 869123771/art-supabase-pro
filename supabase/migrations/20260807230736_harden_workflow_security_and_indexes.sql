-- Keep elevated workflow snapshot reads outside the exposed API schema and
-- cover workflow assignment foreign keys used by joins and cleanup checks.

alter function public.get_workflow_business_snapshot(uuid)
  set schema app_private;

create function public.get_workflow_business_snapshot(p_instance_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $function$
  select app_private.get_workflow_business_snapshot(p_instance_id)
$function$;

revoke all on function app_private.get_workflow_business_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function app_private.get_workflow_business_snapshot(uuid)
  to authenticated, service_role;

revoke all on function public.get_workflow_business_snapshot(uuid)
  from public, anon, authenticated;
grant execute on function public.get_workflow_business_snapshot(uuid)
  to authenticated, service_role;

create index if not exists wf_delegation_delegate_user_id_idx
  on public.wf_delegation(delegate_user_id);

create index if not exists wf_delegation_delegator_user_id_idx
  on public.wf_delegation(delegator_user_id);

create index if not exists wf_delegation_revoked_by_idx
  on public.wf_delegation(revoked_by);

create index if not exists wf_task_last_assigned_by_idx
  on public.wf_task(last_assigned_by);;
