begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(26);

select has_table('public', 'smis_tool_issuance_standard', 'tool issuance standards exist');
select has_table('public', 'smis_tool_personal_standard', 'personal tool standards exist');
select has_table('public', 'smis_tool_personal_requisition', 'personal tool requisitions exist');
select has_table('public', 'smis_tool_issuance_record', 'tool issuance records exist');
select has_table('public', 'smis_tool_return', 'tool return headers exist');
select has_table('public', 'smis_tool_return_item', 'tool return items exist');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.smis_tool_return'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_tool_return_item'::regclass),
  'tool return tables enforce RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.smis_tool_issuance_record', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smis_tool_issuance_record', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smis_tool_issuance_record', 'DELETE'),
  'authenticated users cannot bypass issuance RPC write authorization'
);
select ok(
  not has_table_privilege('anon', 'public.smis_tool_return', 'SELECT')
  and not has_table_privilege('anon', 'public.smis_tool_return', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smis_tool_return', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smis_tool_return', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smis_tool_return', 'DELETE'),
  'authenticated users cannot bypass return RPC write authorization'
);

select has_function(
  'public',
  'smis_list_tool_returns_secure',
  array['integer', 'integer', 'date', 'date', 'uuid', 'text', 'text', 'text'],
  'tenant-safe tool return list RPC exists'
);

select ok(
  position(
    'min(r.tenant_id)' in (
      select lower(p.prosrc)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'smis_push_tool_requisition_items_secure'
    )
  ) = 0,
  'tool requisition push does not apply unsupported aggregates to UUID values'
);
select has_function(
  'public',
  'smis_save_tool_return_secure',
  array['uuid', 'jsonb', 'text'],
  'authorized tool return save RPC exists'
);
select has_function(
  'public',
  'smis_submit_tool_return_secure',
  array['uuid'],
  'tool return workflow submission RPC exists'
);

select ok(
  not has_function_privilege('anon', 'public.smis_save_tool_return_secure(uuid,jsonb,text)', 'EXECUTE')
  and has_function_privilege(
    'authenticated',
    'public.smis_save_tool_return_secure(uuid,jsonb,text)',
    'EXECUTE'
  ),
  'only authenticated callers can invoke the return save boundary'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.smis_submit_tool_return_secure(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.smis_submit_tool_return_secure(uuid)',
    'EXECUTE'
  ),
  'only authenticated callers can submit a return workflow'
);

select ok(
  exists (
    select 1
    from pg_indexes
    where schemaname = 'public'
      and indexname = 'smis_tool_return_item_source_idx'
  ),
  'return quantity validation can resolve source items through an index'
);
select ok(
  exists (
    select 1
    from public.sys_dict_type
    where code = 'smisToolReturnStatus'
  ),
  'tool return status dictionary is registered'
);
select ok(
  exists (
    select 1
    from public.sys_document_number_rule
    where rule_key = 'smis.tool_return'
      and reset_cycle = 'month'
      and template like '%{SEQ:4}%'
  ),
  'tool return numbers use a monthly four-digit sequence'
);
select ok(
  exists (
    select 1
    from public.sys_document_number_rule
    where rule_key = 'smis.tool_issuance_record'
      and reset_cycle = 'month'
      and template like '%{SEQ:4}%'
  ),
  'tool issuance numbers use a monthly four-digit sequence'
);
select ok(
  exists (
    select 1
    from cron.job
    where jobname = 'smis-tool-daily-requisition-and-confirmation'
      and active
  ),
  'daily tool requisition generation and auto-confirmation is scheduled'
);
select ok(
  position(
    'smis_tool_return' in (
      select lower(p.prosrc)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app_private'
        and p.proname = 'execute_workflow_business_callback'
    )
  ) > 0,
  'generic workflow callbacks route tool returns'
);
select ok(
  position(
    'smis_tool_return' in (
      select lower(p.prosrc)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'app_private'
        and p.proname = 'get_workflow_business_snapshot_v3'
    )
  ) > 0,
  'workflow snapshots include tool returns'
);
select ok(
  exists (
    select 1
    from public.sys_menu
    where name = 'SmisToolRequisitionReturn:Return'
      and type = 'button'
  ),
  'return action permission is registered'
);
select ok(
  exists (
    select 1
    from public.sys_menu
    where name = 'SmisToolRequisitionReturn:Submit'
      and type = 'button'
  ),
  'return workflow submission permission is registered'
);
select ok(
  exists (
    select 1
    from public.sys_menu
    where name = 'SmisToolPersonalRequisition:Configure'
      and type = 'button'
  ),
  'auto-confirm configuration permission is registered'
);
select ok(
  position(
    'smistoolrequisitionreturn:submit' in (
      select lower(p.prosrc)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'smis_submit_tool_return_secure'
    )
  ) > 0,
  'server-side return submission checks the button permission'
);

select * from finish();
rollback;
