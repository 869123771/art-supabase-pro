begin;

create or replace function app_private.guard_fms_financial_statement_item()
returns trigger
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_parent public.fms_financial_statement_item%rowtype;
begin
  new.item_code := upper(btrim(new.item_code));
  new.item_name := btrim(new.item_name);

  if new.statement_type = 'cash_flow_statement' and new.calculation_method = 'mapping' then
    if new.cash_flow_direction is null then
      new.cash_flow_direction := case
        when new.item_code in (
          'CF020','CF030','CF040','CF110','CF120','CF130','CF210','CF220'
        ) then 'receipt'
        when new.item_code in (
          'CF050','CF060','CF070','CF080','CF140','CF150','CF230','CF240'
        ) then 'payment'
        else null
      end;
    end if;
    if new.cash_flow_direction is null then
      raise exception using errcode = '23514', message = '现金流量直接取数行必须设置现金流量方向';
    end if;
  else
    new.cash_flow_direction := null;
  end if;

  if new.parent_id is not null then
    select * into v_parent
    from public.fms_financial_statement_item
    where id = new.parent_id;
    if v_parent.id is null
       or v_parent.account_set_id <> new.account_set_id
       or v_parent.tenant_id <> new.tenant_id
       or v_parent.statement_type <> new.statement_type then
      raise exception using errcode = '23514', message = '上级报表项目必须属于同一账套和同一报表';
    end if;
    if new.id is not null and exists (
      with recursive ancestors as (
        select parent.id, parent.parent_id
        from public.fms_financial_statement_item parent
        where parent.id = new.parent_id
        union all
        select parent.id, parent.parent_id
        from public.fms_financial_statement_item parent
        join ancestors child on child.parent_id = parent.id
      )
      select 1 from ancestors where id = new.id
    ) then
      raise exception using errcode = '23514', message = '报表项目层级不允许形成循环';
    end if;
  end if;
  return new;
end;
$$;

commit;

;
