begin;

do $$
declare
  source_name text;
  target_name text;
begin
  for source_name, target_name in
    select *
    from (
      values
        ('sys_organization', 'mdm_organization'),
        ('hr_job_family', 'mdm_job_family'),
        ('hr_grade', 'mdm_grade'),
        ('hr_job_profile', 'mdm_job_profile'),
        ('hr_position', 'mdm_position'),
        ('hr_employee', 'mdm_employee'),
        ('hr_employee_assignment', 'mdm_employee_assignment')
    ) as rename_map(source_name, target_name)
  loop
    if to_regclass(format('public.%I', source_name)) is null then
      raise exception 'MDM migration source table public.% does not exist', source_name;
    end if;

    if to_regclass(format('public.%I', target_name)) is not null then
      raise exception 'MDM migration target public.% already exists', target_name;
    end if;
  end loop;
end;
$$;

alter table public.sys_organization rename to mdm_organization;
alter table public.hr_job_family rename to mdm_job_family;
alter table public.hr_grade rename to mdm_grade;
alter table public.hr_job_profile rename to mdm_job_profile;
alter table public.hr_position rename to mdm_position;
alter table public.hr_employee rename to mdm_employee;
alter table public.hr_employee_assignment rename to mdm_employee_assignment;

comment on table public.mdm_organization is
  'MDM 组织主数据；租户级组织树，供平台权限、HR、SMIS、TMS、VMS 与 FMS 统一引用。';
comment on table public.mdm_job_family is
  'MDM 职族主数据；定义租户级岗位序列。';
comment on table public.mdm_grade is
  'MDM 职级主数据；定义租户级岗位等级。';
comment on table public.mdm_job_profile is
  'MDM 职位模板主数据；连接职族、默认职级与岗位实例。';
comment on table public.mdm_position is
  'MDM 岗位主数据；position_kind 承载业务行为，不依赖岗位显示名称判断。';
comment on table public.mdm_employee is
  'MDM 员工主数据；企业人员花名册与跨业务域人员身份来源。';
comment on table public.mdm_employee_assignment is
  'MDM 员工任职主数据；记录员工在组织、岗位、职位模板和职级上的有效期关系。';

-- PL/pgSQL and dynamic SQL function bodies are stored as text and are not all
-- rewritten by ALTER TABLE RENAME. Recreate routines with canonical MDM names
-- before exposing the legacy names as compatibility views.
do $$
declare
  routine record;
  rewritten_definition text;
begin
  for routine in
    select procedure.oid, pg_get_functiondef(procedure.oid) as definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prokind in ('f', 'p')
      and procedure.prosrc ~
        '\m(sys_organization|hr_job_family|hr_grade|hr_job_profile|hr_position|hr_employee|hr_employee_assignment)\M'
  loop
    rewritten_definition := routine.definition;
    rewritten_definition := regexp_replace(rewritten_definition, '\msys_organization\M', 'mdm_organization', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mhr_job_family\M', 'mdm_job_family', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mhr_grade\M', 'mdm_grade', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mhr_job_profile\M', 'mdm_job_profile', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mhr_position\M', 'mdm_position', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mhr_employee\M', 'mdm_employee', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mhr_employee_assignment\M', 'mdm_employee_assignment', 'g');
    execute rewritten_definition;
  end loop;
end;
$$;

create view public.sys_organization
with (security_invoker = true)
as select * from public.mdm_organization;

create view public.hr_job_family
with (security_invoker = true)
as select * from public.mdm_job_family;

create view public.hr_grade
with (security_invoker = true)
as select * from public.mdm_grade;

create view public.hr_job_profile
with (security_invoker = true)
as select * from public.mdm_job_profile;

create view public.hr_position
with (security_invoker = true)
as select * from public.mdm_position;

create view public.hr_employee
with (security_invoker = true)
as select * from public.mdm_employee;

create view public.hr_employee_assignment
with (security_invoker = true)
as select * from public.mdm_employee_assignment;

comment on view public.sys_organization is
  'Deprecated compatibility view. Use public.mdm_organization for new integrations.';
comment on view public.hr_job_family is
  'Deprecated compatibility view. Use public.mdm_job_family for new integrations.';
comment on view public.hr_grade is
  'Deprecated compatibility view. Use public.mdm_grade for new integrations.';
comment on view public.hr_job_profile is
  'Deprecated compatibility view. Use public.mdm_job_profile for new integrations.';
comment on view public.hr_position is
  'Deprecated compatibility view. Use public.mdm_position for new integrations.';
comment on view public.hr_employee is
  'Deprecated compatibility view. Use public.mdm_employee for new integrations.';
comment on view public.hr_employee_assignment is
  'Deprecated compatibility view. Use public.mdm_employee_assignment for new integrations.';

revoke all on public.sys_organization from public, anon, authenticated;
revoke all on public.hr_job_family from public, anon, authenticated;
revoke all on public.hr_grade from public, anon, authenticated;
revoke all on public.hr_job_profile from public, anon, authenticated;
revoke all on public.hr_position from public, anon, authenticated;
revoke all on public.hr_employee from public, anon, authenticated;
revoke all on public.hr_employee_assignment from public, anon, authenticated;

grant select, insert, update, delete on public.sys_organization to authenticated;
grant select on public.hr_job_family to authenticated;
grant select on public.hr_grade to authenticated;
grant select on public.hr_job_profile to authenticated;
grant select on public.hr_position to authenticated;
grant select on public.hr_employee_assignment to authenticated;

grant select, insert, update, delete on
  public.sys_organization,
  public.hr_job_family,
  public.hr_grade,
  public.hr_job_profile,
  public.hr_position,
  public.hr_employee,
  public.hr_employee_assignment
to service_role;

commit;
