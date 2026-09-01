-- SMIS (安全生产管理信息系统) - 风险分级管控核心模型。
-- 复用 sys_tenant / sys_organization / sys_user / sys_menu / sys_dictionary，
-- 本迁移只创建 SMIS 业务域数据与权限配置。

create table public.smis_site (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  organization_id uuid,
  site_code text not null,
  site_name text not null,
  address text,
  floorplan_url text,
  map_boundary jsonb,
  enabled boolean not null default true,
  sort integer not null default 0,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_site_code_not_blank check (btrim(site_code) <> ''),
  constraint smis_site_name_not_blank check (btrim(site_name) <> ''),
  constraint smis_site_tenant_code_key unique (tenant_id, site_code),
  constraint smis_site_tenant_id_id_key unique (tenant_id, id),
  constraint smis_site_organization_tenant_fkey
    foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict
);

create table public.smis_area (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  site_id uuid not null,
  parent_id uuid,
  manager_user_id uuid,
  area_code text not null,
  area_name text not null,
  floorplan_geometry jsonb,
  enabled boolean not null default true,
  sort integer not null default 0,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_area_code_not_blank check (btrim(area_code) <> ''),
  constraint smis_area_name_not_blank check (btrim(area_name) <> ''),
  constraint smis_area_tenant_id_id_key unique (tenant_id, id),
  constraint smis_area_site_code_key unique (tenant_id, site_id, area_code),
  constraint smis_area_site_tenant_fkey
    foreign key (tenant_id, site_id)
    references public.smis_site(tenant_id, id) on delete restrict,
  constraint smis_area_parent_tenant_fkey
    foreign key (tenant_id, parent_id)
    references public.smis_area(tenant_id, id) on delete restrict,
  constraint smis_area_manager_tenant_fkey
    foreign key (manager_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete restrict,
  constraint smis_area_parent_not_self check (parent_id is null or parent_id <> id)
);

create table public.smis_risk_point (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  organization_id uuid,
  site_id uuid not null,
  area_id uuid not null,
  responsible_user_id uuid,
  risk_point_no text not null,
  risk_point_name text not null,
  operation_activity text,
  risk_category text,
  possible_consequence text,
  current_risk_level text,
  status text not null default 'active',
  inspection_frequency text,
  map_geometry jsonb,
  qr_code_value text,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_point_no_not_blank check (btrim(risk_point_no) <> ''),
  constraint smis_risk_point_name_not_blank check (btrim(risk_point_name) <> ''),
  constraint smis_risk_point_level_check
    check (current_risk_level is null or current_risk_level in ('low', 'general', 'major', 'critical')),
  constraint smis_risk_point_status_check check (status in ('active', 'inactive', 'archived')),
  constraint smis_risk_point_tenant_no_key unique (tenant_id, risk_point_no),
  constraint smis_risk_point_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_point_site_tenant_fkey
    foreign key (tenant_id, site_id)
    references public.smis_site(tenant_id, id) on delete restrict,
  constraint smis_risk_point_area_tenant_fkey
    foreign key (tenant_id, area_id)
    references public.smis_area(tenant_id, id) on delete restrict,
  constraint smis_risk_point_organization_tenant_fkey
    foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_risk_point_responsible_tenant_fkey
    foreign key (responsible_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete restrict
);

create table public.smis_hazard_source (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  risk_point_id uuid not null,
  source_no text not null,
  hazard_name text not null,
  hazard_description text,
  accident_type text,
  possible_consequence text,
  existing_controls text,
  enabled boolean not null default true,
  sort integer not null default 0,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_hazard_source_no_not_blank check (btrim(source_no) <> ''),
  constraint smis_hazard_source_name_not_blank check (btrim(hazard_name) <> ''),
  constraint smis_hazard_source_tenant_id_id_key unique (tenant_id, id),
  constraint smis_hazard_source_point_no_key unique (tenant_id, risk_point_id, source_no),
  constraint smis_hazard_source_point_tenant_fkey
    foreign key (tenant_id, risk_point_id)
    references public.smis_risk_point(tenant_id, id) on delete restrict
);

create table public.smis_risk_assessment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  risk_point_id uuid not null,
  assessor_user_id uuid,
  reviewer_user_id uuid,
  version_no integer not null,
  assessment_method text not null default 'LEC',
  status text not null default 'draft',
  assessment_date date not null default current_date,
  submitted_at timestamptz,
  effective_at timestamptz,
  review_comment text,
  assessment_summary text,
  max_risk_score numeric(12, 2),
  max_risk_level text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_assessment_version_positive check (version_no > 0),
  constraint smis_risk_assessment_method_check check (assessment_method in ('LEC')),
  constraint smis_risk_assessment_status_check
    check (status in ('draft', 'submitted', 'effective', 'superseded')),
  constraint smis_risk_assessment_level_check
    check (max_risk_level is null or max_risk_level in ('low', 'general', 'major', 'critical')),
  constraint smis_risk_assessment_point_version_key unique (tenant_id, risk_point_id, version_no),
  constraint smis_risk_assessment_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_assessment_point_tenant_fkey
    foreign key (tenant_id, risk_point_id)
    references public.smis_risk_point(tenant_id, id) on delete restrict,
  constraint smis_risk_assessment_assessor_tenant_fkey
    foreign key (assessor_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete restrict,
  constraint smis_risk_assessment_reviewer_tenant_fkey
    foreign key (reviewer_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete restrict
);

create table public.smis_risk_assessment_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  assessment_id uuid not null,
  hazard_source_id uuid not null,
  likelihood numeric(8, 2) not null,
  exposure numeric(8, 2) not null,
  consequence numeric(8, 2) not null,
  risk_score numeric(12, 2) generated always as (likelihood * exposure * consequence) stored,
  risk_level text generated always as (
    case
      when likelihood * exposure * consequence >= 320 then 'critical'
      when likelihood * exposure * consequence >= 160 then 'major'
      when likelihood * exposure * consequence >= 70 then 'general'
      else 'low'
    end
  ) stored,
  evaluation_note text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_assessment_item_likelihood_positive check (likelihood > 0),
  constraint smis_risk_assessment_item_exposure_positive check (exposure > 0),
  constraint smis_risk_assessment_item_consequence_positive check (consequence > 0),
  constraint smis_risk_assessment_item_source_key unique (tenant_id, assessment_id, hazard_source_id),
  constraint smis_risk_assessment_item_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_assessment_item_assessment_tenant_fkey
    foreign key (tenant_id, assessment_id)
    references public.smis_risk_assessment(tenant_id, id) on delete cascade,
  constraint smis_risk_assessment_item_source_tenant_fkey
    foreign key (tenant_id, hazard_source_id)
    references public.smis_hazard_source(tenant_id, id) on delete restrict
);

create table public.smis_control_measure (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id) on delete restrict,
  assessment_item_id uuid not null,
  responsible_user_id uuid,
  measure_type text not null,
  measure_content text not null,
  verification_criteria text,
  target_date date,
  status text not null default 'draft',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_control_measure_type_check
    check (measure_type in ('engineering', 'administrative', 'training', 'ppe', 'emergency')),
  constraint smis_control_measure_content_not_blank check (btrim(measure_content) <> ''),
  constraint smis_control_measure_status_check check (status in ('draft', 'active', 'suspended', 'retired')),
  constraint smis_control_measure_tenant_id_id_key unique (tenant_id, id),
  constraint smis_control_measure_item_tenant_fkey
    foreign key (tenant_id, assessment_item_id)
    references public.smis_risk_assessment_item(tenant_id, id) on delete cascade,
  constraint smis_control_measure_responsible_tenant_fkey
    foreign key (responsible_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete restrict
);

create table public.smis_risk_assessment_event (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  assessment_id uuid not null,
  from_status text,
  to_status text not null,
  action text not null,
  comment text,
  actor_user_id uuid,
  create_by text,
  create_time timestamptz not null default now(),
  constraint smis_risk_assessment_event_tenant_fkey
    foreign key (tenant_id, assessment_id)
    references public.smis_risk_assessment(tenant_id, id) on delete cascade,
  constraint smis_risk_assessment_event_actor_tenant_fkey
    foreign key (actor_user_id, tenant_id)
    references public.sys_user(id, tenant_id) on delete restrict
);

create index smis_site_tenant_enabled_sort_idx
  on public.smis_site (tenant_id, enabled, sort, site_name);
create index smis_site_organization_idx on public.smis_site (organization_id);
create index smis_area_tenant_site_enabled_idx
  on public.smis_area (tenant_id, site_id, enabled, sort, area_name);
create index smis_area_parent_idx on public.smis_area (parent_id);
create index smis_area_manager_idx on public.smis_area (manager_user_id);
create index smis_risk_point_tenant_status_level_idx
  on public.smis_risk_point (tenant_id, status, current_risk_level, update_time desc);
create index smis_risk_point_site_area_idx on public.smis_risk_point (site_id, area_id);
create index smis_risk_point_organization_idx on public.smis_risk_point (organization_id);
create index smis_risk_point_responsible_idx on public.smis_risk_point (responsible_user_id);
create index smis_hazard_source_point_enabled_idx
  on public.smis_hazard_source (risk_point_id, enabled, sort);
create index smis_risk_assessment_point_status_idx
  on public.smis_risk_assessment (risk_point_id, status, version_no desc);
create unique index smis_risk_assessment_one_effective_idx
  on public.smis_risk_assessment (tenant_id, risk_point_id)
  where status = 'effective';
create index smis_risk_assessment_assessor_idx on public.smis_risk_assessment (assessor_user_id);
create index smis_risk_assessment_reviewer_idx on public.smis_risk_assessment (reviewer_user_id);
create index smis_risk_assessment_item_assessment_score_idx
  on public.smis_risk_assessment_item (assessment_id, risk_score desc);
create index smis_risk_assessment_item_source_idx
  on public.smis_risk_assessment_item (hazard_source_id);
create index smis_control_measure_item_status_idx
  on public.smis_control_measure (assessment_item_id, status, target_date);
create index smis_control_measure_responsible_idx on public.smis_control_measure (responsible_user_id);
create index smis_risk_assessment_event_assessment_time_idx
  on public.smis_risk_assessment_event (assessment_id, create_time desc);
create index smis_risk_assessment_event_actor_idx on public.smis_risk_assessment_event (actor_user_id);

create or replace function app_private.validate_smis_risk_point_area()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.smis_area area_row
    where area_row.id = new.area_id
      and area_row.site_id = new.site_id
      and area_row.tenant_id = new.tenant_id
  ) then
    raise exception '所选区域不属于当前场所' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function app_private.validate_smis_assessment_item_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.smis_risk_assessment assessment_row
    join public.smis_hazard_source source_row
      on source_row.risk_point_id = assessment_row.risk_point_id
     and source_row.tenant_id = assessment_row.tenant_id
    where assessment_row.id = new.assessment_id
      and source_row.id = new.hazard_source_id
      and assessment_row.tenant_id = new.tenant_id
  ) then
    raise exception '危险源不属于本次评估的风险点' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function app_private.guard_smis_assessment_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select assessment_row.status
    into v_status
  from public.smis_risk_assessment assessment_row
  where assessment_row.id = coalesce(new.assessment_id, old.assessment_id)
    and assessment_row.tenant_id = coalesce(new.tenant_id, old.tenant_id);

  if v_status is distinct from 'draft' then
    raise exception '只有草稿评估可以修改评估明细' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function app_private.normalize_smis_risk_assessment_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.status := 'draft';
  new.submitted_at := null;
  new.effective_at := null;
  new.reviewer_user_id := null;
  new.review_comment := null;
  new.max_risk_score := null;
  new.max_risk_level := null;
  return new;
end;
$$;

create or replace function app_private.normalize_smis_risk_point_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.current_risk_level := null;
  return new;
end;
$$;

create or replace function public.smis_transition_risk_assessment(
  p_assessment_id uuid,
  p_action text,
  p_comment text default null
)
returns public.smis_risk_assessment
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_assessment public.smis_risk_assessment%rowtype;
  v_target_status text;
  v_permission text;
  v_actor_user_id uuid := app_private.current_app_user_id();
  v_max_score numeric(12, 2);
  v_max_level text;
begin
  select * into v_assessment
  from public.smis_risk_assessment assessment_row
  where assessment_row.id = p_assessment_id
    and (
      app_private.is_platform_super()
      or assessment_row.tenant_id = app_private.current_user_tenant_id()
    )
  for update;

  if not found then
    raise exception '风险评估不存在或无权访问' using errcode = 'P0002';
  end if;

  case p_action
    when 'submit' then
      v_target_status := 'submitted';
      v_permission := 'SmisRiskPoint:Assess';
      if v_assessment.status <> 'draft' then
        raise exception '只有草稿评估可以提交';
      end if;
      if not exists (
        select 1 from public.smis_risk_assessment_item item_row
        where item_row.assessment_id = p_assessment_id
      ) then
        raise exception '请至少完成一项危险源评估后再提交';
      end if;
    when 'activate' then
      v_target_status := 'effective';
      v_permission := 'SmisRiskPoint:ActivateAssessment';
      if v_assessment.status <> 'submitted' then
        raise exception '只有已提交评估可以生效';
      end if;
    when 'withdraw' then
      v_target_status := 'draft';
      v_permission := 'SmisRiskPoint:Assess';
      if v_assessment.status <> 'submitted' then
        raise exception '只有已提交评估可以撤回';
      end if;
    else
      raise exception '不支持的评估操作';
  end case;

  if not app_private.can_execute_business_action('SmisRiskPoint', v_permission, null, false) then
    raise exception '当前账号没有执行此评估操作的权限' using errcode = '42501';
  end if;

  select item_row.risk_score, item_row.risk_level
    into v_max_score, v_max_level
  from public.smis_risk_assessment_item item_row
  where item_row.assessment_id = p_assessment_id
  order by item_row.risk_score desc, item_row.id
  limit 1;

  if p_action = 'activate' then
    update public.smis_risk_assessment existing
    set status = 'superseded'
    where existing.tenant_id = v_assessment.tenant_id
      and existing.risk_point_id = v_assessment.risk_point_id
      and existing.status = 'effective'
      and existing.id <> v_assessment.id;
  end if;

  update public.smis_risk_assessment
  set status = v_target_status,
      submitted_at = case
        when p_action = 'submit' then now()
        when p_action = 'withdraw' then null
        else submitted_at
      end,
      effective_at = case when p_action = 'activate' then now() else effective_at end,
      reviewer_user_id = case when p_action = 'activate' then v_actor_user_id else reviewer_user_id end,
      review_comment = case when p_action = 'activate' then nullif(btrim(p_comment), '') else review_comment end,
      max_risk_score = v_max_score,
      max_risk_level = v_max_level
  where id = p_assessment_id
  returning * into v_assessment;

  if p_action = 'activate' then
    update public.smis_risk_point
    set current_risk_level = v_max_level
    where id = v_assessment.risk_point_id
      and tenant_id = v_assessment.tenant_id;
  end if;

  insert into public.smis_risk_assessment_event (
    tenant_id, assessment_id, from_status, to_status, action, comment,
    actor_user_id, create_by
  ) values (
    v_assessment.tenant_id, v_assessment.id,
    case
      when p_action = 'submit' then 'draft'
      when p_action = 'activate' then 'submitted'
      else 'submitted'
    end,
    v_target_status, p_action, nullif(btrim(p_comment), ''),
    v_actor_user_id, coalesce(auth.jwt() ->> 'email', 'unknown')
  );

  return v_assessment;
end;
$$;

revoke all on function app_private.validate_smis_risk_point_area() from public, anon, authenticated, service_role;
revoke all on function app_private.validate_smis_assessment_item_source() from public, anon, authenticated, service_role;
revoke all on function app_private.guard_smis_assessment_content() from public, anon, authenticated, service_role;
revoke all on function app_private.normalize_smis_risk_assessment_insert() from public, anon, authenticated, service_role;
revoke all on function app_private.normalize_smis_risk_point_insert() from public, anon, authenticated, service_role;
revoke all on function public.smis_transition_risk_assessment(uuid, text, text) from public, anon;
grant execute on function public.smis_transition_risk_assessment(uuid, text, text) to authenticated, service_role;

create trigger smis_risk_point_area_guard
before insert or update of tenant_id, site_id, area_id on public.smis_risk_point
for each row execute function app_private.validate_smis_risk_point_area();

create trigger smis_risk_point_insert_normalizer
before insert on public.smis_risk_point
for each row execute function app_private.normalize_smis_risk_point_insert();

create trigger smis_risk_assessment_insert_normalizer
before insert on public.smis_risk_assessment
for each row execute function app_private.normalize_smis_risk_assessment_insert();

create trigger smis_risk_assessment_item_source_guard
before insert or update of tenant_id, assessment_id, hazard_source_id
on public.smis_risk_assessment_item
for each row execute function app_private.validate_smis_assessment_item_source();

create trigger smis_risk_assessment_item_draft_guard
before insert or update or delete on public.smis_risk_assessment_item
for each row execute function app_private.guard_smis_assessment_content();

create or replace function app_private.guard_smis_control_measure_content()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  select assessment_row.status
    into v_status
  from public.smis_risk_assessment_item item_row
  join public.smis_risk_assessment assessment_row
    on assessment_row.id = item_row.assessment_id
   and assessment_row.tenant_id = item_row.tenant_id
  where item_row.id = coalesce(new.assessment_item_id, old.assessment_item_id)
    and item_row.tenant_id = coalesce(new.tenant_id, old.tenant_id);

  if v_status is distinct from 'draft' then
    raise exception '只有草稿评估可以修改管控措施' using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function app_private.guard_smis_control_measure_content() from public, anon, authenticated, service_role;

create trigger smis_control_measure_draft_guard
before insert or update or delete on public.smis_control_measure
for each row execute function app_private.guard_smis_control_measure_content();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_site', 'smis_area', 'smis_risk_point', 'smis_hazard_source',
    'smis_risk_assessment', 'smis_risk_assessment_item', 'smis_control_measure'
  ] loop
    execute format(
      'create trigger %I_create_audit before insert on public.%I '
      || 'for each row execute function public.trg_set_create_time_and_by(''true'', ''true'')',
      v_table, v_table
    );
    execute format(
      'create trigger %I_update_audit before update on public.%I '
      || 'for each row execute function public.trg_set_update_time_and_by()',
      v_table, v_table
    );
    execute format(
      'create trigger %I_apply_tenant before insert or update of tenant_id on public.%I '
      || 'for each row execute function app_private.trg_apply_current_tenant_id()',
      v_table, v_table
    );
  end loop;
end;
$$;

create trigger smis_risk_assessment_event_create_audit
before insert on public.smis_risk_assessment_event
for each row execute function public.trg_set_create_time_and_by('true', 'true');

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_site', 'smis_area', 'smis_risk_point', 'smis_hazard_source',
    'smis_risk_assessment', 'smis_risk_assessment_item', 'smis_control_measure',
    'smis_risk_assessment_event'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
  end loop;
end;
$$;

-- 数据行始终按租户隔离，业务按钮权限在数据库边界再次校验。
create policy smis_site_select on public.smis_site for select to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.can_execute_business_action('SmisRiskPoint', 'SmisRiskPoint:View', null, false));
create policy smis_site_insert on public.smis_site for insert to authenticated
with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.can_execute_business_action('SmisRiskPoint', 'SmisRiskPoint:Add', null, false));
create policy smis_site_update on public.smis_site for update to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.can_execute_business_action('SmisRiskPoint', 'SmisRiskPoint:Edit', null, false))
with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.can_execute_business_action('SmisRiskPoint', 'SmisRiskPoint:Edit', null, false));
create policy smis_site_delete on public.smis_site for delete to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.can_execute_business_action('SmisRiskPoint', 'SmisRiskPoint:Delete', null, false));

do $$
declare
  v_table text;
begin
  foreach v_table in array array['smis_area', 'smis_risk_point', 'smis_hazard_source'] loop
    execute format(
      'create policy %I_select on public.%I for select to authenticated '
      || 'using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:View'', null, false))',
      v_table, v_table
    );
    execute format(
      'create policy %I_insert on public.%I for insert to authenticated '
      || 'with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:Add'', null, false))',
      v_table, v_table
    );
    execute format(
      'create policy %I_update on public.%I for update to authenticated '
      || 'using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:Edit'', null, false)) '
      || 'with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:Edit'', null, false))',
      v_table, v_table
    );
    execute format(
      'create policy %I_delete on public.%I for delete to authenticated '
      || 'using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:Delete'', null, false))',
      v_table, v_table
    );
  end loop;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'smis_risk_assessment', 'smis_risk_assessment_item', 'smis_control_measure'
  ] loop
    execute format(
      'create policy %I_select on public.%I for select to authenticated '
      || 'using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:View'', null, false))',
      v_table, v_table
    );
    execute format(
      'create policy %I_insert on public.%I for insert to authenticated '
      || 'with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:Assess'', null, false))',
      v_table, v_table
    );
    execute format(
      'create policy %I_update on public.%I for update to authenticated '
      || 'using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:Assess'', null, false)) '
      || 'with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:Assess'', null, false))',
      v_table, v_table
    );
    execute format(
      'create policy %I_delete on public.%I for delete to authenticated '
      || 'using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id()) '
      || 'and app_private.can_execute_business_action(''SmisRiskPoint'', ''SmisRiskPoint:Assess'', null, false))',
      v_table, v_table
    );
  end loop;
end;
$$;

create policy smis_risk_assessment_event_select
on public.smis_risk_assessment_event for select to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.can_execute_business_action('SmisRiskPoint', 'SmisRiskPoint:View', null, false));
create policy smis_risk_assessment_event_insert
on public.smis_risk_assessment_event for insert to authenticated
with check (false);

grant select, insert, delete on table
  public.smis_site,
  public.smis_area,
  public.smis_risk_point,
  public.smis_hazard_source,
  public.smis_risk_assessment,
  public.smis_risk_assessment_item,
  public.smis_control_measure
to authenticated, service_role;
grant update (organization_id, site_code, site_name, address, floorplan_url, map_boundary, enabled, sort, remark)
  on public.smis_site to authenticated;
grant update (site_id, parent_id, manager_user_id, area_code, area_name, floorplan_geometry, enabled, sort, remark)
  on public.smis_area to authenticated;
grant update (organization_id, site_id, area_id, responsible_user_id, risk_point_no, risk_point_name,
  operation_activity, risk_category, possible_consequence, status, inspection_frequency, map_geometry,
  qr_code_value, remark)
  on public.smis_risk_point to authenticated;
grant update (risk_point_id, source_no, hazard_name, hazard_description, accident_type,
  possible_consequence, existing_controls, enabled, sort, remark)
  on public.smis_hazard_source to authenticated;
grant update (risk_point_id, assessor_user_id, version_no, assessment_date, assessment_summary)
  on public.smis_risk_assessment to authenticated;
grant update (assessment_id, hazard_source_id, likelihood, exposure, consequence, evaluation_note)
  on public.smis_risk_assessment_item to authenticated;
grant update (assessment_item_id, responsible_user_id, measure_type, measure_content,
  verification_criteria, target_date, status)
  on public.smis_control_measure to authenticated;
grant update on table
  public.smis_site,
  public.smis_area,
  public.smis_risk_point,
  public.smis_hazard_source,
  public.smis_risk_assessment,
  public.smis_risk_assessment_item,
  public.smis_control_measure
to service_role;
grant select on table public.smis_risk_assessment_event to authenticated, service_role;
grant insert on table public.smis_risk_assessment_event to service_role;

-- 复用现有字典管理：这里只注册 SMIS 字典数据，不创建新的字典页面。
do $$
declare
  v_type_id uuid;
begin
  insert into public.sys_dict_type (name, code, status, create_by, remark, node_type, sort)
  values ('SMIS风险等级', 'smisRiskLevel', '1', 'migration', 'LEC评估结果等级', 'dictionary', 610)
  on conflict do nothing;
  select id into v_type_id from public.sys_dict_type where code = 'smisRiskLevel' limit 1;
  insert into public.sys_dictionary (type_id, code, status, create_by, value, label, color, sort, tag_type)
  values
    (v_type_id, 'low', '1', 'migration', 'low', '低风险', '#67c23a', 1, 'success'),
    (v_type_id, 'general', '1', 'migration', 'general', '一般风险', '#e6a23c', 2, 'warning'),
    (v_type_id, 'major', '1', 'migration', 'major', '较大风险', '#f56c6c', 3, 'danger'),
    (v_type_id, 'critical', '1', 'migration', 'critical', '重大风险', '#c45656', 4, 'danger')
  on conflict do nothing;

  insert into public.sys_dict_type (name, code, status, create_by, remark, node_type, sort)
  values ('SMIS风险点状态', 'smisRiskPointStatus', '1', 'migration', '风险点业务状态', 'dictionary', 611)
  on conflict do nothing;
  select id into v_type_id from public.sys_dict_type where code = 'smisRiskPointStatus' limit 1;
  insert into public.sys_dictionary (type_id, code, status, create_by, value, label, sort, tag_type)
  values
    (v_type_id, 'active', '1', 'migration', 'active', '启用', 1, 'success'),
    (v_type_id, 'inactive', '1', 'migration', 'inactive', '停用', 2, 'info'),
    (v_type_id, 'archived', '1', 'migration', 'archived', '已归档', 3, 'info')
  on conflict do nothing;

  insert into public.sys_dict_type (name, code, status, create_by, remark, node_type, sort)
  values ('SMIS管控措施类型', 'smisControlMeasureType', '1', 'migration', '风险管控措施分类', 'dictionary', 612)
  on conflict do nothing;
  select id into v_type_id from public.sys_dict_type where code = 'smisControlMeasureType' limit 1;
  insert into public.sys_dictionary (type_id, code, status, create_by, value, label, sort)
  values
    (v_type_id, 'engineering', '1', 'migration', 'engineering', '工程技术', 1),
    (v_type_id, 'administrative', '1', 'migration', 'administrative', '管理措施', 2),
    (v_type_id, 'training', '1', 'migration', 'training', '教育培训', 3),
    (v_type_id, 'ppe', '1', 'migration', 'ppe', '个体防护', 4),
    (v_type_id, 'emergency', '1', 'migration', 'emergency', '应急处置', 5)
  on conflict do nothing;
end;
$$;

-- 动态菜单与按钮权限。普通角色默认只读，租户管理员拥有本批次维护权限。
do $$
declare
  v_root_id uuid;
  v_control_id uuid;
  v_page_id uuid;
  v_button record;
  v_role record;
begin
  select id into v_root_id from public.sys_menu where name = 'SmisSafetyProduction' limit 1;
  if v_root_id is null then
    insert into public.sys_menu (parent_id, name, path, component, type, meta, sort, create_by)
    values (
      null, 'SmisSafetyProduction', '/smis', '/index/index', 'folder',
      '{"icon":"ri:shield-check-line","roles":[],"title":"SMIS安全生产","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
      13, 'migration'
    ) returning id into v_root_id;
  end if;

  select id into v_control_id from public.sys_menu where name = 'SmisRiskControl' limit 1;
  if v_control_id is null then
    insert into public.sys_menu (parent_id, name, path, component, type, meta, sort, create_by)
    values (
      v_root_id, 'SmisRiskControl', 'risk-control', '/index/index', 'folder',
      '{"icon":"ri:radar-line","roles":[],"title":"风险分级管控","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
      1, 'migration'
    ) returning id into v_control_id;
  end if;

  select id into v_page_id from public.sys_menu where name = 'SmisRiskPoint' limit 1;
  if v_page_id is null then
    insert into public.sys_menu (parent_id, name, path, component, type, meta, sort, create_by)
    values (
      v_control_id, 'SmisRiskPoint', 'risk-point', '/smis/risk-control/risk-point', 'menu',
      '{"icon":"ri:map-pin-warning-line","roles":[],"title":"风险点管理","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
      1, 'migration'
    ) returning id into v_page_id;
  end if;

  for v_button in
    select * from (values
      ('SmisRiskPoint:View', '查看风险点', 1),
      ('SmisRiskPoint:Add', '新增风险点', 2),
      ('SmisRiskPoint:Edit', '编辑风险点', 3),
      ('SmisRiskPoint:Delete', '删除风险点', 4),
      ('SmisRiskPoint:Assess', '维护风险评估', 5),
      ('SmisRiskPoint:ActivateAssessment', '评估生效', 6)
    ) as buttons(name, title, sort)
  loop
    if not exists (select 1 from public.sys_menu where name = v_button.name and type = 'button') then
      insert into public.sys_menu (parent_id, name, path, component, type, meta, sort, create_by)
      values (
        v_page_id, v_button.name, '', '', 'button',
        jsonb_build_object('icon', '', 'roles', '[]'::jsonb, 'title', v_button.title, 'is_enable', true),
        v_button.sort, 'migration'
      );
    end if;
  end loop;

  for v_role in select id, tenant_id, role_code from public.sys_role where enabled is true loop
    insert into public.sys_role_menu (role_id, menu_id, tenant_id, permission, create_by)
    select v_role.id, menu_id, v_role.tenant_id, '{}'::jsonb, 'migration'
    from unnest(array[v_root_id, v_control_id, v_page_id]) as selected(menu_id)
    where not exists (
      select 1 from public.sys_role_menu existing
      where existing.role_id = v_role.id
        and existing.menu_id = selected.menu_id
        and existing.tenant_id = v_role.tenant_id
    );

    insert into public.sys_role_menu (role_id, menu_id, tenant_id, permission, create_by)
    select v_role.id, menu_row.id, v_role.tenant_id, '{}'::jsonb, 'migration'
    from public.sys_menu menu_row
    where menu_row.name = 'SmisRiskPoint:View'
      and menu_row.type = 'button'
      and not exists (
        select 1 from public.sys_role_menu existing
        where existing.role_id = v_role.id
          and existing.menu_id = menu_row.id
          and existing.tenant_id = v_role.tenant_id
      );

    if v_role.role_code in ('R_ADMIN', 'R_SUPER') then
      insert into public.sys_role_menu (role_id, menu_id, tenant_id, permission, create_by)
      select v_role.id, menu_row.id, v_role.tenant_id, '{}'::jsonb, 'migration'
      from public.sys_menu menu_row
      where menu_row.name in (
        'SmisRiskPoint:Add', 'SmisRiskPoint:Edit', 'SmisRiskPoint:Delete',
        'SmisRiskPoint:Assess', 'SmisRiskPoint:ActivateAssessment'
      )
        and menu_row.type = 'button'
        and not exists (
          select 1 from public.sys_role_menu existing
          where existing.role_id = v_role.id
            and existing.menu_id = menu_row.id
            and existing.tenant_id = v_role.tenant_id
        );
    end if;
  end loop;
end;
$$;

comment on table public.smis_site is 'SMIS生产经营场所，组织/租户信息复用系统主数据';
comment on table public.smis_area is 'SMIS场所内区域，可保存平面图多边形坐标';
comment on table public.smis_risk_point is 'SMIS风险点台账，当前风险等级由生效评估回写';
comment on table public.smis_hazard_source is 'SMIS风险点下的危险源辨识记录';
comment on table public.smis_risk_assessment is 'SMIS风险评估版本与生效状态';
comment on table public.smis_risk_assessment_item is 'SMIS LEC评估明细，D值和等级由数据库规则计算';
comment on table public.smis_control_measure is 'SMIS评估明细对应的风险管控措施';
comment on table public.smis_risk_assessment_event is 'SMIS风险评估状态流转审计事件';

;
