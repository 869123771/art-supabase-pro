begin;

-- Only the application root owns the shared platform layout. Intermediate
-- folders provide URL segments and menu hierarchy, but must not mount it again.
update public.sys_menu
set component = ''
where app_code = 'smis'
  and type = 'folder'
  and parent_id is not null
  and component is distinct from '';

commit;;
