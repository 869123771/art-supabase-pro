begin;
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
      v_tenant_id,
      v_account_set_id,
      nullif(p_payload ->> 'parentId', '')::uuid,
      btrim(p_payload ->> 'subjectCode'),
      btrim(p_payload ->> 'subjectName'),
      p_payload ->> 'category',
      p_payload ->> 'balanceDirection',
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
    where id = v_subject_id
      and account_set_id = v_account_set_id
      and tenant_id = v_tenant_id
    returning * into v_subject;

    if not found then
      raise exception using errcode = 'P0002', message = '会计科目不存在或不属于当前账套';
    end if;
  end if;

  if p_payload ? 'auxiliaryConfigs' then
    if exists (
      select 1 from public.fms_opening_balance b where b.subject_id = v_subject.id
    ) and (
      exists (
        select current_config.auxiliary_type_id, current_config.is_required
        from public.fms_subject_auxiliary_type current_config
        where current_config.subject_id = v_subject.id
        except
        select
          coalesce(config ->> 'auxiliaryTypeId', config ->> 'auxiliary_type_id')::uuid,
          coalesce(config ->> 'isRequired', config ->> 'is_required')::boolean
        from jsonb_array_elements(coalesce(p_payload -> 'auxiliaryConfigs', '[]'::jsonb)) config
      )
      or exists (
        select
          coalesce(config ->> 'auxiliaryTypeId', config ->> 'auxiliary_type_id')::uuid,
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

    delete from public.fms_subject_auxiliary_type where subject_id = v_subject.id;

    insert into public.fms_subject_auxiliary_type (
      tenant_id, account_set_id, subject_id, auxiliary_type_id, is_required, sort
    )
    select
      v_subject.tenant_id,
      v_subject.account_set_id,
      v_subject.id,
      coalesce(config ->> 'auxiliaryTypeId', config ->> 'auxiliary_type_id')::uuid,
      coalesce(
        coalesce(config ->> 'isRequired', config ->> 'is_required')::boolean,
        true
      ),
      coalesce(coalesce(config ->> 'sort', '100')::integer, 100)
    from jsonb_array_elements(coalesce(p_payload -> 'auxiliaryConfigs', '[]'::jsonb)) config;
  end if;

  return v_subject;
end;
$$;
revoke execute on function public.save_fms_subject(jsonb) from public, anon;
grant execute on function public.save_fms_subject(jsonb) to authenticated, service_role;
commit;
