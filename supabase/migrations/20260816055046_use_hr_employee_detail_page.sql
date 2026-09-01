update public.sys_menu
set component = '/hr/personnel/employee-detail',
    update_by = 'migration',
    update_time = now()
where name = 'HrEmployeeDetail'
  and component is distinct from '/hr/personnel/employee-detail';;
