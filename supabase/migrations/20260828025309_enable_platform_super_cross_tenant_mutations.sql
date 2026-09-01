create or replace function app_private.resolve_mutation_tenant_id(p_target_tenant_id uuid default null)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor_tenant_id uuid := app_private.auth_user_tenant_id();
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护租户数据' using errcode = '42501';
  end if;
  if v_actor_tenant_id is null then
    raise exception '当前账号未绑定有效租户' using errcode = '42501';
  end if;

  if app_private.is_platform_super() and p_target_tenant_id is not null then
    return p_target_tenant_id;
  end if;

  return v_actor_tenant_id;
end;
$$;

revoke all on function app_private.resolve_mutation_tenant_id(uuid) from public, anon;
grant execute on function app_private.resolve_mutation_tenant_id(uuid) to authenticated, service_role;

comment on function app_private.resolve_mutation_tenant_id(uuid) is
  'Uses the authenticated actor tenant for creates and ordinary users; platform super edits use the existing target row tenant.';

do $$
declare
  v_mapping record;
  v_function_oid oid;
  v_definition text;
  v_replacement text;
  v_changed integer := 0;
begin
  for v_mapping in
    select *
    from (values
      ('hr_save_personnel_change_secure', 'public.hr_employee',
        'nullif(p_payload->>''employee_id'','''')::uuid'),
      ('smis_save_emergency_drill_plan_secure', 'public.smis_emergency_drill_plan', 'p_id'),
      ('smis_save_emergency_drill_record_secure', 'public.smis_emergency_drill_record', 'p_id'),
      ('smis_save_emergency_rescue_plan_secure', 'public.smis_emergency_rescue_plan', 'p_id'),
      ('smis_save_equipment_category_secure', 'public.smis_equipment_category', 'p_id'),
      ('smis_save_equipment_depreciation_secure', 'public.smis_equipment_depreciation', 'p_id'),
      ('smis_save_equipment_inspection_secure', 'public.smis_equipment_inspection', 'p_id'),
      ('smis_save_equipment_ledger_secure', 'public.smis_equipment', 'p_id'),
      ('smis_save_equipment_reminder_secure', 'public.smis_equipment', 'p_equipment_id'),
      ('smis_save_hazard_source_secure', 'public.smis_hazard_source', 'p_id'),
      ('smis_save_leave_information_secure', 'public.hr_leave_request', 'p_id'),
      ('smis_save_site_secure', 'public.smis_site', 'p_id'),
      ('smis_save_statutory_holiday_secure', 'public.smis_statutory_holiday', 'p_id'),
      ('smis_save_supplier_secure', 'public.vehicle_supplier', 'p_id'),
      ('tms_save_waybill_cost_secure', 'public.tms_waybill_cost', 'p_id'),
      ('tms_delete_waybill_cost_secure', 'public.tms_waybill_cost', 'p_id')
    ) as mapping(function_name, target_table, target_id_expression)
  loop
    select procedure.oid into v_function_oid
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = v_mapping.function_name;

    if v_function_oid is null then
      raise exception 'Required mutation RPC % was not found', v_mapping.function_name;
    end if;

    v_definition := pg_get_functiondef(v_function_oid);
    v_replacement := format(
      'app_private.resolve_mutation_tenant_id((select target.tenant_id from %s target where target.id = %s))',
      v_mapping.target_table,
      v_mapping.target_id_expression
    );
    v_definition := regexp_replace(
      v_definition,
      'app_private\.current_user_tenant_id\(\)',
      v_replacement
    );

    if v_definition not ilike '%resolve_mutation_tenant_id%' then
      raise exception 'Mutation tenant resolver was not applied to %', v_mapping.function_name;
    end if;

    execute v_definition;
    v_changed := v_changed + 1;
  end loop;

  if v_changed <> 16 then
    raise exception 'Expected 16 target-aware mutation RPCs, updated %', v_changed;
  end if;
end;
$$;

do $$
declare
  v_function_oid oid;
  v_function_name text;
  v_definition text;
  v_changed integer := 0;
begin
  foreach v_function_name in array array[
    'smis_delete_emergency_drill_plans_secure',
    'smis_delete_emergency_drill_records_secure',
    'smis_delete_emergency_rescue_plans_secure',
    'smis_delete_equipment_categories_secure',
    'smis_delete_equipment_depreciations_secure',
    'smis_delete_equipment_inspections_secure',
    'smis_delete_equipment_ledger_secure',
    'smis_delete_hazard_sources_secure',
    'smis_delete_leave_information_secure',
    'smis_delete_sites_secure',
    'smis_delete_statutory_holidays_secure',
    'smis_delete_suppliers_secure',
    'smis_set_emergency_rescue_plan_validity_secure'
  ]
  loop
    select procedure.oid into v_function_oid
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = v_function_name;

    if v_function_oid is null then
      raise exception 'Required batch mutation RPC % was not found', v_function_name;
    end if;

    v_definition := replace(
      pg_get_functiondef(v_function_oid),
      'app_private.current_user_tenant_id()',
      'app_private.auth_user_tenant_id()'
    );
    v_definition := regexp_replace(
      v_definition,
      '(([a-zA-Z_][a-zA-Z0-9_]*\.)?tenant_id)\s*=\s*(v_tenant_id|v_tenant)',
      '(app_private.is_platform_super() or \1 = \3)',
      'gi'
    );
    v_definition := regexp_replace(
      v_definition,
      '(v_tenant_id|v_tenant)\s*=\s*(([a-zA-Z_][a-zA-Z0-9_]*\.)?tenant_id)',
      '(app_private.is_platform_super() or \2 = \1)',
      'gi'
    );
    v_definition := regexp_replace(
      v_definition,
      '(([a-zA-Z_][a-zA-Z0-9_]*\.)?tenant_id)\s*=\s*app_private\.auth_user_tenant_id\(\)',
      '(app_private.is_platform_super() or \1 = app_private.auth_user_tenant_id())',
      'gi'
    );

    if v_definition not ilike '%app_private.is_platform_super()%' then
      raise exception 'Platform mutation override was not applied to %', v_function_name;
    end if;

    execute v_definition;
    v_changed := v_changed + 1;
  end loop;

  if v_changed <> 13 then
    raise exception 'Expected 13 batch mutation RPCs, updated %', v_changed;
  end if;
end;
$$;

;
