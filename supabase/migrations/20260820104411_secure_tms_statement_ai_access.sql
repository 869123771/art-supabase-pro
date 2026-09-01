-- Let authenticated AI readers reuse the same allocatable-statement boundary.
-- A null counterparty means "all permitted counterparties" and is used only by
-- the matching assistants. Per-record field access still has to resolve to a
-- numeric read/edit level before a row is returned.

create or replace function public.tms_list_customer_statement_allocatable_secure(
  p_customer_id uuid,
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(
    500,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
begin
  if not (
    app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:Add', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:Allocate', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:Import', null, false
    )
  ) then
    raise exception 'Missing customer receipt allocation permission' using errcode = '42501';
  end if;

  return (
    with filtered as materialized (
      select allocatable_row
      from public.tms_customer_statement_allocatable allocatable_row
      join public.tms_customer_statement statement_row
        on statement_row.id = allocatable_row.id
       and statement_row.tenant_id = allocatable_row.tenant_id
      where allocatable_row.tenant_id = v_tenant_id
        and (p_customer_id is null or allocatable_row.customer_id = p_customer_id)
        and app_private.resolve_field_access(
          'tms.customer_statement', 'statementAmounts', statement_row.created_by_user_id
        ) in ('read', 'edit')
        and app_private.resolve_field_access(
          'tms.customer_statement', 'settlementAmounts', statement_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          nullif(btrim(p_keyword), '') is null
          or allocatable_row.statement_no ilike '%' || btrim(p_keyword) || '%'
          or allocatable_row.customer_name ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.allocatable_row
      from filtered
      order by (filtered.allocatable_row).period_end,
               (filtered.allocatable_row).create_time,
               (filtered.allocatable_row).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          to_jsonb(paged.allocatable_row) - 'tenant_id'
          order by (paged.allocatable_row).period_end,
                   (paged.allocatable_row).create_time,
                   (paged.allocatable_row).id
        ) from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    )
  );
end;
$$;

create or replace function public.tms_list_carrier_statement_allocatable_secure(
  p_carrier_id uuid,
  p_keyword text default null,
  p_from integer default 0,
  p_to integer default 9
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer := least(
    500,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
begin
  if not (
    app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:CreatePayment', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:Allocate', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCashTransaction', 'FinanceCashTransaction:Import', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCarrierPaymentApplication', 'FinanceCarrierPaymentApplication:Add', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceCarrierPaymentApplication', 'FinanceCarrierPaymentApplication:Edit', null, false
    )
  ) then
    raise exception 'Missing carrier payment allocation permission' using errcode = '42501';
  end if;

  return (
    with filtered as materialized (
      select allocatable_row
      from public.tms_carrier_statement_allocatable allocatable_row
      join public.tms_carrier_statement statement_row
        on statement_row.id = allocatable_row.id
       and statement_row.tenant_id = allocatable_row.tenant_id
      where allocatable_row.tenant_id = v_tenant_id
        and (p_carrier_id is null or allocatable_row.carrier_id = p_carrier_id)
        and app_private.resolve_field_access(
          'tms.carrier_statement', 'statementAmounts', statement_row.created_by_user_id
        ) in ('read', 'edit')
        and app_private.resolve_field_access(
          'tms.carrier_statement', 'settlementAmounts', statement_row.created_by_user_id
        ) in ('read', 'edit')
        and (
          nullif(btrim(p_keyword), '') is null
          or allocatable_row.statement_no ilike '%' || btrim(p_keyword) || '%'
          or allocatable_row.carrier_name ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.allocatable_row
      from filtered
      order by (filtered.allocatable_row).period_end,
               (filtered.allocatable_row).create_time,
               (filtered.allocatable_row).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          to_jsonb(paged.allocatable_row) - 'tenant_id'
          order by (paged.allocatable_row).period_end,
                   (paged.allocatable_row).create_time,
                   (paged.allocatable_row).id
        ) from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    )
  );
end;
$$;

;
