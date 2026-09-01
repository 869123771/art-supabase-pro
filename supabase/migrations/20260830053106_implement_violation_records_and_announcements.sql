begin;
create table if not exists public.smis_violation_record (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  record_no text not null,
  violation_time timestamptz not null default now(),
  site_id uuid not null,
  checker_employee_id uuid not null,
  site_name_snapshot text not null,
  site_address_snapshot text,
  checker_name_snapshot text not null,
  checker_organization_snapshot text,
  checker_position_snapshot text,
  deduction_points numeric(12, 2) not null default 0,
  fine_amount numeric(14, 2) not null default 0,
  situation_description text,
  image_urls text[] not null default '{}',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_violation_record_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_violation_record_id_tenant_key unique (id, tenant_id),
  constraint smis_violation_record_site_fkey foreign key (site_id, tenant_id)
    references public.smis_site(id, tenant_id) on delete restrict,
  constraint smis_violation_record_checker_fkey foreign key (checker_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_violation_record_no_check check (
    btrim(record_no) <> '' and char_length(record_no) <= 80
  ),
  constraint smis_violation_record_points_check check (
    deduction_points between 0 and 9999999999.99
  ),
  constraint smis_violation_record_fine_check check (
    fine_amount between 0 and 999999999999.99
  ),
  constraint smis_violation_record_situation_check check (
    situation_description is null or char_length(situation_description) <= 3000
  ),
  constraint smis_violation_record_image_check check (cardinality(image_urls) <= 12),
  constraint smis_violation_record_remark_check check (
    remark is null or char_length(remark) <= 1000
  )
);
create unique index if not exists smis_violation_record_no_unique
  on public.smis_violation_record(tenant_id, upper(record_no));
create index if not exists smis_violation_record_scope_idx
  on public.smis_violation_record(tenant_id, violation_time desc);
create index if not exists smis_violation_record_site_idx
  on public.smis_violation_record(site_id);
create index if not exists smis_violation_record_checker_idx
  on public.smis_violation_record(checker_employee_id);
create table if not exists public.smis_violation_record_employee (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  record_id uuid not null,
  employee_id uuid not null,
  employee_no_snapshot text not null,
  employee_name_snapshot text not null,
  avatar_url_snapshot text,
  organization_id_snapshot uuid,
  organization_name_snapshot text,
  position_name_snapshot text,
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_violation_record_employee_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_violation_record_employee_parent_fkey foreign key (record_id, tenant_id)
    references public.smis_violation_record(id, tenant_id) on delete cascade,
  constraint smis_violation_record_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_violation_record_employee_unique unique (record_id, employee_id),
  constraint smis_violation_record_employee_sort_check check (sort between 0 and 999999)
);
create index if not exists smis_violation_record_employee_parent_idx
  on public.smis_violation_record_employee(record_id, sort);
create index if not exists smis_violation_record_employee_employee_idx
  on public.smis_violation_record_employee(employee_id, record_id);
create table if not exists public.smis_violation_record_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  record_id uuid not null,
  standard_id uuid not null,
  category_id_snapshot uuid,
  category_name_snapshot text not null,
  standard_code_snapshot text not null,
  standard_name_snapshot text not null,
  deduction_points_snapshot numeric(10, 2) not null default 0,
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_violation_record_item_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_violation_record_item_parent_fkey foreign key (record_id, tenant_id)
    references public.smis_violation_record(id, tenant_id) on delete cascade,
  constraint smis_violation_record_item_standard_fkey foreign key (standard_id, tenant_id)
    references public.smis_anti_violation_standard(id, tenant_id) on delete restrict,
  constraint smis_violation_record_item_unique unique (record_id, standard_id),
  constraint smis_violation_record_item_points_check check (
    deduction_points_snapshot between 0 and 99999999.99
  ),
  constraint smis_violation_record_item_sort_check check (sort between 0 and 999999)
);
create index if not exists smis_violation_record_item_parent_idx
  on public.smis_violation_record_item(record_id, sort);
create index if not exists smis_violation_record_item_standard_idx
  on public.smis_violation_record_item(standard_id, record_id);
create table if not exists public.smis_announcement_category (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  category_name text not null,
  sort integer not null default 10,
  status text not null default 'enabled',
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_announcement_category_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_announcement_category_id_tenant_key unique (id, tenant_id),
  constraint smis_announcement_category_name_check check (
    btrim(category_name) <> '' and char_length(category_name) <= 100
  ),
  constraint smis_announcement_category_sort_check check (sort between 0 and 999999),
  constraint smis_announcement_category_status_check check (status in ('enabled', 'disabled')),
  constraint smis_announcement_category_description_check check (
    description is null or char_length(description) <= 500
  )
);
create unique index if not exists smis_announcement_category_name_unique
  on public.smis_announcement_category(tenant_id, lower(category_name));
create index if not exists smis_announcement_category_scope_idx
  on public.smis_announcement_category(tenant_id, status, sort);
create table if not exists public.smis_announcement (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  category_id uuid not null,
  title text not null,
  content_html text not null,
  content_text text not null,
  lifecycle_status text not null default 'draft',
  audience_type text not null default 'all',
  effective_start_date date not null default current_date,
  effective_end_date date,
  is_pinned boolean not null default false,
  attachment_urls text[] not null default '{}',
  published_at timestamptz,
  published_by_user_id uuid,
  published_by_name_snapshot text,
  withdrawn_at timestamptz,
  withdrawn_by_user_id uuid,
  withdrawn_by_name_snapshot text,
  create_by_user_id uuid not null,
  create_by_name_snapshot text not null,
  create_organization_snapshot text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_announcement_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_announcement_id_tenant_key unique (id, tenant_id),
  constraint smis_announcement_category_fkey foreign key (category_id, tenant_id)
    references public.smis_announcement_category(id, tenant_id) on delete restrict,
  constraint smis_announcement_creator_fkey foreign key (create_by_user_id)
    references public.sys_user(id) on delete restrict,
  constraint smis_announcement_publisher_fkey foreign key (published_by_user_id)
    references public.sys_user(id) on delete restrict,
  constraint smis_announcement_withdrawer_fkey foreign key (withdrawn_by_user_id)
    references public.sys_user(id) on delete restrict,
  constraint smis_announcement_title_check check (
    btrim(title) <> '' and char_length(title) <= 200
  ),
  constraint smis_announcement_content_html_check check (
    btrim(content_html) <> '' and char_length(content_html) <= 200000
  ),
  constraint smis_announcement_content_text_check check (
    btrim(content_text) <> '' and char_length(content_text) <= 50000
  ),
  constraint smis_announcement_status_check check (
    lifecycle_status in ('draft', 'published', 'withdrawn')
  ),
  constraint smis_announcement_audience_check check (
    audience_type in ('all', 'employees', 'organizations')
  ),
  constraint smis_announcement_date_check check (
    effective_end_date is null or effective_end_date >= effective_start_date
  ),
  constraint smis_announcement_attachment_check check (cardinality(attachment_urls) <= 20)
);
create index if not exists smis_announcement_scope_idx
  on public.smis_announcement(tenant_id, lifecycle_status, is_pinned desc, published_at desc);
create index if not exists smis_announcement_category_idx
  on public.smis_announcement(category_id, lifecycle_status);
create index if not exists smis_announcement_effective_idx
  on public.smis_announcement(tenant_id, effective_start_date, effective_end_date);
create index if not exists smis_announcement_creator_idx
  on public.smis_announcement(create_by_user_id);
create table if not exists public.smis_announcement_audience_employee (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  announcement_id uuid not null,
  employee_id uuid not null,
  employee_no_snapshot text not null,
  employee_name_snapshot text not null,
  organization_name_snapshot text,
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_announcement_audience_employee_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_announcement_audience_employee_parent_fkey
    foreign key (announcement_id, tenant_id)
    references public.smis_announcement(id, tenant_id) on delete cascade,
  constraint smis_announcement_audience_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_announcement_audience_employee_unique unique (announcement_id, employee_id),
  constraint smis_announcement_audience_employee_sort_check check (sort between 0 and 999999)
);
create index if not exists smis_announcement_audience_employee_parent_idx
  on public.smis_announcement_audience_employee(announcement_id, sort);
create index if not exists smis_announcement_audience_employee_employee_idx
  on public.smis_announcement_audience_employee(employee_id, announcement_id);
create table if not exists public.smis_announcement_audience_organization (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  announcement_id uuid not null,
  organization_id uuid not null,
  organization_name_snapshot text not null,
  sort integer not null default 10,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_announcement_audience_org_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_announcement_audience_org_parent_fkey foreign key (announcement_id, tenant_id)
    references public.smis_announcement(id, tenant_id) on delete cascade,
  constraint smis_announcement_audience_org_fkey foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_announcement_audience_org_unique unique (announcement_id, organization_id),
  constraint smis_announcement_audience_org_sort_check check (sort between 0 and 999999)
);
create index if not exists smis_announcement_audience_org_parent_idx
  on public.smis_announcement_audience_organization(announcement_id, sort);
create index if not exists smis_announcement_audience_org_org_idx
  on public.smis_announcement_audience_organization(organization_id, announcement_id);
create table if not exists public.smis_announcement_read_receipt (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  announcement_id uuid not null,
  user_id uuid not null,
  employee_id_snapshot uuid,
  reader_name_snapshot text not null,
  organization_id_snapshot uuid,
  organization_name_snapshot text,
  read_at timestamptz not null default now(),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_announcement_receipt_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_announcement_receipt_parent_fkey foreign key (announcement_id, tenant_id)
    references public.smis_announcement(id, tenant_id) on delete cascade,
  constraint smis_announcement_receipt_user_fkey foreign key (user_id)
    references public.sys_user(id) on delete restrict,
  constraint smis_announcement_receipt_unique unique (announcement_id, user_id)
);
create index if not exists smis_announcement_receipt_parent_idx
  on public.smis_announcement_read_receipt(announcement_id, read_at desc);
create index if not exists smis_announcement_receipt_user_idx
  on public.smis_announcement_read_receipt(user_id, announcement_id);
do $triggers$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_violation_record',
    'smis_violation_record_employee',
    'smis_violation_record_item',
    'smis_announcement_category',
    'smis_announcement',
    'smis_announcement_audience_employee',
    'smis_announcement_audience_organization',
    'smis_announcement_read_receipt'
  ] loop
    execute format('drop trigger if exists %I on public.%I', v_table || '_create_audit', v_table);
    execute format(
      'create trigger %I before insert on public.%I for each row execute function public.trg_set_create_time_and_by(''true'', ''true'')',
      v_table || '_create_audit', v_table
    );
    execute format('drop trigger if exists %I on public.%I', v_table || '_update_audit', v_table);
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.trg_set_update_time_and_by()',
      v_table || '_update_audit', v_table
    );
  end loop;
end;
$triggers$;
do $security$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_violation_record',
    'smis_violation_record_employee',
    'smis_violation_record_item',
    'smis_announcement_category',
    'smis_announcement',
    'smis_announcement_audience_employee',
    'smis_announcement_audience_organization',
    'smis_announcement_read_receipt'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from anon, authenticated', v_table);
  end loop;
end;
$security$;
drop policy if exists smis_violation_record_tenant_select on public.smis_violation_record;
create policy smis_violation_record_tenant_select on public.smis_violation_record
for select to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationRecord:View')
);
drop policy if exists smis_violation_record_tenant_insert on public.smis_violation_record;
create policy smis_violation_record_tenant_insert on public.smis_violation_record
for insert to authenticated with check (
  tenant_id = app_private.current_user_tenant_id()
  and (
    app_private.has_permission('SmisViolationRecord:Add')
    or app_private.has_permission('SmisViolationRecord:Copy')
  )
);
drop policy if exists smis_violation_record_tenant_update on public.smis_violation_record;
create policy smis_violation_record_tenant_update on public.smis_violation_record
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationRecord:Edit')
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationRecord:Edit')
);
drop policy if exists smis_violation_record_tenant_delete on public.smis_violation_record;
create policy smis_violation_record_tenant_delete on public.smis_violation_record
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationRecord:Delete')
);
do $violation_child_policies$
declare
  v_table text;
  v_permission text;
begin
  foreach v_table in array array['smis_violation_record_employee', 'smis_violation_record_item'] loop
    execute format('drop policy if exists %I on public.%I', v_table || '_tenant_select', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and app_private.has_permission(''SmisViolationRecord:View''))',
      v_table || '_tenant_select', v_table
    );
    execute format('drop policy if exists %I on public.%I', v_table || '_tenant_insert', v_table);
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and (app_private.has_permission(''SmisViolationRecord:Add'') or app_private.has_permission(''SmisViolationRecord:Copy'') or app_private.has_permission(''SmisViolationRecord:Edit'')))',
      v_table || '_tenant_insert', v_table
    );
    execute format('drop policy if exists %I on public.%I', v_table || '_tenant_update', v_table);
    execute format(
      'create policy %I on public.%I for update to authenticated using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and app_private.has_permission(''SmisViolationRecord:Edit'')) with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and app_private.has_permission(''SmisViolationRecord:Edit''))',
      v_table || '_tenant_update', v_table
    );
    execute format('drop policy if exists %I on public.%I', v_table || '_tenant_delete', v_table);
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and (app_private.has_permission(''SmisViolationRecord:Edit'') or app_private.has_permission(''SmisViolationRecord:Delete'')))',
      v_table || '_tenant_delete', v_table
    );
  end loop;
end;
$violation_child_policies$;
drop policy if exists smis_announcement_category_tenant_select on public.smis_announcement_category;
create policy smis_announcement_category_tenant_select on public.smis_announcement_category
for select to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisAnnouncementCategory:View')
    or app_private.has_permission('SmisViolationAnnouncement:View')
  )
);
drop policy if exists smis_announcement_category_tenant_insert on public.smis_announcement_category;
create policy smis_announcement_category_tenant_insert on public.smis_announcement_category
for insert to authenticated with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('SmisAnnouncementCategory:Add')
);
drop policy if exists smis_announcement_category_tenant_update on public.smis_announcement_category;
create policy smis_announcement_category_tenant_update on public.smis_announcement_category
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAnnouncementCategory:Edit')
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAnnouncementCategory:Edit')
);
drop policy if exists smis_announcement_category_tenant_delete on public.smis_announcement_category;
create policy smis_announcement_category_tenant_delete on public.smis_announcement_category
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAnnouncementCategory:Delete')
);
do $announcement_policies$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_announcement',
    'smis_announcement_audience_employee',
    'smis_announcement_audience_organization',
    'smis_announcement_read_receipt'
  ] loop
    execute format('drop policy if exists %I on public.%I', v_table || '_tenant_select', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and app_private.has_permission(''SmisViolationAnnouncement:View''))',
      v_table || '_tenant_select', v_table
    );
  end loop;
end;
$announcement_policies$;
drop policy if exists smis_announcement_tenant_insert on public.smis_announcement;
create policy smis_announcement_tenant_insert on public.smis_announcement
for insert to authenticated with check (
  tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('SmisViolationAnnouncement:Add')
);
drop policy if exists smis_announcement_tenant_update on public.smis_announcement;
create policy smis_announcement_tenant_update on public.smis_announcement
for update to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisViolationAnnouncement:Edit')
    or app_private.has_permission('SmisViolationAnnouncement:Publish')
    or app_private.has_permission('SmisViolationAnnouncement:Withdraw')
  )
) with check (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and (
    app_private.has_permission('SmisViolationAnnouncement:Edit')
    or app_private.has_permission('SmisViolationAnnouncement:Publish')
    or app_private.has_permission('SmisViolationAnnouncement:Withdraw')
  )
);
drop policy if exists smis_announcement_tenant_delete on public.smis_announcement;
create policy smis_announcement_tenant_delete on public.smis_announcement
for delete to authenticated using (
  (app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisViolationAnnouncement:Delete')
);
do $announcement_child_write_policies$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_announcement_audience_employee', 'smis_announcement_audience_organization'
  ] loop
    execute format('drop policy if exists %I on public.%I', v_table || '_tenant_insert', v_table);
    execute format(
      'create policy %I on public.%I for insert to authenticated with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and (app_private.has_permission(''SmisViolationAnnouncement:Add'') or app_private.has_permission(''SmisViolationAnnouncement:Edit'')))',
      v_table || '_tenant_insert', v_table
    );
    execute format('drop policy if exists %I on public.%I', v_table || '_tenant_delete', v_table);
    execute format(
      'create policy %I on public.%I for delete to authenticated using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) and (app_private.has_permission(''SmisViolationAnnouncement:Edit'') or app_private.has_permission(''SmisViolationAnnouncement:Delete'')))',
      v_table || '_tenant_delete', v_table
    );
  end loop;
end;
$announcement_child_write_policies$;
drop policy if exists smis_announcement_receipt_tenant_insert on public.smis_announcement_read_receipt;
create policy smis_announcement_receipt_tenant_insert on public.smis_announcement_read_receipt
for insert to authenticated with check (
  tenant_id = app_private.current_user_tenant_id()
  and user_id = (select user_row.id from public.sys_user user_row
    where user_row.auth_user_id = (select auth.uid()) and user_row.deleted_at is null limit 1)
);
drop policy if exists smis_announcement_receipt_tenant_update on public.smis_announcement_read_receipt;
create policy smis_announcement_receipt_tenant_update on public.smis_announcement_read_receipt
for update to authenticated using (
  tenant_id = app_private.current_user_tenant_id()
  and user_id = (select user_row.id from public.sys_user user_row
    where user_row.auth_user_id = (select auth.uid()) and user_row.deleted_at is null limit 1)
) with check (
  tenant_id = app_private.current_user_tenant_id()
  and user_id = (select user_row.id from public.sys_user user_row
    where user_row.auth_user_id = (select auth.uid()) and user_row.deleted_at is null limit 1)
);
create or replace function public.smis_list_violation_records_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_record_no text default null,
  p_violation_keyword text default null,
  p_violator_employee_id uuid default null,
  p_start_time timestamptz default null,
  p_end_time timestamptz default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_record_no text := nullif(lower(btrim(coalesce(p_record_no, ''))), '');
  v_keyword text := nullif(lower(btrim(coalesce(p_violation_keyword, ''))), '');
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看违章记录' using errcode = '42501';
  end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisViolationRecord:View')) then
    raise exception '当前账号没有查看违章记录的权限' using errcode = '42501';
  end if;
  if p_purpose = 'export' and not app_private.has_permission('SmisViolationRecord:Export') then
    raise exception '当前账号没有导出违章记录的权限' using errcode = '42501';
  end if;
  if p_purpose not in ('list', 'export') then
    raise exception '查询用途无效' using errcode = '22023';
  end if;
  if p_start_time is not null and p_end_time is not null and p_end_time < p_start_time then
    raise exception '违章时间结束值不能早于开始值' using errcode = '22023';
  end if;

  return (
    with scoped as (
      select record.*,
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', person.employee_id,
            'employeeNo', person.employee_no_snapshot,
            'employeeName', person.employee_name_snapshot,
            'avatarUrl', person.avatar_url_snapshot,
            'organizationId', person.organization_id_snapshot,
            'organizationName', person.organization_name_snapshot,
            'positionName', person.position_name_snapshot
          ) order by person.sort, person.employee_name_snapshot)
          from public.smis_violation_record_employee person
          where person.record_id = record.id
        ), '[]'::jsonb) as violators,
        coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', item.standard_id,
            'categoryId', item.category_id_snapshot,
            'categoryName', item.category_name_snapshot,
            'standardCode', item.standard_code_snapshot,
            'standardName', item.standard_name_snapshot,
            'deductionPoints', item.deduction_points_snapshot
          ) order by item.sort, item.standard_code_snapshot)
          from public.smis_violation_record_item item
          where item.record_id = record.id
        ), '[]'::jsonb) as items
      from public.smis_violation_record record
      where (app_private.current_read_tenant_id() is null
        or record.tenant_id = app_private.current_read_tenant_id())
        and (v_record_no is null or lower(record.record_no) like '%' || v_record_no || '%')
        and (p_violator_employee_id is null or exists (
          select 1 from public.smis_violation_record_employee person
          where person.record_id = record.id and person.employee_id = p_violator_employee_id
        ))
        and (p_start_time is null or record.violation_time >= p_start_time)
        and (p_end_time is null or record.violation_time <= p_end_time)
        and (
          v_keyword is null
          or lower(coalesce(record.situation_description, '')) like '%' || v_keyword || '%'
          or exists (
            select 1 from public.smis_violation_record_item item
            where item.record_id = record.id and (
              lower(item.standard_code_snapshot) like '%' || v_keyword || '%'
              or lower(item.standard_name_snapshot) like '%' || v_keyword || '%'
              or lower(item.category_name_snapshot) like '%' || v_keyword || '%'
            )
          )
        )
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(to_jsonb(row_data) order by row_data."violationTime" desc, row_data."createTime" desc)
        from (
          select id, tenant_id as "tenantId", record_no as "recordNo",
            violation_time as "violationTime", site_id as "siteId",
            checker_employee_id as "checkerEmployeeId",
            site_name_snapshot as "siteName", site_address_snapshot as "siteAddress",
            checker_name_snapshot as "checkerName",
            checker_organization_snapshot as "checkerOrganizationName",
            checker_position_snapshot as "checkerPositionName",
            deduction_points as "deductionPoints", fine_amount as "fineAmount",
            situation_description as "situationDescription", image_urls as "imageUrls",
            remark, violators, items,
            create_by as "createBy", create_time as "createTime",
            update_by as "updateBy", update_time as "updateTime"
          from scoped
          order by violation_time desc, create_time desc
          offset v_from limit v_to - v_from + 1
        ) row_data
      ), '[]'::jsonb),
      'total', (select count(*) from scoped),
      'overview', (select jsonb_build_object(
        'total', count(*),
        'violatorCount', coalesce((select count(distinct person.employee_id)
          from public.smis_violation_record_employee person
          join scoped scoped_record on scoped_record.id = person.record_id), 0),
        'deductionPoints', coalesce(sum(deduction_points), 0),
        'fineAmount', coalesce(sum(fine_amount), 0)
      ) from scoped)
    )
  );
end;
$function$;
create or replace function public.smis_save_violation_record_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_operation text := coalesce(nullif(p_payload->>'operation', ''), case when p_id is null then 'add' else 'edit' end);
  v_violation_time timestamptz;
  v_site_id uuid;
  v_checker_id uuid;
  v_site record;
  v_checker record;
  v_employee_ids jsonb := coalesce(p_payload->'violator_employee_ids', '[]'::jsonb);
  v_standard_ids jsonb := coalesce(p_payload->'standard_ids', '[]'::jsonb);
  v_fine numeric(14, 2);
  v_points numeric(12, 2);
  v_situation text := nullif(btrim(coalesce(p_payload->>'situation_description', '')), '');
  v_images text[];
  v_remark text := nullif(btrim(coalesce(p_payload->>'remark', '')), '');
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护违章记录' using errcode = '42501';
  end if;
  if p_id is null and v_operation = 'add'
    and not app_private.has_permission('SmisViolationRecord:Add') then
    raise exception '当前账号没有新增违章记录的权限' using errcode = '42501';
  end if;
  if p_id is null and v_operation = 'copy'
    and not app_private.has_permission('SmisViolationRecord:Copy') then
    raise exception '当前账号没有复制并新增违章记录的权限' using errcode = '42501';
  end if;
  if p_id is not null and v_operation = 'edit'
    and not app_private.has_permission('SmisViolationRecord:Edit') then
    raise exception '当前账号没有编辑违章记录的权限' using errcode = '42501';
  end if;
  if (p_id is null and v_operation not in ('add', 'copy'))
    or (p_id is not null and v_operation <> 'edit') then
    raise exception '违章记录操作类型无效' using errcode = '22023';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_violation_record target where target.id = p_id
  ));
  begin
    v_site_id := (p_payload->>'site_id')::uuid;
    v_checker_id := (p_payload->>'checker_employee_id')::uuid;
    v_violation_time := coalesce(nullif(p_payload->>'violation_time', '')::timestamptz, now());
    v_fine := coalesce(nullif(p_payload->>'fine_amount', '')::numeric, 0);
  exception when invalid_text_representation or datetime_field_overflow or numeric_value_out_of_range then
    raise exception '违章地点、检查人、违章时间或罚款金额无效' using errcode = '22023';
  end;
  if jsonb_typeof(v_employee_ids) <> 'array' or jsonb_array_length(v_employee_ids) = 0 then
    raise exception '请至少选择一名违章人员' using errcode = '22023';
  end if;
  if jsonb_typeof(v_standard_ids) <> 'array' or jsonb_array_length(v_standard_ids) = 0 then
    raise exception '请至少选择一个违章项目' using errcode = '22023';
  end if;
  if jsonb_array_length(v_employee_ids) > 100 or jsonb_array_length(v_standard_ids) > 100 then
    raise exception '单条记录最多选择 100 名人员和 100 个违章项目' using errcode = '22023';
  end if;
  if jsonb_array_length(v_employee_ids) <> (
    select count(distinct value) from jsonb_array_elements_text(v_employee_ids)
  ) or jsonb_array_length(v_standard_ids) <> (
    select count(distinct value) from jsonb_array_elements_text(v_standard_ids)
  ) then
    raise exception '违章人员或违章项目不能重复' using errcode = '22023';
  end if;
  if v_fine < 0 or v_fine > 999999999999.99 then
    raise exception '罚款金额必须在有效范围内' using errcode = '22023';
  end if;
  if char_length(coalesce(v_situation, '')) > 3000 then
    raise exception '现场情况补充不能超过 3000 个字符' using errcode = '22023';
  end if;
  if char_length(coalesce(v_remark, '')) > 1000 then
    raise exception '备注不能超过 1000 个字符' using errcode = '22023';
  end if;
  begin
    select coalesce(array_agg(value), '{}') into v_images
    from jsonb_array_elements_text(coalesce(p_payload->'image_urls', '[]'::jsonb));
  exception when others then
    raise exception '违章图片格式无效' using errcode = '22023';
  end;
  if cardinality(v_images) > 12 then
    raise exception '违章图片最多上传 12 张' using errcode = '22023';
  end if;

  select site.* into v_site from public.smis_site site
  where site.id = v_site_id and site.tenant_id = v_tenant_id;
  select employee.*, organization.organization_name, position.position_name into v_checker
  from public.hr_employee employee
  left join public.sys_organization organization on organization.id = employee.organization_id
  left join public.hr_position position on position.id = employee.position_id
  where employee.id = v_checker_id and employee.tenant_id = v_tenant_id;
  if v_site.id is null then
    raise exception '所选违章地点不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  if v_checker.id is null then
    raise exception '所选检查人不在当前租户员工花名册中' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(v_employee_ids) item
    left join public.hr_employee employee
      on employee.id = item.value::uuid and employee.tenant_id = v_tenant_id
    where employee.id is null
  ) then
    raise exception '违章人员包含无效或跨租户员工' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(v_standard_ids) item
    left join public.smis_anti_violation_standard standard
      on standard.id = item.value::uuid and standard.tenant_id = v_tenant_id
      and (p_id is not null or standard.status = 'enabled')
    where standard.id is null
  ) then
    raise exception '违章项目包含不存在、已停用或跨租户标准' using errcode = 'P0002';
  end if;
  select coalesce(sum(standard.deduction_points), 0) into v_points
  from jsonb_array_elements_text(v_standard_ids) item
  join public.smis_anti_violation_standard standard
    on standard.id = item.value::uuid and standard.tenant_id = v_tenant_id;

  if p_id is null then
    insert into public.smis_violation_record(
      tenant_id, record_no, violation_time, site_id, checker_employee_id,
      site_name_snapshot, site_address_snapshot, checker_name_snapshot,
      checker_organization_snapshot, checker_position_snapshot,
      deduction_points, fine_amount, situation_description, image_urls, remark
    ) values (
      v_tenant_id, app_private.next_document_number('smis.violation_record', v_tenant_id),
      v_violation_time, v_site.id, v_checker.id, v_site.site_name, v_site.address_detail,
      v_checker.employee_name, v_checker.organization_name, v_checker.position_name,
      v_points, v_fine, v_situation, v_images, v_remark
    ) returning id into v_result;
  else
    update public.smis_violation_record set
      violation_time = v_violation_time, site_id = v_site.id,
      checker_employee_id = v_checker.id, site_name_snapshot = v_site.site_name,
      site_address_snapshot = v_site.address_detail,
      checker_name_snapshot = v_checker.employee_name,
      checker_organization_snapshot = v_checker.organization_name,
      checker_position_snapshot = v_checker.position_name,
      deduction_points = v_points, fine_amount = v_fine,
      situation_description = v_situation, image_urls = v_images, remark = v_remark
    where id = p_id and tenant_id = v_tenant_id returning id into v_result;
    if v_result is null then
      raise exception '违章记录不存在或不属于当前租户' using errcode = 'P0002';
    end if;
    delete from public.smis_violation_record_employee
      where record_id = v_result and tenant_id = v_tenant_id;
    delete from public.smis_violation_record_item
      where record_id = v_result and tenant_id = v_tenant_id;
  end if;

  insert into public.smis_violation_record_employee(
    tenant_id, record_id, employee_id, employee_no_snapshot, employee_name_snapshot,
    avatar_url_snapshot, organization_id_snapshot, organization_name_snapshot,
    position_name_snapshot, sort
  )
  select v_tenant_id, v_result, employee.id, employee.employee_no, employee.employee_name,
    employee.avatar_url, employee.organization_id, organization.organization_name,
    position.position_name, (item.ordinality - 1) * 10
  from jsonb_array_elements_text(v_employee_ids) with ordinality item(value, ordinality)
  join public.hr_employee employee
    on employee.id = item.value::uuid and employee.tenant_id = v_tenant_id
  left join public.sys_organization organization on organization.id = employee.organization_id
  left join public.hr_position position on position.id = employee.position_id;

  insert into public.smis_violation_record_item(
    tenant_id, record_id, standard_id, category_id_snapshot, category_name_snapshot,
    standard_code_snapshot, standard_name_snapshot, deduction_points_snapshot, sort
  )
  select v_tenant_id, v_result, standard.id, category.id, category.category_name,
    standard.standard_code, standard.standard_name, standard.deduction_points,
    (item.ordinality - 1) * 10
  from jsonb_array_elements_text(v_standard_ids) with ordinality item(value, ordinality)
  join public.smis_anti_violation_standard standard
    on standard.id = item.value::uuid and standard.tenant_id = v_tenant_id
  join public.smis_violation_category category
    on category.id = standard.category_id and category.tenant_id = standard.tenant_id;
  return v_result;
exception when invalid_text_representation then
  raise exception '违章人员或违章项目包含无效标识' using errcode = '22023';
end;
$function$;
create or replace function public.smis_delete_violation_records_secure(p_ids uuid[])
returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_ids, '{}')));
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除违章记录' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisViolationRecord:Delete') then
    raise exception '当前账号没有删除违章记录的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的违章记录' using errcode = '22023';
  end if;
  delete from public.smis_violation_record
  where (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
create or replace function public.smis_list_announcement_categories_secure(
  p_from integer default 0,
  p_to integer default 99,
  p_keyword text default null,
  p_status text default null,
  p_purpose text default 'list'
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 99), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看公告分类' using errcode = '42501';
  end if;
  if not (
    app_private.is_platform_super()
    or app_private.has_permission('SmisAnnouncementCategory:View')
    or app_private.has_permission('SmisViolationAnnouncement:View')
  ) then
    raise exception '当前账号没有查看公告分类的权限' using errcode = '42501';
  end if;
  if p_purpose = 'export' and not app_private.has_permission('SmisAnnouncementCategory:Export') then
    raise exception '当前账号没有导出公告分类的权限' using errcode = '42501';
  end if;
  if p_purpose not in ('list', 'export') or (p_status is not null and p_status not in ('enabled', 'disabled')) then
    raise exception '公告分类查询条件无效' using errcode = '22023';
  end if;
  return (
    with scoped as (
      select category.*,
        (select count(*) from public.smis_announcement announcement
          where announcement.category_id = category.id) as announcement_count
      from public.smis_announcement_category category
      where (app_private.current_read_tenant_id() is null
        or category.tenant_id = app_private.current_read_tenant_id())
        and (p_status is null or category.status = p_status)
        and (v_keyword is null
          or lower(category.category_name) like '%' || v_keyword || '%'
          or lower(coalesce(category.description, '')) like '%' || v_keyword || '%')
    )
    select jsonb_build_object(
      'records', coalesce((select jsonb_agg(to_jsonb(row_data) order by row_data.sort, row_data."categoryName")
        from (select id, tenant_id as "tenantId", category_name as "categoryName",
          sort, status, description, announcement_count as "announcementCount",
          create_by as "createBy", create_time as "createTime",
          update_by as "updateBy", update_time as "updateTime"
          from scoped order by sort, category_name offset v_from limit v_to - v_from + 1) row_data
      ), '[]'::jsonb),
      'total', (select count(*) from scoped),
      'overview', (select jsonb_build_object(
        'total', count(*),
        'enabled', count(*) filter (where status = 'enabled'),
        'disabled', count(*) filter (where status = 'disabled'),
        'used', count(*) filter (where announcement_count > 0)
      ) from scoped)
    )
  );
end;
$function$;
create or replace function public.smis_save_announcement_category_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_name text := btrim(coalesce(p_payload->>'category_name', ''));
  v_sort integer;
  v_status text := coalesce(nullif(p_payload->>'status', ''), 'enabled');
  v_description text := nullif(btrim(coalesce(p_payload->>'description', '')), '');
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护公告分类' using errcode = '42501';
  end if;
  if p_id is null and not app_private.has_permission('SmisAnnouncementCategory:Add') then
    raise exception '当前账号没有新增公告分类的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisAnnouncementCategory:Edit') then
    raise exception '当前账号没有编辑公告分类的权限' using errcode = '42501';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_announcement_category target where target.id = p_id
  ));
  begin
    v_sort := coalesce(nullif(p_payload->>'sort', '')::integer, 10);
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception '公告分类顺序号无效' using errcode = '22023';
  end;
  if v_name = '' or char_length(v_name) > 100 then
    raise exception '请输入不超过 100 个字符的公告分类名称' using errcode = '22023';
  end if;
  if v_sort not between 0 and 999999 or v_status not in ('enabled', 'disabled')
    or char_length(coalesce(v_description, '')) > 500 then
    raise exception '公告分类顺序、状态或说明无效' using errcode = '22023';
  end if;
  if p_id is null then
    insert into public.smis_announcement_category(
      tenant_id, category_name, sort, status, description
    ) values (v_tenant_id, v_name, v_sort, v_status, v_description)
    returning id into v_result;
  else
    update public.smis_announcement_category set
      category_name = v_name, sort = v_sort, status = v_status, description = v_description
    where id = p_id and tenant_id = v_tenant_id returning id into v_result;
    if v_result is null then
      raise exception '公告分类不存在或不属于当前租户' using errcode = 'P0002';
    end if;
  end if;
  return v_result;
exception when unique_violation then
  raise exception '当前租户已存在同名公告分类' using errcode = '23505';
end;
$function$;
create or replace function public.smis_delete_announcement_categories_secure(p_ids uuid[])
returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_ids, '{}')));
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除公告分类' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisAnnouncementCategory:Delete') then
    raise exception '当前账号没有删除公告分类的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的公告分类' using errcode = '22023';
  end if;
  delete from public.smis_announcement_category
  where (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
exception when foreign_key_violation then
  raise exception '公告分类已被公告使用，请改为停用' using errcode = '23503';
end;
$function$;
create or replace function public.smis_save_announcement_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_operation text := coalesce(nullif(p_payload->>'operation', ''), case when p_id is null then 'add' else 'edit' end);
  v_user record;
  v_category_id uuid;
  v_title text := btrim(coalesce(p_payload->>'title', ''));
  v_content_html text := btrim(coalesce(p_payload->>'content_html', ''));
  v_content_text text := btrim(coalesce(p_payload->>'content_text', ''));
  v_audience_type text := coalesce(nullif(p_payload->>'audience_type', ''), 'all');
  v_start date;
  v_end date;
  v_is_pinned boolean := coalesce((p_payload->>'is_pinned')::boolean, false);
  v_employee_ids jsonb := coalesce(p_payload->'audience_employee_ids', '[]'::jsonb);
  v_organization_ids jsonb := coalesce(p_payload->'audience_organization_ids', '[]'::jsonb);
  v_attachments text[];
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护公告' using errcode = '42501';
  end if;
  if p_id is null and v_operation = 'add'
    and not app_private.has_permission('SmisViolationAnnouncement:Add') then
    raise exception '当前账号没有新建公告的权限' using errcode = '42501';
  end if;
  if p_id is not null and v_operation = 'edit'
    and not app_private.has_permission('SmisViolationAnnouncement:Edit') then
    raise exception '当前账号没有编辑公告的权限' using errcode = '42501';
  end if;
  if (p_id is null and v_operation <> 'add') or (p_id is not null and v_operation <> 'edit') then
    raise exception '公告操作类型无效' using errcode = '22023';
  end if;
  v_tenant_id := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_announcement target where target.id = p_id
  ));
  select user_row.*, organization.organization_name into v_user
  from public.sys_user user_row
  left join public.sys_organization organization on organization.id = user_row.organization_id
  where user_row.auth_user_id = (select auth.uid()) and user_row.deleted_at is null
    and user_row.tenant_id = v_tenant_id limit 1;
  if v_user.id is null then
    raise exception '当前登录账号不存在或未关联有效租户' using errcode = '42501';
  end if;
  begin
    v_category_id := (p_payload->>'category_id')::uuid;
    v_start := coalesce(nullif(p_payload->>'effective_start_date', '')::date, current_date);
    v_end := nullif(p_payload->>'effective_end_date', '')::date;
  exception when invalid_text_representation or datetime_field_overflow then
    raise exception '公告分类或生效日期无效' using errcode = '22023';
  end;
  if v_title = '' or char_length(v_title) > 200 then
    raise exception '请输入不超过 200 个字符的公告标题' using errcode = '22023';
  end if;
  if v_content_html = '' or char_length(v_content_html) > 200000
    or v_content_text = '' or char_length(v_content_text) > 50000 then
    raise exception '请输入有效公告内容，正文不能超过 5 万个字符' using errcode = '22023';
  end if;
  if lower(v_content_html) ~ '<\s*(script|iframe|object|embed)'
    or lower(v_content_html) ~ 'javascript\s*:'
    or lower(v_content_html) ~ '\son[a-z]+\s*=' then
    raise exception '公告正文包含不安全的网页内容，请删除脚本或外部嵌入后重试' using errcode = '22023';
  end if;
  if v_audience_type not in ('all', 'employees', 'organizations')
    or (v_end is not null and v_end < v_start) then
    raise exception '公告发布范围或生效日期无效' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.smis_announcement_category category
    where category.id = v_category_id and category.tenant_id = v_tenant_id
      and category.status = 'enabled'
  ) then
    raise exception '所选公告分类不存在、已停用或不属于当前租户' using errcode = 'P0002';
  end if;
  if jsonb_typeof(v_employee_ids) <> 'array' or jsonb_typeof(v_organization_ids) <> 'array' then
    raise exception '公告发布范围格式无效' using errcode = '22023';
  end if;
  if v_audience_type = 'employees' and jsonb_array_length(v_employee_ids) = 0 then
    raise exception '按人员发布时请至少选择一名员工' using errcode = '22023';
  end if;
  if v_audience_type = 'organizations' and jsonb_array_length(v_organization_ids) = 0 then
    raise exception '按组织发布时请至少选择一个组织' using errcode = '22023';
  end if;
  if jsonb_array_length(v_employee_ids) > 500 or jsonb_array_length(v_organization_ids) > 200 then
    raise exception '单条公告最多选择 500 名员工或 200 个组织' using errcode = '22023';
  end if;
  begin
    select coalesce(array_agg(value), '{}') into v_attachments
    from jsonb_array_elements_text(coalesce(p_payload->'attachment_urls', '[]'::jsonb));
  exception when others then
    raise exception '公告附件格式无效' using errcode = '22023';
  end;
  if cardinality(v_attachments) > 20 then
    raise exception '公告附件最多上传 20 个' using errcode = '22023';
  end if;
  if v_audience_type = 'employees' and exists (
    select 1 from jsonb_array_elements_text(v_employee_ids) item
    left join public.hr_employee employee
      on employee.id = item.value::uuid and employee.tenant_id = v_tenant_id
    where employee.id is null
  ) then
    raise exception '发布范围包含无效或跨租户员工' using errcode = 'P0002';
  end if;
  if v_audience_type = 'organizations' and exists (
    select 1 from jsonb_array_elements_text(v_organization_ids) item
    left join public.sys_organization organization
      on organization.id = item.value::uuid and organization.tenant_id = v_tenant_id
    where organization.id is null
  ) then
    raise exception '发布范围包含无效或跨租户组织' using errcode = 'P0002';
  end if;
  if p_id is null then
    insert into public.smis_announcement(
      tenant_id, category_id, title, content_html, content_text, lifecycle_status,
      audience_type, effective_start_date, effective_end_date, is_pinned,
      attachment_urls, create_by_user_id, create_by_name_snapshot,
      create_organization_snapshot
    ) values (
      v_tenant_id, v_category_id, v_title, v_content_html, v_content_text, 'draft',
      v_audience_type, v_start, v_end, v_is_pinned, v_attachments, v_user.id,
      coalesce(v_user.nick_name, v_user.user_name, v_user.user_email),
      v_user.organization_name
    ) returning id into v_result;
  else
    update public.smis_announcement set
      category_id = v_category_id, title = v_title,
      content_html = v_content_html, content_text = v_content_text,
      audience_type = v_audience_type, effective_start_date = v_start,
      effective_end_date = v_end, is_pinned = v_is_pinned,
      attachment_urls = v_attachments
    where id = p_id and tenant_id = v_tenant_id and lifecycle_status = 'draft'
    returning id into v_result;
    if v_result is null then
      raise exception '仅草稿公告允许编辑' using errcode = 'P0001';
    end if;
    delete from public.smis_announcement_audience_employee
      where announcement_id = v_result and tenant_id = v_tenant_id;
    delete from public.smis_announcement_audience_organization
      where announcement_id = v_result and tenant_id = v_tenant_id;
  end if;
  if v_audience_type = 'employees' then
    insert into public.smis_announcement_audience_employee(
      tenant_id, announcement_id, employee_id, employee_no_snapshot,
      employee_name_snapshot, organization_name_snapshot, sort
    )
    select v_tenant_id, v_result, employee.id, employee.employee_no, employee.employee_name,
      organization.organization_name, (item.ordinality - 1) * 10
    from jsonb_array_elements_text(v_employee_ids) with ordinality item(value, ordinality)
    join public.hr_employee employee
      on employee.id = item.value::uuid and employee.tenant_id = v_tenant_id
    left join public.sys_organization organization on organization.id = employee.organization_id;
  elsif v_audience_type = 'organizations' then
    insert into public.smis_announcement_audience_organization(
      tenant_id, announcement_id, organization_id, organization_name_snapshot, sort
    )
    select v_tenant_id, v_result, organization.id, organization.organization_name,
      (item.ordinality - 1) * 10
    from jsonb_array_elements_text(v_organization_ids) with ordinality item(value, ordinality)
    join public.sys_organization organization
      on organization.id = item.value::uuid and organization.tenant_id = v_tenant_id;
  end if;
  return v_result;
exception when invalid_text_representation then
  raise exception '公告发布范围包含无效标识' using errcode = '22023';
end;
$function$;
create or replace function public.smis_list_announcements_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_category_id uuid default null,
  p_status text default null,
  p_start_date date default null,
  p_end_date date default null
) returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(lower(btrim(coalesce(p_keyword, ''))), '');
  v_user record;
  v_can_manage boolean;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看公告' using errcode = '42501';
  end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisViolationAnnouncement:View')) then
    raise exception '当前账号没有查看公告的权限' using errcode = '42501';
  end if;
  if p_status is not null and p_status not in ('draft', 'published', 'withdrawn', 'expired') then
    raise exception '公告状态筛选值无效' using errcode = '22023';
  end if;
  if p_start_date is not null and p_end_date is not null and p_end_date < p_start_date then
    raise exception '生效时间结束值不能早于开始值' using errcode = '22023';
  end if;
  select user_row.* into v_user from public.sys_user user_row
  where user_row.auth_user_id = (select auth.uid()) and user_row.deleted_at is null limit 1;
  if v_user.id is null then
    raise exception '当前登录账号不存在' using errcode = '42501';
  end if;
  v_can_manage := app_private.is_platform_super()
    or app_private.has_permission('SmisViolationAnnouncement:Add')
    or app_private.has_permission('SmisViolationAnnouncement:Edit')
    or app_private.has_permission('SmisViolationAnnouncement:Delete')
    or app_private.has_permission('SmisViolationAnnouncement:Publish')
    or app_private.has_permission('SmisViolationAnnouncement:Withdraw')
    or app_private.has_permission('SmisViolationAnnouncement:ReadStats');

  return (
    with recursive user_org_ancestors(id) as (
      select organization.id from public.sys_organization organization
      where organization.id = v_user.organization_id and organization.tenant_id = v_user.tenant_id
      union all
      select parent.id from public.sys_organization parent
      join public.sys_organization child on child.parent_id = parent.id
      join user_org_ancestors scoped on scoped.id = child.id
      where parent.tenant_id = v_user.tenant_id
    ), scoped as (
      select announcement.*, category.category_name,
        case
          when announcement.lifecycle_status = 'published'
            and announcement.effective_end_date is not null
            and announcement.effective_end_date < current_date then 'expired'
          else announcement.lifecycle_status
        end as display_status,
        exists(select 1 from public.smis_announcement_read_receipt receipt
          where receipt.announcement_id = announcement.id and receipt.user_id = v_user.id) as my_read,
        (select count(*) from public.smis_announcement_read_receipt receipt
          where receipt.announcement_id = announcement.id) as read_count,
        coalesce((select jsonb_agg(jsonb_build_object(
          'id', target.employee_id, 'employeeNo', target.employee_no_snapshot,
          'employeeName', target.employee_name_snapshot,
          'organizationName', target.organization_name_snapshot
        ) order by target.sort, target.employee_name_snapshot)
          from public.smis_announcement_audience_employee target
          where target.announcement_id = announcement.id), '[]'::jsonb) as audience_employees,
        coalesce((select jsonb_agg(jsonb_build_object(
          'id', target.organization_id, 'organizationName', target.organization_name_snapshot
        ) order by target.sort, target.organization_name_snapshot)
          from public.smis_announcement_audience_organization target
          where target.announcement_id = announcement.id), '[]'::jsonb) as audience_organizations
      from public.smis_announcement announcement
      join public.smis_announcement_category category
        on category.id = announcement.category_id and category.tenant_id = announcement.tenant_id
      where (app_private.current_read_tenant_id() is null
        or announcement.tenant_id = app_private.current_read_tenant_id())
        and (
          v_can_manage
          or (
            announcement.lifecycle_status = 'published'
            and announcement.effective_start_date <= current_date
            and (announcement.effective_end_date is null or announcement.effective_end_date >= current_date)
            and (
              announcement.audience_type = 'all'
              or (announcement.audience_type = 'employees' and v_user.hr_employee_id is not null and exists (
                select 1 from public.smis_announcement_audience_employee target
                where target.announcement_id = announcement.id
                  and target.employee_id = v_user.hr_employee_id
              ))
              or (announcement.audience_type = 'organizations' and exists (
                select 1 from public.smis_announcement_audience_organization target
                where target.announcement_id = announcement.id
                  and target.organization_id in (select id from user_org_ancestors)
              ))
            )
          )
        )
        and (p_category_id is null or announcement.category_id = p_category_id)
        and (p_start_date is null or announcement.effective_start_date >= p_start_date)
        and (p_end_date is null or announcement.effective_start_date <= p_end_date)
        and (v_keyword is null
          or lower(announcement.title) like '%' || v_keyword || '%'
          or lower(announcement.content_text) like '%' || v_keyword || '%'
          or lower(category.category_name) like '%' || v_keyword || '%'
          or lower(announcement.create_by_name_snapshot) like '%' || v_keyword || '%')
    ), filtered as (
      select * from scoped where p_status is null or display_status = p_status
    )
    select jsonb_build_object(
      'records', coalesce((select jsonb_agg(to_jsonb(row_data)
        order by row_data."isPinned" desc, row_data."publishedAt" desc nulls last, row_data."createTime" desc)
        from (select id, tenant_id as "tenantId", category_id as "categoryId",
          category_name as "categoryName", title, content_html as "contentHtml",
          content_text as "contentText", lifecycle_status as "lifecycleStatus",
          display_status as "displayStatus", audience_type as "audienceType",
          effective_start_date as "effectiveStartDate", effective_end_date as "effectiveEndDate",
          is_pinned as "isPinned", attachment_urls as "attachmentUrls",
          published_at as "publishedAt", published_by_name_snapshot as "publishedByName",
          withdrawn_at as "withdrawnAt", withdrawn_by_name_snapshot as "withdrawnByName",
          create_by_name_snapshot as "createByName",
          create_organization_snapshot as "createOrganizationName",
          audience_employees as "audienceEmployees",
          audience_organizations as "audienceOrganizations",
          my_read as "myRead", read_count as "readCount",
          create_time as "createTime", update_time as "updateTime"
          from filtered order by is_pinned desc, published_at desc nulls last, create_time desc
          offset v_from limit v_to - v_from + 1) row_data
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'canManage', v_can_manage,
      'overview', (select jsonb_build_object(
        'total', count(*),
        'draft', count(*) filter (where display_status = 'draft'),
        'published', count(*) filter (where display_status = 'published'),
        'expired', count(*) filter (where display_status = 'expired'),
        'unread', count(*) filter (where display_status = 'published' and not my_read)
      ) from filtered),
      'categories', coalesce((select jsonb_agg(jsonb_build_object(
        'id', category.id, 'categoryName', category.category_name
      ) order by category.sort, category.category_name)
        from public.smis_announcement_category category
        where (app_private.current_read_tenant_id() is null
          or category.tenant_id = app_private.current_read_tenant_id())
          and category.status = 'enabled'), '[]'::jsonb),
      'organizations', coalesce((select jsonb_agg(jsonb_build_object(
        'id', organization.id, 'parentId', organization.parent_id,
        'organizationCode', organization.organization_code,
        'organizationName', organization.organization_name,
        'sort', organization.sort
      ) order by organization.sort, organization.organization_name)
        from public.sys_organization organization
        where (app_private.current_read_tenant_id() is null
          or organization.tenant_id = app_private.current_read_tenant_id())
          and organization.status = '1'), '[]'::jsonb)
    )
  );
end;
$function$;
create or replace function public.smis_publish_announcement_secure(p_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_user record;
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再发布公告' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisViolationAnnouncement:Publish') then
    raise exception '当前账号没有发布公告的权限' using errcode = '42501';
  end if;
  select user_row.* into v_user from public.sys_user user_row
  where user_row.auth_user_id = (select auth.uid()) and user_row.deleted_at is null limit 1;
  update public.smis_announcement set
    lifecycle_status = 'published', published_at = now(), published_by_user_id = v_user.id,
    published_by_name_snapshot = coalesce(v_user.nick_name, v_user.user_name, v_user.user_email),
    withdrawn_at = null, withdrawn_by_user_id = null, withdrawn_by_name_snapshot = null
  where id = p_id
    and (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and lifecycle_status = 'draft'
    and (effective_end_date is null or effective_end_date >= current_date)
  returning id into v_result;
  if v_result is null then
    raise exception '仅未过期的草稿公告允许发布' using errcode = 'P0001';
  end if;
  return v_result;
end;
$function$;
create or replace function public.smis_withdraw_announcement_secure(p_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_user record;
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再撤回公告' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisViolationAnnouncement:Withdraw') then
    raise exception '当前账号没有撤回公告的权限' using errcode = '42501';
  end if;
  select user_row.* into v_user from public.sys_user user_row
  where user_row.auth_user_id = (select auth.uid()) and user_row.deleted_at is null limit 1;
  update public.smis_announcement set
    lifecycle_status = 'withdrawn', withdrawn_at = now(), withdrawn_by_user_id = v_user.id,
    withdrawn_by_name_snapshot = coalesce(v_user.nick_name, v_user.user_name, v_user.user_email)
  where id = p_id
    and (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and lifecycle_status = 'published'
  returning id into v_result;
  if v_result is null then
    raise exception '仅已发布公告允许撤回' using errcode = 'P0001';
  end if;
  return v_result;
end;
$function$;
create or replace function public.smis_delete_announcements_secure(p_ids uuid[])
returns integer
language plpgsql security definer set search_path = ''
as $function$
declare
  v_ids uuid[] := array(select distinct unnest(coalesce(p_ids, '{}')));
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除公告' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisViolationAnnouncement:Delete') then
    raise exception '当前账号没有删除公告的权限' using errcode = '42501';
  end if;
  if cardinality(v_ids) = 0 then
    raise exception '请选择要删除的公告' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.smis_announcement announcement
    where announcement.id = any(v_ids)
      and (app_private.is_platform_super() or announcement.tenant_id = app_private.auth_user_tenant_id())
      and announcement.lifecycle_status <> 'draft'
  ) then
    raise exception '仅草稿公告允许删除；已发布公告请先撤回并保留发布审计' using errcode = 'P0001';
  end if;
  delete from public.smis_announcement
  where (app_private.is_platform_super() or tenant_id = app_private.auth_user_tenant_id())
    and lifecycle_status = 'draft' and id = any(v_ids);
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;
create or replace function public.smis_mark_announcement_read_secure(p_id uuid)
returns boolean
language plpgsql security definer set search_path = ''
as $function$
declare
  v_user record;
  v_announcement record;
  v_name text;
  v_organization_name text;
  v_visible boolean := false;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查阅公告' using errcode = '42501';
  end if;
  if not (app_private.is_platform_super() or app_private.has_permission('SmisViolationAnnouncement:View')) then
    raise exception '当前账号没有查看公告的权限' using errcode = '42501';
  end if;
  select user_row.*, organization.organization_name into v_user
  from public.sys_user user_row
  left join public.sys_organization organization on organization.id = user_row.organization_id
  where user_row.auth_user_id = (select auth.uid()) and user_row.deleted_at is null limit 1;
  select * into v_announcement from public.smis_announcement announcement
  where announcement.id = p_id
    and (app_private.is_platform_super() or announcement.tenant_id = v_user.tenant_id);
  if v_announcement.id is null then
    raise exception '公告不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  if v_announcement.lifecycle_status <> 'published' then
    return false;
  end if;
  if app_private.is_platform_super()
    or app_private.has_permission('SmisViolationAnnouncement:Add')
    or app_private.has_permission('SmisViolationAnnouncement:Edit')
    or app_private.has_permission('SmisViolationAnnouncement:Publish')
    or v_announcement.audience_type = 'all'
    or (v_announcement.audience_type = 'employees' and exists (
      select 1 from public.smis_announcement_audience_employee target
      where target.announcement_id = p_id and target.employee_id = v_user.hr_employee_id
    ))
    or (v_announcement.audience_type = 'organizations' and exists (
      with recursive ancestors(id) as (
        select v_user.organization_id where v_user.organization_id is not null
        union all
        select parent.parent_id from public.sys_organization parent
        join ancestors scoped on scoped.id = parent.id
        where parent.parent_id is not null and parent.tenant_id = v_announcement.tenant_id
      )
      select 1 from public.smis_announcement_audience_organization target
      where target.announcement_id = p_id and target.organization_id in (select id from ancestors)
    )) then
    v_visible := true;
  end if;
  if not v_visible then
    raise exception '当前公告不在您的发布范围内' using errcode = '42501';
  end if;
  v_name := coalesce(v_user.nick_name, v_user.user_name, v_user.user_email);
  v_organization_name := v_user.organization_name;
  insert into public.smis_announcement_read_receipt(
    tenant_id, announcement_id, user_id, employee_id_snapshot,
    reader_name_snapshot, organization_id_snapshot, organization_name_snapshot, read_at
  ) values (
    v_announcement.tenant_id, p_id, v_user.id, v_user.hr_employee_id,
    v_name, v_user.organization_id, v_organization_name, now()
  )
  on conflict (announcement_id, user_id) do update set
    employee_id_snapshot = excluded.employee_id_snapshot,
    reader_name_snapshot = excluded.reader_name_snapshot,
    organization_id_snapshot = excluded.organization_id_snapshot,
    organization_name_snapshot = excluded.organization_name_snapshot,
    read_at = least(public.smis_announcement_read_receipt.read_at, excluded.read_at);
  return true;
end;
$function$;
create or replace function public.smis_get_announcement_read_stats_secure(p_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_announcement record;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看公告查阅情况' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisViolationAnnouncement:ReadStats') then
    raise exception '当前账号没有查看公告查阅情况的权限' using errcode = '42501';
  end if;
  select * into v_announcement from public.smis_announcement announcement
  where announcement.id = p_id
    and (app_private.is_platform_super() or announcement.tenant_id = app_private.auth_user_tenant_id());
  if v_announcement.id is null then
    raise exception '公告不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  return (
    with recursive selected_org_descendants(id) as (
      select target.organization_id
      from public.smis_announcement_audience_organization target
      where target.announcement_id = p_id
      union
      select child.id from public.sys_organization child
      join selected_org_descendants parent on child.parent_id = parent.id
      where child.tenant_id = v_announcement.tenant_id
    ), eligible_users as (
      select distinct user_row.id as user_id, user_row.hr_employee_id as employee_id,
        coalesce(employee.employee_name, user_row.nick_name, user_row.user_name, user_row.user_email) as reader_name,
        user_row.organization_id,
        coalesce(organization.organization_name, '未分配组织') as organization_name
      from public.sys_user user_row
      left join public.hr_employee employee
        on employee.id = user_row.hr_employee_id and employee.tenant_id = user_row.tenant_id
      left join public.sys_organization organization on organization.id = user_row.organization_id
      where user_row.tenant_id = v_announcement.tenant_id
        and user_row.deleted_at is null and user_row.status = '1'
        and (
          v_announcement.audience_type = 'all'
          or (v_announcement.audience_type = 'employees' and exists (
            select 1 from public.smis_announcement_audience_employee target
            where target.announcement_id = p_id and target.employee_id = user_row.hr_employee_id
          ))
          or (v_announcement.audience_type = 'organizations'
            and user_row.organization_id in (select id from selected_org_descendants))
        )
    ), detailed as (
      select eligible.*, receipt.read_at
      from eligible_users eligible
      left join public.smis_announcement_read_receipt receipt
        on receipt.announcement_id = p_id and receipt.user_id = eligible.user_id
    ), organization_rows as (
      select organization_id, organization_name,
        count(*) as total_count,
        count(*) filter (where read_at is not null) as read_count,
        count(*) filter (where read_at is null) as unread_count,
        coalesce(jsonb_agg(jsonb_build_object(
          'userId', user_id, 'employeeId', employee_id, 'readerName', reader_name,
          'readAt', read_at
        ) order by (read_at is null), reader_name), '[]'::jsonb) as readers
      from detailed group by organization_id, organization_name
    )
    select jsonb_build_object(
      'announcementId', p_id,
      'title', v_announcement.title,
      'total', (select count(*) from detailed),
      'read', (select count(*) from detailed where read_at is not null),
      'unread', (select count(*) from detailed where read_at is null),
      'organizations', coalesce((select jsonb_agg(jsonb_build_object(
        'organizationId', organization_id, 'organizationName', organization_name,
        'total', total_count, 'read', read_count, 'unread', unread_count,
        'readers', readers
      ) order by organization_name) from organization_rows), '[]'::jsonb)
    )
  );
end;
$function$;
revoke all on function public.smis_list_violation_records_secure(integer, integer, text, text, uuid, timestamptz, timestamptz, text) from public, anon, authenticated;
grant execute on function public.smis_list_violation_records_secure(integer, integer, text, text, uuid, timestamptz, timestamptz, text) to authenticated;
revoke all on function public.smis_save_violation_record_secure(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.smis_save_violation_record_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_delete_violation_records_secure(uuid[]) from public, anon, authenticated;
grant execute on function public.smis_delete_violation_records_secure(uuid[]) to authenticated;
revoke all on function public.smis_list_announcement_categories_secure(integer, integer, text, text, text) from public, anon, authenticated;
grant execute on function public.smis_list_announcement_categories_secure(integer, integer, text, text, text) to authenticated;
revoke all on function public.smis_save_announcement_category_secure(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.smis_save_announcement_category_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_delete_announcement_categories_secure(uuid[]) from public, anon, authenticated;
grant execute on function public.smis_delete_announcement_categories_secure(uuid[]) to authenticated;
revoke all on function public.smis_list_announcements_secure(integer, integer, text, uuid, text, date, date) from public, anon, authenticated;
grant execute on function public.smis_list_announcements_secure(integer, integer, text, uuid, text, date, date) to authenticated;
revoke all on function public.smis_save_announcement_secure(uuid, jsonb) from public, anon, authenticated;
grant execute on function public.smis_save_announcement_secure(uuid, jsonb) to authenticated;
revoke all on function public.smis_publish_announcement_secure(uuid) from public, anon, authenticated;
grant execute on function public.smis_publish_announcement_secure(uuid) to authenticated;
revoke all on function public.smis_withdraw_announcement_secure(uuid) from public, anon, authenticated;
grant execute on function public.smis_withdraw_announcement_secure(uuid) to authenticated;
revoke all on function public.smis_delete_announcements_secure(uuid[]) from public, anon, authenticated;
grant execute on function public.smis_delete_announcements_secure(uuid[]) to authenticated;
revoke all on function public.smis_mark_announcement_read_secure(uuid) from public, anon, authenticated;
grant execute on function public.smis_mark_announcement_read_secure(uuid) to authenticated;
revoke all on function public.smis_get_announcement_read_stats_secure(uuid) from public, anon, authenticated;
grant execute on function public.smis_get_announcement_read_stats_secure(uuid) to authenticated;
update public.sys_menu
set meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object('title', '公告管理', 'is_enable', true),
    update_by = '624944977@qq.com'
where name = 'SmisViolationAnnouncement';
insert into public.sys_menu(
  id, parent_id, name, path, component, type, meta, sort,
  create_by, update_by, app_code
)
select gen_random_uuid(), announcement.parent_id, 'SmisAnnouncementCategory',
  'announcement-category',
  '/smis/safety-production/anti-violation-management/announcement-category',
  'menu',
  jsonb_build_object(
    'title', '公告分类', 'icon', '', 'is_hide', false,
    'is_enable', true, 'roles', '[]'::jsonb
  ),
  greatest(announcement.sort - 1, 1),
  '624944977@qq.com', '624944977@qq.com', 'smis'
from public.sys_menu announcement
where announcement.name = 'SmisViolationAnnouncement'
  and not exists (
    select 1 from public.sys_menu existing where existing.name = 'SmisAnnouncementCategory'
  );
with dictionary_types(code, name, sort) as (
  values
    ('smisAnnouncementStatus', '公告状态', 53),
    ('smisAnnouncementAudienceType', '公告发布范围', 54),
    ('smisAnnouncementCategoryStatus', '公告分类状态', 55)
)
insert into public.sys_dict_type(
  id, parent_id, name, code, status, node_type, sort,
  tenant_id, create_by, update_by, remark
)
select gen_random_uuid(), parent.id, item.name, item.code, '1', 'dictionary', item.sort,
  app_private.platform_tenant_id(), '624944977@qq.com', '624944977@qq.com',
  '公告管理业务字典'
from dictionary_types item
join public.sys_dict_type parent on parent.code = 'smisSafetyProduction'
where not exists (
  select 1 from public.sys_dict_type existing where existing.code = item.code
);
with dictionary_items(type_code, suffix, value, label, color, tag_type, sort) as (
  values
    ('smisAnnouncementStatus', 'draft', 'draft', '草稿', '#64748b', 'info', 1),
    ('smisAnnouncementStatus', 'published', 'published', '生效', '#16a34a', 'success', 2),
    ('smisAnnouncementStatus', 'withdrawn', 'withdrawn', '已撤回', '#d97706', 'warning', 3),
    ('smisAnnouncementStatus', 'expired', 'expired', '已过期', '#94a3b8', 'info', 4),
    ('smisAnnouncementAudienceType', 'all', 'all', '所有人员', '#2563eb', 'primary', 1),
    ('smisAnnouncementAudienceType', 'employees', 'employees', '指定人员', '#7c3aed', 'primary', 2),
    ('smisAnnouncementAudienceType', 'organizations', 'organizations', '指定组织', '#0891b2', 'primary', 3),
    ('smisAnnouncementCategoryStatus', 'enabled', 'enabled', '启用', '#16a34a', 'success', 1),
    ('smisAnnouncementCategoryStatus', 'disabled', 'disabled', '停用', '#64748b', 'info', 2)
)
insert into public.sys_dictionary(
  id, type_id, code, status, value, label, color, tag_type, sort,
  tenant_id, create_by, update_by, remark
)
select gen_random_uuid(), type.id, item.type_code || '_' || item.suffix, '1',
  item.value, item.label, item.color, item.tag_type, item.sort,
  app_private.platform_tenant_id(), '624944977@qq.com', '624944977@qq.com',
  '公告管理默认字典项'
from dictionary_items item
join public.sys_dict_type type on type.code = item.type_code
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = type.id and existing.value = item.value
);
insert into public.smis_announcement_category(
  tenant_id, category_name, sort, status, description, create_by, update_by
)
select tenant.id, seed.category_name, seed.sort, 'enabled', seed.description,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_tenant tenant
cross join (values
  ('日常公告', 10, '面向日常经营与安全生产的信息公告'),
  ('人事管理', 20, '组织、人事与员工活动相关公告'),
  ('财务公告', 30, '财务制度、报销与经营数据相关公告')
) as seed(category_name, sort, description)
where tenant.tenant_code = 'public-register'
  and not exists (
    select 1 from public.smis_announcement_category existing
    where existing.tenant_id = tenant.id and lower(existing.category_name) = lower(seed.category_name)
  );
with scenes(rule_key, rule_name, field_label, category, menu_name, target_table,
  target_column, template, reset_cycle, remark) as (
  values (
    'smis.violation_record', '违章记录编号', '违章编号', 'business_document',
    'SmisViolationRecord', 'smis_violation_record', 'record_no',
    'WZ{YYYYMM}{SEQ:4}', 'month', '新增或复制违章记录时自动生成，每月重置 4 位流水码'
  )
)
insert into public.sys_document_number_scene(
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark,
  create_by, update_by, tenant_id
)
select scene.rule_key, scene.rule_name, scene.field_label, scene.category, menu.id,
  scene.target_table, scene.target_column, scene.template, scene.reset_cycle,
  false, true, scene.remark, '624944977@qq.com', '624944977@qq.com',
  platform_tenant.id
from scenes scene
join public.sys_menu menu on menu.name = scene.menu_name
join public.sys_tenant platform_tenant on platform_tenant.tenant_code = 'platform'
on conflict (rule_key) do update set
  rule_name = excluded.rule_name, menu_id = excluded.menu_id,
  target_table = excluded.target_table, target_column = excluded.target_column,
  default_template = excluded.default_template,
  default_reset_cycle = excluded.default_reset_cycle,
  enabled = true, update_by = excluded.update_by;
with definition(rule_key, rule_name, category, target_table, target_column,
  template, reset_cycle, remark) as (
  values (
    'smis.violation_record', '违章记录编号', 'business_document',
    'smis_violation_record', 'record_no', 'WZ{YYYYMM}{SEQ:4}', 'month',
    '新增或复制违章记录时自动生成，每月重置 4 位流水码'
  )
)
insert into public.sys_document_number_rule(
  id, tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone, rule_version,
  manual_required, builtin, enabled, remark, create_by, update_by
)
select gen_random_uuid(), tenant.id, definition.rule_key, definition.rule_name,
  definition.category, definition.target_table, definition.target_column,
  true, definition.template, definition.reset_cycle, 1, 'Asia/Shanghai', 1,
  false, true, true, definition.remark, '624944977@qq.com', '624944977@qq.com'
from public.sys_tenant tenant cross join definition
on conflict (tenant_id, rule_key) do update set
  rule_name = excluded.rule_name, target_table = excluded.target_table,
  target_column = excluded.target_column, auto_enabled = true,
  template = excluded.template, reset_cycle = excluded.reset_cycle,
  manual_required = false, enabled = true, remark = excluded.remark,
  update_by = excluded.update_by,
  rule_version = public.sys_document_number_rule.rule_version + 1;
with buttons(menu_name, code, title, sort) as (
  values
    ('SmisViolationRecord', 'SmisViolationRecord:View', '查看违章记录', 1),
    ('SmisViolationRecord', 'SmisViolationRecord:Add', '新增违章记录', 2),
    ('SmisViolationRecord', 'SmisViolationRecord:Copy', '复制并新增', 3),
    ('SmisViolationRecord', 'SmisViolationRecord:Edit', '编辑违章记录', 4),
    ('SmisViolationRecord', 'SmisViolationRecord:Delete', '删除违章记录', 5),
    ('SmisViolationRecord', 'SmisViolationRecord:Export', '导出违章记录', 6),
    ('SmisAnnouncementCategory', 'SmisAnnouncementCategory:View', '查看公告分类', 1),
    ('SmisAnnouncementCategory', 'SmisAnnouncementCategory:Add', '新增公告分类', 2),
    ('SmisAnnouncementCategory', 'SmisAnnouncementCategory:Edit', '编辑公告分类', 3),
    ('SmisAnnouncementCategory', 'SmisAnnouncementCategory:Delete', '删除公告分类', 4),
    ('SmisAnnouncementCategory', 'SmisAnnouncementCategory:Export', '导出公告分类', 5),
    ('SmisViolationAnnouncement', 'SmisViolationAnnouncement:View', '查看公告', 1),
    ('SmisViolationAnnouncement', 'SmisViolationAnnouncement:Add', '新建公告', 2),
    ('SmisViolationAnnouncement', 'SmisViolationAnnouncement:Edit', '编辑公告草稿', 3),
    ('SmisViolationAnnouncement', 'SmisViolationAnnouncement:Delete', '删除公告草稿', 4),
    ('SmisViolationAnnouncement', 'SmisViolationAnnouncement:Publish', '发布公告', 5),
    ('SmisViolationAnnouncement', 'SmisViolationAnnouncement:Withdraw', '撤回公告', 6),
    ('SmisViolationAnnouncement', 'SmisViolationAnnouncement:ReadStats', '查看查阅情况', 7)
)
insert into public.sys_menu(
  id, parent_id, name, path, component, type, meta, sort,
  create_by, update_by, app_code
)
select gen_random_uuid(), parent.id, button.code, '', '', 'button',
  jsonb_build_object(
    'title', button.title, 'is_hide', true, 'is_enable', true,
    'roles', '[]'::jsonb
  ),
  button.sort, '624944977@qq.com', '624944977@qq.com', 'smis'
from buttons button
join public.sys_menu parent on parent.name = button.menu_name
where not exists (
  select 1 from public.sys_menu existing where existing.name = button.code
);
insert into public.sys_role_menu(role_id, menu_id, tenant_id, create_by, update_by)
select distinct existing_grant.role_id, category_menu.id, existing_grant.tenant_id,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu existing_grant
join public.sys_menu announcement_menu
  on announcement_menu.id = existing_grant.menu_id
  and announcement_menu.name = 'SmisViolationAnnouncement'
join public.sys_menu category_menu on category_menu.name = 'SmisAnnouncementCategory'
on conflict (role_id, menu_id) do nothing;
insert into public.sys_role_menu(role_id, menu_id, tenant_id, create_by, update_by)
select distinct parent_grant.role_id, child.id, parent_grant.tenant_id,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu parent_grant
join public.sys_menu parent on parent.id = parent_grant.menu_id
join public.sys_menu child on child.parent_id = parent.id and child.type = 'button'
where parent.name in (
  'SmisViolationRecord', 'SmisAnnouncementCategory', 'SmisViolationAnnouncement'
)
on conflict (role_id, menu_id) do nothing;
commit;
