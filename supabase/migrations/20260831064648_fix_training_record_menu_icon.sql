update public.sys_menu
set meta = jsonb_set(coalesce(meta, '{}'::jsonb), '{icon}', '"ri:file-list-3-line"'::jsonb, true),
    update_time = now()
where name = 'SmisSafetyTrainingRecord'
  and type in ('folder', 'menu');;
