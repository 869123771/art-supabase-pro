-- Supabase's exposed-schema table hook grants broad privileges at creation time.
-- Keep business writes behind the permission-aware SECURITY DEFINER RPC boundary.
revoke all on table public.smis_tool_return from anon;
revoke all on table public.smis_tool_return_item from anon;

revoke insert, update, delete, truncate, references, trigger
  on table public.smis_tool_return from authenticated;
revoke insert, update, delete, truncate, references, trigger
  on table public.smis_tool_return_item from authenticated;

grant select on table public.smis_tool_return to authenticated;
grant select on table public.smis_tool_return_item to authenticated;

;
