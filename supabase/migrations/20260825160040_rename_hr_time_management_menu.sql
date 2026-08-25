update public.sys_menu
set meta = jsonb_set(coalesce(meta, '{}'::jsonb), '{title}', to_jsonb('考勤与工时'::text), true),
    update_by = '624944977@qq.com',
    update_time = now()
where name = 'HrAttendance';
