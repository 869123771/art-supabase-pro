-- Cover workflow foreign keys used by detail joins, deletes, and audit lookups.
create index if not exists wf_definition_current_version_id_idx
  on public.wf_definition(current_version_id)
  where current_version_id is not null;
create index if not exists wf_instance_definition_id_idx
  on public.wf_instance(definition_id);
create index if not exists wf_instance_version_id_idx
  on public.wf_instance(version_id);
create index if not exists wf_action_task_id_idx
  on public.wf_action(task_id)
  where task_id is not null;
create index if not exists wf_action_actor_user_id_idx
  on public.wf_action(actor_user_id)
  where actor_user_id is not null;
