begin;

update public.sys_menu
set meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object(
      'title', '特种设备人员证件台账',
      'is_hide', false,
      'is_enable', true
    ),
    sort = 4,
    update_time = now()
where name = 'SmisSpecialEquipmentPersonnelCertificateLedger';

update public.sys_menu
set meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object(
      'title', case name
        when 'SmisSpecialEquipmentOperatorCertificateLedger' then '特种设备作业人员证件台账'
        when 'SmisSpecialOperationCertificate' then '特种作业操作证'
        when 'SmisSafetyManagerCertificate' then '安全管理员证'
      end,
      'is_hide', false,
      'is_enable', true
    ),
    sort = case name
      when 'SmisSpecialEquipmentOperatorCertificateLedger' then 5
      when 'SmisSpecialOperationCertificate' then 6
      when 'SmisSafetyManagerCertificate' then 7
    end,
    update_time = now()
where name in (
  'SmisSpecialEquipmentOperatorCertificateLedger',
  'SmisSpecialOperationCertificate',
  'SmisSafetyManagerCertificate'
);

insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort,
  create_by, create_time, update_by, update_time, type, app_code
)
select
  gen_random_uuid(), parent.id, 'SmisRegisteredSafetyEngineerLedger',
  'registered-safety-engineer-ledger',
  '/smis/qualification-training/safety-qualification-management/registered-safety-engineer-ledger',
  jsonb_build_object(
    'icon', '', 'roles', jsonb_build_array(),
    'title', '注册安全工程师台账',
    'is_hide', false, 'is_enable', true
  ),
  8, 'system', now(), 'system', now(), 'menu', parent.app_code
from public.sys_menu parent
where parent.name = 'SmisSafetyQualificationManagement'
  and not exists (
    select 1 from public.sys_menu existing
    where existing.name = 'SmisRegisteredSafetyEngineerLedger'
  );

update public.sys_menu
set sort = 9,
    update_time = now()
where name = 'SmisSafetyQualificationReportAnalysis';

insert into public.sys_role_menu (
  id, role_id, menu_id, tenant_id, permission,
  create_by, create_time, update_by, update_time
)
select
  gen_random_uuid(), parent_assignment.role_id, registered_menu.id,
  parent_assignment.tenant_id, '{}'::jsonb,
  'system', now(), 'system', now()
from public.sys_role_menu parent_assignment
join public.sys_menu parent_menu
  on parent_menu.id = parent_assignment.menu_id
 and parent_menu.name = 'SmisSafetyQualificationManagement'
join public.sys_menu registered_menu
  on registered_menu.name = 'SmisRegisteredSafetyEngineerLedger'
where not exists (
  select 1
  from public.sys_role_menu existing
  where existing.role_id = parent_assignment.role_id
    and existing.menu_id = registered_menu.id
    and existing.tenant_id = parent_assignment.tenant_id
);

commit;;
