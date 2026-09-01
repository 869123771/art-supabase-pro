begin;
create or replace function app_private.guard_fms_currency()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_base_currency_code text;
begin
  if tg_op = 'DELETE' then
    if old.is_base then
      raise exception using errcode = '23514', message = '账套本位币不可删除';
    end if;
    return old;
  end if;

  select a.base_currency_code
  into v_base_currency_code
  from public.fms_account_set a
  where a.id = new.account_set_id and a.tenant_id = new.tenant_id;

  if not found then
    raise exception using errcode = '23503', message = '币种所属账套不存在或租户不匹配';
  end if;

  if tg_op = 'UPDATE' and (
    new.account_set_id <> old.account_set_id
    or new.tenant_id <> old.tenant_id
    or new.is_base <> old.is_base
  ) then
    raise exception using errcode = '23514', message = '币种所属账套、租户及本位币标识不可变更';
  end if;

  if new.is_base then
    if not new.is_enabled then
      raise exception using errcode = '23514', message = '账套本位币不可停用';
    end if;
    if new.currency_code <> v_base_currency_code then
      raise exception using errcode = '23514', message = '本位币代码必须与账套配置一致';
    end if;
  elsif new.currency_code = v_base_currency_code then
    raise exception using errcode = '23514', message = '外币代码不能与账套本位币重复';
  end if;

  return new;
end;
$$;
drop trigger if exists trg_fms_currency_guard on public.fms_currency;
create trigger trg_fms_currency_guard
before insert or update or delete on public.fms_currency
for each row execute function app_private.guard_fms_currency();
create or replace function app_private.guard_fms_exchange_rate()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.fms_exchange_rate%rowtype;
  v_currency public.fms_currency%rowtype;
  v_period_status text;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;

  select *
  into v_currency
  from public.fms_currency c
  where c.id = v_row.currency_id
    and c.account_set_id = v_row.account_set_id
    and c.tenant_id = v_row.tenant_id;

  if not found then
    raise exception using errcode = '23503', message = '汇率币种不存在或核算范围不匹配';
  end if;
  if v_currency.is_base then
    raise exception using errcode = '23514', message = '本位币无需维护汇率';
  end if;
  if not v_currency.is_enabled then
    raise exception using errcode = '23514', message = '停用币种不能维护汇率';
  end if;

  select p.status
  into v_period_status
  from public.fms_accounting_period p
  where p.account_set_id = v_row.account_set_id
    and v_row.rate_date between p.start_date and p.end_date
  limit 1;

  if v_period_status in ('closing', 'closed') then
    raise exception using errcode = '23514', message = '关账中或已关账期间的汇率不可变更';
  end if;

  if tg_op = 'UPDATE' and (
    new.account_set_id <> old.account_set_id or new.tenant_id <> old.tenant_id
  ) then
    raise exception using errcode = '23514', message = '汇率所属账套和租户不可变更';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists trg_fms_exchange_rate_guard on public.fms_exchange_rate;
create trigger trg_fms_exchange_rate_guard
before insert or update or delete on public.fms_exchange_rate
for each row execute function app_private.guard_fms_exchange_rate();
create or replace function app_private.guard_fms_auxiliary_type()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_expected_source text;
begin
  if tg_op = 'DELETE' then
    if old.is_system then
      raise exception using errcode = '23514', message = '系统辅助核算维度不可删除';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and (
    new.account_set_id <> old.account_set_id
    or new.tenant_id <> old.tenant_id
    or new.is_system <> old.is_system
  ) then
    raise exception using errcode = '23514', message = '辅助核算维度所属范围及系统标识不可变更';
  end if;

  if tg_op = 'UPDATE' and old.is_system and (
    new.type_code <> old.type_code or new.source_type <> old.source_type
  ) then
    raise exception using errcode = '23514', message = '系统辅助核算维度的编码和数据来源不可变更';
  end if;

  if new.is_system then
    v_expected_source := case new.type_code
      when 'CUSTOMER' then 'customer'
      when 'CARRIER' then 'carrier'
      when 'DEPARTMENT' then 'department'
      when 'EMPLOYEE' then 'employee'
      when 'PROJECT' then 'project'
      else null
    end;
    if v_expected_source is null or new.source_type <> v_expected_source then
      raise exception using errcode = '23514', message = '系统辅助核算维度编码与数据来源不匹配';
    end if;
  end if;

  return new;
end;
$$;
drop trigger if exists trg_fms_auxiliary_type_guard on public.fms_auxiliary_type;
create trigger trg_fms_auxiliary_type_guard
before insert or update or delete on public.fms_auxiliary_type
for each row execute function app_private.guard_fms_auxiliary_type();
revoke all on function app_private.guard_fms_currency() from public;
revoke all on function app_private.guard_fms_exchange_rate() from public;
revoke all on function app_private.guard_fms_auxiliary_type() from public;
commit;
