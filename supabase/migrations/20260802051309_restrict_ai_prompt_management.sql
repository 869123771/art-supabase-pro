drop policy if exists tenant_insert on public.ai_prompt_template;
create policy tenant_insert
on public.ai_prompt_template
for insert
to authenticated
with check ((select app_private.is_platform_super()));

drop policy if exists tenant_update on public.ai_prompt_template;
create policy tenant_update
on public.ai_prompt_template
for update
to authenticated
using ((select app_private.is_platform_super()))
with check ((select app_private.is_platform_super()));

drop policy if exists tenant_delete on public.ai_prompt_template;
create policy tenant_delete
on public.ai_prompt_template
for delete
to authenticated
using (
  status = 'draft'
  and (select app_private.is_platform_super())
);

create or replace function public.publish_ai_prompt_template(p_prompt_id uuid)
returns public.ai_prompt_template
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target_prompt public.ai_prompt_template;
  published_prompt public.ai_prompt_template;
  publisher_email text;
begin
  if not (select app_private.is_platform_super()) then
    raise exception 'Only platform super administrators can publish AI prompts'
      using errcode = '42501';
  end if;

  select prompt.*
  into target_prompt
  from public.ai_prompt_template prompt
  where prompt.id = p_prompt_id
  for update;

  if target_prompt.id is null then
    raise exception 'AI prompt template was not found'
      using errcode = 'P0002';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext(target_prompt.tenant_id::text || ':' || target_prompt.feature)
  );

  publisher_email := coalesce(
    nullif(
      nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'email',
      ''
    ),
    'system'
  );

  update public.ai_prompt_template
  set
    status = 'archived',
    update_by = publisher_email
  where tenant_id = target_prompt.tenant_id
    and feature = target_prompt.feature
    and status = 'published'
    and id <> target_prompt.id;

  update public.ai_prompt_template
  set
    status = 'published',
    published_at = pg_catalog.now(),
    published_by = publisher_email,
    update_by = publisher_email
  where id = target_prompt.id
  returning * into published_prompt;

  update public.ai_feature_config
  set
    prompt_version = published_prompt.version,
    update_by = publisher_email
  where tenant_id = published_prompt.tenant_id
    and feature = published_prompt.feature;

  return published_prompt;
end;
$$;

comment on function public.publish_ai_prompt_template(uuid)
  is 'Publishes one prompt version for platform super administrators, archives the previous version, and syncs the runtime config version.';;
