begin;
create table if not exists public.smis_violation_category (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  parent_id uuid,
  category_code text not null,
  category_name text not null,
  sort integer not null default 10,
  status text not null default 'enabled',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_violation_category_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_violation_category_id_tenant_key unique (id, tenant_id),
  constraint smis_violation_category_parent_fkey foreign key (parent_id, tenant_id)
    references public.smis_violation_category(id, tenant_id) on delete restrict,
  constraint smis_violation_category_parent_check check (parent_id is null or parent_id <> id),
  constraint smis_violation_category_code_check check (
    btrim(category_code) <> '' and char_length(category_code) <= 40
  ),
  constraint smis_violation_category_name_check check (
    btrim(category_name) <> '' and char_length(category_name) <= 100
  ),
  constraint smis_violation_category_sort_check check (sort between 0 and 999999),
  constraint smis_violation_category_status_check check (status in ('enabled', 'disabled')),
  constraint smis_violation_category_description_check check (
    description is null or char_length(description) <= 1000
  )
);
create unique index if not exists smis_violation_category_code_unique
  on public.smis_violation_category(tenant_id, upper(category_code));
create unique index if not exists smis_violation_category_sibling_name_unique
  on public.smis_violation_category(
    tenant_id,
    coalesce(parent_id, '00000000-0000-0000-0000-000000000000'::uuid),
    lower(category_name)
  );
create index if not exists smis_violation_category_parent_idx
  on public.smis_violation_category(tenant_id, parent_id, sort);
create table if not exists public.smis_anti_violation_standard (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  category_id uuid not null,
  standard_code text not null,
  standard_name text not null,
  deduction_points numeric(10, 2) not null default 0,
  handling_requirements text,
  legal_basis text,
  status text not null default 'enabled',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_anti_violation_standard_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_anti_violation_standard_id_tenant_key unique (id, tenant_id),
  constraint smis_anti_violation_standard_category_fkey foreign key (category_id, tenant_id)
    references public.smis_violation_category(id, tenant_id) on delete restrict,
  constraint smis_anti_violation_standard_code_check check (
    btrim(standard_code) <> '' and char_length(standard_code) <= 50
  ),
  constraint smis_anti_violation_standard_name_check check (
    btrim(standard_name) <> '' and char_length(standard_name) <= 500
  ),
  constraint smis_anti_violation_standard_points_check check (
    deduction_points between 0 and 99999999.99
  ),
  constraint smis_anti_violation_standard_status_check check (status in ('enabled', 'disabled')),
  constraint smis_anti_violation_standard_handling_check check (
    handling_requirements is null or char_length(handling_requirements) <= 2000
  ),
  constraint smis_anti_violation_standard_basis_check check (
    legal_basis is null or char_length(legal_basis) <= 1000
  ),
  constraint smis_anti_violation_standard_description_check check (
    description is null or char_length(description) <= 1000
  )
);
create unique index if not exists smis_anti_violation_standard_code_unique
  on public.smis_anti_violation_standard(tenant_id, upper(standard_code));
create index if not exists smis_anti_violation_standard_category_idx
  on public.smis_anti_violation_standard(tenant_id, category_id, status);
create index if not exists smis_anti_violation_standard_search_idx
  on public.smis_anti_violation_standard(tenant_id, update_time desc);
create table if not exists public.smis_three_violation_education (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  inspected_employee_id uuid not null,
  checker_employee_id uuid not null,
  standard_id uuid,
  organization_id uuid,
  employee_no_snapshot text not null,
  employee_name_snapshot text not null,
  avatar_url_snapshot text,
  gender_snapshot text,
  birth_date_snapshot date,
  organization_name_snapshot text,
  position_name_snapshot text,
  checker_name_snapshot text not null,
  checker_organization_snapshot text,
  checker_position_snapshot text,
  standard_code_snapshot text,
  standard_name_snapshot text,
  category_name_snapshot text,
  warning_status text not null default 'normal',
  education_status text not null default 'pending',
  inspection_time timestamptz not null default now(),
  violation_description text not null,
  planned_education_content text,
  education_content text,
  education_result text,
  education_start_time timestamptz,
  education_completed_at timestamptz,
  training_hours numeric(8, 2),
  exam_score numeric(5, 2),
  attachment_urls text[] not null default '{}',
  education_remark text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_three_violation_education_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_three_violation_education_id_tenant_key unique (id, tenant_id),
  constraint smis_three_violation_education_employee_fkey
    foreign key (inspected_employee_id, tenant_id) references public.hr_employee(id, tenant_id),
  constraint smis_three_violation_education_checker_fkey
    foreign key (checker_employee_id, tenant_id) references public.hr_employee(id, tenant_id),
  constraint smis_three_violation_education_standard_fkey
    foreign key (standard_id, tenant_id)
    references public.smis_anti_violation_standard(id, tenant_id) on delete restrict,
  constraint smis_three_violation_education_organization_fkey
    foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_three_violation_education_warning_check
    check (warning_status in ('normal', 'warning')),
  constraint smis_three_violation_education_status_check
    check (education_status in ('pending', 'educated')),
  constraint smis_three_violation_education_description_check check (
    btrim(violation_description) <> '' and char_length(violation_description) <= 3000
  ),
  constraint smis_three_violation_education_planned_check check (
    planned_education_content is null or char_length(planned_education_content) <= 3000
  ),
  constraint smis_three_violation_education_content_check check (
    education_content is null or char_length(education_content) <= 5000
  ),
  constraint smis_three_violation_education_result_check check (
    education_result is null or char_length(education_result) <= 2000
  ),
  constraint smis_three_violation_education_hours_check check (
    training_hours is null or training_hours between 0 and 1000
  ),
  constraint smis_three_violation_education_score_check check (
    exam_score is null or exam_score between 0 and 100
  ),
  constraint smis_three_violation_education_time_check check (
    education_start_time is null or education_completed_at is null
    or education_completed_at >= education_start_time
  ),
  constraint smis_three_violation_education_attachment_check check (
    cardinality(attachment_urls) <= 20
  )
);
create table if not exists public.smis_three_violation_education_responsible (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  education_id uuid not null,
  employee_id uuid not null,
  employee_no_snapshot text not null,
  employee_name_snapshot text not null,
  organization_name_snapshot text,
  position_name_snapshot text,
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_three_violation_responsible_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_three_violation_responsible_parent_fkey
    foreign key (education_id, tenant_id)
    references public.smis_three_violation_education(id, tenant_id) on delete cascade,
  constraint smis_three_violation_responsible_employee_fkey
    foreign key (employee_id, tenant_id) references public.hr_employee(id, tenant_id),
  constraint smis_three_violation_responsible_unique unique (education_id, employee_id),
  constraint smis_three_violation_responsible_sort_check check (sort between 0 and 999999)
);
create index if not exists smis_three_violation_scope_idx
  on public.smis_three_violation_education(
    tenant_id, education_status, warning_status, inspection_time desc
  );
create index if not exists smis_three_violation_employee_idx
  on public.smis_three_violation_education(inspected_employee_id);
create index if not exists smis_three_violation_checker_idx
  on public.smis_three_violation_education(checker_employee_id);
create index if not exists smis_three_violation_org_idx
  on public.smis_three_violation_education(organization_id);
create index if not exists smis_three_violation_standard_idx
  on public.smis_three_violation_education(standard_id);
create index if not exists smis_three_violation_responsible_parent_idx
  on public.smis_three_violation_education_responsible(education_id, sort);
create index if not exists smis_three_violation_responsible_employee_idx
  on public.smis_three_violation_education_responsible(employee_id);
drop trigger if exists smis_violation_category_create_audit on public.smis_violation_category;
create trigger smis_violation_category_create_audit before insert on public.smis_violation_category
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_violation_category_update_audit on public.smis_violation_category;
create trigger smis_violation_category_update_audit before update on public.smis_violation_category
for each row execute function public.trg_set_update_time_and_by();
drop trigger if exists smis_anti_violation_standard_create_audit on public.smis_anti_violation_standard;
create trigger smis_anti_violation_standard_create_audit before insert on public.smis_anti_violation_standard
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_anti_violation_standard_update_audit on public.smis_anti_violation_standard;
create trigger smis_anti_violation_standard_update_audit before update on public.smis_anti_violation_standard
for each row execute function public.trg_set_update_time_and_by();
drop trigger if exists smis_three_violation_education_create_audit on public.smis_three_violation_education;
create trigger smis_three_violation_education_create_audit before insert on public.smis_three_violation_education
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_three_violation_education_update_audit on public.smis_three_violation_education;
create trigger smis_three_violation_education_update_audit before update on public.smis_three_violation_education
for each row execute function public.trg_set_update_time_and_by();
drop trigger if exists smis_three_violation_responsible_create_audit on public.smis_three_violation_education_responsible;
create trigger smis_three_violation_responsible_create_audit before insert on public.smis_three_violation_education_responsible
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_three_violation_responsible_update_audit on public.smis_three_violation_education_responsible;
create trigger smis_three_violation_responsible_update_audit before update on public.smis_three_violation_education_responsible
for each row execute function public.trg_set_update_time_and_by();
alter table public.smis_violation_category enable row level security;
alter table public.smis_anti_violation_standard enable row level security;
alter table public.smis_three_violation_education enable row level security;
alter table public.smis_three_violation_education_responsible enable row level security;
revoke all on table public.smis_violation_category from anon, authenticated;
revoke all on table public.smis_anti_violation_standard from anon, authenticated;
revoke all on table public.smis_three_violation_education from anon, authenticated;
revoke all on table public.smis_three_violation_education_responsible from anon, authenticated;
drop policy if exists smis_violation_category_tenant_select on public.smis_violation_category;
create policy smis_violation_category_tenant_select on public.smis_violation_category
for select to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationCategory:View')
);
drop policy if exists smis_violation_category_tenant_insert on public.smis_violation_category;
create policy smis_violation_category_tenant_insert on public.smis_violation_category
for insert to authenticated with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('SmisViolationCategory:Add')
);
drop policy if exists smis_violation_category_tenant_update on public.smis_violation_category;
create policy smis_violation_category_tenant_update on public.smis_violation_category
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationCategory:Edit')
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationCategory:Edit')
);
drop policy if exists smis_violation_category_tenant_delete on public.smis_violation_category;
create policy smis_violation_category_tenant_delete on public.smis_violation_category
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationCategory:Delete')
);
drop policy if exists smis_anti_violation_standard_tenant_select on public.smis_anti_violation_standard;
create policy smis_anti_violation_standard_tenant_select on public.smis_anti_violation_standard
for select to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAntiViolationStandardLibrary:View')
);
drop policy if exists smis_anti_violation_standard_tenant_insert on public.smis_anti_violation_standard;
create policy smis_anti_violation_standard_tenant_insert on public.smis_anti_violation_standard
for insert to authenticated with check (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisAntiViolationStandardLibrary:Add')
    or app_private.has_permission('SmisAntiViolationStandardLibrary:Import')
  )
);
drop policy if exists smis_anti_violation_standard_tenant_update on public.smis_anti_violation_standard;
create policy smis_anti_violation_standard_tenant_update on public.smis_anti_violation_standard
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAntiViolationStandardLibrary:Edit')
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAntiViolationStandardLibrary:Edit')
);
drop policy if exists smis_anti_violation_standard_tenant_delete on public.smis_anti_violation_standard;
create policy smis_anti_violation_standard_tenant_delete on public.smis_anti_violation_standard
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAntiViolationStandardLibrary:Delete')
);
drop policy if exists smis_three_violation_education_tenant_select on public.smis_three_violation_education;
create policy smis_three_violation_education_tenant_select on public.smis_three_violation_education
for select to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisThreeViolationEducation:View')
);
drop policy if exists smis_three_violation_education_tenant_insert on public.smis_three_violation_education;
create policy smis_three_violation_education_tenant_insert on public.smis_three_violation_education
for insert to authenticated with check (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisThreeViolationEducation:Add')
    or app_private.has_permission('SmisThreeViolationEducation:Copy')
  )
);
drop policy if exists smis_three_violation_education_tenant_update on public.smis_three_violation_education;
create policy smis_three_violation_education_tenant_update on public.smis_three_violation_education
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisThreeViolationEducation:Edit')
    or app_private.has_permission('SmisThreeViolationEducation:RecordEducation')
  )
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisThreeViolationEducation:Edit')
    or app_private.has_permission('SmisThreeViolationEducation:RecordEducation')
  )
);
drop policy if exists smis_three_violation_education_tenant_delete on public.smis_three_violation_education;
create policy smis_three_violation_education_tenant_delete on public.smis_three_violation_education
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisThreeViolationEducation:Delete')
);
drop policy if exists smis_three_violation_responsible_tenant_select on public.smis_three_violation_education_responsible;
create policy smis_three_violation_responsible_tenant_select
on public.smis_three_violation_education_responsible for select to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisThreeViolationEducation:View')
);
drop policy if exists smis_three_violation_responsible_tenant_insert on public.smis_three_violation_education_responsible;
create policy smis_three_violation_responsible_tenant_insert
on public.smis_three_violation_education_responsible for insert to authenticated with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisThreeViolationEducation:Add')
    or app_private.has_permission('SmisThreeViolationEducation:Copy')
    or app_private.has_permission('SmisThreeViolationEducation:Edit')
    or app_private.has_permission('SmisThreeViolationEducation:RecordEducation')
  )
);
drop policy if exists smis_three_violation_responsible_tenant_update on public.smis_three_violation_education_responsible;
create policy smis_three_violation_responsible_tenant_update
on public.smis_three_violation_education_responsible for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisThreeViolationEducation:Edit')
    or app_private.has_permission('SmisThreeViolationEducation:RecordEducation')
  )
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisThreeViolationEducation:Edit')
    or app_private.has_permission('SmisThreeViolationEducation:RecordEducation')
  )
);
drop policy if exists smis_three_violation_responsible_tenant_delete on public.smis_three_violation_education_responsible;
create policy smis_three_violation_responsible_tenant_delete
on public.smis_three_violation_education_responsible for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisThreeViolationEducation:Edit')
    or app_private.has_permission('SmisThreeViolationEducation:RecordEducation')
    or app_private.has_permission('SmisThreeViolationEducation:Delete')
  )
);
create or replace function public.smis_list_violation_categories_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_ancestor_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看违章分类' using errcode = '42501';
  end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisViolationCategory:View')) then
    raise exception '当前账号没有查看违章分类的权限' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('enabled', 'disabled') then
    raise exception '启用状态筛选值无效' using errcode = '22023';
  end if;
  if p_ancestor_id is not null and not exists (
    select 1 from public.smis_violation_category category
    where category.id = p_ancestor_id
      and (app_private.current_read_tenant_id() is null
        or category.tenant_id = app_private.current_read_tenant_id())
  ) then
    raise exception '所选违章分类不存在或已删除' using errcode = 'P0002';
  end if;

  return (
    with recursive subtree(id) as (
      select category.id from public.smis_violation_category category
      where category.id = p_ancestor_id
        and (app_private.current_read_tenant_id() is null
          or category.tenant_id = app_private.current_read_tenant_id())
      union all
      select child.id from public.smis_violation_category child
      join subtree parent on parent.id = child.parent_id
      where app_private.current_read_tenant_id() is null
         or child.tenant_id = app_private.current_read_tenant_id()
    ), enriched as (
      select category.*, parent.category_name as parent_category_name,
        (select count(*)::integer from public.smis_violation_category child
          where child.parent_id = category.id
            and (app_private.current_read_tenant_id() is null
              or child.tenant_id = app_private.current_read_tenant_id())) as child_count,
        (select count(*)::integer from public.smis_anti_violation_standard standard
          where standard.category_id = category.id
            and (app_private.current_read_tenant_id() is null
              or standard.tenant_id = app_private.current_read_tenant_id())) as standard_count
      from public.smis_violation_category category
      left join public.smis_violation_category parent
        on parent.id = category.parent_id and parent.tenant_id = category.tenant_id
      where app_private.current_read_tenant_id() is null
         or category.tenant_id = app_private.current_read_tenant_id()
    ), filtered as (
      select * from enriched
      where (p_ancestor_id is null or id in (select subtree.id from subtree))
        and (p_status is null or status = p_status)
        and (
          v_keyword is null
          or lower(category_code) like '%' || v_keyword || '%'
          or lower(category_name) like '%' || v_keyword || '%'
          or lower(coalesce(description, '')) like '%' || v_keyword || '%'
        )
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(to_jsonb(row_data) order by row_data.sort, row_data."categoryName")
        from (
          select id, tenant_id as "tenantId", parent_id as "parentId",
            parent_category_name as "parentCategoryName", category_code as "categoryCode",
            category_name as "categoryName", sort, status, description,
            child_count as "childCount", standard_count as "standardCount",
            create_by as "createBy", create_time as "createTime",
            update_by as "updateBy", update_time as "updateTime"
          from filtered order by sort, category_name, category_code
          offset v_from limit v_to - v_from + 1
        ) row_data
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'tree', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', id, 'tenantId', tenant_id, 'parentId', parent_id,
          'categoryCode', category_code, 'categoryName', category_name,
          'sort', sort, 'status', status, 'childCount', child_count,
          'standardCount', standard_count
        ) order by sort, category_name, category_code) from enriched
      ), '[]'::jsonb),
      'overview', (select jsonb_build_object(
        'total', count(*),
        'enabled', count(*) filter (where status = 'enabled'),
        'rootCount', count(*) filter (where parent_id is null),
        'usedCount', count(*) filter (where standard_count > 0)
      ) from enriched)
    )
  );
end;
$function$;
create or replace function public.smis_save_violation_category_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_parent_id uuid;
  v_category_code text := upper(btrim(coalesce(p_payload->>'category_code', '')));
  v_category_name text := btrim(coalesce(p_payload->>'category_name', ''));
  v_sort integer := coalesce(nullif(p_payload->>'sort', '')::integer, 10);
  v_status text := coalesce(nullif(p_payload->>'status', ''), 'enabled');
  v_description text := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护违章分类' using errcode = '42501';
  end if;
  if p_id is null and not app_private.has_permission('SmisViolationCategory:Add') then
    raise exception '当前账号没有新增违章分类的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisViolationCategory:Edit') then
    raise exception '当前账号没有编辑违章分类的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_violation_category target where target.id = p_id
  ));
  if v_tenant_id is null then
    raise exception '当前账号未绑定有效租户' using errcode = '42501';
  end if;
  begin
    v_parent_id := nullif(btrim(coalesce(p_payload->>'parent_id', '')), '')::uuid;
  exception when invalid_text_representation then
    raise exception '上级违章分类无效' using errcode = '22023';
  end;
  if v_category_code = '' or v_category_code !~ '^[A-Z][A-Z0-9_\-]*$' then
    raise exception '分类编码须以字母开头，仅支持字母、数字、横线和下划线' using errcode = '22023';
  end if;
  if char_length(v_category_code) > 40 then
    raise exception '分类编码不能超过 40 个字符' using errcode = '22023';
  end if;
  if v_category_name = '' or char_length(v_category_name) > 100 then
    raise exception '请输入不超过 100 个字符的分类名称' using errcode = '22023';
  end if;
  if char_length(coalesce(v_description, '')) > 1000 then
    raise exception '分类说明不能超过 1000 个字符' using errcode = '22023';
  end if;
  if v_sort not between 0 and 999999 then
    raise exception '显示顺序须在 0 到 999999 之间' using errcode = '22023';
  end if;
  if v_status not in ('enabled', 'disabled') then
    raise exception '启用状态无效' using errcode = '22023';
  end if;
  if v_parent_id is not null and not exists (
    select 1 from public.smis_violation_category parent
    where parent.id = v_parent_id and parent.tenant_id = v_tenant_id
      and (p_id is not null or parent.status = 'enabled')
  ) then
    raise exception '上级违章分类不存在、已停用或不属于当前租户' using errcode = 'P0002';
  end if;
  if p_id is not null and v_parent_id = p_id then
    raise exception '上级违章分类不能选择当前分类' using errcode = '22023';
  end if;
  if p_id is not null and v_parent_id is not null and exists (
    with recursive descendants(id) as (
      select child.id from public.smis_violation_category child
      where child.tenant_id = v_tenant_id and child.parent_id = p_id
      union all
      select child.id from public.smis_violation_category child
      join descendants parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant_id
    ) select 1 from descendants where id = v_parent_id
  ) then
    raise exception '不能将当前分类移动到自己的下级分类中' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_violation_category(
      tenant_id, parent_id, category_code, category_name, sort, status, description
    ) values (
      v_tenant_id, v_parent_id, v_category_code, v_category_name, v_sort, v_status, v_description
    ) returning id into v_result;
  else
    update public.smis_violation_category set
      parent_id = v_parent_id,
      category_code = v_category_code,
      category_name = v_category_name,
      sort = v_sort,
      status = v_status,
      description = v_description
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result;
    if v_result is null then
      raise exception '违章分类不存在或已删除' using errcode = 'P0002';
    end if;
  end if;
  return v_result;
exception when unique_violation then
  raise exception '同级分类名称或分类编码已存在' using errcode = '23505';
end;
$function$;
create or replace function public.smis_delete_violation_categories_secure(
  p_ids uuid[]
) returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除违章分类' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisViolationCategory:Delete') then
    raise exception '当前账号没有删除违章分类的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的违章分类' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.smis_violation_category child
    where (app_private.is_platform_super() or child.tenant_id = app_private.auth_user_tenant_id())
      and child.parent_id = any(v_ids) and not child.id = any(v_ids)
  ) then
    raise exception '所选违章分类仍有下级分类，请先调整或删除下级分类' using errcode = '23503';
  end if;
  delete from public.smis_violation_category
  where (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
exception when foreign_key_violation then
  raise exception '违章分类已被标准库或教育记录使用，请改为停用' using errcode = '23503';
end;
$function$;
create or replace function public.smis_list_anti_violation_standards_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_category_id uuid default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看反违章标准库' using errcode = '42501';
  end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisAntiViolationStandardLibrary:View')) then
    raise exception '当前账号没有查看反违章标准库的权限' using errcode = '42501';
  end if;
  if p_purpose = 'export' and not app_private.has_permission('SmisAntiViolationStandardLibrary:Export') then
    raise exception '当前账号没有导出反违章标准库的权限' using errcode = '42501';
  end if;
  if p_purpose not in ('list', 'export') then
    raise exception '查询用途无效' using errcode = '22023';
  end if;
  if p_status is not null and p_status not in ('enabled', 'disabled') then
    raise exception '启用状态筛选值无效' using errcode = '22023';
  end if;

  return (
    with recursive category_subtree(id) as (
      select category.id from public.smis_violation_category category
      where category.id = p_category_id
        and (app_private.current_read_tenant_id() is null
          or category.tenant_id = app_private.current_read_tenant_id())
      union all
      select child.id from public.smis_violation_category child
      join category_subtree parent on parent.id = child.parent_id
      where app_private.current_read_tenant_id() is null
         or child.tenant_id = app_private.current_read_tenant_id()
    ), scoped as (
      select standard.*, category.category_code, category.category_name
      from public.smis_anti_violation_standard standard
      join public.smis_violation_category category
        on category.id = standard.category_id and category.tenant_id = standard.tenant_id
      where (app_private.current_read_tenant_id() is null
        or standard.tenant_id = app_private.current_read_tenant_id())
        and (p_category_id is null or standard.category_id in (select id from category_subtree))
        and (p_status is null or standard.status = p_status)
        and (
          v_keyword is null
          or lower(standard.standard_code) like '%' || v_keyword || '%'
          or lower(standard.standard_name) like '%' || v_keyword || '%'
          or lower(category.category_name) like '%' || v_keyword || '%'
          or lower(coalesce(standard.handling_requirements, '')) like '%' || v_keyword || '%'
        )
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(to_jsonb(row_data) order by row_data."updateTime" desc)
        from (
          select id, tenant_id as "tenantId", category_id as "categoryId",
            category_code as "categoryCode", category_name as "categoryName",
            standard_code as "standardCode", standard_name as "standardName",
            deduction_points as "deductionPoints",
            handling_requirements as "handlingRequirements",
            legal_basis as "legalBasis", status, description,
            create_by as "createBy", create_time as "createTime",
            update_by as "updateBy", update_time as "updateTime"
          from scoped order by update_time desc, standard_code
          offset v_from limit v_to - v_from + 1
        ) row_data
      ), '[]'::jsonb),
      'total', (select count(*) from scoped),
      'overview', (select jsonb_build_object(
        'total', count(*),
        'enabled', count(*) filter (where status = 'enabled'),
        'disabled', count(*) filter (where status = 'disabled'),
        'totalPoints', coalesce(sum(deduction_points), 0)
      ) from scoped)
    )
  );
end;
$function$;
create or replace function public.smis_save_anti_violation_standard_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_category_id uuid;
  v_standard_code text := upper(btrim(coalesce(p_payload->>'standard_code', '')));
  v_standard_name text := btrim(coalesce(p_payload->>'standard_name', ''));
  v_deduction_points numeric := coalesce(nullif(p_payload->>'deduction_points', '')::numeric, 0);
  v_status text := coalesce(nullif(p_payload->>'status', ''), 'enabled');
  v_handling text := nullif(btrim(coalesce(p_payload->>'handling_requirements', '')), '');
  v_basis text := nullif(btrim(coalesce(p_payload->>'legal_basis', '')), '');
  v_description text := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护反违章标准库' using errcode = '42501';
  end if;
  if p_id is null and not (
    app_private.has_permission('SmisAntiViolationStandardLibrary:Add')
    or app_private.has_permission('SmisAntiViolationStandardLibrary:Import')
  ) then
    raise exception '当前账号没有新增或导入反违章标准的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisAntiViolationStandardLibrary:Edit') then
    raise exception '当前账号没有编辑反违章标准的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_anti_violation_standard target where target.id = p_id
  ));
  begin
    v_category_id := (p_payload->>'category_id')::uuid;
  exception when invalid_text_representation then
    raise exception '所属违章分类无效' using errcode = '22023';
  end;
  if v_standard_code = '' or char_length(v_standard_code) > 50 then
    raise exception '请输入不超过 50 个字符的违章编号' using errcode = '22023';
  end if;
  if v_standard_name = '' or char_length(v_standard_name) > 500 then
    raise exception '请输入不超过 500 个字符的违章名称' using errcode = '22023';
  end if;
  if v_deduction_points not between 0 and 99999999.99 then
    raise exception '扣减分值须在 0 到 99999999.99 之间' using errcode = '22023';
  end if;
  if v_status not in ('enabled', 'disabled') then
    raise exception '启用状态无效' using errcode = '22023';
  end if;
  if char_length(coalesce(v_handling, '')) > 2000
    or char_length(coalesce(v_basis, '')) > 1000
    or char_length(coalesce(v_description, '')) > 1000 then
    raise exception '处理要求、制度依据或说明内容过长' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.smis_violation_category category
    where category.id = v_category_id and category.tenant_id = v_tenant_id
      and (p_id is not null or category.status = 'enabled')
  ) then
    raise exception '所属违章分类不存在、已停用或不属于当前租户' using errcode = 'P0002';
  end if;

  if p_id is null then
    insert into public.smis_anti_violation_standard(
      tenant_id, category_id, standard_code, standard_name, deduction_points,
      handling_requirements, legal_basis, status, description
    ) values (
      v_tenant_id, v_category_id, v_standard_code, v_standard_name, v_deduction_points,
      v_handling, v_basis, v_status, v_description
    ) returning id into v_result;
  else
    update public.smis_anti_violation_standard set
      category_id = v_category_id,
      standard_code = v_standard_code,
      standard_name = v_standard_name,
      deduction_points = v_deduction_points,
      handling_requirements = v_handling,
      legal_basis = v_basis,
      status = v_status,
      description = v_description
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result;
    if v_result is null then
      raise exception '反违章标准不存在或已删除' using errcode = 'P0002';
    end if;
  end if;
  return v_result;
exception when unique_violation then
  raise exception '违章编号已存在，请检查后重试' using errcode = '23505';
end;
$function$;
create or replace function public.smis_delete_anti_violation_standards_secure(
  p_ids uuid[]
) returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除反违章标准' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisAntiViolationStandardLibrary:Delete') then
    raise exception '当前账号没有删除反违章标准的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的反违章标准' using errcode = '22023';
  end if;
  delete from public.smis_anti_violation_standard
  where (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
exception when foreign_key_violation then
  raise exception '反违章标准已被教育记录使用，请改为停用' using errcode = '23503';
end;
$function$;
create or replace function public.smis_list_three_violation_education_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_organization_id uuid default null,
  p_checker_employee_id uuid default null,
  p_education_status text default null,
  p_warning_status text default null,
  p_start_time timestamptz default null,
  p_end_time timestamptz default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看三违人员教育信息' using errcode = '42501';
  end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisThreeViolationEducation:View')) then
    raise exception '当前账号没有查看三违人员教育信息的权限' using errcode = '42501';
  end if;
  if p_purpose = 'export' and not app_private.has_permission('SmisThreeViolationEducation:Export') then
    raise exception '当前账号没有导出三违人员教育信息的权限' using errcode = '42501';
  end if;
  if p_purpose not in ('list', 'export') then
    raise exception '查询用途无效' using errcode = '22023';
  end if;
  if p_education_status is not null and p_education_status not in ('pending', 'educated') then
    raise exception '教育状态筛选值无效' using errcode = '22023';
  end if;
  if p_warning_status is not null and p_warning_status not in ('normal', 'warning') then
    raise exception '预警状态筛选值无效' using errcode = '22023';
  end if;
  if p_start_time is not null and p_end_time is not null and p_end_time < p_start_time then
    raise exception '检查时间结束值不能早于开始值' using errcode = '22023';
  end if;

  return (
    with recursive organization_scope(id) as (
      select organization.id from public.sys_organization organization
      where organization.id = p_organization_id
        and (app_private.current_read_tenant_id() is null
          or organization.tenant_id = app_private.current_read_tenant_id())
      union all
      select child.id from public.sys_organization child
      join organization_scope parent on parent.id = child.parent_id
      where app_private.current_read_tenant_id() is null
         or child.tenant_id = app_private.current_read_tenant_id()
    ), scoped as (
      select education.*,
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', responsible.employee_id,
            'employeeNo', responsible.employee_no_snapshot,
            'employeeName', responsible.employee_name_snapshot,
            'organizationName', responsible.organization_name_snapshot,
            'positionName', responsible.position_name_snapshot
          ) order by responsible.sort, responsible.employee_name_snapshot)
          from public.smis_three_violation_education_responsible responsible
          where responsible.education_id = education.id
        ), '[]'::jsonb) as responsible_employees
      from public.smis_three_violation_education education
      where (app_private.current_read_tenant_id() is null
        or education.tenant_id = app_private.current_read_tenant_id())
        and (p_organization_id is null or education.organization_id in (select id from organization_scope))
        and (p_checker_employee_id is null or education.checker_employee_id = p_checker_employee_id)
        and (p_education_status is null or education.education_status = p_education_status)
        and (p_warning_status is null or education.warning_status = p_warning_status)
        and (p_start_time is null or education.inspection_time >= p_start_time)
        and (p_end_time is null or education.inspection_time <= p_end_time)
        and (
          v_keyword is null
          or lower(education.employee_no_snapshot) like '%' || v_keyword || '%'
          or lower(education.employee_name_snapshot) like '%' || v_keyword || '%'
          or lower(education.checker_name_snapshot) like '%' || v_keyword || '%'
          or lower(education.violation_description) like '%' || v_keyword || '%'
          or lower(coalesce(education.standard_name_snapshot, '')) like '%' || v_keyword || '%'
        )
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(to_jsonb(row_data) order by row_data."inspectionTime" desc)
        from (
          select id, tenant_id as "tenantId",
            inspected_employee_id as "inspectedEmployeeId",
            checker_employee_id as "checkerEmployeeId",
            standard_id as "standardId", organization_id as "organizationId",
            employee_no_snapshot as "employeeNo",
            employee_name_snapshot as "employeeName",
            avatar_url_snapshot as "avatarUrl", gender_snapshot as gender,
            birth_date_snapshot as "birthDate",
            case when birth_date_snapshot is null then null
              else extract(year from age(inspection_time::date, birth_date_snapshot))::integer end as age,
            organization_name_snapshot as "organizationName",
            position_name_snapshot as "positionName",
            checker_name_snapshot as "checkerName",
            checker_organization_snapshot as "checkerOrganizationName",
            checker_position_snapshot as "checkerPositionName",
            standard_code_snapshot as "standardCode",
            standard_name_snapshot as "standardName",
            category_name_snapshot as "categoryName",
            warning_status as "warningStatus",
            education_status as "educationStatus",
            inspection_time as "inspectionTime",
            violation_description as "violationDescription",
            planned_education_content as "plannedEducationContent",
            education_content as "educationContent",
            education_result as "educationResult",
            education_start_time as "educationStartTime",
            education_completed_at as "educationCompletedAt",
            training_hours as "trainingHours", exam_score as "examScore",
            attachment_urls as "attachmentUrls",
            education_remark as "educationRemark", remark,
            responsible_employees as "responsibleEmployees",
            create_by as "createBy", create_time as "createTime",
            update_by as "updateBy", update_time as "updateTime"
          from scoped order by inspection_time desc, create_time desc
          offset v_from limit v_to - v_from + 1
        ) row_data
      ), '[]'::jsonb),
      'total', (select count(*) from scoped),
      'overview', (select jsonb_build_object(
        'total', count(*),
        'pending', count(*) filter (where education_status = 'pending'),
        'educated', count(*) filter (where education_status = 'educated'),
        'warning', count(*) filter (where warning_status = 'warning')
      ) from scoped),
      'organizations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', organization.id, 'parentId', organization.parent_id,
          'name', organization.organization_name,
          'code', organization.organization_code,
          'type', organization.organization_type,
          'sort', organization.sort
        ) order by organization.sort, organization.organization_name)
        from public.sys_organization organization
        where (app_private.current_read_tenant_id() is null
          or organization.tenant_id = app_private.current_read_tenant_id())
          and organization.status = '1'
      ), '[]'::jsonb),
      'standards', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', standard.id, 'standardCode', standard.standard_code,
          'standardName', standard.standard_name,
          'categoryId', standard.category_id,
          'categoryName', category.category_name,
          'deductionPoints', standard.deduction_points
        ) order by category.sort, standard.standard_code)
        from public.smis_anti_violation_standard standard
        join public.smis_violation_category category
          on category.id = standard.category_id and category.tenant_id = standard.tenant_id
        where (app_private.current_read_tenant_id() is null
          or standard.tenant_id = app_private.current_read_tenant_id())
          and standard.status = 'enabled' and category.status = 'enabled'
      ), '[]'::jsonb)
    )
  );
end;
$function$;
create or replace function public.smis_save_three_violation_education_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_inspected_id uuid;
  v_checker_id uuid;
  v_standard_id uuid;
  v_inspected record;
  v_checker record;
  v_standard record;
  v_warning_status text := coalesce(nullif(p_payload->>'warning_status', ''), 'normal');
  v_inspection_time timestamptz;
  v_violation_description text := btrim(coalesce(p_payload->>'violation_description', ''));
  v_planned_content text := nullif(btrim(coalesce(p_payload->>'planned_education_content', '')), '');
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark', '')), '');
  v_responsible_ids jsonb := coalesce(p_payload->'responsible_employee_ids', '[]'::jsonb);
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护三违人员教育信息' using errcode = '42501';
  end if;
  if p_id is null and not (
    app_private.has_permission('SmisThreeViolationEducation:Add')
    or app_private.has_permission('SmisThreeViolationEducation:Copy')
  ) then
    raise exception '当前账号没有新增或复制三违人员教育信息的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisThreeViolationEducation:Edit') then
    raise exception '当前账号没有编辑三违人员教育信息的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_three_violation_education target where target.id = p_id
  ));
  begin
    v_inspected_id := (p_payload->>'inspected_employee_id')::uuid;
    v_checker_id := (p_payload->>'checker_employee_id')::uuid;
    v_standard_id := nullif(p_payload->>'standard_id', '')::uuid;
    v_inspection_time := coalesce(nullif(p_payload->>'inspection_time', '')::timestamptz, now());
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception '被检查人、检查人、违章标准或检查时间无效' using errcode = '22023';
  end;
  if v_warning_status not in ('normal', 'warning') then
    raise exception '预警状态无效' using errcode = '22023';
  end if;
  if v_violation_description = '' or char_length(v_violation_description) > 3000 then
    raise exception '请输入不超过 3000 个字符的三违问题描述' using errcode = '22023';
  end if;
  if char_length(coalesce(v_planned_content, '')) > 3000 then
    raise exception '拟教育内容不能超过 3000 个字符' using errcode = '22023';
  end if;
  if char_length(coalesce(v_remark, '')) > 1000 then
    raise exception '备注不能超过 1000 个字符' using errcode = '22023';
  end if;
  if jsonb_typeof(v_responsible_ids) <> 'array' or jsonb_array_length(v_responsible_ids) = 0 then
    raise exception '请至少选择一名教育负责人' using errcode = '22023';
  end if;
  if jsonb_array_length(v_responsible_ids) <> (
    select count(distinct value) from jsonb_array_elements_text(v_responsible_ids)
  ) then
    raise exception '教育负责人不能重复' using errcode = '22023';
  end if;
  select employee.*, organization.organization_name, position.position_name
    into v_inspected
  from public.hr_employee employee
  left join public.sys_organization organization on organization.id = employee.organization_id
  left join public.hr_position position on position.id = employee.position_id
  where employee.id = v_inspected_id and employee.tenant_id = v_tenant_id;
  select employee.*, organization.organization_name, position.position_name
    into v_checker
  from public.hr_employee employee
  left join public.sys_organization organization on organization.id = employee.organization_id
  left join public.hr_position position on position.id = employee.position_id
  where employee.id = v_checker_id and employee.tenant_id = v_tenant_id;
  if v_inspected.id is null or v_checker.id is null then
    raise exception '被检查人或检查人不在当前租户员工花名册中' using errcode = 'P0002';
  end if;
  if v_standard_id is not null then
    select standard.*, category.category_name into v_standard
    from public.smis_anti_violation_standard standard
    join public.smis_violation_category category
      on category.id = standard.category_id and category.tenant_id = standard.tenant_id
    where standard.id = v_standard_id and standard.tenant_id = v_tenant_id
      and (p_id is not null or standard.status = 'enabled');
    if v_standard.id is null then
      raise exception '所选反违章标准不存在、已停用或不属于当前租户' using errcode = 'P0002';
    end if;
  else
    select null::uuid as id, null::text as standard_code,
      null::text as standard_name, null::text as category_name
    into v_standard;
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(v_responsible_ids) item
    left join public.hr_employee employee
      on employee.id = item.value::uuid and employee.tenant_id = v_tenant_id
    where employee.id is null
  ) then
    raise exception '教育负责人包含无效或跨租户员工' using errcode = 'P0002';
  end if;

  if p_id is null then
    insert into public.smis_three_violation_education(
      tenant_id, inspected_employee_id, checker_employee_id, standard_id, organization_id,
      employee_no_snapshot, employee_name_snapshot, avatar_url_snapshot,
      gender_snapshot, birth_date_snapshot, organization_name_snapshot, position_name_snapshot,
      checker_name_snapshot, checker_organization_snapshot, checker_position_snapshot,
      standard_code_snapshot, standard_name_snapshot, category_name_snapshot,
      warning_status, education_status, inspection_time, violation_description,
      planned_education_content, remark
    ) values (
      v_tenant_id, v_inspected.id, v_checker.id, v_standard.id, v_inspected.organization_id,
      v_inspected.employee_no, v_inspected.employee_name, v_inspected.avatar_url,
      v_inspected.gender, v_inspected.birth_date, v_inspected.organization_name, v_inspected.position_name,
      v_checker.employee_name, v_checker.organization_name, v_checker.position_name,
      v_standard.standard_code, v_standard.standard_name, v_standard.category_name,
      v_warning_status, 'pending', v_inspection_time, v_violation_description,
      v_planned_content, v_remark
    ) returning id into v_result;
  else
    if not exists (
      select 1 from public.smis_three_violation_education education
      where education.id = p_id and education.tenant_id = v_tenant_id
        and education.education_status = 'pending'
    ) then
      raise exception '仅待教育记录允许编辑，已教育记录请通过“记录教育信息”补充证据' using errcode = 'P0001';
    end if;
    update public.smis_three_violation_education set
      inspected_employee_id = v_inspected.id,
      checker_employee_id = v_checker.id,
      standard_id = v_standard.id,
      organization_id = v_inspected.organization_id,
      employee_no_snapshot = v_inspected.employee_no,
      employee_name_snapshot = v_inspected.employee_name,
      avatar_url_snapshot = v_inspected.avatar_url,
      gender_snapshot = v_inspected.gender,
      birth_date_snapshot = v_inspected.birth_date,
      organization_name_snapshot = v_inspected.organization_name,
      position_name_snapshot = v_inspected.position_name,
      checker_name_snapshot = v_checker.employee_name,
      checker_organization_snapshot = v_checker.organization_name,
      checker_position_snapshot = v_checker.position_name,
      standard_code_snapshot = v_standard.standard_code,
      standard_name_snapshot = v_standard.standard_name,
      category_name_snapshot = v_standard.category_name,
      warning_status = v_warning_status,
      inspection_time = v_inspection_time,
      violation_description = v_violation_description,
      planned_education_content = v_planned_content,
      remark = v_remark
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result;
    delete from public.smis_three_violation_education_responsible
    where education_id = v_result and tenant_id = v_tenant_id;
  end if;

  insert into public.smis_three_violation_education_responsible(
    tenant_id, education_id, employee_id, employee_no_snapshot,
    employee_name_snapshot, organization_name_snapshot, position_name_snapshot, sort
  )
  select v_tenant_id, v_result, employee.id, employee.employee_no,
    employee.employee_name, organization.organization_name, position.position_name,
    (item.ordinality - 1) * 10
  from jsonb_array_elements_text(v_responsible_ids) with ordinality item(value, ordinality)
  join public.hr_employee employee
    on employee.id = item.value::uuid and employee.tenant_id = v_tenant_id
  left join public.sys_organization organization on organization.id = employee.organization_id
  left join public.hr_position position on position.id = employee.position_id;
  return v_result;
end;
$function$;
create or replace function public.smis_record_three_violation_education_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_content text := btrim(coalesce(p_payload->>'education_content', ''));
  v_result_text text := btrim(coalesce(p_payload->>'education_result', ''));
  v_start_time timestamptz;
  v_completed_at timestamptz;
  v_training_hours numeric;
  v_exam_score numeric;
  v_attachment_urls text[] := array[]::text[];
  v_education_remark text := nullif(btrim(coalesce(p_payload->>'education_remark', '')), '');
  v_responsible_ids jsonb := coalesce(p_payload->'responsible_employee_ids', '[]'::jsonb);
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再记录教育信息' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisThreeViolationEducation:RecordEducation') then
    raise exception '当前账号没有记录教育信息的权限' using errcode = '42501';
  end if;
  select education.tenant_id into v_tenant_id
  from public.smis_three_violation_education education
  where education.id = p_id
    and (app_private.is_platform_super() or education.tenant_id = app_private.auth_user_tenant_id());
  if v_tenant_id is null then
    raise exception '三违人员教育记录不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  begin
    v_start_time := nullif(p_payload->>'education_start_time', '')::timestamptz;
    v_completed_at := coalesce(nullif(p_payload->>'education_completed_at', '')::timestamptz, now());
    v_training_hours := nullif(p_payload->>'training_hours', '')::numeric;
    v_exam_score := nullif(p_payload->>'exam_score', '')::numeric;
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception '教育时间、培训课时或考核分数无效' using errcode = '22023';
  end;
  if v_content = '' or char_length(v_content) > 5000 then
    raise exception '请输入不超过 5000 个字符的教育培训内容' using errcode = '22023';
  end if;
  if v_result_text = '' or char_length(v_result_text) > 2000 then
    raise exception '请输入不超过 2000 个字符的教育培训结果' using errcode = '22023';
  end if;
  if v_start_time is null or v_completed_at < v_start_time then
    raise exception '教育完成时间不能早于教育开始时间' using errcode = '22023';
  end if;
  if v_training_hours is null or v_training_hours <= 0 or v_training_hours > 1000 then
    raise exception '培训课时须大于 0 且不超过 1000' using errcode = '22023';
  end if;
  if v_exam_score is not null and (v_exam_score < 0 or v_exam_score > 100) then
    raise exception '考核分数须在 0 到 100 之间' using errcode = '22023';
  end if;
  if jsonb_typeof(v_responsible_ids) <> 'array' or jsonb_array_length(v_responsible_ids) = 0 then
    raise exception '请至少选择一名教育负责人' using errcode = '22023';
  end if;
  if jsonb_array_length(v_responsible_ids) <> (
    select count(distinct value) from jsonb_array_elements_text(v_responsible_ids)
  ) then
    raise exception '教育负责人不能重复' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_payload->'attachment_urls', '[]'::jsonb)) <> 'array' then
    raise exception '教育材料格式无效' using errcode = '22023';
  end if;
  select coalesce(array_agg(value), array[]::text[]) into v_attachment_urls
  from jsonb_array_elements_text(coalesce(p_payload->'attachment_urls', '[]'::jsonb));
  if cardinality(v_attachment_urls) > 20 then
    raise exception '教育材料最多上传 20 个文件' using errcode = '22023';
  end if;
  if char_length(coalesce(v_education_remark, '')) > 1000 then
    raise exception '教育备注不能超过 1000 个字符' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(v_responsible_ids) item
    left join public.hr_employee employee
      on employee.id = item.value::uuid and employee.tenant_id = v_tenant_id
    where employee.id is null
  ) then
    raise exception '教育负责人包含无效或跨租户员工' using errcode = 'P0002';
  end if;

  update public.smis_three_violation_education set
    education_status = 'educated',
    education_content = v_content,
    education_result = v_result_text,
    education_start_time = v_start_time,
    education_completed_at = v_completed_at,
    training_hours = v_training_hours,
    exam_score = v_exam_score,
    attachment_urls = v_attachment_urls,
    education_remark = v_education_remark
  where id = p_id and tenant_id = v_tenant_id;

  delete from public.smis_three_violation_education_responsible
  where education_id = p_id and tenant_id = v_tenant_id;
  insert into public.smis_three_violation_education_responsible(
    tenant_id, education_id, employee_id, employee_no_snapshot,
    employee_name_snapshot, organization_name_snapshot, position_name_snapshot, sort
  )
  select v_tenant_id, p_id, employee.id, employee.employee_no,
    employee.employee_name, organization.organization_name, position.position_name,
    (item.ordinality - 1) * 10
  from jsonb_array_elements_text(v_responsible_ids) with ordinality item(value, ordinality)
  join public.hr_employee employee
    on employee.id = item.value::uuid and employee.tenant_id = v_tenant_id
  left join public.sys_organization organization on organization.id = employee.organization_id
  left join public.hr_position position on position.id = employee.position_id;
  return p_id;
end;
$function$;
create or replace function public.smis_delete_three_violation_education_secure(
  p_ids uuid[]
) returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_ids uuid[] := coalesce(p_ids, array[]::uuid[]);
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除三违人员教育信息' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisThreeViolationEducation:Delete') then
    raise exception '当前账号没有删除三违人员教育信息的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的三违人员教育信息' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.smis_three_violation_education education
    where education.id = any(v_ids)
      and (app_private.is_platform_super() or education.tenant_id = app_private.auth_user_tenant_id())
      and education.education_status = 'educated'
  ) then
    raise exception '已完成教育的记录属于安全教育台账，不能删除' using errcode = 'P0001';
  end if;
  delete from public.smis_three_violation_education
  where (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and education_status = 'pending' and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
revoke all on function public.smis_list_violation_categories_secure(integer, integer, text, text, uuid) from public, anon;
grant execute on function public.smis_list_violation_categories_secure(integer, integer, text, text, uuid) to authenticated;
revoke all on function public.smis_save_violation_category_secure(uuid, jsonb) from public, anon;
grant execute on function public.smis_save_violation_category_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_delete_violation_categories_secure(uuid[]) from public, anon;
grant execute on function public.smis_delete_violation_categories_secure(uuid[]) to authenticated;
revoke all on function public.smis_list_anti_violation_standards_secure(integer, integer, text, text, uuid, text) from public, anon;
grant execute on function public.smis_list_anti_violation_standards_secure(integer, integer, text, text, uuid, text) to authenticated;
revoke all on function public.smis_save_anti_violation_standard_secure(uuid, jsonb) from public, anon;
grant execute on function public.smis_save_anti_violation_standard_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_delete_anti_violation_standards_secure(uuid[]) from public, anon;
grant execute on function public.smis_delete_anti_violation_standards_secure(uuid[]) to authenticated;
revoke all on function public.smis_list_three_violation_education_secure(integer, integer, text, uuid, uuid, text, text, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.smis_list_three_violation_education_secure(integer, integer, text, uuid, uuid, text, text, timestamptz, timestamptz, text) to authenticated;
revoke all on function public.smis_save_three_violation_education_secure(uuid, jsonb) from public, anon;
grant execute on function public.smis_save_three_violation_education_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_record_three_violation_education_secure(uuid, jsonb) from public, anon;
grant execute on function public.smis_record_three_violation_education_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_delete_three_violation_education_secure(uuid[]) from public, anon;
grant execute on function public.smis_delete_three_violation_education_secure(uuid[]) to authenticated;
with dictionary_types(code, name, sort) as (
  values
    ('smisAntiViolationStatus', '反违章启用状态', 50),
    ('smisThreeViolationWarningStatus', '三违预警状态', 51),
    ('smisThreeViolationEducationStatus', '三违教育状态', 52)
)
insert into public.sys_dict_type(
  id, parent_id, name, code, status, node_type, sort,
  tenant_id, create_by, update_by, remark
)
select gen_random_uuid(), parent.id, item.name, item.code, '1', 'dictionary', item.sort,
  app_private.platform_tenant_id(), '624944977@qq.com', '624944977@qq.com',
  '反违章管理业务字典'
from dictionary_types item
join public.sys_dict_type parent on parent.code = 'smisSafetyProduction'
where not exists (
  select 1 from public.sys_dict_type existing where existing.code = item.code
);
with dictionary_items(type_code, suffix, value, label, color, tag_type, sort) as (
  values
    ('smisAntiViolationStatus', 'enabled', 'enabled', '启用', '#16a34a', 'success', 1),
    ('smisAntiViolationStatus', 'disabled', 'disabled', '停用', '#64748b', 'info', 2),
    ('smisThreeViolationWarningStatus', 'normal', 'normal', '正常', '#16a34a', 'success', 1),
    ('smisThreeViolationWarningStatus', 'warning', 'warning', '预警', '#d97706', 'warning', 2),
    ('smisThreeViolationEducationStatus', 'pending', 'pending', '待教育', '#d97706', 'warning', 1),
    ('smisThreeViolationEducationStatus', 'educated', 'educated', '已教育', '#16a34a', 'success', 2)
)
insert into public.sys_dictionary(
  id, type_id, code, status, value, label, color, tag_type, sort,
  tenant_id, create_by, update_by, remark
)
select gen_random_uuid(), type.id, item.type_code || '_' || item.suffix, '1',
  item.value, item.label, item.color, item.tag_type, item.sort,
  app_private.platform_tenant_id(), '624944977@qq.com', '624944977@qq.com',
  '反违章管理默认字典项'
from dictionary_items item
join public.sys_dict_type type on type.code = item.type_code
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = type.id and existing.value = item.value
);
with buttons(menu_name, code, title, sort) as (
  values
    ('SmisThreeViolationEducation', 'SmisThreeViolationEducation:View', '查看三违人员教育信息', 1),
    ('SmisThreeViolationEducation', 'SmisThreeViolationEducation:Add', '新增三违人员信息', 2),
    ('SmisThreeViolationEducation', 'SmisThreeViolationEducation:Copy', '复制并新增', 3),
    ('SmisThreeViolationEducation', 'SmisThreeViolationEducation:Edit', '编辑三违人员信息', 4),
    ('SmisThreeViolationEducation', 'SmisThreeViolationEducation:Delete', '删除三违人员信息', 5),
    ('SmisThreeViolationEducation', 'SmisThreeViolationEducation:RecordEducation', '记录教育信息', 6),
    ('SmisThreeViolationEducation', 'SmisThreeViolationEducation:Export', '导出三违人员教育信息', 7),
    ('SmisThreeViolationEducation', 'SmisThreeViolationEducation:Print', '打印安全教育台账', 8),
    ('SmisViolationCategory', 'SmisViolationCategory:View', '查看违章分类', 1),
    ('SmisViolationCategory', 'SmisViolationCategory:Add', '新增违章分类', 2),
    ('SmisViolationCategory', 'SmisViolationCategory:Edit', '编辑违章分类', 3),
    ('SmisViolationCategory', 'SmisViolationCategory:Delete', '删除违章分类', 4),
    ('SmisViolationCategory', 'SmisViolationCategory:Export', '导出违章分类', 5),
    ('SmisAntiViolationStandardLibrary', 'SmisAntiViolationStandardLibrary:View', '查看反违章标准库', 1),
    ('SmisAntiViolationStandardLibrary', 'SmisAntiViolationStandardLibrary:Add', '新增反违章标准', 2),
    ('SmisAntiViolationStandardLibrary', 'SmisAntiViolationStandardLibrary:Edit', '编辑反违章标准', 3),
    ('SmisAntiViolationStandardLibrary', 'SmisAntiViolationStandardLibrary:Delete', '删除反违章标准', 4),
    ('SmisAntiViolationStandardLibrary', 'SmisAntiViolationStandardLibrary:Import', '导入反违章标准', 5),
    ('SmisAntiViolationStandardLibrary', 'SmisAntiViolationStandardLibrary:Export', '导出反违章标准', 6)
)
insert into public.sys_menu(
  id, parent_id, name, path, component, type, meta, sort,
  create_by, update_by, app_code
)
select gen_random_uuid(), parent.id, button.code, '', '', 'button',
  jsonb_build_object(
    'title', button.title, 'is_hide', true, 'is_enable', true, 'roles', '[]'::jsonb
  ),
  button.sort, '624944977@qq.com', '624944977@qq.com', 'smis'
from buttons button
join public.sys_menu parent on parent.name = button.menu_name
where not exists (
  select 1 from public.sys_menu existing where existing.name = button.code
);
insert into public.sys_role_menu(role_id, menu_id, tenant_id, create_by, update_by)
select distinct parent_grant.role_id, child.id, parent_grant.tenant_id,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu parent_grant
join public.sys_menu parent on parent.id = parent_grant.menu_id
join public.sys_menu child on child.parent_id = parent.id and child.type = 'button'
where parent.name in (
  'SmisThreeViolationEducation', 'SmisViolationCategory', 'SmisAntiViolationStandardLibrary'
)
on conflict (role_id, menu_id) do nothing;
commit;
