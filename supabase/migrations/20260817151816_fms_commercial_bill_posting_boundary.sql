begin;

-- The lifecycle RPC is the only caller allowed to bridge into the private posting queue.
-- It keeps the caller JWT visible to is_platform_super(), uses a fixed search path, and
-- validates every state transition before the private SECURITY DEFINER queue is invoked.
alter function public.act_fms_commercial_bill(uuid, text, jsonb) security definer;

revoke execute on function public.act_fms_commercial_bill(uuid, text, jsonb) from public, anon;
grant execute on function public.act_fms_commercial_bill(uuid, text, jsonb)
  to authenticated, service_role;

commit;;
