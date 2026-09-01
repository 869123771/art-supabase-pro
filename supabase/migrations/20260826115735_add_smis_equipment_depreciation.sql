create table public.smis_equipment_depreciation (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  depreciation_no text not null,
  equipment_id uuid not null,
  depreciation_method text not null,
  depreciation_start_date date not null,
  original_value numeric(18, 2) not null,
  residual_rate numeric(8, 4) not null default 5,
  useful_life_years numeric(8, 2) not null,
  accumulated_depreciation numeric(18, 2) not null default 0,
  net_value numeric(18, 2) not null,
  remark text,
  status text not null default 'active',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_depreciation_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_equipment_depreciation_equipment_fkey
    foreign key (equipment_id, tenant_id)
    references public.smis_equipment(id, tenant_id) on delete restrict,
  constraint smis_equipment_depreciation_method_check check (
    depreciation_method in ('double_declining_balance', 'sum_of_years_digits', 'straight_line')
  ),
  constraint smis_equipment_depreciation_status_check check (status in ('active', 'stopped')),
  constraint smis_equipment_depreciation_value_check check (
    original_value > 0 and useful_life_years > 0 and residual_rate between 0 and 100
    and accumulated_depreciation >= 0 and net_value >= 0
    and accumulated_depreciation <= original_value and net_value <= original_value
  ),
  constraint smis_equipment_depreciation_remark_length check (
    remark is null or char_length(remark) <= 1000
  )
);

comment on table public.smis_equipment_depreciation is
  '设备折旧方案；同一设备可保留历史方案，但同一时点仅允许一个执行中方案';
comment on column public.smis_equipment_depreciation.depreciation_method is
  '双倍余额递减法、年限总和法或平均年限法';

create unique index smis_equipment_depreciation_no_uq
  on public.smis_equipment_depreciation(tenant_id, lower(btrim(depreciation_no)));
create unique index smis_equipment_depreciation_active_equipment_uq
  on public.smis_equipment_depreciation(tenant_id, equipment_id)
  where status = 'active';
create index smis_equipment_depreciation_equipment_idx
  on public.smis_equipment_depreciation(equipment_id, tenant_id);
create index smis_equipment_depreciation_query_idx
  on public.smis_equipment_depreciation(tenant_id, depreciation_method, status, depreciation_start_date desc);

create trigger smis_equipment_depreciation_create_audit
before insert on public.smis_equipment_depreciation
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_equipment_depreciation_update_audit
before update on public.smis_equipment_depreciation
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_equipment_depreciation enable row level security;
create policy smis_equipment_depreciation_select on public.smis_equipment_depreciation
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentDepreciation:View')))
  or (select app_private.is_platform_super())
);
create policy smis_equipment_depreciation_insert on public.smis_equipment_depreciation
for insert to authenticated with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentDepreciation:Add'))
);
create policy smis_equipment_depreciation_update on public.smis_equipment_depreciation
for update to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentDepreciation:Edit'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentDepreciation:Edit'))
);
create policy smis_equipment_depreciation_delete on public.smis_equipment_depreciation
for delete to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentDepreciation:Delete'))
);

revoke all on table public.smis_equipment_depreciation from public, anon, authenticated;
grant select, insert, update, delete on table public.smis_equipment_depreciation to service_role;

create or replace function public.smis_list_equipment_depreciations_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_depreciation_method text default null,
  p_status text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid;
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
  v_records jsonb := '[]'::jsonb;
  v_total bigint := 0;
  v_overview jsonb := '{}'::jsonb;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看设备折旧'; end if;
  if not app_private.has_permission('SmisEquipmentDepreciation:View') then
    raise exception '当前账号无权查看设备折旧';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();

  select count(*) into v_total
  from public.smis_equipment_depreciation depreciation
  join public.smis_equipment equipment on equipment.id = depreciation.equipment_id
    and equipment.tenant_id = depreciation.tenant_id
  where depreciation.tenant_id = v_tenant_id
    and (p_depreciation_method is null or depreciation.depreciation_method = p_depreciation_method)
    and (p_status is null or depreciation.status = p_status)
    and (v_keyword is null or depreciation.depreciation_no ilike '%' || v_keyword || '%'
      or equipment.equipment_code ilike '%' || v_keyword || '%'
      or equipment.equipment_name ilike '%' || v_keyword || '%');

  select coalesce(jsonb_agg(item.payload order by item.create_time desc), '[]'::jsonb)
  into v_records from (
    select depreciation.create_time, jsonb_build_object(
      'id', depreciation.id,
      'depreciationNo', depreciation.depreciation_no,
      'equipmentId', depreciation.equipment_id,
      'depreciationMethod', depreciation.depreciation_method,
      'depreciationStartDate', depreciation.depreciation_start_date,
      'originalValue', depreciation.original_value,
      'residualRate', depreciation.residual_rate,
      'usefulLifeYears', depreciation.useful_life_years,
      'accumulatedDepreciation', depreciation.accumulated_depreciation,
      'netValue', depreciation.net_value,
      'remark', depreciation.remark,
      'status', depreciation.status,
      'createBy', depreciation.create_by,
      'createTime', depreciation.create_time,
      'updateBy', depreciation.update_by,
      'updateTime', depreciation.update_time,
      'equipment', jsonb_build_object(
        'id', equipment.id,
        'equipmentCode', equipment.equipment_code,
        'equipmentName', equipment.equipment_name,
        'model', equipment.model,
        'assetOriginalValue', equipment.asset_original_value,
        'serviceLifeYears', equipment.service_life_years,
        'categoryName', category.category_name,
        'locationName', location.location_name
      )
    ) payload
    from public.smis_equipment_depreciation depreciation
    join public.smis_equipment equipment on equipment.id = depreciation.equipment_id
      and equipment.tenant_id = depreciation.tenant_id
    join public.smis_equipment_category category on category.id = equipment.category_id
      and category.tenant_id = equipment.tenant_id
    left join public.smis_storage_location location on location.id = equipment.location_id
      and location.tenant_id = equipment.tenant_id
    where depreciation.tenant_id = v_tenant_id
      and (p_depreciation_method is null or depreciation.depreciation_method = p_depreciation_method)
      and (p_status is null or depreciation.status = p_status)
      and (v_keyword is null or depreciation.depreciation_no ilike '%' || v_keyword || '%'
        or equipment.equipment_code ilike '%' || v_keyword || '%'
        or equipment.equipment_name ilike '%' || v_keyword || '%')
    order by depreciation.create_time desc
    offset greatest(coalesce(p_from, 0), 0)
    limit greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  ) item;

  select jsonb_build_object(
    'total', count(*),
    'active', count(*) filter (where status = 'active'),
    'totalOriginalValue', coalesce(sum(original_value), 0),
    'totalNetValue', coalesce(sum(net_value), 0)
  ) into v_overview
  from public.smis_equipment_depreciation where tenant_id = v_tenant_id;
  return jsonb_build_object('records', v_records, 'total', v_total, 'overview', v_overview);
end;
$$;

create or replace function public.smis_save_equipment_depreciation_secure(p_id uuid, p_payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid;
  v_equipment_id uuid := nullif(p_payload ->> 'equipment_id', '')::uuid;
  v_method text := p_payload ->> 'depreciation_method';
  v_status text := coalesce(nullif(p_payload ->> 'status', ''), 'active');
  v_no text := upper(btrim(coalesce(p_payload ->> 'depreciation_no', '')));
  v_original numeric := nullif(p_payload ->> 'original_value', '')::numeric;
  v_residual numeric := coalesce(nullif(p_payload ->> 'residual_rate', '')::numeric, 5);
  v_life numeric := nullif(p_payload ->> 'useful_life_years', '')::numeric;
  v_accumulated numeric := coalesce(nullif(p_payload ->> 'accumulated_depreciation', '')::numeric, 0);
  v_net numeric := nullif(p_payload ->> 'net_value', '')::numeric;
  v_result uuid;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护设备折旧'; end if;
  if p_id is null and not app_private.has_permission('SmisEquipmentDepreciation:Add') then raise exception '当前账号无权新增设备折旧'; end if;
  if p_id is not null and not app_private.has_permission('SmisEquipmentDepreciation:Edit') then raise exception '当前账号无权编辑设备折旧'; end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if v_equipment_id is null or not exists (select 1 from public.smis_equipment where id = v_equipment_id and tenant_id = v_tenant_id) then raise exception '请选择当前租户的有效设备'; end if;
  if v_method not in ('double_declining_balance', 'sum_of_years_digits', 'straight_line') then raise exception '请选择有效折旧方法'; end if;
  if nullif(p_payload ->> 'depreciation_start_date', '') is null then raise exception '请选择折旧开始日期'; end if;
  if v_original is null or v_original <= 0 then raise exception '资产原值必须大于 0'; end if;
  if v_life is null or v_life <= 0 then raise exception '使用年限必须大于 0'; end if;
  if v_residual < 0 or v_residual > 100 then raise exception '预计净残值率须在 0 到 100 之间'; end if;
  if v_accumulated < 0 or v_accumulated > v_original then raise exception '累计折旧金额不合法'; end if;
  v_net := coalesce(v_net, v_original - v_accumulated);
  if v_net < 0 or v_net > v_original then raise exception '当前净值不合法'; end if;
  if v_status not in ('active', 'stopped') then raise exception '折旧状态不合法'; end if;

  if p_id is null then
    if v_no = '' then v_no := app_private.next_document_number('smis.equipment_depreciation', v_tenant_id); end if;
    insert into public.smis_equipment_depreciation(
      tenant_id, depreciation_no, equipment_id, depreciation_method,
      depreciation_start_date, original_value, residual_rate, useful_life_years,
      accumulated_depreciation, net_value, remark, status
    ) values (
      v_tenant_id, v_no, v_equipment_id, v_method,
      (p_payload ->> 'depreciation_start_date')::date, v_original, v_residual, v_life,
      v_accumulated, v_net, nullif(btrim(p_payload ->> 'remark'), ''), v_status
    ) returning id into v_result;
  else
    select depreciation_no into v_no from public.smis_equipment_depreciation
    where id = p_id and tenant_id = v_tenant_id for update;
    if not found then raise exception '待编辑折旧方案不存在或无权访问'; end if;
    update public.smis_equipment_depreciation set
      equipment_id = v_equipment_id, depreciation_method = v_method,
      depreciation_start_date = (p_payload ->> 'depreciation_start_date')::date,
      original_value = v_original, residual_rate = v_residual,
      useful_life_years = v_life, accumulated_depreciation = v_accumulated,
      net_value = v_net, remark = nullif(btrim(p_payload ->> 'remark'), ''), status = v_status
    where id = p_id and tenant_id = v_tenant_id returning id into v_result;
  end if;
  return v_result;
exception when unique_violation then
  raise exception '该设备已有执行中的折旧方案，或折旧单号已存在';
end;
$$;

create or replace function public.smis_delete_equipment_depreciations_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  if not app_private.has_permission('SmisEquipmentDepreciation:Delete') then raise exception '当前账号无权删除设备折旧'; end if;
  delete from public.smis_equipment_depreciation
  where tenant_id = app_private.current_user_tenant_id() and id = any(coalesce(p_ids, '{}'::uuid[]));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.smis_list_equipment_depreciations_secure(integer, integer, text, text, text) from public, anon;
revoke all on function public.smis_save_equipment_depreciation_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_equipment_depreciations_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_equipment_depreciations_secure(integer, integer, text, text, text) to authenticated, service_role;
grant execute on function public.smis_save_equipment_depreciation_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.smis_delete_equipment_depreciations_secure(uuid[]) to authenticated, service_role;

with platform_tenant as (select id from public.sys_tenant where tenant_code = 'platform' limit 1)
insert into public.sys_document_number_scene(
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark, create_by, update_by, tenant_id
)
select 'smis.equipment_depreciation', '设备折旧单号', '折旧单号', 'business_document',
  'a1530000-0000-4000-8000-000000000015'::uuid,
  'smis_equipment_depreciation', 'depreciation_no', 'ZJ{YYYY}-{SEQ:3}', 'year', false, true,
  '按年度重置的三位流水号，可在编号规则中心按租户配置', 'number-engine', 'number-engine', platform_tenant.id
from platform_tenant on conflict (rule_key) do update set
  rule_name = excluded.rule_name, field_label = excluded.field_label, category = excluded.category,
  menu_id = excluded.menu_id, target_table = excluded.target_table, target_column = excluded.target_column,
  default_template = excluded.default_template, default_reset_cycle = excluded.default_reset_cycle,
  manual_required = excluded.manual_required, enabled = excluded.enabled, remark = excluded.remark,
  update_by = excluded.update_by, update_time = now();

insert into public.sys_document_number_rule(
  tenant_id, rule_key, rule_name, category, target_table, target_column, auto_enabled,
  template, reset_cycle, sequence_start, timezone, manual_required, builtin, enabled, remark,
  create_by, update_by
)
select id, 'smis.equipment_depreciation', '设备折旧单号', 'business_document',
  'smis_equipment_depreciation', 'depreciation_no', true, 'ZJ{YYYY}-{SEQ:3}', 'year', 1,
  'Asia/Shanghai', false, true, true, '设备折旧年度三位流水规则', 'number-engine', 'number-engine'
from public.sys_tenant on conflict (tenant_id, rule_key) do nothing;

create or replace function app_private.trg_seed_smis_equipment_depreciation_number_rule()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.sys_document_number_rule(
    tenant_id, rule_key, rule_name, category, target_table, target_column, auto_enabled,
    template, reset_cycle, sequence_start, timezone, manual_required, builtin, enabled, remark,
    create_by, update_by
  ) values (
    new.id, 'smis.equipment_depreciation', '设备折旧单号', 'business_document',
    'smis_equipment_depreciation', 'depreciation_no', true, 'ZJ{YYYY}-{SEQ:3}', 'year', 1,
    'Asia/Shanghai', false, true, true, '设备折旧年度三位流水规则', 'number-engine', 'number-engine'
  ) on conflict (tenant_id, rule_key) do nothing;
  return new;
end;
$$;
create trigger trg_seed_smis_equipment_depreciation_number_rule
after insert on public.sys_tenant for each row
execute function app_private.trg_seed_smis_equipment_depreciation_number_rule();

with platform_tenant as (select id from public.sys_tenant where tenant_code = 'platform' limit 1),
types(name, code, remark, sort) as (values
  ('设备折旧方法', 'smisEquipmentDepreciationMethod', '设备折旧计算方法及说明', 19),
  ('设备折旧状态', 'smisEquipmentDepreciationStatus', '设备折旧方案执行状态', 20)
)
insert into public.sys_dict_type(id, name, code, status, create_by, update_by, remark, tenant_id, parent_id, node_type, sort)
select gen_random_uuid(), types.name, types.code, '1', '624944977@qq.com', '624944977@qq.com', types.remark,
  platform_tenant.id, (select id from public.sys_dict_type where code = 'smisEquipmentLedger' limit 1), 'dictionary', types.sort
from types cross join platform_tenant on conflict (code) do update set
  name = excluded.name, status = excluded.status, remark = excluded.remark,
  parent_id = excluded.parent_id, sort = excluded.sort, update_time = now();

with platform_tenant as (select id from public.sys_tenant where tenant_code = 'platform' limit 1),
items(type_code, value, label, sort, tag_type, remark) as (values
  ('smisEquipmentDepreciationMethod', 'double_declining_balance', '双倍余额递减法', 1, 'warning', '前期折旧较快；按期初账面净值乘以直线折旧率的两倍计提，最后两年通常改用直线法。'),
  ('smisEquipmentDepreciationMethod', 'sum_of_years_digits', '年限总和法', 2, 'primary', '以尚可使用年限占年限数字总和的比例计提，折旧额逐年递减。'),
  ('smisEquipmentDepreciationMethod', 'straight_line', '平均年限法', 3, 'success', '在预计使用年限内，将扣除预计净残值后的金额均匀分摊。'),
  ('smisEquipmentDepreciationStatus', 'active', '执行中', 1, 'success', null),
  ('smisEquipmentDepreciationStatus', 'stopped', '已停止', 2, 'info', null)
)
insert into public.sys_dictionary(id, type_id, code, status, create_by, update_by, remark, value, label, tenant_id, tag_type, sort)
select gen_random_uuid(), dictionary_type.id, items.type_code || '_' || items.value, '1',
  '624944977@qq.com', '624944977@qq.com', items.remark, items.value, items.label,
  platform_tenant.id, items.tag_type, items.sort
from items join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant where not exists (
  select 1 from public.sys_dictionary existing where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.sys_menu(id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by)
select seed.id, 'a1530000-0000-4000-8000-000000000015'::uuid, seed.name, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'smis', '624944977@qq.com', '624944977@qq.com'
from (values
  ('a1530000-0000-4000-8150-000000000001'::uuid, 'SmisEquipmentDepreciation:View', '查看设备折旧', 1),
  ('a1530000-0000-4000-8150-000000000002'::uuid, 'SmisEquipmentDepreciation:Add', '新增设备折旧', 2),
  ('a1530000-0000-4000-8150-000000000003'::uuid, 'SmisEquipmentDepreciation:Edit', '编辑设备折旧', 3),
  ('a1530000-0000-4000-8150-000000000004'::uuid, 'SmisEquipmentDepreciation:Delete', '删除设备折旧', 4)
) seed(id, name, title, sort)
on conflict (id) do update set parent_id = excluded.parent_id, name = excluded.name,
  meta = excluded.meta, sort = excluded.sort, type = excluded.type,
  app_code = excluded.app_code, update_time = now();

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select page_grant.role_id, button.id, role.tenant_id, '{}'::jsonb, '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant join public.sys_role role on role.id = page_grant.role_id
cross join (values
  ('a1530000-0000-4000-8150-000000000001'::uuid),
  ('a1530000-0000-4000-8150-000000000002'::uuid),
  ('a1530000-0000-4000-8150-000000000003'::uuid),
  ('a1530000-0000-4000-8150-000000000004'::uuid)
) button(id)
where page_grant.menu_id = 'a1530000-0000-4000-8000-000000000015'::uuid
on conflict (role_id, menu_id) do nothing;

;
