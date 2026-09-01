-- Secure ledger reports with tenant-scoped field permissions.
-- Ledger rows are aggregate/derived records, so creator override is intentionally disabled.
-- Button permission definitions remain unchanged.

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_ledger_center;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_ledger_center(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.ledger_center', '账簿查询', 'FinanceLedgerCenter', null,
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = null,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (
      p_tenant_id, v_resource_id, 'ledgerAmounts',
      '期初、发生额、累计额、期末余额及原币金额',
      'hidden', 'amount', false, 10, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'voucherReferences',
      '凭证编号、摘要、来源标识及凭证分录数量',
      'hidden', 'none', false, 20, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'auxiliaryDetails',
      '辅助核算项目、币种、数量及计量单位',
      'hidden', 'none', false, 30, '624944977@qq.com', '624944977@qq.com'
    )
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

-- Preserve the report visibility of roles that already own the ledger-center menu.
insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id, role_menu.role_id, resource_row.id, field_row.id,
  'read', '624944977@qq.com', '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'FinanceLedgerCenter'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.ledger_center'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.assert_fms_ledger_center_readable(
  p_account_set_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action(
    'FinanceLedgerCenter', null, null, false
  ) then
    raise exception 'Missing ledger-center menu permission' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.fms_account_set account_set
    where account_set.id = p_account_set_id
      and account_set.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Ledger account set is outside the current tenant'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.fms_subject_balance_report_secure(
  p_account_set_id uuid,
  p_fiscal_year integer,
  p_period_from integer default 1,
  p_period_to integer default 12,
  p_subject_id uuid default null,
  p_hide_zero boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.ledger_center', null);
  v_amount_access text := coalesce(v_access ->> 'ledgerAmounts', 'hidden');
  v_records jsonb := '[]'::jsonb;
  v_row record;
  v_data jsonb;
begin
  perform app_private.assert_fms_ledger_center_readable(p_account_set_id);

  for v_row in
    select *
    from public.fms_subject_balance_report(
      p_account_set_id, p_fiscal_year, p_period_from, p_period_to,
      p_subject_id, p_hide_zero
    )
  loop
    v_data := app_private.apply_jsonb_amount_access(
      to_jsonb(v_row),
      array[
        'opening_debit', 'opening_credit', 'period_debit', 'period_credit',
        'year_to_date_debit', 'year_to_date_credit', 'ending_debit',
        'ending_credit', 'ending_balance'
      ]::text[],
      v_amount_access
    );
    v_data := app_private.apply_jsonb_text_access(
      v_data, array['ending_direction']::text[], v_amount_access
    );
    v_records := v_records || jsonb_build_array(v_data);
  end loop;

  return jsonb_build_object('records', v_records, 'field_access', v_access);
end;
$$;

create or replace function public.fms_general_ledger_report_secure(
  p_account_set_id uuid,
  p_fiscal_year integer,
  p_subject_id uuid,
  p_period_from integer default 1,
  p_period_to integer default 12
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.ledger_center', null);
  v_amount_access text := coalesce(v_access ->> 'ledgerAmounts', 'hidden');
  v_reference_access text := coalesce(v_access ->> 'voucherReferences', 'hidden');
  v_records jsonb := '[]'::jsonb;
  v_row record;
  v_data jsonb;
begin
  perform app_private.assert_fms_ledger_center_readable(p_account_set_id);

  for v_row in
    select *
    from public.fms_general_ledger_report(
      p_account_set_id, p_fiscal_year, p_subject_id, p_period_from, p_period_to
    )
  loop
    v_data := app_private.apply_jsonb_amount_access(
      to_jsonb(v_row),
      array[
        'opening_balance', 'debit_amount', 'credit_amount',
        'year_to_date_debit', 'year_to_date_credit', 'ending_balance'
      ]::text[],
      v_amount_access
    );
    v_data := app_private.apply_jsonb_text_access(
      v_data, array['opening_direction', 'ending_direction']::text[], v_amount_access
    );
    v_data := app_private.apply_jsonb_amount_access(
      v_data, array['voucher_count', 'line_count']::text[], v_reference_access
    );
    v_records := v_records || jsonb_build_array(v_data);
  end loop;

  return jsonb_build_object('records', v_records, 'field_access', v_access);
end;
$$;

create or replace function public.fms_subsidiary_ledger_report_secure(
  p_account_set_id uuid,
  p_fiscal_year integer,
  p_subject_id uuid,
  p_period_from integer default 1,
  p_period_to integer default 12,
  p_auxiliary_type_id uuid default null,
  p_auxiliary_item_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.ledger_center', null);
  v_amount_access text := coalesce(v_access ->> 'ledgerAmounts', 'hidden');
  v_reference_access text := coalesce(v_access ->> 'voucherReferences', 'hidden');
  v_auxiliary_access text := coalesce(v_access ->> 'auxiliaryDetails', 'hidden');
  v_records jsonb := '[]'::jsonb;
  v_row record;
  v_data jsonb;
begin
  perform app_private.assert_fms_ledger_center_readable(p_account_set_id);

  for v_row in
    select *
    from public.fms_subsidiary_ledger_report(
      p_account_set_id, p_fiscal_year, p_subject_id, p_period_from, p_period_to,
      p_auxiliary_type_id, p_auxiliary_item_id
    )
  loop
    v_data := app_private.apply_jsonb_amount_access(
      to_jsonb(v_row),
      array['original_amount', 'debit_amount', 'credit_amount', 'balance_amount']::text[],
      v_amount_access
    );
    v_data := app_private.apply_jsonb_text_access(
      v_data, array['balance_direction']::text[], v_amount_access
    );
    v_data := app_private.apply_jsonb_text_access(
      v_data,
      array[
        'voucher_line_id', 'voucher_id', 'voucher_no', 'voucher_type', 'summary'
      ]::text[],
      v_reference_access
    );
    v_data := app_private.apply_jsonb_text_access(
      v_data, array['auxiliary_display', 'currency_code', 'unit_name']::text[],
      v_auxiliary_access
    );
    v_data := app_private.apply_jsonb_amount_access(
      v_data, array['quantity']::text[], v_auxiliary_access
    );
    v_records := v_records || jsonb_build_array(v_data);
  end loop;

  return jsonb_build_object('records', v_records, 'field_access', v_access);
end;
$$;

revoke execute on function public.fms_subject_balance_report(
  uuid, integer, integer, integer, uuid, boolean
) from public, anon, authenticated;
revoke execute on function public.fms_general_ledger_report(
  uuid, integer, uuid, integer, integer
) from public, anon, authenticated;
revoke execute on function public.fms_subsidiary_ledger_report(
  uuid, integer, uuid, integer, integer, uuid, uuid
) from public, anon, authenticated;

grant execute on function public.fms_subject_balance_report_secure(
  uuid, integer, integer, integer, uuid, boolean
) to authenticated;
grant execute on function public.fms_general_ledger_report_secure(
  uuid, integer, uuid, integer, integer
) to authenticated;
grant execute on function public.fms_subsidiary_ledger_report_secure(
  uuid, integer, uuid, integer, integer, uuid, uuid
) to authenticated;

revoke execute on function public.fms_subject_balance_report_secure(
  uuid, integer, integer, integer, uuid, boolean
) from public, anon;
revoke execute on function public.fms_general_ledger_report_secure(
  uuid, integer, uuid, integer, integer
) from public, anon;
revoke execute on function public.fms_subsidiary_ledger_report_secure(
  uuid, integer, uuid, integer, integer, uuid, uuid
) from public, anon;

revoke execute on function app_private.assert_fms_ledger_center_readable(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog_before_ledger_center(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog(uuid)
  from public, anon, authenticated;

do $$
begin
  if exists (
    select 1
    from public.sys_tenant tenant_row
    where not exists (
      select 1
      from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'fms.ledger_center'
        and resource_row.owner_column is null
    )
  ) then
    raise exception 'Missing fms.ledger_center permission resource';
  end if;

  if exists (
    select 1
    from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.ledger_center'
      and (
        select count(*)
        from public.sys_permission_field field_row
        where field_row.resource_id = resource_row.id
          and field_row.enabled
          and field_row.field_key in (
            'ledgerAmounts', 'voucherReferences', 'auxiliaryDetails'
          )
      ) <> 3
  ) then
    raise exception 'Unexpected fms.ledger_center field catalog';
  end if;
end;
$$;

;
