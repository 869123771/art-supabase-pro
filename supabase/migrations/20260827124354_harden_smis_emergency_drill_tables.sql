revoke all on table public.smis_emergency_drill_plan from public,anon;
revoke all on table public.smis_emergency_drill_plan_trainee from public,anon,authenticated;
revoke all on table public.smis_emergency_drill_record from public,anon,authenticated;
revoke all on table public.smis_emergency_drill_record_participant from public,anon,authenticated;

grant select on table public.smis_emergency_drill_plan,
  public.smis_emergency_drill_plan_trainee,
  public.smis_emergency_drill_record,
  public.smis_emergency_drill_record_participant to authenticated,service_role;

;
