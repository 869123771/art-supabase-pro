create or replace function public.hr_list_lifecycle_options_secure(
  p_kind text,
  p_tenant_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if p_kind not in ('case', 'template', 'employee', 'organization', 'position', 'handoff') then
    raise exception '不支持的生命周期选项类型';
  end if;
  if not app_private.can_execute_business_action('HrLifecycle', 'Hr:Lifecycle:View', null, false) then
    raise exception '当前账号没有查看生命周期选项的权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;

  if p_kind = 'case' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', c.id, 'tenant_id', c.tenant_id, 'code', c.case_no, 'name', e.employee_name,
      'status', c.execution_status, 'case_type', c.case_type, 'employee_id', c.employee_id
    ) order by c.planned_effective_date desc)
    from public.hr_lifecycle_case c
    join public.hr_employee e on e.id = c.employee_id and e.tenant_id = c.tenant_id
    where (p_tenant_id is null or c.tenant_id = p_tenant_id)
      and c.execution_status in ('planning', 'in_progress', 'ready')), '[]'::jsonb);
  end if;
  if p_kind = 'template' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', t.id, 'tenant_id', t.tenant_id, 'code', t.template_code, 'name', t.template_name,
      'status', t.status, 'case_type', t.case_type
    ) order by t.case_type, t.is_default desc, t.template_name)
    from public.hr_lifecycle_template t
    where (p_tenant_id is null or t.tenant_id = p_tenant_id)), '[]'::jsonb);
  end if;
  if p_kind = 'employee' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', e.id, 'tenant_id', e.tenant_id, 'code', e.employee_no, 'name', e.employee_name,
      'organization_id', e.organization_id, 'position_id', e.position_id, 'status', e.employment_status
    ) order by e.employee_no)
    from public.hr_employee e
    where (p_tenant_id is null or e.tenant_id = p_tenant_id)
      and e.employment_status <> 'terminated'), '[]'::jsonb);
  end if;
  if p_kind = 'organization' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', o.id, 'tenant_id', o.tenant_id, 'code', o.organization_code, 'name', o.organization_name,
      'status', o.status
    ) order by o.organization_code)
    from public.sys_organization o
    where (p_tenant_id is null or o.tenant_id = p_tenant_id) and o.status = '1'), '[]'::jsonb);
  end if;
  if p_kind = 'position' then
    return coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'tenant_id', p.tenant_id, 'code', p.position_code, 'name', p.position_name,
      'organization_id', p.organization_id, 'status', p.status
    ) order by p.position_code)
    from public.hr_position p
    where (p_tenant_id is null or p.tenant_id = p_tenant_id) and p.status = '1'), '[]'::jsonb);
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', h.id, 'tenant_id', h.tenant_id, 'code', c.candidate_no, 'name', e.employee_name,
    'status', h.status, 'employee_id', h.onboard_employee_id,
    'organization_id', h.organization_id, 'position_id', h.position_id
  ) order by h.completed_at desc)
  from public.hr_recruitment_handoff h
  join public.hr_candidate c on c.id = h.candidate_id and c.tenant_id = h.tenant_id
  join public.hr_employee e on e.id = h.onboard_employee_id and e.tenant_id = h.tenant_id
  where (p_tenant_id is null or h.tenant_id = p_tenant_id)
    and h.status = 'completed'
    and not exists (select 1 from public.hr_lifecycle_case lifecycle
      where lifecycle.tenant_id = h.tenant_id
        and lifecycle.source_type = 'recruitment_handoff' and lifecycle.source_id = h.id)), '[]'::jsonb);
end
$function$;

revoke all on function public.hr_list_lifecycle_options_secure(text,uuid)
  from public, anon, authenticated;
grant execute on function public.hr_list_lifecycle_options_secure(text,uuid)
  to authenticated, service_role;

;
