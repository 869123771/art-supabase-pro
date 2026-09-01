revoke all on function public.delete_fms_auxiliary_type(uuid) from public;
revoke all on function public.delete_fms_auxiliary_type(uuid) from anon;
grant execute on function public.delete_fms_auxiliary_type(uuid) to authenticated;;
