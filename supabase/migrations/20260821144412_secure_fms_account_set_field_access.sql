-- Secure account-set tax registration, accounting policy and administrative audit fields.
-- Account-set identity options remain available as a minimal tenant-scoped read model for
-- the finance modules that need a selector. Existing menu/button definitions stay unchanged.

alter table public.fms_account_set
  add column if not exists created_by_user_id uuid;

with matched_creator as (
  select account_set_row.id, (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = account_set_row.tenant_id
      and lower(user_row.user_email) = lower(account_set_row.create_by)
    order by user_row.create_time, user_row.id
    limit 1
  ) user_id
  from public.fms_account_set account_set_row
  where account_set_row.created_by_user_id is null
    and nullif(btrim(coalesce(account_set_row.create_by, '')), '') is not null
)
update public.fms_account_set account_set_row
set created_by_user_id = matched_creator.user_id
from matched_creator
where account_set_row.id = matched_creator.id
  and matched_creator.user_id is not null;

create index if not exists fms_account_set_tenant_creator_idx
  on public.fms_account_set(tenant_id, created_by_user_id);
create index if not exists fms_account_set_creator_tenant_idx
  on public.fms_account_set(created_by_user_id, tenant_id)
  where created_by_user_id is not null;

alter table public.fms_account_set
  drop constraint if exists fms_account_set_creator_tenant_fkey;
alter table public.fms_account_set
  add constraint fms_account_set_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_account_set_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null and v_current_tenant_id = new.tenant_id then
      if new.created_by_user_id is null then
        new.created_by_user_id := v_current_user_id;
      elsif new.created_by_user_id <> v_current_user_id then
        raise exception 'Account-set creator must be the current user'
          using errcode = '42501';
      end if;
    elsif v_current_user_id is not null
      and not app_private.is_platform_super() then
      raise exception 'Account-set tenant must match the current user tenant'
        using errcode = '42501';
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
    raise exception 'Account-set creator cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_account_set_creator_identity on public.fms_account_set;
create trigger fms_account_set_creator_identity
before insert or update of created_by_user_id on public.fms_account_set
for each row execute function app_private.set_fms_account_set_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_account_set;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_account_set(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.account_set', '账套管理', 'FinanceAccountSet',
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
      p_tenant_id, v_resource_id, 'taxRegistration',
      '统一社会信用代码及纳税人类型',
      'hidden', 'id_card', true, 10, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'accountingPolicy',
      '会计准则、本位币及启用期间口径',
      'hidden', 'none', true, 20, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'administrativeAudit',
      '管理备注、维护人员及时间审计',
      'hidden', 'none', true, 30, '624944977@qq.com', '624944977@qq.com'
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

-- Preserve existing behaviour during rollout: roles that can open the management page
-- initially receive edit access. Tenant administrators can tighten it afterwards.
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
 and menu_row.name = 'FinanceAccountSet'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.account_set'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.assert_fms_account_set_readable()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action(
    'FinanceAccountSet', null, null, false
  ) then
    raise exception 'Missing account-set menu permission' using errcode = '42501';
  end if;
end;
$$;

create or replace function app_private.assert_fms_account_set_tenant(
  p_requested_tenant_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if (select auth.uid()) is null
    or v_current_tenant_id is null
    or app_private.current_app_user_id() is null then
    raise exception 'Authenticated application user is required' using errcode = '42501';
  end if;

  if app_private.is_platform_super() then
    return coalesce(p_requested_tenant_id, v_current_tenant_id);
  end if;

  if p_requested_tenant_id is not null
    and p_requested_tenant_id <> v_current_tenant_id then
    raise exception 'Account-set tenant is outside the current tenant'
      using errcode = '42501';
  end if;
  return v_current_tenant_id;
end;
$$;

create or replace function app_private.fms_account_set_to_secure_json(
  p_account_set_id uuid,
  p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.account_set', p_owner_id);
  v_tax_access text := coalesce(v_access ->> 'taxRegistration', 'hidden');
  v_policy_access text := coalesce(v_access ->> 'accountingPolicy', 'hidden');
  v_audit_access text := coalesce(v_access ->> 'administrativeAudit', 'hidden');
  v_data jsonb;
begin
  select to_jsonb(account_set_row) - 'created_by_user_id'
    || jsonb_build_object(
      'tenant', case when app_private.is_platform_super() then jsonb_build_object(
        'id', tenant_row.id,
        'tenant_code', tenant_row.tenant_code,
        'tenant_name', tenant_row.tenant_name
      ) else null end
    )
    into v_data
  from public.fms_account_set account_set_row
  join public.sys_tenant tenant_row on tenant_row.id = account_set_row.tenant_id
  where account_set_row.id = p_account_set_id
    and (
      app_private.is_platform_super()
      or account_set_row.tenant_id = app_private.current_user_tenant_id()
    );
  if v_data is null then return null; end if;

  if v_tax_access = 'hidden' then
    v_data := v_data - 'unified_social_credit_code' - 'vat_taxpayer_type';
  elsif v_tax_access = 'masked' then
    v_data := jsonb_set(
      v_data,
      '{unified_social_credit_code}',
      to_jsonb(app_private.mask_permission_value(
        v_data ->> 'unified_social_credit_code', 'id_card'
      )),
      true
    );
    v_data := jsonb_set(v_data, '{vat_taxpayer_type}', '"***"'::jsonb, true);
  end if;

  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'accounting_standard', 'base_currency_code', 'enabled_on',
      'fiscal_year_start_month'
    ]::text[],
    v_policy_access
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'remark', 'version', 'create_by', 'create_time', 'update_by', 'update_time'
    ]::text[],
    v_audit_access
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_account_set_options_secure(
  p_from integer default 0,
  p_to integer default 999,
  p_status text default null,
  p_tenant_id uuid default null,
  p_ids uuid[] default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_platform boolean := app_private.is_platform_super();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 999) - greatest(coalesce(p_from, 0), 0) + 1, 1), 1000);
  v_total bigint;
  v_records jsonb;
begin
  if (select auth.uid()) is null
    or v_current_tenant_id is null
    or app_private.current_app_user_id() is null then
    raise exception 'Authenticated application user is required' using errcode = '42501';
  end if;
  if not v_platform and p_tenant_id is not null and p_tenant_id <> v_current_tenant_id then
    raise exception 'Account-set tenant is outside the current tenant'
      using errcode = '42501';
  end if;

  select count(*) into v_total
  from public.fms_account_set account_set_row
  where (
      (v_platform and p_tenant_id is null)
      or account_set_row.tenant_id = coalesce(p_tenant_id, v_current_tenant_id)
    )
    and (p_status is null or account_set_row.status = p_status)
    and (p_ids is null or account_set_row.id = any(p_ids));

  select coalesce(jsonb_agg(option_row.payload order by option_row.is_default desc, option_row.account_set_name), '[]'::jsonb)
    into v_records
  from (
    select
      account_set_row.is_default,
      account_set_row.account_set_name,
      jsonb_build_object(
        'id', account_set_row.id,
        'tenant_id', account_set_row.tenant_id,
        'account_set_code', account_set_row.account_set_code,
        'account_set_name', account_set_row.account_set_name,
        'status', account_set_row.status
      ) payload
    from public.fms_account_set account_set_row
    where (
        (v_platform and p_tenant_id is null)
        or account_set_row.tenant_id = coalesce(p_tenant_id, v_current_tenant_id)
      )
      and (p_status is null or account_set_row.status = p_status)
      and (p_ids is null or account_set_row.id = any(p_ids))
    order by account_set_row.is_default desc, account_set_row.account_set_name
    offset v_from limit v_limit
  ) option_row;

  return jsonb_build_object('records', v_records, 'total', v_total);
end;
$$;

create or replace function public.fms_list_account_sets_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_platform boolean := app_private.is_platform_super();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1), 1000);
  v_keyword text := nullif(btrim(p_keyword), '');
  v_tax_access text := app_private.resolve_field_access(
    'fms.account_set', 'taxRegistration', null
  );
  v_total bigint;
  v_records jsonb := '[]'::jsonb;
  v_row record;
begin
  perform app_private.assert_fms_account_set_readable();
  if not v_platform and p_tenant_id is not null and p_tenant_id <> v_current_tenant_id then
    raise exception 'Account-set tenant is outside the current tenant'
      using errcode = '42501';
  end if;

  select count(*) into v_total
  from public.fms_account_set account_set_row
  where (
      (v_platform and p_tenant_id is null)
      or account_set_row.tenant_id = coalesce(p_tenant_id, v_current_tenant_id)
    )
    and (p_status is null or account_set_row.status = p_status)
    and (
      v_keyword is null
      or account_set_row.account_set_code ilike '%' || v_keyword || '%'
      or account_set_row.account_set_name ilike '%' || v_keyword || '%'
      or account_set_row.legal_entity_name ilike '%' || v_keyword || '%'
      or (
        v_tax_access in ('read', 'edit')
        and account_set_row.unified_social_credit_code ilike '%' || v_keyword || '%'
      )
    );

  for v_row in
    select account_set_row.id, account_set_row.created_by_user_id
    from public.fms_account_set account_set_row
    where (
        (v_platform and p_tenant_id is null)
        or account_set_row.tenant_id = coalesce(p_tenant_id, v_current_tenant_id)
      )
      and (p_status is null or account_set_row.status = p_status)
      and (
        v_keyword is null
        or account_set_row.account_set_code ilike '%' || v_keyword || '%'
        or account_set_row.account_set_name ilike '%' || v_keyword || '%'
        or account_set_row.legal_entity_name ilike '%' || v_keyword || '%'
        or (
          v_tax_access in ('read', 'edit')
          and account_set_row.unified_social_credit_code ilike '%' || v_keyword || '%'
        )
      )
    order by account_set_row.is_default desc, account_set_row.create_time desc
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_account_set_to_secure_json(v_row.id, v_row.created_by_user_id)
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', app_private.field_access_map('fms.account_set', null)
  );
end;
$$;

create or replace function public.fms_get_account_set_secure(p_account_set_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app_private.assert_fms_account_set_readable();
  select account_set_row.created_by_user_id into v_owner_id
  from public.fms_account_set account_set_row
  where account_set_row.id = p_account_set_id
    and (
      app_private.is_platform_super()
      or account_set_row.tenant_id = app_private.current_user_tenant_id()
    );
  if not found then
    raise exception 'Account set not found' using errcode = 'P0002';
  end if;
  return app_private.fms_account_set_to_secure_json(p_account_set_id, v_owner_id);
end;
$$;

create or replace function public.fms_get_account_set_overview_secure(
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_current_tenant_id uuid := app_private.current_user_tenant_id();
  v_platform boolean := app_private.is_platform_super();
  v_total bigint;
  v_active bigint;
  v_draft bigint;
  v_suspended bigint;
begin
  perform app_private.assert_fms_account_set_readable();
  if not v_platform and p_tenant_id is not null and p_tenant_id <> v_current_tenant_id then
    raise exception 'Account-set tenant is outside the current tenant'
      using errcode = '42501';
  end if;

  select
    count(*),
    count(*) filter (where account_set_row.status = 'active'),
    count(*) filter (where account_set_row.status = 'draft'),
    count(*) filter (where account_set_row.status = 'suspended')
  into v_total, v_active, v_draft, v_suspended
  from public.fms_account_set account_set_row
  where (
    (v_platform and p_tenant_id is null)
    or account_set_row.tenant_id = coalesce(p_tenant_id, v_current_tenant_id)
  );

  return jsonb_build_object(
    'total_count', v_total,
    'active_count', v_active,
    'draft_count', v_draft,
    'suspended_count', v_suspended
  );
end;
$$;

create or replace function public.save_fms_account_set_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account_set_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_requested_tenant_id uuid := nullif(p_payload ->> 'tenantId', '')::uuid;
  v_tenant_id uuid;
  v_owner_id uuid;
  v_current public.fms_account_set%rowtype;
  v_tax_access text;
  v_policy_access text;
  v_audit_access text;
  v_safe_payload jsonb;
  v_saved public.fms_account_set%rowtype;
begin
  perform app_private.assert_fms_account_set_readable();

  if v_account_set_id is null then
    v_tenant_id := app_private.assert_fms_account_set_tenant(v_requested_tenant_id);
    if app_private.current_user_tenant_id() = v_tenant_id then
      v_owner_id := app_private.current_app_user_id();
    end if;
  else
    select account_set_row.* into v_current
    from public.fms_account_set account_set_row
    where account_set_row.id = v_account_set_id
      and (
        app_private.is_platform_super()
        or account_set_row.tenant_id = app_private.current_user_tenant_id()
      )
    for update;
    if not found then
      raise exception 'Account set not found' using errcode = 'P0002';
    end if;
    v_tenant_id := v_current.tenant_id;
    if v_requested_tenant_id is not null and v_requested_tenant_id <> v_tenant_id then
      raise exception 'Account-set tenant cannot be changed' using errcode = '23514';
    end if;
    v_owner_id := v_current.created_by_user_id;
  end if;

  v_tax_access := app_private.resolve_field_access(
    'fms.account_set', 'taxRegistration', v_owner_id
  );
  v_policy_access := app_private.resolve_field_access(
    'fms.account_set', 'accountingPolicy', v_owner_id
  );
  v_audit_access := app_private.resolve_field_access(
    'fms.account_set', 'administrativeAudit', v_owner_id
  );

  if v_account_set_id is null then
    if v_tax_access <> 'edit' or v_policy_access <> 'edit' or v_audit_access <> 'edit' then
      raise exception 'New account-set sensitive fields are not editable'
        using errcode = '42501';
    end if;
    v_safe_payload := p_payload || jsonb_build_object('tenantId', v_tenant_id);
  else
    v_safe_payload := jsonb_build_object(
      'id', v_current.id,
      'tenantId', v_current.tenant_id,
      'accountSetCode', case when p_payload ? 'accountSetCode'
        then p_payload -> 'accountSetCode' else to_jsonb(v_current.account_set_code) end,
      'accountSetName', case when p_payload ? 'accountSetName'
        then p_payload -> 'accountSetName' else to_jsonb(v_current.account_set_name) end,
      'legalEntityName', case when p_payload ? 'legalEntityName'
        then p_payload -> 'legalEntityName' else to_jsonb(v_current.legal_entity_name) end,
      'unifiedSocialCreditCode', case
        when v_tax_access = 'edit' and p_payload ? 'unifiedSocialCreditCode'
          then p_payload -> 'unifiedSocialCreditCode'
        else to_jsonb(v_current.unified_social_credit_code) end,
      'vatTaxpayerType', case
        when v_tax_access = 'edit' and p_payload ? 'vatTaxpayerType'
          then p_payload -> 'vatTaxpayerType'
        else to_jsonb(v_current.vat_taxpayer_type) end,
      'accountingStandard', case
        when v_policy_access = 'edit' and p_payload ? 'accountingStandard'
          then p_payload -> 'accountingStandard'
        else to_jsonb(v_current.accounting_standard) end,
      'baseCurrencyCode', case
        when v_policy_access = 'edit' and p_payload ? 'baseCurrencyCode'
          then p_payload -> 'baseCurrencyCode'
        else to_jsonb(v_current.base_currency_code) end,
      'enabledOn', to_jsonb(v_current.enabled_on),
      'fiscalYearStartMonth', to_jsonb(v_current.fiscal_year_start_month),
      'status', to_jsonb(v_current.status),
      'isDefault', case when p_payload ? 'isDefault'
        then p_payload -> 'isDefault' else to_jsonb(v_current.is_default) end,
      'remark', case
        when v_audit_access = 'edit' and p_payload ? 'remark'
          then p_payload -> 'remark'
        else to_jsonb(v_current.remark) end
    );
  end if;

  v_saved := public.save_fms_account_set(v_safe_payload);
  return app_private.fms_account_set_to_secure_json(
    v_saved.id, v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.set_fms_account_set_status_secure(
  p_account_set_id uuid,
  p_status text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_saved public.fms_account_set%rowtype;
begin
  perform app_private.assert_fms_account_set_readable();
  select account_set_row.created_by_user_id into v_owner_id
  from public.fms_account_set account_set_row
  where account_set_row.id = p_account_set_id
    and (
      app_private.is_platform_super()
      or account_set_row.tenant_id = app_private.current_user_tenant_id()
    );
  if not found then
    raise exception 'Account set not found' using errcode = 'P0002';
  end if;

  v_saved := public.set_fms_account_set_status(p_account_set_id, p_status, p_reason);
  return app_private.fms_account_set_to_secure_json(v_saved.id, v_owner_id);
end;
$$;

revoke all privileges on table public.fms_account_set from anon, authenticated;

revoke execute on function public.save_fms_account_set(jsonb)
  from public, anon, authenticated;
revoke execute on function public.set_fms_account_set_status(uuid,text,text)
  from public, anon, authenticated;

grant execute on function public.fms_list_account_set_options_secure(integer,integer,text,uuid,uuid[])
  to authenticated;
grant execute on function public.fms_list_account_sets_secure(integer,integer,text,text,uuid)
  to authenticated;
grant execute on function public.fms_get_account_set_secure(uuid)
  to authenticated;
grant execute on function public.fms_get_account_set_overview_secure(uuid)
  to authenticated;
grant execute on function public.save_fms_account_set_secure(jsonb)
  to authenticated;
grant execute on function public.set_fms_account_set_status_secure(uuid,text,text)
  to authenticated;

revoke execute on function public.fms_list_account_set_options_secure(integer,integer,text,uuid,uuid[])
  from public, anon;
revoke execute on function public.fms_list_account_sets_secure(integer,integer,text,text,uuid)
  from public, anon;
revoke execute on function public.fms_get_account_set_secure(uuid)
  from public, anon;
revoke execute on function public.fms_get_account_set_overview_secure(uuid)
  from public, anon;
revoke execute on function public.save_fms_account_set_secure(jsonb)
  from public, anon;
revoke execute on function public.set_fms_account_set_status_secure(uuid,text,text)
  from public, anon;

revoke execute on function app_private.set_fms_account_set_creator_identity()
  from public, anon, authenticated;
revoke execute on function app_private.assert_fms_account_set_readable()
  from public, anon, authenticated;
revoke execute on function app_private.assert_fms_account_set_tenant(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.fms_account_set_to_secure_json(uuid,uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog_before_account_set(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog(uuid)
  from public, anon, authenticated;

do $$
begin
  if exists (
    select 1 from public.sys_tenant tenant_row
    where not exists (
      select 1 from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'fms.account_set'
        and resource_row.owner_column = 'created_by_user_id'
    )
  ) then
    raise exception 'Missing fms.account_set permission resource';
  end if;
  if exists (
    select 1 from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.account_set'
      and (
        select count(*) from public.sys_permission_field field_row
        where field_row.resource_id = resource_row.id
          and field_row.enabled
          and field_row.field_key in (
            'taxRegistration', 'accountingPolicy', 'administrativeAudit'
          )
      ) <> 3
  ) then
    raise exception 'Unexpected fms.account_set field catalog';
  end if;
end;
$$;

;
