create or replace function public.hr_get_employee_relation_case_detail_secure(
  p_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
  v_sensitive boolean := app_private.is_platform_super()
    or app_private.has_permission('Hr:EmployeeRelations:Sensitive:View');
begin
  v_result := app_private.hr_get_employee_relation_case_detail_internal(p_id);
  if not v_sensitive then
    v_result := v_result
      - 'remark'
      - 'external_reference'
      - 'reporter_employee';
  end if;
  return v_result;
end
$function$;

revoke all on function public.hr_get_employee_relation_case_detail_secure(uuid)
  from public, anon;
grant execute on function public.hr_get_employee_relation_case_detail_secure(uuid)
  to authenticated, service_role;

;
