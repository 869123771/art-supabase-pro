create or replace function app_private.hr_employee_relation_case_visible(
  p_tenant_id uuid,
  p_subject_employee_id uuid,
  p_reporter_employee_id uuid,
  p_owner_employee_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app_private.is_platform_super()
    or (
      p_tenant_id = app_private.current_user_tenant_id()
      and (
        p_subject_employee_id = app_private.hr_current_employee_id()
        or p_reporter_employee_id = app_private.hr_current_employee_id()
        or p_owner_employee_id = app_private.hr_current_employee_id()
        or app_private.has_permission('Hr:EmployeeRelations:Assign')
        or app_private.has_permission('Hr:EmployeeRelations:Investigate')
        or app_private.has_permission('Hr:EmployeeRelations:Resolve')
        or app_private.has_permission('Hr:EmployeeRelations:Close')
        or app_private.has_permission('Hr:EmployeeRelations:Action:Manage')
        or app_private.has_permission('Hr:EmployeeRelations:Sensitive:View')
      )
    )
$function$;

revoke all on function app_private.hr_employee_relation_case_visible(
  uuid, uuid, uuid, uuid
) from public, anon, authenticated;

alter function public.hr_list_employee_relations_records_secure(
  text, integer, integer, text, text, text, text, uuid
) set schema app_private;
alter function app_private.hr_list_employee_relations_records_secure(
  text, integer, integer, text, text, text, text, uuid
) rename to hr_list_employee_relations_records_internal;

revoke all on function app_private.hr_list_employee_relations_records_internal(
  text, integer, integer, text, text, text, text, uuid
) from public, anon, authenticated, service_role;

create or replace function public.hr_list_employee_relations_records_secure(
  p_kind text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_case_type text default null,
  p_severity text default null,
  p_tenant_id uuid default null
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
  v_result := app_private.hr_list_employee_relations_records_internal(
    p_kind, p_from, p_to, p_keyword, p_status, p_case_type, p_severity, p_tenant_id
  );

  select jsonb_set(
    v_result,
    '{records}',
    coalesce(jsonb_agg(
      case
        when v_sensitive then record - 'safe_title'
        else record - 'safe_title' - 'remark' - 'external_reference' - 'reporter_employee'
      end
    ), '[]'::jsonb)
  )
  into v_result
  from jsonb_array_elements(coalesce(v_result -> 'records', '[]'::jsonb)) record;

  return coalesce(v_result, jsonb_build_object('records', '[]'::jsonb, 'total', 0));
end
$function$;

alter function public.hr_get_employee_relation_case_detail_secure(uuid)
  set schema app_private;
alter function app_private.hr_get_employee_relation_case_detail_secure(uuid)
  rename to hr_get_employee_relation_case_detail_internal;

revoke all on function app_private.hr_get_employee_relation_case_detail_internal(uuid)
  from public, anon, authenticated, service_role;

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
    v_result := v_result - 'remark' - 'external_reference';
  end if;
  return v_result;
end
$function$;

create trigger hr_employee_relation_event_update_audit
before update on public.hr_employee_relation_event for each row
execute function public.trg_set_update_time_and_by();

revoke all on function public.hr_list_employee_relations_records_secure(
  text, integer, integer, text, text, text, text, uuid
) from public, anon;
revoke all on function public.hr_get_employee_relation_case_detail_secure(uuid)
  from public, anon;

grant execute on function public.hr_list_employee_relations_records_secure(
  text, integer, integer, text, text, text, text, uuid
) to authenticated, service_role;
grant execute on function public.hr_get_employee_relation_case_detail_secure(uuid)
  to authenticated, service_role;

;
