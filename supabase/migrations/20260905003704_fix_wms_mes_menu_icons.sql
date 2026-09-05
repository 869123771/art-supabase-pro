begin;

-- These application roots previously referenced icon names that do not exist in
-- Remix Icon. Keep the correction path-based so the migration remains portable.
update public.sys_menu
set meta = jsonb_set(coalesce(meta, '{}'::jsonb), '{icon}', '"ri:store-3-line"'::jsonb, true),
    update_by = 'migration',
    update_time = now()
where app_code = 'wms'
  and path = '/wms'
  and parent_id is null;

update public.sys_menu
set meta = jsonb_set(coalesce(meta, '{}'::jsonb), '{icon}', '"ri:tools-line"'::jsonb, true),
    update_by = 'migration',
    update_time = now()
where app_code = 'mes'
  and path = '/mes'
  and parent_id is null;

commit;
