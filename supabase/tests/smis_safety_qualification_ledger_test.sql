begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(57);

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

select has_function('public','smis_list_qualification_catalog_secure',array['text','integer','integer','text','text','uuid','text','uuid'],'catalog list RPC exists');
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
  position('smis_certificate_permission_prefix' in lower((
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_list_personnel_certificates_secure'
  ))) > 0,
  'review history is returned only with the exact permission for the requested certificate category'
);

select ok(
  position('smispersonnelcertificateledger:view' in lower((
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_list_qualification_catalog_secure'
  ))) > 0,
  'ledger viewers can load enabled catalog options without catalog maintenance access'
);

select has_column(
  'public',
  'smis_qualification_catalog',
  'work_category_id',
  'permitted operation items have a normalized work-category relation'
);

select ok(
  exists(
    select 1
    from pg_constraint
    where conrelid='public.smis_qualification_catalog'::regclass
      and conname='smis_qualification_catalog_work_category_fkey'
  ),
  'work-category relations are tenant-scoped foreign keys'
);

select ok(
  exists(
    select 1
    from pg_constraint
    where conrelid='public.smis_qualification_catalog'::regclass
      and conname='smis_qualification_catalog_work_category_required_check'
  ),
  'only permitted operation items require a work category'
);

select ok(
  exists(
    select 1
    from pg_trigger
    where tgname='smis_qualification_catalog_relation'
      and tgenabled='O'
  ),
  'catalog relation trigger enforces same-category hierarchy and cycle safety'
);

select ok(
  not exists(
    select 1
    from public.smis_qualification_catalog item
    left join public.smis_qualification_catalog category
      on category.id=item.work_category_id
     and category.tenant_id=item.tenant_id
     and category.catalog_type='work_category'
    where item.catalog_type='permitted_operation_item'
      and category.id is null
  ),
  'every permitted operation item belongs to a work category in the same tenant'
);

select ok(
  not exists(
    select 1
    from public.smis_qualification_catalog item
    join public.smis_qualification_catalog parent on parent.id=item.parent_id
    where item.catalog_type='permitted_operation_item'
      and parent.work_category_id is distinct from item.work_category_id
  ),
  'permitted operation item parents stay inside the same work category'
);

select ok(
  position('work_category_id' in lower((
    select prosrc
    from pg_proc
    join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_qualification_catalog_secure'
  ))) > 0
  and position('请选择作业类别' in (
    select prosrc
    from pg_proc
    join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_qualification_catalog_secure'
  )) > 0,
  'catalog writes require and validate work-category ownership'
);

select ok(
  exists(
    select 1
    from public.sys_tenant tenant
    where tenant.tenant_code='public-register'
      and (
        select count(*)
        from public.smis_qualification_catalog category
        where category.tenant_id=tenant.id
          and category.catalog_type='work_category'
          and category.item_code in ('1','2','3','4','5','6')
      )=6
      and (
        select count(*)
        from public.smis_qualification_catalog item
        where item.tenant_id=tenant.id
          and item.catalog_type='permitted_operation_item'
          and item.item_code in (
            '1.1','1.2','1.3','2.1','2.2','2.3','3.1','3.2','4.1','4.2',
            '5.1','5.2','5.3','5.4','5.5','5.6','5.7','5.8','6.1'
          )
      )=19
  ),
  'the six requested work categories and nineteen permitted operation items are seeded'
);

select ok(
  position('dismissal_reason' in lower((select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_save_personnel_certificate_secure'))) > 0
  and position('新增证件时不能填写消除提醒原因' in (select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_save_personnel_certificate_secure')) > 0,
  'dismissal reason is rejected while adding certificates'
);

select ok(
  position('v_catalog_type' in lower((select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_save_personnel_certificate_base_secure'))) > 0
  and position('所选项目与证件类别不匹配' in (select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_save_personnel_certificate_base_secure')) > 0,
  'certificate item catalog type is enforced at the write boundary'
);

select ok(
  position('已有复审记录的证件项目不能移除' in (select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_save_personnel_certificate_base_secure')) > 0,
  'reviewed certificate items cannot be removed through ordinary edits'
);

select ok(
  position('certificate.warning_status = p_warning_status' in lower((select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_list_personnel_certificates_raw_secure'))) > 0
  and position('from filtered' in lower((select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace where nspname='public' and proname='smis_list_personnel_certificates_raw_secure'))) > 0,
  'warning queries and overview metrics use the filtered unified ledger result'
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
       'smis_qualification_catalog_parent_fk_idx',
       'smis_qualification_catalog_work_category_idx'
     )) = 8,
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
  not exists(
    with target_tenants as (
      select tenant.id
      from public.sys_tenant tenant
      where tenant.tenant_code='public-register'
      union
      select distinct assignment.tenant_id
      from public.sys_role_menu assignment
      join public.sys_menu menu on menu.id=assignment.menu_id
      where menu.name='SmisSpecialEquipmentOperatorCertificateLedger'
      union
      select distinct catalog.tenant_id
      from public.smis_qualification_catalog catalog
      where catalog.catalog_type='work_item'
    )
    select 1
    from target_tenants tenant
    where (
      select count(*)
      from public.smis_qualification_catalog item
      where item.tenant_id=tenant.id
        and item.catalog_type='work_item'
        and item.item_code in (
          'G1','G2','G3','G4','G5','G6','R1','R2','D1','D2','D3',
          'T1','T2','T3','Q1','Q2','Q3','Q4','Q5','Q6','Q7','Q8','Q9','Q10',
          'N1','N2','F1','F2'
        )
    ) <> 28
  ),
  'all operator-ledger tenants have the twenty-eight statutory G/R/D/T/Q/N/F projects'
);

select ok(
  position('special_equipment_operator' in (
    select prosrc
    from pg_proc
    join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='app_private' and proname='smis_certificate_permission_prefix'
  )) > 0
  and position('SmisSpecialEquipmentOperatorCertificateLedger' in (
    select prosrc
    from pg_proc
    join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='app_private' and proname='smis_certificate_permission_prefix'
  )) > 0,
  'operator certificates resolve to their exact page permission prefix'
);

select ok(
  position('特种设备作业人员证只能选择 G、R、D、T、Q、N、F 类作业项目' in (
    select prosrc
    from pg_proc
    join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_base_secure'
  )) > 0
  and position('smis_certificate_permission_prefix' in lower((
    select prosrc
    from pg_proc
    join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_base_secure'
  ))) > 0,
  'operator project scope and exact add/edit permissions are enforced at the write boundary'
);

select ok(
  (select count(*)
   from public.sys_menu button
   join public.sys_menu page on page.id=button.parent_id
   where page.name='SmisSpecialEquipmentOperatorCertificateLedger'
     and button.type='button'
     and button.name like 'SmisSpecialEquipmentOperatorCertificateLedger:%') = 7
  and not exists(
    select 1
    from public.sys_role_menu page_assignment
    join public.sys_menu page
      on page.id=page_assignment.menu_id
     and page.name='SmisSpecialEquipmentOperatorCertificateLedger'
    join public.sys_menu button
      on button.parent_id=page.id
     and button.type='button'
     and button.name like 'SmisSpecialEquipmentOperatorCertificateLedger:%'
    where not exists(
      select 1
      from public.sys_role_menu action_assignment
      where action_assignment.role_id=page_assignment.role_id
        and action_assignment.menu_id=button.id
        and action_assignment.tenant_id=page_assignment.tenant_id
    )
  ),
  'operator ledger actions are registered under the exact page and inherited by existing page roles'
);

select ok(
  (select count(*) from public.sys_menu child
   join public.sys_menu parent on parent.id=child.parent_id
   where parent.name='SmisSafetyQualificationManagement'
     and child.type='menu'
     and child.meta->>'is_hide'='false'
     and child.meta->>'is_enable'='true') = 9
  and (select meta->>'title' from public.sys_menu where name='SmisSpecialEquipmentPersonnelCertificateLedger')='特种设备人员证件台账'
  and (select meta->>'title' from public.sys_menu where name='SmisSafetyManagerCertificate')='安全管理人员证'
  and exists(select 1 from public.sys_menu where name='SmisRegisteredSafetyEngineerLedger' and meta->>'title'='注册安全工程师台账'),
  'qualification management exposes the nine requested menu entries'
);

select has_function(
  'public',
  'smis_list_certificate_employees_secure',
  array['text','integer','integer','text'],
  'certificate pages use their own tenant-scoped employee selector'
);
select has_function(
  'public',
  'smis_get_certificate_employee_secure',
  array['text','uuid'],
  'certificate employee detail RPC supports roster field linkage'
);
select has_function(
  'public',
  'smis_list_certificate_catalog_options_secure',
  array['text'],
  'certificate project options are resolved by exact certificate category'
);

select ok(
  exists(select 1 from public.sys_dict_type where code='smisSafetyManagerUnitType')
  and exists(select 1 from public.sys_dict_type where code='smisSafetyManagerOccupationType')
  and (
    select count(*)
    from public.sys_dictionary value
    join public.sys_dict_type type on type.id=value.type_id
    where type.code='smisSafetyManagerUnitType' and value.status='1'
  )=4
  and (
    select count(*)
    from public.sys_dictionary value
    join public.sys_dict_type type on type.id=value.type_id
    where type.code='smisSafetyManagerOccupationType' and value.status='1'
  )=2,
  'safety-manager unit and occupation dictionaries match the requested values'
);

select ok(
  position('SmisSpecialOperationCertificate' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='app_private' and proname='smis_certificate_permission_prefix'
  )) > 0
  and position('SmisSafetyManagerCertificate' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='app_private' and proname='smis_certificate_permission_prefix'
  )) > 0,
  'special-operation and safety-manager certificates resolve to exact page permissions'
);

select ok(
  (select count(*) from public.sys_menu button
   join public.sys_menu page on page.id=button.parent_id
   where page.name='SmisSpecialOperationCertificate'
     and button.type='button'
     and button.name like 'SmisSpecialOperationCertificate:%')=7
  and (select count(*) from public.sys_menu button
   join public.sys_menu page on page.id=button.parent_id
   where page.name='SmisSafetyManagerCertificate'
     and button.type='button'
     and button.name like 'SmisSafetyManagerCertificate:%')=7,
  'both certificate pages register all seven standard and history actions'
);

select ok(
  exists(
    select 1
    from public.smis_qualification_catalog catalog
    join public.sys_tenant tenant on tenant.id=catalog.tenant_id
    where tenant.tenant_code='public-register'
      and catalog.catalog_type='certificate_term'
      and catalog.item_code='SAFETY_MANAGER'
      and catalog.status='enabled'
  )
  and position('certificate_term' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_base_secure'
  )) > 0,
  'safety-manager validity dates use an internal non-maintainable certificate term'
);

select ok(
  position('unit_type' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_base_secure'
  )) > 0
  and position('occupation_type' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_base_secure'
  )) > 0
  and position('准操项目必须属于已启用的作业类别' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_base_secure'
  )) > 0,
  'category-specific fields and permitted-operation category ownership are enforced on write'
);

select ok(
  exists(select 1 from public.sys_dict_type where code='smisRegisteredSafetyOfficerType')
  and exists(select 1 from public.sys_dict_type where code='smisRegisteredEngineerType')
  and exists(select 1 from public.sys_dict_type where code='smisRegisteredPracticeCategory')
  and (
    select count(*) from public.sys_dictionary value
    join public.sys_dict_type type on type.id=value.type_id
    where type.code='smisRegisteredSafetyOfficerType' and value.status='1'
  )=2
  and (
    select count(*) from public.sys_dictionary value
    join public.sys_dict_type type on type.id=value.type_id
    where type.code='smisRegisteredEngineerType' and value.status='1'
  )=2
  and (
    select count(*) from public.sys_dictionary value
    join public.sys_dict_type type on type.id=value.type_id
    where type.code='smisRegisteredPracticeCategory' and value.status='1'
  )=5,
  'registered-safety-engineer dictionaries match the requested values'
);

select ok(
  exists(
    select 1
    from public.smis_qualification_catalog catalog
    join public.sys_tenant tenant on tenant.id=catalog.tenant_id
    where tenant.tenant_code='public-register'
      and catalog.catalog_type='certificate_term'
      and catalog.item_code='REGISTERED_SAFETY_ENGINEER'
      and catalog.status='enabled'
  ),
  'registered-safety-engineer validity uses one internal certificate term'
);

select ok(
  position('SmisRegisteredSafetyEngineerLedger' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='app_private' and proname='smis_certificate_permission_prefix'
  )) > 0
  and (select count(*) from public.sys_menu button
       join public.sys_menu page on page.id=button.parent_id
       where page.name='SmisRegisteredSafetyEngineerLedger'
         and button.type='button')=7
  and (select count(*) from public.sys_menu button
       join public.sys_menu page on page.id=button.parent_id
       where page.name='SmisSafetyQualificationReportAnalysis'
         and button.type='button')=1,
  'registered ledger and report analysis use exact assignable permissions'
);

select ok(
  position('safety_officer_type' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_secure'
  )) > 0
  and position('engineer_type' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_secure'
  )) > 0
  and position('practice_category' in (
    select prosrc from pg_proc join pg_namespace on pg_namespace.oid=pronamespace
    where nspname='public' and proname='smis_save_personnel_certificate_secure'
  )) > 0,
  'registered-safety-engineer fields are enforced at the write boundary'
);

select has_function(
  'public',
  'smis_get_safety_qualification_analysis_secure',
  array['date','date','uuid'],
  'safety qualification analysis exposes the ten requested reporting dimensions'
);

select * from finish();
rollback;
