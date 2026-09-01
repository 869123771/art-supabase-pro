-- Carrier payment applications contain approval amounts and supporting evidence.
-- Authenticated clients must use the secure RPC boundary below so tenant, button,
-- record-owner, role/user field grants and masking are evaluated together.

alter table public.tms_carrier_payment_application
  add column if not exists created_by_user_id uuid;

update public.tms_carrier_payment_application application_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = application_row.tenant_id
    and user_row.deleted_at is null
    and (
      lower(user_row.user_email) = lower(application_row.create_by)
      or lower(user_row.user_name) = lower(application_row.create_by)
      or lower(user_row.nick_name) = lower(application_row.create_by)
    )
  order by
    case
      when lower(user_row.user_email) = lower(application_row.create_by) then 0
      when lower(user_row.user_name) = lower(application_row.create_by) then 1
      else 2
    end,
    user_row.create_time,
    user_row.id
  limit 1
)
where application_row.created_by_user_id is null;

do $$
begin
  if exists (
    select 1
    from public.tms_carrier_payment_application
    where created_by_user_id is null
  ) then
    raise exception 'Unable to resolve every carrier payment application creator';
  end if;
end;
$$;

alter table public.tms_carrier_payment_application
  alter column created_by_user_id set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.tms_carrier_payment_application'::regclass
      and conname = 'tms_carrier_payment_application_created_by_user_tenant_fkey'
  ) then
    alter table public.tms_carrier_payment_application
      add constraint tms_carrier_payment_application_created_by_user_tenant_fkey
      foreign key (created_by_user_id, tenant_id)
      references public.sys_user (id, tenant_id)
      on delete restrict;
  end if;
end;
$$;

create index if not exists tms_carrier_payment_application_tenant_creator_idx
  on public.tms_carrier_payment_application (tenant_id, created_by_user_id);

create or replace function app_private.set_tms_carrier_payment_application_creator_identity()
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
      raise exception 'Authenticated payment application creator identity is required'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Payment application creator identity is immutable'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists tms_carrier_payment_application_creator_identity
  on public.tms_carrier_payment_application;
create trigger tms_carrier_payment_application_creator_identity
before insert or update of created_by_user_id
on public.tms_carrier_payment_application
for each row
execute function app_private.set_tms_carrier_payment_application_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_carrier_payment_application;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_carrier_payment_application(
    p_tenant_id
  );

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.carrier_payment_application', '承运商付款申请',
    'FinanceCarrierPaymentApplication', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'applicationAmounts', '申请与付款分配金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'basisEvidence', '付款依据附件',
      'hidden', 'none', true, 20, '624944977@qq.com', '624944977@qq.com')
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

-- Preserve current users during rollout. Tenant administrators can tighten these
-- grants later from the field-permission matrix.
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
 and menu_row.name = 'FinanceCarrierPaymentApplication'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'tms.carrier_payment_application'
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.tms_carrier_payment_application_to_secure_json(
  p_application jsonb,
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
    app_private.field_access_map('tms.carrier_payment_application', p_owner_id)
  );
  v_data jsonb := coalesce(p_application, '{}'::jsonb)
    - 'tenant_id'
    - 'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['amount']::text[],
    coalesce(v_access->>'applicationAmounts', 'hidden')
  );
  v_data := app_private.apply_jsonb_document_access(
    v_data,
    array['basis_urls']::text[],
    coalesce(v_access->>'basisEvidence', 'hidden')
  );

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.tms_list_carrier_payment_applications_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_carrier_id uuid default null,
  p_status text default null,
  p_record_id uuid default null,
  p_planned_payment_date_start date default null,
  p_planned_payment_date_end date default null,
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
    then 'FinanceCarrierPaymentApplication:Export'
    else 'FinanceCarrierPaymentApplication:View'
  end;
  v_limit integer;
  v_base_access jsonb;
begin
  if p_purpose not in ('list', 'export') then
    raise exception 'Invalid carrier payment application read purpose';
  end if;
  if not app_private.can_execute_business_action(
    'FinanceCarrierPaymentApplication', v_permission, null, false
  ) then
    raise exception 'Missing carrier payment application read permission'
      using errcode = '42501';
  end if;
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  v_limit := least(
    case when p_purpose = 'export' then 10000 else 500 end,
    greatest(coalesce(p_to, 9) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );
  v_base_access := app_private.field_access_map(
    'tms.carrier_payment_application', null
  );

  return (
    with filtered as materialized (
      select
        summary_row as application_record,
        application_row.created_by_user_id
      from public.tms_carrier_payment_application_summary summary_row
      join public.tms_carrier_payment_application application_row
        on application_row.id = summary_row.id
       and application_row.tenant_id = summary_row.tenant_id
      where (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id)
        and (p_carrier_id is null or summary_row.carrier_id = p_carrier_id)
        and (p_status is null or summary_row.status = p_status)
        and (p_record_id is null or summary_row.id = p_record_id)
        and (
          p_planned_payment_date_start is null
          or summary_row.planned_payment_date >= p_planned_payment_date_start
        )
        and (
          p_planned_payment_date_end is null
          or summary_row.planned_payment_date <= p_planned_payment_date_end
        )
        and (p_ids is null or summary_row.id = any(p_ids))
        and (
          nullif(btrim(p_keyword), '') is null
          or summary_row.application_no ilike '%' || btrim(p_keyword) || '%'
          or summary_row.carrier_name ilike '%' || btrim(p_keyword) || '%'
          or summary_row.statement_nos ilike '%' || btrim(p_keyword) || '%'
          or summary_row.paid_transaction_no ilike '%' || btrim(p_keyword) || '%'
          or summary_row.remark ilike '%' || btrim(p_keyword) || '%'
        )
    ), paged as (
      select filtered.*
      from filtered
      order by (filtered.application_record).create_time desc,
               (filtered.application_record).id
      offset greatest(coalesce(p_from, 0), 0)
      limit v_limit
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          app_private.tms_carrier_payment_application_to_secure_json(
            to_jsonb(paged.application_record),
            paged.created_by_user_id
          )
          order by (paged.application_record).create_time desc,
                   (paged.application_record).id
        )
        from paged
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'fieldAccess', v_base_access
    )
  );
end;
$$;

create or replace function public.tms_get_carrier_payment_application_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_application public.tms_carrier_payment_application_summary%rowtype;
  v_owner_id uuid;
  v_access jsonb;
  v_amount_access text;
  v_items jsonb;
begin
  if not (
    app_private.can_execute_business_action(
      'FinanceCarrierPaymentApplication',
      'FinanceCarrierPaymentApplication:View',
      null,
      false
    )
    or app_private.can_execute_business_action(
      'FinanceCarrierPaymentApplication',
      'FinanceCarrierPaymentApplication:Edit',
      null,
      false
    )
  ) then
    raise exception 'Missing carrier payment application detail permission'
      using errcode = '42501';
  end if;

  select summary_row.*
  into v_application
  from public.tms_carrier_payment_application_summary summary_row
  where summary_row.id = p_id
    and (app_private.is_platform_super() or summary_row.tenant_id = v_tenant_id);

  if not found then
    return null;
  end if;

  select application_row.created_by_user_id
  into v_owner_id
  from public.tms_carrier_payment_application application_row
  where application_row.id = v_application.id
    and application_row.tenant_id = v_application.tenant_id;

  v_access := app_private.field_access_map(
    'tms.carrier_payment_application', v_owner_id
  );
  v_amount_access := coalesce(v_access->>'applicationAmounts', 'hidden');

  select coalesce(jsonb_agg(
    app_private.apply_jsonb_amount_access(
      to_jsonb(item_row) - 'tenant_id',
      array[
        'statement_amount_snapshot',
        'outstanding_amount_snapshot',
        'applied_amount'
      ]::text[],
      v_amount_access
    )
    order by item_row.statement_no_snapshot, item_row.id
  ), '[]'::jsonb)
  into v_items
  from public.tms_carrier_payment_application_item item_row
  where item_row.application_id = p_id
    and item_row.tenant_id = v_application.tenant_id;

  return app_private.tms_carrier_payment_application_to_secure_json(
    to_jsonb(v_application), v_owner_id, v_access
  ) || jsonb_build_object('items', coalesce(v_items, '[]'::jsonb));
end;
$$;

create or replace function public.save_tms_carrier_payment_application_secure(
  p_application_id uuid,
  p_carrier_id uuid,
  p_planned_payment_date date,
  p_amount numeric,
  p_payment_method text,
  p_basis_urls jsonb,
  p_remark text,
  p_allocations jsonb,
  p_application_no text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_existing public.tms_carrier_payment_application%rowtype;
  v_access jsonb := jsonb_build_object(
    'applicationAmounts', 'edit',
    'basisEvidence', 'edit'
  );
  v_carrier_id uuid := p_carrier_id;
  v_amount numeric := p_amount;
  v_basis_urls jsonb := coalesce(p_basis_urls, '[]'::jsonb);
  v_allocations jsonb;
begin
  if v_tenant_id is null then
    raise exception 'Current tenant not found' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'statement_id', coalesce(item.value->>'statementId', item.value->>'statement_id'),
    'amount', item.value->>'amount'
  ) order by item.ordinality), '[]'::jsonb)
  into v_allocations
  from jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb))
    with ordinality as item(value, ordinality);

  if p_application_id is null then
    if not app_private.can_execute_business_action(
      'FinanceCarrierPaymentApplication',
      'FinanceCarrierPaymentApplication:Add',
      null,
      false
    ) then
      raise exception 'Missing carrier payment application create permission'
        using errcode = '42501';
    end if;
  else
    if not app_private.can_execute_business_action(
      'FinanceCarrierPaymentApplication',
      'FinanceCarrierPaymentApplication:Edit',
      null,
      false
    ) then
      raise exception 'Missing carrier payment application edit permission'
        using errcode = '42501';
    end if;

    perform pg_advisory_xact_lock(hashtextextended(p_application_id::text, 841329));
    select application_row.*
    into v_existing
    from public.tms_carrier_payment_application application_row
    where application_row.id = p_application_id
      and (app_private.is_platform_super() or application_row.tenant_id = v_tenant_id)
    for update;

    if not found or v_existing.status not in ('draft', 'rejected') then
      raise exception '付款申请不存在或当前状态不能编辑';
    end if;

    v_access := app_private.field_access_map(
      'tms.carrier_payment_application', v_existing.created_by_user_id
    );

    if coalesce(v_access->>'applicationAmounts', 'hidden') <> 'edit' then
      v_carrier_id := v_existing.carrier_id;
      v_amount := v_existing.amount;
      select coalesce(jsonb_agg(jsonb_build_object(
        'statement_id', item_row.statement_id,
        'amount', item_row.applied_amount
      ) order by item_row.create_time, item_row.id), '[]'::jsonb)
      into v_allocations
      from public.tms_carrier_payment_application_item item_row
      where item_row.application_id = p_application_id
        and item_row.tenant_id = v_existing.tenant_id;
    end if;

    if coalesce(v_access->>'basisEvidence', 'hidden') <> 'edit' then
      v_basis_urls := v_existing.basis_urls;
    end if;
  end if;

  if p_application_id is null
     or coalesce(v_access->>'applicationAmounts', 'edit') = 'edit' then
    if exists (
      select 1
      from jsonb_to_recordset(v_allocations)
        as allocation_row(statement_id uuid, amount numeric)
      left join public.tms_carrier_statement statement_row
        on statement_row.id = allocation_row.statement_id
       and statement_row.tenant_id = v_tenant_id
       and statement_row.carrier_id = v_carrier_id
      where statement_row.id is null
         or app_private.resolve_field_access(
           'tms.carrier_statement',
           'statementAmounts',
           statement_row.created_by_user_id
         ) not in ('read', 'edit')
         or app_private.resolve_field_access(
           'tms.carrier_statement',
           'settlementAmounts',
           statement_row.created_by_user_id
         ) not in ('read', 'edit')
    ) then
      raise exception '当前字段权限不足，无法读取所选承运商对账金额或未付余额'
        using errcode = '42501';
    end if;
  end if;

  perform set_config(
    'app.document_number.tms_carrier_payment_application',
    coalesce(p_application_no, ''),
    true
  );

  return public.save_tms_carrier_payment_application(
    p_application_id,
    v_carrier_id,
    p_planned_payment_date,
    v_amount,
    p_payment_method,
    v_basis_urls,
    p_remark,
    v_allocations
  );
end;
$$;

create or replace function public.validate_tms_carrier_payment_application_submission_secure(
  p_application_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_application public.tms_carrier_payment_application%rowtype;
begin
  if not app_private.can_execute_business_action(
    'FinanceCarrierPaymentApplication',
    'FinanceCarrierPaymentApplication:Submit',
    null,
    false
  ) then
    raise exception 'Missing carrier payment application submit permission'
      using errcode = '42501';
  end if;

  select application_row.*
  into v_application
  from public.tms_carrier_payment_application application_row
  where application_row.id = p_application_id
    and (app_private.is_platform_super() or application_row.tenant_id = v_tenant_id);

  if not found then
    raise exception '付款申请不存在或无权访问';
  end if;

  if app_private.resolve_field_access(
    'tms.carrier_payment_application',
    'applicationAmounts',
    v_application.created_by_user_id
  ) not in ('read', 'edit') then
    raise exception '当前字段权限不足，无法提交付款金额审批'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.tms_carrier_payment_application_item item_row
    left join public.tms_carrier_statement statement_row
      on statement_row.id = item_row.statement_id
     and statement_row.tenant_id = item_row.tenant_id
    where item_row.application_id = p_application_id
      and item_row.tenant_id = v_application.tenant_id
      and (
        statement_row.id is null
        or app_private.resolve_field_access(
          'tms.carrier_statement',
          'statementAmounts',
          statement_row.created_by_user_id
        ) not in ('read', 'edit')
        or app_private.resolve_field_access(
          'tms.carrier_statement',
          'settlementAmounts',
          statement_row.created_by_user_id
        ) not in ('read', 'edit')
      )
  ) then
    raise exception '当前字段权限不足，无法校验付款申请关联的对账金额'
      using errcode = '42501';
  end if;

  return public.validate_tms_carrier_payment_application_submission(p_application_id);
end;
$$;

create or replace function public.execute_fms_carrier_payment_application_secure(
  p_application_id uuid,
  p_fund_account_id uuid,
  p_transaction_date date,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_transaction_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_application public.tms_carrier_payment_application%rowtype;
begin
  if not app_private.can_execute_business_action(
    'FinanceCarrierPaymentApplication',
    'FinanceCarrierPaymentApplication:Execute',
    null,
    false
  ) then
    raise exception 'Missing carrier payment application execute permission'
      using errcode = '42501';
  end if;

  select application_row.*
  into v_application
  from public.tms_carrier_payment_application application_row
  where application_row.id = p_application_id
    and (app_private.is_platform_super() or application_row.tenant_id = v_tenant_id)
  for update;

  if not found then
    raise exception '付款申请不存在或无权访问';
  end if;

  if app_private.resolve_field_access(
    'tms.carrier_payment_application',
    'applicationAmounts',
    v_application.created_by_user_id
  ) not in ('read', 'edit') then
    raise exception '当前字段权限不足，无法读取并执行付款申请金额'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.tms_carrier_payment_application_item item_row
    left join public.tms_carrier_statement statement_row
      on statement_row.id = item_row.statement_id
     and statement_row.tenant_id = item_row.tenant_id
    where item_row.application_id = p_application_id
      and item_row.tenant_id = v_application.tenant_id
      and (
        statement_row.id is null
        or app_private.resolve_field_access(
          'tms.carrier_statement',
          'statementAmounts',
          statement_row.created_by_user_id
        ) not in ('read', 'edit')
        or app_private.resolve_field_access(
          'tms.carrier_statement',
          'settlementAmounts',
          statement_row.created_by_user_id
        ) <> 'edit'
      )
  ) then
    raise exception '当前字段权限不足，无法执行承运商对账核销'
      using errcode = '42501';
  end if;

  return public.execute_fms_carrier_payment_application(
    p_application_id,
    p_fund_account_id,
    p_transaction_date,
    p_bank_reference,
    coalesce(p_voucher_urls, '[]'::jsonb),
    p_transaction_no
  );
end;
$$;

create or replace function public.cancel_tms_carrier_payment_application_secure(
  p_application_id uuid,
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
    'FinanceCarrierPaymentApplication',
    'FinanceCarrierPaymentApplication:Cancel',
    null,
    false
  ) then
    raise exception 'Missing carrier payment application cancel permission'
      using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.tms_carrier_payment_application application_row
    where application_row.id = p_application_id
      and (app_private.is_platform_super() or application_row.tenant_id = v_tenant_id)
  ) then
    raise exception '付款申请不存在或无权访问';
  end if;
  return public.cancel_tms_carrier_payment_application(p_application_id, p_reason);
end;
$$;

create or replace function public.delete_tms_carrier_payment_application_secure(
  p_application_id uuid
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
    'FinanceCarrierPaymentApplication',
    'FinanceCarrierPaymentApplication:Delete',
    null,
    false
  ) then
    raise exception 'Missing carrier payment application delete permission'
      using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.tms_carrier_payment_application application_row
    where application_row.id = p_application_id
      and (app_private.is_platform_super() or application_row.tenant_id = v_tenant_id)
  ) then
    raise exception '付款申请不存在或无权访问';
  end if;
  return public.delete_tms_carrier_payment_application(p_application_id);
end;
$$;

create or replace function app_private.get_carrier_payment_application_workflow_snapshot(
  p_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_instance public.wf_instance;
  v_application record;
  v_access jsonb;
  v_amount_access text;
  v_evidence_access text;
  v_metrics jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_attachments jsonb := '[]'::jsonb;
begin
  if (select auth.uid()) is null
     or not app_private.can_view_workflow_instance(p_instance_id) then
    raise exception '无权查看该审批业务信息' using errcode = '42501';
  end if;

  select instance_row.*
  into v_instance
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;

  if not found then
    raise exception '审批实例不存在';
  end if;

  select
    application_row.*,
    (
      select count(*)::integer
      from public.tms_carrier_payment_application_item item_row
      where item_row.application_id = application_row.id
    ) as statement_count,
    (
      select coalesce(
        string_agg(
          item_row.statement_no_snapshot,
          '、'
          order by item_row.statement_no_snapshot
        ),
        ''
      )
      from public.tms_carrier_payment_application_item item_row
      where item_row.application_id = application_row.id
    ) as statement_nos
  into v_application
  from public.tms_carrier_payment_application application_row
  where application_row.id = v_instance.business_id;

  if not found then
    return jsonb_build_object(
      'instanceId', v_instance.id,
      'businessType', v_instance.business_type,
      'businessId', v_instance.business_id,
      'title', v_instance.business_title,
      'metrics', '[]'::jsonb,
      'fields', '[]'::jsonb,
      'warnings', jsonb_build_array('业务原单已删除，当前仅展示流程快照'),
      'attachments', '[]'::jsonb
    );
  end if;

  v_access := app_private.field_access_map(
    'tms.carrier_payment_application',
    v_application.created_by_user_id
  );
  v_amount_access := coalesce(v_access->>'applicationAmounts', 'hidden');
  v_evidence_access := coalesce(v_access->>'basisEvidence', 'hidden');

  if v_instance.status = 'running' and not exists (
    select 1
    from public.wf_task task_row
    where task_row.instance_id = v_instance.id
      and task_row.status = 'pending'
  ) then
    v_warnings := jsonb_build_array(
      '流程运行中但当前没有待办任务，请联系审批管理员检查流程条件。'
    );
  end if;

  v_metrics := jsonb_build_array(
    jsonb_build_object(
      'label', '关联对账单',
      'value', v_application.statement_count::text || ' 份',
      'tone', 'primary'
    ),
    jsonb_build_object(
      'label', '计划付款日',
      'value', v_application.planned_payment_date::text,
      'tone', 'info'
    )
  );

  if v_amount_access <> 'hidden' then
    v_metrics := jsonb_build_array(jsonb_build_object(
      'label', '申请金额',
      'value', case
        when v_amount_access = 'masked' then '***'
        else '¥ ' || to_char(v_application.amount, 'FM999,999,990.00')
      end,
      'tone', 'warning'
    )) || v_metrics;
  end if;

  if v_amount_access = 'masked' then
    v_warnings := v_warnings || jsonb_build_array('申请金额已按字段权限脱敏');
  end if;
  if v_evidence_access = 'masked' then
    v_warnings := v_warnings || jsonb_build_array('付款依据已按字段权限脱敏');
  end if;
  if v_evidence_access in ('read', 'edit') then
    v_attachments := app_private.workflow_attachment_list(v_application.basis_urls);
  end if;

  return jsonb_build_object(
    'instanceId', v_instance.id,
    'businessType', v_instance.business_type,
    'businessId', v_instance.business_id,
    'title', v_instance.business_title,
    'subtitle', v_application.carrier_name_snapshot,
    'businessNo', v_application.application_no,
    'status', v_application.status,
    'routePath', '/tms-transportation/finance-center/payment-application',
    'metrics', v_metrics,
    'fields', jsonb_build_array(
      jsonb_build_object('label', '申请单号', 'value', v_application.application_no),
      jsonb_build_object(
        'label', '付款承运商', 'value', v_application.carrier_name_snapshot
      ),
      jsonb_build_object(
        'label',
        '关联对账单',
        'value', coalesce(nullif(v_application.statement_nos, ''), '--')
      ),
      jsonb_build_object('label', '付款方式', 'value', v_application.payment_method),
      jsonb_build_object(
        'label', '备注', 'value', coalesce(v_application.remark, '--')
      )
    ),
    'warnings', v_warnings,
    'attachments', v_attachments,
    'fieldAccess', v_access
  );
end;
$$;

-- OCR evidence may contain the same amount and attachment content. Keep it out of
-- workflow responses unless the viewer can read both protected field groups.
create or replace function app_private.get_workflow_business_snapshot_v2(
  p_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_type text;
  v_business_id uuid;
  v_snapshot jsonb;
  v_ocr record;
  v_payment_access jsonb;
  v_include_ocr boolean := true;
begin
  select instance_row.business_type, instance_row.business_id
  into v_type, v_business_id
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;

  if v_type = 'tms_carrier_payment_application' then
    v_snapshot := app_private.get_carrier_payment_application_workflow_snapshot(
      p_instance_id
    );

    select app_private.field_access_map(
      'tms.carrier_payment_application',
      application_row.created_by_user_id
    )
    into v_payment_access
    from public.tms_carrier_payment_application application_row
    where application_row.id = v_business_id;

    v_include_ocr := found
      and coalesce(v_payment_access->>'applicationAmounts', 'hidden') in ('read', 'edit')
      and coalesce(v_payment_access->>'basisEvidence', 'hidden') in ('read', 'edit');
  elsif v_type = 'tms_contract' then
    v_snapshot := app_private.get_contract_workflow_snapshot(p_instance_id);
  else
    v_snapshot := app_private.get_workflow_business_snapshot(p_instance_id);
  end if;

  if v_include_ocr then
    select
      artifact_row.id,
      artifact_row.raw_ocr_text,
      artifact_row.create_time
    into v_ocr
    from public.ai_artifact_review artifact_row
    where artifact_row.entity_type = v_type
      and artifact_row.entity_id = v_business_id
      and artifact_row.status = 'applied'
    order by
      artifact_row.reviewed_at desc nulls last,
      artifact_row.create_time desc
    limit 1;

    if found then
      v_snapshot := v_snapshot || jsonb_build_object(
        'ocrEvidence',
        jsonb_build_object(
          'artifactId', v_ocr.id,
          'rawText', coalesce(v_ocr.raw_ocr_text, ''),
          'capturedAt', v_ocr.create_time
        )
      );
    end if;
  end if;

  return v_snapshot;
end;
$$;

-- Remove direct Data API paths that could bypass field authorization.
revoke all on table
  public.tms_carrier_payment_application,
  public.tms_carrier_payment_application_item,
  public.tms_carrier_payment_application_summary
from public, anon, authenticated;

grant all on table
  public.tms_carrier_payment_application,
  public.tms_carrier_payment_application_item
to service_role;
grant select on table public.tms_carrier_payment_application_summary
  to service_role;

revoke execute on function public.save_tms_carrier_payment_application(
  uuid, uuid, date, numeric, text, jsonb, text, jsonb
) from public, anon, authenticated;
revoke execute on function public.save_tms_carrier_payment_application(
  uuid, uuid, date, numeric, text, jsonb, text, jsonb, text
) from public, anon, authenticated;
revoke execute on function public.validate_tms_carrier_payment_application_submission(uuid)
  from public, anon, authenticated;
revoke execute on function public.execute_fms_carrier_payment_application(
  uuid, uuid, date, text, jsonb, text
) from public, anon, authenticated;
revoke execute on function public.execute_tms_carrier_payment_application(
  uuid, date, text, jsonb
) from public, anon, authenticated;
revoke execute on function public.execute_tms_carrier_payment_application(
  uuid, date, text, jsonb, text
) from public, anon, authenticated;
revoke execute on function public.cancel_tms_carrier_payment_application(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.delete_tms_carrier_payment_application(uuid)
  from public, anon, authenticated;

revoke execute on function public.tms_list_carrier_payment_applications_secure(
  integer, integer, uuid, text, uuid, date, date, text, uuid[], text
) from public, anon;
revoke execute on function public.tms_get_carrier_payment_application_secure(uuid)
  from public, anon;
revoke execute on function public.save_tms_carrier_payment_application_secure(
  uuid, uuid, date, numeric, text, jsonb, text, jsonb, text
) from public, anon;
revoke execute on function public.validate_tms_carrier_payment_application_submission_secure(uuid)
  from public, anon;
revoke execute on function public.execute_fms_carrier_payment_application_secure(
  uuid, uuid, date, text, jsonb, text
) from public, anon;
revoke execute on function public.cancel_tms_carrier_payment_application_secure(uuid, text)
  from public, anon;
revoke execute on function public.delete_tms_carrier_payment_application_secure(uuid)
  from public, anon;

grant execute on function public.tms_list_carrier_payment_applications_secure(
  integer, integer, uuid, text, uuid, date, date, text, uuid[], text
) to authenticated, service_role;
grant execute on function public.tms_get_carrier_payment_application_secure(uuid)
  to authenticated, service_role;
grant execute on function public.save_tms_carrier_payment_application_secure(
  uuid, uuid, date, numeric, text, jsonb, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.validate_tms_carrier_payment_application_submission_secure(uuid)
  to authenticated, service_role;
grant execute on function public.execute_fms_carrier_payment_application_secure(
  uuid, uuid, date, text, jsonb, text
) to authenticated, service_role;
grant execute on function public.cancel_tms_carrier_payment_application_secure(uuid, text)
  to authenticated, service_role;
grant execute on function public.delete_tms_carrier_payment_application_secure(uuid)
  to authenticated, service_role;

;
