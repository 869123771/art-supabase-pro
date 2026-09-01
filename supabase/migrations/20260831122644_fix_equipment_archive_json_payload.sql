-- PostgreSQL functions accept at most 100 arguments; split the archive JSON constructor.
do $migration$
declare
  v_function_sql text;
  v_updated_sql text;
begin
  select pg_get_functiondef(function_row.oid)
  into v_function_sql
  from pg_proc function_row
  join pg_namespace namespace_row on namespace_row.oid = function_row.pronamespace
  where namespace_row.nspname = 'public'
    and function_row.proname = 'smis_get_equipment_archive_secure'
    and pg_get_function_identity_arguments(function_row.oid) = 'p_equipment_id uuid';

  if v_function_sql is null then
    raise exception 'smis_get_equipment_archive_secure(uuid) 不存在';
  end if;

  if position(
    $new$'specialParameters', equipment.special_parameters
  ) || jsonb_build_object(
    'useStatus'$new$ in v_function_sql
  ) > 0 then
    return;
  end if;

  v_updated_sql := replace(
    v_function_sql,
    $old$'specialParameters', equipment.special_parameters,
    'useStatus'$old$,
    $new$'specialParameters', equipment.special_parameters
  ) || jsonb_build_object(
    'useStatus'$new$
  );

  if v_updated_sql = v_function_sql then
    raise exception '设备档案 JSON 构造器修复未命中预期片段';
  end if;

  execute v_updated_sql;
end;
$migration$;

;
