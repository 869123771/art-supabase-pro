
alter table public.fms_posting_rule
  drop constraint if exists fms_posting_rule_source_check;
alter table public.fms_posting_rule
  add constraint fms_posting_rule_source_check
  check (source_type = any (array[
    'customer_statement','carrier_statement','customer_receipt','carrier_payment',
    'invoice','expense_reimbursement','waybill_cost','system',
    'commercial_bill','fixed_asset','asset_depreciation','payroll','tax','period_close'
  ]::text[]));

alter table public.fms_voucher
  drop constraint if exists fms_voucher_source_check;
alter table public.fms_voucher
  add constraint fms_voucher_source_check
  check (source_type = any (array[
    'manual','customer_statement','carrier_statement','customer_receipt','carrier_payment',
    'invoice','expense_reimbursement','waybill_cost','system','reversal',
    'commercial_bill','fixed_asset','asset_depreciation','payroll','tax','period_close'
  ]::text[]));

alter table public.fms_posting_rule_line
  drop constraint if exists fms_posting_rule_line_amount_key_check;
alter table public.fms_posting_rule_line
  add constraint fms_posting_rule_line_amount_key_check
  check (amount_key = any (array[
    'gross_amount','net_amount','tax_amount',
    'original_value','accumulated_depreciation','impairment_amount',
    'disposal_gain','disposal_loss',
    'salary_gross_amount','deduction_amount','employer_cost_amount',
    'output_tax_amount','input_tax_amount'
  ]::text[]));

with dict_type as (
  select id, tenant_id
  from public.sys_dict_type
  where code = 'fmsPostingAmountKey'
  order by create_time
  limit 1
), new_items(value,label,sort) as (
  values
    ('original_value','资产原值',10),
    ('accumulated_depreciation','累计折旧',11),
    ('impairment_amount','资产减值准备',12),
    ('disposal_gain','资产处置收益',13),
    ('disposal_loss','资产处置损失',14),
    ('salary_gross_amount','应发薪资',20),
    ('deduction_amount','个人扣款与代扣税费',21),
    ('employer_cost_amount','企业承担人工成本',22),
    ('output_tax_amount','销项税额',30),
    ('input_tax_amount','进项税额',31)
)
insert into public.sys_dictionary (
  type_id, code, value, label, status, sort, tenant_id, create_by, update_by
)
select t.id, i.value, i.value, i.label, '1', i.sort, t.tenant_id,
       'migration', 'migration'
from dict_type t cross join new_items i
where not exists (
  select 1 from public.sys_dictionary d
  where d.type_id=t.id and d.value=i.value
);

create or replace function public.act_fms_fixed_asset(
  p_asset_id uuid,
  p_action text,
  p_payload jsonb default '{}'::jsonb
)
returns public.fms_fixed_asset
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_row public.fms_fixed_asset%rowtype;
  v_event_date date := coalesce(nullif(p_payload ->> 'actionDate', '')::date, current_date);
  v_net_book_value numeric(20,2);
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行资产操作';
  end if;
  select * into v_row from public.fms_fixed_asset where id = p_asset_id for update;
  if not found then raise exception using errcode = 'P0002', message = '固定资产不存在'; end if;

  if p_action = 'activate' and v_row.status = 'draft' then
    update public.fms_fixed_asset set status='active', version=version+1
    where id=v_row.id returning * into v_row;
    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id, 'fixed_asset', 'activated', v_row.id, v_row.asset_no, v_event_date,
      concat('固定资产转固 · ', v_row.asset_no, ' · ', v_row.asset_name),
      jsonb_build_object(
        'gross_amount',v_row.original_value,
        'original_value',v_row.original_value,
        'asset_id',v_row.id,
        'category_id',v_row.category_id
      )
    );
  elsif p_action = 'suspend' and v_row.status = 'active' then
    update public.fms_fixed_asset set status='suspended', version=version+1
    where id=v_row.id returning * into v_row;
  elsif p_action = 'resume' and v_row.status = 'suspended' then
    update public.fms_fixed_asset set status='active', version=version+1
    where id=v_row.id returning * into v_row;
  elsif p_action = 'dispose' and v_row.status in ('active','suspended') then
    if nullif(btrim(p_payload ->> 'reason'), '') is null then
      raise exception using errcode = '23502', message = '资产处置必须填写原因';
    end if;
    update public.fms_fixed_asset set
      status='disposed',
      disposal_date=v_event_date,
      disposal_amount=coalesce(nullif(p_payload ->> 'amount', '')::numeric,0),
      disposal_reason=btrim(p_payload ->> 'reason'),
      version=version+1
    where id=v_row.id returning * into v_row;

    v_net_book_value := greatest(
      v_row.original_value - v_row.accumulated_depreciation - v_row.impairment_amount,
      0
    );
    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id, 'fixed_asset', 'disposed', v_row.id, v_row.asset_no, v_event_date,
      concat('固定资产处置 · ', v_row.asset_no, ' · ', v_row.asset_name),
      jsonb_build_object(
        'gross_amount',v_row.disposal_amount,
        'asset_id',v_row.id,
        'category_id',v_row.category_id,
        'original_value',v_row.original_value,
        'accumulated_depreciation',v_row.accumulated_depreciation,
        'impairment_amount',v_row.impairment_amount,
        'disposal_gain',greatest(v_row.disposal_amount-v_net_book_value,0),
        'disposal_loss',greatest(v_net_book_value-v_row.disposal_amount,0),
        'reason',v_row.disposal_reason
      )
    );
  else
    raise exception using errcode = '23514', message = '当前资产状态不允许执行该操作';
  end if;
  return v_row;
end;
$function$;

revoke all on function public.act_fms_fixed_asset(uuid,text,jsonb) from public;
grant execute on function public.act_fms_fixed_asset(uuid,text,jsonb) to authenticated;
;
