-- 隐患分类由级联字典统一校验，避免固定枚举与可配置字典发生漂移。
alter table public.smis_position_safety_responsibility
  drop constraint if exists smis_position_safety_responsibility_primary_category_check,
  drop constraint if exists smis_position_safety_responsibility_secondary_category_check,
  drop constraint if exists smis_position_safety_responsibility_text_check;

alter table public.smis_position_safety_responsibility
  alter column hazard_content drop not null;

update public.smis_position_safety_responsibility
set hazard_content = null
where hazard_content is not null
  and btrim(hazard_content) = '';

alter table public.smis_position_safety_responsibility
  add constraint smis_position_safety_responsibility_text_check
  check (
    btrim(inspection_item) <> ''
    and btrim(inspection_standard) <> ''
  );

create or replace function app_private.validate_smis_hazard_cascade()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_primary_item_id uuid;
  v_secondary_item_id uuid;
begin
  select dictionary_item.id
  into v_primary_item_id
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = 'smisPrimaryHazardCategory'
    and dictionary_item.status = '1'
    and dictionary_item.value = new.primary_hazard_category
  limit 1;

  if v_primary_item_id is null then
    raise exception '一级隐患类别无效，请重新选择' using errcode = '23514';
  end if;

  select dictionary_item.id
  into v_secondary_item_id
  from public.sys_dictionary dictionary_item
  join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
  where dictionary_type.code = 'smisSecondaryHazardCategory'
    and dictionary_item.status = '1'
    and dictionary_item.cascade_parent_id = v_primary_item_id
    and dictionary_item.value = new.secondary_hazard_category
  limit 1;

  if v_secondary_item_id is null then
    raise exception '二级隐患类别不属于所选一级类别，请重新选择' using errcode = '23514';
  end if;

  new.hazard_content := nullif(btrim(new.hazard_content), '');

  if new.hazard_content is not null and not exists (
    select 1
    from public.sys_dictionary dictionary_item
    join public.sys_dict_type dictionary_type on dictionary_type.id = dictionary_item.type_id
    where dictionary_type.code = 'smisHazardContent'
      and dictionary_item.status = '1'
      and dictionary_item.cascade_parent_id = v_secondary_item_id
      and dictionary_item.value = new.hazard_content
  ) then
    raise exception '隐患内容不属于所选二级类别，请重新选择' using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function app_private.validate_smis_hazard_cascade()
from public, anon, authenticated;;
