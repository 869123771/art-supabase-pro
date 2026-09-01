-- Notification reminder RPCs are SECURITY DEFINER functions. PostgreSQL grants
-- EXECUTE to PUBLIC by default, so every browser-facing entry point must opt in
-- authenticated users explicitly and keep anonymous callers out.

revoke all on function public.get_notification_reminder_workspace(uuid)
  from public, anon;
revoke all on function public.save_notification_rule(jsonb)
  from public, anon;
revoke all on function public.delete_notification_rule(uuid)
  from public, anon;
revoke all on function public.save_notification_channel_config(uuid, text, text, boolean, jsonb, jsonb)
  from public, anon;
revoke all on function public.test_notification_channel(uuid, text)
  from public, anon;
revoke all on function public.run_notification_reminders_now(uuid)
  from public, anon;
revoke all on function public.get_notification_dispatch_scope()
  from public, anon;

grant execute on function public.get_notification_reminder_workspace(uuid)
  to authenticated;
grant execute on function public.save_notification_rule(jsonb)
  to authenticated;
grant execute on function public.delete_notification_rule(uuid)
  to authenticated;
grant execute on function public.save_notification_channel_config(uuid, text, text, boolean, jsonb, jsonb)
  to authenticated;
grant execute on function public.test_notification_channel(uuid, text)
  to authenticated;
grant execute on function public.run_notification_reminders_now(uuid)
  to authenticated;
grant execute on function public.get_notification_dispatch_scope()
  to authenticated;

;
