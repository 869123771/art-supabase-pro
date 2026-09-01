-- Secure financial-statement amounts and configuration rules with tenant field permissions.
-- Button permission definitions remain unchanged. Cash-flow allocations stay in voucher scope.

alter table public.fms_financial_statement_item
  add column if not exists created_by_user_id uuid;

update public.fms_financial_statement_item item_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = item_row.tenant_id
    and lower(user_row.user_email) = lower(item_row.create_by)
  order by user_row.create_time, user_row.id
  limit 1
)
where item_row.created_by_user_id is null
  and nullif(btrim(coalesce(item_row.create_by, '')), '') is not null;

create index if not exists fms_financial_statement_item_tenant_creator_idx
  on public.fms_financial_statement_item(tenant_id, created_by_user_id);
create index if not exists fms_financial_statement_item_creator_tenant_idx
  on public.fms_financial_statement_item(created_by_user_id, tenant_id)
  where created_by_user_id is not null;

alter table public.fms_financial_statement_item
  drop constraint if exists fms_financial_statement_item_creator_tenant_fkey;
alter table public.fms_financial_statement_item
  add constraint fms_financial_statement_item_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_financial_statement_item_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null then
      if new.created_by_user_id is null then
        new.created_by_user_id := v_current_user_id;
      elsif new.created_by_user_id <> v_current_user_id then
        raise exception 'Financial-statement creator must be the current user'
          using errcode = '42501';
      end if;
    elsif new.created_by_user_id is null
       and nullif(btrim(coalesce(new.create_by, '')), '') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Financial-statement creator cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_financial_statement_item_creator_identity
  on public.fms_financial_statement_item;
create trigger fms_financial_statement_item_creator_identity
before insert or update of created_by_user_id on public.fms_financial_statement_item
for each row execute function app_private.set_fms_financial_statement_item_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_financial_report;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_financial_report(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.financial_report', '财务报表', 'FinanceFinancialReports',
    'created_by_user_id', '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (
      p_tenant_id, v_resource_id, 'reportAmounts', '本期、累计及期末报表金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'reportRules', '科目映射、公式关系及取数规则数量',
      'hidden', 'none', true, 20, '624944977@qq.com', '624944977@qq.com'
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

-- Preserve the access held by roles that already owned the financial-report page.
insert into public.sys_role_field_permission(
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id, role_menu.role_id, resource_row.id, field_row.id,
  'edit', '624944977@qq.com', '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name = 'FinanceFinancialReports'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.financial_report'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

-- Existing voucher and auto-posting roles previously read statement items directly.
-- Keep their shared item-picker data available without granting report amounts.
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
 and field_row.field_key = 'reportRules'
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and menu_row.name in ('FinanceVoucherCenter', 'FinanceAutoPosting')
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.financial_report'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_read_fms_financial_statement_items()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    app_private.can_execute_business_action('FinanceFinancialReports', null, null, false)
    or app_private.can_execute_business_action('FinanceVoucherCenter', null, null, false)
    or app_private.can_execute_business_action('FinanceAutoPosting', null, null, false);
$$;

create or replace function app_private.assert_fms_financial_report_rules_editable(
  p_owner_id uuid default null
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceFinancialReports', null, p_owner_id, false
  ) then
    raise exception 'Missing financial-report menu permission' using errcode = '42501';
  end if;

  v_access := app_private.field_access_map('fms.financial_report', p_owner_id);
  if coalesce(v_access ->> 'reportRules', 'hidden') <> 'edit' then
    raise exception 'Financial-report rules are not editable' using errcode = '42501';
  end if;
end;
$$;

create or replace function app_private.fms_financial_statement_item_raw_json(p_item_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select
    (to_jsonb(item_row) - 'tenant_id' - 'created_by_user_id')
    || jsonb_build_object(
      'mappings', coalesce((
        select jsonb_agg(
          (to_jsonb(mapping_row) - 'tenant_id')
          || jsonb_build_object(
            'subject', jsonb_build_object(
              'id', subject_row.id,
              'subject_code', subject_row.subject_code,
              'subject_name', subject_row.subject_name,
              'category', subject_row.category
            )
          )
          order by mapping_row.create_time, mapping_row.id
        )
        from public.fms_financial_statement_mapping mapping_row
        join public.fms_subject subject_row
          on subject_row.id = mapping_row.subject_id
         and subject_row.account_set_id = mapping_row.account_set_id
         and subject_row.tenant_id = mapping_row.tenant_id
        where mapping_row.statement_item_id = item_row.id
          and mapping_row.tenant_id = item_row.tenant_id
      ), '[]'::jsonb),
      'rule_count', case item_row.calculation_method
        when 'mapping' then (
          select count(*)
          from public.fms_financial_statement_mapping mapping_row
          where mapping_row.statement_item_id = item_row.id
            and mapping_row.tenant_id = item_row.tenant_id
        )
        when 'formula' then (
          select count(*)
          from public.fms_financial_statement_formula formula_row
          where formula_row.target_item_id = item_row.id
            and formula_row.tenant_id = item_row.tenant_id
        )
        else 0
      end
    )
  from public.fms_financial_statement_item item_row
  where item_row.id = p_item_id
    and item_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_financial_statement_item_to_secure_json(
  p_item_id uuid,
  p_owner_id uuid,
  p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(
    p_access,
    app_private.field_access_map('fms.financial_report', p_owner_id)
  );
  v_rule_access text := coalesce(v_access ->> 'reportRules', 'hidden');
  v_data jsonb := app_private.fms_financial_statement_item_raw_json(p_item_id);
begin
  if v_data is null then
    return null;
  end if;

  if v_rule_access = 'hidden' then
    v_data := v_data - 'mappings' - 'rule_count' - 'remark';
  elsif v_rule_access = 'masked' then
    v_data := v_data - 'mappings';
    v_data := app_private.apply_jsonb_amount_access(
      v_data, array['rule_count']::text[], v_rule_access
    );
    v_data := app_private.apply_jsonb_text_access(
      v_data, array['remark']::text[], v_rule_access
    );
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_financial_statement_items_secure(
  p_account_set_id uuid,
  p_statement_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  if not app_private.can_read_fms_financial_statement_items() then
    raise exception 'Missing financial-statement item menu permission' using errcode = '42501';
  end if;
  if p_statement_type not in ('balance_sheet', 'income_statement', 'cash_flow_statement') then
    raise exception 'Invalid financial-statement type' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.fms_account_set account_set
    where account_set.id = p_account_set_id
      and account_set.tenant_id = v_tenant_id
  ) then
    raise exception 'Financial-statement account set is outside the current tenant'
      using errcode = '42501';
  end if;

  for v_row in
    select item_row.id, item_row.created_by_user_id
    from public.fms_financial_statement_item item_row
    where item_row.tenant_id = v_tenant_id
      and item_row.account_set_id = p_account_set_id
      and item_row.statement_type = p_statement_type
    order by item_row.line_no, item_row.id
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_financial_statement_item_to_secure_json(
        v_row.id, v_row.created_by_user_id
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'field_access', app_private.field_access_map('fms.financial_report', null)
  );
end;
$$;

create or replace function public.fms_list_financial_statement_formulas_secure(
  p_target_item_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_owner_id uuid;
  v_access jsonb;
  v_rule_access text;
  v_records jsonb := '[]'::jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceFinancialReports', null, null, false
  ) then
    raise exception 'Missing financial-report menu permission' using errcode = '42501';
  end if;

  select item_row.created_by_user_id into v_owner_id
  from public.fms_financial_statement_item item_row
  where item_row.id = p_target_item_id
    and item_row.tenant_id = v_tenant_id;
  if not found then
    raise exception 'Financial-statement item does not exist in the current tenant'
      using errcode = 'P0002';
  end if;

  v_access := app_private.field_access_map('fms.financial_report', v_owner_id);
  v_rule_access := coalesce(v_access ->> 'reportRules', 'hidden');

  if v_rule_access in ('read', 'edit') then
    select coalesce(jsonb_agg(
      (to_jsonb(formula_row) - 'tenant_id')
      || jsonb_build_object(
        'source_item', jsonb_build_object(
          'id', source_item.id,
          'item_code', source_item.item_code,
          'item_name', source_item.item_name,
          'line_no', source_item.line_no
        )
      )
      order by formula_row.create_time, formula_row.id
    ), '[]'::jsonb)
    into v_records
    from public.fms_financial_statement_formula formula_row
    join public.fms_financial_statement_item source_item
      on source_item.id = formula_row.source_item_id
     and source_item.account_set_id = formula_row.account_set_id
     and source_item.tenant_id = formula_row.tenant_id
    where formula_row.target_item_id = p_target_item_id
      and formula_row.tenant_id = v_tenant_id;
  elsif v_rule_access = 'masked' then
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'id', formula_row.id,
        'target_item_id', formula_row.target_item_id,
        'source_item_id', '***',
        'factor', '***',
        'source_item', jsonb_build_object(
          'id', '***', 'item_code', '***', 'item_name', '***', 'line_no', '***'
        )
      )
      order by formula_row.create_time, formula_row.id
    ), '[]'::jsonb)
    into v_records
    from public.fms_financial_statement_formula formula_row
    where formula_row.target_item_id = p_target_item_id
      and formula_row.tenant_id = v_tenant_id;
  end if;

  return jsonb_build_object(
    'records', v_records,
    'field_access', v_access,
    'is_record_owner', v_owner_id is not null
      and v_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_financial_statement_report_secure(
  p_account_set_id uuid,
  p_statement_type text,
  p_fiscal_year integer,
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
  v_records jsonb := '[]'::jsonb;
  v_row record;
  v_access jsonb;
  v_data jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceFinancialReports', null, null, false
  ) then
    raise exception 'Missing financial-report menu permission' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.fms_account_set account_set
    where account_set.id = p_account_set_id
      and account_set.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Financial-report account set is outside the current tenant'
      using errcode = '42501';
  end if;

  for v_row in
    select report_row.*, item_row.created_by_user_id
    from public.fms_financial_statement_report(
      p_account_set_id, p_statement_type, p_fiscal_year, p_period_from, p_period_to
    ) report_row
    join public.fms_financial_statement_item item_row
      on item_row.id = report_row.item_id
     and item_row.account_set_id = p_account_set_id
     and item_row.tenant_id = app_private.current_user_tenant_id()
    order by report_row.line_no, report_row.item_id
  loop
    v_access := app_private.field_access_map(
      'fms.financial_report', v_row.created_by_user_id
    );
    v_data := to_jsonb(v_row) - 'created_by_user_id';
    v_data := app_private.apply_jsonb_amount_access(
      v_data,
      array['primary_amount', 'secondary_amount']::text[],
      coalesce(v_access ->> 'reportAmounts', 'hidden')
    );
    v_data := app_private.apply_jsonb_amount_access(
      v_data,
      array['mapping_count']::text[],
      coalesce(v_access ->> 'reportRules', 'hidden')
    );
    v_records := v_records || jsonb_build_array(
      v_data || jsonb_build_object(
        'field_access', v_access,
        'is_record_owner', v_row.created_by_user_id is not null
          and v_row.created_by_user_id = app_private.current_app_user_id()
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'field_access', app_private.field_access_map('fms.financial_report', null)
  );
end;
$$;

create or replace function public.initialize_fms_financial_statement_items_secure(
  p_account_set_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.assert_fms_financial_report_rules_editable(null);
  if not exists (
    select 1
    from public.fms_account_set account_set
    where account_set.id = p_account_set_id
      and account_set.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Financial-statement account set is outside the current tenant'
      using errcode = '42501';
  end if;
  return public.initialize_fms_financial_statement_items(p_account_set_id);
end;
$$;

create or replace function public.save_fms_financial_statement_item_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_item_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set_id uuid := nullif(p_payload ->> 'accountSetId', '')::uuid;
  v_owner_id uuid;
  v_saved public.fms_financial_statement_item%rowtype;
begin
  if v_account_set_id is null or not exists (
    select 1
    from public.fms_account_set account_set
    where account_set.id = v_account_set_id
      and account_set.tenant_id = v_tenant_id
  ) then
    raise exception 'Financial-statement account set is outside the current tenant'
      using errcode = '42501';
  end if;

  if v_item_id is not null then
    select item_row.created_by_user_id into v_owner_id
    from public.fms_financial_statement_item item_row
    where item_row.id = v_item_id
      and item_row.account_set_id = v_account_set_id
      and item_row.tenant_id = v_tenant_id
    for update;
    if not found then
      raise exception 'Financial-statement item does not exist in the current tenant'
        using errcode = 'P0002';
    end if;
  end if;

  perform app_private.assert_fms_financial_report_rules_editable(v_owner_id);
  v_saved := public.save_fms_financial_statement_item(p_payload);
  return app_private.fms_financial_statement_item_to_secure_json(
    v_saved.id, v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.save_fms_financial_statement_mappings_secure(
  p_statement_item_id uuid,
  p_mappings jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  select item_row.created_by_user_id into v_owner_id
  from public.fms_financial_statement_item item_row
  where item_row.id = p_statement_item_id
    and item_row.tenant_id = app_private.current_user_tenant_id()
  for update;
  if not found then
    raise exception 'Financial-statement item does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  perform app_private.assert_fms_financial_report_rules_editable(v_owner_id);
  return public.save_fms_financial_statement_mappings(p_statement_item_id, p_mappings);
end;
$$;

create or replace function public.save_fms_financial_statement_formulas_secure(
  p_target_item_id uuid,
  p_formulas jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  select item_row.created_by_user_id into v_owner_id
  from public.fms_financial_statement_item item_row
  where item_row.id = p_target_item_id
    and item_row.tenant_id = app_private.current_user_tenant_id()
  for update;
  if not found then
    raise exception 'Financial-statement item does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  perform app_private.assert_fms_financial_report_rules_editable(v_owner_id);
  return public.save_fms_financial_statement_formulas(p_target_item_id, p_formulas);
end;
$$;

revoke all on table public.fms_financial_statement_item from anon, authenticated;
revoke all on table public.fms_financial_statement_mapping from anon, authenticated;
revoke all on table public.fms_financial_statement_formula from anon, authenticated;

revoke execute on function public.fms_financial_statement_report(uuid, text, integer, integer, integer)
  from public, anon, authenticated;
revoke execute on function public.initialize_fms_financial_statement_items(uuid)
  from public, anon, authenticated;
revoke execute on function public.initialize_fms_financial_statement_items_base(uuid)
  from public, anon, authenticated;
revoke execute on function public.save_fms_financial_statement_item(jsonb)
  from public, anon, authenticated;
revoke execute on function public.save_fms_financial_statement_mappings(uuid, jsonb)
  from public, anon, authenticated;
revoke execute on function public.save_fms_financial_statement_formulas(uuid, jsonb)
  from public, anon, authenticated;

revoke all on function public.fms_list_financial_statement_items_secure(uuid, text)
  from public, anon, authenticated;
revoke all on function public.fms_list_financial_statement_formulas_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.fms_financial_statement_report_secure(
  uuid, text, integer, integer, integer
) from public, anon, authenticated;
revoke all on function public.initialize_fms_financial_statement_items_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.save_fms_financial_statement_item_secure(jsonb)
  from public, anon, authenticated;
revoke all on function public.save_fms_financial_statement_mappings_secure(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.save_fms_financial_statement_formulas_secure(uuid, jsonb)
  from public, anon, authenticated;

grant execute on function public.fms_list_financial_statement_items_secure(uuid, text)
  to authenticated;
grant execute on function public.fms_list_financial_statement_formulas_secure(uuid)
  to authenticated;
grant execute on function public.fms_financial_statement_report_secure(
  uuid, text, integer, integer, integer
) to authenticated;
grant execute on function public.initialize_fms_financial_statement_items_secure(uuid)
  to authenticated;
grant execute on function public.save_fms_financial_statement_item_secure(jsonb)
  to authenticated;
grant execute on function public.save_fms_financial_statement_mappings_secure(uuid, jsonb)
  to authenticated;
grant execute on function public.save_fms_financial_statement_formulas_secure(uuid, jsonb)
  to authenticated;

do $$
begin
  if exists (
    select 1
    from public.sys_tenant tenant_row
    where not exists (
      select 1
      from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'fms.financial_report'
        and resource_row.owner_column = 'created_by_user_id'
        and resource_row.enabled
    )
  ) then
    raise exception 'Missing fms.financial_report permission resource';
  end if;

  if exists (
    select 1
    from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.financial_report'
      and (
        select count(*)
        from public.sys_permission_field field_row
        where field_row.tenant_id = resource_row.tenant_id
          and field_row.resource_id = resource_row.id
          and field_row.enabled
      ) <> 2
  ) then
    raise exception 'Unexpected fms.financial_report field catalog';
  end if;

  if has_table_privilege(
       'authenticated', 'public.fms_financial_statement_item', 'select'
     ) or has_table_privilege(
       'authenticated', 'public.fms_financial_statement_mapping', 'select'
     ) or has_table_privilege(
       'authenticated', 'public.fms_financial_statement_formula', 'select'
     ) or has_table_privilege(
       'anon', 'public.fms_financial_statement_item', 'select'
     ) then
    raise exception 'Direct financial-statement reads remain exposed';
  end if;

  if has_function_privilege(
       'anon', 'public.fms_list_financial_statement_items_secure(uuid,text)', 'execute'
     ) or has_function_privilege(
       'authenticated',
       'public.fms_financial_statement_report(uuid,text,integer,integer,integer)',
       'execute'
     ) or not has_function_privilege(
       'authenticated',
       'public.fms_financial_statement_report_secure(uuid,text,integer,integer,integer)',
       'execute'
     ) then
    raise exception 'Financial-statement function privileges are not secure';
  end if;
end;
$$;

;
