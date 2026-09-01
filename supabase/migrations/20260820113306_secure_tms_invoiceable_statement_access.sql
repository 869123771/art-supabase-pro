-- Close downstream invoice read paths that otherwise expose settlement amounts.
-- Invoice creation only receives plaintext statement candidates, while invoice
-- detail links apply the effective owner/user/role field access per statement.

create or replace function public.tms_list_invoiceable_statements_secure(
  p_direction text,
  p_counterparty_id uuid,
  p_from integer default 0,
  p_to integer default 9,
  p_keyword text default null,
  p_include_fully_invoiced boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
begin
  if p_direction not in ('output', 'input') or p_counterparty_id is null then
    raise exception 'Invalid invoiceable statement scope';
  end if;
  if not (
    app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:Add', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:Edit', null, false
    )
  ) then
    raise exception 'Missing invoice statement selection permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    500,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  return (
    with filtered as materialized (
      select
        invoiceable_row as statement_record,
        case
          when p_direction = 'output' then app_private.resolve_field_access(
            'tms.customer_statement', 'statementAmounts', customer_statement.created_by_user_id
          )
          else app_private.resolve_field_access(
            'tms.carrier_statement', 'statementAmounts', carrier_statement.created_by_user_id
          )
        end as statement_access,
        case
          when p_direction = 'output' then app_private.resolve_field_access(
            'tms.customer_statement', 'settlementAmounts', customer_statement.created_by_user_id
          )
          else app_private.resolve_field_access(
            'tms.carrier_statement', 'settlementAmounts', carrier_statement.created_by_user_id
          )
        end as settlement_access
      from public.tms_invoiceable_statement invoiceable_row
      left join public.tms_customer_statement customer_statement
        on p_direction = 'output'
       and customer_statement.id = invoiceable_row.statement_id
       and customer_statement.tenant_id = invoiceable_row.tenant_id
      left join public.tms_carrier_statement carrier_statement
        on p_direction = 'input'
       and carrier_statement.id = invoiceable_row.statement_id
       and carrier_statement.tenant_id = invoiceable_row.tenant_id
      where invoiceable_row.direction = p_direction
        and invoiceable_row.counterparty_id = p_counterparty_id
        and (app_private.is_platform_super() or invoiceable_row.tenant_id = v_tenant_id)
        and (
          coalesce(p_include_fully_invoiced, false)
          or invoiceable_row.uninvoiced_amount > 0
        )
        and (
          nullif(btrim(p_keyword), '') is null
          or invoiceable_row.statement_no ilike '%' || btrim(p_keyword) || '%'
          or invoiceable_row.counterparty_name ilike '%' || btrim(p_keyword) || '%'
        )
        and case
          when p_direction = 'output' then app_private.resolve_field_access(
            'tms.customer_statement', 'statementAmounts', customer_statement.created_by_user_id
          )
          else app_private.resolve_field_access(
            'tms.carrier_statement', 'statementAmounts', carrier_statement.created_by_user_id
          )
        end in ('read', 'edit')
        and case
          when p_direction = 'output' then app_private.resolve_field_access(
            'tms.customer_statement', 'settlementAmounts', customer_statement.created_by_user_id
          )
          else app_private.resolve_field_access(
            'tms.carrier_statement', 'settlementAmounts', carrier_statement.created_by_user_id
          )
        end in ('read', 'edit')
    ), paged as (
      select filtered.*
      from filtered
      order by (filtered.statement_record).period_end,
               (filtered.statement_record).statement_id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          (to_jsonb(paged.statement_record) - 'tenant_id')
          || jsonb_build_object(
            'field_access', jsonb_build_object(
              'statementAmounts', paged.statement_access,
              'settlementAmounts', paged.settlement_access
            )
          )
          order by (paged.statement_record).period_end,
                   (paged.statement_record).statement_id
        )
        from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    )
  );
end;
$$;

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

-- Include invoice progress in the already field-filtered AI statement payload so
-- the Edge Function never needs to read the invoiceable view directly.
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
        (to_jsonb(permitted.statement_record) - 'tenant_id')
        || jsonb_build_object(
          'invoiced_amount', permitted.invoiced_amount,
          'uninvoiced_amount', permitted.uninvoiced_amount
        )
        order by (permitted.statement_record).period_end,
                 (permitted.statement_record).id
      )
      from (
        select
          summary_row as statement_record,
          coalesce(invoiceable_row.invoiced_amount, 0::numeric) as invoiced_amount,
          coalesce(invoiceable_row.uninvoiced_amount, 0::numeric) as uninvoiced_amount
        from public.tms_customer_statement_summary summary_row
        join public.tms_customer_statement statement_row
          on statement_row.id = summary_row.id
         and statement_row.tenant_id = summary_row.tenant_id
        left join public.tms_invoiceable_statement invoiceable_row
          on invoiceable_row.direction = 'output'
         and invoiceable_row.statement_id = summary_row.id
         and invoiceable_row.tenant_id = summary_row.tenant_id
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

revoke all on table
  public.tms_invoiceable_statement,
  public.tms_invoice_detail_link
from public, anon, authenticated;

revoke execute on function public.tms_list_invoiceable_statements_secure(
  text, uuid, integer, integer, text, boolean
) from public, anon;
revoke execute on function public.tms_list_invoice_statement_links_secure(uuid)
  from public, anon;
revoke execute on function public.tms_list_customer_statements_receivables_ai_secure(integer)
  from public, anon;

grant execute on function public.tms_list_invoiceable_statements_secure(
  text, uuid, integer, integer, text, boolean
) to authenticated, service_role;
grant execute on function public.tms_list_invoice_statement_links_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_list_customer_statements_receivables_ai_secure(integer)
  to authenticated, service_role;

;
