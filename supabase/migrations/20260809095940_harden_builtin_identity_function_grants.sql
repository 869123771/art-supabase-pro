revoke all on function public.prevent_platform_tenant_change() from public, anon, authenticated;
revoke all on function public.trg_default_system_organization() from public, anon, authenticated;
revoke all on function public.current_is_super() from public, anon;
grant execute on function public.current_is_super() to authenticated;;
