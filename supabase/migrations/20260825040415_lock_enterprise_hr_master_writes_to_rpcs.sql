-- Master-data writes must cross the validated SECURITY DEFINER RPC boundary.
-- RLS remains enabled as defense in depth, while authenticated clients retain
-- read access for option lists and directory pages.
revoke insert, update, delete on table public.hr_job_family from authenticated;
revoke insert, update, delete on table public.hr_grade from authenticated;
revoke insert, update, delete on table public.hr_job_profile from authenticated;
