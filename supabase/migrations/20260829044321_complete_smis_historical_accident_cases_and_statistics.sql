
create table if not exists public.smis_historical_accident_case (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  accident_name text not null check (char_length(btrim(accident_name)) between 1 and 160),
  accident_categories text[] not null default '{}'::text[] check (
    cardinality(accident_categories) > 0
    and accident_categories <@ array[
      'object_strike', 'other_injury', 'mechanical_injury', 'lifting_injury',
      'electric_shock', 'drowning', 'burn', 'fire', 'fall_from_height', 'collapse',
      'roof_fall', 'water_inrush', 'blasting', 'explosive_material', 'gas_explosion',
      'boiler_explosion', 'vessel_explosion', 'other_explosion',
      'poisoning_asphyxiation'
    ]::text[]
  ),
  accident_level text not null check (
    accident_level in ('near_miss', 'minor_injury', 'general', 'major', 'severe', 'catastrophic')
  ),
  accident_organization_id uuid,
  occurrence_date date not null,
  case_status text check (case_status is null or case_status in ('stopped', 'in_use')),
  applicable_company_id uuid,
  summary text check (summary is null or char_length(summary) <= 1000),
  content text not null check (char_length(btrim(content)) between 1 and 12000),
  image_urls text[] not null default '{}'::text[] check (cardinality(image_urls) <= 9),
  attachment_urls text[] not null default '{}'::text[] check (cardinality(attachment_urls) <= 8),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_historical_accident_case_tenant_id_fkey
    foreign key (tenant_id) references public.sys_tenant(id),
  constraint smis_historical_accident_case_accident_org_fkey
    foreign key (tenant_id, accident_organization_id)
    references public.sys_organization(tenant_id, id),
  constraint smis_historical_accident_case_company_fkey
    foreign key (tenant_id, applicable_company_id)
    references public.sys_organization(tenant_id, id),
  constraint smis_historical_accident_case_tenant_id_id_key unique (tenant_id, id)
);

comment on table public.smis_historical_accident_case is '租户级历史事故案例知识库';
comment on column public.smis_historical_accident_case.accident_categories is '事故类别字典值数组，支持多选';

create index if not exists smis_historical_accident_case_tenant_date_idx
  on public.smis_historical_accident_case(tenant_id, occurrence_date desc);
create index if not exists smis_historical_accident_case_tenant_level_idx
  on public.smis_historical_accident_case(tenant_id, accident_level);
create index if not exists smis_historical_accident_case_accident_org_idx
  on public.smis_historical_accident_case(tenant_id, accident_organization_id);
create index if not exists smis_historical_accident_case_company_idx
  on public.smis_historical_accident_case(tenant_id, applicable_company_id);
create index if not exists smis_historical_accident_case_categories_gin_idx
  on public.smis_historical_accident_case using gin(accident_categories);

drop trigger if exists smis_historical_accident_case_create_audit
  on public.smis_historical_accident_case;
create trigger smis_historical_accident_case_create_audit
before insert on public.smis_historical_accident_case
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists smis_historical_accident_case_update_audit
  on public.smis_historical_accident_case;
create trigger smis_historical_accident_case_update_audit
before update on public.smis_historical_accident_case
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_historical_accident_case enable row level security;

drop policy if exists smis_historical_accident_case_tenant_select
  on public.smis_historical_accident_case;
create policy smis_historical_accident_case_tenant_select
on public.smis_historical_accident_case
for select to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisHistoricalAccidentCases:View')
);

drop policy if exists smis_historical_accident_case_tenant_insert
  on public.smis_historical_accident_case;
create policy smis_historical_accident_case_tenant_insert
on public.smis_historical_accident_case
for insert to authenticated
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisHistoricalAccidentCases:Add')
);

drop policy if exists smis_historical_accident_case_tenant_update
  on public.smis_historical_accident_case;
create policy smis_historical_accident_case_tenant_update
on public.smis_historical_accident_case
for update to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisHistoricalAccidentCases:Edit')
)
with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisHistoricalAccidentCases:Edit')
);

drop policy if exists smis_historical_accident_case_tenant_delete
  on public.smis_historical_accident_case;
create policy smis_historical_accident_case_tenant_delete
on public.smis_historical_accident_case
for delete to authenticated
using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisHistoricalAccidentCases:Delete')
);

grant select, insert, update, delete on table public.smis_historical_accident_case to authenticated;

create or replace function public.smis_list_historical_accident_cases_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_accident_level text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_ids uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_read_tenant uuid := app_private.current_read_tenant_id();
  v_records jsonb;
  v_total bigint;
  v_overview jsonb;
  v_organizations jsonb;
begin
  if auth.uid() is null then
    raise exception '请先登录后再查看历史事故案例';
  end if;
  if not app_private.has_permission('SmisHistoricalAccidentCases:View') then
    raise exception '当前账号无权查看历史事故案例';
  end if;
  if p_start_date is not null and p_end_date is not null and p_start_date > p_end_date then
    raise exception '发生日期开始值不能晚于结束值';
  end if;

  with filtered as materialized (
    select
      c.*,
      accident_org.organization_name as accident_organization_name,
      company.organization_name as applicable_company_name
    from public.smis_historical_accident_case c
    left join public.sys_organization accident_org
      on accident_org.id = c.accident_organization_id
     and accident_org.tenant_id = c.tenant_id
    left join public.sys_organization company
      on company.id = c.applicable_company_id
     and company.tenant_id = c.tenant_id
    where (v_read_tenant is null or c.tenant_id = v_read_tenant)
      and (p_ids is null or c.id = any(p_ids))
      and (
        nullif(btrim(p_keyword), '') is null
        or c.accident_name ilike '%' || btrim(p_keyword) || '%'
      )
      and (p_accident_level is null or c.accident_level = p_accident_level)
      and (p_start_date is null or c.occurrence_date >= p_start_date)
      and (p_end_date is null or c.occurrence_date <= p_end_date)
  ),
  paged as materialized (
    select *
    from filtered
    order by occurrence_date desc, id desc
    offset greatest(coalesce(p_from, 0), 0)
    limit least(
      greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 0),
      5000
    )
  )
  select
    (select count(*) from filtered),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', p.id,
          'accidentName', p.accident_name,
          'accidentCategories', p.accident_categories,
          'accidentLevel', p.accident_level,
          'accidentOrganizationId', p.accident_organization_id,
          'accidentOrganizationName', p.accident_organization_name,
          'occurrenceDate', p.occurrence_date,
          'caseStatus', p.case_status,
          'applicableCompanyId', p.applicable_company_id,
          'applicableCompanyName', p.applicable_company_name,
          'summary', p.summary,
          'content', p.content,
          'imageUrls', p.image_urls,
          'attachmentUrls', p.attachment_urls,
          'createBy', p.create_by,
          'createTime', p.create_time,
          'updateBy', p.update_by,
          'updateTime', p.update_time
        )
        order by p.occurrence_date desc, p.id desc
      ),
      '[]'::jsonb
    )
  into v_total, v_records
  from paged p;

  select jsonb_build_object(
    'total', count(*),
    'inUse', count(*) filter (where c.case_status = 'in_use'),
    'currentYear', count(*) filter (
      where extract(year from c.occurrence_date) = extract(year from current_date)
    ),
    'highSeverity', count(*) filter (
      where c.accident_level in ('major', 'severe', 'catastrophic')
    )
  )
  into v_overview
  from public.smis_historical_accident_case c
  where (v_read_tenant is null or c.tenant_id = v_read_tenant);

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'parentId', o.parent_id,
        'organizationCode', o.organization_code,
        'organizationName', o.organization_name,
        'organizationType', o.organization_type,
        'sort', o.sort,
        'children', '[]'::jsonb
      )
      order by o.sort, o.organization_name
    ),
    '[]'::jsonb
  )
  into v_organizations
  from public.sys_organization o
  where (v_read_tenant is null or o.tenant_id = v_read_tenant)
    and o.status = '1';

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'overview', coalesce(
      v_overview,
      jsonb_build_object('total', 0, 'inUse', 0, 'currentYear', 0, 'highSeverity', 0)
    ),
    'organizations', v_organizations
  );
end;
$function$;

create or replace function public.smis_save_historical_accident_case_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_id uuid;
  v_name text := btrim(coalesce(p_payload->>'accident_name', ''));
  v_categories text[] := array(
    select jsonb_array_elements_text(coalesce(p_payload->'accident_categories', '[]'::jsonb))
  );
  v_level text := p_payload->>'accident_level';
  v_accident_org_id uuid := nullif(p_payload->>'accident_organization_id', '')::uuid;
  v_occurrence_date date := nullif(p_payload->>'occurrence_date', '')::date;
  v_status text := nullif(p_payload->>'case_status', '');
  v_company_id uuid := nullif(p_payload->>'applicable_company_id', '')::uuid;
  v_summary text := nullif(btrim(coalesce(p_payload->>'summary', '')), '');
  v_content text := btrim(coalesce(p_payload->>'content', ''));
  v_image_urls text[] := array(
    select jsonb_array_elements_text(coalesce(p_payload->'image_urls', '[]'::jsonb))
  );
  v_attachment_urls text[] := array(
    select jsonb_array_elements_text(coalesce(p_payload->'attachment_urls', '[]'::jsonb))
  );
begin
  if auth.uid() is null then
    raise exception '请先登录后再维护历史事故案例';
  end if;
  if p_id is null and not app_private.has_permission('SmisHistoricalAccidentCases:Add') then
    raise exception '当前账号无权新增历史事故案例';
  end if;
  if p_id is not null and not app_private.has_permission('SmisHistoricalAccidentCases:Edit') then
    raise exception '当前账号无权编辑历史事故案例';
  end if;

  v_tenant := app_private.resolve_mutation_tenant_id((
    select target.tenant_id
    from public.smis_historical_accident_case target
    where target.id = p_id
  ));

  if v_name = '' then raise exception '请输入事故名称'; end if;
  if char_length(v_name) > 160 then raise exception '事故名称不能超过 160 个字符'; end if;
  if cardinality(v_categories) = 0 or not v_categories <@ array[
    'object_strike', 'other_injury', 'mechanical_injury', 'lifting_injury',
    'electric_shock', 'drowning', 'burn', 'fire', 'fall_from_height', 'collapse',
    'roof_fall', 'water_inrush', 'blasting', 'explosive_material', 'gas_explosion',
    'boiler_explosion', 'vessel_explosion', 'other_explosion',
    'poisoning_asphyxiation'
  ]::text[] then
    raise exception '请选择有效的事故类别';
  end if;
  if v_level not in ('near_miss', 'minor_injury', 'general', 'major', 'severe', 'catastrophic') then
    raise exception '请选择有效的事故级别';
  end if;
  if v_occurrence_date is null then raise exception '请选择发生日期'; end if;
  if v_status is not null and v_status not in ('stopped', 'in_use') then
    raise exception '请选择有效的案例状态';
  end if;
  if v_content = '' then raise exception '请输入案例正文'; end if;
  if char_length(v_content) > 12000 then raise exception '案例正文不能超过 12000 个字符'; end if;
  if v_summary is not null and char_length(v_summary) > 1000 then
    raise exception '案例概述不能超过 1000 个字符';
  end if;
  if cardinality(v_image_urls) > 9 then raise exception '事故图片不能超过 9 张'; end if;
  if cardinality(v_attachment_urls) > 8 then raise exception '案例附件不能超过 8 个'; end if;
  if v_accident_org_id is not null and not exists(
    select 1
    from public.sys_organization o
    where o.id = v_accident_org_id
      and o.tenant_id = v_tenant
      and o.status = '1'
  ) then
    raise exception '请选择当前租户有效的事故单位';
  end if;
  if v_company_id is not null and not exists(
    select 1
    from public.sys_organization o
    where o.id = v_company_id
      and o.tenant_id = v_tenant
      and o.status = '1'
  ) then
    raise exception '请选择当前租户有效的适用公司';
  end if;

  if p_id is null then
    insert into public.smis_historical_accident_case(
      tenant_id,
      accident_name,
      accident_categories,
      accident_level,
      accident_organization_id,
      occurrence_date,
      case_status,
      applicable_company_id,
      summary,
      content,
      image_urls,
      attachment_urls
    )
    values (
      v_tenant,
      v_name,
      v_categories,
      v_level,
      v_accident_org_id,
      v_occurrence_date,
      v_status,
      v_company_id,
      v_summary,
      v_content,
      v_image_urls,
      v_attachment_urls
    )
    returning id into v_id;
  else
    update public.smis_historical_accident_case
    set accident_name = v_name,
        accident_categories = v_categories,
        accident_level = v_level,
        accident_organization_id = v_accident_org_id,
        occurrence_date = v_occurrence_date,
        case_status = v_status,
        applicable_company_id = v_company_id,
        summary = v_summary,
        content = v_content,
        image_urls = v_image_urls,
        attachment_urls = v_attachment_urls
    where id = p_id
      and tenant_id = v_tenant
    returning id into v_id;

    if v_id is null then
      raise exception '历史事故案例不存在或不属于当前租户';
    end if;
  end if;

  return v_id;
end;
$function$;

create or replace function public.smis_delete_historical_accident_cases_secure(
  p_ids uuid[]
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_count integer;
begin
  if auth.uid() is null then
    raise exception '请先登录后再删除历史事故案例';
  end if;
  if not app_private.has_permission('SmisHistoricalAccidentCases:Delete') then
    raise exception '当前账号无权删除历史事故案例';
  end if;

  delete from public.smis_historical_accident_case
  where id = any(coalesce(p_ids, '{}'::uuid[]))
    and (app_private.is_platform_super() or tenant_id = v_tenant);

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

create or replace function public.smis_get_safety_accident_statistics_secure(
  p_start_date date default null,
  p_end_date date default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_read_tenant uuid := app_private.current_read_tenant_id();
  v_start_date date := coalesce(p_start_date, date_trunc('year', current_date)::date);
  v_end_date date := coalesce(p_end_date, current_date);
  v_overview jsonb;
  v_trend jsonb;
  v_levels jsonb;
  v_categories jsonb;
  v_organizations jsonb;
  v_organization_options jsonb;
begin
  if auth.uid() is null then
    raise exception '请先登录后再查看安全事故统计';
  end if;
  if not app_private.has_permission('SmisSafetyAccidentStatistics:View') then
    raise exception '当前账号无权查看安全事故统计';
  end if;
  if v_start_date > v_end_date then
    raise exception '统计开始日期不能晚于结束日期';
  end if;
  if p_organization_id is not null and not exists(
    select 1
    from public.sys_organization o
    where o.id = p_organization_id
      and (v_read_tenant is null or o.tenant_id = v_read_tenant)
  ) then
    raise exception '所选事故发生组织不存在或不属于当前租户';
  end if;

  with recursive organization_scope as (
    select o.id, o.tenant_id
    from public.sys_organization o
    where o.id = p_organization_id
      and (v_read_tenant is null or o.tenant_id = v_read_tenant)
    union all
    select child.id, child.tenant_id
    from public.sys_organization child
    join organization_scope parent
      on child.parent_id = parent.id
     and child.tenant_id = parent.tenant_id
  ),
  filtered as materialized (
    select r.*
    from public.smis_accident_report r
    where (v_read_tenant is null or r.tenant_id = v_read_tenant)
      and r.accident_time::date between v_start_date and v_end_date
      and (
        p_organization_id is null
        or (r.operation_area_organization_id, r.tenant_id) in (
          select scope.id, scope.tenant_id from organization_scope scope
        )
      )
  )
  select jsonb_build_object(
    'total', count(*),
    'currentYear', count(*) filter (
      where extract(year from accident_time) = extract(year from current_date)
    ),
    'highSeverity', count(*) filter (
      where accident_level in ('major', 'severe', 'catastrophic')
    ),
    'affectedPeople', coalesce(sum((
      select count(*)
      from public.smis_accident_person person
      where person.accident_report_id = filtered.id
        and person.tenant_id = filtered.tenant_id
    )), 0)
  )
  into v_overview
  from filtered;

  with recursive organization_scope as (
    select o.id, o.tenant_id
    from public.sys_organization o
    where o.id = p_organization_id
      and (v_read_tenant is null or o.tenant_id = v_read_tenant)
    union all
    select child.id, child.tenant_id
    from public.sys_organization child
    join organization_scope parent
      on child.parent_id = parent.id
     and child.tenant_id = parent.tenant_id
  ),
  months as (
    select generate_series(
      date_trunc('month', v_start_date::timestamp),
      date_trunc('month', v_end_date::timestamp),
      interval '1 month'
    )::date as period
  ),
  grouped as (
    select date_trunc('month', r.accident_time)::date as period, count(*)::integer as count
    from public.smis_accident_report r
    where (v_read_tenant is null or r.tenant_id = v_read_tenant)
      and r.accident_time::date between v_start_date and v_end_date
      and (
        p_organization_id is null
        or (r.operation_area_organization_id, r.tenant_id) in (
          select scope.id, scope.tenant_id from organization_scope scope
        )
      )
    group by date_trunc('month', r.accident_time)::date
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'period', to_char(months.period, 'YYYY-MM'),
        'label', to_char(months.period, 'YYYY年MM月'),
        'count', coalesce(grouped.count, 0)
      )
      order by months.period
    ),
    '[]'::jsonb
  )
  into v_trend
  from months
  left join grouped on grouped.period = months.period;

  with recursive organization_scope as (
    select o.id, o.tenant_id
    from public.sys_organization o
    where o.id = p_organization_id
      and (v_read_tenant is null or o.tenant_id = v_read_tenant)
    union all
    select child.id, child.tenant_id
    from public.sys_organization child
    join organization_scope parent
      on child.parent_id = parent.id
     and child.tenant_id = parent.tenant_id
  ),
  grouped as (
    select r.accident_level as value, count(*)::integer as count
    from public.smis_accident_report r
    where (v_read_tenant is null or r.tenant_id = v_read_tenant)
      and r.accident_time::date between v_start_date and v_end_date
      and (
        p_organization_id is null
        or (r.operation_area_organization_id, r.tenant_id) in (
          select scope.id, scope.tenant_id from organization_scope scope
        )
      )
    group by r.accident_level
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object('value', grouped.value, 'count', grouped.count)
      order by array_position(
        array['near_miss', 'minor_injury', 'general', 'major', 'severe', 'catastrophic'],
        grouped.value
      )
    ),
    '[]'::jsonb
  )
  into v_levels
  from grouped;

  with recursive organization_scope as (
    select o.id, o.tenant_id
    from public.sys_organization o
    where o.id = p_organization_id
      and (v_read_tenant is null or o.tenant_id = v_read_tenant)
    union all
    select child.id, child.tenant_id
    from public.sys_organization child
    join organization_scope parent
      on child.parent_id = parent.id
     and child.tenant_id = parent.tenant_id
  ),
  grouped as (
    select category as value, count(*)::integer as count
    from public.smis_accident_report r
    cross join lateral unnest(r.accident_categories) category
    where (v_read_tenant is null or r.tenant_id = v_read_tenant)
      and r.accident_time::date between v_start_date and v_end_date
      and (
        p_organization_id is null
        or (r.operation_area_organization_id, r.tenant_id) in (
          select scope.id, scope.tenant_id from organization_scope scope
        )
      )
    group by category
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object('value', grouped.value, 'count', grouped.count)
      order by grouped.count desc, grouped.value
    ),
    '[]'::jsonb
  )
  into v_categories
  from grouped;

  with recursive organization_scope as (
    select o.id, o.tenant_id
    from public.sys_organization o
    where o.id = p_organization_id
      and (v_read_tenant is null or o.tenant_id = v_read_tenant)
    union all
    select child.id, child.tenant_id
    from public.sys_organization child
    join organization_scope parent
      on child.parent_id = parent.id
     and child.tenant_id = parent.tenant_id
  ),
  grouped as (
    select
      r.operation_area_organization_id as organization_id,
      r.tenant_id,
      count(*)::integer as count,
      count(*) filter (
        where r.accident_level in ('major', 'severe', 'catastrophic')
      )::integer as high_severity
    from public.smis_accident_report r
    where (v_read_tenant is null or r.tenant_id = v_read_tenant)
      and r.accident_time::date between v_start_date and v_end_date
      and (
        p_organization_id is null
        or (r.operation_area_organization_id, r.tenant_id) in (
          select scope.id, scope.tenant_id from organization_scope scope
        )
      )
    group by r.operation_area_organization_id, r.tenant_id
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'organizationId', grouped.organization_id,
        'organizationName', coalesce(o.organization_name, '未归属组织'),
        'count', grouped.count,
        'highSeverity', grouped.high_severity
      )
      order by grouped.count desc, coalesce(o.organization_name, '未归属组织')
    ),
    '[]'::jsonb
  )
  into v_organizations
  from grouped
  left join public.sys_organization o
    on o.id = grouped.organization_id
   and o.tenant_id = grouped.tenant_id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', o.id,
        'parentId', o.parent_id,
        'organizationCode', o.organization_code,
        'organizationName', o.organization_name,
        'organizationType', o.organization_type,
        'sort', o.sort,
        'children', '[]'::jsonb
      )
      order by o.sort, o.organization_name
    ),
    '[]'::jsonb
  )
  into v_organization_options
  from public.sys_organization o
  where (v_read_tenant is null or o.tenant_id = v_read_tenant)
    and o.status = '1';

  return jsonb_build_object(
    'overview', coalesce(
      v_overview,
      jsonb_build_object('total', 0, 'currentYear', 0, 'highSeverity', 0, 'affectedPeople', 0)
    ),
    'trend', v_trend,
    'levels', v_levels,
    'categories', v_categories,
    'organizations', v_organizations,
    'organizationOptions', v_organization_options
  );
end;
$function$;

revoke all on function public.smis_list_historical_accident_cases_secure(
  integer, integer, text, text, date, date, uuid[]
) from public;
revoke all on function public.smis_save_historical_accident_case_secure(uuid, jsonb) from public;
revoke all on function public.smis_delete_historical_accident_cases_secure(uuid[]) from public;
revoke all on function public.smis_get_safety_accident_statistics_secure(date, date, uuid) from public;

grant execute on function public.smis_list_historical_accident_cases_secure(
  integer, integer, text, text, date, date, uuid[]
) to authenticated;
grant execute on function public.smis_save_historical_accident_case_secure(uuid, jsonb)
  to authenticated;
grant execute on function public.smis_delete_historical_accident_cases_secure(uuid[])
  to authenticated;
grant execute on function public.smis_get_safety_accident_statistics_secure(date, date, uuid)
  to authenticated;

insert into public.sys_dict_type(
  name, code, status, create_by, update_by, tenant_id, node_type, sort
)
values (
  '事故案例状态',
  'smisAccidentCaseStatus',
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  app_private.platform_tenant_id(),
  'dictionary',
  0
)
on conflict (code) do update
set name = excluded.name,
    status = excluded.status,
    update_by = excluded.update_by,
    update_time = now();

do $block$
declare
  v_type_id uuid;
  v_tenant_id uuid := app_private.platform_tenant_id();
begin
  select id into v_type_id
  from public.sys_dict_type
  where code = 'smisAccidentCaseStatus';

  update public.sys_dictionary
  set label = '已停止',
      code = 'stopped',
      status = '1',
      sort = 1,
      tag_type = 'info',
      update_by = '624944977@qq.com',
      update_time = now(),
      tenant_id = v_tenant_id
  where type_id = v_type_id and value = 'stopped';

  if not found then
    insert into public.sys_dictionary(
      type_id, code, value, label, status, sort, tag_type,
      create_by, update_by, tenant_id
    )
    values (
      v_type_id, 'stopped', 'stopped', '已停止', '1', 1, 'info',
      '624944977@qq.com', '624944977@qq.com', v_tenant_id
    );
  end if;

  update public.sys_dictionary
  set label = '使用中',
      code = 'in_use',
      status = '1',
      sort = 2,
      tag_type = 'success',
      update_by = '624944977@qq.com',
      update_time = now(),
      tenant_id = v_tenant_id
  where type_id = v_type_id and value = 'in_use';

  if not found then
    insert into public.sys_dictionary(
      type_id, code, value, label, status, sort, tag_type,
      create_by, update_by, tenant_id
    )
    values (
      v_type_id, 'in_use', 'in_use', '使用中', '1', 2, 'success',
      '624944977@qq.com', '624944977@qq.com', v_tenant_id
    );
  end if;
end;
$block$;

do $block$
declare
  v_case_menu uuid;
  v_statistics_menu uuid;
  v_definition record;
  v_button_id uuid;
begin
  select id into v_case_menu
  from public.sys_menu
  where name = 'SmisHistoricalAccidentCases'
  limit 1;

  select id into v_statistics_menu
  from public.sys_menu
  where name = 'SmisSafetyAccidentStatistics'
  limit 1;

  if v_case_menu is null or v_statistics_menu is null then
    raise exception '历史事故案例或安全事故统计菜单不存在';
  end if;

  for v_definition in
    select *
    from (
      values
        (v_case_menu, 'SmisHistoricalAccidentCases:View', '查看', 1),
        (v_case_menu, 'SmisHistoricalAccidentCases:Add', '新增', 2),
        (v_case_menu, 'SmisHistoricalAccidentCases:Edit', '编辑', 3),
        (v_case_menu, 'SmisHistoricalAccidentCases:Delete', '删除', 4),
        (v_case_menu, 'SmisHistoricalAccidentCases:Export', '导出', 5),
        (v_statistics_menu, 'SmisSafetyAccidentStatistics:View', '查看', 1)
    ) as definitions(parent_id, name, title, sort)
  loop
    select id into v_button_id
    from public.sys_menu
    where name = v_definition.name
    limit 1;

    if v_button_id is null then
      insert into public.sys_menu(
        name, path, component, meta, sort, create_by, update_by,
        parent_id, type, app_code
      )
      values (
        v_definition.name,
        '',
        '',
        jsonb_build_object(
          'roles', '[]'::jsonb,
          'title', v_definition.title,
          'is_hide', true,
          'is_enable', true
        ),
        v_definition.sort,
        '624944977@qq.com',
        '624944977@qq.com',
        v_definition.parent_id,
        'button',
        'smis'
      )
      returning id into v_button_id;
    else
      update public.sys_menu
      set parent_id = v_definition.parent_id,
          path = '',
          component = '',
          meta = jsonb_build_object(
            'roles', '[]'::jsonb,
            'title', v_definition.title,
            'is_hide', true,
            'is_enable', true
          ),
          sort = v_definition.sort,
          type = 'button',
          app_code = 'smis',
          update_by = '624944977@qq.com',
          update_time = now()
      where id = v_button_id;
    end if;

    insert into public.sys_role_menu(
      role_id, menu_id, tenant_id, permission, create_by, update_by
    )
    select
      parent_grant.role_id,
      v_button_id,
      parent_grant.tenant_id,
      '{}'::jsonb,
      '624944977@qq.com',
      '624944977@qq.com'
    from public.sys_role_menu parent_grant
    where parent_grant.menu_id = v_definition.parent_id
    on conflict (role_id, menu_id) do nothing;
  end loop;
end;
$block$;
;
