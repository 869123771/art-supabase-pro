begin;
create or replace function app_private.guard_fms_opening_balance_write()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.fms_opening_balance%rowtype;
  v_subject public.fms_subject%rowtype;
  v_currency public.fms_currency%rowtype;
begin
  if tg_op = 'DELETE' then v_row := old; else v_row := new; end if;

  if exists (
    select 1 from public.fms_opening_balance_control c
    where c.account_set_id = v_row.account_set_id
      and c.fiscal_year = v_row.fiscal_year
      and c.status = 'confirmed'
  ) then
    raise exception using errcode = '23514', message = '期初余额已确认，请先反确认后再修改';
  end if;

  if exists (
    select 1 from public.fms_accounting_period p
    where p.account_set_id = v_row.account_set_id
      and p.fiscal_year = v_row.fiscal_year
      and p.status in ('closing', 'closed')
  ) then
    raise exception using errcode = '23514', message = '会计期间已进入结账流程，不能修改期初余额';
  end if;

  if tg_op = 'DELETE' then return old; end if;

  select * into v_subject
  from public.fms_subject s
  where s.id = new.subject_id
    and s.account_set_id = new.account_set_id
    and s.tenant_id = new.tenant_id
    and s.is_enabled;

  if not found then
    raise exception using errcode = '23503', message = '会计科目不存在、已停用或核算范围不匹配';
  end if;
  if exists (select 1 from public.fms_subject child where child.parent_id = v_subject.id) then
    raise exception using errcode = '23514', message = '期初余额只能录入末级科目';
  end if;
  if (v_subject.balance_direction = 'debit' and new.opening_credit <> 0)
     or (v_subject.balance_direction = 'credit' and new.opening_debit <> 0) then
    raise exception using errcode = '23514', message = '期初余额必须录入科目规定的余额方向';
  end if;
  if not v_subject.allow_quantity and new.opening_quantity <> 0 then
    raise exception using errcode = '23514', message = '当前科目未启用数量核算';
  end if;
  if new.opening_quantity < 0 or new.original_currency_amount < 0 then
    raise exception using errcode = '23514', message = '期初数量和原币金额不能小于零';
  end if;

  if new.currency_id is not null then
    if not v_subject.allow_foreign_currency then
      raise exception using errcode = '23514', message = '当前科目未启用外币核算';
    end if;
    select * into v_currency
    from public.fms_currency c
    where c.id = new.currency_id
      and c.account_set_id = new.account_set_id
      and c.tenant_id = new.tenant_id
      and c.is_enabled
      and not c.is_base;
    if not found then
      raise exception using errcode = '23503', message = '核算外币不存在、已停用或不是外币';
    end if;
  elsif new.original_currency_amount <> 0 then
    raise exception using errcode = '23514', message = '录入原币金额时必须指定核算外币';
  end if;

  if exists (
    select 1
    from public.fms_subject_auxiliary_type config
    where config.subject_id = v_subject.id
      and config.is_required
      and nullif(new.auxiliary_values ->> config.auxiliary_type_id::text, '') is null
  ) then
    raise exception using errcode = '23502', message = '请完整填写科目要求的辅助核算项目';
  end if;

  if exists (
    select 1
    from jsonb_each_text(new.auxiliary_values) provided(type_id, item_id)
    left join public.fms_subject_auxiliary_type config
      on config.subject_id = v_subject.id
      and config.auxiliary_type_id = provided.type_id::uuid
    left join public.fms_auxiliary_item item
      on item.id = provided.item_id::uuid
      and item.auxiliary_type_id = provided.type_id::uuid
      and item.account_set_id = new.account_set_id
      and item.tenant_id = new.tenant_id
      and item.is_enabled
    where config.id is null or item.id is null
  ) then
    raise exception using errcode = '23503', message = '辅助核算维度或项目无效、已停用或不属于当前科目';
  end if;

  return new;
end;
$$;
drop trigger if exists trg_fms_opening_balance_write_guard on public.fms_opening_balance;
create trigger trg_fms_opening_balance_write_guard
before insert or update or delete on public.fms_opening_balance
for each row execute function app_private.guard_fms_opening_balance_write();
create or replace function app_private.guard_fms_subject_auxiliary_write()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_subject_id uuid;
begin
  v_subject_id := case when tg_op = 'DELETE' then old.subject_id else new.subject_id end;
  if exists (select 1 from public.fms_opening_balance b where b.subject_id = v_subject_id) then
    raise exception using errcode = '23514', message = '科目已有期初余额，不能变更辅助核算配置';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists trg_fms_subject_auxiliary_write_guard on public.fms_subject_auxiliary_type;
create trigger trg_fms_subject_auxiliary_write_guard
before insert or update or delete on public.fms_subject_auxiliary_type
for each row execute function app_private.guard_fms_subject_auxiliary_write();
create or replace function public.save_fms_subject(p_payload jsonb)
returns public.fms_subject
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_subject public.fms_subject%rowtype;
  v_subject_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set_id uuid := (p_payload ->> 'accountSetId')::uuid;
  v_tenant_id uuid := (p_payload ->> 'tenantId')::uuid;
  v_has_opening_balance boolean;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护会计科目';
  end if;

  if v_subject_id is null then
    insert into public.fms_subject (
      tenant_id, account_set_id, parent_id, subject_code, subject_name,
      category, balance_direction, is_enabled, allow_quantity, unit_name,
      allow_foreign_currency, allow_period_end_revaluation, cash_flow_required,
      sort, remark
    ) values (
      v_tenant_id, v_account_set_id, nullif(p_payload ->> 'parentId', '')::uuid,
      btrim(p_payload ->> 'subjectCode'), btrim(p_payload ->> 'subjectName'),
      p_payload ->> 'category', p_payload ->> 'balanceDirection',
      coalesce((p_payload ->> 'isEnabled')::boolean, true),
      coalesce((p_payload ->> 'allowQuantity')::boolean, false),
      nullif(btrim(p_payload ->> 'unitName'), ''),
      coalesce((p_payload ->> 'allowForeignCurrency')::boolean, false),
      coalesce((p_payload ->> 'allowPeriodEndRevaluation')::boolean, false),
      coalesce((p_payload ->> 'cashFlowRequired')::boolean, false),
      coalesce((p_payload ->> 'sort')::integer, 100),
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_subject;
  else
    update public.fms_subject set
      parent_id = nullif(p_payload ->> 'parentId', '')::uuid,
      subject_code = btrim(p_payload ->> 'subjectCode'),
      subject_name = btrim(p_payload ->> 'subjectName'),
      category = p_payload ->> 'category',
      balance_direction = p_payload ->> 'balanceDirection',
      is_enabled = coalesce((p_payload ->> 'isEnabled')::boolean, is_enabled),
      allow_quantity = coalesce((p_payload ->> 'allowQuantity')::boolean, false),
      unit_name = nullif(btrim(p_payload ->> 'unitName'), ''),
      allow_foreign_currency = coalesce((p_payload ->> 'allowForeignCurrency')::boolean, false),
      allow_period_end_revaluation = coalesce((p_payload ->> 'allowPeriodEndRevaluation')::boolean, false),
      cash_flow_required = coalesce((p_payload ->> 'cashFlowRequired')::boolean, false),
      sort = coalesce((p_payload ->> 'sort')::integer, 100),
      remark = nullif(btrim(p_payload ->> 'remark'), '')
    where id = v_subject_id and account_set_id = v_account_set_id and tenant_id = v_tenant_id
    returning * into v_subject;
    if not found then
      raise exception using errcode = 'P0002', message = '会计科目不存在或不属于当前账套';
    end if;
  end if;

  if p_payload ? 'auxiliaryConfigs' then
    select exists (
      select 1 from public.fms_opening_balance b where b.subject_id = v_subject.id
    ) into v_has_opening_balance;

    if v_has_opening_balance and (
      exists (
        select current_config.auxiliary_type_id, current_config.is_required
        from public.fms_subject_auxiliary_type current_config
        where current_config.subject_id = v_subject.id
        except
        select coalesce(config ->> 'auxiliaryTypeId', config ->> 'auxiliary_type_id')::uuid,
          coalesce(config ->> 'isRequired', config ->> 'is_required')::boolean
        from jsonb_array_elements(coalesce(p_payload -> 'auxiliaryConfigs', '[]'::jsonb)) config
      )
      or exists (
        select coalesce(config ->> 'auxiliaryTypeId', config ->> 'auxiliary_type_id')::uuid,
          coalesce(config ->> 'isRequired', config ->> 'is_required')::boolean
        from jsonb_array_elements(coalesce(p_payload -> 'auxiliaryConfigs', '[]'::jsonb)) config
        except
        select current_config.auxiliary_type_id, current_config.is_required
        from public.fms_subject_auxiliary_type current_config
        where current_config.subject_id = v_subject.id
      )
    ) then
      raise exception using errcode = '23514', message = '科目已有期初余额，不能变更辅助核算配置';
    end if;

    if not v_has_opening_balance then
      delete from public.fms_subject_auxiliary_type where subject_id = v_subject.id;
      insert into public.fms_subject_auxiliary_type (
        tenant_id, account_set_id, subject_id, auxiliary_type_id, is_required, sort
      )
      select v_subject.tenant_id, v_subject.account_set_id, v_subject.id,
        coalesce(config ->> 'auxiliaryTypeId', config ->> 'auxiliary_type_id')::uuid,
        coalesce(coalesce(config ->> 'isRequired', config ->> 'is_required')::boolean, true),
        coalesce(coalesce(config ->> 'sort', '100')::integer, 100)
      from jsonb_array_elements(coalesce(p_payload -> 'auxiliaryConfigs', '[]'::jsonb)) config;
    end if;
  end if;

  return v_subject;
end;
$$;
revoke all on function app_private.guard_fms_opening_balance_write() from public;
revoke all on function app_private.guard_fms_subject_auxiliary_write() from public;
revoke execute on function public.save_fms_subject(jsonb) from public, anon;
grant execute on function public.save_fms_subject(jsonb) to authenticated, service_role;
commit;
