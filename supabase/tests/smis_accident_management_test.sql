begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(40);

select has_table('public', 'smis_accident_report', 'accident report table exists');
select has_table('public', 'smis_accident_prevention_measure', 'prevention measure table exists');
select has_table('public', 'smis_accident_person', 'accident person snapshot table exists');
select has_table('public', 'smis_work_injury_declaration', 'work injury declaration table exists');
select has_table('public', 'smis_accident_analysis', 'accident analysis table exists');
select has_table('public', 'smis_accident_analysis_participant', 'analysis participant table exists');

select ok((select relrowsecurity from pg_class where oid='public.smis_accident_report'::regclass), 'accident reports enforce RLS');
select ok((select relrowsecurity from pg_class where oid='public.smis_accident_prevention_measure'::regclass), 'prevention measures enforce RLS');
select ok((select relrowsecurity from pg_class where oid='public.smis_accident_person'::regclass), 'accident people enforce RLS');
select ok((select relrowsecurity from pg_class where oid='public.smis_work_injury_declaration'::regclass), 'work injury declarations enforce RLS');
select ok((select relrowsecurity from pg_class where oid='public.smis_accident_analysis'::regclass), 'accident analyses enforce RLS');
select ok((select relrowsecurity from pg_class where oid='public.smis_accident_analysis_participant'::regclass), 'analysis participants enforce RLS');
select hasnt_function(
  'app_private',
  'guard_smis_accident_platform_super_write',
  array[]::text[],
  'accident writes are not hard-gated to platform-super'
);
select is(
  (select count(*)::integer from pg_trigger where not tgisinternal and tgname in (
    'smis_accident_report_platform_super_write', 'smis_accident_measure_platform_super_write',
    'smis_accident_person_platform_super_write', 'smis_work_injury_platform_super_write',
    'smis_accident_analysis_platform_super_write',
    'smis_accident_analysis_participant_platform_super_write'
  )),
  0,
  'accident management tables do not retain platform-super write triggers'
);
select ok(
  not exists (
    select 1
    from pg_policy policy
    where policy.polrelid in (
      'public.smis_accident_report'::regclass,
      'public.smis_accident_prevention_measure'::regclass,
      'public.smis_accident_person'::regclass,
      'public.smis_accident_analysis'::regclass,
      'public.smis_accident_analysis_participant'::regclass,
      'public.smis_work_injury_declaration'::regclass
    )
      and policy.polcmd in ('a', 'w', 'd')
      and concat_ws(
        ' ',
        pg_get_expr(policy.polqual, policy.polrelid),
        pg_get_expr(policy.polwithcheck, policy.polrelid)
      ) like '%is_platform_super() AND%'
  ),
  'write policies use tenant scope and button permissions instead of a platform-super gate'
);
select ok(
  exists(select 1 from pg_trigger where not tgisinternal and tgname='smis_accident_report_create_analysis'),
  'accident report automatically creates an analysis row'
);
select ok(
  exists (
    select 1
    from sys_role_menu rm
    join sys_role role on role.id=rm.role_id and role.tenant_id=rm.tenant_id
    join sys_menu button on button.id=rm.menu_id
    where button.name in (
      'SmisAccidentInvestigation:Add', 'SmisAccidentInvestigation:Edit',
      'SmisAccidentInvestigation:Delete'
    )
      and role.builtin_type is distinct from 'platform_super'
  ),
  'ordinary business roles can receive accident investigation write buttons'
);

select has_function('public', 'smis_list_accident_employee_candidates_secure', array['integer', 'integer', 'text'], 'employee candidate RPC exists');
select has_function('public', 'smis_list_accident_reports_secure', array['integer', 'integer', 'text', 'text', 'text', 'uuid', 'timestamptz', 'timestamptz', 'uuid[]'], 'accident list RPC exists');
select has_function('public', 'smis_save_accident_report_secure', array['uuid', 'jsonb'], 'accident save RPC exists');
select has_function('public', 'smis_delete_accident_reports_secure', array['uuid[]'], 'accident delete RPC exists');
select has_function('public', 'smis_list_accident_report_options_secure', array['text'], 'accident option RPC exists');
select has_function('public', 'smis_list_work_injury_declarations_secure', array['integer', 'integer', 'text', 'text', 'date', 'date', 'uuid[]'], 'work injury list RPC exists');
select has_function('public', 'smis_save_work_injury_declaration_secure', array['uuid', 'jsonb'], 'work injury save RPC exists');
select has_function('public', 'smis_delete_work_injury_declarations_secure', array['uuid[]'], 'work injury delete RPC exists');
select has_function('public', 'smis_list_accident_analyses_secure', array['integer', 'integer', 'text', 'text', 'uuid[]'], 'accident analysis list RPC exists');
select has_function('public', 'smis_save_accident_analysis_secure', array['uuid', 'jsonb'], 'accident analysis save RPC exists');
select has_function('public', 'smis_delete_accident_analyses_secure', array['uuid[]'], 'accident analysis delete RPC exists');

select ok(
  not exists (
    select 1
    from unnest(array[
      'smis_list_accident_employee_candidates_secure(integer,integer,text)',
      'smis_list_accident_reports_secure(integer,integer,text,text,text,uuid,timestamptz,timestamptz,uuid[])',
      'smis_save_accident_report_secure(uuid,jsonb)',
      'smis_delete_accident_reports_secure(uuid[])',
      'smis_list_accident_report_options_secure(text)',
      'smis_list_work_injury_declarations_secure(integer,integer,text,text,date,date,uuid[])',
      'smis_save_work_injury_declaration_secure(uuid,jsonb)',
      'smis_delete_work_injury_declarations_secure(uuid[])'
      ,'smis_list_accident_analyses_secure(integer,integer,text,text,uuid[])'
      ,'smis_save_accident_analysis_secure(uuid,jsonb)'
      ,'smis_delete_accident_analyses_secure(uuid[])'
    ]) signature
    where has_function_privilege('anon', 'public.' || signature, 'execute')
  ),
  'anonymous role cannot call accident management RPCs'
);
select ok(
  not exists (
    select 1
    from unnest(array[
      'smis_list_accident_employee_candidates_secure(integer,integer,text)',
      'smis_list_accident_reports_secure(integer,integer,text,text,text,uuid,timestamptz,timestamptz,uuid[])',
      'smis_save_accident_report_secure(uuid,jsonb)',
      'smis_delete_accident_reports_secure(uuid[])',
      'smis_list_accident_report_options_secure(text)',
      'smis_list_work_injury_declarations_secure(integer,integer,text,text,date,date,uuid[])',
      'smis_save_work_injury_declaration_secure(uuid,jsonb)',
      'smis_delete_work_injury_declarations_secure(uuid[])'
      ,'smis_list_accident_analyses_secure(integer,integer,text,text,uuid[])'
      ,'smis_save_accident_analysis_secure(uuid,jsonb)'
      ,'smis_delete_accident_analyses_secure(uuid[])'
    ]) signature
    where not has_function_privilege('authenticated', 'public.' || signature, 'execute')
  ),
  'authenticated role can call accident management RPC boundaries'
);

select is((select count(*)::integer from sys_dictionary d join sys_dict_type t on t.id=d.type_id where t.code='smisAccidentCategory' and d.status='1'), 19, 'accident category dictionary is complete');
select is((select count(*)::integer from sys_dictionary d join sys_dict_type t on t.id=d.type_id where t.code='smisAccidentLevel' and d.status='1'), 6, 'accident level dictionary is complete');
select is((select count(*)::integer from sys_dictionary d join sys_dict_type t on t.id=d.type_id where t.code='smisWorkInjuryType' and d.status='1'), 4, 'work injury type dictionary is complete');

select is((select count(*)::integer from sys_menu where type='button' and name like 'SmisAccidentFlashReport:%'), 5, 'accident page exposes five button permissions');
select is((select count(*)::integer from sys_menu where type='button' and name like 'SmisWorkInjuryDeclaration:%'), 5, 'work injury page exposes five button permissions');
select is((select count(*)::integer from sys_menu where type='button' and name like 'SmisAccidentInvestigation:%'), 5, 'accident analysis page exposes five button permissions');
select is((select count(*)::integer from sys_document_number_scene where rule_key in ('smis.accident_report', 'smis.work_injury_declaration') and enabled), 2, 'both document number scenes are enabled');
select is((select count(*)::integer from pg_constraint where contype='f' and conrelid in ('public.smis_accident_prevention_measure'::regclass, 'public.smis_accident_person'::regclass, 'public.smis_work_injury_declaration'::regclass) and confrelid='public.smis_accident_report'::regclass), 3, 'child records retain normalized accident foreign keys');
select is((select count(*)::integer from pg_constraint where contype='f' and conrelid='public.smis_accident_analysis'::regclass and confrelid='public.smis_accident_report'::regclass), 1, 'analysis retains one normalized accident foreign key');
select is((select count(*)::integer from pg_constraint where conrelid='public.smis_accident_analysis'::regclass and contype='u' and conname='smis_accident_analysis_report_key'), 1, 'one accident can only have one analysis');

select * from finish();
rollback;
