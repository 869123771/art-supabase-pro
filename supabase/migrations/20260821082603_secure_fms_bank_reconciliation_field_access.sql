-- Secure bank reconciliation batches, statement lines, matches, and candidate reads.
-- Direct table/view access is replaced with tenant-scoped, field-aware RPCs.

alter table public.fms_bank_reconciliation_batch
  add column if not exists created_by_user_id uuid;

update public.fms_bank_reconciliation_batch batch_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = batch_row.tenant_id
    and lower(user_row.user_email) = lower(batch_row.create_by)
  order by user_row.create_time, user_row.id
  limit 1
)
where batch_row.created_by_user_id is null
  and nullif(btrim(coalesce(batch_row.create_by, '')), '') is not null;

do $$
begin
  if exists (
    select 1
    from public.fms_bank_reconciliation_batch
    where created_by_user_id is null
  ) then
    raise exception 'Unable to backfill fms_bank_reconciliation_batch.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_bank_reconciliation_batch
  alter column created_by_user_id set not null;

create index if not exists fms_bank_reconciliation_batch_tenant_creator_idx
  on public.fms_bank_reconciliation_batch(tenant_id, created_by_user_id);

create index if not exists fms_bank_reconciliation_batch_creator_tenant_idx
  on public.fms_bank_reconciliation_batch(created_by_user_id, tenant_id);

alter table public.fms_bank_reconciliation_batch
  drop constraint if exists fms_bank_reconciliation_batch_creator_tenant_fkey;

alter table public.fms_bank_reconciliation_batch
  add constraint fms_bank_reconciliation_batch_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_bank_reconciliation_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.created_by_user_id is null then
      new.created_by_user_id := app_private.current_app_user_id();
    end if;
    if new.created_by_user_id is null
       and nullif(btrim(coalesce(new.create_by, '')), '') is not null then
      select user_row.id
      into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve bank reconciliation creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Bank reconciliation creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_bank_reconciliation_creator_identity
  on public.fms_bank_reconciliation_batch;
create trigger fms_bank_reconciliation_creator_identity
before insert or update of created_by_user_id
on public.fms_bank_reconciliation_batch
for each row execute function app_private.set_fms_bank_reconciliation_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_bank_reconciliation;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_bank_reconciliation(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'fms.bank_reconciliation', '银行对账',
    'FinanceBankReconciliation', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'accountDetails', '对账账户与交易对方信息',
      'hidden', 'bank_account', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'statementAmounts', '对账余额、流水与匹配金额',
      'hidden', 'amount', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'bankReferences', '银行参考号、流水摘要与来源文件',
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
 and menu_row.name = 'FinanceBankReconciliation'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'fms.bank_reconciliation'
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.fms_bank_reconciliation_batch_raw_json(p_batch_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(summary_row)
    - 'tenant_id'
    - 'created_by_user_id'
  from public.fms_bank_reconciliation_batch_summary summary_row
  join public.fms_bank_reconciliation_batch batch_row
    on batch_row.id = summary_row.id
   and batch_row.tenant_id = summary_row.tenant_id
  where summary_row.id = p_batch_id
    and summary_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_bank_reconciliation_batch_to_secure_json(
  p_batch jsonb,
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
    app_private.field_access_map('fms.bank_reconciliation', p_owner_id)
  );
  v_data jsonb := coalesce(p_batch, '{}'::jsonb)
    - 'tenant_id'
    - 'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['account_no_masked']::text[],
    coalesce(v_access->>'accountDetails', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array[
      'opening_balance', 'closing_balance', 'statement_inflow_amount',
      'statement_outflow_amount', 'matched_amount', 'calculated_closing_balance',
      'statement_balance_difference'
    ]::text[],
    coalesce(v_access->>'statementAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['imported_file_name']::text[],
    coalesce(v_access->>'bankReferences', 'hidden')
  );
  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_bank_statement_line_raw_json(p_line_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select to_jsonb(summary_row)
    - 'tenant_id'
    - 'import_hash'
  from public.fms_bank_statement_line_summary summary_row
  join public.fms_bank_reconciliation_batch batch_row
    on batch_row.id = summary_row.batch_id
   and batch_row.tenant_id = summary_row.tenant_id
  where summary_row.id = p_line_id
    and summary_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_bank_statement_line_to_secure_json(
  p_line jsonb,
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
    app_private.field_access_map('fms.bank_reconciliation', p_owner_id)
  );
  v_data jsonb := coalesce(p_line, '{}'::jsonb)
    - 'tenant_id'
    - 'import_hash';
begin
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['counterparty_name', 'counterparty_account_masked']::text[],
    coalesce(v_access->>'accountDetails', 'hidden')
  );
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['amount', 'statement_balance', 'matched_amount', 'remaining_amount']::text[],
    coalesce(v_access->>'statementAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['bank_reference', 'bank_serial_no', 'bank_memo']::text[],
    coalesce(v_access->>'bankReferences', 'hidden')
  );
  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_bank_statement_match_to_secure_json(
  p_match_id uuid,
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
    app_private.field_access_map('fms.bank_reconciliation', p_owner_id)
  );
  v_data jsonb;
  v_ledger jsonb;
begin
  select jsonb_build_object(
    'id', match_row.id,
    'statement_line_id', match_row.statement_line_id,
    'ledger_entry_id', match_row.ledger_entry_id,
    'matched_amount', match_row.matched_amount,
    'match_type', match_row.match_type,
    'confidence_score', match_row.confidence_score,
    'match_remark', match_row.match_remark,
    'matched_by', match_row.matched_by,
    'matched_at', match_row.matched_at
  ), jsonb_build_object(
    'id', ledger_row.id,
    'entry_date', ledger_row.entry_date,
    'summary', ledger_row.summary,
    'amount', ledger_row.amount,
    'source_no', ledger_row.source_no,
    'bank_reference', ledger_row.bank_reference
  )
  into v_data, v_ledger
  from public.fms_bank_statement_match match_row
  join public.fms_bank_statement_line line_row
    on line_row.id = match_row.statement_line_id
   and line_row.tenant_id = match_row.tenant_id
  join public.fms_bank_reconciliation_batch batch_row
    on batch_row.id = line_row.batch_id
   and batch_row.tenant_id = line_row.tenant_id
  join public.fms_fund_ledger_entry ledger_row
    on ledger_row.id = match_row.ledger_entry_id
   and ledger_row.tenant_id = match_row.tenant_id
  where match_row.id = p_match_id
    and match_row.tenant_id = app_private.current_user_tenant_id();

  if v_data is null then
    return null;
  end if;
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['matched_amount']::text[],
    coalesce(v_access->>'statementAmounts', 'hidden')
  );
  v_ledger := app_private.apply_jsonb_amount_access(
    v_ledger,
    array['amount']::text[],
    coalesce(v_access->>'statementAmounts', 'hidden')
  );
  v_ledger := app_private.apply_jsonb_text_access(
    v_ledger,
    array['source_no', 'bank_reference']::text[],
    coalesce(v_access->>'bankReferences', 'hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['match_remark']::text[],
    coalesce(v_access->>'bankReferences', 'hidden')
  );
  return v_data || jsonb_build_object(
    'ledger_entry', v_ledger,
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_bank_reconciliations_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_account_set_id uuid default null,
  p_fund_account_id uuid default null,
  p_status text default null,
  p_keyword text default null,
  p_statement_start_date date default null,
  p_statement_end_date date default null,
  p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := least(greatest(coalesce(p_to, 19) - v_from + 1, 1), 1000);
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map('fms.bank_reconciliation', null);
  v_row record;
begin
  if p_tenant_id is not null and p_tenant_id <> v_tenant_id then
    raise exception 'Cross-tenant bank reconciliation access is forbidden'
      using errcode = '42501';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceBankReconciliation', null, null, false
  ) then
    raise exception 'Missing bank reconciliation menu permission'
      using errcode = '42501';
  end if;

  select count(*)::integer
  into v_total
  from public.fms_bank_reconciliation_batch_summary summary_row
  join public.fms_bank_reconciliation_batch batch_row
    on batch_row.id = summary_row.id
   and batch_row.tenant_id = summary_row.tenant_id
  where summary_row.tenant_id = v_tenant_id
    and (p_account_set_id is null or summary_row.account_set_id = p_account_set_id)
    and (p_fund_account_id is null or summary_row.fund_account_id = p_fund_account_id)
    and (p_status is null or summary_row.status = p_status)
    and (p_statement_start_date is null or summary_row.statement_end_date >= p_statement_start_date)
    and (p_statement_end_date is null or summary_row.statement_start_date <= p_statement_end_date)
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or summary_row.batch_no ilike '%' || btrim(p_keyword) || '%'
      or summary_row.account_name ilike '%' || btrim(p_keyword) || '%'
      or (
        app_private.resolve_field_access(
          'fms.bank_reconciliation', 'accountDetails', batch_row.created_by_user_id
        ) in ('read', 'edit')
        and summary_row.account_no_masked ilike '%' || btrim(p_keyword) || '%'
      )
      or (
        app_private.resolve_field_access(
          'fms.bank_reconciliation', 'bankReferences', batch_row.created_by_user_id
        ) in ('read', 'edit')
        and summary_row.imported_file_name ilike '%' || btrim(p_keyword) || '%'
      )
    );

  for v_row in
    select summary_row.id, batch_row.created_by_user_id
    from public.fms_bank_reconciliation_batch_summary summary_row
    join public.fms_bank_reconciliation_batch batch_row
      on batch_row.id = summary_row.id
     and batch_row.tenant_id = summary_row.tenant_id
    where summary_row.tenant_id = v_tenant_id
      and (p_account_set_id is null or summary_row.account_set_id = p_account_set_id)
      and (p_fund_account_id is null or summary_row.fund_account_id = p_fund_account_id)
      and (p_status is null or summary_row.status = p_status)
      and (p_statement_start_date is null or summary_row.statement_end_date >= p_statement_start_date)
      and (p_statement_end_date is null or summary_row.statement_start_date <= p_statement_end_date)
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or summary_row.batch_no ilike '%' || btrim(p_keyword) || '%'
        or summary_row.account_name ilike '%' || btrim(p_keyword) || '%'
        or (
          app_private.resolve_field_access(
            'fms.bank_reconciliation', 'accountDetails', batch_row.created_by_user_id
          ) in ('read', 'edit')
          and summary_row.account_no_masked ilike '%' || btrim(p_keyword) || '%'
        )
        or (
          app_private.resolve_field_access(
            'fms.bank_reconciliation', 'bankReferences', batch_row.created_by_user_id
          ) in ('read', 'edit')
          and summary_row.imported_file_name ilike '%' || btrim(p_keyword) || '%'
        )
      )
    order by summary_row.statement_end_date desc, summary_row.create_time desc, summary_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_bank_reconciliation_batch_to_secure_json(
        app_private.fms_bank_reconciliation_batch_raw_json(v_row.id),
        v_row.created_by_user_id
      )
    );
  end loop;

  return jsonb_build_object(
    'records', v_records,
    'total', coalesce(v_total, 0),
    'field_access', v_base_access
  );
end;
$$;

create or replace function public.fms_get_bank_reconciliation_secure(p_batch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'FinanceBankReconciliation', null, null, false
  ) then
    raise exception 'Missing bank reconciliation menu permission'
      using errcode = '42501';
  end if;
  select batch_row.created_by_user_id
  into v_owner_id
  from public.fms_bank_reconciliation_batch batch_row
  where batch_row.id = p_batch_id
    and batch_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Bank reconciliation batch does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_result := app_private.fms_bank_reconciliation_batch_to_secure_json(
    app_private.fms_bank_reconciliation_batch_raw_json(p_batch_id),
    v_owner_id
  );
  return v_result;
end;
$$;

create or replace function public.fms_list_bank_statement_lines_secure(p_batch_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_access jsonb;
  v_records jsonb := '[]'::jsonb;
  v_line_id uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceBankReconciliation', null, null, false
  ) then
    raise exception 'Missing bank reconciliation menu permission'
      using errcode = '42501';
  end if;
  select batch_row.created_by_user_id
  into v_owner_id
  from public.fms_bank_reconciliation_batch batch_row
  where batch_row.id = p_batch_id
    and batch_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Bank reconciliation batch does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_access := app_private.field_access_map('fms.bank_reconciliation', v_owner_id);
  for v_line_id in
    select line_row.id
    from public.fms_bank_statement_line line_row
    where line_row.batch_id = p_batch_id
      and line_row.tenant_id = app_private.current_user_tenant_id()
    order by line_row.transaction_date, line_row.line_no, line_row.id
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_bank_statement_line_to_secure_json(
        app_private.fms_bank_statement_line_raw_json(v_line_id),
        v_owner_id,
        v_access
      )
    );
  end loop;
  return jsonb_build_object('records', v_records, 'field_access', v_access);
end;
$$;

create or replace function public.fms_list_bank_statement_matches_secure(p_statement_line_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
  v_access jsonb;
  v_records jsonb := '[]'::jsonb;
  v_match_id uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceBankReconciliation', null, null, false
  ) then
    raise exception 'Missing bank reconciliation menu permission'
      using errcode = '42501';
  end if;
  select batch_row.created_by_user_id
  into v_owner_id
  from public.fms_bank_statement_line line_row
  join public.fms_bank_reconciliation_batch batch_row
    on batch_row.id = line_row.batch_id
   and batch_row.tenant_id = line_row.tenant_id
  where line_row.id = p_statement_line_id
    and line_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Bank statement line does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_access := app_private.field_access_map('fms.bank_reconciliation', v_owner_id);
  for v_match_id in
    select match_row.id
    from public.fms_bank_statement_match match_row
    where match_row.statement_line_id = p_statement_line_id
      and match_row.tenant_id = app_private.current_user_tenant_id()
    order by match_row.matched_at, match_row.id
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_bank_statement_match_to_secure_json(
        v_match_id,
        v_owner_id,
        v_access
      )
    );
  end loop;
  return v_records;
end;
$$;

create or replace function public.fms_list_bank_match_candidates_secure(
  p_statement_line_id uuid,
  p_date_tolerance_days integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_line record;
  v_owner_id uuid;
  v_access jsonb;
  v_records jsonb := '[]'::jsonb;
  v_record jsonb;
  v_row record;
begin
  if not app_private.can_execute_business_action(
    'FinanceBankReconciliation', null, null, false
  ) then
    raise exception 'Missing bank reconciliation menu permission'
      using errcode = '42501';
  end if;
  if p_date_tolerance_days not between 0 and 90 then
    raise exception 'Date tolerance must be between 0 and 90 days'
      using errcode = '22023';
  end if;
  select line_row.*, batch_row.created_by_user_id as owner_id
  into v_line
  from public.fms_bank_statement_line line_row
  join public.fms_bank_reconciliation_batch batch_row
    on batch_row.id = line_row.batch_id
   and batch_row.tenant_id = line_row.tenant_id
  where line_row.id = p_statement_line_id
    and line_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Bank statement line does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_owner_id := v_line.owner_id;
  v_access := app_private.field_access_map('fms.bank_reconciliation', v_owner_id);
  for v_row in
    select ledger_row.id, ledger_row.entry_date, ledger_row.summary,
      ledger_row.amount, ledger_row.source_no, ledger_row.bank_reference
    from public.fms_fund_ledger_entry ledger_row
    where ledger_row.tenant_id = app_private.current_user_tenant_id()
      and ledger_row.fund_account_id = v_line.fund_account_id
      and ledger_row.direction = v_line.direction
      and ledger_row.entry_date between
        v_line.transaction_date - p_date_tolerance_days
        and v_line.transaction_date + p_date_tolerance_days
    order by abs(ledger_row.entry_date - v_line.transaction_date), ledger_row.entry_date, ledger_row.id
    limit 200
  loop
    v_record := jsonb_build_object(
      'id', v_row.id,
      'entry_date', v_row.entry_date,
      'summary', v_row.summary,
      'amount', v_row.amount,
      'source_no', v_row.source_no,
      'bank_reference', v_row.bank_reference
    );
    v_record := app_private.apply_jsonb_amount_access(
      v_record,
      array['amount']::text[],
      coalesce(v_access->>'statementAmounts', 'hidden')
    );
    v_record := app_private.apply_jsonb_text_access(
      v_record,
      array['source_no', 'bank_reference']::text[],
      coalesce(v_access->>'bankReferences', 'hidden')
    );
    v_records := v_records || jsonb_build_array(v_record);
  end loop;
  return jsonb_build_object('records', v_records, 'field_access', v_access);
end;
$$;

create or replace function public.import_fms_bank_reconciliation_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_saved public.fms_bank_reconciliation_batch%rowtype;
begin
  if not exists (
    select 1
    from public.fms_fund_account account_row
    where account_row.id = (p_payload->>'fundAccountId')::uuid
      and account_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Fund account does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_saved := public.import_fms_bank_reconciliation(p_payload);
  if v_saved.tenant_id <> app_private.current_user_tenant_id() then
    raise exception 'Cross-tenant bank reconciliation import is forbidden'
      using errcode = '42501';
  end if;
  return app_private.fms_bank_reconciliation_batch_to_secure_json(
    app_private.fms_bank_reconciliation_batch_raw_json(v_saved.id),
    v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.auto_match_fms_bank_reconciliation_secure(
  p_batch_id uuid,
  p_date_tolerance_days integer default 3
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.fms_bank_reconciliation_batch batch_row
    where batch_row.id = p_batch_id
      and batch_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Bank reconciliation batch does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  return public.auto_match_fms_bank_reconciliation(p_batch_id, p_date_tolerance_days);
end;
$$;

create or replace function public.match_fms_bank_statement_line_secure(
  p_statement_line_id uuid,
  p_ledger_entry_id uuid,
  p_matched_amount numeric default null,
  p_remark text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_saved public.fms_bank_statement_match%rowtype;
  v_owner_id uuid;
begin
  select batch_row.created_by_user_id
  into v_owner_id
  from public.fms_bank_statement_line line_row
  join public.fms_bank_reconciliation_batch batch_row
    on batch_row.id = line_row.batch_id
   and batch_row.tenant_id = line_row.tenant_id
  where line_row.id = p_statement_line_id
    and line_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Bank statement line does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.fms_fund_ledger_entry ledger_row
    where ledger_row.id = p_ledger_entry_id
      and ledger_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Fund ledger entry does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_saved := public.match_fms_bank_statement_line(
    p_statement_line_id, p_ledger_entry_id, p_matched_amount, p_remark
  );
  return app_private.fms_bank_statement_match_to_secure_json(
    v_saved.id,
    v_owner_id
  );
end;
$$;

create or replace function public.unmatch_fms_bank_statement_line_secure(p_match_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.fms_bank_statement_match match_row
    join public.fms_bank_statement_line line_row
      on line_row.id = match_row.statement_line_id
     and line_row.tenant_id = match_row.tenant_id
    where match_row.id = p_match_id
      and match_row.tenant_id = app_private.current_user_tenant_id()
  ) then
    raise exception 'Bank statement match does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  return public.unmatch_fms_bank_statement_line(p_match_id);
end;
$$;

create or replace function public.ignore_fms_bank_statement_line_secure(
  p_statement_line_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_saved public.fms_bank_statement_line%rowtype;
  v_owner_id uuid;
begin
  select batch_row.created_by_user_id
  into v_owner_id
  from public.fms_bank_statement_line line_row
  join public.fms_bank_reconciliation_batch batch_row
    on batch_row.id = line_row.batch_id
   and batch_row.tenant_id = line_row.tenant_id
  where line_row.id = p_statement_line_id
    and line_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Bank statement line does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_saved := public.ignore_fms_bank_statement_line(p_statement_line_id, p_reason);
  return app_private.fms_bank_statement_line_to_secure_json(
    app_private.fms_bank_statement_line_raw_json(v_saved.id),
    v_owner_id
  );
end;
$$;

create or replace function public.transition_fms_bank_reconciliation_secure(
  p_batch_id uuid,
  p_action text,
  p_reason text default null,
  p_expected_version integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_saved public.fms_bank_reconciliation_batch%rowtype;
  v_owner_id uuid;
begin
  select batch_row.created_by_user_id
  into v_owner_id
  from public.fms_bank_reconciliation_batch batch_row
  where batch_row.id = p_batch_id
    and batch_row.tenant_id = app_private.current_user_tenant_id();
  if not found then
    raise exception 'Bank reconciliation batch does not exist in the current tenant'
      using errcode = 'P0002';
  end if;
  v_saved := public.transition_fms_bank_reconciliation(
    p_batch_id, p_action, p_reason, p_expected_version
  );
  return app_private.fms_bank_reconciliation_batch_to_secure_json(
    app_private.fms_bank_reconciliation_batch_raw_json(v_saved.id),
    v_owner_id
  );
end;
$$;

revoke all on table public.fms_bank_reconciliation_batch from anon, authenticated;
revoke all on table public.fms_bank_reconciliation_batch_summary from anon, authenticated;
revoke all on table public.fms_bank_statement_line from anon, authenticated;
revoke all on table public.fms_bank_statement_line_summary from anon, authenticated;
revoke all on table public.fms_bank_statement_match from anon, authenticated;

revoke execute on function public.import_fms_bank_reconciliation(jsonb)
  from public, anon, authenticated;
revoke execute on function public.auto_match_fms_bank_reconciliation(uuid, integer)
  from public, anon, authenticated;
revoke execute on function public.match_fms_bank_statement_line(uuid, uuid, numeric, text)
  from public, anon, authenticated;
revoke execute on function public.unmatch_fms_bank_statement_line(uuid)
  from public, anon, authenticated;
revoke execute on function public.ignore_fms_bank_statement_line(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.transition_fms_bank_reconciliation(uuid, text, text, integer)
  from public, anon, authenticated;

revoke all on function public.fms_list_bank_reconciliations_secure(
  integer, integer, uuid, uuid, text, text, date, date, uuid
) from public, anon, authenticated;
revoke all on function public.fms_get_bank_reconciliation_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.fms_list_bank_statement_lines_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.fms_list_bank_statement_matches_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.fms_list_bank_match_candidates_secure(uuid, integer)
  from public, anon, authenticated;
revoke all on function public.import_fms_bank_reconciliation_secure(jsonb)
  from public, anon, authenticated;
revoke all on function public.auto_match_fms_bank_reconciliation_secure(uuid, integer)
  from public, anon, authenticated;
revoke all on function public.match_fms_bank_statement_line_secure(uuid, uuid, numeric, text)
  from public, anon, authenticated;
revoke all on function public.unmatch_fms_bank_statement_line_secure(uuid)
  from public, anon, authenticated;
revoke all on function public.ignore_fms_bank_statement_line_secure(uuid, text)
  from public, anon, authenticated;
revoke all on function public.transition_fms_bank_reconciliation_secure(uuid, text, text, integer)
  from public, anon, authenticated;

grant execute on function public.fms_list_bank_reconciliations_secure(
  integer, integer, uuid, uuid, text, text, date, date, uuid
) to authenticated;
grant execute on function public.fms_get_bank_reconciliation_secure(uuid)
  to authenticated;
grant execute on function public.fms_list_bank_statement_lines_secure(uuid)
  to authenticated;
grant execute on function public.fms_list_bank_statement_matches_secure(uuid)
  to authenticated;
grant execute on function public.fms_list_bank_match_candidates_secure(uuid, integer)
  to authenticated;
grant execute on function public.import_fms_bank_reconciliation_secure(jsonb)
  to authenticated;
grant execute on function public.auto_match_fms_bank_reconciliation_secure(uuid, integer)
  to authenticated;
grant execute on function public.match_fms_bank_statement_line_secure(uuid, uuid, numeric, text)
  to authenticated;
grant execute on function public.unmatch_fms_bank_statement_line_secure(uuid)
  to authenticated;
grant execute on function public.ignore_fms_bank_statement_line_secure(uuid, text)
  to authenticated;
grant execute on function public.transition_fms_bank_reconciliation_secure(uuid, text, text, integer)
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
        and resource_row.resource_key = 'fms.bank_reconciliation'
        and resource_row.owner_column = 'created_by_user_id'
        and resource_row.enabled is true
    )
  ) then
    raise exception 'Missing fms.bank_reconciliation permission resource';
  end if;
  if exists (
    select 1
    from public.sys_permission_resource resource_row
    where resource_row.resource_key = 'fms.bank_reconciliation'
      and (
        select count(*)
        from public.sys_permission_field field_row
        where field_row.tenant_id = resource_row.tenant_id
          and field_row.resource_id = resource_row.id
          and field_row.enabled is true
      ) <> 3
  ) then
    raise exception 'Unexpected fms.bank_reconciliation field catalog';
  end if;
  if has_table_privilege('authenticated', 'public.fms_bank_reconciliation_batch', 'select')
     or has_table_privilege('authenticated', 'public.fms_bank_reconciliation_batch_summary', 'select')
     or has_table_privilege('authenticated', 'public.fms_bank_statement_line', 'select')
     or has_table_privilege('authenticated', 'public.fms_bank_statement_line_summary', 'select')
     or has_table_privilege('authenticated', 'public.fms_bank_statement_match', 'select')
     or has_table_privilege('anon', 'public.fms_bank_reconciliation_batch', 'select')
     or has_table_privilege('anon', 'public.fms_bank_statement_line', 'select')
     or has_table_privilege('anon', 'public.fms_bank_statement_match', 'select') then
    raise exception 'Direct bank reconciliation reads remain exposed';
  end if;
  if has_function_privilege(
    'anon',
    'public.fms_list_bank_reconciliations_secure(integer,integer,uuid,uuid,text,text,date,date,uuid)',
    'execute'
  ) or has_function_privilege(
    'anon',
    'public.import_fms_bank_reconciliation_secure(jsonb)',
    'execute'
  ) then
    raise exception 'Anonymous bank reconciliation RPC access remains exposed';
  end if;
end;
$$;

;
