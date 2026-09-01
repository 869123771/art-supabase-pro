-- Keep the internal authorization predicate available to authenticated policies and
-- trusted server work only. Browser callers use public.current_is_super().
revoke all on function app_private.is_platform_super() from public;
revoke all on function app_private.is_platform_super() from anon;
grant execute on function app_private.is_platform_super() to authenticated;
grant execute on function app_private.is_platform_super() to service_role;;
