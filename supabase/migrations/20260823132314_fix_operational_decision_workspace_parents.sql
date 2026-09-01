do $block$
declare
  v_parent_id uuid;
begin
  select id into v_parent_id
  from public.sys_menu
  where name = 'TmsTransportation'
    and type in ('folder', 'menu')
    and app_code = 'tms'
  limit 1;

  if v_parent_id is null then
    raise exception 'TMS transportation parent menu is missing';
  end if;

  update public.sys_menu
  set parent_id = v_parent_id,
      update_by = 'migration',
      update_time = now()
  where name = 'TmsCapacityPlanning'
    and type = 'menu'
    and app_code = 'tms';

  select id into v_parent_id
  from public.sys_menu
  where name = 'FinanceCenter'
    and type in ('folder', 'menu')
    and app_code = 'fms'
  limit 1;

  if v_parent_id is null then
    raise exception 'Finance center parent menu is missing';
  end if;

  update public.sys_menu
  set parent_id = v_parent_id,
      update_by = 'migration',
      update_time = now()
  where name = 'FinanceExceptionCenter'
    and type = 'menu'
    and app_code = 'fms';

  select id into v_parent_id
  from public.sys_menu
  where name = 'HrTalent'
    and type in ('folder', 'menu')
    and app_code = 'hr'
  limit 1;

  if v_parent_id is null then
    raise exception 'HR talent parent menu is missing';
  end if;

  update public.sys_menu
  set parent_id = v_parent_id,
      update_by = 'migration',
      update_time = now()
  where name = 'HrSkillMatrix'
    and type = 'menu'
    and app_code = 'hr';
end;
$block$;;
