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

create trigger fms_financial_statement_item_business_guard
before insert or update on public.fms_financial_statement_item
for each row execute function app_private.guard_fms_financial_statement_item();

create or replace function public.save_fms_financial_statement_item(p_payload jsonb)
returns public.fms_financial_statement_item
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_item public.fms_financial_statement_item%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护财务报表项目';
  end if;
  select * into v_account_set
  from public.fms_account_set
  where id = (p_payload ->> 'accountSetId')::uuid;
  if not found then
    raise exception using errcode = 'P0002', message = '账套不存在';
  end if;

  if v_id is null then
    insert into public.fms_financial_statement_item (
      tenant_id, account_set_id, statement_type, parent_id, item_code,
      item_name, line_no, item_level, display_style, calculation_method,
      cash_flow_direction, is_enabled, remark
    ) values (
      v_account_set.tenant_id, v_account_set.id,
      p_payload ->> 'statementType', nullif(p_payload ->> 'parentId', '')::uuid,
      p_payload ->> 'itemCode', p_payload ->> 'itemName',
      (p_payload ->> 'lineNo')::integer,
      coalesce(nullif(p_payload ->> 'itemLevel', '')::smallint, 1),
      coalesce(nullif(p_payload ->> 'displayStyle', ''), 'normal'),
      coalesce(nullif(p_payload ->> 'calculationMethod', ''), 'mapping'),
      nullif(p_payload ->> 'cashFlowDirection', ''),
      coalesce((p_payload ->> 'isEnabled')::boolean, true),
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_item;
  else
    update public.fms_financial_statement_item item set
      parent_id = nullif(p_payload ->> 'parentId', '')::uuid,
      item_code = p_payload ->> 'itemCode',
      item_name = p_payload ->> 'itemName',
      line_no = (p_payload ->> 'lineNo')::integer,
      item_level = coalesce(nullif(p_payload ->> 'itemLevel', '')::smallint, 1),
      display_style = coalesce(nullif(p_payload ->> 'displayStyle', ''), 'normal'),
      calculation_method = coalesce(nullif(p_payload ->> 'calculationMethod', ''), 'mapping'),
      cash_flow_direction = nullif(p_payload ->> 'cashFlowDirection', ''),
      is_enabled = coalesce((p_payload ->> 'isEnabled')::boolean, true),
      remark = nullif(btrim(p_payload ->> 'remark'), '')
    where item.id = v_id
      and item.account_set_id = v_account_set.id
      and item.statement_type = p_payload ->> 'statementType'
    returning * into v_item;
    if not found then
      raise exception using errcode = 'P0002', message = '财务报表项目不存在';
    end if;
  end if;

  if v_item.calculation_method <> 'mapping' then
    delete from public.fms_financial_statement_mapping
    where statement_item_id = v_item.id;
  end if;
  if v_item.calculation_method <> 'formula' then
    delete from public.fms_financial_statement_formula
    where target_item_id = v_item.id;
  end if;
  return v_item;
end;
$$;

create or replace function public.save_fms_financial_statement_mappings(
  p_statement_item_id uuid,
  p_mappings jsonb
)
returns integer
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_item public.fms_financial_statement_item%rowtype;
  v_mapping jsonb;
  v_count integer := 0;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护报表科目映射';
  end if;
  if jsonb_typeof(coalesce(p_mappings, '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = '报表科目映射参数必须为数组';
  end if;
  select * into v_item from public.fms_financial_statement_item
  where id = p_statement_item_id for update;
  if not found or v_item.calculation_method <> 'mapping' then
    raise exception using errcode = '23514', message = '仅直接取数行可配置科目映射';
  end if;

  delete from public.fms_financial_statement_mapping
  where statement_item_id = v_item.id;
  for v_mapping in
    select value from jsonb_array_elements(coalesce(p_mappings, '[]'::jsonb))
  loop
    insert into public.fms_financial_statement_mapping (
      tenant_id, account_set_id, statement_item_id, subject_id,
      mapping_direction, factor, remark
    ) values (
      v_item.tenant_id, v_item.account_set_id, v_item.id,
      (v_mapping ->> 'subjectId')::uuid,
      v_mapping ->> 'mappingDirection',
      coalesce(nullif(v_mapping ->> 'factor', '')::numeric, 1),
      nullif(btrim(v_mapping ->> 'remark'), '')
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.save_fms_financial_statement_formulas(
  p_target_item_id uuid,
  p_formulas jsonb
)
returns integer
language plpgsql
security invoker
set search_path = public, app_private, pg_temp
as $$
declare
  v_item public.fms_financial_statement_item%rowtype;
  v_formula jsonb;
  v_count integer := 0;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护报表计算公式';
  end if;
  if jsonb_typeof(coalesce(p_formulas, '[]'::jsonb)) <> 'array' then
    raise exception using errcode = '22023', message = '报表计算公式参数必须为数组';
  end if;
  select * into v_item from public.fms_financial_statement_item
  where id = p_target_item_id for update;
  if not found or v_item.calculation_method <> 'formula' then
    raise exception using errcode = '23514', message = '仅公式行可配置计算关系';
  end if;

  delete from public.fms_financial_statement_formula
  where target_item_id = v_item.id;
  for v_formula in
    select value from jsonb_array_elements(coalesce(p_formulas, '[]'::jsonb))
  loop
    insert into public.fms_financial_statement_formula (
      tenant_id, account_set_id, target_item_id, source_item_id, factor
    ) values (
      v_item.tenant_id, v_item.account_set_id, v_item.id,
      (v_formula ->> 'sourceItemId')::uuid,
      coalesce(nullif(v_formula ->> 'factor', '')::numeric, 1)
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function app_private.guard_fms_financial_statement_item()
  from public, anon, authenticated;
revoke all on function public.save_fms_financial_statement_item(jsonb)
  from public, anon, authenticated;
grant execute on function public.save_fms_financial_statement_item(jsonb)
  to authenticated, service_role;
revoke all on function public.save_fms_financial_statement_mappings(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.save_fms_financial_statement_mappings(uuid, jsonb)
  to authenticated, service_role;
revoke all on function public.save_fms_financial_statement_formulas(uuid, jsonb)
  from public, anon, authenticated;
grant execute on function public.save_fms_financial_statement_formulas(uuid, jsonb)
  to authenticated, service_role;

commit;

;
