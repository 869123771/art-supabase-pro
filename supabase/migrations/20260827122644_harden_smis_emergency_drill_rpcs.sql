revoke all on function public.smis_list_emergency_drill_plans_secure(integer,integer,text,text,text,text,uuid,text) from public,anon;
revoke all on function public.smis_save_emergency_drill_plan_secure(uuid,jsonb,boolean) from public,anon;
revoke all on function public.smis_delete_emergency_drill_plans_secure(uuid[]) from public,anon;
revoke all on function public.smis_push_emergency_drill_plan_to_record_secure(uuid) from public,anon;
revoke all on function public.smis_list_emergency_drill_records_secure(integer,integer,text,text,date,date,uuid) from public,anon;
revoke all on function public.smis_save_emergency_drill_record_secure(uuid,jsonb,boolean) from public,anon;
revoke all on function public.smis_delete_emergency_drill_records_secure(uuid[]) from public,anon;
revoke all on function public.smis_emergency_drill_report_secure(date,date,uuid) from public,anon;
revoke all on function public.smis_push_emergency_rescue_plan_to_drill_secure(uuid) from public,anon;

grant execute on function public.smis_list_emergency_drill_plans_secure(integer,integer,text,text,text,text,uuid,text) to authenticated,service_role;
grant execute on function public.smis_save_emergency_drill_plan_secure(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.smis_delete_emergency_drill_plans_secure(uuid[]) to authenticated,service_role;
grant execute on function public.smis_push_emergency_drill_plan_to_record_secure(uuid) to authenticated,service_role;
grant execute on function public.smis_list_emergency_drill_records_secure(integer,integer,text,text,date,date,uuid) to authenticated,service_role;
grant execute on function public.smis_save_emergency_drill_record_secure(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.smis_delete_emergency_drill_records_secure(uuid[]) to authenticated,service_role;
grant execute on function public.smis_emergency_drill_report_secure(date,date,uuid) to authenticated,service_role;
grant execute on function public.smis_push_emergency_rescue_plan_to_drill_secure(uuid) to authenticated,service_role;

;
