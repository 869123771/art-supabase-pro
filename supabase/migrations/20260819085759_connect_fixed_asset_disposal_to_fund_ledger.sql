create or replace function public.act_fms_fixed_asset(
  p_asset_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns public.fms_fixed_asset
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_row public.fms_fixed_asset%rowtype;
  v_event_date date := coalesce(nullif(p_payload ->> 'actionDate', '')::date, current_date);
  v_net_book_value numeric(20,2);
  v_disposal_amount numeric(20,2) := round(coalesce(nullif(p_payload ->> 'amount', '')::numeric, 0), 2);
  v_fund_account_id uuid := nullif(p_payload ->> 'fundAccountId', '')::uuid;
  v_reference_no text := nullif(btrim(p_payload ->> 'referenceNo'), '');
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行资产操作';
  end if;

  select *
  into v_row
  from public.fms_fixed_asset
  where id = p_asset_id
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = '固定资产不存在';
  end if;

  if p_action = 'activate' and v_row.status = 'draft' then
    update public.fms_fixed_asset
    set status = 'active', version = version + 1
    where id = v_row.id
    returning * into v_row;

    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id,
      'fixed_asset',
      'activated',
      v_row.id,
      v_row.asset_no,
      v_event_date,
      concat('固定资产转固 · ', v_row.asset_no, ' · ', v_row.asset_name),
      jsonb_build_object(
        'gross_amount', v_row.original_value,
        'original_value', v_row.original_value,
        'asset_id', v_row.id,
        'category_id', v_row.category_id
      )
    );
  elsif p_action = 'suspend' and v_row.status = 'active' then
    update public.fms_fixed_asset
    set status = 'suspended', version = version + 1
    where id = v_row.id
    returning * into v_row;
  elsif p_action = 'resume' and v_row.status = 'suspended' then
    update public.fms_fixed_asset
    set status = 'active', version = version + 1
    where id = v_row.id
    returning * into v_row;
  elsif p_action = 'dispose' and v_row.status in ('active', 'suspended') then
    if nullif(btrim(p_payload ->> 'reason'), '') is null then
      raise exception using errcode = '23502', message = '资产处置必须填写原因';
    end if;
    if v_disposal_amount < 0 then
      raise exception using errcode = '23514', message = '资产处置收入不能小于零';
    end if;
    if v_disposal_amount > 0 and v_fund_account_id is null then
      raise exception using errcode = '23502', message = '有处置收入时必须选择实际收款账户';
    end if;
    if v_disposal_amount > 0 and not exists (
      select 1
      from public.fms_fund_account fa
      join public.fms_account_set aset on aset.id = fa.account_set_id
      where fa.id = v_fund_account_id
        and fa.tenant_id = v_row.tenant_id
        and fa.account_set_id = v_row.account_set_id
        and fa.status = 'active'
        and fa.currency_id = aset.base_currency_id
    ) then
      raise exception using errcode = '23503', message = '收款账户不属于当前账套、本位币不一致或账户不可用';
    end if;

    update public.fms_fixed_asset
    set
      status = 'disposed',
      disposal_date = v_event_date,
      disposal_amount = v_disposal_amount,
      disposal_reason = btrim(p_payload ->> 'reason'),
      version = version + 1
    where id = v_row.id
    returning * into v_row;

    v_net_book_value := greatest(
      v_row.original_value - v_row.accumulated_depreciation - v_row.impairment_amount,
      0
    );

    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id,
      'fixed_asset',
      'disposed',
      v_row.id,
      v_row.asset_no,
      v_event_date,
      concat('固定资产处置 · ', v_row.asset_no, ' · ', v_row.asset_name),
      jsonb_build_object(
        'gross_amount', v_row.disposal_amount,
        'asset_id', v_row.id,
        'category_id', v_row.category_id,
        'original_value', v_row.original_value,
        'accumulated_depreciation', v_row.accumulated_depreciation,
        'impairment_amount', v_row.impairment_amount,
        'disposal_gain', greatest(v_row.disposal_amount - v_net_book_value, 0),
        'disposal_loss', greatest(v_net_book_value - v_row.disposal_amount, 0),
        'reason', v_row.disposal_reason
      )
    );

    if v_disposal_amount > 0 then
      perform app_private.post_fms_fund_ledger_entry(
        v_fund_account_id,
        v_event_date,
        'inflow',
        v_disposal_amount,
        'fixed_asset',
        v_row.id,
        v_row.asset_no,
        concat('固定资产处置收入 · ', v_row.asset_no, ' · ', v_row.asset_name),
        null,
        v_reference_no,
        null
      );
    end if;
  else
    raise exception using errcode = '23514', message = '当前资产状态不允许执行该操作';
  end if;

  return v_row;
end;
$function$;;
