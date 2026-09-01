-- The cargo-operation and execution-record SELECT policies invoke this internal
-- predicate. PostgreSQL still requires the policy role to have EXECUTE on the
-- predicate even though the function is not exposed as a public Data API RPC.
revoke all on function app_private.can_access_waybill_cargo_operation(uuid)
  from public, anon;

grant execute on function app_private.can_access_waybill_cargo_operation(uuid)
  to authenticated, service_role;;
