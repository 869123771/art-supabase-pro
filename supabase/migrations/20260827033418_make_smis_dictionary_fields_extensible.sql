create or replace function app_private.is_enabled_dictionary_value(
  p_type_code text,
  p_value text
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select nullif(btrim(coalesce(p_value, '')), '') is not null
    and exists (
      select 1
      from public.sys_dict_type dictionary_type
      join public.sys_dictionary dictionary_item
        on dictionary_item.type_id = dictionary_type.id
      where dictionary_type.code = p_type_code
        and dictionary_type.status = '1'
        and dictionary_item.status = '1'
        and btrim(dictionary_item.value) = btrim(p_value)
    );
$function$;

revoke all on function app_private.is_enabled_dictionary_value(text, text)
  from public, anon, authenticated, service_role;

comment on function app_private.is_enabled_dictionary_value(text, text) is
  '判断值是否属于指定的启用字典；比较时忽略字典值首尾空白。';

create index if not exists idx_sys_dictionary_type_normalized_value_enabled
  on public.sys_dictionary(type_id, btrim(value))
  where status = '1';

create or replace function app_private.enforce_enabled_dictionary_fields()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_index integer;
  v_column_name text;
  v_type_code text;
  v_field_label text;
  v_raw_value text;
  v_normalized_value text;
  v_old_value text;
begin
  if tg_nargs = 0 or tg_nargs % 3 <> 0 then
    raise exception '字典字段守卫配置无效' using errcode = '22023';
  end if;

  v_index := 0;
  while v_index < tg_nargs loop
    v_column_name := tg_argv[v_index];
    v_type_code := tg_argv[v_index + 1];
    v_field_label := tg_argv[v_index + 2];
    v_raw_value := to_jsonb(new)->>v_column_name;

    if v_raw_value is not null then
      v_normalized_value := btrim(v_raw_value);
      if v_normalized_value = '' then
        raise exception '%不能为空', v_field_label using errcode = '22023';
      end if;

      v_old_value := case
        when tg_op = 'UPDATE' then btrim(to_jsonb(old)->>v_column_name)
        else null
      end;

      if not app_private.is_enabled_dictionary_value(v_type_code, v_normalized_value)
        and not (tg_op = 'UPDATE' and v_old_value = v_normalized_value) then
        raise exception '%无效或已停用', v_field_label using errcode = '22023';
      end if;

      new := jsonb_populate_record(
        new,
        jsonb_build_object(v_column_name, v_normalized_value)
      );
    end if;

    v_index := v_index + 3;
  end loop;

  return new;
end;
$function$;

revoke all on function app_private.enforce_enabled_dictionary_fields()
  from public, anon, authenticated, service_role;

comment on function app_private.enforce_enabled_dictionary_fields() is
  '通用字典字段写入守卫：新增或改值时要求启用字典项，编辑时允许保留历史停用值。';

create or replace function app_private.validate_smis_hazard_cascade()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_primary_item_id uuid;
  v_secondary_item_id uuid;
  v_primary_value text := btrim(new.primary_hazard_category);
  v_secondary_value text := btrim(new.secondary_hazard_category);
  v_hazard_content text := nullif(btrim(new.hazard_content), '');
begin
  new.primary_hazard_category := v_primary_value;
  new.secondary_hazard_category := v_secondary_value;
  new.hazard_content := v_hazard_content;

  select dictionary_item.id
  into v_primary_item_id
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = 'smisPrimaryHazardCategory'
    and dictionary_type.status = '1'
    and dictionary_item.status = '1'
    and btrim(dictionary_item.value) = v_primary_value
  order by dictionary_item.sort, dictionary_item.id
  limit 1;

  if v_primary_item_id is null
    and tg_op = 'UPDATE'
    and btrim(old.primary_hazard_category) = v_primary_value then
    select dictionary_item.id
    into v_primary_item_id
    from public.sys_dictionary dictionary_item
    join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
    where dictionary_type.code = 'smisPrimaryHazardCategory'
      and btrim(dictionary_item.value) = v_primary_value
    order by dictionary_item.sort, dictionary_item.id
    limit 1;
  end if;

  if v_primary_item_id is null then
    raise exception '一级隐患类别无效或已停用，请重新选择' using errcode = '23514';
  end if;

  select dictionary_item.id
  into v_secondary_item_id
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = 'smisSecondaryHazardCategory'
    and dictionary_type.status = '1'
    and dictionary_item.status = '1'
    and dictionary_item.cascade_parent_id = v_primary_item_id
    and btrim(dictionary_item.value) = v_secondary_value
  order by dictionary_item.sort, dictionary_item.id
  limit 1;

  if v_secondary_item_id is null
    and tg_op = 'UPDATE'
    and btrim(old.primary_hazard_category) = v_primary_value
    and btrim(old.secondary_hazard_category) = v_secondary_value then
    select dictionary_item.id
    into v_secondary_item_id
    from public.sys_dictionary dictionary_item
    join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
    where dictionary_type.code = 'smisSecondaryHazardCategory'
      and dictionary_item.cascade_parent_id = v_primary_item_id
      and btrim(dictionary_item.value) = v_secondary_value
    order by dictionary_item.sort, dictionary_item.id
    limit 1;
  end if;

  if v_secondary_item_id is null then
    raise exception '二级隐患类别不属于所选一级类别，请重新选择' using errcode = '23514';
  end if;

  if v_hazard_content is not null and not exists (
    select 1
    from public.sys_dictionary dictionary_item
    join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
    where dictionary_type.code = 'smisHazardContent'
      and dictionary_type.status = '1'
      and dictionary_item.status = '1'
      and dictionary_item.cascade_parent_id = v_secondary_item_id
      and btrim(dictionary_item.value) = v_hazard_content
  ) and not (
    tg_op = 'UPDATE'
    and btrim(old.primary_hazard_category) = v_primary_value
    and btrim(old.secondary_hazard_category) = v_secondary_value
    and nullif(btrim(old.hazard_content), '') is not distinct from v_hazard_content
  ) then
    raise exception '隐患内容不属于所选二级类别，请重新选择' using errcode = '23514';
  end if;

  return new;
end;
$function$;

comment on function app_private.validate_smis_hazard_cascade() is
  '按启用字典及其级联关系校验隐患类别；编辑时允许保留历史停用值。';

do $migration$
declare
  v_duplicate record;
begin
  select normalized.value, count(*) as item_count
  into v_duplicate
  from (
    select btrim(dictionary_item.value) as value
    from public.sys_dictionary dictionary_item
    join public.sys_dict_type dictionary_type
      on dictionary_type.id = dictionary_item.type_id
    where dictionary_type.code = 'smisSiteCategory'
  ) normalized
  group by normalized.value
  having count(*) > 1
  limit 1;

  if found then
    raise exception '场所属性类别存在重复的规范化字典值：%', v_duplicate.value;
  end if;

  update public.sys_dictionary dictionary_item
  set value = btrim(dictionary_item.value),
      code = btrim(dictionary_item.code),
      update_time = now()
  from public.sys_dict_type dictionary_type
  where dictionary_type.id = dictionary_item.type_id
    and dictionary_type.code = 'smisSiteCategory'
    and (
      dictionary_item.value is distinct from btrim(dictionary_item.value)
      or dictionary_item.code is distinct from btrim(dictionary_item.code)
    );
end;
$migration$;

alter table public.smis_position_risk_control
  drop constraint if exists smis_position_risk_control_measure_category_check,
  drop constraint if exists smis_position_risk_control_level_check,
  drop constraint if exists smis_position_risk_control_primary_category_check,
  drop constraint if exists smis_position_risk_control_secondary_category_check,
  drop constraint if exists smis_position_risk_control_hazard_level_check;

drop trigger if exists smis_position_risk_control_dictionary_guard
  on public.smis_position_risk_control;
create trigger smis_position_risk_control_dictionary_guard
before insert or update of
  control_measure_category,
  control_level,
  primary_hazard_category,
  secondary_hazard_category,
  hazard_level
on public.smis_position_risk_control
for each row
execute function app_private.enforce_enabled_dictionary_fields(
  'control_measure_category', 'smisControlMeasureCategory', '管控措施类别',
  'control_level', 'smisControlLevel', '防控级别',
  'primary_hazard_category', 'smisPrimaryHazardCategory', '一级隐患类别',
  'secondary_hazard_category', 'smisSecondaryHazardCategory', '二级隐患类别',
  'hazard_level', 'smisHazardLevel', '隐患级别'
);

alter table public.smis_position_safety_responsibility
  drop constraint if exists smis_position_safety_responsibility_frequency_check,
  drop constraint if exists smis_position_safety_responsibility_frequency_unit_check,
  drop constraint if exists smis_position_safety_responsibility_hazard_level_check,
  drop constraint if exists smis_position_safety_responsibility_risk_level_check;

drop trigger if exists smis_position_safety_responsibility_dictionary_guard
  on public.smis_position_safety_responsibility;
create trigger smis_position_safety_responsibility_dictionary_guard
before insert or update of
  primary_hazard_category,
  secondary_hazard_category,
  hazard_level,
  risk_level,
  inspection_frequency,
  frequency_unit
on public.smis_position_safety_responsibility
for each row
execute function app_private.enforce_enabled_dictionary_fields(
  'primary_hazard_category', 'smisPrimaryHazardCategory', '一级隐患类别',
  'secondary_hazard_category', 'smisSecondaryHazardCategory', '二级隐患类别',
  'hazard_level', 'smisHazardLevel', '隐患级别',
  'risk_level', 'smisRiskLevel', '隐患风险等级',
  'inspection_frequency', 'smisInspectionFrequency', '排查频次',
  'frequency_unit', 'smisFrequencyUnit', '频次单位'
);

alter table public.smis_equipment
  drop constraint if exists smis_equipment_importance_check;

drop trigger if exists smis_equipment_importance_dictionary_guard
  on public.smis_equipment;
create trigger smis_equipment_importance_dictionary_guard
before insert or update of importance_level
on public.smis_equipment
for each row
execute function app_private.enforce_enabled_dictionary_fields(
  'importance_level', 'smisEquipmentImportanceLevel', '设备重要级别'
);

alter table public.smis_equipment_attachment
  drop constraint if exists smis_equipment_attachment_type_check;

drop trigger if exists smis_equipment_attachment_type_dictionary_guard
  on public.smis_equipment_attachment;
create trigger smis_equipment_attachment_type_dictionary_guard
before insert or update of attachment_type
on public.smis_equipment_attachment
for each row
execute function app_private.enforce_enabled_dictionary_fields(
  'attachment_type', 'smisEquipmentAttachmentType', '设备附件类型'
);

drop trigger if exists smis_statutory_holiday_type_dictionary_guard
  on public.smis_statutory_holiday;
create trigger smis_statutory_holiday_type_dictionary_guard
before insert or update of holiday_type
on public.smis_statutory_holiday
for each row
execute function app_private.enforce_enabled_dictionary_fields(
  'holiday_type', 'smisHolidayType', '假期类型'
);

drop trigger if exists smis_site_category_dictionary_guard
  on public.smis_site;
create trigger smis_site_category_dictionary_guard
before insert or update of category_code
on public.smis_site
for each row
execute function app_private.enforce_enabled_dictionary_fields(
  'category_code', 'smisSiteCategory', '属性类别'
);

do $migration$
declare
  v_definition text;
  v_updated_definition text;
begin
  select pg_get_functiondef(procedure_row.oid)
  into v_definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid = procedure_row.pronamespace
  where namespace_row.nspname = 'public'
    and procedure_row.proname = 'smis_save_equipment_ledger_secure'
    and pg_get_function_identity_arguments(procedure_row.oid) = 'p_id uuid, p_payload jsonb';

  v_updated_definition := replace(
    v_definition,
$old$  if v_importance_level not in ('general', 'important', 'critical') then
    raise exception '重要级别不合法';
  end if;$old$,
$new$  if not app_private.is_enabled_dictionary_value(
    'smisEquipmentImportanceLevel', v_importance_level
  ) and not (
    p_id is not null
    and exists (
      select 1
      from public.smis_equipment existing_equipment
      where existing_equipment.id = p_id
        and existing_equipment.tenant_id = v_tenant_id
        and btrim(existing_equipment.importance_level) = v_importance_level
    )
  ) then
    raise exception '设备重要级别无效或已停用';
  end if;$new$
  );

  if v_updated_definition is null or v_updated_definition = v_definition then
    raise exception '未找到设备重要级别的旧校验定义';
  end if;
  execute v_updated_definition;
end;
$migration$;

do $migration$
declare
  v_definition text;
  v_updated_definition text;
begin
  select pg_get_functiondef(procedure_row.oid)
  into v_definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid = procedure_row.pronamespace
  where namespace_row.nspname = 'public'
    and procedure_row.proname = 'smis_save_statutory_holiday_secure'
    and pg_get_function_identity_arguments(procedure_row.oid) = 'p_id uuid, p_payload jsonb';

  v_updated_definition := replace(
    v_definition,
$old$  if v_type not in ('compensatory_leave', 'spring_festival', 'new_year', 'qingming', 'labor_day', 'dragon_boat', 'mid_autumn', 'national_day') then
    raise exception '假期类型无效' using errcode = '22023';
  end if;$old$,
$new$  if not app_private.is_enabled_dictionary_value('smisHolidayType', v_type)
    and not (
      p_id is not null
      and exists (
        select 1
        from public.smis_statutory_holiday existing_holiday
        where existing_holiday.id = p_id
          and existing_holiday.tenant_id = v_tenant_id
          and btrim(existing_holiday.holiday_type) = v_type
      )
    ) then
    raise exception '假期类型无效或已停用' using errcode = '22023';
  end if;$new$
  );

  if v_updated_definition is null or v_updated_definition = v_definition then
    raise exception '未找到法定假期类型的旧校验定义';
  end if;
  execute v_updated_definition;
end;
$migration$;

do $migration$
declare
  v_definition text;
  v_updated_definition text;
begin
  select pg_get_functiondef(procedure_row.oid)
  into v_definition
  from pg_proc procedure_row
  join pg_namespace namespace_row on namespace_row.oid = procedure_row.pronamespace
  where namespace_row.nspname = 'public'
    and procedure_row.proname = 'smis_save_leave_information_secure'
    and pg_get_function_identity_arguments(procedure_row.oid) = 'p_id uuid, p_payload jsonb';

  v_updated_definition := replace(
    v_definition,
$old$  v_leave_category text;
  v_result_id uuid;$old$,
$new$  v_leave_category text;
  v_leave_sort bigint;
  v_result_id uuid;$new$
  );

  v_updated_definition := replace(
    v_updated_definition,
$old$  select mapped.leave_name, mapped.category
  into v_leave_type_name, v_leave_category
  from (values
    ('bereavement', '丧假', 'bereavement'),
    ('personal', '事假', 'personal'),
    ('maternity', '产假', 'maternity'),
    ('public_rest', '公休', 'compensatory'),
    ('sick', '病假', 'sick'),
    ('marriage', '婚假', 'marriage'),
    ('work_injury', '工伤假', 'other'),
    ('annual', '年假', 'annual'),
    ('family_visit', '探亲假', 'other'),
    ('other', '其他', 'other')
  ) as mapped(leave_code, leave_name, category)
  where mapped.leave_code = v_leave_type_code;
  if v_leave_type_name is null then raise exception '请选择有效的请假类型'; end if;$old$,
$new$  if not app_private.is_enabled_dictionary_value('smisLeaveType', v_leave_type_code)
    and not (
      p_id is not null
      and exists (
        select 1
        from public.hr_leave_request existing_request
        join public.hr_leave_type existing_type
          on existing_type.id = existing_request.leave_type_id
         and existing_type.tenant_id = existing_request.tenant_id
        where existing_request.id = p_id
          and existing_request.tenant_id = v_tenant_id
          and btrim(existing_type.leave_code) = v_leave_type_code
      )
    ) then
    raise exception '请假类型无效或已停用';
  end if;

  select dictionary_item.label,
    case
      when v_leave_type_code in (
        'annual', 'sick', 'personal', 'marriage', 'maternity',
        'paternity', 'bereavement', 'parental', 'unpaid', 'other'
      ) then v_leave_type_code
      when v_leave_type_code = 'public_rest' then 'compensatory'
      else 'other'
    end,
    dictionary_item.sort
  into v_leave_type_name, v_leave_category, v_leave_sort
  from public.sys_dict_type dictionary_type
  join public.sys_dictionary dictionary_item
    on dictionary_item.type_id = dictionary_type.id
  where dictionary_type.code = 'smisLeaveType'
    and btrim(dictionary_item.value) = v_leave_type_code
  order by
    (dictionary_type.status = '1' and dictionary_item.status = '1') desc,
    dictionary_item.sort,
    dictionary_item.id
  limit 1;

  if v_leave_type_name is null and p_id is not null then
    select existing_type.leave_name, existing_type.category, existing_type.sort
    into v_leave_type_name, v_leave_category, v_leave_sort
    from public.hr_leave_request existing_request
    join public.hr_leave_type existing_type
      on existing_type.id = existing_request.leave_type_id
     and existing_type.tenant_id = existing_request.tenant_id
    where existing_request.id = p_id
      and existing_request.tenant_id = v_tenant_id
      and btrim(existing_type.leave_code) = v_leave_type_code;
  end if;

  if nullif(btrim(v_leave_type_name), '') is null then
    raise exception '请选择有效的请假类型';
  end if;$new$
  );

  v_updated_definition := replace(
    v_updated_definition,
$old$    case v_leave_type_code
      when 'bereavement' then 1 when 'personal' then 2 when 'maternity' then 3
      when 'public_rest' then 4 when 'sick' then 5 when 'marriage' then 6
      when 'work_injury' then 7 when 'annual' then 8 when 'family_visit' then 9 else 10
    end,$old$,
$new$    coalesce(v_leave_sort, 100),$new$
  );

  if v_updated_definition is null
    or v_updated_definition = v_definition
    or position('v_leave_sort bigint' in v_updated_definition) = 0
    or position('smisLeaveType' in v_updated_definition) = 0 then
    raise exception '未完整替换请假类型的旧校验定义';
  end if;
  execute v_updated_definition;
end;
$migration$;

;
