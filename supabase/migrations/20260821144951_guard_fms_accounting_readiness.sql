-- The readiness read model is shared by the finance workbench and account-set page.
-- It already enforces the current tenant, but must execute with its owner privileges now
-- that authenticated users no longer have direct SELECT on fms_account_set.

alter function public.fms_accounting_readiness(uuid) security definer;
alter function public.fms_accounting_readiness(uuid)
  set search_path = '';

revoke execute on function public.fms_accounting_readiness(uuid)
  from public, anon;
grant execute on function public.fms_accounting_readiness(uuid)
  to authenticated;

;
