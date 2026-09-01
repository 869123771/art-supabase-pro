update public.sys_menu
set meta = coalesce(meta, '{}'::jsonb) - 'roles',
    update_by = 'number-engine',
    update_time = now()
where name = 'DocumentNumberRule';;
