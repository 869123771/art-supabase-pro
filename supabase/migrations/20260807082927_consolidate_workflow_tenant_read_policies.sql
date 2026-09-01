-- Tenant-wide read access subsumes the older participant-only policies.
-- Keep one permissive SELECT policy per table so Postgres evaluates the
-- authorization predicate once per row.

drop policy if exists participant_select on public.wf_instance;
drop policy if exists participant_select on public.wf_task;
drop policy if exists participant_select on public.wf_action;

;
