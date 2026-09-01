begin;

create or replace function public.save_fms_asset_category(p_payload jsonb)
returns public.fms_asset_category
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_row public.fms_asset_category%rowtype;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护资产类别';
  end if;

  select * into v_account_set from public.fms_account_set
  where id = nullif(p_payload ->> 'accountSetId', '')::uuid;
  if not found or v_account_set.status <> 'active' then
    raise exception using errcode = '23514', message = '请选择启用中的账套';
  end if;

  if v_id is null then
    insert into public.fms_asset_category (
      tenant_id, account_set_id, category_code, category_name, depreciation_method,
      default_useful_life_months, default_residual_rate, asset_subject_id,
      accumulated_depreciation_subject_id, depreciation_expense_subject_id,
      disposal_subject_id, is_enabled, sort, remark
    ) values (
      v_account_set.tenant_id, v_account_set.id, upper(btrim(p_payload ->> 'categoryCode')),
      btrim(p_payload ->> 'categoryName'),
      coalesce(nullif(p_payload ->> 'depreciationMethod', ''), 'straight_line'),
      (p_payload ->> 'defaultUsefulLifeMonths')::integer,
      coalesce(nullif(p_payload ->> 'defaultResidualRate', '')::numeric, 0),
      nullif(p_payload ->> 'assetSubjectId', '')::uuid,
      nullif(p_payload ->> 'accumulatedDepreciationSubjectId', '')::uuid,
      nullif(p_payload ->> 'depreciationExpenseSubjectId', '')::uuid,
      nullif(p_payload ->> 'disposalSubjectId', '')::uuid,
      coalesce((p_payload ->> 'isEnabled')::boolean, true),
      coalesce(nullif(p_payload ->> 'sort', '')::integer, 100),
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_row;
  else
    select * into v_row from public.fms_asset_category where id = v_id for update;
    if not found then
      raise exception using errcode = 'P0002', message = '资产类别不存在';
    end if;
    if v_row.account_set_id <> v_account_set.id then
      raise exception using errcode = '23514', message = '资产类别所属账套不可变更';
    end if;
    if coalesce((p_payload ->> 'isEnabled')::boolean, v_row.is_enabled) = false
      and exists(select 1 from public.fms_fixed_asset where category_id = v_id and status = 'active') then
      raise exception using errcode = '23514', message = '存在使用中的资产，不能停用该类别';
    end if;

    update public.fms_asset_category set
      category_code = upper(btrim(p_payload ->> 'categoryCode')),
      category_name = btrim(p_payload ->> 'categoryName'),
      depreciation_method = coalesce(nullif(p_payload ->> 'depreciationMethod', ''), depreciation_method),
      default_useful_life_months = (p_payload ->> 'defaultUsefulLifeMonths')::integer,
      default_residual_rate = coalesce(nullif(p_payload ->> 'defaultResidualRate', '')::numeric, default_residual_rate),
      asset_subject_id = nullif(p_payload ->> 'assetSubjectId', '')::uuid,
      accumulated_depreciation_subject_id = nullif(p_payload ->> 'accumulatedDepreciationSubjectId', '')::uuid,
      depreciation_expense_subject_id = nullif(p_payload ->> 'depreciationExpenseSubjectId', '')::uuid,
      disposal_subject_id = nullif(p_payload ->> 'disposalSubjectId', '')::uuid,
      is_enabled = coalesce((p_payload ->> 'isEnabled')::boolean, is_enabled),
      sort = coalesce(nullif(p_payload ->> 'sort', '')::integer, sort),
      remark = nullif(btrim(p_payload ->> 'remark'), '')
    where id = v_id returning * into v_row;
  end if;
  return v_row;
end;
$$;

create or replace function public.delete_fms_asset_category(p_category_id uuid)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可删除资产类别';
  end if;
  if exists(select 1 from public.fms_fixed_asset where category_id = p_category_id) then
    raise exception using errcode = '23514', message = '资产类别已被资产卡片使用，不能删除';
  end if;
  delete from public.fms_asset_category where id = p_category_id;
  if not found then raise exception using errcode = 'P0002', message = '资产类别不存在'; end if;
end;
$$;

create or replace function public.save_fms_fixed_asset(p_payload jsonb)
returns public.fms_fixed_asset
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid := nullif(p_payload ->> 'id', '')::uuid;
  v_account_set public.fms_account_set%rowtype;
  v_category public.fms_asset_category%rowtype;
  v_row public.fms_fixed_asset%rowtype;
  v_original numeric(20,2) := (p_payload ->> 'originalValue')::numeric;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可维护固定资产';
  end if;
  select * into v_account_set from public.fms_account_set
  where id = nullif(p_payload ->> 'accountSetId', '')::uuid;
  if not found or v_account_set.status <> 'active' then
    raise exception using errcode = '23514', message = '请选择启用中的账套';
  end if;
  select * into v_category from public.fms_asset_category
  where id = nullif(p_payload ->> 'categoryId', '')::uuid
    and account_set_id = v_account_set.id and is_enabled;
  if not found then raise exception using errcode = '23503', message = '资产类别不存在或已停用'; end if;

  if v_id is null then
    insert into public.fms_fixed_asset (
      tenant_id, account_set_id, category_id, asset_no, asset_name,
      acquisition_date, ready_for_use_date, depreciation_start_date,
      original_value, residual_value, useful_life_months, department_id, employee_id,
      location, specification, serial_no, source_type, source_id, source_no, remark
    ) values (
      v_account_set.tenant_id, v_account_set.id, v_category.id,
      btrim(p_payload ->> 'assetNo'), btrim(p_payload ->> 'assetName'),
      (p_payload ->> 'acquisitionDate')::date,
      (p_payload ->> 'readyForUseDate')::date,
      coalesce(nullif(p_payload ->> 'depreciationStartDate', '')::date, (p_payload ->> 'readyForUseDate')::date),
      v_original,
      coalesce(nullif(p_payload ->> 'residualValue', '')::numeric, round(v_original * v_category.default_residual_rate, 2)),
      coalesce(nullif(p_payload ->> 'usefulLifeMonths', '')::integer, v_category.default_useful_life_months),
      nullif(p_payload ->> 'departmentId', '')::uuid,
      nullif(p_payload ->> 'employeeId', '')::uuid,
      nullif(btrim(p_payload ->> 'location'), ''), nullif(btrim(p_payload ->> 'specification'), ''),
      nullif(btrim(p_payload ->> 'serialNo'), ''), nullif(p_payload ->> 'sourceType', ''),
      nullif(p_payload ->> 'sourceId', '')::uuid, nullif(p_payload ->> 'sourceNo', ''),
      nullif(btrim(p_payload ->> 'remark'), '')
    ) returning * into v_row;
  else
    select * into v_row from public.fms_fixed_asset where id = v_id for update;
    if not found then raise exception using errcode = 'P0002', message = '固定资产不存在'; end if;
    if v_row.status <> 'draft' then
      raise exception using errcode = '23514', message = '仅草稿资产允许编辑';
    end if;
    if v_row.account_set_id <> v_account_set.id then
      raise exception using errcode = '23514', message = '资产所属账套不可变更';
    end if;
    update public.fms_fixed_asset set
      category_id = v_category.id, asset_no = btrim(p_payload ->> 'assetNo'),
      asset_name = btrim(p_payload ->> 'assetName'), acquisition_date = (p_payload ->> 'acquisitionDate')::date,
      ready_for_use_date = (p_payload ->> 'readyForUseDate')::date,
      depreciation_start_date = coalesce(nullif(p_payload ->> 'depreciationStartDate', '')::date, (p_payload ->> 'readyForUseDate')::date),
      original_value = v_original,
      residual_value = coalesce(nullif(p_payload ->> 'residualValue', '')::numeric, round(v_original * v_category.default_residual_rate, 2)),
      useful_life_months = coalesce(nullif(p_payload ->> 'usefulLifeMonths', '')::integer, v_category.default_useful_life_months),
      department_id = nullif(p_payload ->> 'departmentId', '')::uuid,
      employee_id = nullif(p_payload ->> 'employeeId', '')::uuid,
      location = nullif(btrim(p_payload ->> 'location'), ''), specification = nullif(btrim(p_payload ->> 'specification'), ''),
      serial_no = nullif(btrim(p_payload ->> 'serialNo'), ''), source_type = nullif(p_payload ->> 'sourceType', ''),
      source_id = nullif(p_payload ->> 'sourceId', '')::uuid, source_no = nullif(p_payload ->> 'sourceNo', ''),
      remark = nullif(btrim(p_payload ->> 'remark'), ''), version = version + 1
    where id = v_id returning * into v_row;
  end if;
  return v_row;
end;
$$;

create or replace function public.delete_fms_fixed_asset(p_asset_id uuid)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可删除固定资产';
  end if;
  delete from public.fms_fixed_asset where id = p_asset_id and status = 'draft';
  if not found then raise exception using errcode = '23514', message = '资产不存在或当前状态不允许删除'; end if;
end;
$$;

create or replace function public.act_fms_fixed_asset(p_asset_id uuid, p_action text, p_payload jsonb default '{}'::jsonb)
returns public.fms_fixed_asset
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.fms_fixed_asset%rowtype;
  v_event_date date := coalesce(nullif(p_payload ->> 'actionDate', '')::date, current_date);
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可执行资产操作';
  end if;
  select * into v_row from public.fms_fixed_asset where id = p_asset_id for update;
  if not found then raise exception using errcode = 'P0002', message = '固定资产不存在'; end if;

  if p_action = 'activate' and v_row.status = 'draft' then
    update public.fms_fixed_asset set status='active', version=version+1 where id=v_row.id returning * into v_row;
    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id, 'fixed_asset', 'activated', v_row.id, v_row.asset_no, v_event_date,
      concat('固定资产转固 · ', v_row.asset_no, ' · ', v_row.asset_name),
      jsonb_build_object('gross_amount',v_row.original_value,'asset_id',v_row.id,'category_id',v_row.category_id)
    );
  elsif p_action = 'suspend' and v_row.status = 'active' then
    update public.fms_fixed_asset set status='suspended', version=version+1 where id=v_row.id returning * into v_row;
  elsif p_action = 'resume' and v_row.status = 'suspended' then
    update public.fms_fixed_asset set status='active', version=version+1 where id=v_row.id returning * into v_row;
  elsif p_action = 'dispose' and v_row.status in ('active','suspended') then
    if nullif(btrim(p_payload ->> 'reason'), '') is null then
      raise exception using errcode = '23502', message = '资产处置必须填写原因';
    end if;
    update public.fms_fixed_asset set
      status='disposed', disposal_date=v_event_date,
      disposal_amount=coalesce(nullif(p_payload ->> 'amount', '')::numeric,0),
      disposal_reason=btrim(p_payload ->> 'reason'), version=version+1
    where id=v_row.id returning * into v_row;
    perform app_private.enqueue_fms_posting_event(
      v_row.tenant_id, 'fixed_asset', 'disposed', v_row.id, v_row.asset_no, v_event_date,
      concat('固定资产处置 · ', v_row.asset_no, ' · ', v_row.asset_name),
      jsonb_build_object(
        'gross_amount',v_row.disposal_amount,'asset_id',v_row.id,'category_id',v_row.category_id,
        'original_value',v_row.original_value,'accumulated_depreciation',v_row.accumulated_depreciation,
        'impairment_amount',v_row.impairment_amount,'reason',v_row.disposal_reason
      )
    );
  else
    raise exception using errcode = '23514', message = '当前资产状态不允许执行该操作';
  end if;
  return v_row;
end;
$$;

create or replace function public.calculate_fms_asset_depreciation(p_accounting_period_id uuid, p_remark text default null)
returns public.fms_asset_depreciation_run
language plpgsql security invoker set search_path = '' as $$
declare
  v_period public.fms_accounting_period%rowtype;
  v_run public.fms_asset_depreciation_run%rowtype;
  v_asset public.fms_fixed_asset%rowtype;
  v_amount numeric(20,2);
  v_remaining numeric(20,2);
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可计提折旧';
  end if;
  select * into v_period from public.fms_accounting_period where id=p_accounting_period_id for update;
  if not found or v_period.status <> 'open' then
    raise exception using errcode = '23514', message = '仅开放会计期间允许计提折旧';
  end if;

  select * into v_run from public.fms_asset_depreciation_run
  where accounting_period_id=v_period.id for update;
  if found and v_run.status='posted' then
    raise exception using errcode = '23514', message = '本期折旧已入账，不能重复计提';
  elsif found then
    delete from public.fms_asset_depreciation_line where run_id=v_run.id;
    update public.fms_asset_depreciation_run set status='draft',asset_count=0,total_amount=0,
      calculated_at=null,remark=nullif(btrim(p_remark),'') where id=v_run.id returning * into v_run;
  else
    insert into public.fms_asset_depreciation_run(
      tenant_id,account_set_id,accounting_period_id,run_no,remark
    ) values(v_period.tenant_id,v_period.account_set_id,v_period.id,'',nullif(btrim(p_remark),''))
    returning * into v_run;
  end if;

  for v_asset in
    select * from public.fms_fixed_asset
    where account_set_id=v_period.account_set_id and status='active'
      and depreciation_start_date <= v_period.end_date
      and depreciated_months < useful_life_months
    order by asset_no for update
  loop
    v_remaining := v_asset.original_value-v_asset.residual_value-v_asset.accumulated_depreciation-v_asset.impairment_amount;
    v_amount := least(round((v_asset.original_value-v_asset.residual_value)/v_asset.useful_life_months,2),v_remaining);
    if v_amount > 0 then
      insert into public.fms_asset_depreciation_line(
        tenant_id,account_set_id,run_id,asset_id,opening_accumulated_depreciation,
        depreciation_amount,closing_accumulated_depreciation
      ) values(
        v_asset.tenant_id,v_asset.account_set_id,v_run.id,v_asset.id,v_asset.accumulated_depreciation,
        v_amount,v_asset.accumulated_depreciation+v_amount
      );
    end if;
  end loop;

  update public.fms_asset_depreciation_run r set
    status='calculated',asset_count=x.asset_count,total_amount=x.total_amount,calculated_at=now()
  from (select count(*)::integer asset_count,coalesce(sum(depreciation_amount),0)::numeric total_amount
        from public.fms_asset_depreciation_line where run_id=v_run.id) x
  where r.id=v_run.id returning r.* into v_run;
  return v_run;
end;
$$;

create or replace function public.act_fms_asset_depreciation_run(p_run_id uuid, p_action text, p_reason text default null)
returns public.fms_asset_depreciation_run
language plpgsql security definer set search_path = '' as $$
declare
  v_run public.fms_asset_depreciation_run%rowtype;
  v_period public.fms_accounting_period%rowtype;
  v_conflict_count bigint;
begin
  if not (select app_private.is_platform_super()) then
    raise exception using errcode = '42501', message = '仅平台超级管理员可确认折旧';
  end if;
  select * into v_run from public.fms_asset_depreciation_run where id=p_run_id for update;
  if not found then raise exception using errcode = 'P0002', message = '折旧批次不存在'; end if;
  select * into v_period from public.fms_accounting_period where id=v_run.accounting_period_id for update;

  if p_action='post' and v_run.status='calculated' then
    if v_period.status <> 'open' then raise exception using errcode='23514',message='会计期间已锁定，不能确认折旧'; end if;
    select count(*) into v_conflict_count
    from public.fms_asset_depreciation_line l join public.fms_fixed_asset a on a.id=l.asset_id
    where l.run_id=v_run.id and a.accumulated_depreciation<>l.opening_accumulated_depreciation;
    if v_conflict_count>0 then raise exception using errcode='40001',message='资产累计折旧已变化，请重新计算'; end if;
    update public.fms_fixed_asset a set
      accumulated_depreciation=l.closing_accumulated_depreciation,
      depreciated_months=least(a.useful_life_months,a.depreciated_months+1),version=a.version+1
    from public.fms_asset_depreciation_line l where l.run_id=v_run.id and a.id=l.asset_id;
    update public.fms_asset_depreciation_run set status='posted',posted_at=now()
    where id=v_run.id returning * into v_run;
    perform app_private.enqueue_fms_posting_event(
      v_run.tenant_id,'asset_depreciation','posted',v_run.id,v_run.run_no,v_period.end_date,
      concat(v_period.fiscal_year,'年第',v_period.period_no,'期固定资产折旧'),
      jsonb_build_object('gross_amount',v_run.total_amount,'run_id',v_run.id,'asset_count',v_run.asset_count,'period_id',v_period.id)
    );
  elsif p_action='cancel' and v_run.status in ('draft','calculated') then
    if nullif(btrim(p_reason),'') is null then raise exception using errcode='23502',message='取消折旧批次必须填写原因'; end if;
    update public.fms_asset_depreciation_run set status='cancelled',remark=concat_ws(E'\n',remark,'[取消] '||btrim(p_reason))
    where id=v_run.id returning * into v_run;
  else
    raise exception using errcode='23514',message='当前折旧批次状态不允许执行该操作';
  end if;
  return v_run;
end;
$$;

create or replace function public.fms_fixed_asset_summary(p_account_set_id uuid, p_period_id uuid default null)
returns table(category_count bigint,asset_count bigint,active_count bigint,original_value numeric,net_value numeric,period_depreciation numeric)
language sql stable security invoker set search_path = '' as $$
  select
    (select count(*) from public.fms_asset_category c where c.account_set_id=p_account_set_id and c.is_enabled),
    count(*),count(*) filter(where a.status='active'),coalesce(sum(a.original_value),0),
    coalesce(sum(a.original_value-a.accumulated_depreciation-a.impairment_amount),0),
    coalesce((select r.total_amount from public.fms_asset_depreciation_run r where r.accounting_period_id=p_period_id and r.status<>'cancelled'),0)
  from public.fms_fixed_asset a where a.account_set_id=p_account_set_id
$$;

revoke execute on function public.save_fms_asset_category(jsonb) from public,anon;
revoke execute on function public.delete_fms_asset_category(uuid) from public,anon;
revoke execute on function public.save_fms_fixed_asset(jsonb) from public,anon;
revoke execute on function public.delete_fms_fixed_asset(uuid) from public,anon;
revoke execute on function public.act_fms_fixed_asset(uuid,text,jsonb) from public,anon;
revoke execute on function public.calculate_fms_asset_depreciation(uuid,text) from public,anon;
revoke execute on function public.act_fms_asset_depreciation_run(uuid,text,text) from public,anon;
revoke execute on function public.fms_fixed_asset_summary(uuid,uuid) from public,anon;
grant execute on function public.save_fms_asset_category(jsonb) to authenticated,service_role;
grant execute on function public.delete_fms_asset_category(uuid) to authenticated,service_role;
grant execute on function public.save_fms_fixed_asset(jsonb) to authenticated,service_role;
grant execute on function public.delete_fms_fixed_asset(uuid) to authenticated,service_role;
grant execute on function public.act_fms_fixed_asset(uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.calculate_fms_asset_depreciation(uuid,text) to authenticated,service_role;
grant execute on function public.act_fms_asset_depreciation_run(uuid,text,text) to authenticated,service_role;
grant execute on function public.fms_fixed_asset_summary(uuid,uuid) to authenticated,service_role;

with platform_tenant as (
  select id from public.sys_tenant where builtin_type='platform' limit 1
), dictionary_items as (
  select * from (values
    ('c2000000-0000-4000-8000-000000000166'::uuid,'fixed_asset:activated','固定资产转固',26,'success'),
    ('c2000000-0000-4000-8000-000000000167'::uuid,'fixed_asset:disposed','固定资产处置',27,'warning'),
    ('c2000000-0000-4000-8000-000000000168'::uuid,'asset_depreciation:posted','固定资产折旧确认',28,'primary')
  ) i(id,value,label,sort,tag_type)
)
insert into public.sys_dictionary(id,type_id,code,status,value,label,sort,tag_type,create_by,update_by,tenant_id)
select i.id,'b2000000-0000-4000-8000-000000000013'::uuid,i.value,'1',i.value,i.label,i.sort,i.tag_type,
  '624944977@qq.com','624944977@qq.com',p.id from platform_tenant p cross join dictionary_items i
on conflict(id) do update set type_id=excluded.type_id,code=excluded.code,status=excluded.status,value=excluded.value,
  label=excluded.label,sort=excluded.sort,tag_type=excluded.tag_type,update_by=excluded.update_by,update_time=now();

commit;

;
