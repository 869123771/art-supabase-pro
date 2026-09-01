alter table public.tms_waybill_event
  drop constraint if exists tms_waybill_event_event_type_check;

alter table public.tms_waybill_event
  add constraint tms_waybill_event_event_type_check
  check (
    event_type in (
      'created',
      'accepted',
      'loading_checked_in',
      'loaded',
      'departed',
      'arrived',
      'unloaded',
      'signed',
      'completed',
      'cancelled',
      'photo_uploaded',
      'status_changed'
    )
  );

insert into public.sys_menu (
  parent_id, name, path, component, meta, sort, type, create_by, update_by
)
select
  parent.id,
  'TmsWaybillDetail',
  'detail/:id',
  '/tms-transportation/waybill-management/detail',
  jsonb_build_object(
    'icon', 'ri:route-line',
    'title', '运单详情',
    'is_hide', true,
    'is_enable', true,
    'keep_alive', false,
    'is_hide_tab', false,
    'active_path', '/tms-transportation/waybill-management/loaded'
  ),
  3,
  'menu',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_menu parent
where parent.name = 'TmsWaybillManagement'
  and not exists (
    select 1 from public.sys_menu existing where existing.name = 'TmsWaybillDetail'
  );

insert into public.sys_role_menu (
  role_id, menu_id, permission, create_by, update_by, tenant_id
)
select
  parent_grant.role_id,
  detail_menu.id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com',
  parent_grant.tenant_id
from public.sys_role_menu parent_grant
join public.sys_menu loaded_menu on loaded_menu.id = parent_grant.menu_id
join public.sys_menu detail_menu on detail_menu.name = 'TmsWaybillDetail'
where loaded_menu.name = 'TmsLoadedWaybillList'
on conflict (role_id, menu_id) do nothing;;
