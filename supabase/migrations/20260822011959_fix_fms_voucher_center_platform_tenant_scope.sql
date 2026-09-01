-- Voucher-center reads use the tenant of the selected account set for platform
-- super users. Ordinary users remain bound to their login tenant by the shared
-- resolver introduced in 20260822011209.
do $$
declare
  v_definition text;
  v_rewritten_definition text;
begin
  select pg_get_functiondef(function_row.oid)
    into strict v_definition
  from pg_proc function_row
  join pg_namespace schema_row on schema_row.oid = function_row.pronamespace
  where schema_row.nspname = 'public'
    and function_row.proname = 'fms_list_vouchers_secure'
    and function_row.prokind = 'f';

  v_rewritten_definition := replace(
    replace(
      v_definition,
      'v_tenant_id uuid := app_private.current_user_tenant_id();',
      'v_tenant_id uuid := app_private.resolve_fms_account_set_tenant(p_account_set_id, null);'
    ),
    'v_tenant_id uuid:=app_private.current_user_tenant_id();',
    'v_tenant_id uuid := app_private.resolve_fms_account_set_tenant(p_account_set_id, null);'
  );

  if v_rewritten_definition = v_definition then
    raise exception 'Expected tenant declaration not found in public.fms_list_vouchers_secure';
  end if;

  execute v_rewritten_definition;

  select pg_get_functiondef(function_row.oid)
    into strict v_definition
  from pg_proc function_row
  join pg_namespace schema_row on schema_row.oid = function_row.pronamespace
  where schema_row.nspname = 'public'
    and function_row.proname = 'fms_voucher_summary_secure'
    and function_row.prokind = 'f';

  v_rewritten_definition := replace(
    v_definition,
    'account_set_row.tenant_id = app_private.current_user_tenant_id()',
    'account_set_row.tenant_id = app_private.resolve_fms_account_set_tenant(p_account_set_id, null)'
  );

  if v_rewritten_definition = v_definition then
    raise exception 'Expected tenant comparison not found in public.fms_voucher_summary_secure';
  end if;

  execute v_rewritten_definition;
end;
$$;

;
