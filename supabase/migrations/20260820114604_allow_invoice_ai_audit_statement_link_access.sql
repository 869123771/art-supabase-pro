-- The AI audit action is a legitimate consumer of the same field-filtered links.
-- Keep the existing View/Edit paths and also honor the dedicated AI audit button.

create or replace function public.tms_list_invoice_statement_links_secure(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:View', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:Edit', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:AiAudit', null, false
    )
  ) then
    raise exception 'Missing invoice detail permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      app_private.apply_jsonb_amount_access(
        to_jsonb(secured.link_record) - 'tenant_id',
        array['statement_amount']::text[],
        secured.statement_access
      )
      || jsonb_build_object(
        'field_access', jsonb_build_object('statementAmounts', secured.statement_access)
      )
      order by (secured.link_record).period_end, (secured.link_record).id
    )
    from (
      select
        link_row as link_record,
        case
          when link_row.direction = 'output' then app_private.resolve_field_access(
            'tms.customer_statement', 'statementAmounts', customer_statement.created_by_user_id
          )
          else app_private.resolve_field_access(
            'tms.carrier_statement', 'statementAmounts', carrier_statement.created_by_user_id
          )
        end as statement_access
      from public.tms_invoice_detail_link link_row
      left join public.tms_customer_statement customer_statement
        on link_row.direction = 'output'
       and customer_statement.id = link_row.statement_id
       and customer_statement.tenant_id = link_row.tenant_id
      left join public.tms_carrier_statement carrier_statement
        on link_row.direction = 'input'
       and carrier_statement.id = link_row.statement_id
       and carrier_statement.tenant_id = link_row.tenant_id
      where link_row.invoice_id = p_invoice_id
        and (app_private.is_platform_super() or link_row.tenant_id = v_tenant_id)
    ) secured
  ), '[]'::jsonb);
end;
$$;

revoke execute on function public.tms_list_invoice_statement_links_secure(uuid)
  from public, anon;
grant execute on function public.tms_list_invoice_statement_links_secure(uuid)
  to authenticated, service_role;

;
