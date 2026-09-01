begin;
update public.sys_notification_scenario
set route_path = '/smis/safety-production/document-center/all-documents'
where scenario_code = 'smis_document_effective';
update public.sys_notification_subject
set route_path = '/smis/safety-production/document-center/all-documents',
    update_by = 'system-document-center'
where business_type = 'smis_document'
  and route_path = '/safety-production/document-center/all-documents';
do $migration$
declare
  v_function regprocedure;
  v_definition text;
  v_updated_definition text;
begin
  foreach v_function in array array[
    'public.smis_save_document_secure(uuid,jsonb)'::regprocedure,
    'public.smis_share_document_secure(uuid,uuid[],text)'::regprocedure
  ] loop
    select pg_get_functiondef(v_function) into v_definition;
    v_updated_definition := replace(
      v_definition,
      '/safety-production/document-center/all-documents',
      '/smis/safety-production/document-center/all-documents'
    );
    if v_updated_definition <> v_definition then
      execute v_updated_definition;
    end if;
  end loop;
end;
$migration$;
commit;
