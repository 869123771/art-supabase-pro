create or replace function app_private.guard_smis_accident_platform_super_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not app_private.is_platform_super() then
    raise exception '事故管理写操作仅限平台超级管理员';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke all on function app_private.guard_smis_accident_platform_super_write() from public, anon, authenticated;
create trigger smis_accident_report_platform_super_write
before insert or update or delete on public.smis_accident_report
for each row execute function app_private.guard_smis_accident_platform_super_write();
create trigger smis_accident_measure_platform_super_write
before insert or update or delete on public.smis_accident_prevention_measure
for each row execute function app_private.guard_smis_accident_platform_super_write();
create trigger smis_accident_person_platform_super_write
before insert or update or delete on public.smis_accident_person
for each row execute function app_private.guard_smis_accident_platform_super_write();
create trigger smis_work_injury_platform_super_write
before insert or update or delete on public.smis_work_injury_declaration
for each row execute function app_private.guard_smis_accident_platform_super_write();
drop policy if exists smis_accident_report_tenant_insert on public.smis_accident_report;
drop policy if exists smis_accident_report_tenant_update on public.smis_accident_report;
drop policy if exists smis_accident_report_tenant_delete on public.smis_accident_report;
create policy smis_accident_report_tenant_insert on public.smis_accident_report for insert to authenticated
with check (app_private.is_platform_super()
  and tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('SmisAccidentFlashReport:Add'));
create policy smis_accident_report_tenant_update on public.smis_accident_report for update to authenticated
using (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Edit'))
with check (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Edit'));
create policy smis_accident_report_tenant_delete on public.smis_accident_report for delete to authenticated
using (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Delete'));
drop policy if exists smis_accident_measure_tenant_insert on public.smis_accident_prevention_measure;
drop policy if exists smis_accident_measure_tenant_update on public.smis_accident_prevention_measure;
drop policy if exists smis_accident_measure_tenant_delete on public.smis_accident_prevention_measure;
create policy smis_accident_measure_tenant_insert on public.smis_accident_prevention_measure for insert to authenticated
with check (app_private.is_platform_super()
  and tenant_id = app_private.current_user_tenant_id()
  and (app_private.has_permission('SmisAccidentFlashReport:Add') or app_private.has_permission('SmisAccidentFlashReport:Edit')));
create policy smis_accident_measure_tenant_update on public.smis_accident_prevention_measure for update to authenticated
using (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Edit'))
with check (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Edit'));
create policy smis_accident_measure_tenant_delete on public.smis_accident_prevention_measure for delete to authenticated
using (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Delete'));
drop policy if exists smis_accident_person_tenant_insert on public.smis_accident_person;
drop policy if exists smis_accident_person_tenant_update on public.smis_accident_person;
drop policy if exists smis_accident_person_tenant_delete on public.smis_accident_person;
create policy smis_accident_person_tenant_insert on public.smis_accident_person for insert to authenticated
with check (app_private.is_platform_super()
  and tenant_id = app_private.current_user_tenant_id()
  and (app_private.has_permission('SmisAccidentFlashReport:Add') or app_private.has_permission('SmisAccidentFlashReport:Edit')));
create policy smis_accident_person_tenant_update on public.smis_accident_person for update to authenticated
using (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Edit'))
with check (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Edit'));
create policy smis_accident_person_tenant_delete on public.smis_accident_person for delete to authenticated
using (app_private.is_platform_super() and app_private.has_permission('SmisAccidentFlashReport:Delete'));
drop policy if exists smis_work_injury_tenant_insert on public.smis_work_injury_declaration;
drop policy if exists smis_work_injury_tenant_update on public.smis_work_injury_declaration;
drop policy if exists smis_work_injury_tenant_delete on public.smis_work_injury_declaration;
create policy smis_work_injury_tenant_insert on public.smis_work_injury_declaration for insert to authenticated
with check (app_private.is_platform_super()
  and tenant_id = app_private.current_user_tenant_id()
  and app_private.has_permission('SmisWorkInjuryDeclaration:Add'));
create policy smis_work_injury_tenant_update on public.smis_work_injury_declaration for update to authenticated
using (app_private.is_platform_super() and app_private.has_permission('SmisWorkInjuryDeclaration:Edit'))
with check (app_private.is_platform_super() and app_private.has_permission('SmisWorkInjuryDeclaration:Edit'));
create policy smis_work_injury_tenant_delete on public.smis_work_injury_declaration for delete to authenticated
using (app_private.is_platform_super() and app_private.has_permission('SmisWorkInjuryDeclaration:Delete'));
-- Ordinary users retain tenant-scoped read/export access. Controlled writes are
-- granted only to the platform-super role at both menu and database boundaries.
delete from public.sys_role_menu grant_row
using public.sys_menu button, public.sys_role role
where grant_row.menu_id = button.id
  and grant_row.role_id = role.id
  and grant_row.tenant_id = role.tenant_id
  and button.name in (
    'SmisAccidentFlashReport:Add', 'SmisAccidentFlashReport:Edit', 'SmisAccidentFlashReport:Delete',
    'SmisWorkInjuryDeclaration:Add', 'SmisWorkInjuryDeclaration:Edit', 'SmisWorkInjuryDeclaration:Delete'
  )
  and role.builtin_type is distinct from 'platform_super';
insert into public.sys_role_menu(
  id, role_id, menu_id, permission, tenant_id, create_by, create_time, update_by, update_time
)
select gen_random_uuid(), page_grant.role_id, button.id, '{}'::jsonb, page_grant.tenant_id,
  '624944977@qq.com', now(), '624944977@qq.com', now()
from public.sys_menu page
join public.sys_role_menu page_grant on page_grant.menu_id = page.id
join public.sys_role role on role.id = page_grant.role_id
  and role.tenant_id = page_grant.tenant_id
  and role.builtin_type = 'platform_super'
join public.sys_menu button on button.parent_id = page.id and button.type = 'button'
where page.name in ('SmisAccidentFlashReport', 'SmisWorkInjuryDeclaration')
  and button.name in (
    'SmisAccidentFlashReport:Add', 'SmisAccidentFlashReport:Edit', 'SmisAccidentFlashReport:Delete',
    'SmisWorkInjuryDeclaration:Add', 'SmisWorkInjuryDeclaration:Edit', 'SmisWorkInjuryDeclaration:Delete'
  )
  and not exists (
    select 1 from public.sys_role_menu existing
    where existing.role_id = page_grant.role_id
      and existing.menu_id = button.id
      and existing.tenant_id = page_grant.tenant_id
  );
