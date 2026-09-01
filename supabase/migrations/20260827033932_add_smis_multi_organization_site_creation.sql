create or replace function public.smis_save_sites_secure(
  p_organization_ids uuid[],
  p_payload jsonb
)
returns uuid[]
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_organization_ids uuid[];
  v_organization_id uuid;
  v_result_ids uuid[] := array[]::uuid[];
  v_result_id uuid;
begin
  select array_agg(normalized.organization_id order by normalized.first_ordinal)
  into v_organization_ids
  from (
    select organization_id, min(ordinality) as first_ordinal
    from unnest(coalesce(p_organization_ids, array[]::uuid[]))
      with ordinality as selected(organization_id, ordinality)
    where organization_id is not null
    group by organization_id
  ) normalized;

  if coalesce(cardinality(v_organization_ids), 0) = 0 then
    raise exception '请至少选择一个所属部门' using errcode = '22023';
  end if;
  if cardinality(v_organization_ids) > 50 then
    raise exception '单次最多选择 50 个所属部门' using errcode = '22023';
  end if;

  foreach v_organization_id in array v_organization_ids loop
    v_result_id := public.smis_save_site_secure(
      null,
      (coalesce(p_payload, '{}'::jsonb) - 'organization_id' - 'organization_ids')
        || jsonb_build_object('organization_id', v_organization_id::text)
    );
    v_result_ids := array_append(v_result_ids, v_result_id);
  end loop;

  return v_result_ids;
end;
$function$;

revoke all on function public.smis_save_sites_secure(uuid[], jsonb)
  from public, anon;
grant execute on function public.smis_save_sites_secure(uuid[], jsonb)
  to authenticated, service_role;

comment on function public.smis_save_sites_secure(uuid[], jsonb) is
  '为选中的多个当前租户部门原子批量新增同一场所，复用单条场所安全写入边界。';

;
