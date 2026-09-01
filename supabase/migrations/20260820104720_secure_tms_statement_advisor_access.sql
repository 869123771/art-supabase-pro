-- Finance workbench advice may consume only statement rows whose numeric fields
-- resolve to plaintext read/edit access for the current user. Hidden and masked
-- amounts are excluded so aggregate AI output cannot reveal them indirectly.

create or replace function public.tms_list_customer_statements_receivables_ai_secure(
  p_limit integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(500, greatest(coalesce(p_limit, 300), 1));
begin
  if not app_private.can_execute_business_action('FinanceWorkbench', null, null, false) then
    raise exception 'Missing finance workbench permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'records', coalesce((
      select jsonb_agg(
        to_jsonb(permitted.statement_record) - 'tenant_id'
        order by (permitted.statement_record).period_end,
                 (permitted.statement_record).id
      )
      from (
        select summary_row as statement_record
        from public.tms_customer_statement_summary summary_row
        join public.tms_customer_statement statement_row
          on statement_row.id = summary_row.id
         and statement_row.tenant_id = summary_row.tenant_id
        where summary_row.tenant_id = v_tenant_id
          and summary_row.status not in ('settled', 'voided')
          and app_private.resolve_field_access(
            'tms.customer_statement', 'statementAmounts', statement_row.created_by_user_id
          ) in ('read', 'edit')
          and app_private.resolve_field_access(
            'tms.customer_statement', 'settlementAmounts', statement_row.created_by_user_id
          ) in ('read', 'edit')
        order by summary_row.period_end, summary_row.id
        limit v_limit
      ) permitted
    ), '[]'::jsonb)
  );
end;
$$;

revoke execute on function public.tms_list_customer_statements_receivables_ai_secure(integer)
  from public, anon;
grant execute on function public.tms_list_customer_statements_receivables_ai_secure(integer)
  to authenticated, service_role;

;
