update public.sys_menu
set meta = jsonb_set(
      coalesce(meta, '{}'::jsonb),
      '{icon}',
      to_jsonb('ri:arrow-go-back-line'::text),
      true
    ),
    update_by = '624944977@qq.com',
    update_time = now()
where name = 'SmisToolRequisitionReturn'
  and type = 'menu';;
