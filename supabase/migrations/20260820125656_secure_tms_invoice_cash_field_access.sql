-- Add tenant-scoped, owner-aware field authorization to invoices and cash transactions.
-- Direct summary/base-table reads no longer expose sensitive finance fields; clients use
-- the secure RPC boundary defined below for list, detail, export and mutation workflows.

alter table public.tms_invoice
  add column if not exists created_by_user_id uuid;

alter table public.tms_cash_transaction
  add column if not exists created_by_user_id uuid;

update public.tms_invoice invoice_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = invoice_row.tenant_id
    and user_row.deleted_at is null
    and (
      lower(user_row.user_email) = lower(invoice_row.create_by)
      or lower(user_row.user_name) = lower(invoice_row.create_by)
      or lower(user_row.nick_name) = lower(invoice_row.create_by)
    )
  order by
    case
      when lower(user_row.user_email) = lower(invoice_row.create_by) then 0
      when lower(user_row.user_name) = lower(invoice_row.create_by) then 1
      else 2
    end,
    user_row.create_time,
    user_row.id
  limit 1
)
where invoice_row.created_by_user_id is null;

update public.tms_cash_transaction transaction_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = transaction_row.tenant_id
    and user_row.deleted_at is null
    and (
      lower(user_row.user_email) = lower(transaction_row.create_by)
      or lower(user_row.user_name) = lower(transaction_row.create_by)
      or lower(user_row.nick_name) = lower(transaction_row.create_by)
    )
  order by
    case
      when lower(user_row.user_email) = lower(transaction_row.create_by) then 0
      when lower(user_row.user_name) = lower(transaction_row.create_by) then 1
      else 2
    end,
    user_row.create_time,
    user_row.id
  limit 1
)
where transaction_row.created_by_user_id is null;

do $$
begin
  if exists (select 1 from public.tms_invoice where created_by_user_id is null) then
    raise exception 'Unable to resolve every invoice creator';
  end if;
  if exists (select 1 from public.tms_cash_transaction where created_by_user_id is null) then
    raise exception 'Unable to resolve every cash transaction creator';
  end if;
end;
$$;

alter table public.tms_invoice
  alter column created_by_user_id set not null;

alter table public.tms_cash_transaction
  alter column created_by_user_id set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_invoice'::regclass
      and conname = 'tms_invoice_created_by_user_tenant_fkey'
  ) then
    alter table public.tms_invoice
      add constraint tms_invoice_created_by_user_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user (id, tenant_id)
      on delete restrict;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.tms_cash_transaction'::regclass
      and conname = 'tms_cash_transaction_created_by_user_tenant_fkey'
  ) then
    alter table public.tms_cash_transaction
      add constraint tms_cash_transaction_created_by_user_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user (id, tenant_id)
      on delete restrict;
  end if;
end;
$$;

create index if not exists tms_invoice_creator_tenant_idx
  on public.tms_invoice (created_by_user_id, tenant_id);

create index if not exists tms_cash_transaction_creator_tenant_idx
  on public.tms_cash_transaction (created_by_user_id, tenant_id);

create or replace function app_private.set_tms_financial_document_creator_identity()
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
      new.created_by_user_id := v_current_user_id;
    elsif new.created_by_user_id is null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and user_row.deleted_at is null
        and (
          lower(user_row.user_email) = lower(new.create_by)
          or lower(user_row.user_name) = lower(new.create_by)
          or lower(user_row.nick_name) = lower(new.create_by)
        )
      order by
        case
          when lower(user_row.user_email) = lower(new.create_by) then 0
          when lower(user_row.user_name) = lower(new.create_by) then 1
          else 2
        end,
        user_row.create_time,
        user_row.id
      limit 1;
    end if;

    if new.created_by_user_id is null then
      raise exception 'Authenticated financial document creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Financial document creator identity is immutable' using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists tms_invoice_creator_identity on public.tms_invoice;
create trigger tms_invoice_creator_identity
before insert or update of created_by_user_id on public.tms_invoice
for each row execute function app_private.set_tms_financial_document_creator_identity();

drop trigger if exists tms_cash_transaction_creator_identity on public.tms_cash_transaction;
create trigger tms_cash_transaction_creator_identity
before insert or update of created_by_user_id on public.tms_cash_transaction
for each row execute function app_private.set_tms_financial_document_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_invoice_cash;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_invoice_cash(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.invoice', '发票',
    'FinanceInvoiceManagement', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'invoiceAmounts', '税率与发票金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'taxIdentity', '纳税人识别号',
      'hidden', 'id_card', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'invoiceAttachments', '发票附件',
      'hidden', 'none', true, 30, '624944977@qq.com', '624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label = excluded.field_label,
        mask_strategy = excluded.mask_strategy,
        owner_override_enabled = excluded.owner_override_enabled,
        sort = excluded.sort,
        sensitive = true,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now();

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.cash_transaction', '收付款流水',
    'FinanceCashTransaction', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label = excluded.resource_label,
        menu_name = excluded.menu_name,
        owner_column = excluded.owner_column,
        enabled = true,
        update_by = excluded.update_by,
        update_time = now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sort, create_by, update_by
  ) values
    (p_tenant_id, v_resource_id, 'transactionAmounts', '收付款与核销金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'bankDetails', '银行流水与资金账户',
      'hidden', 'bank_account', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'voucherEvidence', '收付款凭证',
      'hidden', 'none', true, 30, '624944977@qq.com', '624944977@qq.com')
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

-- Keep existing finance users fully functional on rollout. Tenant administrators can
-- subsequently reduce these grants from the field-permission matrix.
insert into public.sys_role_field_permission (
  tenant_id, role_id, resource_id, field_id, access_level, create_by, update_by
)
select distinct
  resource_row.tenant_id,
  role_menu.role_id,
  resource_row.id,
  field_row.id,
  'edit',
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id = resource_row.tenant_id
 and field_row.resource_id = resource_row.id
join public.sys_menu menu_row
  on menu_row.type = 'menu'
 and (
   (resource_row.resource_key = 'tms.invoice' and menu_row.name = 'FinanceInvoiceManagement')
   or (
     resource_row.resource_key = 'tms.cash_transaction'
     and menu_row.name in ('FinanceCashTransaction', 'FinanceCarrierPaymentApplication')
   )
 )
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key in ('tms.invoice', 'tms.cash_transaction')
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.apply_jsonb_text_access(
  p_data jsonb,
  p_keys text[],
  p_access text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb := coalesce(p_data, '{}'::jsonb);
  v_key text;
begin
  foreach v_key in array p_keys loop
    if p_access = 'hidden' then
      v_result := v_result - v_key;
    elsif p_access = 'masked' and v_result ? v_key then
      v_result := jsonb_set(v_result, array[v_key], '"***"'::jsonb, true);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function app_private.apply_jsonb_document_access(
  p_data jsonb,
  p_keys text[],
  p_access text
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_result jsonb := coalesce(p_data, '{}'::jsonb);
  v_key text;
begin
  foreach v_key in array p_keys loop
    if p_access = 'hidden' then
      v_result := v_result - v_key;
    elsif p_access = 'masked' and v_result ? v_key then
      v_result := jsonb_set(v_result, array[v_key], '[]'::jsonb, true);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function app_private.tms_invoice_to_secure_json(
  p_invoice jsonb,
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
  v_access jsonb := coalesce(p_access, app_private.field_access_map('tms.invoice', p_owner_id));
  v_data jsonb := coalesce(p_invoice, '{}'::jsonb) - 'tenant_id' - 'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'tax_rate', 'amount_excluding_tax', 'tax_amount', 'total_amount',
      'linked_amount', 'unlinked_amount'
    ]::text[],
    coalesce(v_access->>'invoiceAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['tax_number']::text[],
    coalesce(v_access->>'taxIdentity', 'hidden')
  );
  v_data := app_private.apply_jsonb_document_access(
    v_data,
    array['attachments']::text[],
    coalesce(v_access->>'invoiceAttachments', 'hidden')
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.tms_cash_transaction_to_secure_json(
  p_transaction jsonb,
  p_owner_id uuid,
  p_fund_account jsonb default null,
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
    app_private.field_access_map('tms.cash_transaction', p_owner_id)
  );
  v_bank_access text := coalesce(v_access->>'bankDetails', 'hidden');
  v_data jsonb := coalesce(p_transaction, '{}'::jsonb) - 'tenant_id' - 'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['amount', 'allocated_amount', 'unallocated_amount']::text[],
    coalesce(v_access->>'transactionAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['bank_reference']::text[],
    v_bank_access
  );
  v_data := app_private.apply_jsonb_document_access(
    v_data,
    array['voucher_urls']::text[],
    coalesce(v_access->>'voucherEvidence', 'hidden')
  );

  if v_bank_access = 'hidden' then
    v_data := v_data - 'fund_account_id' - 'fund_account';
  elsif v_bank_access = 'masked' then
    v_data := (v_data - 'fund_account_id') || jsonb_build_object(
      'fund_account', case when p_fund_account is null then null else jsonb_build_object(
        'account_code', '***',
        'account_name', '***',
        'account_no_masked', '***'
      ) end
    );
  else
    v_data := v_data || jsonb_build_object('fund_account', p_fund_account);
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.tms_list_invoices_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_direction text default null,
  p_status text default null,
  p_invoice_type text default null,
  p_customer_id uuid default null,
  p_carrier_id uuid default null,
  p_record_id uuid default null,
  p_issue_date_start date default null,
  p_issue_date_end date default null,
  p_keyword text default null,
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
    then 'FinanceInvoiceManagement:Export'
    else 'FinanceInvoiceManagement:View'
  end;
  v_limit integer;
  v_base_access jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid invoice read purpose';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceInvoiceManagement', v_permission, null, false
  ) then
    raise exception 'Missing invoice read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.invoice', null);

  return (
    with filtered as materialized (
      select summary_row as invoice_record, invoice_row.created_by_user_id
      from public.tms_invoice_summary summary_row
      join public.tms_invoice invoice_row
        on invoice_row.id = summary_row.id
       and invoice_row.tenant_id = summary_row.tenant_id
      where (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id)
        and (p_direction is null or summary_row.direction = p_direction)
        and (p_status is null or summary_row.status = p_status)
        and (p_invoice_type is null or summary_row.invoice_type = p_invoice_type)
        and (p_customer_id is null or summary_row.customer_id = p_customer_id)
        and (p_carrier_id is null or summary_row.carrier_id = p_carrier_id)
        and (p_record_id is null or summary_row.id = p_record_id)
        and (p_issue_date_start is null or summary_row.issue_date >= p_issue_date_start)
        and (p_issue_date_end is null or summary_row.issue_date <= p_issue_date_end)
        and (p_ids is null or summary_row.id = any(p_ids))
        and (
          nullif(btrim(p_keyword), '') is null
          or summary_row.invoice_record_no ilike '%' || btrim(p_keyword) || '%'
          or summary_row.invoice_no ilike '%' || btrim(p_keyword) || '%'
          or summary_row.invoice_code ilike '%' || btrim(p_keyword) || '%'
          or summary_row.counterparty_name_snapshot ilike '%' || btrim(p_keyword) || '%'
          or summary_row.invoice_title ilike '%' || btrim(p_keyword) || '%'
          or (
            app_private.resolve_field_access(
              'tms.invoice', 'taxIdentity', invoice_row.created_by_user_id
            ) in ('read', 'edit')
            and summary_row.tax_number ilike '%' || btrim(p_keyword) || '%'
          )
        )
    ), paged as (
      select filtered.*
      from filtered
      order by (filtered.invoice_record).issue_date desc,
               (filtered.invoice_record).create_time desc,
               (filtered.invoice_record).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          app_private.tms_invoice_to_secure_json(
            to_jsonb(paged.invoice_record), paged.created_by_user_id
          )
          order by (paged.invoice_record).issue_date desc,
                   (paged.invoice_record).create_time desc,
                   (paged.invoice_record).id
        )
        from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'fieldAccess', v_base_access
    )
  );
end;
$$;

create or replace function public.tms_get_invoice_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_invoice public.tms_invoice_summary%rowtype;
  v_owner_id uuid;
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

  select summary_row.*
  into v_invoice
  from public.tms_invoice_summary summary_row
  where summary_row.id = p_id
    and (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id);

  if not found then
    return null;
  end if;

  select invoice_row.created_by_user_id
  into v_owner_id
  from public.tms_invoice invoice_row
  where invoice_row.id = v_invoice.id
    and invoice_row.tenant_id = v_invoice.tenant_id;

  return app_private.tms_invoice_to_secure_json(to_jsonb(v_invoice), v_owner_id);
end;
$$;

create or replace function public.tms_find_active_invoice_by_legal_no_secure(
  p_direction text,
  p_invoice_no text,
  p_exclude_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_invoice public.tms_invoice_summary%rowtype;
  v_owner_id uuid;
begin
  if not (
    app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:Add', null, false
    )
    or app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:Edit', null, false
    )
  ) then
    raise exception 'Missing invoice maintenance permission' using errcode = '42501';
  end if;

  select summary_row.*
  into v_invoice
  from public.tms_invoice_summary summary_row
  where summary_row.tenant_id = v_tenant_id
    and summary_row.direction = p_direction
    and summary_row.invoice_no = btrim(p_invoice_no)
    and summary_row.status <> 'voided'
    and (p_exclude_id is null or summary_row.id <> p_exclude_id)
  order by summary_row.create_time
  limit 1;

  if not found then
    return null;
  end if;

  select invoice_row.created_by_user_id
  into v_owner_id
  from public.tms_invoice invoice_row
  where invoice_row.id = v_invoice.id
    and invoice_row.tenant_id = v_invoice.tenant_id;

  return app_private.tms_invoice_to_secure_json(
    to_jsonb(v_invoice), v_owner_id
  ) - 'tax_number' - 'attachments';
end;
$$;

create or replace function public.tms_list_cash_transactions_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_direction text default null,
  p_status text default null,
  p_customer_id uuid default null,
  p_carrier_id uuid default null,
  p_record_id uuid default null,
  p_transaction_date_start date default null,
  p_transaction_date_end date default null,
  p_keyword text default null,
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
    then 'FinanceCashTransaction:Export'
    else 'FinanceCashTransaction:View'
  end;
  v_limit integer;
  v_base_access jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid cash transaction read purpose';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', v_permission, null, false
  ) then
    raise exception 'Missing cash transaction read permission' using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map('tms.cash_transaction', null);

  return (
    with filtered as materialized (
      select
        summary_row as transaction_record,
        transaction_row.created_by_user_id,
        case when account_row.id is null then null else jsonb_build_object(
          'id', account_row.id,
          'account_code', account_row.account_code,
          'account_name', account_row.account_name,
          'account_no_masked', account_row.account_no_masked
        ) end as fund_account
      from public.tms_cash_transaction_summary summary_row
      join public.tms_cash_transaction transaction_row
        on transaction_row.id = summary_row.id
       and transaction_row.tenant_id = summary_row.tenant_id
      left join public.fms_fund_account account_row
        on account_row.id = summary_row.fund_account_id
       and account_row.tenant_id = summary_row.tenant_id
      where (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id)
        and (p_direction is null or summary_row.direction = p_direction)
        and (p_status is null or summary_row.status = p_status)
        and (p_customer_id is null or summary_row.customer_id = p_customer_id)
        and (p_carrier_id is null or summary_row.carrier_id = p_carrier_id)
        and (p_record_id is null or summary_row.id = p_record_id)
        and (
          p_transaction_date_start is null
          or summary_row.transaction_date >= p_transaction_date_start
        )
        and (
          p_transaction_date_end is null
          or summary_row.transaction_date <= p_transaction_date_end
        )
        and (p_ids is null or summary_row.id = any(p_ids))
        and (
          nullif(btrim(p_keyword), '') is null
          or summary_row.transaction_no ilike '%' || btrim(p_keyword) || '%'
          or summary_row.counterparty_name ilike '%' || btrim(p_keyword) || '%'
          or summary_row.remark ilike '%' || btrim(p_keyword) || '%'
          or (
            app_private.resolve_field_access(
              'tms.cash_transaction', 'bankDetails', transaction_row.created_by_user_id
            ) in ('read', 'edit')
            and summary_row.bank_reference ilike '%' || btrim(p_keyword) || '%'
          )
        )
    ), paged as (
      select filtered.*
      from filtered
      order by (filtered.transaction_record).transaction_date desc,
               (filtered.transaction_record).create_time desc,
               (filtered.transaction_record).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          app_private.tms_cash_transaction_to_secure_json(
            to_jsonb(paged.transaction_record),
            paged.created_by_user_id,
            paged.fund_account
          )
          order by (paged.transaction_record).transaction_date desc,
                   (paged.transaction_record).create_time desc,
                   (paged.transaction_record).id
        )
        from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'fieldAccess', v_base_access
    )
  );
end;
$$;

create or replace function public.tms_get_cash_transaction_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_transaction public.tms_cash_transaction_summary%rowtype;
  v_owner_id uuid;
  v_fund_account jsonb;
  v_access jsonb;
  v_amount_access text;
  v_allocations jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:View', null, false
  ) then
    raise exception 'Missing cash transaction detail permission' using errcode = '42501';
  end if;

  select summary_row.*
  into v_transaction
  from public.tms_cash_transaction_summary summary_row
  where summary_row.id = p_id
    and (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id);

  if not found then
    return null;
  end if;

  select
    transaction_row.created_by_user_id,
    case when account_row.id is null then null else jsonb_build_object(
      'id', account_row.id,
      'account_code', account_row.account_code,
      'account_name', account_row.account_name,
      'account_no_masked', account_row.account_no_masked
    ) end
  into v_owner_id, v_fund_account
  from public.tms_cash_transaction transaction_row
  left join public.fms_fund_account account_row
    on account_row.id = transaction_row.fund_account_id
   and account_row.tenant_id = transaction_row.tenant_id
  where transaction_row.id = v_transaction.id
    and transaction_row.tenant_id = v_transaction.tenant_id;

  v_access := app_private.field_access_map('tms.cash_transaction', v_owner_id);
  v_amount_access := coalesce(v_access->>'transactionAmounts', 'hidden');

  if v_transaction.direction = 'payment' then
    select coalesce(jsonb_agg(
      app_private.apply_jsonb_amount_access(
        (to_jsonb(allocation_row) - 'tenant_id') || jsonb_build_object(
          'statement', jsonb_build_object(
            'statement_no', statement_row.statement_no,
            'period_start', statement_row.period_start,
            'period_end', statement_row.period_end
          )
        ),
        array['allocated_amount']::text[],
        v_amount_access
      )
      order by allocation_row.create_time desc, allocation_row.id
    ), '[]'::jsonb)
    into v_allocations
    from public.tms_carrier_cash_allocation allocation_row
    left join public.tms_carrier_statement statement_row
      on statement_row.id = allocation_row.statement_id
     and statement_row.tenant_id = allocation_row.tenant_id
    where allocation_row.transaction_id = p_id
      and allocation_row.tenant_id = v_transaction.tenant_id;
  else
    select coalesce(jsonb_agg(
      app_private.apply_jsonb_amount_access(
        (to_jsonb(allocation_row) - 'tenant_id') || jsonb_build_object(
          'statement', jsonb_build_object(
            'statement_no', statement_row.statement_no,
            'period_start', statement_row.period_start,
            'period_end', statement_row.period_end
          )
        ),
        array['allocated_amount']::text[],
        v_amount_access
      )
      order by allocation_row.create_time desc, allocation_row.id
    ), '[]'::jsonb)
    into v_allocations
    from public.tms_cash_allocation allocation_row
    left join public.tms_customer_statement statement_row
      on statement_row.id = allocation_row.statement_id
     and statement_row.tenant_id = allocation_row.tenant_id
    where allocation_row.transaction_id = p_id
      and allocation_row.tenant_id = v_transaction.tenant_id;
  end if;

  return app_private.tms_cash_transaction_to_secure_json(
    to_jsonb(v_transaction), v_owner_id, v_fund_account, v_access
  ) || jsonb_build_object('allocations', coalesce(v_allocations, '[]'::jsonb));
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
  v_invoice_owner_id uuid;
  v_invoice_amount_access text;
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

  select invoice_row.created_by_user_id
  into v_invoice_owner_id
  from public.tms_invoice invoice_row
  where invoice_row.id = p_invoice_id
    and (app_private.is_platform_super() or invoice_row.tenant_id = v_tenant_id);

  if not found then
    return '[]'::jsonb;
  end if;

  v_invoice_amount_access := app_private.resolve_field_access(
    'tms.invoice', 'invoiceAmounts', v_invoice_owner_id
  );

  return coalesce((
    select jsonb_agg(
      app_private.apply_jsonb_amount_access(
        app_private.apply_jsonb_amount_access(
          to_jsonb(secured.link_record) - 'tenant_id',
          array['statement_amount']::text[],
          secured.statement_access
        ),
        array['linked_amount']::text[],
        v_invoice_amount_access
      )
      || jsonb_build_object(
        'field_access', jsonb_build_object(
          'statementAmounts', secured.statement_access,
          'invoiceAmounts', v_invoice_amount_access
        )
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

create or replace function public.save_tms_invoice_secure(
  p_invoice_id uuid,
  p_direction text,
  p_invoice_type text,
  p_customer_id uuid,
  p_carrier_id uuid,
  p_invoice_title text,
  p_tax_number text,
  p_invoice_code text,
  p_invoice_no text,
  p_issue_date date,
  p_tax_rate numeric,
  p_amount_excluding_tax numeric,
  p_tax_amount numeric,
  p_total_amount numeric,
  p_attachments jsonb,
  p_remark text,
  p_statement_links jsonb,
  p_invoice_record_no text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_existing public.tms_invoice%rowtype;
  v_access jsonb;
  v_statement_links jsonb := coalesce(p_statement_links, '[]'::jsonb);
  v_tax_number text := p_tax_number;
  v_tax_rate numeric := p_tax_rate;
  v_amount_excluding_tax numeric := p_amount_excluding_tax;
  v_tax_amount numeric := p_tax_amount;
  v_total_amount numeric := p_total_amount;
  v_attachments jsonb := coalesce(p_attachments, '[]'::jsonb);
begin
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  if p_invoice_id is null then
    if not app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:Add', null, false
    ) then
      raise exception 'Missing invoice create permission' using errcode = '42501';
    end if;
  else
    if not app_private.can_execute_business_action(
      'FinanceInvoiceManagement', 'FinanceInvoiceManagement:Edit', null, false
    ) then
      raise exception 'Missing invoice edit permission' using errcode = '42501';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(p_invoice_id::text, 932816));
    select invoice_row.*
    into v_existing
    from public.tms_invoice invoice_row
    where invoice_row.id = p_invoice_id
      and (app_private.is_platform_super() or invoice_row.tenant_id = v_tenant_id)
    for update;

    if not found or v_existing.status <> 'draft' then
      raise exception '发票不存在或不是可编辑草稿';
    end if;

    v_access := app_private.field_access_map('tms.invoice', v_existing.created_by_user_id);

    if coalesce(v_access->>'taxIdentity', 'hidden') <> 'edit' then
      v_tax_number := v_existing.tax_number;
    end if;

    if coalesce(v_access->>'invoiceAmounts', 'hidden') <> 'edit' then
      v_tax_rate := v_existing.tax_rate;
      v_amount_excluding_tax := v_existing.amount_excluding_tax;
      v_tax_amount := v_existing.tax_amount;
      v_total_amount := v_existing.total_amount;
      select coalesce(jsonb_agg(jsonb_build_object(
        'statementId', coalesce(
          link_row.customer_statement_id,
          link_row.carrier_statement_id
        ),
        'linkedAmount', link_row.linked_amount
      ) order by link_row.create_time, link_row.id), '[]'::jsonb)
      into v_statement_links
      from public.tms_invoice_statement_link link_row
      where link_row.invoice_id = p_invoice_id
        and link_row.tenant_id = v_existing.tenant_id;
    end if;

    if coalesce(v_access->>'invoiceAttachments', 'hidden') <> 'edit' then
      v_attachments := v_existing.attachments;
    end if;
  end if;

  if jsonb_typeof(v_statement_links) <> 'array' then
    raise exception '关联对账单格式不正确';
  end if;

  if p_invoice_id is null
     or coalesce(v_access->>'invoiceAmounts', 'edit') = 'edit' then
    if p_direction = 'output' and exists (
      select 1
      from jsonb_to_recordset(v_statement_links)
        as item("statementId" uuid, "linkedAmount" numeric)
      left join public.tms_customer_statement statement_row
        on statement_row.id = item."statementId"
       and statement_row.tenant_id = v_tenant_id
       and statement_row.customer_id = p_customer_id
      where statement_row.id is null
         or app_private.resolve_field_access(
           'tms.customer_statement', 'statementAmounts', statement_row.created_by_user_id
         ) not in ('read', 'edit')
    ) then
      raise exception '无权读取所选客户对账金额' using errcode = '42501';
    end if;

    if p_direction = 'input' and exists (
      select 1
      from jsonb_to_recordset(v_statement_links)
        as item("statementId" uuid, "linkedAmount" numeric)
      left join public.tms_carrier_statement statement_row
        on statement_row.id = item."statementId"
       and statement_row.tenant_id = v_tenant_id
       and statement_row.carrier_id = p_carrier_id
      where statement_row.id is null
         or app_private.resolve_field_access(
           'tms.carrier_statement', 'statementAmounts', statement_row.created_by_user_id
         ) not in ('read', 'edit')
    ) then
      raise exception '无权读取所选承运商对账金额' using errcode = '42501';
    end if;
  end if;

  perform set_config('app.document_number.tms_invoice_record', coalesce(p_invoice_record_no, ''), true);
  return public.save_tms_invoice(
    p_invoice_id,
    p_direction,
    p_invoice_type,
    p_customer_id,
    p_carrier_id,
    p_invoice_title,
    v_tax_number,
    p_invoice_code,
    p_invoice_no,
    p_issue_date,
    v_tax_rate,
    v_amount_excluding_tax,
    v_tax_amount,
    v_total_amount,
    v_attachments,
    p_remark,
    v_statement_links,
    p_invoice_record_no
  );
end;
$$;

create or replace function public.create_fms_customer_receipt_secure(
  p_customer_id uuid,
  p_fund_account_id uuid,
  p_transaction_date date,
  p_amount numeric,
  p_payment_method text,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null,
  p_allocations jsonb default '[]'::jsonb,
  p_transaction_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allocations jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:Add', null, false
  ) then
    raise exception 'Missing customer receipt create permission' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'statement_id', coalesce(item.value->>'statementId', item.value->>'statement_id'),
    'amount', item.value->>'amount'
  ) order by item.ordinality), '[]'::jsonb)
  into v_allocations
  from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
    with ordinality as item(value, ordinality);

  return public.create_fms_customer_receipt(
    p_customer_id,
    p_fund_account_id,
    p_transaction_date,
    p_amount,
    p_payment_method,
    p_bank_reference,
    p_voucher_urls,
    p_remark,
    v_allocations,
    p_transaction_no
  );
end;
$$;

create or replace function public.create_fms_carrier_payment_secure(
  p_carrier_id uuid,
  p_fund_account_id uuid,
  p_transaction_date date,
  p_amount numeric,
  p_payment_method text,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null,
  p_allocations jsonb default '[]'::jsonb,
  p_transaction_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_allocations jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:CreatePayment', null, false
  ) then
    raise exception 'Missing carrier payment create permission' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'statement_id', coalesce(item.value->>'statementId', item.value->>'statement_id'),
    'amount', item.value->>'amount'
  ) order by item.ordinality), '[]'::jsonb)
  into v_allocations
  from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
    with ordinality as item(value, ordinality);

  return public.create_fms_carrier_payment(
    p_carrier_id,
    p_fund_account_id,
    p_transaction_date,
    p_amount,
    p_payment_method,
    p_bank_reference,
    p_voucher_urls,
    p_remark,
    v_allocations,
    p_transaction_no
  );
end;
$$;

create or replace function public.allocate_tms_customer_receipt_secure(
  p_transaction_id uuid,
  p_allocations jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_transaction public.tms_cash_transaction%rowtype;
  v_allocations jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:Allocate', null, false
  ) then
    raise exception 'Missing receipt allocation permission' using errcode = '42501';
  end if;

  select transaction_row.*
  into v_transaction
  from public.tms_cash_transaction transaction_row
  where transaction_row.id = p_transaction_id
    and transaction_row.tenant_id = v_tenant_id
    and transaction_row.direction = 'receipt';

  if not found then
    raise exception '客户收款记录不存在';
  end if;
  if app_private.resolve_field_access(
    'tms.cash_transaction', 'transactionAmounts', v_transaction.created_by_user_id
  ) <> 'edit' then
    raise exception '当前字段权限不允许修改收款核销金额' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'statement_id', coalesce(item.value->>'statementId', item.value->>'statement_id'),
    'amount', item.value->>'amount'
  ) order by item.ordinality), '[]'::jsonb)
  into v_allocations
  from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
    with ordinality as item(value, ordinality);

  if exists (
    select 1
    from jsonb_to_recordset(v_allocations)
      as item(statement_id uuid, amount numeric)
    left join public.tms_customer_statement statement_row
      on statement_row.id = item.statement_id
     and statement_row.tenant_id = v_transaction.tenant_id
     and statement_row.customer_id = v_transaction.customer_id
    where statement_row.id is null
       or app_private.resolve_field_access(
         'tms.customer_statement', 'statementAmounts', statement_row.created_by_user_id
       ) not in ('read', 'edit')
       or app_private.resolve_field_access(
         'tms.customer_statement', 'settlementAmounts', statement_row.created_by_user_id
       ) <> 'edit'
  ) then
    raise exception '当前字段权限不允许修改所选客户对账核销金额' using errcode = '42501';
  end if;

  return public.allocate_tms_customer_receipt(p_transaction_id, v_allocations);
end;
$$;

create or replace function public.allocate_tms_carrier_payment_secure(
  p_transaction_id uuid,
  p_allocations jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_transaction public.tms_cash_transaction%rowtype;
  v_allocations jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:Allocate', null, false
  ) then
    raise exception 'Missing payment allocation permission' using errcode = '42501';
  end if;

  select transaction_row.*
  into v_transaction
  from public.tms_cash_transaction transaction_row
  where transaction_row.id = p_transaction_id
    and transaction_row.tenant_id = v_tenant_id
    and transaction_row.direction = 'payment';

  if not found then
    raise exception '承运商付款记录不存在';
  end if;
  if app_private.resolve_field_access(
    'tms.cash_transaction', 'transactionAmounts', v_transaction.created_by_user_id
  ) <> 'edit' then
    raise exception '当前字段权限不允许修改付款核销金额' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'statement_id', coalesce(item.value->>'statementId', item.value->>'statement_id'),
    'amount', item.value->>'amount'
  ) order by item.ordinality), '[]'::jsonb)
  into v_allocations
  from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
    with ordinality as item(value, ordinality);

  if exists (
    select 1
    from jsonb_to_recordset(v_allocations)
      as item(statement_id uuid, amount numeric)
    left join public.tms_carrier_statement statement_row
      on statement_row.id = item.statement_id
     and statement_row.tenant_id = v_transaction.tenant_id
     and statement_row.carrier_id = v_transaction.carrier_id
    where statement_row.id is null
       or app_private.resolve_field_access(
         'tms.carrier_statement', 'statementAmounts', statement_row.created_by_user_id
       ) not in ('read', 'edit')
       or app_private.resolve_field_access(
         'tms.carrier_statement', 'settlementAmounts', statement_row.created_by_user_id
       ) <> 'edit'
  ) then
    raise exception '当前字段权限不允许修改所选承运商对账核销金额' using errcode = '42501';
  end if;

  return public.allocate_tms_carrier_payment(p_transaction_id, v_allocations);
end;
$$;

create or replace function public.reverse_tms_cash_allocation_secure(
  p_allocation_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_allocation public.tms_cash_allocation%rowtype;
  v_transaction public.tms_cash_transaction%rowtype;
  v_statement_owner_id uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:Allocate', null, false
  ) then
    raise exception 'Missing receipt allocation permission' using errcode = '42501';
  end if;

  select allocation_row.*
  into v_allocation
  from public.tms_cash_allocation allocation_row
  where allocation_row.id = p_allocation_id
    and allocation_row.tenant_id = v_tenant_id;

  if not found then
    raise exception '有效核销记录不存在或已撤销';
  end if;

  select transaction_row.*
  into v_transaction
  from public.tms_cash_transaction transaction_row
  where transaction_row.id = v_allocation.transaction_id
    and transaction_row.tenant_id = v_allocation.tenant_id;

  select statement_row.created_by_user_id
  into v_statement_owner_id
  from public.tms_customer_statement statement_row
  where statement_row.id = v_allocation.statement_id
    and statement_row.tenant_id = v_allocation.tenant_id;
  if app_private.resolve_field_access(
    'tms.cash_transaction', 'transactionAmounts', v_transaction.created_by_user_id
  ) <> 'edit'
     or app_private.resolve_field_access(
       'tms.customer_statement', 'settlementAmounts', v_statement_owner_id
     ) <> 'edit' then
    raise exception '当前字段权限不允许撤销该核销金额' using errcode = '42501';
  end if;

  return public.reverse_tms_cash_allocation(p_allocation_id, p_reason);
end;
$$;

create or replace function public.reverse_tms_carrier_cash_allocation_secure(
  p_allocation_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_allocation public.tms_carrier_cash_allocation%rowtype;
  v_transaction public.tms_cash_transaction%rowtype;
  v_statement_owner_id uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:Allocate', null, false
  ) then
    raise exception 'Missing payment allocation permission' using errcode = '42501';
  end if;

  select allocation_row.*
  into v_allocation
  from public.tms_carrier_cash_allocation allocation_row
  where allocation_row.id = p_allocation_id
    and allocation_row.tenant_id = v_tenant_id;

  if not found then
    raise exception '有效付款核销记录不存在或已撤销';
  end if;

  select transaction_row.*
  into v_transaction
  from public.tms_cash_transaction transaction_row
  where transaction_row.id = v_allocation.transaction_id
    and transaction_row.tenant_id = v_allocation.tenant_id;

  select statement_row.created_by_user_id
  into v_statement_owner_id
  from public.tms_carrier_statement statement_row
  where statement_row.id = v_allocation.statement_id
    and statement_row.tenant_id = v_allocation.tenant_id;
  if app_private.resolve_field_access(
    'tms.cash_transaction', 'transactionAmounts', v_transaction.created_by_user_id
  ) <> 'edit'
     or app_private.resolve_field_access(
       'tms.carrier_statement', 'settlementAmounts', v_statement_owner_id
     ) <> 'edit' then
    raise exception '当前字段权限不允许撤销该核销金额' using errcode = '42501';
  end if;

  return public.reverse_tms_carrier_cash_allocation(p_allocation_id, p_reason);
end;
$$;

create or replace function public.void_tms_cash_transaction_secure(
  p_transaction_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:Void', null, false
  ) then
    raise exception 'Missing cash transaction void permission' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.tms_cash_transaction transaction_row
    where transaction_row.id = p_transaction_id
      and transaction_row.tenant_id = v_tenant_id
  ) then
    raise exception '收付款记录不存在或已作废';
  end if;
  return public.void_tms_cash_transaction(p_transaction_id, p_reason);
end;
$$;

create or replace function public.update_tms_invoice_status_secure(
  p_invoice_id uuid,
  p_action text,
  p_remark text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if p_action <> 'void' then
    raise exception '不支持的发票状态操作';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceInvoiceManagement', 'FinanceInvoiceManagement:Void', null, false
  ) then
    raise exception 'Missing invoice void permission' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.tms_invoice invoice_row
    where invoice_row.id = p_invoice_id
      and invoice_row.tenant_id = v_tenant_id
  ) then
    raise exception '发票不存在或无权访问';
  end if;
  return public.update_tms_invoice_status(p_invoice_id, p_action, p_remark);
end;
$$;

create or replace function public.tms_get_invoice_compliance_audit_secure(p_invoice_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_invoice public.tms_invoice%rowtype;
  v_access jsonb;
  v_statement_links jsonb;
  v_duplicates jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceInvoiceManagement', 'FinanceInvoiceManagement:AiAudit', null, false
  ) then
    raise exception 'Missing invoice AI audit permission' using errcode = '42501';
  end if;

  select invoice_row.*
  into v_invoice
  from public.tms_invoice invoice_row
  where invoice_row.id = p_invoice_id
    and invoice_row.tenant_id = v_tenant_id;

  if not found then
    return null;
  end if;

  v_access := app_private.field_access_map('tms.invoice', v_invoice.created_by_user_id);
  if coalesce(v_access->>'invoiceAmounts', 'hidden') not in ('read', 'edit')
     or coalesce(v_access->>'taxIdentity', 'hidden') not in ('read', 'edit')
     or coalesce(v_access->>'invoiceAttachments', 'hidden') not in ('read', 'edit') then
    raise exception '当前字段权限不足，无法读取发票金额、税号或附件进行合规审核'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.tms_invoice_statement_link link_row
    left join public.tms_customer_statement customer_statement
      on link_row.customer_statement_id = customer_statement.id
     and link_row.tenant_id = customer_statement.tenant_id
    left join public.tms_carrier_statement carrier_statement
      on link_row.carrier_statement_id = carrier_statement.id
     and link_row.tenant_id = carrier_statement.tenant_id
    where link_row.invoice_id = p_invoice_id
      and (
        (
          link_row.customer_statement_id is not null
          and app_private.resolve_field_access(
            'tms.customer_statement', 'statementAmounts', customer_statement.created_by_user_id
          ) not in ('read', 'edit')
        )
        or (
          link_row.carrier_statement_id is not null
          and app_private.resolve_field_access(
            'tms.carrier_statement', 'statementAmounts', carrier_statement.created_by_user_id
          ) not in ('read', 'edit')
        )
      )
  ) then
    raise exception '当前字段权限不足，无法读取关联对账金额进行合规审核'
      using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(link_row) - 'tenant_id'
    order by link_row.period_end, link_row.id), '[]'::jsonb)
  into v_statement_links
  from public.tms_invoice_detail_link link_row
  where link_row.invoice_id = p_invoice_id
    and link_row.tenant_id = v_invoice.tenant_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', duplicate_row.id,
    'status', duplicate_row.status,
    'invoice_record_no', duplicate_row.invoice_record_no,
    'invoice_code', duplicate_row.invoice_code,
    'invoice_no', duplicate_row.invoice_no
  ) order by duplicate_row.create_time, duplicate_row.id), '[]'::jsonb)
  into v_duplicates
  from public.tms_invoice duplicate_row
  where duplicate_row.tenant_id = v_invoice.tenant_id
    and duplicate_row.id <> v_invoice.id
    and duplicate_row.status <> 'voided'
    and duplicate_row.invoice_no = v_invoice.invoice_no
    and (
      nullif(v_invoice.invoice_code, '') is null
      or duplicate_row.invoice_code = v_invoice.invoice_code
    );

  return jsonb_build_object(
    'invoice', to_jsonb(v_invoice) - 'tenant_id' - 'created_by_user_id',
    'statementLinks', v_statement_links,
    'duplicateInvoices', v_duplicates
  );
end;
$$;

create or replace function public.tms_list_cash_bank_references_ai_secure(
  p_limit integer default 5000
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'FinanceCashTransaction', 'FinanceCashTransaction:Import', null, false
  ) then
    raise exception 'Missing bank statement import permission' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'direction', permitted.direction,
      'bank_reference', permitted.bank_reference
    ) order by permitted.id)
    from (
      select transaction_row.id, transaction_row.direction, transaction_row.bank_reference
      from public.tms_cash_transaction transaction_row
      where transaction_row.tenant_id = v_tenant_id
        and transaction_row.bank_reference is not null
        and app_private.resolve_field_access(
          'tms.cash_transaction', 'bankDetails', transaction_row.created_by_user_id
        ) in ('read', 'edit')
      order by transaction_row.id
      limit least(5000, greatest(coalesce(p_limit, 5000), 1))
    ) permitted
  ), '[]'::jsonb);
end;
$$;

create or replace function app_private.assert_customer_delete_scope(p_customer_ids uuid[])
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action(
    'TmsCustomer', 'TmsCustomer:Delete', null, false
  ) then
    raise exception 'Missing customer delete permission' using errcode = '42501';
  end if;
  if coalesce(array_length(p_customer_ids, 1), 0) = 0 then
    raise exception '请选择客户';
  end if;
  if not app_private.is_platform_super() and exists (
    select 1
    from unnest(p_customer_ids) requested(customer_id)
    left join public.tms_customer customer_row
      on customer_row.id = requested.customer_id
     and customer_row.tenant_id = v_tenant_id
    where customer_row.id is null
  ) then
    raise exception '无权读取或清理其他租户的客户依赖' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.get_tms_customer_delete_dependencies_secure(
  p_customer_ids uuid[]
)
returns table(customer_id uuid, dependency_code text, dependency_count bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.assert_customer_delete_scope(p_customer_ids);
  return query
  select dependency_row.*
  from public.get_tms_customer_delete_dependencies(p_customer_ids) dependency_row;
end;
$$;

create or replace function public.get_tms_customer_delete_dependency_details_secure(
  p_customer_ids uuid[]
)
returns table(
  customer_id uuid,
  dependency_code text,
  record_id uuid,
  target_id uuid,
  record_no text,
  record_summary text,
  record_status text,
  record_amount numeric,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.assert_customer_delete_scope(p_customer_ids);
  return query
  select
    detail_row.customer_id,
    detail_row.dependency_code,
    detail_row.record_id,
    detail_row.target_id,
    detail_row.record_no,
    case
      when app_private.is_platform_super() then detail_row.record_summary
      when detail_row.dependency_code = 'cash_transaction' then null
      else detail_row.record_summary
    end,
    detail_row.record_status,
    case when app_private.is_platform_super() then detail_row.record_amount else null end,
    detail_row.created_at
  from public.get_tms_customer_delete_dependency_details(p_customer_ids) detail_row;
end;
$$;

create or replace function public.get_tms_customer_delete_safe_cleanup_candidates_secure(
  p_customer_ids uuid[]
)
returns table(customer_id uuid, dependency_code text, record_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform app_private.assert_customer_delete_scope(p_customer_ids);
  return query
  select candidate_row.*
  from public.get_tms_customer_delete_safe_cleanup_candidates(p_customer_ids) candidate_row;
end;
$$;

create or replace function public.cleanup_tms_customer_safe_delete_dependencies_secure(
  p_customer_ids uuid[]
)
returns table(dependency_code text, deleted_count bigint)
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_private.assert_customer_delete_scope(p_customer_ids);
  return query
  select cleanup_row.*
  from public.cleanup_tms_customer_safe_delete_dependencies(p_customer_ids) cleanup_row;
end;
$$;

-- These established workflows already enforce platform-super or tenant/lifecycle rules.
-- SECURITY DEFINER keeps them functional after direct table writes are revoked.
alter function public.commit_ai_bank_statement_batch(uuid, jsonb) security definer;
alter function public.execute_fms_carrier_payment_application(
  uuid, uuid, date, text, jsonb, text
) security definer;
alter function public.execute_tms_carrier_payment_application(
  uuid, date, text, jsonb
) security definer;
alter function public.execute_tms_carrier_payment_application(
  uuid, date, text, jsonb, text
) security definer;

-- Remove direct Data API mutation/read paths that could bypass field authorization.
revoke all on table
  public.tms_invoice_summary,
  public.tms_cash_transaction_summary
from public, anon, authenticated;

revoke select, insert, update on table public.tms_invoice
  from public, anon, authenticated;
revoke select, insert, update, delete on table public.tms_cash_transaction
  from public, anon, authenticated;
revoke select, insert, update, delete on table
  public.tms_cash_allocation,
  public.tms_carrier_cash_allocation,
  public.tms_invoice_statement_link
from public, anon, authenticated;

-- Invoice deletion remains a button/RLS-controlled operation. Only the identifier is
-- readable directly; every business detail is returned through secure RPCs.
grant select (id) on table public.tms_invoice to authenticated;

grant select on table
  public.tms_invoice_summary,
  public.tms_cash_transaction_summary
to service_role;
grant all on table
  public.tms_invoice,
  public.tms_cash_transaction,
  public.tms_cash_allocation,
  public.tms_carrier_cash_allocation,
  public.tms_invoice_statement_link
to service_role;

revoke execute on function public.save_tms_invoice(
  uuid, text, text, uuid, uuid, text, text, text, text, date,
  numeric, numeric, numeric, numeric, jsonb, text, jsonb
) from public, anon, authenticated;
revoke execute on function public.save_tms_invoice(
  uuid, text, text, uuid, uuid, text, text, text, text, date,
  numeric, numeric, numeric, numeric, jsonb, text, jsonb, text
) from public, anon, authenticated;
revoke execute on function public.create_fms_customer_receipt(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) from public, anon, authenticated;
revoke execute on function public.create_fms_carrier_payment(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) from public, anon, authenticated;
revoke execute on function public.allocate_tms_customer_receipt(uuid, jsonb)
  from public, anon, authenticated;
revoke execute on function public.allocate_tms_carrier_payment(uuid, jsonb)
  from public, anon, authenticated;
revoke execute on function public.reverse_tms_cash_allocation(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.reverse_tms_carrier_cash_allocation(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.void_tms_cash_transaction(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.update_tms_invoice_status(uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.get_tms_customer_delete_dependencies(uuid[])
  from public, anon, authenticated;
revoke execute on function public.get_tms_customer_delete_dependency_details(uuid[])
  from public, anon, authenticated;
revoke execute on function public.get_tms_customer_delete_safe_cleanup_candidates(uuid[])
  from public, anon, authenticated;
revoke execute on function public.cleanup_tms_customer_safe_delete_dependencies(uuid[])
  from public, anon, authenticated;

revoke execute on function public.tms_list_invoices_secure(
  integer, integer, text, text, text, uuid, uuid, uuid, date, date, text, uuid[], text
) from public, anon;
revoke execute on function public.tms_get_invoice_secure(uuid) from public, anon;
revoke execute on function public.tms_find_active_invoice_by_legal_no_secure(text, text, uuid)
  from public, anon;
revoke execute on function public.tms_list_cash_transactions_secure(
  integer, integer, text, text, uuid, uuid, uuid, date, date, text, uuid[], text
) from public, anon;
revoke execute on function public.tms_get_cash_transaction_secure(uuid) from public, anon;
revoke execute on function public.save_tms_invoice_secure(
  uuid, text, text, uuid, uuid, text, text, text, text, date,
  numeric, numeric, numeric, numeric, jsonb, text, jsonb, text
) from public, anon;
revoke execute on function public.create_fms_customer_receipt_secure(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) from public, anon;
revoke execute on function public.create_fms_carrier_payment_secure(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) from public, anon;
revoke execute on function public.allocate_tms_customer_receipt_secure(uuid, jsonb)
  from public, anon;
revoke execute on function public.allocate_tms_carrier_payment_secure(uuid, jsonb)
  from public, anon;
revoke execute on function public.reverse_tms_cash_allocation_secure(uuid, text)
  from public, anon;
revoke execute on function public.reverse_tms_carrier_cash_allocation_secure(uuid, text)
  from public, anon;
revoke execute on function public.void_tms_cash_transaction_secure(uuid, text)
  from public, anon;
revoke execute on function public.update_tms_invoice_status_secure(uuid, text, text)
  from public, anon;
revoke execute on function public.tms_get_invoice_compliance_audit_secure(uuid)
  from public, anon;
revoke execute on function public.tms_list_cash_bank_references_ai_secure(integer)
  from public, anon;
revoke execute on function public.get_tms_customer_delete_dependencies_secure(uuid[])
  from public, anon;
revoke execute on function public.get_tms_customer_delete_dependency_details_secure(uuid[])
  from public, anon;
revoke execute on function public.get_tms_customer_delete_safe_cleanup_candidates_secure(uuid[])
  from public, anon;
revoke execute on function public.cleanup_tms_customer_safe_delete_dependencies_secure(uuid[])
  from public, anon;

grant execute on function public.tms_list_invoices_secure(
  integer, integer, text, text, text, uuid, uuid, uuid, date, date, text, uuid[], text
) to authenticated, service_role;
grant execute on function public.tms_get_invoice_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_find_active_invoice_by_legal_no_secure(text, text, uuid)
  to authenticated, service_role;
grant execute on function public.tms_list_cash_transactions_secure(
  integer, integer, text, text, uuid, uuid, uuid, date, date, text, uuid[], text
) to authenticated, service_role;
grant execute on function public.tms_get_cash_transaction_secure(uuid)
  to authenticated, service_role;
grant execute on function public.save_tms_invoice_secure(
  uuid, text, text, uuid, uuid, text, text, text, text, date,
  numeric, numeric, numeric, numeric, jsonb, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.create_fms_customer_receipt_secure(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.create_fms_carrier_payment_secure(
  uuid, uuid, date, numeric, text, text, jsonb, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.allocate_tms_customer_receipt_secure(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.allocate_tms_carrier_payment_secure(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.reverse_tms_cash_allocation_secure(uuid, text)
  to authenticated, service_role;
grant execute on function public.reverse_tms_carrier_cash_allocation_secure(uuid, text)
  to authenticated, service_role;
grant execute on function public.void_tms_cash_transaction_secure(uuid, text)
  to authenticated, service_role;
grant execute on function public.update_tms_invoice_status_secure(uuid, text, text)
  to authenticated, service_role;
grant execute on function public.tms_get_invoice_compliance_audit_secure(uuid)
  to authenticated, service_role;
grant execute on function public.tms_list_cash_bank_references_ai_secure(integer)
  to authenticated, service_role;
grant execute on function public.get_tms_customer_delete_dependencies_secure(uuid[])
  to authenticated, service_role;
grant execute on function public.get_tms_customer_delete_dependency_details_secure(uuid[])
  to authenticated, service_role;
grant execute on function public.get_tms_customer_delete_safe_cleanup_candidates_secure(uuid[])
  to authenticated, service_role;
grant execute on function public.cleanup_tms_customer_safe_delete_dependencies_secure(uuid[])
  to authenticated, service_role;

;
