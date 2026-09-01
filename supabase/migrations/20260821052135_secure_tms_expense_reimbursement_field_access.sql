-- Secure TMS expense reimbursement amounts, payee details, evidence, and payment results.
-- Field access is enforced at the database boundary for list, detail, workflow, and payment paths.

alter table public.tms_expense_reimbursement
  add column if not exists created_by_user_id uuid;

update public.tms_expense_reimbursement reimbursement_row
set created_by_user_id = reimbursement_row.applicant_user_id
where reimbursement_row.created_by_user_id is null
  and reimbursement_row.applicant_user_id is not null;

update public.tms_expense_reimbursement reimbursement_row
set created_by_user_id = (
  select candidate.id
  from public.sys_user candidate
  where candidate.tenant_id = reimbursement_row.tenant_id
    and lower(candidate.user_email) = lower(reimbursement_row.create_by)
  order by candidate.create_time, candidate.id
  limit 1
)
where reimbursement_row.created_by_user_id is null
  and nullif(btrim(coalesce(reimbursement_row.create_by, '')), '') is not null;

do $$
begin
  if exists (
    select 1
    from public.tms_expense_reimbursement
    where created_by_user_id is null
  ) then
    raise exception 'Unable to backfill tms_expense_reimbursement.created_by_user_id';
  end if;
end;
$$;

alter table public.tms_expense_reimbursement
  alter column created_by_user_id set not null;

create index if not exists tms_expense_reimbursement_tenant_creator_idx
  on public.tms_expense_reimbursement(tenant_id, created_by_user_id);

create index if not exists tms_expense_reimbursement_creator_tenant_idx
  on public.tms_expense_reimbursement(created_by_user_id, tenant_id);

alter table public.tms_expense_reimbursement
  drop constraint if exists tms_expense_reimbursement_creator_tenant_fkey;

alter table public.tms_expense_reimbursement
  add constraint tms_expense_reimbursement_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_tms_expense_reimbursement_creator_identity()
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
    if new.created_by_user_id is null then
      new.created_by_user_id := new.applicant_user_id;
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
      raise exception 'Unable to resolve expense reimbursement creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Expense reimbursement creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists tms_expense_reimbursement_creator_identity
  on public.tms_expense_reimbursement;
create trigger tms_expense_reimbursement_creator_identity
before insert or update of created_by_user_id
on public.tms_expense_reimbursement
for each row execute function app_private.set_tms_expense_reimbursement_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_expense_reimbursement;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_expense_reimbursement(p_tenant_id);

  insert into public.sys_permission_resource (
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'tms.expense_reimbursement', '费用报销单',
    'FinanceExpenseReimbursement', 'created_by_user_id',
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
    (p_tenant_id, v_resource_id, 'reimbursementAmounts', '报销总额与逐笔核销金额',
      'hidden', 'amount', true, 10, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'payeeDetails', '收款人、银行账号与付款方式',
      'hidden', 'bank_account', true, 20, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'reimbursementEvidence', '报销说明与依据附件',
      'hidden', 'none', true, 30, '624944977@qq.com', '624944977@qq.com'),
    (p_tenant_id, v_resource_id, 'paymentExecution', '付款单、银行流水与付款凭证',
      'hidden', 'bank_account', true, 40, '624944977@qq.com', '624944977@qq.com')
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
 and menu_row.name = 'FinanceExpenseReimbursement'
join public.sys_role_menu role_menu
  on role_menu.tenant_id = resource_row.tenant_id
 and role_menu.menu_id = menu_row.id
where resource_row.resource_key = 'tms.expense_reimbursement'
  and resource_row.enabled is true
  and field_row.enabled is true
on conflict (tenant_id, role_id, resource_id, field_id) do nothing;

create or replace function app_private.tms_expense_reimbursement_raw_json(
  p_reimbursement_id uuid,
  p_include_items boolean default true
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select
    (to_jsonb(reimbursement_row) - 'tenant_id' - 'created_by_user_id') ||
    jsonb_build_object(
      'item_count', (
        select count(*)::integer
        from public.tms_expense_reimbursement_item item_row
        where item_row.reimbursement_id = reimbursement_row.id
          and item_row.tenant_id = reimbursement_row.tenant_id
      ),
      'waybill_count', (
        select count(distinct item_row.waybill_id)::integer
        from public.tms_expense_reimbursement_item item_row
        where item_row.reimbursement_id = reimbursement_row.id
          and item_row.tenant_id = reimbursement_row.tenant_id
      ),
      'waybill_nos', (
        select string_agg(
          distinct item_row.waybill_no_snapshot,
          '、' order by item_row.waybill_no_snapshot
        )
        from public.tms_expense_reimbursement_item item_row
        where item_row.reimbursement_id = reimbursement_row.id
          and item_row.tenant_id = reimbursement_row.tenant_id
      ),
      'payment_id', (
        select payment_row.id
        from public.tms_expense_payment payment_row
        where payment_row.reimbursement_id = reimbursement_row.id
          and payment_row.tenant_id = reimbursement_row.tenant_id
        order by payment_row.create_time desc, payment_row.id
        limit 1
      ),
      'payment_no', (
        select payment_row.payment_no
        from public.tms_expense_payment payment_row
        where payment_row.reimbursement_id = reimbursement_row.id
          and payment_row.tenant_id = reimbursement_row.tenant_id
        order by payment_row.create_time desc, payment_row.id
        limit 1
      )
    ) ||
    case when p_include_items then jsonb_build_object(
      'items', coalesce((
        select jsonb_agg(
          to_jsonb(item_row) - 'tenant_id'
          order by item_row.occurred_on_snapshot, item_row.create_time, item_row.id
        )
        from public.tms_expense_reimbursement_item item_row
        where item_row.reimbursement_id = reimbursement_row.id
          and item_row.tenant_id = reimbursement_row.tenant_id
      ), '[]'::jsonb)
    ) else '{}'::jsonb end
  from public.tms_expense_reimbursement reimbursement_row
  where reimbursement_row.id = p_reimbursement_id
    and reimbursement_row.tenant_id = app_private.current_user_tenant_id();
$$;

create or replace function app_private.tms_expense_reimbursement_to_secure_json(
  p_reimbursement jsonb,
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
    app_private.field_access_map('tms.expense_reimbursement', p_owner_id)
  );
  v_data jsonb := coalesce(p_reimbursement, '{}'::jsonb)
    - 'tenant_id'
    - 'created_by_user_id';
  v_level text;
  v_items jsonb;
begin
  v_level := coalesce(v_access->>'reimbursementAmounts', 'hidden');
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['total_amount']::text[],
    v_level
  );
  if jsonb_typeof(v_data->'items') = 'array' then
    select coalesce(jsonb_agg(
      app_private.apply_jsonb_amount_access(
        item_value,
        array['amount_snapshot']::text[],
        v_level
      )
    ), '[]'::jsonb)
    into v_items
    from jsonb_array_elements(v_data->'items') item_value;
    v_data := jsonb_set(v_data, '{items}', v_items, true);
  end if;

  v_level := coalesce(v_access->>'payeeDetails', 'hidden');
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['payee_name', 'payee_bank', 'payment_method']::text[],
    v_level
  );
  if v_level = 'hidden' then
    v_data := v_data - 'payee_account';
  elsif v_level = 'masked' and v_data ? 'payee_account' then
    v_data := jsonb_set(
      v_data,
      '{payee_account}',
      coalesce(
        to_jsonb(app_private.mask_permission_value(
          v_data->>'payee_account', 'bank_account'
        )),
        'null'::jsonb
      ),
      true
    );
  end if;

  v_level := coalesce(v_access->>'reimbursementEvidence', 'hidden');
  v_data := app_private.apply_jsonb_document_access(
    v_data,
    array['basis_urls']::text[],
    v_level
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['remark']::text[],
    v_level
  );

  v_level := coalesce(v_access->>'paymentExecution', 'hidden');
  v_data := app_private.apply_jsonb_text_access(
    v_data,
    array['payment_no', 'paid_by']::text[],
    v_level
  );
  v_data := app_private.apply_jsonb_document_access(
    v_data,
    array['payment_voucher_urls']::text[],
    v_level
  );
  if v_level = 'hidden' then
    v_data := v_data - 'payment_id' - 'payment_reference' - 'paid_at';
  elsif v_level = 'masked' then
    v_data := v_data - 'payment_id';
    if v_data ? 'payment_reference' then
      v_data := jsonb_set(
        v_data,
        '{payment_reference}',
        coalesce(
          to_jsonb(app_private.mask_permission_value(
            v_data->>'payment_reference', 'bank_account'
          )),
          'null'::jsonb
        ),
        true
      );
    end if;
  end if;

  return v_data || jsonb_build_object(
    'field_access', v_access,
    'is_record_owner', p_owner_id = app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.tms_list_expense_reimbursements_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_keyword text default null,
  p_status text default null,
  p_payment_method text default null,
  p_planned_payment_date_start date default null,
  p_planned_payment_date_end date default null,
  p_ids uuid[] default null
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
  v_limit integer := least(greatest(coalesce(p_to, 9) - v_from + 1, 1), 200);
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map(
    'tms.expense_reimbursement', null
  );
  v_row record;
begin
  if not app_private.can_execute_business_action(
    'FinanceExpenseReimbursement', null, null, false
  ) then
    raise exception 'Missing expense reimbursement menu permission'
      using errcode = '42501';
  end if;
  if p_payment_method is not null
     and coalesce(v_base_access->>'payeeDetails', 'hidden') not in ('read', 'edit') then
    raise exception '当前字段权限不足，无法按付款方式筛选'
      using errcode = '42501';
  end if;

  select count(*)::integer
  into v_total
  from public.tms_expense_reimbursement reimbursement_row
  where reimbursement_row.tenant_id = v_tenant_id
    and (p_status is null or reimbursement_row.status = p_status)
    and (p_payment_method is null or reimbursement_row.payment_method = p_payment_method)
    and (
      p_planned_payment_date_start is null
      or reimbursement_row.planned_payment_date >= p_planned_payment_date_start
    )
    and (
      p_planned_payment_date_end is null
      or reimbursement_row.planned_payment_date <= p_planned_payment_date_end
    )
    and (p_ids is null or reimbursement_row.id = any(p_ids))
    and (
      nullif(btrim(coalesce(p_keyword, '')), '') is null
      or reimbursement_row.reimbursement_no ilike '%' || btrim(p_keyword) || '%'
      or reimbursement_row.applicant_name_snapshot ilike '%' || btrim(p_keyword) || '%'
      or exists (
        select 1
        from public.tms_expense_reimbursement_item item_row
        where item_row.reimbursement_id = reimbursement_row.id
          and item_row.tenant_id = reimbursement_row.tenant_id
          and (
            item_row.waybill_no_snapshot ilike '%' || btrim(p_keyword) || '%'
            or item_row.cost_no_snapshot ilike '%' || btrim(p_keyword) || '%'
          )
      )
      or (
        coalesce(v_base_access->>'payeeDetails', 'hidden') in ('read', 'edit')
        and reimbursement_row.payee_name ilike '%' || btrim(p_keyword) || '%'
      )
      or (
        coalesce(v_base_access->>'paymentExecution', 'hidden') in ('read', 'edit')
        and reimbursement_row.payment_reference ilike '%' || btrim(p_keyword) || '%'
      )
      or (
        coalesce(v_base_access->>'paymentExecution', 'hidden') in ('read', 'edit')
        and exists (
          select 1
          from public.tms_expense_payment payment_row
          where payment_row.reimbursement_id = reimbursement_row.id
            and payment_row.tenant_id = reimbursement_row.tenant_id
            and payment_row.payment_no ilike '%' || btrim(p_keyword) || '%'
        )
      )
    );

  for v_row in
    select reimbursement_row.id, reimbursement_row.created_by_user_id
    from public.tms_expense_reimbursement reimbursement_row
    where reimbursement_row.tenant_id = v_tenant_id
      and (p_status is null or reimbursement_row.status = p_status)
      and (p_payment_method is null or reimbursement_row.payment_method = p_payment_method)
      and (
        p_planned_payment_date_start is null
        or reimbursement_row.planned_payment_date >= p_planned_payment_date_start
      )
      and (
        p_planned_payment_date_end is null
        or reimbursement_row.planned_payment_date <= p_planned_payment_date_end
      )
      and (p_ids is null or reimbursement_row.id = any(p_ids))
      and (
        nullif(btrim(coalesce(p_keyword, '')), '') is null
        or reimbursement_row.reimbursement_no ilike '%' || btrim(p_keyword) || '%'
        or reimbursement_row.applicant_name_snapshot ilike '%' || btrim(p_keyword) || '%'
        or exists (
          select 1
          from public.tms_expense_reimbursement_item item_row
          where item_row.reimbursement_id = reimbursement_row.id
            and item_row.tenant_id = reimbursement_row.tenant_id
            and (
              item_row.waybill_no_snapshot ilike '%' || btrim(p_keyword) || '%'
              or item_row.cost_no_snapshot ilike '%' || btrim(p_keyword) || '%'
            )
        )
        or (
          coalesce(v_base_access->>'payeeDetails', 'hidden') in ('read', 'edit')
          and reimbursement_row.payee_name ilike '%' || btrim(p_keyword) || '%'
        )
        or (
          coalesce(v_base_access->>'paymentExecution', 'hidden') in ('read', 'edit')
          and reimbursement_row.payment_reference ilike '%' || btrim(p_keyword) || '%'
        )
        or (
          coalesce(v_base_access->>'paymentExecution', 'hidden') in ('read', 'edit')
          and exists (
            select 1
            from public.tms_expense_payment payment_row
            where payment_row.reimbursement_id = reimbursement_row.id
              and payment_row.tenant_id = reimbursement_row.tenant_id
              and payment_row.payment_no ilike '%' || btrim(p_keyword) || '%'
          )
        )
      )
    order by reimbursement_row.create_time desc, reimbursement_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.tms_expense_reimbursement_to_secure_json(
        app_private.tms_expense_reimbursement_raw_json(v_row.id, false),
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

create or replace function public.tms_get_expense_reimbursement_secure(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_owner_id uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceExpenseReimbursement', null, null, false
  ) then
    raise exception 'Missing expense reimbursement menu permission'
      using errcode = '42501';
  end if;
  select reimbursement_row.created_by_user_id
  into v_owner_id
  from public.tms_expense_reimbursement reimbursement_row
  where reimbursement_row.id = p_id
    and reimbursement_row.tenant_id = app_private.current_user_tenant_id();
  if not found then return null; end if;
  return app_private.tms_expense_reimbursement_to_secure_json(
    app_private.tms_expense_reimbursement_raw_json(p_id, true),
    v_owner_id
  );
end;
$$;

create or replace function public.validate_tms_expense_reimbursement_submission_secure(
  p_reimbursement_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_reimbursement public.tms_expense_reimbursement%rowtype;
  v_access jsonb;
begin
  select reimbursement_row.*
  into v_reimbursement
  from public.tms_expense_reimbursement reimbursement_row
  where reimbursement_row.id = p_reimbursement_id
    and reimbursement_row.tenant_id = v_tenant_id;
  if not found then raise exception '费用报销单不存在或无权访问'; end if;
  if v_reimbursement.status not in ('draft', 'rejected') then
    raise exception '当前费用报销单状态不允许提交审批';
  end if;
  v_access := app_private.field_access_map(
    'tms.expense_reimbursement', v_reimbursement.created_by_user_id
  );
  if coalesce(v_access->>'reimbursementAmounts', 'hidden') not in ('read', 'edit') then
    raise exception '当前字段权限不足，无法读取报销金额并提交审批'
      using errcode = '42501';
  end if;
  if coalesce(v_access->>'payeeDetails', 'hidden') not in ('read', 'edit') then
    raise exception '当前字段权限不足，无法读取收款信息并提交审批'
      using errcode = '42501';
  end if;
  return jsonb_build_object(
    'amount', v_reimbursement.total_amount,
    'reimbursementNo', v_reimbursement.reimbursement_no,
    'paymentMethod', v_reimbursement.payment_method,
    'plannedPaymentDate', v_reimbursement.planned_payment_date,
    'itemCount', (
      select count(*)::integer
      from public.tms_expense_reimbursement_item item_row
      where item_row.reimbursement_id = v_reimbursement.id
        and item_row.tenant_id = v_reimbursement.tenant_id
    ),
    'waybillCount', (
      select count(distinct item_row.waybill_id)::integer
      from public.tms_expense_reimbursement_item item_row
      where item_row.reimbursement_id = v_reimbursement.id
        and item_row.tenant_id = v_reimbursement.tenant_id
    )
  );
end;
$$;

create or replace function public.start_workflow(
  p_business_type text,
  p_business_id uuid,
  p_business_title text,
  p_context jsonb default '{}'::jsonb,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_instance_id uuid;
  v_context jsonb := coalesce(p_context, '{}'::jsonb);
  v_title text := p_business_title;
begin
  if app_private.is_driver_user() then
    raise exception '司机端请通过对应的业务上报入口提交审批'
      using errcode = '42501';
  end if;
  if p_business_type = 'tms_waybill_cost' then
    perform public.validate_tms_waybill_cost_submission_secure(p_business_id);
  elsif p_business_type = 'tms_expense_reimbursement' then
    v_context := v_context ||
      public.validate_tms_expense_reimbursement_submission_secure(p_business_id);
    v_title := '费用报销 ' || coalesce(v_context->>'reimbursementNo', p_business_id::text);
  end if;
  v_instance_id := app_private.start_workflow(
    p_business_type, p_business_id, v_title, v_context, p_idempotency_key
  );
  if p_business_type = 'tms_waybill_cost' then
    update public.wf_instance
    set context_snapshot = coalesce(context_snapshot, '{}'::jsonb) - 'amount'
    where id = v_instance_id
      and business_type = 'tms_waybill_cost'
      and tenant_id = app_private.current_user_tenant_id();
  elsif p_business_type = 'tms_expense_reimbursement' then
    update public.wf_instance
    set business_title = v_title,
        context_snapshot = coalesce(context_snapshot, '{}'::jsonb)
          - 'amount'
          - 'paymentMethod'
          - 'payeeName'
          - 'payeeBank'
          - 'payeeAccount'
    where id = v_instance_id
      and business_type = 'tms_expense_reimbursement'
      and tenant_id = app_private.current_user_tenant_id();
  end if;
  return v_instance_id;
end;
$$;

update public.wf_instance instance_row
set business_title = '费用报销 ' || reimbursement_row.reimbursement_no,
    context_snapshot = coalesce(instance_row.context_snapshot, '{}'::jsonb)
      - 'amount'
      - 'paymentMethod'
      - 'payeeName'
      - 'payeeBank'
      - 'payeeAccount'
from public.tms_expense_reimbursement reimbursement_row
where instance_row.business_type = 'tms_expense_reimbursement'
  and instance_row.business_id = reimbursement_row.id
  and instance_row.tenant_id = reimbursement_row.tenant_id;

create or replace function public.execute_fms_expense_reimbursement_secure(
  p_reimbursement_id uuid,
  p_fund_account_id uuid,
  p_payment_date date,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null,
  p_payment_no text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_reimbursement public.tms_expense_reimbursement%rowtype;
  v_access jsonb;
  v_payment_id uuid;
begin
  select reimbursement_row.*
  into v_reimbursement
  from public.tms_expense_reimbursement reimbursement_row
  where reimbursement_row.id = p_reimbursement_id
    and reimbursement_row.tenant_id = v_tenant_id;
  if not found then raise exception '费用报销单不存在或无权付款'; end if;

  v_access := app_private.field_access_map(
    'tms.expense_reimbursement', v_reimbursement.created_by_user_id
  );
  if coalesce(v_access->>'reimbursementAmounts', 'hidden') not in ('read', 'edit')
     or coalesce(v_access->>'payeeDetails', 'hidden') not in ('read', 'edit')
     or coalesce(v_access->>'paymentExecution', 'hidden') <> 'edit' then
    raise exception '当前字段权限不足，无法登记报销付款'
      using errcode = '42501';
  end if;

  perform app_private.validate_fms_fund_account_assignment(
    p_fund_account_id, v_tenant_id, true
  );
  perform set_config(
    'app.document_number.tms_expense_payment',
    coalesce(p_payment_no, ''),
    true
  );
  v_payment_id := public.execute_tms_expense_reimbursement(
    p_reimbursement_id,
    p_payment_date,
    p_bank_reference,
    p_voucher_urls,
    p_remark
  );
  update public.tms_expense_payment
  set fund_account_id = p_fund_account_id
  where id = v_payment_id
    and tenant_id = v_tenant_id;
  return v_payment_id;
end;
$$;

create or replace function app_private.get_expense_reimbursement_workflow_snapshot(
  p_instance_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_instance public.wf_instance%rowtype;
  v_reimbursement record;
  v_access jsonb;
  v_amount_level text;
  v_payee_level text;
  v_evidence_level text;
  v_payment_level text;
  v_metrics jsonb := '[]'::jsonb;
  v_fields jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;
  v_attachments jsonb := '[]'::jsonb;
begin
  if auth.uid() is null or not app_private.can_view_workflow_instance(p_instance_id) then
    raise exception '无权查看该审批业务信息' using errcode = '42501';
  end if;
  select instance_row.*
  into v_instance
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;
  if not found then raise exception '审批实例不存在'; end if;

  select reimbursement_row.*,
         (select count(*)::integer
          from public.tms_expense_reimbursement_item item_row
          where item_row.reimbursement_id = reimbursement_row.id
            and item_row.tenant_id = reimbursement_row.tenant_id) as item_count,
         (select string_agg(
            distinct item_row.waybill_no_snapshot,
            '、' order by item_row.waybill_no_snapshot
          )
          from public.tms_expense_reimbursement_item item_row
          where item_row.reimbursement_id = reimbursement_row.id
            and item_row.tenant_id = reimbursement_row.tenant_id) as waybill_nos
  into v_reimbursement
  from public.tms_expense_reimbursement reimbursement_row
  where reimbursement_row.id = v_instance.business_id
    and reimbursement_row.tenant_id = v_instance.tenant_id;

  if not found then
    return jsonb_build_object(
      'instanceId', v_instance.id,
      'businessType', v_instance.business_type,
      'businessId', v_instance.business_id,
      'title', v_instance.business_title,
      'subtitle', null,
      'businessNo', null,
      'status', null,
      'routePath', '/fms/settlement/expense-reimbursement',
      'metrics', '[]'::jsonb,
      'fields', '[]'::jsonb,
      'warnings', jsonb_build_array('业务原单已删除，当前仅展示流程基本信息'),
      'attachments', '[]'::jsonb
    );
  end if;

  v_access := app_private.field_access_map(
    'tms.expense_reimbursement', v_reimbursement.created_by_user_id
  );
  v_amount_level := coalesce(v_access->>'reimbursementAmounts', 'hidden');
  v_payee_level := coalesce(v_access->>'payeeDetails', 'hidden');
  v_evidence_level := coalesce(v_access->>'reimbursementEvidence', 'hidden');
  v_payment_level := coalesce(v_access->>'paymentExecution', 'hidden');

  if v_amount_level <> 'hidden' then
    v_metrics := v_metrics || jsonb_build_array(jsonb_build_object(
      'label', '报销金额',
      'value', case when v_amount_level = 'masked' then '***'
        else '¥ ' || to_char(
          coalesce(v_reimbursement.total_amount, 0), 'FM999,999,990.00'
        ) end,
      'tone', 'warning'
    ));
    if v_amount_level = 'masked' then
      v_warnings := v_warnings || jsonb_build_array('报销金额已按字段权限脱敏');
    end if;
  end if;
  v_metrics := v_metrics || jsonb_build_array(
    jsonb_build_object(
      'label', '费用笔数',
      'value', coalesce(v_reimbursement.item_count, 0)::text || ' 笔',
      'tone', 'primary'
    ),
    jsonb_build_object(
      'label', '计划付款日',
      'value', coalesce(v_reimbursement.planned_payment_date::text, '--'),
      'tone', 'info'
    )
  );

  v_fields := jsonb_build_array(
    jsonb_build_object(
      'label', '申请人',
      'value', coalesce(v_reimbursement.applicant_name_snapshot, '--')
    ),
    jsonb_build_object(
      'label', '关联运单',
      'value', coalesce(v_reimbursement.waybill_nos, '--')
    )
  );
  if v_payee_level <> 'hidden' then
    v_fields := v_fields || jsonb_build_array(
      jsonb_build_object(
        'label', '收款人',
        'value', case when v_payee_level = 'masked' then '***'
          else coalesce(v_reimbursement.payee_name, '--') end
      ),
      jsonb_build_object(
        'label', '收款账号',
        'value', case when v_payee_level = 'masked' then
          coalesce(app_private.mask_permission_value(
            v_reimbursement.payee_account, 'bank_account'
          ), '--')
          else coalesce(v_reimbursement.payee_account, '--') end
      )
    );
  end if;
  if v_evidence_level <> 'hidden' then
    v_fields := v_fields || jsonb_build_array(jsonb_build_object(
      'label', '报销说明',
      'value', case when v_evidence_level = 'masked' then '***'
        else coalesce(v_reimbursement.remark, '--') end
    ));
  end if;
  if v_payment_level <> 'hidden' and v_reimbursement.payment_reference is not null then
    v_fields := v_fields || jsonb_build_array(jsonb_build_object(
      'label', '付款流水',
      'value', case when v_payment_level = 'masked' then
        app_private.mask_permission_value(
          v_reimbursement.payment_reference, 'bank_account'
        ) else v_reimbursement.payment_reference end
    ));
  end if;

  if v_evidence_level in ('read', 'edit') then
    v_attachments := v_attachments || app_private.workflow_attachment_list(
      v_reimbursement.basis_urls
    );
  elsif jsonb_array_length(coalesce(v_reimbursement.basis_urls, '[]'::jsonb)) > 0 then
    v_warnings := v_warnings || jsonb_build_array('报销依据已按字段权限隐藏');
  end if;
  if v_payment_level in ('read', 'edit') then
    v_attachments := v_attachments || app_private.workflow_attachment_list(
      v_reimbursement.payment_voucher_urls
    );
  elsif jsonb_array_length(
    coalesce(v_reimbursement.payment_voucher_urls, '[]'::jsonb)
  ) > 0 then
    v_warnings := v_warnings || jsonb_build_array('付款凭证已按字段权限隐藏');
  end if;

  return jsonb_build_object(
    'instanceId', v_instance.id,
    'businessType', v_instance.business_type,
    'businessId', v_instance.business_id,
    'title', '费用报销 ' || v_reimbursement.reimbursement_no,
    'subtitle', case when v_payee_level in ('read', 'edit')
      then v_reimbursement.payee_name else null end,
    'businessNo', v_reimbursement.reimbursement_no,
    'status', v_reimbursement.status,
    'routePath', '/fms/settlement/expense-reimbursement/detail/' ||
      v_reimbursement.id::text,
    'metrics', v_metrics,
    'fields', v_fields,
    'warnings', v_warnings,
    'attachments', v_attachments
  );
end;
$$;

alter function app_private.get_workflow_business_snapshot_v2(uuid)
  rename to get_workflow_business_snapshot_v2_before_reimbursement;

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
  v_business_type text;
begin
  select instance_row.business_type
  into v_business_type
  from public.wf_instance instance_row
  where instance_row.id = p_instance_id;
  if v_business_type = 'tms_expense_reimbursement' then
    return app_private.get_expense_reimbursement_workflow_snapshot(p_instance_id);
  end if;
  return app_private.get_workflow_business_snapshot_v2_before_reimbursement(
    p_instance_id
  );
end;
$$;

revoke all on table public.tms_expense_reimbursement
  from public, anon, authenticated;
revoke all on table public.tms_expense_reimbursement_item
  from public, anon, authenticated;
revoke all on table public.tms_expense_reimbursement_summary
  from public, anon, authenticated;

grant select, insert, update, delete on table public.tms_expense_reimbursement
  to service_role;
grant select, insert, update, delete on table public.tms_expense_reimbursement_item
  to service_role;
grant select on table public.tms_expense_reimbursement_summary
  to service_role;

revoke all on function app_private.tms_expense_reimbursement_raw_json(uuid, boolean)
  from public, anon, authenticated;
revoke all on function app_private.tms_expense_reimbursement_to_secure_json(
  jsonb, uuid, jsonb
) from public, anon, authenticated;
revoke all on function app_private.get_expense_reimbursement_workflow_snapshot(uuid)
  from public, anon, authenticated;

revoke all on function public.tms_list_expense_reimbursements_secure(
  integer, integer, text, text, text, date, date, uuid[]
) from public, anon;
revoke all on function public.tms_get_expense_reimbursement_secure(uuid)
  from public, anon;
revoke all on function public.validate_tms_expense_reimbursement_submission_secure(uuid)
  from public, anon;
revoke all on function public.execute_fms_expense_reimbursement_secure(
  uuid, uuid, date, text, jsonb, text, text
) from public, anon;

grant execute on function public.tms_list_expense_reimbursements_secure(
  integer, integer, text, text, text, date, date, uuid[]
) to authenticated, service_role;
grant execute on function public.tms_get_expense_reimbursement_secure(uuid)
  to authenticated, service_role;
grant execute on function public.validate_tms_expense_reimbursement_submission_secure(uuid)
  to authenticated, service_role;
grant execute on function public.execute_fms_expense_reimbursement_secure(
  uuid, uuid, date, text, jsonb, text, text
) to authenticated, service_role;

revoke all on function public.execute_fms_expense_reimbursement(
  uuid, uuid, date, text, jsonb, text, text
) from public, anon, authenticated;
revoke all on function public.execute_tms_expense_reimbursement(
  uuid, date, text, jsonb, text
) from public, anon, authenticated;
revoke all on function public.execute_tms_expense_reimbursement(
  uuid, date, text, jsonb, text, text
) from public, anon, authenticated;
grant execute on function public.execute_fms_expense_reimbursement(
  uuid, uuid, date, text, jsonb, text, text
) to service_role;
grant execute on function public.execute_tms_expense_reimbursement(
  uuid, date, text, jsonb, text
) to service_role;
grant execute on function public.execute_tms_expense_reimbursement(
  uuid, date, text, jsonb, text, text
) to service_role;

revoke all on function public.start_workflow(text, uuid, text, jsonb, text)
  from public, anon;
grant execute on function public.start_workflow(text, uuid, text, jsonb, text)
  to authenticated, service_role;

do $$
begin
  if exists (
    select 1
    from public.tms_expense_reimbursement
    where created_by_user_id is null
  ) then
    raise exception 'Expense reimbursement creator backfill is incomplete';
  end if;
  if (
    select count(*)
    from public.sys_permission_resource resource_row
    join public.sys_permission_field field_row
      on field_row.resource_id = resource_row.id
     and field_row.tenant_id = resource_row.tenant_id
    where resource_row.resource_key = 'tms.expense_reimbursement'
      and field_row.enabled
  ) < (select count(*) * 4 from public.sys_tenant) then
    raise exception 'Expense reimbursement field permission catalog is incomplete';
  end if;
  if has_table_privilege(
    'authenticated', 'public.tms_expense_reimbursement', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.tms_expense_reimbursement_item', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.tms_expense_reimbursement_summary', 'SELECT'
  ) then
    raise exception 'Authenticated direct expense reimbursement access is still enabled';
  end if;
  if has_function_privilege(
    'anon',
    'public.tms_get_expense_reimbursement_secure(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Anonymous secure expense reimbursement RPC access is still enabled';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.tms_get_expense_reimbursement_secure(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated secure expense reimbursement RPC access is missing';
  end if;
end;
$$;

;
