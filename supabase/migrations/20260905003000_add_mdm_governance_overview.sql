begin;

create or replace function public.mdm_get_governance_overview_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  tenant_value uuid;
  is_super boolean;
  result_value jsonb;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  tenant_value := app_private.current_user_tenant_id();
  is_super := app_private.is_platform_super();

  with visible as materialized (
    select *
    from app_private.mdm_catalog_projection
    where is_super or tenant_id = tenant_value
  ),
  domain_counts as (
    select
      domain_key,
      count(*)::integer as record_count,
      count(*) filter (where is_active)::integer as active_count,
      count(*) filter (where quality_score < 90)::integer as attention_count
    from visible
    group by domain_key
  )
  select jsonb_build_object(
    'domains', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', domain_key,
        'recordCount', record_count,
        'activeCount', active_count,
        'attentionCount', attention_count
      ) order by domain_key)
      from domain_counts
    ), '[]'::jsonb),
    'summary', jsonb_build_object(
      'total', (select count(*) from visible),
      'active', (select count(*) from visible where is_active),
      'attention', (select count(*) from visible where quality_score < 90),
      'averageScore', coalesce((select round(avg(quality_score))::integer from visible), 0)
    )
  ) into result_value;

  return result_value;
end;
$$;

comment on function public.mdm_get_governance_overview_secure() is
  'Returns tenant-safe MDM governance counts across the five business domains.';

revoke all on function public.mdm_get_governance_overview_secure()
  from public, anon, authenticated;
grant execute on function public.mdm_get_governance_overview_secure()
  to authenticated, service_role;

commit;
