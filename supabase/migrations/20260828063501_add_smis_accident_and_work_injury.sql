-- SMIS 事故快报与工伤申报。
-- 事故人员字段是法律与审计场景下的时间点快照；员工主数据后续变更不会改写历史记录。

create table public.smis_accident_report (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  accident_no text not null,
  accident_name text not null,
  reporter_employee_id uuid not null,
  accident_time timestamptz not null,
  accident_location text not null,
  accident_categories text[] not null default '{}',
  operation_area_organization_id uuid,
  accident_level text not null,
  indirect_economic_loss numeric(14,2) not null default 0,
  cause_analysis text,
  result_determination text,
  image_urls text[] not null default '{}',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_accident_report_id_tenant_key unique (id, tenant_id),
  constraint smis_accident_report_tenant_no_key unique (tenant_id, accident_no),
  constraint smis_accident_report_reporter_fkey foreign key (reporter_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_accident_report_operation_area_fkey foreign key (tenant_id, operation_area_organization_id)
    references public.sys_organization(tenant_id, id),
  constraint smis_accident_report_name_check check (char_length(btrim(accident_name)) between 1 and 160),
  constraint smis_accident_report_location_check check (char_length(btrim(accident_location)) between 1 and 300),
  constraint smis_accident_report_categories_check check (cardinality(accident_categories) > 0),
  constraint smis_accident_report_level_check check (
    accident_level in ('near_miss', 'minor_injury', 'general', 'major', 'severe', 'catastrophic')
  ),
  constraint smis_accident_report_loss_check check (indirect_economic_loss >= 0)
);
comment on table public.smis_accident_report is '租户级安全事故快报主档';
comment on column public.smis_accident_report.accident_categories is '事故类别字典值数组，支持多选';
create table public.smis_accident_prevention_measure (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  accident_report_id uuid not null,
  planned_measure text not null,
  planned_implementation_date date,
  responsible_employee_id uuid,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_accident_prevention_measure_id_tenant_key unique (id, tenant_id),
  constraint smis_accident_prevention_measure_report_fkey foreign key (accident_report_id, tenant_id)
    references public.smis_accident_report(id, tenant_id) on delete cascade,
  constraint smis_accident_prevention_measure_responsible_fkey foreign key (responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_accident_prevention_measure_text_check check (char_length(btrim(planned_measure)) between 1 and 1000),
  constraint smis_accident_prevention_measure_sort_check check (sort >= 0)
);
comment on table public.smis_accident_prevention_measure is '事故快报防范措施子表';
create table public.smis_accident_person (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  accident_report_id uuid not null,
  employee_id uuid not null,
  company_name text,
  operation_department_name text,
  operation_area_name text,
  team_name text,
  employee_no text not null,
  employee_name text not null,
  gender text,
  id_card_no text,
  age integer,
  phone text,
  job_title text,
  work_years numeric(5,1),
  job_years numeric(5,1),
  safety_education_level text,
  victim_nature text,
  injury_part text,
  injury_degree text,
  education_level text,
  home_address text,
  remark text,
  sort integer not null default 0,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_accident_person_id_tenant_key unique (id, tenant_id),
  constraint smis_accident_person_report_employee_key unique (tenant_id, accident_report_id, employee_id),
  constraint smis_accident_person_report_fkey foreign key (accident_report_id, tenant_id)
    references public.smis_accident_report(id, tenant_id) on delete cascade,
  constraint smis_accident_person_employee_fkey foreign key (employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_accident_person_age_check check (age is null or age between 0 and 150),
  constraint smis_accident_person_work_years_check check (work_years is null or work_years between 0 and 100),
  constraint smis_accident_person_job_years_check check (job_years is null or job_years between 0 and 100),
  constraint smis_accident_person_sort_check check (sort >= 0)
);
comment on table public.smis_accident_person is '事故涉及人员及其事故发生时的人事档案快照';
create table public.smis_work_injury_declaration (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  declaration_no text not null,
  declaration_date date not null,
  accident_report_id uuid not null,
  declarant_employee_id uuid not null,
  declarant_employee_no_snapshot text not null,
  declarant_name_snapshot text not null,
  department_name_snapshot text,
  injury_type text not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_work_injury_declaration_id_tenant_key unique (id, tenant_id),
  constraint smis_work_injury_declaration_tenant_no_key unique (tenant_id, declaration_no),
  constraint smis_work_injury_declaration_report_fkey foreign key (accident_report_id, tenant_id)
    references public.smis_accident_report(id, tenant_id),
  constraint smis_work_injury_declaration_employee_fkey foreign key (declarant_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id),
  constraint smis_work_injury_declaration_type_check check (
    injury_type in ('slight', 'minor', 'serious', 'fatal')
  )
);
comment on table public.smis_work_injury_declaration is '关联事故快报的租户级工伤申报记录';
comment on column public.smis_work_injury_declaration.declarant_name_snapshot is '申报发生时的员工姓名快照';
create index smis_accident_report_tenant_time_idx
  on public.smis_accident_report (tenant_id, accident_time desc, id);
create index smis_accident_report_tenant_level_idx
  on public.smis_accident_report (tenant_id, accident_level, accident_time desc);
create index smis_accident_report_tenant_reporter_idx
  on public.smis_accident_report (tenant_id, reporter_employee_id);
create index smis_accident_report_tenant_org_idx
  on public.smis_accident_report (tenant_id, operation_area_organization_id)
  where operation_area_organization_id is not null;
create index smis_accident_report_categories_gin_idx
  on public.smis_accident_report using gin (accident_categories);
create index smis_accident_measure_report_idx
  on public.smis_accident_prevention_measure (tenant_id, accident_report_id, sort);
create index smis_accident_measure_responsible_idx
  on public.smis_accident_prevention_measure (tenant_id, responsible_employee_id)
  where responsible_employee_id is not null;
create index smis_accident_person_report_idx
  on public.smis_accident_person (tenant_id, accident_report_id, sort);
create index smis_accident_person_employee_idx
  on public.smis_accident_person (tenant_id, employee_id);
create index smis_work_injury_declaration_tenant_date_idx
  on public.smis_work_injury_declaration (tenant_id, declaration_date desc, id);
create index smis_work_injury_declaration_tenant_type_idx
  on public.smis_work_injury_declaration (tenant_id, injury_type, declaration_date desc);
create index smis_work_injury_declaration_report_idx
  on public.smis_work_injury_declaration (tenant_id, accident_report_id);
create index smis_work_injury_declaration_employee_idx
  on public.smis_work_injury_declaration (tenant_id, declarant_employee_id);
create trigger smis_accident_report_create_audit before insert on public.smis_accident_report
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_accident_report_update_audit before update on public.smis_accident_report
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_accident_prevention_measure_create_audit before insert on public.smis_accident_prevention_measure
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_accident_prevention_measure_update_audit before update on public.smis_accident_prevention_measure
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_accident_person_create_audit before insert on public.smis_accident_person
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_accident_person_update_audit before update on public.smis_accident_person
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_work_injury_declaration_create_audit before insert on public.smis_work_injury_declaration
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_work_injury_declaration_update_audit before update on public.smis_work_injury_declaration
for each row execute function public.trg_set_update_time_and_by();
alter table public.smis_accident_report enable row level security;
alter table public.smis_accident_prevention_measure enable row level security;
alter table public.smis_accident_person enable row level security;
alter table public.smis_work_injury_declaration enable row level security;
create policy smis_accident_report_tenant_select on public.smis_accident_report for select to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:View'));
create policy smis_accident_report_tenant_insert on public.smis_accident_report for insert to authenticated
with check (tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('SmisAccidentFlashReport:Add'));
create policy smis_accident_report_tenant_update on public.smis_accident_report for update to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Edit'))
with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Edit'));
create policy smis_accident_report_tenant_delete on public.smis_accident_report for delete to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Delete'));
create policy smis_accident_measure_tenant_select on public.smis_accident_prevention_measure for select to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:View'));
create policy smis_accident_measure_tenant_insert on public.smis_accident_prevention_measure for insert to authenticated
with check (tenant_id = app_private.current_user_tenant_id()
  and (app_private.has_permission('SmisAccidentFlashReport:Add') or app_private.has_permission('SmisAccidentFlashReport:Edit')));
create policy smis_accident_measure_tenant_update on public.smis_accident_prevention_measure for update to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Edit'))
with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Edit'));
create policy smis_accident_measure_tenant_delete on public.smis_accident_prevention_measure for delete to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Delete'));
create policy smis_accident_person_tenant_select on public.smis_accident_person for select to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:View'));
create policy smis_accident_person_tenant_insert on public.smis_accident_person for insert to authenticated
with check (tenant_id = app_private.current_user_tenant_id()
  and (app_private.has_permission('SmisAccidentFlashReport:Add') or app_private.has_permission('SmisAccidentFlashReport:Edit')));
create policy smis_accident_person_tenant_update on public.smis_accident_person for update to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Edit'))
with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Edit'));
create policy smis_accident_person_tenant_delete on public.smis_accident_person for delete to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisAccidentFlashReport:Delete'));
create policy smis_work_injury_tenant_select on public.smis_work_injury_declaration for select to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisWorkInjuryDeclaration:View'));
create policy smis_work_injury_tenant_insert on public.smis_work_injury_declaration for insert to authenticated
with check (tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('SmisWorkInjuryDeclaration:Add'));
create policy smis_work_injury_tenant_update on public.smis_work_injury_declaration for update to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisWorkInjuryDeclaration:Edit'))
with check ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisWorkInjuryDeclaration:Edit'));
create policy smis_work_injury_tenant_delete on public.smis_work_injury_declaration for delete to authenticated
using ((app_private.is_platform_super() or tenant_id = app_private.current_user_tenant_id())
  and app_private.has_permission('SmisWorkInjuryDeclaration:Delete'));
grant select on public.smis_accident_report to authenticated;
grant select on public.smis_accident_prevention_measure to authenticated;
grant select on public.smis_accident_person to authenticated;
grant select on public.smis_work_injury_declaration to authenticated;
revoke all on public.smis_accident_report from anon;
revoke all on public.smis_accident_prevention_measure from anon;
revoke all on public.smis_accident_person from anon;
revoke all on public.smis_work_injury_declaration from anon;
create or replace function app_private.smis_accident_employee_snapshot(
  p_tenant_id uuid,
  p_employee_id uuid
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with recursive employee_row as (
    select e.*, p.position_name
    from public.hr_employee e
    left join public.hr_position p
      on p.id = e.position_id and p.tenant_id = e.tenant_id
    where e.id = p_employee_id and e.tenant_id = p_tenant_id
  ), organization_chain as (
    select o.id, o.parent_id, o.organization_name, o.organization_type, 0 as depth
    from public.sys_organization o
    join employee_row e on e.organization_id = o.id and e.tenant_id = o.tenant_id
    union all
    select parent.id, parent.parent_id, parent.organization_name, parent.organization_type, child.depth + 1
    from public.sys_organization parent
    join organization_chain child on child.parent_id = parent.id
    where parent.tenant_id = p_tenant_id
  ), organization_depth as (
    select coalesce(max(depth), 0) as max_depth from organization_chain
  )
  select jsonb_build_object(
    'id', e.id,
    'tenantId', e.tenant_id,
    'organizationId', e.organization_id,
    'employeeNo', e.employee_no,
    'employeeName', e.employee_name,
    'avatarUrl', e.avatar_url,
    'jobTitle', coalesce(e.job_title, e.position_name),
    'employmentStatus', e.employment_status,
    'gender', e.gender,
    'birthDate', e.birth_date,
    'idCardNo', e.id_card_no,
    'age', case when e.birth_date is null then null else extract(year from age(current_date, e.birth_date))::integer end,
    'phone', e.phone,
    'hireDate', e.hire_date,
    'workYears', case when e.hire_date is null then null else extract(year from age(current_date, e.hire_date))::numeric(5,1) end,
    'educationLevel', e.education_level,
    'homeAddress', e.home_address,
    'companyName', (select organization_name from organization_chain where depth = (select max_depth from organization_depth) limit 1),
    'operationDepartmentName', (select organization_name from organization_chain where depth = greatest((select max_depth from organization_depth) - 1, 0) limit 1),
    'operationAreaName', (select organization_name from organization_chain where (select max_depth from organization_depth) >= 2 and depth = (select max_depth from organization_depth) - 2 limit 1),
    'teamName', (select organization_name from organization_chain where (select max_depth from organization_depth) >= 3 and depth = 0 limit 1),
    'organization', case when e.organization_id is null then null else jsonb_build_object(
      'id', e.organization_id,
      'organizationCode', coalesce((select o.organization_code from public.sys_organization o where o.id = e.organization_id and o.tenant_id = e.tenant_id), ''),
      'organizationName', coalesce((select o.organization_name from public.sys_organization o where o.id = e.organization_id and o.tenant_id = e.tenant_id), '')
    ) end
  )
  from employee_row e;
$$;
revoke execute on function app_private.smis_accident_employee_snapshot(uuid, uuid)
  from public, anon, authenticated;
create or replace function public.smis_list_accident_employee_candidates_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1), 200);
  v_keyword text := nullif(btrim(p_keyword), '');
  v_records jsonb;
  v_total bigint;
begin
  if not (
    app_private.has_permission('SmisAccidentFlashReport:Add')
    or app_private.has_permission('SmisAccidentFlashReport:Edit')
    or app_private.has_permission('SmisWorkInjuryDeclaration:Add')
    or app_private.has_permission('SmisWorkInjuryDeclaration:Edit')
  ) then
    raise exception '当前账号无权选择事故相关人员';
  end if;

  with filtered as materialized (
    select e.id, e.employee_name, e.employee_no
    from public.hr_employee e
    left join public.sys_organization o on o.id = e.organization_id and o.tenant_id = e.tenant_id
    where e.tenant_id = v_tenant
      and e.employment_status in ('probation', 'active')
      and (
        v_keyword is null
        or e.employee_name ilike '%' || v_keyword || '%'
        or e.employee_no ilike '%' || v_keyword || '%'
        or e.job_title ilike '%' || v_keyword || '%'
        or o.organization_name ilike '%' || v_keyword || '%'
      )
  ), paged as (
    select * from filtered order by employee_name, employee_no, id offset v_from limit v_limit
  )
  select
    (select count(*) from filtered),
    coalesce(jsonb_agg(app_private.smis_accident_employee_snapshot(v_tenant, paged.id)
      order by paged.employee_name, paged.employee_no, paged.id), '[]'::jsonb)
  into v_total, v_records
  from paged;

  return jsonb_build_object('records', v_records, 'total', v_total);
end;
$$;
create or replace function public.smis_list_accident_reports_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_accident_level text default null,
  p_accident_category text default null,
  p_organization_id uuid default null,
  p_start_time timestamptz default null,
  p_end_time timestamptz default null,
  p_ids uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_records jsonb;
  v_total bigint;
  v_overview jsonb;
  v_organizations jsonb;
  v_current_employee jsonb;
begin
  if not app_private.has_permission('SmisAccidentFlashReport:View') then
    raise exception '当前账号无权查看事故快报';
  end if;

  with filtered as materialized (
    select r.*,
      reporter.employee_no as reporter_employee_no,
      reporter.employee_name as reporter_employee_name,
      reporter.avatar_url as reporter_avatar_url,
      reporter.job_title as reporter_job_title,
      reporter.employment_status as reporter_employment_status,
      reporter.organization_id as reporter_organization_id,
      reporter_org.organization_code as reporter_organization_code,
      reporter_org.organization_name as reporter_organization_name,
      accident_org.organization_name as operation_area_organization_name
    from public.smis_accident_report r
    join public.hr_employee reporter on reporter.id = r.reporter_employee_id and reporter.tenant_id = r.tenant_id
    left join public.sys_organization reporter_org on reporter_org.id = reporter.organization_id and reporter_org.tenant_id = reporter.tenant_id
    left join public.sys_organization accident_org on accident_org.id = r.operation_area_organization_id and accident_org.tenant_id = r.tenant_id
    where (app_private.is_platform_super() or r.tenant_id = v_tenant)
      and (p_ids is null or r.id = any(p_ids))
      and (
        nullif(btrim(p_keyword), '') is null
        or r.accident_no ilike '%' || btrim(p_keyword) || '%'
        or r.accident_name ilike '%' || btrim(p_keyword) || '%'
        or r.accident_location ilike '%' || btrim(p_keyword) || '%'
        or reporter.employee_name ilike '%' || btrim(p_keyword) || '%'
      )
      and (p_accident_level is null or r.accident_level = p_accident_level)
      and (p_accident_category is null or r.accident_categories @> array[p_accident_category])
      and (p_organization_id is null or r.operation_area_organization_id = p_organization_id)
      and (p_start_time is null or r.accident_time >= p_start_time)
      and (p_end_time is null or r.accident_time <= p_end_time)
  ), paged as materialized (
    select * from filtered
    order by accident_time desc, id desc
    offset greatest(coalesce(p_from, 0), 0)
    limit least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 0), 5000)
  ), measures as (
    select m.accident_report_id,
      jsonb_agg(jsonb_build_object(
        'id', m.id,
        'plannedMeasure', m.planned_measure,
        'plannedImplementationDate', m.planned_implementation_date,
        'responsibleEmployeeId', m.responsible_employee_id,
        'responsibleEmployee', case when employee.id is null then null else jsonb_build_object(
          'id', employee.id,
          'tenantId', employee.tenant_id,
          'organizationId', employee.organization_id,
          'employeeNo', employee.employee_no,
          'employeeName', employee.employee_name,
          'avatarUrl', employee.avatar_url,
          'jobTitle', employee.job_title,
          'employmentStatus', employee.employment_status,
          'organization', case when organization.id is null then null else jsonb_build_object(
            'id', organization.id,
            'organizationCode', organization.organization_code,
            'organizationName', organization.organization_name
          ) end
        ) end,
        'sort', m.sort
      ) order by m.sort, m.id) as rows
    from public.smis_accident_prevention_measure m
    join paged p on p.id = m.accident_report_id and p.tenant_id = m.tenant_id
    left join public.hr_employee employee on employee.id = m.responsible_employee_id and employee.tenant_id = m.tenant_id
    left join public.sys_organization organization on organization.id = employee.organization_id and organization.tenant_id = employee.tenant_id
    group by m.accident_report_id
  ), people as (
    select person.accident_report_id,
      jsonb_agg(jsonb_build_object(
        'id', person.id,
        'employeeId', person.employee_id,
        'companyName', person.company_name,
        'operationDepartmentName', person.operation_department_name,
        'operationAreaName', person.operation_area_name,
        'teamName', person.team_name,
        'employeeNo', person.employee_no,
        'employeeName', person.employee_name,
        'gender', person.gender,
        'idCardNo', person.id_card_no,
        'age', person.age,
        'phone', person.phone,
        'jobTitle', person.job_title,
        'workYears', person.work_years,
        'jobYears', person.job_years,
        'safetyEducationLevel', person.safety_education_level,
        'victimNature', person.victim_nature,
        'injuryPart', person.injury_part,
        'injuryDegree', person.injury_degree,
        'educationLevel', person.education_level,
        'homeAddress', person.home_address,
        'remark', person.remark,
        'sort', person.sort
      ) order by person.sort, person.employee_name, person.id) as rows
    from public.smis_accident_person person
    join paged p on p.id = person.accident_report_id and p.tenant_id = person.tenant_id
    group by person.accident_report_id
  )
  select
    (select count(*) from filtered),
    coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'accidentNo', p.accident_no,
      'accidentName', p.accident_name,
      'reporterEmployeeId', p.reporter_employee_id,
      'reporterEmployee', jsonb_build_object(
        'id', p.reporter_employee_id,
        'tenantId', p.tenant_id,
        'organizationId', p.reporter_organization_id,
        'employeeNo', p.reporter_employee_no,
        'employeeName', p.reporter_employee_name,
        'avatarUrl', p.reporter_avatar_url,
        'jobTitle', p.reporter_job_title,
        'employmentStatus', p.reporter_employment_status,
        'organization', case when p.reporter_organization_id is null then null else jsonb_build_object(
          'id', p.reporter_organization_id,
          'organizationCode', p.reporter_organization_code,
          'organizationName', p.reporter_organization_name
        ) end
      ),
      'accidentTime', p.accident_time,
      'accidentLocation', p.accident_location,
      'accidentCategories', p.accident_categories,
      'operationAreaOrganizationId', p.operation_area_organization_id,
      'operationAreaOrganizationName', p.operation_area_organization_name,
      'accidentLevel', p.accident_level,
      'indirectEconomicLoss', p.indirect_economic_loss,
      'causeAnalysis', p.cause_analysis,
      'resultDetermination', p.result_determination,
      'imageUrls', p.image_urls,
      'measures', coalesce(measures.rows, '[]'::jsonb),
      'people', coalesce(people.rows, '[]'::jsonb),
      'createBy', p.create_by,
      'createTime', p.create_time,
      'updateBy', p.update_by,
      'updateTime', p.update_time
    ) order by p.accident_time desc, p.id desc), '[]'::jsonb)
  into v_total, v_records
  from paged p
  left join measures on measures.accident_report_id = p.id
  left join people on people.accident_report_id = p.id;

  select jsonb_build_object(
    'total', count(*),
    'currentMonth', count(*) filter (where date_trunc('month', accident_time) = date_trunc('month', now())),
    'highSeverity', count(*) filter (where accident_level in ('major', 'severe', 'catastrophic')),
    'affectedPeople', coalesce(sum((select count(*) from public.smis_accident_person person where person.accident_report_id = r.id and person.tenant_id = r.tenant_id)), 0)
  ) into v_overview
  from public.smis_accident_report r
  where (app_private.is_platform_super() or r.tenant_id = v_tenant);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', o.id,
    'parentId', o.parent_id,
    'organizationCode', o.organization_code,
    'organizationName', o.organization_name,
    'organizationType', o.organization_type,
    'sort', o.sort,
    'children', '[]'::jsonb
  ) order by o.sort, o.organization_name), '[]'::jsonb)
  into v_organizations
  from public.sys_organization o
  where o.tenant_id = v_tenant and o.status = '1';

  select app_private.smis_accident_employee_snapshot(v_tenant, u.hr_employee_id)
  into v_current_employee
  from public.sys_user u
  where u.auth_user_id = auth.uid()
    and u.tenant_id = v_tenant
    and u.deleted_at is null
  limit 1;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'overview', coalesce(v_overview, jsonb_build_object('total', 0, 'currentMonth', 0, 'highSeverity', 0, 'affectedPeople', 0)),
    'organizations', v_organizations,
    'currentEmployee', v_current_employee
  );
end;
$$;
create or replace function public.smis_save_accident_report_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid;
  v_accident_no text;
  v_name text := btrim(coalesce(p_payload->>'accident_name', ''));
  v_reporter_id uuid := nullif(p_payload->>'reporter_employee_id', '')::uuid;
  v_accident_time timestamptz := nullif(p_payload->>'accident_time', '')::timestamptz;
  v_location text := btrim(coalesce(p_payload->>'accident_location', ''));
  v_categories text[] := array(select jsonb_array_elements_text(coalesce(p_payload->'accident_categories', '[]'::jsonb)));
  v_organization_id uuid := nullif(p_payload->>'operation_area_organization_id', '')::uuid;
  v_level text := p_payload->>'accident_level';
  v_loss numeric(14,2) := coalesce(nullif(p_payload->>'indirect_economic_loss', '')::numeric, 0);
  v_measures jsonb := coalesce(p_payload->'measures', '[]'::jsonb);
  v_people jsonb := coalesce(p_payload->'people', '[]'::jsonb);
  v_item jsonb;
  v_child_id uuid;
  v_employee_id uuid;
  v_responsible_id uuid;
  v_snapshot jsonb;
  v_measure_ids uuid[] := '{}';
  v_person_ids uuid[] := '{}';
  v_sort integer := 0;
begin
  if p_id is null and not app_private.has_permission('SmisAccidentFlashReport:Add') then
    raise exception '当前账号无权新增事故快报';
  end if;
  if p_id is not null and not app_private.has_permission('SmisAccidentFlashReport:Edit') then
    raise exception '当前账号无权编辑事故快报';
  end if;

  v_tenant := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_accident_report target where target.id = p_id
  ));

  if v_name = '' then raise exception '请输入事故名称'; end if;
  if v_reporter_id is null or not exists(
    select 1 from public.hr_employee e
    where e.id = v_reporter_id and e.tenant_id = v_tenant
      and e.employment_status in ('probation', 'active')
  ) then raise exception '请选择当前租户在职员工担任上报人'; end if;
  if v_accident_time is null then raise exception '请选择事故时间'; end if;
  if v_location = '' then raise exception '请输入事故地点'; end if;
  if cardinality(v_categories) = 0 or not v_categories <@ array[
    'object_strike', 'other_injury', 'mechanical_injury', 'lifting_injury', 'electric_shock',
    'drowning', 'burn', 'fire', 'fall_from_height', 'collapse', 'roof_fall', 'water_inrush',
    'blasting', 'explosive_material', 'gas_explosion', 'boiler_explosion', 'vessel_explosion',
    'other_explosion', 'poisoning_asphyxiation'
  ]::text[] then raise exception '请选择有效的事故类别'; end if;
  if v_level not in ('near_miss', 'minor_injury', 'general', 'major', 'severe', 'catastrophic') then
    raise exception '请选择有效的事故级别';
  end if;
  if v_loss < 0 then raise exception '间接经济损失不能小于 0'; end if;
  if v_organization_id is not null and not exists(
    select 1 from public.sys_organization o
    where o.id = v_organization_id and o.tenant_id = v_tenant and o.status = '1'
  ) then raise exception '请选择当前租户有效的事故发生作业区'; end if;
  if exists(
    select 1 from jsonb_array_elements(v_people) item
    where nullif(item->>'employee_id', '') is null
  ) then raise exception '人员信息中存在未关联员工的记录'; end if;
  if exists(
    select 1
    from jsonb_array_elements(v_people) item
    group by item->>'employee_id'
    having count(*) > 1
  ) then raise exception '人员信息不能重复选择同一员工'; end if;

  if p_id is null then
    v_accident_no := app_private.next_document_number('smis.accident_report', v_tenant);
    insert into public.smis_accident_report(
      tenant_id, accident_no, accident_name, reporter_employee_id, accident_time,
      accident_location, accident_categories, operation_area_organization_id,
      accident_level, indirect_economic_loss, cause_analysis, result_determination, image_urls
    ) values (
      v_tenant, v_accident_no, v_name, v_reporter_id, v_accident_time,
      v_location, v_categories, v_organization_id, v_level, v_loss,
      nullif(btrim(p_payload->>'cause_analysis'), ''),
      nullif(btrim(p_payload->>'result_determination'), ''),
      array(select jsonb_array_elements_text(coalesce(p_payload->'image_urls', '[]'::jsonb)))
    ) returning id into v_id;
  else
    update public.smis_accident_report
    set accident_name = v_name,
        reporter_employee_id = v_reporter_id,
        accident_time = v_accident_time,
        accident_location = v_location,
        accident_categories = v_categories,
        operation_area_organization_id = v_organization_id,
        accident_level = v_level,
        indirect_economic_loss = v_loss,
        cause_analysis = nullif(btrim(p_payload->>'cause_analysis'), ''),
        result_determination = nullif(btrim(p_payload->>'result_determination'), ''),
        image_urls = array(select jsonb_array_elements_text(coalesce(p_payload->'image_urls', '[]'::jsonb)))
    where id = p_id and tenant_id = v_tenant
    returning id into v_id;
    if v_id is null then raise exception '事故快报不存在或不属于当前租户'; end if;
  end if;

  v_sort := 0;
  for v_item in select value from jsonb_array_elements(v_measures)
  loop
    if btrim(coalesce(v_item->>'planned_measure', '')) = '' then
      raise exception '请填写计划防范措施';
    end if;
    v_child_id := nullif(v_item->>'id', '')::uuid;
    v_responsible_id := nullif(v_item->>'responsible_employee_id', '')::uuid;
    if v_responsible_id is not null and not exists(
      select 1 from public.hr_employee e where e.id = v_responsible_id and e.tenant_id = v_tenant
        and e.employment_status in ('probation', 'active')
    ) then raise exception '防范措施责任人必须是当前租户在职员工'; end if;

    if v_child_id is null then
      insert into public.smis_accident_prevention_measure(
        tenant_id, accident_report_id, planned_measure, planned_implementation_date,
        responsible_employee_id, sort
      ) values (
        v_tenant, v_id, btrim(v_item->>'planned_measure'),
        nullif(v_item->>'planned_implementation_date', '')::date,
        v_responsible_id, v_sort
      ) returning id into v_child_id;
    else
      update public.smis_accident_prevention_measure
      set planned_measure = btrim(v_item->>'planned_measure'),
          planned_implementation_date = nullif(v_item->>'planned_implementation_date', '')::date,
          responsible_employee_id = v_responsible_id,
          sort = v_sort
      where id = v_child_id and tenant_id = v_tenant and accident_report_id = v_id;
      if not found then raise exception '防范措施记录不存在或不属于当前事故'; end if;
    end if;
    v_measure_ids := array_append(v_measure_ids, v_child_id);
    v_sort := v_sort + 1;
  end loop;
  delete from public.smis_accident_prevention_measure
  where tenant_id = v_tenant and accident_report_id = v_id and not (id = any(v_measure_ids));

  v_sort := 0;
  for v_item in select value from jsonb_array_elements(v_people)
  loop
    v_employee_id := nullif(v_item->>'employee_id', '')::uuid;
    if not exists(
      select 1 from public.hr_employee e where e.id = v_employee_id and e.tenant_id = v_tenant
    ) then raise exception '人员信息包含当前租户之外的员工'; end if;

    v_child_id := nullif(v_item->>'id', '')::uuid;
    if v_child_id is null then
      select person.id into v_child_id
      from public.smis_accident_person person
      where person.tenant_id = v_tenant and person.accident_report_id = v_id
        and person.employee_id = v_employee_id;
    end if;

    if v_child_id is null then
      v_snapshot := app_private.smis_accident_employee_snapshot(v_tenant, v_employee_id);
      if v_snapshot is null then raise exception '无法读取所选员工档案'; end if;
      insert into public.smis_accident_person(
        tenant_id, accident_report_id, employee_id, company_name,
        operation_department_name, operation_area_name, team_name,
        employee_no, employee_name, gender, id_card_no, age, phone, job_title,
        work_years, job_years, safety_education_level, victim_nature, injury_part,
        injury_degree, education_level, home_address, remark, sort
      ) values (
        v_tenant, v_id, v_employee_id, v_snapshot->>'companyName',
        v_snapshot->>'operationDepartmentName', v_snapshot->>'operationAreaName', v_snapshot->>'teamName',
        v_snapshot->>'employeeNo', v_snapshot->>'employeeName', v_snapshot->>'gender',
        v_snapshot->>'idCardNo', nullif(v_snapshot->>'age', '')::integer,
        v_snapshot->>'phone', v_snapshot->>'jobTitle', nullif(v_snapshot->>'workYears', '')::numeric,
        nullif(v_item->>'job_years', '')::numeric,
        nullif(btrim(v_item->>'safety_education_level'), ''),
        nullif(btrim(v_item->>'victim_nature'), ''),
        nullif(btrim(v_item->>'injury_part'), ''),
        nullif(btrim(v_item->>'injury_degree'), ''),
        v_snapshot->>'educationLevel', v_snapshot->>'homeAddress',
        nullif(btrim(v_item->>'remark'), ''), v_sort
      ) returning id into v_child_id;
    else
      update public.smis_accident_person
      set job_years = nullif(v_item->>'job_years', '')::numeric,
          safety_education_level = nullif(btrim(v_item->>'safety_education_level'), ''),
          victim_nature = nullif(btrim(v_item->>'victim_nature'), ''),
          injury_part = nullif(btrim(v_item->>'injury_part'), ''),
          injury_degree = nullif(btrim(v_item->>'injury_degree'), ''),
          remark = nullif(btrim(v_item->>'remark'), ''),
          sort = v_sort
      where id = v_child_id and tenant_id = v_tenant and accident_report_id = v_id
        and employee_id = v_employee_id;
      if not found then raise exception '人员快照不存在或员工关联不一致'; end if;
    end if;
    v_person_ids := array_append(v_person_ids, v_child_id);
    v_sort := v_sort + 1;
  end loop;
  delete from public.smis_accident_person
  where tenant_id = v_tenant and accident_report_id = v_id and not (id = any(v_person_ids));

  return v_id;
exception
  when unique_violation then
    raise exception '事故编号已存在，请检查编号规则或人员信息是否重复';
end;
$$;
create or replace function public.smis_delete_accident_reports_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_count integer;
begin
  if not app_private.has_permission('SmisAccidentFlashReport:Delete') then
    raise exception '当前账号无权删除事故快报';
  end if;
  if exists(
    select 1 from public.smis_work_injury_declaration declaration
    join public.smis_accident_report report on report.id = declaration.accident_report_id and report.tenant_id = declaration.tenant_id
    where report.id = any(p_ids) and (app_private.is_platform_super() or report.tenant_id = v_tenant)
  ) then raise exception '事故快报已被工伤申报引用，不能删除'; end if;
  delete from public.smis_accident_report
  where id = any(p_ids) and (app_private.is_platform_super() or tenant_id = v_tenant);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
create or replace function public.smis_list_accident_report_options_secure(
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_records jsonb;
begin
  if not (
    app_private.has_permission('SmisWorkInjuryDeclaration:Add')
    or app_private.has_permission('SmisWorkInjuryDeclaration:Edit')
  ) then raise exception '当前账号无权选择关联事故'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'accidentNo', r.accident_no,
    'accidentName', r.accident_name,
    'accidentTime', r.accident_time,
    'accidentLocation', r.accident_location,
    'accidentLevel', r.accident_level
  ) order by r.accident_time desc, r.id desc), '[]'::jsonb)
  into v_records
  from public.smis_accident_report r
  where (app_private.is_platform_super() or r.tenant_id = v_tenant)
    and (
      nullif(btrim(p_keyword), '') is null
      or r.accident_no ilike '%' || btrim(p_keyword) || '%'
      or r.accident_name ilike '%' || btrim(p_keyword) || '%'
    );
  return v_records;
end;
$$;
create or replace function public.smis_list_work_injury_declarations_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_injury_type text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_ids uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_records jsonb;
  v_total bigint;
  v_overview jsonb;
  v_current_employee jsonb;
begin
  if not app_private.has_permission('SmisWorkInjuryDeclaration:View') then
    raise exception '当前账号无权查看工伤申报';
  end if;

  with filtered as materialized (
    select d.*, r.accident_no, r.accident_name, r.accident_time, r.accident_location,
      e.avatar_url, e.job_title, e.employment_status, e.organization_id,
      o.organization_code, o.organization_name
    from public.smis_work_injury_declaration d
    join public.smis_accident_report r on r.id = d.accident_report_id and r.tenant_id = d.tenant_id
    join public.hr_employee e on e.id = d.declarant_employee_id and e.tenant_id = d.tenant_id
    left join public.sys_organization o on o.id = e.organization_id and o.tenant_id = e.tenant_id
    where (app_private.is_platform_super() or d.tenant_id = v_tenant)
      and (p_ids is null or d.id = any(p_ids))
      and (
        nullif(btrim(p_keyword), '') is null
        or d.declaration_no ilike '%' || btrim(p_keyword) || '%'
        or d.declarant_name_snapshot ilike '%' || btrim(p_keyword) || '%'
        or r.accident_no ilike '%' || btrim(p_keyword) || '%'
        or r.accident_name ilike '%' || btrim(p_keyword) || '%'
      )
      and (p_injury_type is null or d.injury_type = p_injury_type)
      and (p_start_date is null or d.declaration_date >= p_start_date)
      and (p_end_date is null or d.declaration_date <= p_end_date)
  ), paged as (
    select * from filtered
    order by declaration_date desc, id desc
    offset greatest(coalesce(p_from, 0), 0)
    limit least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 0), 5000)
  )
  select
    (select count(*) from filtered),
    coalesce(jsonb_agg(jsonb_build_object(
      'id', p.id,
      'declarationNo', p.declaration_no,
      'declarationDate', p.declaration_date,
      'accidentReportId', p.accident_report_id,
      'accident', jsonb_build_object(
        'id', p.accident_report_id,
        'accidentNo', p.accident_no,
        'accidentName', p.accident_name,
        'accidentTime', p.accident_time,
        'accidentLocation', p.accident_location
      ),
      'declarantEmployeeId', p.declarant_employee_id,
      'declarantEmployeeNoSnapshot', p.declarant_employee_no_snapshot,
      'declarantNameSnapshot', p.declarant_name_snapshot,
      'departmentNameSnapshot', p.department_name_snapshot,
      'declarantEmployee', jsonb_build_object(
        'id', p.declarant_employee_id,
        'tenantId', p.tenant_id,
        'organizationId', p.organization_id,
        'employeeNo', p.declarant_employee_no_snapshot,
        'employeeName', p.declarant_name_snapshot,
        'avatarUrl', p.avatar_url,
        'jobTitle', p.job_title,
        'employmentStatus', p.employment_status,
        'organization', case when p.organization_id is null then null else jsonb_build_object(
          'id', p.organization_id,
          'organizationCode', p.organization_code,
          'organizationName', p.organization_name
        ) end
      ),
      'injuryType', p.injury_type,
      'createBy', p.create_by,
      'createTime', p.create_time,
      'updateBy', p.update_by,
      'updateTime', p.update_time
    ) order by p.declaration_date desc, p.id desc), '[]'::jsonb)
  into v_total, v_records
  from paged p;

  select jsonb_build_object(
    'total', count(*),
    'slight', count(*) filter (where injury_type = 'slight'),
    'minor', count(*) filter (where injury_type = 'minor'),
    'serious', count(*) filter (where injury_type = 'serious'),
    'fatal', count(*) filter (where injury_type = 'fatal')
  ) into v_overview
  from public.smis_work_injury_declaration d
  where (app_private.is_platform_super() or d.tenant_id = v_tenant);

  select app_private.smis_accident_employee_snapshot(v_tenant, u.hr_employee_id)
  into v_current_employee
  from public.sys_user u
  where u.auth_user_id = auth.uid() and u.tenant_id = v_tenant and u.deleted_at is null
  limit 1;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'overview', coalesce(v_overview, jsonb_build_object('total', 0, 'slight', 0, 'minor', 0, 'serious', 0, 'fatal', 0)),
    'currentEmployee', v_current_employee
  );
end;
$$;
create or replace function public.smis_save_work_injury_declaration_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid;
  v_id uuid;
  v_no text;
  v_date date := nullif(p_payload->>'declaration_date', '')::date;
  v_report_id uuid := nullif(p_payload->>'accident_report_id', '')::uuid;
  v_employee_id uuid := nullif(p_payload->>'declarant_employee_id', '')::uuid;
  v_injury_type text := p_payload->>'injury_type';
  v_employee public.hr_employee;
  v_department_name text;
begin
  if p_id is null and not app_private.has_permission('SmisWorkInjuryDeclaration:Add') then
    raise exception '当前账号无权新增工伤申报';
  end if;
  if p_id is not null and not app_private.has_permission('SmisWorkInjuryDeclaration:Edit') then
    raise exception '当前账号无权编辑工伤申报';
  end if;

  v_tenant := app_private.resolve_mutation_tenant_id((
    select target.tenant_id from public.smis_work_injury_declaration target where target.id = p_id
  ));
  if v_date is null then raise exception '请选择申报时间'; end if;
  if not exists(
    select 1 from public.smis_accident_report r where r.id = v_report_id and r.tenant_id = v_tenant
  ) then raise exception '请选择当前租户有效的关联事故'; end if;
  select * into v_employee from public.hr_employee e
  where e.id = v_employee_id and e.tenant_id = v_tenant
    and e.employment_status in ('probation', 'active');
  if v_employee.id is null then raise exception '请选择当前租户在职员工作为申报人'; end if;
  if v_injury_type not in ('slight', 'minor', 'serious', 'fatal') then
    raise exception '请选择有效的工伤类型';
  end if;
  select o.organization_name into v_department_name
  from public.sys_organization o
  where o.id = v_employee.organization_id and o.tenant_id = v_tenant;

  if p_id is null then
    v_no := app_private.next_document_number('smis.work_injury_declaration', v_tenant);
    insert into public.smis_work_injury_declaration(
      tenant_id, declaration_no, declaration_date, accident_report_id,
      declarant_employee_id, declarant_employee_no_snapshot, declarant_name_snapshot,
      department_name_snapshot, injury_type
    ) values (
      v_tenant, v_no, v_date, v_report_id, v_employee_id, v_employee.employee_no,
      v_employee.employee_name, v_department_name, v_injury_type
    ) returning id into v_id;
  else
    update public.smis_work_injury_declaration
    set declaration_date = v_date,
        accident_report_id = v_report_id,
        declarant_employee_id = v_employee_id,
        declarant_employee_no_snapshot = v_employee.employee_no,
        declarant_name_snapshot = v_employee.employee_name,
        department_name_snapshot = v_department_name,
        injury_type = v_injury_type
    where id = p_id and tenant_id = v_tenant
    returning id into v_id;
    if v_id is null then raise exception '工伤申报不存在或不属于当前租户'; end if;
  end if;
  return v_id;
exception
  when unique_violation then raise exception '申报编号已存在，请检查编号规则';
end;
$$;
create or replace function public.smis_delete_work_injury_declarations_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant uuid := app_private.current_user_tenant_id();
  v_count integer;
begin
  if not app_private.has_permission('SmisWorkInjuryDeclaration:Delete') then
    raise exception '当前账号无权删除工伤申报';
  end if;
  delete from public.smis_work_injury_declaration
  where id = any(p_ids) and (app_private.is_platform_super() or tenant_id = v_tenant);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.smis_list_accident_employee_candidates_secure(integer, integer, text) from public, anon;
revoke all on function public.smis_list_accident_reports_secure(integer, integer, text, text, text, uuid, timestamptz, timestamptz, uuid[]) from public, anon;
revoke all on function public.smis_save_accident_report_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_accident_reports_secure(uuid[]) from public, anon;
revoke all on function public.smis_list_accident_report_options_secure(text) from public, anon;
revoke all on function public.smis_list_work_injury_declarations_secure(integer, integer, text, text, date, date, uuid[]) from public, anon;
revoke all on function public.smis_save_work_injury_declaration_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_work_injury_declarations_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_accident_employee_candidates_secure(integer, integer, text) to authenticated;
grant execute on function public.smis_list_accident_reports_secure(integer, integer, text, text, text, uuid, timestamptz, timestamptz, uuid[]) to authenticated;
grant execute on function public.smis_save_accident_report_secure(uuid, jsonb) to authenticated;
grant execute on function public.smis_delete_accident_reports_secure(uuid[]) to authenticated;
grant execute on function public.smis_list_accident_report_options_secure(text) to authenticated;
grant execute on function public.smis_list_work_injury_declarations_secure(integer, integer, text, text, date, date, uuid[]) to authenticated;
grant execute on function public.smis_save_work_injury_declaration_secure(uuid, jsonb) to authenticated;
grant execute on function public.smis_delete_work_injury_declarations_secure(uuid[]) to authenticated;
-- 可分配的页面按钮权限。新按钮仅继承给已经拥有对应页面的角色。
with page_rows as (
  select id, name, app_code from public.sys_menu
  where app_code = 'smis' and name in ('SmisAccidentFlashReport', 'SmisWorkInjuryDeclaration')
), button_rows(page_name, button_name, title, sort) as (
  values
    ('SmisAccidentFlashReport', 'SmisAccidentFlashReport:View', '查看', 1),
    ('SmisAccidentFlashReport', 'SmisAccidentFlashReport:Add', '新增', 2),
    ('SmisAccidentFlashReport', 'SmisAccidentFlashReport:Edit', '编辑', 3),
    ('SmisAccidentFlashReport', 'SmisAccidentFlashReport:Delete', '删除', 4),
    ('SmisAccidentFlashReport', 'SmisAccidentFlashReport:Export', '导出', 5),
    ('SmisWorkInjuryDeclaration', 'SmisWorkInjuryDeclaration:View', '查看', 1),
    ('SmisWorkInjuryDeclaration', 'SmisWorkInjuryDeclaration:Add', '新增', 2),
    ('SmisWorkInjuryDeclaration', 'SmisWorkInjuryDeclaration:Edit', '编辑', 3),
    ('SmisWorkInjuryDeclaration', 'SmisWorkInjuryDeclaration:Delete', '删除', 4),
    ('SmisWorkInjuryDeclaration', 'SmisWorkInjuryDeclaration:Export', '导出', 5)
)
insert into public.sys_menu(
  id, parent_id, name, path, component, type, meta, sort, app_code,
  create_by, create_time, update_by, update_time
)
select gen_random_uuid(), page.id, button.button_name, '', '', 'button',
  jsonb_build_object('title', button.title, 'roles', '[]'::jsonb, 'is_hide', true, 'is_enable', true),
  button.sort, page.app_code, '624944977@qq.com', now(), '624944977@qq.com', now()
from button_rows button
join page_rows page on page.name = button.page_name
where not exists(select 1 from public.sys_menu existing where existing.name = button.button_name);
insert into public.sys_role_menu(
  id, role_id, menu_id, permission, tenant_id, create_by, create_time, update_by, update_time
)
select gen_random_uuid(), page_grant.role_id, button.id, '{}'::jsonb, page_grant.tenant_id,
  '624944977@qq.com', now(), '624944977@qq.com', now()
from public.sys_menu page
join public.sys_role_menu page_grant on page_grant.menu_id = page.id
join public.sys_menu button on button.parent_id = page.id and button.type = 'button'
where page.app_code = 'smis'
  and page.name in ('SmisAccidentFlashReport', 'SmisWorkInjuryDeclaration')
  and button.name in (
    'SmisAccidentFlashReport:View', 'SmisAccidentFlashReport:Add',
    'SmisAccidentFlashReport:Edit', 'SmisAccidentFlashReport:Delete',
    'SmisAccidentFlashReport:Export', 'SmisWorkInjuryDeclaration:View',
    'SmisWorkInjuryDeclaration:Add', 'SmisWorkInjuryDeclaration:Edit',
    'SmisWorkInjuryDeclaration:Delete', 'SmisWorkInjuryDeclaration:Export'
  )
  and not exists(
    select 1 from public.sys_role_menu existing
    where existing.role_id = page_grant.role_id
      and existing.menu_id = button.id
      and existing.tenant_id = page_grant.tenant_id
  );
-- 字典类型与字典项均归平台配置租户，供所有业务租户读取。
with dictionary_context as (
  select tenant.id as tenant_id, parent.id as parent_id
  from public.sys_tenant tenant
  cross join lateral (
    select id from public.sys_dict_type
    where tenant_id = tenant.id and code = 'smisSafetyProduction'
    limit 1
  ) parent
  where tenant.tenant_code = 'platform'
), dictionary_types(name, code, sort, remark) as (
  values
    ('事故类别', 'smisAccidentCategory', 70, '事故快报事故类别多选字典'),
    ('事故级别', 'smisAccidentLevel', 71, '事故快报事故等级'),
    ('工伤类型', 'smisWorkInjuryType', 72, '工伤申报伤害类型')
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, create_time, update_by, update_time,
  remark, tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', now(),
  '624944977@qq.com', now(), types.remark, context.tenant_id, context.parent_id,
  'dictionary', types.sort
from dictionary_types types cross join dictionary_context context
on conflict (code) do update set
  name = excluded.name,
  status = excluded.status,
  update_by = excluded.update_by,
  update_time = excluded.update_time,
  remark = excluded.remark,
  sort = excluded.sort;
with dictionary_items(dict_code, label, value, sort, tag_type, color) as (
  values
    ('smisAccidentCategory', '物体打击', 'object_strike', 1, 'warning', null),
    ('smisAccidentCategory', '其他伤害', 'other_injury', 2, 'info', null),
    ('smisAccidentCategory', '机械伤害', 'mechanical_injury', 3, 'warning', null),
    ('smisAccidentCategory', '起重伤害', 'lifting_injury', 4, 'warning', null),
    ('smisAccidentCategory', '触电', 'electric_shock', 5, 'danger', null),
    ('smisAccidentCategory', '淹溺', 'drowning', 6, 'danger', null),
    ('smisAccidentCategory', '灼烫', 'burn', 7, 'danger', null),
    ('smisAccidentCategory', '火灾', 'fire', 8, 'danger', null),
    ('smisAccidentCategory', '高处坠落', 'fall_from_height', 9, 'danger', null),
    ('smisAccidentCategory', '坍塌', 'collapse', 10, 'danger', null),
    ('smisAccidentCategory', '冒顶片帮', 'roof_fall', 11, 'danger', null),
    ('smisAccidentCategory', '透水', 'water_inrush', 12, 'danger', null),
    ('smisAccidentCategory', '放炮', 'blasting', 13, 'danger', null),
    ('smisAccidentCategory', '火药爆炸', 'explosive_material', 14, 'danger', null),
    ('smisAccidentCategory', '瓦斯爆炸', 'gas_explosion', 15, 'danger', null),
    ('smisAccidentCategory', '锅炉爆炸', 'boiler_explosion', 16, 'danger', null),
    ('smisAccidentCategory', '容器爆炸', 'vessel_explosion', 17, 'danger', null),
    ('smisAccidentCategory', '其他爆炸', 'other_explosion', 18, 'danger', null),
    ('smisAccidentCategory', '中毒和窒息', 'poisoning_asphyxiation', 19, 'danger', null),
    ('smisAccidentLevel', '险肇未遂', 'near_miss', 1, 'info', null),
    ('smisAccidentLevel', '轻伤', 'minor_injury', 2, 'warning', null),
    ('smisAccidentLevel', '一般', 'general', 3, 'warning', null),
    ('smisAccidentLevel', '较大', 'major', 4, 'danger', null),
    ('smisAccidentLevel', '重大', 'severe', 5, 'danger', '#e65100'),
    ('smisAccidentLevel', '特别重大', 'catastrophic', 6, 'danger', '#b71c1c'),
    ('smisWorkInjuryType', '轻微伤', 'slight', 1, 'info', null),
    ('smisWorkInjuryType', '轻伤', 'minor', 2, 'warning', null),
    ('smisWorkInjuryType', '重伤', 'serious', 3, 'danger', null),
    ('smisWorkInjuryType', '死亡', 'fatal', 4, 'danger', '#b71c1c')
), resolved as (
  select item.*, type.id as type_id, type.tenant_id
  from dictionary_items item
  join public.sys_dict_type type on type.code = item.dict_code
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, create_time, update_by, update_time,
  remark, value, label, color, sort, tenant_id, tag_type
)
select gen_random_uuid(), resolved.type_id, resolved.value, '1', '624944977@qq.com', now(),
  '624944977@qq.com', now(), '', resolved.value, resolved.label, resolved.color,
  resolved.sort, resolved.tenant_id, resolved.tag_type
from resolved
where not exists(
  select 1 from public.sys_dictionary existing
  where existing.type_id = resolved.type_id
    and existing.tenant_id = resolved.tenant_id
    and existing.value = resolved.value
);
-- 编号场景与各租户默认规则；管理员仍可在编号规则页面按租户调整模板。
with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), scene_rows(rule_key, rule_name, field_label, menu_name, target_table, target_column, template) as (
  values
    ('smis.accident_report', '事故快报编号', '事故编号', 'SmisAccidentFlashReport', 'smis_accident_report', 'accident_no', 'SG{YYYY}{MM}-{SEQ:4}'),
    ('smis.work_injury_declaration', '工伤申报编号', '申报编号', 'SmisWorkInjuryDeclaration', 'smis_work_injury_declaration', 'declaration_no', 'GS{YYYY}{MM}-{SEQ:4}')
)
insert into public.sys_document_number_scene(
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark,
  create_by, create_time, update_by, update_time, tenant_id
)
select scene.rule_key, scene.rule_name, scene.field_label, 'business_document', menu.id,
  scene.target_table, scene.target_column, scene.template, 'month', false, true,
  '事故管理单据保存时由数据库原子取号', '624944977@qq.com', now(),
  '624944977@qq.com', now(), platform.id
from scene_rows scene
join public.sys_menu menu on menu.name = scene.menu_name and menu.app_code = 'smis'
cross join platform_tenant platform
on conflict (rule_key) do update set
  rule_name = excluded.rule_name,
  field_label = excluded.field_label,
  menu_id = excluded.menu_id,
  target_table = excluded.target_table,
  target_column = excluded.target_column,
  default_template = excluded.default_template,
  enabled = true,
  update_by = excluded.update_by,
  update_time = excluded.update_time;
with rule_rows(rule_key, rule_name, target_table, target_column, template) as (
  values
    ('smis.accident_report', '事故快报编号', 'smis_accident_report', 'accident_no', 'SG{YYYY}{MM}-{SEQ:4}'),
    ('smis.work_injury_declaration', '工伤申报编号', 'smis_work_injury_declaration', 'declaration_no', 'GS{YYYY}{MM}-{SEQ:4}')
)
insert into public.sys_document_number_rule(
  id, tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone, rule_version,
  manual_required, builtin, enabled, remark, create_by, create_time, update_by, update_time
)
select gen_random_uuid(), tenant.id, rule.rule_key, rule.rule_name, 'business_document',
  rule.target_table, rule.target_column, true, rule.template, 'month', 1,
  'Asia/Shanghai', 1, false, true, true, '系统预置事故管理编号规则',
  '624944977@qq.com', now(), '624944977@qq.com', now()
from public.sys_tenant tenant cross join rule_rows rule
where tenant.status = '1'
on conflict (tenant_id, rule_key) do nothing;
