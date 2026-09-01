begin;

update public.sys_menu child
set component = '/index/index',
    update_time = now(),
    update_by = '624944977@qq.com'
from public.sys_menu application_root
where child.parent_id = application_root.id
  and application_root.parent_id is null
  and child.type = 'folder'
  and coalesce(child.component, '') = '';

commit;

;
