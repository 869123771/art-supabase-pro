begin;

update public.sys_menu child
set component = '',
    update_time = now()
from public.sys_menu application_root
where child.parent_id = application_root.id
  and application_root.parent_id is null
  and child.type = 'folder'
  and child.component = '/index/index';

commit;;
