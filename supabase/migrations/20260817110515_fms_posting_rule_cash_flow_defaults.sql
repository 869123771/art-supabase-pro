begin;

alter table public.fms_posting_rule_line
  add column cash_flow_item_id uuid;

alter table public.fms_posting_rule_line
  add constraint fms_posting_rule_line_cash_flow_item_fkey
  foreign key (cash_flow_item_id, account_set_id, tenant_id)
  references public.fms_financial_statement_item (id, account_set_id, tenant_id)
  on delete restrict;

create index fms_posting_rule_line_cash_flow_item_idx
  on public.fms_posting_rule_line (cash_flow_item_id)
  where cash_flow_item_id is not null;

create or replace function app_private.guard_fms_posting_rule_cash_flow_item()
returns trigger
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_subject public.fms_subject%rowtype;
  v_item public.fms_financial_statement_item%rowtype;
  v_expected_direction text;
begin
  select * into v_subject from public.fms_subject where id = new.subject_id;
  if not coalesce(v_subject.cash_flow_required, false) then
    if new.cash_flow_item_id is not null then
      raise exception using errcode = '23514', message = '非现金科目分录不能配置现金流量项目';
    end if;
    return new;
  end if;

  if new.cash_flow_item_id is null then
    raise exception using errcode = '23514', message = '现金科目自动制证分录必须配置现金流量项目';
  end if;
  select * into v_item
  from public.fms_financial_statement_item
  where id = new.cash_flow_item_id;
  v_expected_direction := case new.direction when 'debit' then 'receipt' else 'payment' end;
  if v_item.id is null
     or v_item.account_set_id <> new.account_set_id
     or v_item.tenant_id <> new.tenant_id
     or v_item.statement_type <> 'cash_flow_statement'
     or v_item.calculation_method <> 'mapping'
     or v_item.cash_flow_direction <> v_expected_direction
     or not v_item.is_enabled then
    raise exception using errcode = '23514', message = '自动制证现金流量项目与账套、分录方向或启用状态不匹配';
  end if;
  return new;
end;
$$;

create trigger fms_posting_rule_line_cash_flow_guard
before insert or update of subject_id, direction, cash_flow_item_id
on public.fms_posting_rule_line
for each row execute function app_private.guard_fms_posting_rule_cash_flow_item();

do $$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef('public.save_fms_posting_rule(jsonb)'::regprocedure)
  into v_definition;
  v_updated := replace(
    v_definition,
    'amount_multiplier, subject_id, summary, auxiliary_bindings, create_by, update_by',
    'amount_multiplier, subject_id, cash_flow_item_id, summary, auxiliary_bindings, create_by, update_by'
  );
  v_updated := replace(
    v_updated,
    $find$      (v_line ->> 'subjectId')::uuid,
      nullif(btrim(v_line ->> 'summary'), ''),$find$,
    $replace$      (v_line ->> 'subjectId')::uuid,
      nullif(v_line ->> 'cashFlowItemId', '')::uuid,
      nullif(btrim(v_line ->> 'summary'), ''),$replace$
  );
  if v_updated = v_definition then
    raise exception 'Unable to extend automatic posting rule persistence with cash-flow defaults';
  end if;
  execute v_updated;
end;
$$;

do $$
declare
  v_definition text;
  v_updated text;
begin
  select pg_get_functiondef(
    'app_private.process_fms_posting_event(uuid,boolean)'::regprocedure
  ) into v_definition;
  v_updated := replace(
    v_definition,
    '    perform app_private.assert_fms_voucher_ready(v_voucher.id);',
    $replacement$    insert into public.fms_cash_flow_allocation (
      tenant_id, account_set_id, voucher_line_id, statement_item_id,
      flow_direction, amount, remark
    )
    select line.tenant_id, line.account_set_id, line.id, rule_line.cash_flow_item_id,
      case when line.debit_amount > 0 then 'receipt' else 'payment' end,
      greatest(line.debit_amount, line.credit_amount),
      '自动制证规则默认现金流量项目'
    from public.fms_voucher_line line
    join public.fms_posting_rule_line rule_line
      on rule_line.id = line.source_line_id
    where line.voucher_id = v_voucher.id
      and line.source_line_type = 'posting_rule_line'
      and rule_line.cash_flow_item_id is not null;

    perform app_private.assert_fms_voucher_ready(v_voucher.id);$replacement$
  );
  if v_updated = v_definition then
    raise exception 'Unable to connect automatic posting with cash-flow allocations';
  end if;
  execute v_updated;
end;
$$;

revoke all on function app_private.guard_fms_posting_rule_cash_flow_item()
  from public, anon, authenticated;

commit;

;
