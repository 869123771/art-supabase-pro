begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(29);

select has_table('public','smis_qualification_catalog','qualification catalog table exists');
select has_table('public','smis_personnel_certificate','certificate master table exists');
select has_table('public','smis_personnel_certificate_item','certificate item table exists');
select has_table('public','smis_personnel_certificate_review_history','immutable review history exists');

select ok(
  (select relrowsecurity from pg_class where oid='public.smis_qualification_catalog'::regclass)
  and (select relrowsecurity from pg_class where oid='public.smis_personnel_certificate'::regclass)
  and (select relrowsecurity from pg_class where oid='public.smis_personnel_certificate_item'::regclass)
  and (select relrowsecurity from pg_class where oid='public.smis_personnel_certificate_review_history'::regclass),
  'all qualification tables enforce RLS'
);

select ok(
  not has_table_privilege('authenticated','public.smis_qualification_catalog','INSERT')
  and not has_table_privilege('authenticated','public.smis_personnel_certificate','UPDATE')
  and not has_table_privilege('authenticated','public.smis_personnel_certificate_item','DELETE')
  and not has_table_privilege('authenticated','public.smis_personnel_certificate_review_history','INSERT'),
  'authenticated callers cannot bypass secure RPC write boundaries'
);

select has_function('public','smis_list_qualification_catalog_secure',array['text','integer','integer','text','text','uuid','text'],'catalog list RPC exists');
select has_function('public','smis_save_qualification_catalog_secure',array['uuid','jsonb'],'catalog save RPC exists');
select has_function('public','smis_delete_qualification_catalog_secure',array['text','uuid[]'],'catalog delete RPC exists');
select has_function('public','smis_list_personnel_certificates_secure',array['integer','integer','text','text','text','date','date','text','text'],'certificate list RPC exists');
select has_function('public','smis_save_personnel_certificate_secure',array['uuid','jsonb'],'certificate save RPC exists');
select has_function('public','smis_delete_personnel_certificates_secure',array['uuid[]'],'certificate delete RPC exists');

select ok(
  not has_function_privilege('anon','public.smis_save_personnel_certificate_secure(uuid,jsonb)','EXECUTE')
  and has_function_privilege('authenticated','public.smis_save_personnel_certificate_secure(uuid,jsonb)','EXECUTE'),
  'only authenticated callers can invoke certificate writes'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.smis_list_personnel_certificates_raw_secure(integer,integer,text,text,text,date,date,text,text)',
    'EXECUTE'
  ),
  'authenticated callers cannot bypass review-history filtering'
);

select ok(
  position('smispersonnelcertificateledger:viewhistory' in lower((
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_list_personnel_certificates_secure'
  ))) > 0,
  'review history is returned only with its exact permission'
);

select ok(
  position('smispersonnelcertificateledger:view' in lower((
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_list_qualification_catalog_secure'
  ))) > 0,
  'ledger viewers can load enabled catalog options without catalog maintenance access'
);

select ok(
  position('dismissal_reason' in lower((select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_save_personnel_certificate_secure'))) > 0
  and position('新增证件时不能填写消除提醒原因' in (select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_save_personnel_certificate_secure')) > 0,
  'dismissal reason is rejected while adding certificates'
);

select ok(
  exists(select 1 from pg_trigger where tgname='smis_personnel_certificate_item_review' and tgenabled='O'),
  'date changes are captured by review trigger'
);

select ok(
  exists(select 1 from pg_indexes where schemaname='public' and indexname='smis_personnel_certificate_item_due_idx'),
  'active expiration reminders use a partial date index'
);
select ok(
  exists(select 1 from pg_indexes where schemaname='public' and indexname='smis_qualification_catalog_parent_idx'),
  'catalog hierarchy queries use a scoped parent index'
);
select ok(
  (select count(*) from pg_indexes
   where schemaname='public'
     and indexname in (
       'smis_personnel_certificate_employee_fk_idx',
       'smis_certificate_item_catalog_fk_idx',
       'smis_certificate_item_parent_fk_idx',
       'smis_certificate_review_item_fk_idx',
       'smis_certificate_review_parent_fk_idx',
       'smis_certificate_review_tenant_fk_idx',
       'smis_qualification_catalog_parent_fk_idx'
     )) = 7,
  'all qualification foreign keys have covering indexes'
);

select ok(
  exists(select 1 from pg_constraint where conname='smis_personnel_certificate_item_date_check'),
  'certificate effective date cannot precede approval date'
);
select ok(
  exists(select 1 from pg_constraint where conname='smis_personnel_certificate_item_dismissal_check'),
  'dismissal reasons are constrained to training and offboarding'
);

select ok(
  exists(select 1 from public.sys_dict_type where code='smisCertificateCategory')
  and exists(select 1 from public.sys_dict_type where code='smisCertificateReminderDays')
  and exists(select 1 from public.sys_dict_type where code='smisCertificateDismissalReason'),
  'certificate dictionaries are registered'
);

select is(
  (select count(*)::integer from public.sys_dictionary d join public.sys_dict_type t on t.id=d.type_id where t.code='smisCertificateCategory' and d.status='1'),
  5,
  'five certificate categories are configured'
);

select ok(
  exists(select 1 from public.sys_dictionary d join public.sys_dict_type t on t.id=d.type_id where t.code='smisCertificateDismissalReason' and d.value='offboarded')
  and exists(select 1 from public.sys_dictionary d join public.sys_dict_type t on t.id=d.type_id where t.code='smisCertificateDismissalReason' and d.value='trained'),
  'dismissal dictionary contains only supported business reasons'
);

select ok(
  exists(select 1 from public.sys_menu where name='SmisPersonnelCertificateLedger:ViewHistory' and type='button')
  and exists(select 1 from public.sys_menu where name='SmisPersonnelCertificateLedger:Export' and type='button'),
  'certificate history and export permissions are registered'
);

select ok(
  exists(select 1 from public.sys_menu where name='SmisWorkItem:View' and type='button')
  and exists(select 1 from public.sys_menu where name='SmisWorkCategory:View' and type='button')
  and exists(select 1 from public.sys_menu where name='SmisPermittedOperationItem:View' and type='button'),
  'three catalog view permissions are registered'
);

select ok(
  (select meta->>'title' from public.sys_menu where name='SmisSpecialEquipmentPersonnelCertificateLedger')='人员证件台账',
  'unified ledger menu uses consolidated title'
);

select * from finish();
rollback;
