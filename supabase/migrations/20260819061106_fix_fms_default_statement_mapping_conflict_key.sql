do $migration$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.initialize_fms_accounting_defaults(uuid)'::regprocedure)
    into v_definition;

  v_definition := replace(
    v_definition,
    'on conflict(statement_item_id,subject_id) do nothing',
    'on conflict(statement_item_id,subject_id,mapping_direction) do nothing'
  );

  if v_definition not like '%on conflict(statement_item_id,subject_id,mapping_direction) do nothing%' then
    raise exception '未找到待修正的报表映射冲突键';
  end if;

  execute v_definition;
end;
$migration$;;
