begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(42);

select has_table('public', 'smis_violation_record', 'violation record table exists');
select has_table(
  'public',
  'smis_violation_record_employee',
  'violation record employee junction exists'
);
select has_table(
  'public',
  'smis_violation_record_item',
  'violation record standard junction exists'
);
select has_table('public', 'smis_announcement_category', 'announcement category table exists');
select has_table('public', 'smis_announcement', 'announcement table exists');
select has_table(
  'public',
  'smis_announcement_audience_employee',
  'announcement employee audience junction exists'
);
select has_table(
  'public',
  'smis_announcement_audience_organization',
  'announcement organization audience junction exists'
);
select has_table(
  'public',
  'smis_announcement_read_receipt',
  'announcement read receipt ledger exists'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.smis_violation_record'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_violation_record_employee'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_violation_record_item'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_announcement_category'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_announcement'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_announcement_audience_employee'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_announcement_audience_organization'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.smis_announcement_read_receipt'::regclass),
  'all violation and announcement tables enforce RLS'
);

select ok(
  not has_table_privilege('authenticated', 'public.smis_violation_record', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smis_violation_record_employee', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smis_violation_record_item', 'DELETE')
  and not has_table_privilege('authenticated', 'public.smis_announcement_category', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smis_announcement', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smis_announcement_read_receipt', 'DELETE'),
  'authenticated callers cannot bypass secure RPC write boundaries'
);

select has_function(
  'public',
  'smis_list_violation_records_secure',
  array[
    'integer', 'integer', 'text', 'text', 'uuid',
    'timestamp with time zone', 'timestamp with time zone', 'text'
  ],
  'violation record list RPC exists'
);
select has_function(
  'public',
  'smis_save_violation_record_secure',
  array['uuid', 'jsonb'],
  'violation record save RPC exists'
);
select has_function(
  'public',
  'smis_delete_violation_records_secure',
  array['uuid[]'],
  'violation record delete RPC exists'
);
select has_function(
  'public',
  'smis_list_announcement_categories_secure',
  array['integer', 'integer', 'text', 'text', 'text'],
  'announcement category list RPC exists'
);
select has_function(
  'public',
  'smis_save_announcement_category_secure',
  array['uuid', 'jsonb'],
  'announcement category save RPC exists'
);
select has_function(
  'public',
  'smis_delete_announcement_categories_secure',
  array['uuid[]'],
  'announcement category delete RPC exists'
);
select has_function(
  'public',
  'smis_save_announcement_secure',
  array['uuid', 'jsonb'],
  'announcement save RPC exists'
);
select has_function(
  'public',
  'smis_list_announcements_secure',
  array['integer', 'integer', 'text', 'uuid', 'text', 'date', 'date'],
  'announcement list RPC exists'
);
select has_function(
  'public',
  'smis_publish_announcement_secure',
  array['uuid'],
  'announcement publish RPC exists'
);
select has_function(
  'public',
  'smis_withdraw_announcement_secure',
  array['uuid'],
  'announcement withdrawal RPC exists'
);
select has_function(
  'public',
  'smis_delete_announcements_secure',
  array['uuid[]'],
  'announcement delete RPC exists'
);
select has_function(
  'public',
  'smis_mark_announcement_read_secure',
  array['uuid'],
  'announcement read receipt RPC exists'
);
select has_function(
  'public',
  'smis_get_announcement_read_stats_secure',
  array['uuid'],
  'announcement read statistics RPC exists'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.smis_save_violation_record_secure(uuid,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.smis_save_violation_record_secure(uuid,jsonb)',
    'EXECUTE'
  ),
  'only authenticated callers can save violation records'
);
select ok(
  not has_function_privilege(
    'anon',
    'public.smis_mark_announcement_read_secure(uuid)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.smis_mark_announcement_read_secure(uuid)',
    'EXECUTE'
  ),
  'only authenticated callers can record announcement reads'
);

select ok(
  position('smisviolationrecord:copy' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_save_violation_record_secure'
  ))) > 0,
  'violation copy operation enforces the exact copy permission'
);
select ok(
  position('smisviolationrecord:export' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_list_violation_records_secure'
  ))) > 0,
  'violation exports enforce the exact export permission'
);
select ok(
  position('smisviolationannouncement:publish' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_publish_announcement_secure'
  ))) > 0
  and position('lifecycle_status = ''draft''' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_publish_announcement_secure'
  ))) > 0,
  'announcement publishing requires permission and a draft source state'
);
select ok(
  position('smisviolationannouncement:readstats' in lower((
    select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'smis_get_announcement_read_stats_secure'
  ))) > 0,
  'announcement readership statistics enforce the exact permission'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'smis_violation_record_scope_idx'
  ),
  'violation time filtering uses a tenant-scoped index'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'smis_violation_record_employee_employee_idx'
  ),
  'violator filtering uses an employee index'
);
select ok(
  exists (
    select 1 from pg_indexes
    where schemaname = 'public' and indexname = 'smis_announcement_scope_idx'
  ),
  'announcement lifecycle listing uses a tenant-scoped index'
);

select ok(
  exists (select 1 from pg_constraint where conname = 'smis_violation_record_image_check'),
  'violation records cap uploaded images'
);
select ok(
  exists (select 1 from pg_constraint where conname = 'smis_announcement_date_check'),
  'announcement effective date range is validated'
);
select ok(
  exists (select 1 from pg_constraint where conname = 'smis_announcement_receipt_unique'),
  'each user has one read receipt per announcement'
);

select ok(
  exists (select 1 from public.sys_dict_type where code = 'smisAnnouncementStatus')
  and exists (select 1 from public.sys_dict_type where code = 'smisAnnouncementAudienceType')
  and exists (select 1 from public.sys_dict_type where code = 'smisAnnouncementCategoryStatus'),
  'announcement dictionaries are registered'
);
select ok(
  exists (
    select 1 from public.sys_dictionary data
    join public.sys_dict_type type on type.id = data.type_id
    where type.code = 'smisAnnouncementStatus' and data.value = 'draft'
  )
  and exists (
    select 1 from public.sys_dictionary data
    join public.sys_dict_type type on type.id = data.type_id
    where type.code = 'smisAnnouncementStatus' and data.value = 'published'
  )
  and exists (
    select 1 from public.sys_dictionary data
    join public.sys_dict_type type on type.id = data.type_id
    where type.code = 'smisAnnouncementStatus' and data.value = 'withdrawn'
  ),
  'announcement status dictionary covers its managed lifecycle'
);

select ok(
  exists (select 1 from public.sys_menu where name = 'SmisViolationRecord:Copy' and type = 'button'),
  'violation copy permission is registered'
);
select ok(
  exists (select 1 from public.sys_menu where name = 'SmisViolationAnnouncement:Publish' and type = 'button'),
  'announcement publish permission is registered'
);
select ok(
  exists (select 1 from public.sys_menu where name = 'SmisViolationAnnouncement:ReadStats' and type = 'button'),
  'announcement read statistics permission is registered'
);
select ok(
  exists (
    select 1 from public.sys_menu
    where name = 'SmisAnnouncementCategory'
      and path = 'announcement-category'
      and component = '/smis/safety-production/anti-violation-management/announcement-category'
  ),
  'announcement category route is registered'
);
select ok(
  exists (
    select 1 from public.sys_document_number_rule
    where rule_key = 'smis.violation_record'
      and target_table = 'smis_violation_record'
      and target_column = 'record_no'
  ),
  'violation record numbering rule is registered'
);

select * from finish();
rollback;
