-- Close the legacy lifecycle mutation path now that task execution is handled by
-- hr_transition_lifecycle_task_secure, and cover the composite template FK in
-- the same column order used by PostgreSQL's referential checks.

create index if not exists hr_lifecycle_template_task_template_fk_idx
  on public.hr_lifecycle_template_task(template_id, tenant_id);

revoke execute on function public.hr_complete_lifecycle_task(uuid, text, boolean)
  from public, anon, authenticated;
