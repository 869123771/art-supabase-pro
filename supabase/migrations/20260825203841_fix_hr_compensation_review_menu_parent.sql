-- Align compensation review with the existing HR Operations menu root.

update public.sys_menu
set parent_id = 'c0de0000-0000-4000-8000-000000000200'::uuid,
    update_by = '624944977@qq.com',
    update_time = now()
where id = 'c0de0000-0000-4000-8000-000000000211'::uuid;


;
