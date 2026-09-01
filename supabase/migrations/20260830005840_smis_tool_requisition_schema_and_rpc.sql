
set local check_function_bodies = off;

do $migration$
declare
  source_tables text[] := array[
    'smis_ppe_issuance_standard',
    'smis_ppe_issuance_standard_detail',
    'smis_ppe_issuance_standard_organization',
    'smis_ppe_issuance_standard_position',
    'smis_ppe_personal_standard',
    'smis_ppe_personal_standard_item',
    'smis_ppe_personal_requisition',
    'smis_ppe_personal_requisition_item',
    'smis_ppe_issuance_record',
    'smis_ppe_issuance_record_item',
    'smis_ppe_setting'
  ];
  source_table text;
  target_table text;
  object_record record;
  policy_record record;
  function_record record;
  definition text;
  target_name text;
  roles_sql text;
begin
  foreach source_table in array source_tables loop
    target_table := replace(source_table, 'smis_ppe_', 'smis_tool_');
    if to_regclass(format('public.%I', target_table)) is null then
      execute format('create table public.%I (like public.%I including all)', target_table, source_table);
    end if;
  end loop;

  for object_record in
    select c.relname as source_table, con.conname, pg_get_constraintdef(con.oid, true) as definition
    from pg_constraint con
    join pg_class c on c.oid = con.conrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = any(source_tables) and con.contype = 'f'
    order by c.relname, con.conname
  loop
    target_table := replace(object_record.source_table, 'smis_ppe_', 'smis_tool_');
    target_name := replace(object_record.conname, 'ppe', 'tool');
    if not exists (
      select 1 from pg_constraint
      where conrelid = format('public.%I', target_table)::regclass and conname = target_name
    ) then
      definition := replace(object_record.definition, 'smis_ppe_', 'smis_tool_');
      execute format('alter table public.%I add constraint %I %s', target_table, target_name, definition);
    end if;
  end loop;

  for object_record in
    select c.relname as source_table, t.tgname, pg_get_triggerdef(t.oid, true) as definition
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = any(source_tables) and not t.tgisinternal
    order by c.relname, t.tgname
  loop
    target_table := replace(object_record.source_table, 'smis_ppe_', 'smis_tool_');
    target_name := replace(object_record.tgname, 'ppe', 'tool');
    if not exists (
      select 1 from pg_trigger
      where tgrelid = format('public.%I', target_table)::regclass
        and tgname = target_name and not tgisinternal
    ) then
      definition := replace(object_record.definition, 'smis_ppe_', 'smis_tool_');
      definition := replace(definition, 'ppe', 'tool');
      execute definition;
    end if;
  end loop;

  foreach source_table in array source_tables loop
    target_table := replace(source_table, 'smis_ppe_', 'smis_tool_');
    execute format('alter table public.%I enable row level security', target_table);
    execute format('revoke all on table public.%I from anon', target_table);
    execute format('grant all on table public.%I to authenticated, service_role', target_table);
  end loop;

  for policy_record in
    select * from pg_policies
    where schemaname = 'public' and tablename = any(source_tables)
    order by tablename, policyname
  loop
    target_table := replace(policy_record.tablename, 'smis_ppe_', 'smis_tool_');
    target_name := replace(policy_record.policyname, 'ppe', 'tool');
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = target_table and policyname = target_name
    ) then
      roles_sql := array_to_string(policy_record.roles, ', ');
      definition := format(
        'create policy %I on public.%I for %s to %s',
        target_name, target_table, policy_record.cmd, roles_sql
      );
      if policy_record.qual is not null then
        definition := definition || format(
          ' using (%s)',
          replace(replace(policy_record.qual, 'smis_ppe_', 'smis_tool_'), 'SmisPpe', 'SmisTool')
        );
      end if;
      if policy_record.with_check is not null then
        definition := definition || format(
          ' with check (%s)',
          replace(replace(policy_record.with_check, 'smis_ppe_', 'smis_tool_'), 'SmisPpe', 'SmisTool')
        );
      end if;
      execute definition;
    end if;
  end loop;

  for function_record in
    select p.oid, n.nspname as schema_name, p.proname,
      pg_get_function_identity_arguments(p.oid) as identity_arguments
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where
      (n.nspname = 'public' and p.proname like 'smis%ppe%')
      or (
        n.nspname = 'app_private'
        and (
          p.proname like '%\_ppe\_%' escape '\'
          or p.proname like 'ppe\_%' escape '\'
        )
      )
    order by case when n.nspname = 'app_private' then 0 else 1 end, p.proname
  loop
    definition := pg_get_functiondef(function_record.oid);
    definition := replace(definition, 'smis_ppe_', 'smis_tool_');
    definition := replace(definition, 'ppe_', 'tool_');
    definition := replace(definition, 'SmisPpe', 'SmisTool');
    definition := replace(definition, 'protective_equipment', 'tool');
    definition := replace(definition, '防护用品', '工器具');
    definition := replace(definition, '劳保单', '工器具发放单');
    execute definition;

    target_name := replace(function_record.proname, 'ppe_', 'tool_');
    if function_record.schema_name = 'public' then
      execute format(
        'revoke all on function public.%I(%s) from public, anon',
        target_name, function_record.identity_arguments
      );
      execute format(
        'grant execute on function public.%I(%s) to authenticated, service_role',
        target_name, function_record.identity_arguments
      );
    else
      execute format(
        'revoke all on function app_private.%I(%s) from public, anon, authenticated',
        target_name, function_record.identity_arguments
      );
    end if;
  end loop;
end
$migration$;

notify pgrst, 'reload schema';
;
