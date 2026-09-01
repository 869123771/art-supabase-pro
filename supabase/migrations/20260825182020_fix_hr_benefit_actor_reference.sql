-- Map the authentication subject to the business user record before writing
-- benefit audit events. The audit FK references the globally unique business
-- user id and can safely null only that column when a user is removed.
alter table public.hr_benefit_event
  drop constraint if exists hr_benefit_event_actor_fkey;
alter table public.hr_benefit_event
  add constraint hr_benefit_event_actor_fkey foreign key (actor_user_id)
    references public.sys_user(id) on delete set null;

create or replace function app_private.hr_add_benefit_event(
  p_tenant_id uuid,
  p_entity_type text,
  p_entity_id uuid,
  p_event_type text,
  p_from_status text,
  p_to_status text,
  p_summary text,
  p_payload jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.hr_benefit_event(
    tenant_id, entity_type, entity_id, event_type, from_status, to_status,
    summary, payload, actor_user_id, actor_name
  ) values (
    p_tenant_id, p_entity_type, p_entity_id, p_event_type,
    p_from_status, p_to_status, p_summary, coalesce(p_payload, '{}'::jsonb),
    (select app_user.id from public.sys_user app_user
      where app_user.auth_user_id = auth.uid()
        and app_user.tenant_id = p_tenant_id
        and app_user.deleted_at is null
      limit 1),
    coalesce(auth.jwt() ->> 'email', auth.uid()::text)
  );
end
$function$;

revoke all on function app_private.hr_add_benefit_event(
  uuid, text, uuid, text, text, text, text, jsonb
) from public, anon, authenticated;

;
