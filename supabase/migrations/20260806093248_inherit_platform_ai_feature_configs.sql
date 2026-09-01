-- Platform AI configuration is the default catalog. A tenant row with the
-- same feature is an explicit override, including an explicit disabled state.
-- Configuration rows contain no provider secrets, so authenticated tenants may
-- read platform defaults while writes remain platform-super only.
drop policy if exists tenant_select on public.ai_feature_config;
create policy tenant_select
on public.ai_feature_config
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
  or tenant_id = (select app_private.platform_tenant_id())
);
create or replace function public.get_effective_ai_feature_configs()
returns table (
  id uuid,
  tenant_id uuid,
  source_tenant_id uuid,
  inherited boolean,
  feature text,
  enabled boolean,
  provider text,
  model text,
  vision_model text,
  fallback_model text,
  timeout_ms integer,
  max_retries smallint,
  temperature numeric,
  max_tokens integer,
  rate_limit_per_minute integer,
  rate_limit_per_day integer,
  prompt_version text,
  metadata jsonb,
  create_by text,
  create_time timestamptz,
  update_by text,
  update_time timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  with request_context as (
    select
      app_private.current_user_tenant_id() as current_tenant_id,
      app_private.platform_tenant_id() as platform_tenant_id
  ),
  ranked as (
    select
      config.*,
      context.current_tenant_id,
      row_number() over (
        partition by config.feature
        order by
          case when config.tenant_id = context.current_tenant_id then 0 else 1 end,
          config.update_time desc,
          config.id
      ) as priority
    from public.ai_feature_config as config
    cross join request_context as context
    where config.tenant_id in (context.current_tenant_id, context.platform_tenant_id)
  )
  select
    ranked.id,
    ranked.current_tenant_id as tenant_id,
    ranked.tenant_id as source_tenant_id,
    ranked.tenant_id <> ranked.current_tenant_id as inherited,
    ranked.feature,
    ranked.enabled,
    ranked.provider,
    ranked.model,
    ranked.vision_model,
    ranked.fallback_model,
    ranked.timeout_ms,
    ranked.max_retries,
    ranked.temperature,
    ranked.max_tokens,
    ranked.rate_limit_per_minute,
    ranked.rate_limit_per_day,
    ranked.prompt_version,
    ranked.metadata,
    ranked.create_by,
    ranked.create_time,
    ranked.update_by,
    ranked.update_time
  from ranked
  where ranked.priority = 1
  order by ranked.feature;
$$;
comment on function public.get_effective_ai_feature_configs() is
  'Returns current-tenant AI overrides merged over platform defaults.';
revoke execute on function public.get_effective_ai_feature_configs()
  from public, anon, service_role;
grant execute on function public.get_effective_ai_feature_configs()
  to authenticated;
