-- Secure opening-balance amounts, auxiliary dimensions and control audit data.
-- Existing menu/button permission definitions and checks remain unchanged.

alter table public.fms_opening_balance
  add column if not exists created_by_user_id uuid;

with matched_creator as (
  select balance_row.id, (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = balance_row.tenant_id
      and lower(user_row.user_email) = lower(balance_row.create_by)
    order by user_row.create_time, user_row.id
    limit 1
  ) user_id
  from public.fms_opening_balance balance_row
  where balance_row.created_by_user_id is null
    and nullif(btrim(coalesce(balance_row.create_by, '')), '') is not null
)
update public.fms_opening_balance balance_row
set created_by_user_id = matched_creator.user_id
from matched_creator
where balance_row.id = matched_creator.id
  and matched_creator.user_id is not null;

create index if not exists fms_opening_balance_tenant_creator_idx
  on public.fms_opening_balance(tenant_id, created_by_user_id);
create index if not exists fms_opening_balance_creator_tenant_idx
  on public.fms_opening_balance(created_by_user_id, tenant_id)
  where created_by_user_id is not null;

alter table public.fms_opening_balance
  drop constraint if exists fms_opening_balance_creator_tenant_fkey;
alter table public.fms_opening_balance
  add constraint fms_opening_balance_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_opening_balance_creator_identity()
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
        raise exception 'Opening-balance creator must be the current user'
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
    raise exception 'Opening-balance creator cannot be changed'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_opening_balance_creator_identity on public.fms_opening_balance;
create trigger fms_opening_balance_creator_identity
before insert or update of created_by_user_id on public.fms_opening_balance
for each row execute function app_private.set_fms_opening_balance_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_opening_balance;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_opening_balance(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.opening_balance', '期初余额', 'FinanceOpeningBalance',
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
      p_tenant_id, v_resource_id, 'balanceAmounts',
      '期初借贷、本年累计、数量及原币金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'auxiliaryDetails',
      '核算外币及辅助核算维度明细',
      'hidden', 'none', true, 20, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'controlAudit',
      '确认、反确认原因、操作人员及时间审计',
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
 and menu_row.name = 'FinanceOpeningBalance'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.opening_balance'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.assert_fms_opening_balance_readable()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action(
    'FinanceOpeningBalance', null, null, false
  ) then
    raise exception 'Missing opening-balance menu permission' using errcode = '42501';
  end if;
end;
$$;

create or replace function app_private.fms_opening_balance_raw_json(p_balance_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select
    (to_jsonb(balance_row) - 'tenant_id' - 'created_by_user_id')
    || jsonb_build_object(
      'subject', jsonb_build_object(
        'id', subject_row.id,
        'subject_code', subject_row.subject_code,
        'subject_name', subject_row.subject_name,
        'balance_direction', subject_row.balance_direction
      ),
      'currency', case when currency_row.id is null then null else jsonb_build_object(
        'id', currency_row.id,
        'currency_code', currency_row.currency_code,
        'currency_name', currency_row.currency_name
      ) end
    )
  from public.fms_opening_balance balance_row
  join public.fms_subject subject_row
    on subject_row.id = balance_row.subject_id
   and subject_row.account_set_id = balance_row.account_set_id
   and subject_row.tenant_id = balance_row.tenant_id
  left join public.fms_currency currency_row
    on currency_row.id = balance_row.currency_id
   and currency_row.account_set_id = balance_row.account_set_id
   and currency_row.tenant_id = balance_row.tenant_id
  where balance_row.id = p_balance_id
    and balance_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_opening_balance_to_secure_json(
  p_balance_id uuid,
  p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.opening_balance', p_owner_id);
  v_amount_access text := coalesce(v_access ->> 'balanceAmounts', 'hidden');
  v_auxiliary_access text := coalesce(v_access ->> 'auxiliaryDetails', 'hidden');
  v_audit_access text := coalesce(v_access ->> 'controlAudit', 'hidden');
  v_data jsonb := app_private.fms_opening_balance_raw_json(p_balance_id);
  v_masked_auxiliary jsonb;
begin
  if v_data is null then return null; end if;

  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'opening_debit', 'opening_credit', 'year_to_date_debit',
      'year_to_date_credit', 'opening_quantity', 'original_currency_amount'
    ]::text[],
    v_amount_access
  );

  if v_auxiliary_access = 'hidden' then
    v_data := v_data - 'currency_id' - 'currency' - 'auxiliary_values';
  elsif v_auxiliary_access = 'masked' then
    select coalesce(jsonb_object_agg(item.key, '***'::text), '{}'::jsonb)
      into v_masked_auxiliary
    from jsonb_each(coalesce(v_data -> 'auxiliary_values', '{}'::jsonb)) item;
    v_data := (v_data - 'currency_id' - 'currency' - 'auxiliary_values')
      || jsonb_build_object(
        'currency_id', case when v_data -> 'currency_id' = 'null'::jsonb then null else '***' end,
        'currency', case when v_data -> 'currency' = 'null'::jsonb then null else
          jsonb_build_object('id', '***', 'currency_code', '***', 'currency_name', '***') end,
        'auxiliary_values', v_masked_auxiliary
      );
  end if;

  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['create_by', 'update_by', 'create_time', 'update_time']::text[],
    v_audit_access
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_opening_balance_control_to_secure_json(
  p_control_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.opening_balance', null);
  v_audit_access text := coalesce(v_access ->> 'controlAudit', 'hidden');
  v_data jsonb;
begin
  select to_jsonb(control_row) - 'tenant_id'
    into v_data
  from public.fms_opening_balance_control control_row
  where control_row.id = p_control_id
    and control_row.tenant_id = app_private.current_user_tenant_id();
  if v_data is null then return null; end if;

  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'confirmed_at', 'confirmed_by', 'reopened_at', 'reopened_by',
      'reopen_reason', 'create_by', 'update_by', 'create_time', 'update_time'
    ]::text[],
    v_audit_access
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data, array['reopen_count']::text[], v_audit_access
  );

  return v_data || jsonb_build_object('field_access', v_access);
end;
$$;

create or replace function public.fms_list_opening_balances_secure(
  p_account_set_id uuid,
  p_fiscal_year smallint
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
  perform app_private.assert_fms_opening_balance_readable();
  if not exists (
    select 1 from public.fms_account_set account_set
    where account_set.id = p_account_set_id
      and account_set.tenant_id = v_tenant_id
  ) then
    raise exception 'Opening-balance account set is outside the current tenant'
      using errcode = '42501';
  end if;

  for v_row in
    select balance_row.id, balance_row.created_by_user_id
    from public.fms_opening_balance balance_row
    join public.fms_subject subject_row
      on subject_row.id = balance_row.subject_id
     and subject_row.account_set_id = balance_row.account_set_id
     and subject_row.tenant_id = balance_row.tenant_id
    where balance_row.tenant_id = v_tenant_id
      and balance_row.account_set_id = p_account_set_id
      and balance_row.fiscal_year = p_fiscal_year
    order by subject_row.subject_code, balance_row.id
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_opening_balance_to_secure_json(
        v_row.id, v_row.created_by_user_id
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'field_access', app_private.field_access_map('fms.opening_balance', null)
  );
end;
$$;

create or replace function public.fms_get_opening_balance_secure(p_balance_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app_private.assert_fms_opening_balance_readable();
  select balance_row.created_by_user_id into v_owner_id
  from public.fms_opening_balance balance_row
  where balance_row.id = p_balance_id
    and balance_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Opening balance not found' using errcode = 'P0002';
  end if;
  return app_private.fms_opening_balance_to_secure_json(p_balance_id, v_owner_id);
end;
$$;

create or replace function public.save_fms_opening_balance_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_balance_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set_id uuid := nullif(p_payload ->> 'accountSetId', '')::uuid;
  v_fiscal_year smallint := nullif(p_payload ->> 'fiscalYear', '')::smallint;
  v_owner_id uuid;
  v_current public.fms_opening_balance%rowtype;
  v_amount_access text;
  v_auxiliary_access text;
  v_safe_payload jsonb;
  v_saved public.fms_opening_balance%rowtype;
begin
  perform app_private.assert_fms_opening_balance_readable();

  if v_balance_id is null then
    if v_account_set_id is null or v_fiscal_year is null or not exists (
      select 1 from public.fms_account_set account_set
      where account_set.id = v_account_set_id
        and account_set.tenant_id = v_tenant_id
    ) then
      raise exception 'Opening-balance account set is outside the current tenant'
        using errcode = '42501';
    end if;
    v_owner_id := app_private.current_app_user_id();
  else
    select balance_row.* into v_current
    from public.fms_opening_balance balance_row
    where balance_row.id = v_balance_id
      and balance_row.tenant_id = v_tenant_id;
    if not found then
      raise exception 'Opening balance not found' using errcode = 'P0002';
    end if;
    v_account_set_id := v_current.account_set_id;
    v_fiscal_year := v_current.fiscal_year;
    v_owner_id := v_current.created_by_user_id;
  end if;

  v_amount_access := app_private.resolve_field_access(
    'fms.opening_balance', 'balanceAmounts', v_owner_id
  );
  v_auxiliary_access := app_private.resolve_field_access(
    'fms.opening_balance', 'auxiliaryDetails', v_owner_id
  );
  if v_amount_access <> 'edit' and v_auxiliary_access <> 'edit' then
    raise exception 'Opening-balance fields are not editable' using errcode = '42501';
  end if;

  v_safe_payload := jsonb_build_object(
    'id', v_balance_id,
    'tenantId', v_tenant_id,
    'accountSetId', v_account_set_id,
    'fiscalYear', v_fiscal_year,
    'subjectId', case when v_balance_id is null
      then p_payload -> 'subjectId' else to_jsonb(v_current.subject_id) end,
    'currencyId', case when v_auxiliary_access = 'edit'
      then coalesce(p_payload -> 'currencyId', 'null'::jsonb)
      else to_jsonb(v_current.currency_id) end,
    'auxiliaryValues', case when v_auxiliary_access = 'edit'
      then coalesce(p_payload -> 'auxiliaryValues', '{}'::jsonb)
      else v_current.auxiliary_values end,
    'openingDebit', case when v_amount_access = 'edit'
      then coalesce(p_payload -> 'openingDebit', '0'::jsonb)
      else to_jsonb(v_current.opening_debit) end,
    'openingCredit', case when v_amount_access = 'edit'
      then coalesce(p_payload -> 'openingCredit', '0'::jsonb)
      else to_jsonb(v_current.opening_credit) end,
    'yearToDateDebit', case when v_amount_access = 'edit'
      then coalesce(p_payload -> 'yearToDateDebit', '0'::jsonb)
      else to_jsonb(v_current.year_to_date_debit) end,
    'yearToDateCredit', case when v_amount_access = 'edit'
      then coalesce(p_payload -> 'yearToDateCredit', '0'::jsonb)
      else to_jsonb(v_current.year_to_date_credit) end,
    'openingQuantity', case when v_amount_access = 'edit'
      then coalesce(p_payload -> 'openingQuantity', '0'::jsonb)
      else to_jsonb(v_current.opening_quantity) end,
    'originalCurrencyAmount', case when v_amount_access = 'edit'
      then coalesce(p_payload -> 'originalCurrencyAmount', '0'::jsonb)
      else to_jsonb(v_current.original_currency_amount) end
  );

  v_saved := public.save_fms_opening_balance(v_safe_payload);
  return app_private.fms_opening_balance_to_secure_json(
    v_saved.id, v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.delete_fms_opening_balance_secure(p_balance_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  perform app_private.assert_fms_opening_balance_readable();
  select balance_row.created_by_user_id into v_owner_id
  from public.fms_opening_balance balance_row
  where balance_row.id = p_balance_id
    and balance_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Opening balance not found' using errcode = 'P0002';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceOpeningBalance', 'FinanceOpeningBalance:Delete', v_owner_id, false
  ) then
    raise exception 'Missing opening-balance delete permission' using errcode = '42501';
  end if;
  delete from public.fms_opening_balance balance_row
  where balance_row.id = p_balance_id
    and balance_row.tenant_id = app_private.current_user_tenant_id();
  return p_balance_id;
end;
$$;

create or replace function public.fms_opening_balance_summary_secure(
  p_account_set_id uuid,
  p_fiscal_year smallint
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.opening_balance', null);
  v_amount_access text := coalesce(v_access ->> 'balanceAmounts', 'hidden');
  v_entry_count bigint;
  v_opening_debit numeric;
  v_opening_credit numeric;
  v_difference numeric;
  v_status text;
  v_control_id uuid;
  v_result jsonb;
begin
  perform app_private.assert_fms_opening_balance_readable();
  if not exists (
    select 1 from public.fms_account_set account_set
    where account_set.id = p_account_set_id
      and account_set.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Opening-balance account set is outside the current tenant'
      using errcode = '42501';
  end if;

  select
    count(balance_row.id),
    coalesce(sum(balance_row.opening_debit), 0),
    coalesce(sum(balance_row.opening_credit), 0)
  into v_entry_count, v_opening_debit, v_opening_credit
  from public.fms_opening_balance balance_row
  where balance_row.tenant_id = app_private.current_user_tenant_id()
    and balance_row.account_set_id = p_account_set_id
    and balance_row.fiscal_year = p_fiscal_year;
  v_difference := v_opening_debit - v_opening_credit;

  select control_row.id, control_row.status
    into v_control_id, v_status
  from public.fms_opening_balance_control control_row
  where control_row.tenant_id = app_private.current_user_tenant_id()
    and control_row.account_set_id = p_account_set_id
    and control_row.fiscal_year = p_fiscal_year;
  v_status := coalesce(v_status, 'draft');

  v_result := jsonb_build_object(
    'account_set_id', p_account_set_id,
    'fiscal_year', p_fiscal_year,
    'status', v_status,
    'entry_count', v_entry_count,
    'is_balanced', v_difference = 0,
    'field_access', v_access,
    'control', case when v_control_id is null then null else
      app_private.fms_opening_balance_control_to_secure_json(v_control_id) end
  );

  if v_amount_access in ('read', 'edit') then
    v_result := v_result || jsonb_build_object(
      'opening_debit', v_opening_debit,
      'opening_credit', v_opening_credit,
      'difference', v_difference
    );
  elsif v_amount_access = 'masked' then
    v_result := v_result || jsonb_build_object(
      'opening_debit', '***', 'opening_credit', '***', 'difference', '***'
    );
  end if;
  return v_result;
end;
$$;

create or replace function public.set_fms_opening_balance_status_secure(
  p_account_set_id uuid,
  p_fiscal_year smallint,
  p_status text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_saved public.fms_opening_balance_control%rowtype;
begin
  perform app_private.assert_fms_opening_balance_readable();
  if not exists (
    select 1 from public.fms_account_set account_set
    where account_set.id = p_account_set_id
      and account_set.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Opening-balance account set is outside the current tenant'
      using errcode = '42501';
  end if;
  v_saved := public.set_fms_opening_balance_status(
    p_account_set_id, p_fiscal_year, p_status, p_reason
  );
  return app_private.fms_opening_balance_control_to_secure_json(v_saved.id);
end;
$$;

-- The account-set setup drawer only needs aggregate counts. Keep it available after
-- direct opening-balance table access is closed, with an explicit tenant/menu boundary.
create or replace function public.fms_accounting_foundation_summary(p_account_set_id uuid)
returns table(
  account_set_id uuid,
  subject_count bigint,
  enabled_subject_count bigint,
  currency_count bigint,
  auxiliary_type_count bigint,
  open_period_count bigint,
  closed_period_count bigint,
  opening_balance_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not app_private.can_execute_business_action('FinanceAccountSet', null, null, false) then
    raise exception 'Missing account-set menu permission' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.fms_account_set account_set
    where account_set.id = p_account_set_id
      and account_set.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Account set is outside the current tenant' using errcode = '42501';
  end if;

  return query
  select
    account_set.id,
    (select count(*) from public.fms_subject subject_row
      where subject_row.account_set_id = account_set.id
        and subject_row.tenant_id = account_set.tenant_id),
    (select count(*) from public.fms_subject subject_row
      where subject_row.account_set_id = account_set.id
        and subject_row.tenant_id = account_set.tenant_id
        and subject_row.is_enabled),
    (select count(*) from public.fms_currency currency_row
      where currency_row.account_set_id = account_set.id
        and currency_row.tenant_id = account_set.tenant_id
        and currency_row.is_enabled),
    (select count(*) from public.fms_auxiliary_type type_row
      where type_row.account_set_id = account_set.id
        and type_row.tenant_id = account_set.tenant_id
        and type_row.is_enabled),
    (select count(*) from public.fms_accounting_period period_row
      where period_row.account_set_id = account_set.id
        and period_row.tenant_id = account_set.tenant_id
        and period_row.status = 'open'),
    (select count(*) from public.fms_accounting_period period_row
      where period_row.account_set_id = account_set.id
        and period_row.tenant_id = account_set.tenant_id
        and period_row.status = 'closed'),
    (select count(*) from public.fms_opening_balance balance_row
      where balance_row.account_set_id = account_set.id
        and balance_row.tenant_id = account_set.tenant_id)
  from public.fms_account_set account_set
  where account_set.id = p_account_set_id
    and account_set.tenant_id = app_private.current_user_tenant_id();
end;
$$;

revoke all privileges on table public.fms_opening_balance from anon, authenticated;
revoke all privileges on table public.fms_opening_balance_control from anon, authenticated;

revoke execute on function public.save_fms_opening_balance(jsonb)
  from public, anon, authenticated;
revoke execute on function public.fms_opening_balance_summary(uuid,smallint)
  from public, anon, authenticated;
revoke execute on function public.set_fms_opening_balance_status(uuid,smallint,text,text)
  from public, anon, authenticated;

grant execute on function public.fms_list_opening_balances_secure(uuid,smallint)
  to authenticated;
grant execute on function public.fms_get_opening_balance_secure(uuid)
  to authenticated;
grant execute on function public.save_fms_opening_balance_secure(jsonb)
  to authenticated;
grant execute on function public.delete_fms_opening_balance_secure(uuid)
  to authenticated;
grant execute on function public.fms_opening_balance_summary_secure(uuid,smallint)
  to authenticated;
grant execute on function public.set_fms_opening_balance_status_secure(
  uuid,smallint,text,text
) to authenticated;

revoke execute on function public.fms_list_opening_balances_secure(uuid,smallint)
  from public, anon;
revoke execute on function public.fms_get_opening_balance_secure(uuid)
  from public, anon;
revoke execute on function public.save_fms_opening_balance_secure(jsonb)
  from public, anon;
revoke execute on function public.delete_fms_opening_balance_secure(uuid)
  from public, anon;
revoke execute on function public.fms_opening_balance_summary_secure(uuid,smallint)
  from public, anon;
revoke execute on function public.set_fms_opening_balance_status_secure(
  uuid,smallint,text,text
) from public, anon;

revoke execute on function public.fms_accounting_foundation_summary(uuid)
  from public, anon;
grant execute on function public.fms_accounting_foundation_summary(uuid)
  to authenticated;

revoke execute on function app_private.set_fms_opening_balance_creator_identity()
  from public, anon, authenticated;
revoke execute on function app_private.assert_fms_opening_balance_readable()
  from public, anon, authenticated;
revoke execute on function app_private.fms_opening_balance_raw_json(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.fms_opening_balance_to_secure_json(uuid,uuid)
  from public, anon, authenticated;
revoke execute on function app_private.fms_opening_balance_control_to_secure_json(uuid)
  from public, anon, authenticated;
revoke execute on function app_private.seed_field_permission_catalog_before_opening_balance(uuid)
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
        and resource_row.resource_key = 'fms.opening_balance'
        and resource_row.owner_column = 'created_by_user_id'
    )
  ) then
    raise exception 'Missing fms.opening_balance permission resource';
  end if;
  if exists (
    select 1 from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.opening_balance'
      and (
        select count(*) from public.sys_permission_field field_row
        where field_row.resource_id = resource_row.id
          and field_row.enabled
          and field_row.field_key in (
            'balanceAmounts', 'auxiliaryDetails', 'controlAudit'
          )
      ) <> 3
  ) then
    raise exception 'Unexpected fms.opening_balance field catalog';
  end if;
end;
$$;

;
