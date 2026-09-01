revoke all on function public.tms_list_driver_employee_options_secure(integer, integer, text)
  from public, anon;

grant execute on function public.tms_list_driver_employee_options_secure(integer, integer, text)
  to authenticated, service_role;

;
