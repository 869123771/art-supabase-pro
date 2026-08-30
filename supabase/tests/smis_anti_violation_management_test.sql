begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(28);

select has_table('public', 'smis_violation_category', 'violation category table exists');
select has_table('public', 'smis_anti_violation_standard', 'anti-violation standard table exists');
select has_table(
  'public',
  'smis_three_violation_education',
  'three-violation education table exists'
);
select has_table(
  'public',
  'smis_three_violation_education_responsible',
  'education responsible employee table exists'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.smis_violation_category'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_anti_violation_standard'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_three_violation_education'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_three_violation_education_responsible'::regclass),
  'all anti-violation tables enforce RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.smis_violation_category', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smis_anti_violation_standard', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smis_three_violation_education', 'DELETE')
  and not has_table_privilege(
    'authenticated',
    'public.smis_three_violation_education_responsible',
    'INSERT'
  ),
  'authenticated callers cannot bypass secure RPC write boundaries'
);

select has_function(
  'public',
  'smis_list_violation_categories_secure',
  array['integer', 'integer', 'text', 'text', 'uuid', 'text'],
  'category list RPC exists'
);
select has_function(
  'public',
  'smis_save_violation_category_secure',
  array['uuid', 'jsonb'],
  'category save RPC exists'
);
select has_function(
  'public',
  'smis_list_anti_violation_standards_secure',
  array['integer', 'integer', 'text', 'text', 'uuid', 'text'],
  'standard list RPC exists'
);
select has_function(
  'public',
  'smis_save_anti_violation_standard_secure',
  array['uuid', 'jsonb'],
  'standard save RPC exists'
);
select has_function(
  'public',
  'smis_list_three_violation_education_secure',
  array[
    'integer', 'integer', 'text', 'uuid', 'uuid', 'text', 'text',
    'timestamp with time zone', 'timestamp with time zone', 'text'
  ],
  'education list RPC exists'
);
select has_function(
  'public',
  'smis_save_three_violation_education_secure',
  array['uuid', 'jsonb'],
  'education save RPC exists'
);
select has_function(
  'public',
  'smis_record_three_violation_education_secure',
  array['uuid', 'jsonb'],
  'education recording RPC exists'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.smis_record_three_violation_education_secure(uuid,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.smis_record_three_violation_education_secure(uuid,jsonb)',
    'EXECUTE'
  ),
  'only authenticated callers can record education information'
);

select ok(
  position(
    'smisthreeviolationeducation:recordeducation' in (
      select lower(p.prosrc)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'smis_record_three_violation_education_secure'
    )
  ) > 0,
  'education lifecycle transition checks the exact record permission'
);

select ok(
  position('smisthreeviolationeducation:add' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_save_three_violation_education_secure'
  ))) > 0
  and position('smisthreeviolationeducation:copy' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_save_three_violation_education_secure'
  ))) > 0,
  'education add and copy operations enforce their exact permissions'
);

select ok(
  position('smisantiviolationstandardlibrary:import' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_save_anti_violation_standard_secure'
  ))) > 0,
  'standard imports enforce the exact import permission'
);

select ok(
  position('smisviolationcategory:export' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_list_violation_categories_secure'
  ))) > 0,
  'category exports enforce the exact export permission'
);

select ok(
  position(
    'education_status = ''pending''' in (
      select lower(p.prosrc)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname = 'smis_save_three_violation_education_secure'
    )
  ) > 0,
  'base education edits are restricted to pending records'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'smis_three_violation_scope_idx'
  ),
  'education status and inspection time filters use a scoped index'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'smis_three_violation_checker_idx'
  ),
  'checker filtering uses an index'
);

select ok(
  exists (select 1 from public.sys_dict_type where code = 'smisAntiViolationStatus')
  and exists (select 1 from public.sys_dict_type where code = 'smisThreeViolationWarningStatus')
  and exists (select 1 from public.sys_dict_type where code = 'smisThreeViolationEducationStatus'),
  'anti-violation status dictionaries are registered'
);

select ok(
  exists (
    select 1 from public.sys_dictionary data
    join public.sys_dict_type type on type.id = data.type_id
    where type.code = 'smisThreeViolationEducationStatus' and data.value = 'pending'
  )
  and exists (
    select 1 from public.sys_dictionary data
    join public.sys_dict_type type on type.id = data.type_id
    where type.code = 'smisThreeViolationEducationStatus' and data.value = 'educated'
  ),
  'education status dictionary contains pending and educated values'
);

select ok(
  exists (
    select 1 from public.sys_menu
    where name = 'SmisThreeViolationEducation:RecordEducation' and type = 'button'
  ),
  'record education permission is registered'
);
select ok(
  exists (
    select 1 from public.sys_menu
    where name = 'SmisThreeViolationEducation:Print' and type = 'button'
  ),
  'education ledger print permission is registered'
);
select ok(
  exists (
    select 1 from public.sys_menu
    where name = 'SmisViolationCategory:Export' and type = 'button'
  ),
  'violation category export permission is registered'
);
select ok(
  exists (
    select 1 from public.sys_menu
    where name = 'SmisAntiViolationStandardLibrary:Import' and type = 'button'
  ),
  'standard library import permission is registered'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conname = 'smis_three_violation_education_time_check'
  ),
  'education completion cannot precede its start time'
);

select * from finish();
rollback;
