-- Secure voucher amounts, source references, attachments and audit details.
-- Existing menu/button definitions are intentionally left unchanged.

alter table public.fms_voucher
  add column if not exists created_by_user_id uuid;

with matched_creator as (
  select voucher_row.id as voucher_id, (
    select user_row.id
    from public.sys_user user_row
    where user_row.tenant_id = voucher_row.tenant_id
      and lower(user_row.user_email) = lower(voucher_row.create_by)
    order by user_row.create_time, user_row.id
    limit 1
  ) as user_id
  from public.fms_voucher voucher_row
  where voucher_row.created_by_user_id is null
    and nullif(btrim(coalesce(voucher_row.create_by, '')), '') is not null
)
update public.fms_voucher voucher_row
set created_by_user_id = matched_creator.user_id
from matched_creator
where voucher_row.id = matched_creator.voucher_id
  and matched_creator.user_id is not null;

create index if not exists fms_voucher_tenant_creator_idx
  on public.fms_voucher(tenant_id, created_by_user_id);
create index if not exists fms_voucher_creator_tenant_idx
  on public.fms_voucher(created_by_user_id, tenant_id)
  where created_by_user_id is not null;

alter table public.fms_voucher
  drop constraint if exists fms_voucher_creator_tenant_fkey;
alter table public.fms_voucher
  add constraint fms_voucher_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_voucher_creator_identity()
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
        raise exception 'Voucher creator must be the current user' using errcode = '42501';
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
    raise exception 'Voucher creator cannot be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_voucher_creator_identity on public.fms_voucher;
create trigger fms_voucher_creator_identity
before insert or update of created_by_user_id on public.fms_voucher
for each row execute function app_private.set_fms_voucher_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_voucher;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_voucher(p_tenant_id);

  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.voucher', '会计凭证', 'FinanceVoucherCenter',
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
      p_tenant_id, v_resource_id, 'voucherAmounts',
      '凭证借贷、原币、汇率、数量及现金流归集金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'sourceReferences',
      '业务来源单号、来源标识及分录来源关联',
      'hidden', 'none', true, 20, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'voucherAttachments',
      '原始凭证附件',
      'hidden', 'none', true, 30, '624944977@qq.com', '624944977@qq.com'
    ),
    (
      p_tenant_id, v_resource_id, 'auditTrail',
      '审核、过账、作废、冲销人员及原因',
      'hidden', 'none', true, 40, '624944977@qq.com', '624944977@qq.com'
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

-- Preserve current voucher-center behavior. Tenant administrators can tighten it later.
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
 and menu_row.name = 'FinanceVoucherCenter'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.voucher'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

-- Auto-posting opens voucher details from its event drawer. Keep that shared read path intact.
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
 and menu_row.name = 'FinanceAutoPosting'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.voucher'
  and resource_row.enabled
  and field_row.enabled
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.can_read_fms_voucher_detail()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    app_private.can_execute_business_action(
      'FinanceVoucherCenter', 'FinanceVoucherCenter:View', null, false
    )
    or app_private.can_execute_business_action('FinanceAutoPosting', null, null, false);
$$;

create or replace function app_private.fms_voucher_raw_json(
  p_voucher_id uuid,
  p_include_detail boolean default false
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select
    (to_jsonb(voucher_row) - 'tenant_id' - 'created_by_user_id')
    || jsonb_build_object(
      'account_set', jsonb_build_object(
        'id', account_set_row.id,
        'account_set_code', account_set_row.account_set_code,
        'account_set_name', account_set_row.account_set_name,
        'base_currency_code', account_set_row.base_currency_code
      )
    )
    || case when p_include_detail then jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(
          (to_jsonb(line_row) - 'tenant_id')
          || jsonb_build_object(
            'subject', jsonb_build_object(
              'id', subject_row.id,
              'subject_code', subject_row.subject_code,
              'subject_name', subject_row.subject_name,
              'balance_direction', subject_row.balance_direction,
              'allow_quantity', subject_row.allow_quantity,
              'unit_name', subject_row.unit_name,
              'allow_foreign_currency', subject_row.allow_foreign_currency
            ),
            'currency', case when currency_row.id is null then null else jsonb_build_object(
              'id', currency_row.id,
              'currency_code', currency_row.currency_code,
              'currency_name', currency_row.currency_name
            ) end
          )
          order by line_row.line_no, line_row.id
        )
        from public.fms_voucher_line line_row
        join public.fms_subject subject_row on subject_row.id = line_row.subject_id
        left join public.fms_currency currency_row on currency_row.id = line_row.currency_id
        where line_row.voucher_id = voucher_row.id
          and line_row.tenant_id = voucher_row.tenant_id
      ), '[]'::jsonb),
      'actions', coalesce((
        select jsonb_agg(to_jsonb(action_row) - 'tenant_id' order by action_row.action_time, action_row.id)
        from public.fms_voucher_action action_row
        where action_row.voucher_id = voucher_row.id
          and action_row.tenant_id = voucher_row.tenant_id
      ), '[]'::jsonb)
    ) else '{}'::jsonb end
  from public.fms_voucher voucher_row
  join public.fms_account_set account_set_row
    on account_set_row.id = voucher_row.account_set_id
   and account_set_row.tenant_id = voucher_row.tenant_id
  where voucher_row.id = p_voucher_id
    and voucher_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.apply_fms_voucher_line_access(
  p_lines jsonb,
  p_amount_access text,
  p_source_access text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(
    app_private.apply_jsonb_text_access(
      app_private.apply_jsonb_amount_access(
        line_value,
        array[
          'exchange_rate', 'original_amount', 'quantity',
          'debit_amount', 'credit_amount'
        ]::text[],
        p_amount_access
      ),
      array['source_line_type', 'source_line_id']::text[],
      p_source_access
    ) order by line_number
  ), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
    with ordinality as line_rows(line_value, line_number);
$$;

create or replace function app_private.apply_fms_voucher_action_access(
  p_actions jsonb,
  p_access text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
begin
  if p_access = 'hidden' then
    return '[]'::jsonb;
  end if;
  if p_access = 'masked' then
    return coalesce((
      select jsonb_agg(
        jsonb_set(
          app_private.apply_jsonb_text_access(
            action_value,
            array['actor', 'reason']::text[],
            'masked'
          ),
          '{snapshot}', '{}'::jsonb, true
        ) order by action_number
      )
      from jsonb_array_elements(coalesce(p_actions, '[]'::jsonb))
        with ordinality as action_rows(action_value, action_number)
    ), '[]'::jsonb);
  end if;
  return coalesce(p_actions, '[]'::jsonb);
end;
$$;

create or replace function app_private.fms_voucher_to_secure_json(
  p_voucher jsonb,
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
  v_access jsonb := coalesce(p_access, app_private.field_access_map('fms.voucher', p_owner_id));
  v_data jsonb := coalesce(p_voucher, '{}'::jsonb) - 'tenant_id' - 'created_by_user_id';
  v_amount_access text := coalesce(v_access ->> 'voucherAmounts', 'hidden');
  v_source_access text := coalesce(v_access ->> 'sourceReferences', 'hidden');
  v_attachment_access text := coalesce(v_access ->> 'voucherAttachments', 'hidden');
  v_audit_access text := coalesce(v_access ->> 'auditTrail', 'hidden');
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['total_debit', 'total_credit']::text[],
    v_amount_access
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['source_id', 'source_no', 'source_event_code', 'reversal_voucher_id']::text[],
    v_source_access
  );
  v_data := app_private.apply_jsonb_document_access(
    v_data,
    array['attachments']::text[],
    v_attachment_access
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array[
      'submitted_by', 'reviewed_by', 'review_comment', 'posted_by',
      'voided_by', 'void_reason', 'reversed_by', 'reversal_reason'
    ]::text[],
    v_audit_access
  );

  if v_data ? 'lines' then
    v_data := jsonb_set(
      v_data, '{lines}',
      app_private.apply_fms_voucher_line_access(
        v_data -> 'lines', v_amount_access, v_source_access
      ), true
    );
  end if;
  if v_data ? 'actions' then
    v_data := jsonb_set(
      v_data, '{actions}',
      app_private.apply_fms_voucher_action_access(v_data -> 'actions', v_audit_access),
      true
    );
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id is not null
      and p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_vouchers_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_status text default null,
  p_voucher_type text default null,
  p_source_type text default null,
  p_keyword text default null,
  p_voucher_start_date date default null,
  p_voucher_end_date date default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_permission text := case when p_purpose = 'export'
    then 'FinanceVoucherCenter:Export'
    else 'FinanceVoucherCenter:View'
  end;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer;
  v_total integer := 0;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map('fms.voucher', null);
  v_row record;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid voucher read purpose' using errcode = '22023';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceVoucherCenter', v_permission, null, false
  ) then
    raise exception 'Missing voucher read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;
  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 19) - v_from + 1, 1)
  );

  select count(*)::integer into v_total
  from public.fms_voucher voucher_row
  where voucher_row.tenant_id = v_tenant_id
    and (p_ids is null or voucher_row.id = any(p_ids))
    and (p_account_set_id is null or voucher_row.account_set_id = p_account_set_id)
    and (p_status is null or voucher_row.status = p_status)
    and (p_voucher_type is null or voucher_row.voucher_type = p_voucher_type)
    and (p_source_type is null or voucher_row.source_type = p_source_type)
    and (p_voucher_start_date is null or voucher_row.voucher_date >= p_voucher_start_date)
    and (p_voucher_end_date is null or voucher_row.voucher_date <= p_voucher_end_date)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or voucher_row.voucher_no ilike '%' || btrim(p_keyword) || '%'
      or voucher_row.summary ilike '%' || btrim(p_keyword) || '%'
      or (
        app_private.resolve_field_access(
          'fms.voucher', 'sourceReferences', voucher_row.created_by_user_id
        ) in ('read', 'edit')
        and voucher_row.source_no ilike '%' || btrim(p_keyword) || '%'
      )
    );

  for v_row in
    select voucher_row.id, voucher_row.created_by_user_id
    from public.fms_voucher voucher_row
    where voucher_row.tenant_id = v_tenant_id
      and (p_ids is null or voucher_row.id = any(p_ids))
      and (p_account_set_id is null or voucher_row.account_set_id = p_account_set_id)
      and (p_status is null or voucher_row.status = p_status)
      and (p_voucher_type is null or voucher_row.voucher_type = p_voucher_type)
      and (p_source_type is null or voucher_row.source_type = p_source_type)
      and (p_voucher_start_date is null or voucher_row.voucher_date >= p_voucher_start_date)
      and (p_voucher_end_date is null or voucher_row.voucher_date <= p_voucher_end_date)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or voucher_row.voucher_no ilike '%' || btrim(p_keyword) || '%'
        or voucher_row.summary ilike '%' || btrim(p_keyword) || '%'
        or (
          app_private.resolve_field_access(
            'fms.voucher', 'sourceReferences', voucher_row.created_by_user_id
          ) in ('read', 'edit')
          and voucher_row.source_no ilike '%' || btrim(p_keyword) || '%'
        )
      )
    order by voucher_row.voucher_date desc, voucher_row.voucher_no desc, voucher_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_voucher_to_secure_json(
        app_private.fms_voucher_raw_json(v_row.id, false),
        v_row.created_by_user_id
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'field_access', v_base_access
  );
end;
$$;

create or replace function public.fms_get_voucher_secure(p_voucher_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_data jsonb;
begin
  if not app_private.can_read_fms_voucher_detail() then
    raise exception 'Missing voucher detail permission' using errcode = '42501';
  end if;
  select voucher_row.created_by_user_id into v_owner_id
  from public.fms_voucher voucher_row
  where voucher_row.id = p_voucher_id
    and voucher_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Voucher not found' using errcode = 'P0002';
  end if;
  v_data := app_private.fms_voucher_raw_json(p_voucher_id, true);
  return app_private.fms_voucher_to_secure_json(v_data, v_owner_id);
end;
$$;

create or replace function public.fms_voucher_summary_secure(p_account_set_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.voucher', null);
  v_data jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceVoucherCenter', 'FinanceVoucherCenter:View', null, false
  ) then
    raise exception 'Missing voucher summary permission' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.fms_account_set account_set_row
    where account_set_row.id = p_account_set_id
      and account_set_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Account set not found' using errcode = 'P0002';
  end if;
  select to_jsonb(summary_row) into v_data
  from public.fms_voucher_summary(p_account_set_id) summary_row;
  v_data := app_private.apply_jsonb_amount_access(
    coalesce(v_data, jsonb_build_object('account_set_id', p_account_set_id)),
    array['current_period_posted_amount']::text[],
    coalesce(v_access ->> 'voucherAmounts', 'hidden')
  );
  return v_data || jsonb_build_object('field_access', v_access);
end;
$$;

create or replace function public.fms_list_cash_flow_allocations_secure(p_voucher_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_access jsonb;
  v_amount_access text;
begin
  if not app_private.can_read_fms_voucher_detail() then
    raise exception 'Missing voucher cash-flow permission' using errcode = '42501';
  end if;
  select voucher_row.created_by_user_id into v_owner_id
  from public.fms_voucher voucher_row
  where voucher_row.id = p_voucher_id
    and voucher_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Voucher not found' using errcode = 'P0002';
  end if;
  v_access := app_private.field_access_map('fms.voucher', v_owner_id);
  v_amount_access := coalesce(v_access ->> 'voucherAmounts', 'hidden');
  return coalesce((
    select jsonb_agg(
      app_private.apply_jsonb_amount_access(
        (to_jsonb(allocation_row) - 'tenant_id')
        || jsonb_build_object(
          'statement_item', jsonb_build_object(
            'id', item_row.id,
            'item_code', item_row.item_code,
            'item_name', item_row.item_name,
            'cash_flow_direction', item_row.cash_flow_direction
          ),
          'field_access', v_access,
          'is_record_owner', v_owner_id is not null
            and v_owner_id = app_private.current_app_user_id()
        ),
        array['amount']::text[],
        v_amount_access
      ) order by allocation_row.create_time, allocation_row.id
    )
    from public.fms_cash_flow_allocation allocation_row
    join public.fms_voucher_line line_row on line_row.id = allocation_row.voucher_line_id
    join public.fms_financial_statement_item item_row
      on item_row.id = allocation_row.statement_item_id
    where line_row.voucher_id = p_voucher_id
      and allocation_row.tenant_id = app_private.current_user_tenant_id()
  ), '[]'::jsonb);
end;
$$;

create or replace function app_private.fms_voucher_financial_lines_payload(p_voucher_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'lineNo', line_row.line_no,
    'exchangeRate', line_row.exchange_rate,
    'originalAmount', line_row.original_amount,
    'quantity', line_row.quantity,
    'debitAmount', line_row.debit_amount,
    'creditAmount', line_row.credit_amount
  ) order by line_row.line_no, line_row.id), '[]'::jsonb)
  from public.fms_voucher_line line_row
  where line_row.voucher_id = p_voucher_id
    and line_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_voucher_financial_lines_input(p_lines jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'lineNo', coalesce(nullif(line_value ->> 'lineNo', '')::smallint, line_number::smallint),
    'exchangeRate', coalesce(nullif(line_value ->> 'exchangeRate', '')::numeric, 1),
    'originalAmount', coalesce(nullif(line_value ->> 'originalAmount', '')::numeric, 0),
    'quantity', coalesce(nullif(line_value ->> 'quantity', '')::numeric, 0),
    'debitAmount', coalesce(nullif(line_value ->> 'debitAmount', '')::numeric, 0),
    'creditAmount', coalesce(nullif(line_value ->> 'creditAmount', '')::numeric, 0)
  ) order by line_number), '[]'::jsonb)
  from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
    with ordinality as line_rows(line_value, line_number);
$$;

create or replace function public.save_fms_voucher_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_existing public.fms_voucher%rowtype;
  v_saved public.fms_voucher%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_access jsonb;
  v_amount_editable boolean := true;
  v_date date;
  v_actor text := coalesce(auth.jwt() ->> 'email', auth.uid()::text, 'unknown');
  v_permission text := case when v_id is null
    then 'FinanceVoucherCenter:Add'
    else 'FinanceVoucherCenter:Edit'
  end;
begin
  if not app_private.can_execute_business_action(
    'FinanceVoucherCenter', v_permission, null, false
  ) then
    raise exception 'Missing voucher write permission' using errcode = '42501';
  end if;

  if v_id is not null then
    select * into v_existing
    from public.fms_voucher voucher_row
    where voucher_row.id = v_id
      and voucher_row.tenant_id = app_private.current_user_tenant_id()
    for update;
    if not found then
      raise exception 'Voucher not found' using errcode = 'P0002';
    end if;
    v_access := app_private.field_access_map('fms.voucher', v_existing.created_by_user_id);
    v_amount_editable := coalesce(v_access ->> 'voucherAmounts', 'hidden') = 'edit';

    if not v_amount_editable
       and app_private.fms_voucher_financial_lines_input(p_payload -> 'lines')
         is distinct from app_private.fms_voucher_financial_lines_payload(v_id) then
      raise exception 'Voucher amounts are not editable' using errcode = '42501';
    end if;

    if coalesce(v_access ->> 'sourceReferences', 'hidden') <> 'edit'
       and (
         case when p_payload ? 'sourceId'
           then nullif(p_payload ->> 'sourceId', '')::uuid
           else v_existing.source_id
         end is distinct from v_existing.source_id
         or case when p_payload ? 'sourceNo'
           then nullif(btrim(p_payload ->> 'sourceNo'), '')
           else v_existing.source_no
         end is distinct from v_existing.source_no
         or case when p_payload ? 'sourceEventCode'
           then nullif(btrim(p_payload ->> 'sourceEventCode'), '')
           else v_existing.source_event_code
         end is distinct from v_existing.source_event_code
       ) then
      raise exception 'Voucher source references are not editable' using errcode = '42501';
    end if;
    if coalesce(v_access ->> 'sourceReferences', 'hidden') <> 'edit' then
      p_payload := p_payload || jsonb_build_object(
        'sourceId', v_existing.source_id,
        'sourceNo', v_existing.source_no,
        'sourceEventCode', v_existing.source_event_code
      );
    end if;

    if coalesce(v_access ->> 'voucherAttachments', 'hidden') <> 'edit'
       and coalesce(p_payload -> 'attachments', '[]'::jsonb)
         is distinct from v_existing.attachments then
      raise exception 'Voucher attachments are not editable' using errcode = '42501';
    end if;
    if coalesce(v_access ->> 'voucherAttachments', 'hidden') <> 'edit' then
      p_payload := p_payload || jsonb_build_object('attachments', v_existing.attachments);
    end if;

    if not v_amount_editable then
      if nullif(p_payload ->> 'accountSetId', '')::uuid is distinct from v_existing.account_set_id then
        raise exception 'Voucher account set cannot be changed' using errcode = '42501';
      end if;
      if v_existing.status not in ('draft', 'rejected') then
        raise exception 'Only draft or rejected vouchers are editable' using errcode = '23514';
      end if;
      v_date := coalesce(nullif(p_payload ->> 'voucherDate', '')::date, v_existing.voucher_date);
      select * into v_period
      from public.fms_accounting_period period_row
      where period_row.account_set_id = v_existing.account_set_id
        and v_date between period_row.start_date and period_row.end_date;
      if not found then
        raise exception 'Voucher date has no accounting period' using errcode = '23503';
      end if;

      update public.fms_voucher
      set accounting_period_id = v_period.id,
          voucher_type = coalesce(nullif(p_payload ->> 'voucherType', ''), voucher_type),
          voucher_date = v_date,
          fiscal_year = v_period.fiscal_year,
          period_no = v_period.period_no,
          source_type = coalesce(nullif(p_payload ->> 'sourceType', ''), source_type),
          source_id = nullif(p_payload ->> 'sourceId', '')::uuid,
          source_no = nullif(btrim(p_payload ->> 'sourceNo'), ''),
          source_event_code = nullif(btrim(p_payload ->> 'sourceEventCode'), ''),
          summary = btrim(p_payload ->> 'summary'),
          attachments = coalesce(p_payload -> 'attachments', attachments)
      where id = v_id
      returning * into v_saved;

      insert into public.fms_voucher_action(
        tenant_id, account_set_id, voucher_id, action, from_status, to_status,
        actor, snapshot
      ) values (
        v_saved.tenant_id, v_saved.account_set_id, v_saved.id, 'save',
        v_saved.status, v_saved.status, v_actor,
        jsonb_build_object(
          'version', v_saved.version,
          'lineCount', v_saved.line_count,
          'totalDebit', v_saved.total_debit,
          'totalCredit', v_saved.total_credit
        )
      );
      return app_private.fms_voucher_to_secure_json(
        app_private.fms_voucher_raw_json(v_saved.id, false),
        v_saved.created_by_user_id
      );
    end if;
  end if;

  v_saved := public.save_fms_voucher(p_payload);
  return app_private.fms_voucher_to_secure_json(
    app_private.fms_voucher_raw_json(v_saved.id, false),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.transition_fms_voucher_secure(
  p_voucher_id uuid,
  p_action text,
  p_reason text default null,
  p_action_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing public.fms_voucher%rowtype;
  v_saved public.fms_voucher%rowtype;
begin
  select * into v_existing
  from public.fms_voucher voucher_row
  where voucher_row.id = p_voucher_id
    and voucher_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Voucher not found' using errcode = 'P0002';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceVoucherCenter', 'FinanceVoucherCenter:' || initcap(p_action),
    v_existing.created_by_user_id, false
  ) then
    raise exception 'Missing voucher action permission' using errcode = '42501';
  end if;
  v_saved := public.transition_fms_voucher(
    p_voucher_id, p_action, p_reason, p_action_date
  );
  return app_private.fms_voucher_to_secure_json(
    app_private.fms_voucher_raw_json(v_saved.id, false),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.save_fms_cash_flow_allocations_secure(
  p_voucher_id uuid,
  p_allocations jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  select voucher_row.created_by_user_id into v_owner_id
  from public.fms_voucher voucher_row
  where voucher_row.id = p_voucher_id
    and voucher_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Voucher not found' using errcode = 'P0002';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceVoucherCenter', 'FinanceVoucherCenter:Edit', v_owner_id, false
  ) then
    raise exception 'Missing voucher edit permission' using errcode = '42501';
  end if;
  if app_private.resolve_field_access(
    'fms.voucher', 'voucherAmounts', v_owner_id
  ) <> 'edit' then
    raise exception 'Voucher amounts are not editable' using errcode = '42501';
  end if;
  return public.save_fms_cash_flow_allocations(p_voucher_id, p_allocations);
end;
$$;

revoke select, insert, update, delete on table public.fms_voucher
  from anon, authenticated;
revoke select, insert, update, delete on table public.fms_voucher_line
  from anon, authenticated;
revoke select, insert, update, delete on table public.fms_voucher_action
  from anon, authenticated;
revoke select, insert, update, delete on table public.fms_cash_flow_allocation
  from anon, authenticated;

revoke execute on function public.save_fms_voucher(jsonb)
  from public, anon, authenticated;
revoke execute on function public.transition_fms_voucher(uuid, text, text, date)
  from public, anon, authenticated;
revoke execute on function public.fms_voucher_summary(uuid)
  from public, anon, authenticated;
revoke execute on function public.save_fms_cash_flow_allocations(uuid, jsonb)
  from public, anon, authenticated;

grant execute on function public.fms_list_vouchers_secure(
  integer, integer, uuid, text, text, text, text, date, date, uuid[], text
) to authenticated;
grant execute on function public.fms_get_voucher_secure(uuid) to authenticated;
grant execute on function public.fms_voucher_summary_secure(uuid) to authenticated;
grant execute on function public.fms_list_cash_flow_allocations_secure(uuid) to authenticated;
grant execute on function public.save_fms_voucher_secure(jsonb) to authenticated;
grant execute on function public.transition_fms_voucher_secure(uuid, text, text, date)
  to authenticated;
grant execute on function public.save_fms_cash_flow_allocations_secure(uuid, jsonb)
  to authenticated;

revoke execute on function public.fms_list_vouchers_secure(
  integer, integer, uuid, text, text, text, text, date, date, uuid[], text
) from anon;
revoke execute on function public.fms_get_voucher_secure(uuid) from anon;
revoke execute on function public.fms_voucher_summary_secure(uuid) from anon;
revoke execute on function public.fms_list_cash_flow_allocations_secure(uuid) from anon;
revoke execute on function public.save_fms_voucher_secure(jsonb) from anon;
revoke execute on function public.transition_fms_voucher_secure(uuid, text, text, date)
  from anon;
revoke execute on function public.save_fms_cash_flow_allocations_secure(uuid, jsonb)
  from anon;

do $$
begin
  if exists (
    select 1 from public.sys_tenant tenant_row
    where not exists (
      select 1 from public.sys_permission_resource resource_row
      where resource_row.tenant_id = tenant_row.id
        and resource_row.resource_key = 'fms.voucher'
        and resource_row.owner_column = 'created_by_user_id'
    )
  ) then
    raise exception 'Missing fms.voucher permission resource';
  end if;

  if exists (
    select 1
    from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.voucher'
      and (
        select count(*)
        from public.sys_permission_field field_row
        where field_row.resource_id = resource_row.id
          and field_row.enabled
          and field_row.field_key in (
            'voucherAmounts', 'sourceReferences', 'voucherAttachments', 'auditTrail'
          )
      ) <> 4
  ) then
    raise exception 'Unexpected fms.voucher field catalog';
  end if;
end;
$$;

;
