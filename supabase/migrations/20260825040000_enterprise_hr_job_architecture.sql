-- Enterprise HR job architecture.
-- A job profile is the reusable enterprise role; a position is an organization-owned seat.

create table public.hr_job_family (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  family_code text not null,
  family_name text not null,
  enabled boolean not null default true,
  sort integer not null default 0,
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_job_family_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_job_family_id_tenant_unique unique (id, tenant_id),
  constraint hr_job_family_code_not_blank check (btrim(family_code) <> ''),
  constraint hr_job_family_name_not_blank check (btrim(family_name) <> '')
)

create unique index hr_job_family_tenant_code_unique
  on public.hr_job_family(tenant_id, lower(family_code))

create unique index hr_job_family_tenant_name_unique
  on public.hr_job_family(tenant_id, lower(family_name))

create index hr_job_family_tenant_enabled_sort_idx
  on public.hr_job_family(tenant_id, enabled, sort, family_name)

create table public.hr_grade (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  grade_code text not null,
  grade_name text not null,
  grade_level integer not null default 1,
  enabled boolean not null default true,
  sort integer not null default 0,
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_grade_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_grade_id_tenant_unique unique (id, tenant_id),
  constraint hr_grade_code_not_blank check (btrim(grade_code) <> ''),
  constraint hr_grade_name_not_blank check (btrim(grade_name) <> ''),
  constraint hr_grade_level_positive check (grade_level > 0)
)

create unique index hr_grade_tenant_code_unique
  on public.hr_grade(tenant_id, lower(grade_code))

create unique index hr_grade_tenant_name_unique
  on public.hr_grade(tenant_id, lower(grade_name))

create index hr_grade_tenant_enabled_sort_idx
  on public.hr_grade(tenant_id, enabled, sort, grade_level, grade_name)

create table public.hr_job_profile (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  family_id uuid not null,
  default_grade_id uuid,
  job_code text not null,
  job_name text not null,
  enabled boolean not null default true,
  sort integer not null default 0,
  responsibilities text,
  requirements text,
  description text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_job_profile_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_job_profile_family_fkey foreign key (family_id, tenant_id)
    references public.hr_job_family(id, tenant_id) on delete restrict,
  constraint hr_job_profile_grade_fkey foreign key (default_grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  constraint hr_job_profile_id_tenant_unique unique (id, tenant_id),
  constraint hr_job_profile_code_not_blank check (btrim(job_code) <> ''),
  constraint hr_job_profile_name_not_blank check (btrim(job_name) <> '')
)

create unique index hr_job_profile_tenant_code_unique
  on public.hr_job_profile(tenant_id, lower(job_code))

create unique index hr_job_profile_tenant_name_unique
  on public.hr_job_profile(tenant_id, lower(job_name))

create index hr_job_profile_family_idx on public.hr_job_profile(family_id, tenant_id)

create index hr_job_profile_grade_idx on public.hr_job_profile(default_grade_id, tenant_id)
  where default_grade_id is not null

create index hr_job_profile_tenant_enabled_sort_idx
  on public.hr_job_profile(tenant_id, enabled, sort, job_name)

create trigger hr_job_family_create_audit before insert on public.hr_job_family
for each row execute function public.trg_set_create_time_and_by('true', 'true')

create trigger hr_job_family_update_audit before update on public.hr_job_family
for each row execute function public.trg_set_update_time_and_by()

create trigger hr_grade_create_audit before insert on public.hr_grade
for each row execute function public.trg_set_create_time_and_by('true', 'true')

create trigger hr_grade_update_audit before update on public.hr_grade
for each row execute function public.trg_set_update_time_and_by()

create trigger hr_job_profile_create_audit before insert on public.hr_job_profile
for each row execute function public.trg_set_create_time_and_by('true', 'true')

create trigger hr_job_profile_update_audit before update on public.hr_job_profile
for each row execute function public.trg_set_update_time_and_by()

alter table public.hr_job_family enable row level security

alter table public.hr_grade enable row level security

alter table public.hr_job_profile enable row level security

grant select, insert, update, delete on public.hr_job_family to authenticated

grant select, insert, update, delete on public.hr_grade to authenticated

grant select, insert, update, delete on public.hr_job_profile to authenticated

revoke all on public.hr_job_family from anon

revoke all on public.hr_grade from anon

revoke all on public.hr_job_profile from anon

create policy hr_job_family_tenant_select on public.hr_job_family for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:JobFamily:View'))
      or (select app_private.has_permission('Hr:JobProfile:View'))
      or (select app_private.has_permission('Hr:Position:View'))
      or (select app_private.has_permission('Hr:PersonnelChange:View'))
    )
  )
)

create policy hr_job_family_tenant_insert on public.hr_job_family for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:JobFamily:Add'))
)

create policy hr_job_family_tenant_update on public.hr_job_family for update to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('Hr:JobFamily:Edit'))
  )
)
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
)

create policy hr_job_family_tenant_delete on public.hr_job_family for delete to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('Hr:JobFamily:Delete'))
  )
)

create policy hr_grade_tenant_select on public.hr_grade for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:Grade:View'))
      or (select app_private.has_permission('Hr:JobProfile:View'))
      or (select app_private.has_permission('Hr:Position:View'))
      or (select app_private.has_permission('Hr:PersonnelChange:View'))
    )
  )
)

create policy hr_grade_tenant_insert on public.hr_grade for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:Grade:Add'))
)

create policy hr_grade_tenant_update on public.hr_grade for update to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('Hr:Grade:Edit'))
  )
)
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
)

create policy hr_grade_tenant_delete on public.hr_grade for delete to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('Hr:Grade:Delete'))
  )
)

create policy hr_job_profile_tenant_select on public.hr_job_profile for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('Hr:JobProfile:View'))
      or (select app_private.has_permission('Hr:Position:View'))
      or (select app_private.has_permission('Hr:PersonnelChange:View'))
    )
  )
)

create policy hr_job_profile_tenant_insert on public.hr_job_profile for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('Hr:JobProfile:Add'))
)

create policy hr_job_profile_tenant_update on public.hr_job_profile for update to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('Hr:JobProfile:Edit'))
  )
)
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
)

create policy hr_job_profile_tenant_delete on public.hr_job_profile for delete to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('Hr:JobProfile:Delete'))
  )
)

-- Backfill one default family and one reusable job profile per existing position name.
insert into public.hr_job_family (
  tenant_id, family_code, family_name, enabled, sort, description,
  create_by, update_by
)
select distinct
  position_row.tenant_id,
  'UNCLASSIFIED',
  '未分类职族',
  true,
  9999,
  '系统迁移生成；请在职务体系中重新归类。',
  '624944977@qq.com',
  '624944977@qq.com'
from public.hr_position position_row
on conflict (tenant_id, lower(family_code)) do nothing

insert into public.hr_job_profile (
  tenant_id, family_id, job_code, job_name, enabled, sort, description,
  create_by, update_by
)
select
  position_row.tenant_id,
  family_row.id,
  case
    when position_row.system_code is not null then upper(position_row.position_code)
    else 'JOB-' || upper(substr(replace(position_row.id::text, '-', ''), 1, 12))
  end,
  position_row.position_name,
  position_row.enabled,
  position_row.sort,
  '由历史岗位主数据迁移生成',
  '624944977@qq.com',
  '624944977@qq.com'
from public.hr_position position_row
join public.hr_job_family family_row
  on family_row.tenant_id = position_row.tenant_id
 and lower(family_row.family_code) = 'unclassified'
on conflict (tenant_id, lower(job_name)) do nothing

alter table public.hr_position
  add column organization_id uuid,
  add column job_profile_id uuid,
  add column grade_id uuid,
  add column headcount_limit integer not null default 1,
  add column multiple_incumbents_allowed boolean not null default false

update public.hr_position position_row
set organization_id = organization_source.organization_id
from (
  select
    employee_row.position_id,
    employee_row.tenant_id,
    (array_agg(employee_row.organization_id order by employee_row.organization_id::text))[1]
      as organization_id
  from public.hr_employee employee_row
  where employee_row.organization_id is not null
  group by employee_row.position_id, employee_row.tenant_id
  having count(distinct employee_row.organization_id) = 1
) organization_source
where position_row.id = organization_source.position_id
  and position_row.tenant_id = organization_source.tenant_id

update public.hr_position position_row
set job_profile_id = profile_row.id
from public.hr_job_profile profile_row
where profile_row.tenant_id = position_row.tenant_id
  and lower(profile_row.job_name) = lower(position_row.position_name)

alter table public.hr_position
  alter column job_profile_id set not null,
  add constraint hr_position_organization_tenant_fkey
    foreign key (organization_id, tenant_id)
    references public.sys_organization(id, tenant_id) on delete restrict,
  add constraint hr_position_job_profile_tenant_fkey
    foreign key (job_profile_id, tenant_id)
    references public.hr_job_profile(id, tenant_id) on delete restrict,
  add constraint hr_position_grade_tenant_fkey
    foreign key (grade_id, tenant_id)
    references public.hr_grade(id, tenant_id) on delete restrict,
  add constraint hr_position_headcount_limit_positive check (headcount_limit > 0),
  add constraint hr_position_incumbent_policy_check check (
    multiple_incumbents_allowed or headcount_limit = 1
  )

drop index public.hr_position_tenant_name_unique

create unique index hr_position_tenant_org_name_unique
  on public.hr_position(tenant_id, coalesce(organization_id, '00000000-0000-0000-0000-000000000000'::uuid), lower(position_name))

create index hr_position_organization_idx on public.hr_position(organization_id, tenant_id)
  where organization_id is not null

create index hr_position_job_profile_idx on public.hr_position(job_profile_id, tenant_id)

create index hr_position_grade_idx on public.hr_position(grade_id, tenant_id)
  where grade_id is not null

create or replace function app_private.sync_hr_employee_position_title()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
  v_job_profile public.hr_job_profile%rowtype;
begin
  select * into v_position
  from public.hr_position position_row
  where position_row.id = new.position_id
    and position_row.tenant_id = new.tenant_id;

  if not found then raise exception '所选岗位不存在或不属于员工所在租户'; end if;
  if not v_position.enabled then raise exception '所选岗位已停用'; end if;
  if v_position.organization_id is not null
     and new.organization_id is distinct from v_position.organization_id then
    raise exception '所选岗位不属于员工所在组织';
  end if;

  if tg_op = 'UPDATE' and new.position_id is distinct from old.position_id then
    if exists (
      select 1 from public.tms_driver driver_row
      where driver_row.employee_id = new.id and driver_row.tenant_id = new.tenant_id
    ) and v_position.position_kind <> 'driver' then
      raise exception '该员工已有司机档案，请先在司机管理中处理后再调整岗位';
    end if;
    if v_position.position_kind = 'driver' and not exists (
      select 1 from public.tms_driver driver_row
      where driver_row.employee_id = new.id and driver_row.tenant_id = new.tenant_id
    ) then
      raise exception '已有员工转为司机岗位时，请从司机管理选择该员工并补齐司机资料';
    end if;
  end if;

  select * into v_job_profile
  from public.hr_job_profile profile_row
  where profile_row.id = v_position.job_profile_id
    and profile_row.tenant_id = v_position.tenant_id;
  new.job_title := v_job_profile.job_name;
  return new;
end;
$function$

create or replace function public.hr_list_positions_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_enabled boolean default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:View', null, false) then
    raise exception 'Missing position view permission' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  v_limit := least(2000, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));

  with filtered as materialized (
    select
      position_row.*,
      tenant_row.tenant_code,
      tenant_row.tenant_name,
      organization_row.organization_code,
      organization_row.organization_name,
      profile_row.job_code,
      profile_row.job_name,
      grade_row.grade_code,
      grade_row.grade_name,
      (
        select count(*) from public.hr_employee employee_row
        where employee_row.position_id = position_row.id
          and employee_row.tenant_id = position_row.tenant_id
          and employee_row.employment_status <> 'terminated'
      ) as employee_count
    from public.hr_position position_row
    join public.sys_tenant tenant_row on tenant_row.id = position_row.tenant_id
    left join public.sys_organization organization_row
      on organization_row.id = position_row.organization_id
     and organization_row.tenant_id = position_row.tenant_id
    join public.hr_job_profile profile_row
      on profile_row.id = position_row.job_profile_id
     and profile_row.tenant_id = position_row.tenant_id
    left join public.hr_grade grade_row
      on grade_row.id = position_row.grade_id
     and grade_row.tenant_id = position_row.tenant_id
    where (p_tenant_id is null or position_row.tenant_id = p_tenant_id)
      and (p_enabled is null or position_row.enabled = p_enabled)
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or profile_row.job_name ilike '%' || btrim(p_keyword) || '%'
        or organization_row.organization_name ilike '%' || btrim(p_keyword) || '%'
        or position_row.description ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select * from filtered
    order by tenant_name, sort, position_name
    offset greatest(coalesce(p_from, 0), 0) limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        (to_jsonb(paged)
          - 'tenant_code' - 'tenant_name'
          - 'organization_code' - 'organization_name'
          - 'job_code' - 'job_name' - 'grade_code' - 'grade_name')
        || jsonb_build_object(
          'tenant', jsonb_build_object('id', paged.tenant_id, 'tenant_code', paged.tenant_code, 'tenant_name', paged.tenant_name),
          'organization', case when paged.organization_id is null then null else jsonb_build_object(
            'id', paged.organization_id, 'organization_code', paged.organization_code,
            'organization_name', paged.organization_name
          ) end,
          'job_profile', jsonb_build_object(
            'id', paged.job_profile_id, 'job_code', paged.job_code, 'job_name', paged.job_name
          ),
          'grade', case when paged.grade_id is null then null else jsonb_build_object(
            'id', paged.grade_id, 'grade_code', paged.grade_code, 'grade_name', paged.grade_name
          ) end
        ) order by paged.tenant_name, paged.sort, paged.position_name
      ) from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;
  return v_result;
end;
$function$

create or replace function public.hr_list_position_options_secure(
  p_tenant_id uuid default null,
  p_include_disabled boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.can_execute_business_action('HrEmployeeRoster', 'Hr:Employee:Add', null, false)
    or app_private.can_execute_business_action('HrEmployeeRoster', 'Hr:Employee:Edit', null, false)
    or app_private.can_execute_business_action('HrPosition', 'Hr:Position:View', null, false)
    or app_private.can_execute_business_action('HrPersonnelChange', 'Hr:PersonnelChange:Add', null, false)
    or app_private.can_execute_business_action('HrPersonnelChange', 'Hr:PersonnelChange:Edit', null, false)
  ) then raise exception 'Missing employee or position permission' using errcode = '42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  if p_tenant_id is null then return '[]'::jsonb; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', position_row.id,
      'tenant_id', position_row.tenant_id,
      'organization_id', position_row.organization_id,
      'position_code', position_row.position_code,
      'position_name', position_row.position_name,
      'position_kind', position_row.position_kind,
      'system_code', position_row.system_code,
      'job_profile_id', position_row.job_profile_id,
      'grade_id', position_row.grade_id,
      'headcount_limit', position_row.headcount_limit,
      'multiple_incumbents_allowed', position_row.multiple_incumbents_allowed,
      'enabled', position_row.enabled,
      'job_profile', jsonb_build_object(
        'id', profile_row.id, 'job_code', profile_row.job_code, 'job_name', profile_row.job_name
      ),
      'grade', case when grade_row.id is null then null else jsonb_build_object(
        'id', grade_row.id, 'grade_code', grade_row.grade_code, 'grade_name', grade_row.grade_name
      ) end
    ) order by position_row.sort, position_row.position_name)
    from public.hr_position position_row
    join public.hr_job_profile profile_row
      on profile_row.id = position_row.job_profile_id and profile_row.tenant_id = position_row.tenant_id
    left join public.hr_grade grade_row
      on grade_row.id = position_row.grade_id and grade_row.tenant_id = position_row.tenant_id
    where position_row.tenant_id = p_tenant_id
      and (p_include_disabled or position_row.enabled)
  ), '[]'::jsonb);
end;
$function$

create or replace function public.hr_create_position_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid;
  v_id uuid;
  v_organization_id uuid;
  v_job_profile_id uuid;
  v_grade_id uuid;
  v_headcount_limit integer;
  v_multiple boolean;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:Add', null, false) then
    raise exception 'Missing position create permission' using errcode = '42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then raise exception '岗位数据格式不正确'; end if;
  if exists (
    select 1 from jsonb_object_keys(p_payload) key
    where key <> all(array[
      'tenant_id','organization_id','job_profile_id','grade_id','position_code','position_name',
      'enabled','sort','description','headcount_limit','multiple_incumbents_allowed'
    ]::text[])
  ) then raise exception '岗位数据包含不允许写入的字段'; end if;

  v_tenant_id := case when app_private.is_platform_super()
    then nullif(p_payload->>'tenant_id', '')::uuid else app_private.current_user_tenant_id() end;
  v_organization_id := nullif(p_payload->>'organization_id', '')::uuid;
  v_job_profile_id := nullif(p_payload->>'job_profile_id', '')::uuid;
  v_grade_id := nullif(p_payload->>'grade_id', '')::uuid;
  v_headcount_limit := coalesce((p_payload->>'headcount_limit')::integer, 1);
  v_multiple := coalesce((p_payload->>'multiple_incumbents_allowed')::boolean, false);
  if v_tenant_id is null then raise exception '请选择岗位所属租户'; end if;
  if v_organization_id is null then raise exception '请选择岗位所属组织'; end if;
  if v_job_profile_id is null then raise exception '请选择岗位对应的标准职务'; end if;
  if not v_multiple and v_headcount_limit <> 1 then raise exception '单人岗位的编制人数必须为 1'; end if;

  if not exists (select 1 from public.sys_organization where id = v_organization_id and tenant_id = v_tenant_id and status = '1') then
    raise exception '所选组织不存在、已停用或不属于当前租户';
  end if;
  if not exists (select 1 from public.hr_job_profile where id = v_job_profile_id and tenant_id = v_tenant_id and enabled) then
    raise exception '所选标准职务不存在、已停用或不属于当前租户';
  end if;
  if v_grade_id is not null and not exists (select 1 from public.hr_grade where id = v_grade_id and tenant_id = v_tenant_id and enabled) then
    raise exception '所选职级不存在、已停用或不属于当前租户';
  end if;

  insert into public.hr_position (
    tenant_id, organization_id, job_profile_id, grade_id, position_code, position_name,
    enabled, sort, description, headcount_limit, multiple_incumbents_allowed, create_by
  ) values (
    v_tenant_id, v_organization_id, v_job_profile_id, v_grade_id,
    upper(btrim(p_payload->>'position_code')), btrim(p_payload->>'position_name'),
    coalesce((p_payload->>'enabled')::boolean, true), coalesce((p_payload->>'sort')::integer, 0),
    nullif(btrim(p_payload->>'description'), ''), v_headcount_limit, v_multiple,
    coalesce(auth.uid()::text, 'system')
  ) returning id into v_id;
  return v_id;
end;
$function$

create or replace function public.hr_update_position_secure(p_id uuid, p_payload jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_position public.hr_position%rowtype;
  v_organization_id uuid;
  v_job_profile_id uuid;
  v_grade_id uuid;
  v_headcount_limit integer;
  v_multiple boolean;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:Edit', null, false) then
    raise exception 'Missing position edit permission' using errcode = '42501';
  end if;
  select * into v_position from public.hr_position where id = p_id;
  if not found or (not app_private.is_platform_super() and v_position.tenant_id <> app_private.current_user_tenant_id()) then
    raise exception '岗位不存在或无权编辑';
  end if;
  if exists (
    select 1 from jsonb_object_keys(p_payload) key
    where key <> all(array[
      'organization_id','job_profile_id','grade_id','position_code','position_name','enabled','sort',
      'description','headcount_limit','multiple_incumbents_allowed'
    ]::text[])
  ) then raise exception '岗位数据包含不允许写入的字段'; end if;
  if v_position.system_code = 'driver' and (
    coalesce((p_payload->>'enabled')::boolean, v_position.enabled) = false
    or upper(coalesce(nullif(btrim(p_payload->>'position_code'), ''), v_position.position_code)) <> v_position.position_code
  ) then raise exception '系统司机岗位不可停用或修改编码'; end if;

  v_organization_id := coalesce(nullif(p_payload->>'organization_id', '')::uuid, v_position.organization_id);
  v_job_profile_id := coalesce(nullif(p_payload->>'job_profile_id', '')::uuid, v_position.job_profile_id);
  v_grade_id := case when p_payload ? 'grade_id' then nullif(p_payload->>'grade_id', '')::uuid else v_position.grade_id end;
  v_headcount_limit := coalesce((p_payload->>'headcount_limit')::integer, v_position.headcount_limit);
  v_multiple := coalesce((p_payload->>'multiple_incumbents_allowed')::boolean, v_position.multiple_incumbents_allowed);
  if v_position.system_code is null and v_organization_id is null then raise exception '请选择岗位所属组织'; end if;
  if not v_multiple and v_headcount_limit <> 1 then raise exception '单人岗位的编制人数必须为 1'; end if;
  if v_organization_id is not null and not exists (
    select 1 from public.sys_organization where id = v_organization_id and tenant_id = v_position.tenant_id and status = '1'
  ) then raise exception '所选组织不存在、已停用或不属于当前租户'; end if;
  if not exists (
    select 1 from public.hr_job_profile where id = v_job_profile_id and tenant_id = v_position.tenant_id and enabled
  ) then raise exception '所选标准职务不存在、已停用或不属于当前租户'; end if;
  if v_grade_id is not null and not exists (
    select 1 from public.hr_grade where id = v_grade_id and tenant_id = v_position.tenant_id and enabled
  ) then raise exception '所选职级不存在、已停用或不属于当前租户'; end if;

  update public.hr_position position_row
  set organization_id = v_organization_id,
      job_profile_id = v_job_profile_id,
      grade_id = v_grade_id,
      position_code = upper(coalesce(nullif(btrim(p_payload->>'position_code'), ''), position_row.position_code)),
      position_name = coalesce(nullif(btrim(p_payload->>'position_name'), ''), position_row.position_name),
      enabled = coalesce((p_payload->>'enabled')::boolean, position_row.enabled),
      sort = coalesce((p_payload->>'sort')::integer, position_row.sort),
      description = case when p_payload ? 'description' then nullif(btrim(p_payload->>'description'), '') else position_row.description end,
      headcount_limit = v_headcount_limit,
      multiple_incumbents_allowed = v_multiple,
      update_by = coalesce(auth.uid()::text, 'system'),
      update_time = now()
  where position_row.id = p_id;

  update public.hr_employee employee_row
  set organization_id = coalesce(v_organization_id, employee_row.organization_id),
      job_title = profile_row.job_name,
      update_time = now()
  from public.hr_job_profile profile_row
  where profile_row.id = v_job_profile_id
    and employee_row.position_id = p_id
    and employee_row.tenant_id = v_position.tenant_id;
  return true;
end;
$function$

-- Job architecture reads and writes stay behind permission-checked RPCs.
create or replace function public.hr_list_job_families_secure(
  p_from integer default 0, p_to integer default 499, p_keyword text default null,
  p_enabled boolean default null, p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_tenant_id uuid := app_private.current_user_tenant_id(); v_limit integer;
begin
  if not app_private.can_execute_business_action('HrJobArchitecture', 'Hr:JobFamily:View', null, false) then
    raise exception 'Missing job family view permission' using errcode = '42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  v_limit := least(2000, greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  return (with filtered as materialized (
    select family_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
      (select count(*) from public.hr_job_profile profile_row where profile_row.family_id = family_row.id) as job_profile_count
    from public.hr_job_family family_row join public.sys_tenant tenant_row on tenant_row.id = family_row.tenant_id
    where (p_tenant_id is null or family_row.tenant_id = p_tenant_id)
      and (p_enabled is null or family_row.enabled = p_enabled)
      and (nullif(btrim(p_keyword), '') is null or family_row.family_code ilike '%'||btrim(p_keyword)||'%' or family_row.family_name ilike '%'||btrim(p_keyword)||'%')
  ), paged as (select * from filtered order by tenant_name,sort,family_name offset greatest(coalesce(p_from,0),0) limit v_limit)
  select jsonb_build_object('records',coalesce((select jsonb_agg((to_jsonb(paged)-'tenant_code'-'tenant_name')||jsonb_build_object('tenant',jsonb_build_object('id',tenant_id,'tenant_code',tenant_code,'tenant_name',tenant_name)) order by tenant_name,sort,family_name) from paged),'[]'::jsonb),'total',(select count(*) from filtered)));
end;
$function$

create or replace function public.hr_list_grades_secure(
  p_from integer default 0, p_to integer default 499, p_keyword text default null,
  p_enabled boolean default null, p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_tenant_id uuid := app_private.current_user_tenant_id(); v_limit integer;
begin
  if not app_private.can_execute_business_action('HrJobArchitecture', 'Hr:Grade:View', null, false) then
    raise exception 'Missing grade view permission' using errcode = '42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  v_limit := least(2000, greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  return (with filtered as materialized (
    select grade_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
      (select count(*) from public.hr_job_profile profile_row where profile_row.default_grade_id = grade_row.id) as job_profile_count
    from public.hr_grade grade_row join public.sys_tenant tenant_row on tenant_row.id = grade_row.tenant_id
    where (p_tenant_id is null or grade_row.tenant_id = p_tenant_id)
      and (p_enabled is null or grade_row.enabled = p_enabled)
      and (nullif(btrim(p_keyword), '') is null or grade_row.grade_code ilike '%'||btrim(p_keyword)||'%' or grade_row.grade_name ilike '%'||btrim(p_keyword)||'%')
  ), paged as (select * from filtered order by tenant_name,sort,grade_level,grade_name offset greatest(coalesce(p_from,0),0) limit v_limit)
  select jsonb_build_object('records',coalesce((select jsonb_agg((to_jsonb(paged)-'tenant_code'-'tenant_name')||jsonb_build_object('tenant',jsonb_build_object('id',tenant_id,'tenant_code',tenant_code,'tenant_name',tenant_name)) order by tenant_name,sort,grade_level,grade_name) from paged),'[]'::jsonb),'total',(select count(*) from filtered)));
end;
$function$

create or replace function public.hr_list_job_profiles_secure(
  p_from integer default 0, p_to integer default 499, p_keyword text default null,
  p_enabled boolean default null, p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_tenant_id uuid := app_private.current_user_tenant_id(); v_limit integer;
begin
  if not app_private.can_execute_business_action('HrJobArchitecture', 'Hr:JobProfile:View', null, false) then
    raise exception 'Missing job profile view permission' using errcode = '42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  v_limit := least(2000, greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1));
  return (with filtered as materialized (
    select profile_row.*, tenant_row.tenant_code, tenant_row.tenant_name,
      family_row.family_code,family_row.family_name,grade_row.grade_code,grade_row.grade_name,
      (select count(*) from public.hr_position position_row where position_row.job_profile_id=profile_row.id) as position_count
    from public.hr_job_profile profile_row
    join public.sys_tenant tenant_row on tenant_row.id=profile_row.tenant_id
    join public.hr_job_family family_row on family_row.id=profile_row.family_id and family_row.tenant_id=profile_row.tenant_id
    left join public.hr_grade grade_row on grade_row.id=profile_row.default_grade_id and grade_row.tenant_id=profile_row.tenant_id
    where (p_tenant_id is null or profile_row.tenant_id=p_tenant_id)
      and (p_enabled is null or profile_row.enabled=p_enabled)
      and (nullif(btrim(p_keyword),'') is null or profile_row.job_code ilike '%'||btrim(p_keyword)||'%' or profile_row.job_name ilike '%'||btrim(p_keyword)||'%' or family_row.family_name ilike '%'||btrim(p_keyword)||'%')
  ), paged as (select * from filtered order by tenant_name,sort,job_name offset greatest(coalesce(p_from,0),0) limit v_limit)
  select jsonb_build_object('records',coalesce((select jsonb_agg((to_jsonb(paged)-'tenant_code'-'tenant_name'-'family_code'-'family_name'-'grade_code'-'grade_name')||jsonb_build_object(
    'tenant',jsonb_build_object('id',tenant_id,'tenant_code',tenant_code,'tenant_name',tenant_name),
    'family',jsonb_build_object('id',family_id,'family_code',family_code,'family_name',family_name),
    'default_grade',case when default_grade_id is null then null else jsonb_build_object('id',default_grade_id,'grade_code',grade_code,'grade_name',grade_name) end
  ) order by tenant_name,sort,job_name) from paged),'[]'::jsonb),'total',(select count(*) from filtered)));
end;
$function$

create or replace function public.hr_list_job_architecture_options_secure(p_kind text, p_tenant_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $function$
declare v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.can_execute_business_action('HrJobArchitecture', null, null, false)
    or app_private.can_execute_business_action('HrPosition', null, null, false)
    or app_private.can_execute_business_action('HrPersonnelChange', null, null, false)
  ) then raise exception 'Missing HR architecture permission' using errcode='42501'; end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  if p_tenant_id is null then return '[]'::jsonb; end if;
  if p_kind='family' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',family_code,'name',family_name) order by sort,family_name) from public.hr_job_family where tenant_id=p_tenant_id and enabled),'[]'::jsonb); end if;
  if p_kind='grade' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',grade_code,'name',grade_name,'level',grade_level) order by sort,grade_level,grade_name) from public.hr_grade where tenant_id=p_tenant_id and enabled),'[]'::jsonb); end if;
  if p_kind='profile' then return coalesce((select jsonb_agg(jsonb_build_object('id',id,'code',job_code,'name',job_name,'family_id',family_id,'default_grade_id',default_grade_id) order by sort,job_name) from public.hr_job_profile where tenant_id=p_tenant_id and enabled),'[]'::jsonb); end if;
  raise exception '不支持的职务体系选项类型';
end;
$function$

create or replace function public.hr_save_job_family_secure(p_id uuid, p_payload jsonb)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_id uuid:=coalesce(p_id,gen_random_uuid()); v_tenant_id uuid;
begin
  if not app_private.can_execute_business_action('HrJobArchitecture',case when p_id is null then 'Hr:JobFamily:Add' else 'Hr:JobFamily:Edit' end,null,false) then raise exception 'Missing job family write permission' using errcode='42501'; end if;
  v_tenant_id:=case when app_private.is_platform_super() then coalesce(nullif(p_payload->>'tenant_id','')::uuid,(select tenant_id from public.hr_job_family where id=p_id)) else app_private.current_user_tenant_id() end;
  if v_tenant_id is null then raise exception '请选择所属租户'; end if;
  insert into public.hr_job_family(id,tenant_id,family_code,family_name,enabled,sort,description)
  values(v_id,v_tenant_id,upper(btrim(p_payload->>'family_code')),btrim(p_payload->>'family_name'),coalesce((p_payload->>'enabled')::boolean,true),coalesce((p_payload->>'sort')::integer,0),nullif(btrim(p_payload->>'description'),''))
  on conflict(id) do update set family_code=excluded.family_code,family_name=excluded.family_name,enabled=excluded.enabled,sort=excluded.sort,description=excluded.description
  where hr_job_family.tenant_id=v_tenant_id;
  if not found then raise exception '职族不存在或无权编辑'; end if; return v_id;
end;
$function$

create or replace function public.hr_save_grade_secure(p_id uuid, p_payload jsonb)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_id uuid:=coalesce(p_id,gen_random_uuid()); v_tenant_id uuid;
begin
  if not app_private.can_execute_business_action('HrJobArchitecture',case when p_id is null then 'Hr:Grade:Add' else 'Hr:Grade:Edit' end,null,false) then raise exception 'Missing grade write permission' using errcode='42501'; end if;
  v_tenant_id:=case when app_private.is_platform_super() then coalesce(nullif(p_payload->>'tenant_id','')::uuid,(select tenant_id from public.hr_grade where id=p_id)) else app_private.current_user_tenant_id() end;
  if v_tenant_id is null then raise exception '请选择所属租户'; end if;
  insert into public.hr_grade(id,tenant_id,grade_code,grade_name,grade_level,enabled,sort,description)
  values(v_id,v_tenant_id,upper(btrim(p_payload->>'grade_code')),btrim(p_payload->>'grade_name'),coalesce((p_payload->>'grade_level')::integer,1),coalesce((p_payload->>'enabled')::boolean,true),coalesce((p_payload->>'sort')::integer,0),nullif(btrim(p_payload->>'description'),''))
  on conflict(id) do update set grade_code=excluded.grade_code,grade_name=excluded.grade_name,grade_level=excluded.grade_level,enabled=excluded.enabled,sort=excluded.sort,description=excluded.description
  where hr_grade.tenant_id=v_tenant_id;
  if not found then raise exception '职级不存在或无权编辑'; end if; return v_id;
end;
$function$

create or replace function public.hr_save_job_profile_secure(p_id uuid, p_payload jsonb)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_id uuid:=coalesce(p_id,gen_random_uuid()); v_tenant_id uuid; v_family_id uuid; v_grade_id uuid;
begin
  if not app_private.can_execute_business_action('HrJobArchitecture',case when p_id is null then 'Hr:JobProfile:Add' else 'Hr:JobProfile:Edit' end,null,false) then raise exception 'Missing job profile write permission' using errcode='42501'; end if;
  v_tenant_id:=case when app_private.is_platform_super() then coalesce(nullif(p_payload->>'tenant_id','')::uuid,(select tenant_id from public.hr_job_profile where id=p_id)) else app_private.current_user_tenant_id() end;
  v_family_id:=nullif(p_payload->>'family_id','')::uuid; v_grade_id:=nullif(p_payload->>'default_grade_id','')::uuid;
  if v_tenant_id is null then raise exception '请选择所属租户'; end if;
  if not exists(select 1 from public.hr_job_family where id=v_family_id and tenant_id=v_tenant_id and enabled) then raise exception '所选职族不可用'; end if;
  if v_grade_id is not null and not exists(select 1 from public.hr_grade where id=v_grade_id and tenant_id=v_tenant_id and enabled) then raise exception '所选默认职级不可用'; end if;
  insert into public.hr_job_profile(id,tenant_id,family_id,default_grade_id,job_code,job_name,enabled,sort,responsibilities,requirements,description)
  values(v_id,v_tenant_id,v_family_id,v_grade_id,upper(btrim(p_payload->>'job_code')),btrim(p_payload->>'job_name'),coalesce((p_payload->>'enabled')::boolean,true),coalesce((p_payload->>'sort')::integer,0),nullif(btrim(p_payload->>'responsibilities'),''),nullif(btrim(p_payload->>'requirements'),''),nullif(btrim(p_payload->>'description'),''))
  on conflict(id) do update set family_id=excluded.family_id,default_grade_id=excluded.default_grade_id,job_code=excluded.job_code,job_name=excluded.job_name,enabled=excluded.enabled,sort=excluded.sort,responsibilities=excluded.responsibilities,requirements=excluded.requirements,description=excluded.description
  where hr_job_profile.tenant_id=v_tenant_id;
  if not found then raise exception '标准职务不存在或无权编辑'; end if; return v_id;
end;
$function$

create or replace function public.hr_delete_job_architecture_record_secure(p_kind text,p_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $function$
declare v_tenant_id uuid:=app_private.current_user_tenant_id(); v_permission text;
begin
  v_permission:=case p_kind when 'family' then 'Hr:JobFamily:Delete' when 'grade' then 'Hr:Grade:Delete' when 'profile' then 'Hr:JobProfile:Delete' else null end;
  if v_permission is null then raise exception '不支持的职务体系记录类型'; end if;
  if not app_private.can_execute_business_action('HrJobArchitecture',v_permission,null,false) then raise exception 'Missing job architecture delete permission' using errcode='42501'; end if;
  if p_kind='family' then
    if exists(select 1 from public.hr_job_profile where family_id=p_id) then raise exception '该职族已有标准职务使用，不能删除'; end if;
    delete from public.hr_job_family where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id);
  elsif p_kind='grade' then
    if exists(select 1 from public.hr_job_profile where default_grade_id=p_id) or exists(select 1 from public.hr_position where grade_id=p_id) then raise exception '该职级正在使用，不能删除'; end if;
    delete from public.hr_grade where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id);
  else
    if exists(select 1 from public.hr_position where job_profile_id=p_id) then raise exception '该标准职务已有岗位使用，不能删除'; end if;
    delete from public.hr_job_profile where id=p_id and (app_private.is_platform_super() or tenant_id=v_tenant_id);
  end if;
  if not found then raise exception '记录不存在或无权删除'; end if; return true;
end;
$function$

revoke all on function public.hr_list_job_families_secure(integer,integer,text,boolean,uuid) from public,anon

revoke all on function public.hr_list_grades_secure(integer,integer,text,boolean,uuid) from public,anon

revoke all on function public.hr_list_job_profiles_secure(integer,integer,text,boolean,uuid) from public,anon

revoke all on function public.hr_list_job_architecture_options_secure(text,uuid) from public,anon

revoke all on function public.hr_save_job_family_secure(uuid,jsonb) from public,anon

revoke all on function public.hr_save_grade_secure(uuid,jsonb) from public,anon

revoke all on function public.hr_save_job_profile_secure(uuid,jsonb) from public,anon

revoke all on function public.hr_delete_job_architecture_record_secure(text,uuid) from public,anon

grant execute on function public.hr_list_job_families_secure(integer,integer,text,boolean,uuid) to authenticated,service_role

grant execute on function public.hr_list_grades_secure(integer,integer,text,boolean,uuid) to authenticated,service_role

grant execute on function public.hr_list_job_profiles_secure(integer,integer,text,boolean,uuid) to authenticated,service_role

grant execute on function public.hr_list_job_architecture_options_secure(text,uuid) to authenticated,service_role

grant execute on function public.hr_save_job_family_secure(uuid,jsonb) to authenticated,service_role

grant execute on function public.hr_save_grade_secure(uuid,jsonb) to authenticated,service_role

grant execute on function public.hr_save_job_profile_secure(uuid,jsonb) to authenticated,service_role

grant execute on function public.hr_delete_job_architecture_record_secure(text,uuid) to authenticated,service_role

do $$ begin
  if not exists(select 1 from public.sys_menu where id='8b8f0000-0000-4000-8000-000000000001'::uuid) then
    update public.sys_menu set sort=sort+1,update_by='624944977@qq.com',update_time=now()
    where parent_id='aa71d8bd-c141-4aef-9697-8e75433de2c2'::uuid and type='menu' and sort>=3;
  end if;
end $$

insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,app_code,create_by,update_by)
values(
  '8b8f0000-0000-4000-8000-000000000001','aa71d8bd-c141-4aef-9697-8e75433de2c2',
  'HrJobArchitecture','job-architecture','/hr/personnel/job-architecture',
  jsonb_build_object('title','职务体系','icon','ri:stack-line','is_hide',false,'is_enable',true,'keep_alive',true,'is_iframe',false,'fixed_tab',false,'show_badge',false,'show_text_badge','','is_hide_tab',false,'is_full_page',false,'active_path','','link','','roles',jsonb_build_array('R_SUPER','R_ADMIN')),
  3,'menu','hr','624944977@qq.com','624944977@qq.com'
)
on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,path=excluded.path,component=excluded.component,meta=excluded.meta,sort=excluded.sort,type=excluded.type,app_code=excluded.app_code,update_by=excluded.update_by,update_time=now()

insert into public.sys_menu(id,parent_id,name,path,component,meta,sort,type,app_code,create_by,update_by)
select row_data.id,'8b8f0000-0000-4000-8000-000000000001'::uuid,row_data.name,'','',jsonb_build_object('title',row_data.title,'icon','','is_hide',true,'is_enable',true,'roles',jsonb_build_array()),row_data.sort,'button','hr','624944977@qq.com','624944977@qq.com'
from (values
  ('8b8f0000-0000-4000-8100-000000000001'::uuid,'Hr:JobFamily:View','查看职族',1),
  ('8b8f0000-0000-4000-8100-000000000002'::uuid,'Hr:JobFamily:Add','新增职族',2),
  ('8b8f0000-0000-4000-8100-000000000003'::uuid,'Hr:JobFamily:Edit','编辑职族',3),
  ('8b8f0000-0000-4000-8100-000000000004'::uuid,'Hr:JobFamily:Delete','删除职族',4),
  ('8b8f0000-0000-4000-8100-000000000005'::uuid,'Hr:Grade:View','查看职级',5),
  ('8b8f0000-0000-4000-8100-000000000006'::uuid,'Hr:Grade:Add','新增职级',6),
  ('8b8f0000-0000-4000-8100-000000000007'::uuid,'Hr:Grade:Edit','编辑职级',7),
  ('8b8f0000-0000-4000-8100-000000000008'::uuid,'Hr:Grade:Delete','删除职级',8),
  ('8b8f0000-0000-4000-8100-000000000009'::uuid,'Hr:JobProfile:View','查看标准职务',9),
  ('8b8f0000-0000-4000-8100-000000000010'::uuid,'Hr:JobProfile:Add','新增标准职务',10),
  ('8b8f0000-0000-4000-8100-000000000011'::uuid,'Hr:JobProfile:Edit','编辑标准职务',11),
  ('8b8f0000-0000-4000-8100-000000000012'::uuid,'Hr:JobProfile:Delete','删除标准职务',12)
) as row_data(id,name,title,sort)
on conflict(id) do update set parent_id=excluded.parent_id,name=excluded.name,meta=excluded.meta,sort=excluded.sort,type=excluded.type,app_code=excluded.app_code,update_by=excluded.update_by,update_time=now()

insert into public.sys_role_menu(role_id,menu_id,tenant_id,permission,create_by,update_by)
select existing.role_id,new_menu.menu_id,existing.tenant_id,'{}'::jsonb,'624944977@qq.com','624944977@qq.com'
from public.sys_role_menu existing
cross join (values
  ('8b8f0000-0000-4000-8000-000000000001'::uuid),
  ('8b8f0000-0000-4000-8100-000000000001'::uuid),('8b8f0000-0000-4000-8100-000000000002'::uuid),
  ('8b8f0000-0000-4000-8100-000000000003'::uuid),('8b8f0000-0000-4000-8100-000000000004'::uuid),
  ('8b8f0000-0000-4000-8100-000000000005'::uuid),('8b8f0000-0000-4000-8100-000000000006'::uuid),
  ('8b8f0000-0000-4000-8100-000000000007'::uuid),('8b8f0000-0000-4000-8100-000000000008'::uuid),
  ('8b8f0000-0000-4000-8100-000000000009'::uuid),('8b8f0000-0000-4000-8100-000000000010'::uuid),
  ('8b8f0000-0000-4000-8100-000000000011'::uuid),('8b8f0000-0000-4000-8100-000000000012'::uuid)
) as new_menu(menu_id)
where existing.menu_id='7a619f4f-68c5-4ab0-97f1-7dd3a7e06c01'::uuid
on conflict(role_id,menu_id) do nothing
