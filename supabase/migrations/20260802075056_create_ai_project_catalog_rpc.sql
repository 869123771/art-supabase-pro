
create or replace function public.get_ai_project_catalog(
  p_action text,
  p_args jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_action text := lower(coalesce(nullif(btrim(p_action), ''), 'overview'));
  v_type text := lower(coalesce(nullif(btrim(p_args->>'objectType'), ''), 'all'));
  v_schema text := coalesce(nullif(btrim(p_args->>'schema'), ''), 'public');
  v_name text := nullif(btrim(p_args->>'name'), '');
  v_keyword text := nullif(btrim(p_args->>'keyword'), '');
  v_limit integer := least(greatest(coalesce((p_args->>'limit')::integer, 50), 1), 200);
  v_result jsonb;
begin
  if not public.current_is_super() then
    raise exception 'Platform super administrator permission is required'
      using errcode = '42501';
  end if;

  if v_action = 'overview' then
    select jsonb_build_object(
      'projectRef', 'ckbftoopuyophiebamwy',
      'databaseVersion', current_setting('server_version'),
      'schemas', (
        select count(*) from pg_namespace
        where nspname not like 'pg_%' and nspname <> 'information_schema'
      ),
      'tables', (
        select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where c.relkind in ('r','p') and n.nspname not like 'pg_%'
          and n.nspname <> 'information_schema'
      ),
      'views', (
        select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where c.relkind in ('v','m') and n.nspname not like 'pg_%'
          and n.nspname <> 'information_schema'
      ),
      'functions', (
        select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname not like 'pg_%' and n.nspname <> 'information_schema'
      ),
      'triggers', (
        select count(*) from pg_trigger t
        join pg_class c on c.oid=t.tgrelid
        join pg_namespace n on n.oid=c.relnamespace
        where not t.tgisinternal and n.nspname not like 'pg_%'
          and n.nspname <> 'information_schema'
      ),
      'policies', (
        select count(*) from pg_policy pol
        join pg_class c on c.oid=pol.polrelid
        join pg_namespace n on n.oid=c.relnamespace
        where n.nspname not like 'pg_%' and n.nspname <> 'information_schema'
      ),
      'indexes', (
        select count(*) from pg_index i
        join pg_class c on c.oid=i.indexrelid
        join pg_namespace n on n.oid=c.relnamespace
        where n.nspname not like 'pg_%' and n.nspname <> 'information_schema'
      )
    ) into v_result;
    return v_result;
  end if;

  if v_action = 'schemas' then
    select coalesce(jsonb_agg(x.name order by x.name), '[]'::jsonb)
    into v_result
    from (
      select nspname as name
      from pg_namespace
      where nspname not like 'pg_%' and nspname <> 'information_schema'
    ) x;
    return v_result;
  end if;

  if v_action = 'list_objects' then
    select coalesce(jsonb_agg(to_jsonb(x) order by x.object_type, x.schema_name, x.object_name), '[]'::jsonb)
    into v_result
    from (
      select *
      from (
        select n.nspname as schema_name, c.relname as object_name,
          case c.relkind when 'v' then 'view' when 'm' then 'materialized_view' else 'table' end as object_type,
          obj_description(c.oid, 'pg_class') as description
        from pg_class c join pg_namespace n on n.oid=c.relnamespace
        where c.relkind in ('r','p','v','m')
          and n.nspname not like 'pg_%' and n.nspname <> 'information_schema'
        union all
        select n.nspname, p.proname, 'function',
          obj_description(p.oid, 'pg_proc')
        from pg_proc p join pg_namespace n on n.oid=p.pronamespace
        where n.nspname not like 'pg_%' and n.nspname <> 'information_schema'
        union all
        select n.nspname, t.tgname, 'trigger',
          'on ' || quote_ident(c.relname)
        from pg_trigger t
        join pg_class c on c.oid=t.tgrelid
        join pg_namespace n on n.oid=c.relnamespace
        where not t.tgisinternal and n.nspname not like 'pg_%'
          and n.nspname <> 'information_schema'
        union all
        select n.nspname, pol.polname, 'policy',
          'on ' || quote_ident(c.relname)
        from pg_policy pol
        join pg_class c on c.oid=pol.polrelid
        join pg_namespace n on n.oid=c.relnamespace
        where n.nspname not like 'pg_%' and n.nspname <> 'information_schema'
        union all
        select n.nspname, idx.relname, 'index',
          'on ' || quote_ident(tbl.relname)
        from pg_index i
        join pg_class idx on idx.oid=i.indexrelid
        join pg_class tbl on tbl.oid=i.indrelid
        join pg_namespace n on n.oid=idx.relnamespace
        where n.nspname not like 'pg_%' and n.nspname <> 'information_schema'
      ) objects
      where (v_type = 'all' or objects.object_type = v_type
        or (v_type = 'view' and objects.object_type = 'materialized_view'))
        and (v_schema = 'all' or objects.schema_name = v_schema)
        and (v_keyword is null
          or objects.object_name ilike '%' || v_keyword || '%'
          or coalesce(objects.description, '') ilike '%' || v_keyword || '%')
      limit v_limit
    ) x;
    return v_result;
  end if;

  if v_action = 'object_detail' then
    if v_name is null then
      raise exception 'Object name is required' using errcode = '22023';
    end if;

    if v_type = 'table' then
      select jsonb_build_object(
        'schemaName', n.nspname,
        'objectName', c.relname,
        'objectType', 'table',
        'description', obj_description(c.oid, 'pg_class'),
        'columns', coalesce((
          select jsonb_agg(jsonb_build_object(
            'name', a.attname,
            'dataType', format_type(a.atttypid, a.atttypmod),
            'nullable', not a.attnotnull,
            'defaultValue', pg_get_expr(ad.adbin, ad.adrelid),
            'description', col_description(a.attrelid, a.attnum)
          ) order by a.attnum)
          from pg_attribute a
          left join pg_attrdef ad on ad.adrelid=a.attrelid and ad.adnum=a.attnum
          where a.attrelid=c.oid and a.attnum > 0 and not a.attisdropped
        ), '[]'::jsonb),
        'constraints', coalesce((
          select jsonb_agg(jsonb_build_object(
            'name', con.conname,
            'type', con.contype,
            'definition', pg_get_constraintdef(con.oid, true)
          ) order by con.conname)
          from pg_constraint con where con.conrelid=c.oid
        ), '[]'::jsonb),
        'ddl', 'CREATE TABLE ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname)
          || E' (\n'
          || coalesce((
            select string_agg(
              '  ' || quote_ident(a.attname) || ' ' || format_type(a.atttypid, a.atttypmod)
              || case when ad.adbin is not null then ' DEFAULT ' || pg_get_expr(ad.adbin, ad.adrelid) else '' end
              || case when a.attnotnull then ' NOT NULL' else '' end,
              E',\n' order by a.attnum
            )
            from pg_attribute a
            left join pg_attrdef ad on ad.adrelid=a.attrelid and ad.adnum=a.attnum
            where a.attrelid=c.oid and a.attnum > 0 and not a.attisdropped
          ), '')
          || coalesce((
            select E',\n' || string_agg(
              '  CONSTRAINT ' || quote_ident(con.conname) || ' ' || pg_get_constraintdef(con.oid, true),
              E',\n' order by con.conname
            )
            from pg_constraint con where con.conrelid=c.oid
          ), '')
          || E'\n);'
      ) into v_result
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname=v_schema and c.relname=v_name and c.relkind in ('r','p')
      limit 1;
    elsif v_type in ('view','materialized_view') then
      select jsonb_build_object(
        'schemaName', n.nspname, 'objectName', c.relname,
        'objectType', case c.relkind when 'm' then 'materialized_view' else 'view' end,
        'description', obj_description(c.oid, 'pg_class'),
        'ddl', 'CREATE ' || case when c.relkind='m' then 'MATERIALIZED ' else '' end
          || 'VIEW ' || quote_ident(n.nspname) || '.' || quote_ident(c.relname)
          || E' AS\n' || pg_get_viewdef(c.oid, true) || ';'
      ) into v_result
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname=v_schema and c.relname=v_name and c.relkind in ('v','m')
      limit 1;
    elsif v_type = 'function' then
      select jsonb_build_object(
        'schemaName', n.nspname, 'objectName', p.proname, 'objectType', 'function',
        'description', obj_description(p.oid, 'pg_proc'),
        'identityArguments', pg_get_function_identity_arguments(p.oid),
        'resultType', pg_get_function_result(p.oid),
        'ddl', pg_get_functiondef(p.oid)
      ) into v_result
      from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname=v_schema and p.proname=v_name
      order by p.oid limit 1;
    elsif v_type = 'trigger' then
      select jsonb_build_object(
        'schemaName', n.nspname, 'objectName', t.tgname, 'objectType', 'trigger',
        'tableName', c.relname, 'enabled', t.tgenabled,
        'ddl', pg_get_triggerdef(t.oid, true) || ';'
      ) into v_result
      from pg_trigger t
      join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace
      where n.nspname=v_schema and t.tgname=v_name and not t.tgisinternal
      limit 1;
    elsif v_type = 'policy' then
      select jsonb_build_object(
        'schemaName', schemaname, 'objectName', policyname, 'objectType', 'policy',
        'tableName', tablename, 'command', cmd, 'roles', roles,
        'usingExpression', qual, 'checkExpression', with_check,
        'ddl', 'CREATE POLICY ' || quote_ident(policyname) || ' ON '
          || quote_ident(schemaname) || '.' || quote_ident(tablename)
          || ' FOR ' || cmd
          || case when array_length(roles,1) > 0 then ' TO ' || array_to_string(roles, ', ') else '' end
          || case when qual is not null then ' USING (' || qual || ')' else '' end
          || case when with_check is not null then ' WITH CHECK (' || with_check || ')' else '' end
          || ';'
      ) into v_result
      from pg_policies
      where schemaname=v_schema and policyname=v_name
      limit 1;
    elsif v_type = 'index' then
      select jsonb_build_object(
        'schemaName', n.nspname, 'objectName', idx.relname, 'objectType', 'index',
        'tableName', tbl.relname, 'isUnique', i.indisunique, 'isPrimary', i.indisprimary,
        'ddl', pg_get_indexdef(idx.oid) || ';'
      ) into v_result
      from pg_index i
      join pg_class idx on idx.oid=i.indexrelid
      join pg_class tbl on tbl.oid=i.indrelid
      join pg_namespace n on n.oid=idx.relnamespace
      where n.nspname=v_schema and idx.relname=v_name
      limit 1;
    else
      raise exception 'Unsupported object type: %', v_type using errcode = '22023';
    end if;
    return coalesce(v_result, jsonb_build_object('notFound', true));
  end if;

  if v_action = 'relationships' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'constraintName', con.conname,
      'sourceSchema', ns.nspname,
      'sourceTable', src.relname,
      'sourceColumns', (
        select jsonb_agg(sa.attname order by k.ordinality)
        from unnest(con.conkey) with ordinality k(attnum, ordinality)
        join pg_attribute sa on sa.attrelid=con.conrelid and sa.attnum=k.attnum
      ),
      'targetSchema', nt.nspname,
      'targetTable', tgt.relname,
      'targetColumns', (
        select jsonb_agg(ta.attname order by k.ordinality)
        from unnest(con.confkey) with ordinality k(attnum, ordinality)
        join pg_attribute ta on ta.attrelid=con.confrelid and ta.attnum=k.attnum
      ),
      'definition', pg_get_constraintdef(con.oid, true)
    ) order by ns.nspname, src.relname, con.conname), '[]'::jsonb)
    into v_result
    from pg_constraint con
    join pg_class src on src.oid=con.conrelid
    join pg_namespace ns on ns.oid=src.relnamespace
    join pg_class tgt on tgt.oid=con.confrelid
    join pg_namespace nt on nt.oid=tgt.relnamespace
    where con.contype='f'
      and ns.nspname not like 'pg_%' and ns.nspname <> 'information_schema'
      and (v_schema='all' or ns.nspname=v_schema)
      and (v_name is null or src.relname=v_name or tgt.relname=v_name);
    return v_result;
  end if;

  raise exception 'Unsupported catalog action: %', v_action using errcode = '22023';
exception
  when invalid_text_representation then
    raise exception 'Invalid catalog arguments' using errcode = '22023';
end;
$function$;

revoke all on function public.get_ai_project_catalog(text, jsonb) from public;
revoke all on function public.get_ai_project_catalog(text, jsonb) from anon;
grant execute on function public.get_ai_project_catalog(text, jsonb) to authenticated;
grant execute on function public.get_ai_project_catalog(text, jsonb) to service_role;
comment on function public.get_ai_project_catalog(text, jsonb)
is 'Platform-super-only allowlisted read-only database catalog for the Supabase AI assistant.';
;
