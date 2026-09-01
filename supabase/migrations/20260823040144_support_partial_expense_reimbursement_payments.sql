-- Allow one approved expense reimbursement to be paid in several cashier payments.

alter table public.tms_expense_payment
  drop constraint if exists tms_expense_payment_reimbursement_id_key;

create index if not exists tms_expense_payment_reimbursement_created_idx
  on public.tms_expense_payment (reimbursement_id, create_time desc, id);

alter table public.tms_expense_reimbursement
  drop constraint if exists tms_expense_reimbursement_status_check;

alter table public.tms_expense_reimbursement
  add constraint tms_expense_reimbursement_status_check
  check (
    status = any (
      array[
        'draft'::text,
        'pending_review'::text,
        'approved'::text,
        'rejected'::text,
        'partially_paid'::text,
        'paid'::text,
        'cancelled'::text
      ]
    )
  );

update public.sys_dictionary dictionary_row
set sort = case dictionary_row.value
    when 'paid' then 6
    when 'cancelled' then 7
    else dictionary_row.sort
  end,
  update_by = '624944977@qq.com',
  update_time = now()
from public.sys_dict_type type_row
where dictionary_row.type_id = type_row.id
  and dictionary_row.tenant_id = type_row.tenant_id
  and type_row.code = 'tmsReimbursementApprovalStatus'
  and dictionary_row.value in ('paid', 'cancelled');

insert into public.sys_dictionary (
  type_id,
  code,
  status,
  create_by,
  update_by,
  remark,
  value,
  label,
  i18n_scope,
  sort,
  tenant_id,
  tag_type
)
select
  type_row.id,
  'partially_paid',
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  '累计实付金额小于申请报销金额，可继续登记付款',
  'partially_paid',
  '已部分付款',
  '1',
  5,
  type_row.tenant_id,
  'warning'
from public.sys_dict_type type_row
where type_row.code = 'tmsReimbursementApprovalStatus'
  and not exists (
    select 1
    from public.sys_dictionary existing_row
    where existing_row.type_id = type_row.id
      and existing_row.tenant_id = type_row.tenant_id
      and existing_row.value = 'partially_paid'
  );

create or replace function app_private.tms_expense_reimbursement_raw_json(
  p_reimbursement_id uuid,
  p_include_items boolean default true
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
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
      'paid_amount', coalesce(payment_summary.paid_amount, 0)::numeric(14, 2),
      'remaining_amount', greatest(
        reimbursement_row.total_amount - coalesce(payment_summary.paid_amount, 0),
        0
      )::numeric(14, 2),
      'payment_count', coalesce(payment_summary.payment_count, 0),
      'payment_id', payment_summary.latest_payment_id,
      'payment_no', payment_summary.latest_payment_no
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
  left join lateral (
    select
      coalesce(sum(payment_row.amount), 0) as paid_amount,
      count(*)::integer as payment_count,
      (array_agg(payment_row.id order by payment_row.create_time desc, payment_row.id desc))[1]
        as latest_payment_id,
      (array_agg(payment_row.payment_no order by payment_row.create_time desc, payment_row.id desc))[1]
        as latest_payment_no
    from public.tms_expense_payment payment_row
    where payment_row.reimbursement_id = reimbursement_row.id
      and payment_row.tenant_id = reimbursement_row.tenant_id
  ) payment_summary on true
  where reimbursement_row.id = p_reimbursement_id
    and reimbursement_row.tenant_id = app_private.current_user_tenant_id();
$function$;

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
as $function$
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
    array['total_amount', 'paid_amount', 'remaining_amount']::text[],
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
$function$;

drop function if exists public.execute_fms_expense_reimbursement_secure(
  uuid, uuid, date, text, jsonb, text, text
);
drop function if exists public.execute_tms_expense_reimbursement(
  uuid, date, text, jsonb, text, text
);
drop function if exists public.execute_tms_expense_reimbursement(
  uuid, date, text, jsonb, text
);

create function public.execute_tms_expense_reimbursement(
  p_reimbursement_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_bank_reference text default null,
  p_voucher_urls jsonb default '[]'::jsonb,
  p_remark text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_actor text := coalesce(nullif(auth.jwt() ->> 'email', ''), auth.uid()::text);
  v_reimbursement public.tms_expense_reimbursement%rowtype;
  v_paid_amount numeric(14, 2);
  v_payment_amount numeric(14, 2);
  v_remaining_amount numeric(14, 2);
  v_total_paid numeric(14, 2);
  v_payment_id uuid;
  v_is_fully_paid boolean;
begin
  if auth.uid() is null or v_tenant_id is null then
    raise exception '请登录后操作';
  end if;
  if p_payment_date is null then
    raise exception '请选择实际付款日期';
  end if;
  if jsonb_typeof(coalesce(p_voucher_urls, '[]'::jsonb)) <> 'array' then
    raise exception '付款凭证格式不正确';
  end if;

  v_payment_amount := round(p_amount, 2);
  if v_payment_amount is null or v_payment_amount <= 0 then
    raise exception '实付金额必须大于 0';
  end if;
  if p_amount <> v_payment_amount then
    raise exception '实付金额最多保留两位小数';
  end if;

  select reimbursement_row.*
  into v_reimbursement
  from public.tms_expense_reimbursement reimbursement_row
  where reimbursement_row.id = p_reimbursement_id
    and reimbursement_row.tenant_id = v_tenant_id
  for update;
  if not found then
    raise exception '费用报销单不存在或无权付款';
  end if;
  if v_reimbursement.status not in ('approved', 'partially_paid') then
    raise exception '仅已批准待付款或已部分付款的报销单可以登记付款';
  end if;
  if v_reimbursement.payment_method = 'bank_transfer'
     and nullif(btrim(coalesce(p_bank_reference, '')), '') is null then
    raise exception '银行转账必须填写银行流水号';
  end if;

  select coalesce(sum(payment_row.amount), 0)::numeric(14, 2)
  into v_paid_amount
  from public.tms_expense_payment payment_row
  where payment_row.reimbursement_id = v_reimbursement.id
    and payment_row.tenant_id = v_reimbursement.tenant_id;

  v_remaining_amount := greatest(v_reimbursement.total_amount - v_paid_amount, 0);
  if v_remaining_amount <= 0 then
    raise exception '该费用报销单已全部付清';
  end if;
  if v_payment_amount > v_remaining_amount then
    raise exception '实付金额不能大于剩余待付金额 % 元', v_remaining_amount;
  end if;

  perform set_config('app.expense_payment_engine', 'on', true);
  insert into public.tms_expense_payment (
    tenant_id,
    payment_no,
    reimbursement_id,
    payee_name_snapshot,
    payment_date,
    amount,
    payment_method,
    bank_reference,
    voucher_urls,
    remark,
    paid_by,
    create_by,
    update_by
  ) values (
    v_reimbursement.tenant_id,
    '',
    v_reimbursement.id,
    v_reimbursement.payee_name,
    p_payment_date,
    v_payment_amount,
    v_reimbursement.payment_method,
    nullif(btrim(coalesce(p_bank_reference, '')), ''),
    coalesce(p_voucher_urls, '[]'::jsonb),
    nullif(btrim(coalesce(p_remark, '')), ''),
    v_actor,
    v_actor,
    v_actor
  ) returning id into v_payment_id;

  v_total_paid := v_paid_amount + v_payment_amount;
  v_is_fully_paid := v_total_paid = v_reimbursement.total_amount;

  update public.tms_expense_reimbursement
  set status = case when v_is_fully_paid then 'paid' else 'partially_paid' end,
      paid_at = case when v_is_fully_paid then now() else null end,
      paid_by = case when v_is_fully_paid then v_actor else null end,
      payment_reference = nullif(btrim(coalesce(p_bank_reference, '')), ''),
      payment_voucher_urls = coalesce(p_voucher_urls, '[]'::jsonb)
  where id = v_reimbursement.id;

  if v_is_fully_paid then
    update public.tms_waybill_cost cost_row
    set settlement_status = 'paid',
        expense_payment_id = v_payment_id,
        paid_at = now()
    from public.tms_expense_reimbursement_item item_row
    where item_row.reimbursement_id = v_reimbursement.id
      and item_row.cost_id = cost_row.id;
  end if;

  return v_payment_id;
end;
$function$;

revoke all on function public.execute_tms_expense_reimbursement(
  uuid, numeric, date, text, jsonb, text
) from public, anon, authenticated;
grant execute on function public.execute_tms_expense_reimbursement(
  uuid, numeric, date, text, jsonb, text
) to service_role;

create function public.execute_fms_expense_reimbursement_secure(
  p_reimbursement_id uuid,
  p_fund_account_id uuid,
  p_amount numeric,
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
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_reimbursement public.tms_expense_reimbursement%rowtype;
  v_access jsonb;
  v_payment_id uuid;
begin
  if not app_private.can_execute_business_action(
    'FinanceWaybillCost', 'FinanceWaybillCost:Pay', null, false
  ) then
    raise exception 'Missing expense reimbursement payment permission'
      using errcode = '42501';
  end if;

  select reimbursement_row.*
  into v_reimbursement
  from public.tms_expense_reimbursement reimbursement_row
  where reimbursement_row.id = p_reimbursement_id
    and reimbursement_row.tenant_id = v_tenant_id;
  if not found then
    raise exception '费用报销单不存在或无权付款';
  end if;

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
    p_amount,
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
$function$;

revoke all on function public.execute_fms_expense_reimbursement_secure(
  uuid, uuid, numeric, date, text, jsonb, text, text
) from public, anon;
grant execute on function public.execute_fms_expense_reimbursement_secure(
  uuid, uuid, numeric, date, text, jsonb, text, text
) to authenticated, service_role;

notify pgrst, 'reload schema';

;
