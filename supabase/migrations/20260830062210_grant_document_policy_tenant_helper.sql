begin;
grant execute on function app_private.auth_user_tenant_id() to authenticated;
do $migration$
declare
  v_definition text;
  v_updated_definition text;
begin
  select pg_get_functiondef('public.smis_delete_documents_secure(uuid[])'::regprocedure)
  into v_definition;
  v_updated_definition := replace(
    v_definition,
    $replace$status = 'completed'$replace$,
    $replace$status = 'cancelled'$replace$
  );
  if v_updated_definition <> v_definition then
    execute v_updated_definition;
  end if;

  select pg_get_functiondef(
    'public.smis_list_documents_secure(integer,integer,text,text,uuid,text,uuid[],text)'::regprocedure
  ) into v_definition;
  v_updated_definition := replace(
    replace(
      replace(
        v_definition,
        'display_version.file_size,' || chr(10) || '      display_version.effective_date current_effective_date,',
        'display_version.file_size,' || chr(10) ||
          '      display_version.version_no current_version_no,' || chr(10) ||
          '      display_version.effective_date current_effective_date,'
      ),
      'select coalesce(effective_version.id, latest_version.id) id,' || chr(10) ||
        '        coalesce(effective_version.file_name, latest_version.file_name) file_name,',
      'select coalesce(effective_version.id, latest_version.id) id,' || chr(10) ||
        '        coalesce(effective_version.version_no, latest_version.version_no) version_no,' || chr(10) ||
        '        coalesce(effective_version.file_name, latest_version.file_name) file_name,'
    ),
    $replace$'versionNo', row.latest_version_no,$replace$,
    $replace$'versionNo', row.current_version_no,$replace$
  );
  if v_updated_definition <> v_definition then
    execute v_updated_definition;
  end if;

  select pg_get_functiondef(
    'public.smis_list_documents_secure(integer,integer,text,text,uuid,text,uuid[],text)'::regprocedure
  ) into v_definition;
  v_updated_definition := replace(
    v_definition,
    $replace$'versionNo', row.current_version_no,$replace$,
    $replace$'versionNo', row.current_version_no,
        'latestVersionNo', row.latest_version_no,$replace$
  );
  if v_updated_definition <> v_definition then
    execute v_updated_definition;
  end if;
end;
$migration$;
commit;
