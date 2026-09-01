drop view if exists public.hr_position_headcount_overview;

create or replace function public.hr_resolve_workspace_references_secure(
  p_employee_ids uuid[] default array[]::uuid[],
  p_position_ids uuid[] default array[]::uuid[],
  p_organization_ids uuid[] default array[]::uuid[],
  p_headcount_scopes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_is_platform boolean := app_private.is_platform_super();
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not v_is_platform and not (
    app_private.has_permission('Hr:Employee:View')
    or app_private.has_permission('Hr:Position:View')
    or app_private.has_permission('Hr:PersonnelChange:View')
    or app_private.has_permission('Hr:Lifecycle:View')
    or app_private.has_permission('Hr:Compliance:View')
    or app_private.has_permission('Hr:Headcount:View')
    or app_private.has_permission('Hr:Attendance:View')
    or app_private.has_permission('Hr:SelfService:View')
    or app_private.has_permission('Hr:Performance:View')
    or app_private.has_permission('Hr:Talent:View')
    or app_private.has_permission('Hr:Recruitment:View')
  ) then
    raise exception '当前账号没有查看人力资源引用数据的权限' using errcode='42501';
  end if;

  return jsonb_build_object(
    'employees',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',e.id,'employeeNo',e.employee_no,'employeeName',e.employee_name
      ) order by e.employee_name,e.employee_no)
      from public.hr_employee e
      where e.id=any(coalesce(p_employee_ids,array[]::uuid[]))
        and (v_is_platform or e.tenant_id=v_tenant_id)
    ),'[]'::jsonb),
    'positions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',p.id,'positionCode',p.position_code,'positionName',p.position_name
      ) order by p.position_name,p.position_code)
      from public.hr_position p
      where p.id=any(coalesce(p_position_ids,array[]::uuid[]))
        and (v_is_platform or p.tenant_id=v_tenant_id)
    ),'[]'::jsonb),
    'organizations',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',o.id,'organizationCode',o.organization_code,'organizationName',o.organization_name
      ) order by o.organization_name,o.organization_code)
      from public.sys_organization o
      where o.id=any(coalesce(p_organization_ids,array[]::uuid[]))
        and (v_is_platform or o.tenant_id=v_tenant_id)
    ),'[]'::jsonb),
    'headcounts',coalesce((
      select jsonb_agg(jsonb_build_object(
        'organizationId',scope.organization_id,
        'positionId',scope.position_id,
        'occupiedCount',(
          select count(*) from public.hr_employee e
          where e.organization_id=scope.organization_id and e.position_id=scope.position_id
            and e.employment_status<>'terminated'
            and (v_is_platform or e.tenant_id=v_tenant_id)
        )
      ))
      from jsonb_to_recordset(coalesce(p_headcount_scopes,'[]'::jsonb))
        as scope(organization_id uuid,position_id uuid)
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.hr_resolve_workspace_references_secure(uuid[],uuid[],uuid[],jsonb)
from public,anon;
grant execute on function public.hr_resolve_workspace_references_secure(uuid[],uuid[],uuid[],jsonb)
to authenticated;;
