begin;

create table if not exists public.smis_position_safety_responsibility (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  organization_id uuid not null,
  position_id uuid not null,
  primary_hazard_category text not null,
  secondary_hazard_category text not null,
  hazard_content text not null,
  hazard_level text not null,
  risk_level text not null,
  inspection_item text not null,
  inspection_standard text not null,
  inspection_frequency smallint not null,
  frequency_unit text not null,
  revision_date date not null default current_date,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_position_safety_responsibility_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint smis_position_safety_responsibility_organization_tenant_fkey
    foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_position_safety_responsibility_position_tenant_fkey
    foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint smis_position_safety_responsibility_primary_category_check
    check (primary_hazard_category = any (array['basic_management', 'site_management'])),
  constraint smis_position_safety_responsibility_secondary_category_check
    check (secondary_hazard_category = any (array[
      'safety_rules',
      'occupational_hazard',
      'raw_material_product',
      'equipment_facility',
      'workplace',
      'protective_equipment',
      'safety_skill',
      'related_party_operation',
      'other',
      'personal_protection'
    ])),
  constraint smis_position_safety_responsibility_hazard_level_check
    check (hazard_level = any (array[
      'general_a', 'general_b', 'general_c', 'general_d', 'major'
    ])),
  constraint smis_position_safety_responsibility_risk_level_check
    check (risk_level = any (array['major_a', 'higher_b', 'general_c', 'low_d'])),
  constraint smis_position_safety_responsibility_frequency_check
    check (inspection_frequency between 1 and 3),
  constraint smis_position_safety_responsibility_frequency_unit_check
    check (frequency_unit = any (array[
      'shift', 'day', 'week', 'month', 'quarter', 'year', 'ten_day'
    ])),
  constraint smis_position_safety_responsibility_text_check
    check (
      btrim(hazard_content) <> ''
      and btrim(inspection_item) <> ''
      and btrim(inspection_standard) <> ''
    )
);

create index if not exists smis_position_safety_responsibility_scope_idx
  on public.smis_position_safety_responsibility
  (tenant_id, organization_id, position_id, revision_date desc);

create index if not exists smis_position_safety_responsibility_category_idx
  on public.smis_position_safety_responsibility
  (tenant_id, primary_hazard_category, hazard_level, risk_level);

drop trigger if exists smis_position_safety_responsibility_create_audit
  on public.smis_position_safety_responsibility;
create trigger smis_position_safety_responsibility_create_audit
before insert on public.smis_position_safety_responsibility
for each row
execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists smis_position_safety_responsibility_update_audit
  on public.smis_position_safety_responsibility;
create trigger smis_position_safety_responsibility_update_audit
before update on public.smis_position_safety_responsibility
for each row
execute function public.trg_set_update_time_and_by();

alter table public.smis_position_safety_responsibility enable row level security;

drop policy if exists tenant_select on public.smis_position_safety_responsibility;
create policy tenant_select
on public.smis_position_safety_responsibility
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionSafetyResponsibility:View'))
  )
);

drop policy if exists tenant_insert on public.smis_position_safety_responsibility;
create policy tenant_insert
on public.smis_position_safety_responsibility
for insert
to authenticated
with check (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (
      (select app_private.has_permission('SmisPositionSafetyResponsibility:Add'))
      or (select app_private.has_permission('SmisPositionSafetyResponsibility:Import'))
    )
  )
);

drop policy if exists tenant_update on public.smis_position_safety_responsibility;
create policy tenant_update
on public.smis_position_safety_responsibility
for update
to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionSafetyResponsibility:Edit'))
  )
)
with check (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionSafetyResponsibility:Edit'))
  )
);

drop policy if exists tenant_delete on public.smis_position_safety_responsibility;
create policy tenant_delete
on public.smis_position_safety_responsibility
for delete
to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionSafetyResponsibility:Delete'))
  )
);

revoke all on table public.smis_position_safety_responsibility from anon;
grant select, insert, update, delete
  on table public.smis_position_safety_responsibility to authenticated;
grant all on table public.smis_position_safety_responsibility to service_role;

create or replace function public.smis_list_positions_secure(
  p_from integer default 0,
  p_to integer default 499,
  p_keyword text default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionSafetyResponsibility',
    'SmisPositionSafetyResponsibility:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS position safety responsibility view permission'
      using errcode = '42501';
  end if;

  if p_organization_id is not null and not exists (
    select 1
    from public.sys_organization organization_row
    where organization_row.id = p_organization_id
      and organization_row.tenant_id = v_tenant_id
      and organization_row.status = '1'
  ) then
    raise exception 'Organization is outside the current tenant or unavailable'
      using errcode = '42501';
  end if;

  v_limit := least(
    500,
    greatest(coalesce(p_to, 499) - greatest(coalesce(p_from, 0), 0) + 1, 1)
  );

  with filtered as materialized (
    select
      position_row.id,
      position_row.position_code,
      position_row.position_name,
      position_row.position_kind,
      position_row.description,
      position_row.sort,
      (
        select count(*)
        from public.hr_employee employee_row
        where employee_row.tenant_id = v_tenant_id
          and employee_row.position_id = position_row.id
          and employee_row.employment_status <> 'terminated'
          and (
            p_organization_id is null
            or employee_row.organization_id = p_organization_id
          )
      )::integer as employee_count
    from public.hr_position position_row
    where position_row.tenant_id = v_tenant_id
      and position_row.enabled
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or coalesce(position_row.description, '') ilike '%' || btrim(p_keyword) || '%'
      )
      and (
        p_organization_id is null
        or exists (
          select 1
          from public.hr_position_headcount headcount_row
          where headcount_row.tenant_id = v_tenant_id
            and headcount_row.position_id = position_row.id
            and headcount_row.organization_id = p_organization_id
            and headcount_row.enabled
            and headcount_row.effective_from <= current_date
            and (headcount_row.effective_to is null or headcount_row.effective_to >= current_date)
        )
        or exists (
          select 1
          from public.hr_employee employee_row
          where employee_row.tenant_id = v_tenant_id
            and employee_row.position_id = position_row.id
            and employee_row.organization_id = p_organization_id
            and employee_row.employment_status <> 'terminated'
        )
        or exists (
          select 1
          from public.smis_position_safety_responsibility responsibility_row
          where responsibility_row.tenant_id = v_tenant_id
            and responsibility_row.position_id = position_row.id
            and responsibility_row.organization_id = p_organization_id
        )
      )
  ), paged as (
    select *
    from filtered
    order by sort, position_name, position_code
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((select jsonb_agg(to_jsonb(paged) order by sort, position_name, position_code) from paged), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$$;

revoke all on function public.smis_list_positions_secure(integer, integer, text, uuid)
  from public, anon;
grant execute on function public.smis_list_positions_secure(integer, integer, text, uuid)
  to authenticated, service_role;

with platform_tenant as (
  select id
  from public.sys_tenant
  where tenant_code = 'platform'
), type_seed (id, parent_code, node_type, name, code, sort, remark) as (
  values
    ('d1530000-0000-4000-8000-000000000001'::uuid, null::text, 'directory', 'SMIS安全管理', 'smis', 60, 'SMIS 安全管理数据字典'),
    ('d1530000-0000-4000-8000-000000000002'::uuid, 'smis', 'dictionary', '一级隐患类别', 'smisPrimaryHazardCategory', 1, '岗位安全责任制一级隐患类别'),
    ('d1530000-0000-4000-8000-000000000003'::uuid, 'smis', 'dictionary', '二级隐患类别', 'smisSecondaryHazardCategory', 2, '岗位安全责任制二级隐患类别'),
    ('d1530000-0000-4000-8000-000000000004'::uuid, 'smis', 'dictionary', '隐患级别', 'smisHazardLevel', 3, '岗位安全责任制隐患级别'),
    ('d1530000-0000-4000-8000-000000000005'::uuid, 'smis', 'dictionary', '频次单位', 'smisFrequencyUnit', 4, '岗位排查频次单位'),
    ('d1530000-0000-4000-8000-000000000006'::uuid, 'smis', 'dictionary', '排查频次', 'smisInspectionFrequency', 5, '岗位排查频次数值'),
    ('d1530000-0000-4000-8000-000000000007'::uuid, 'smis', 'dictionary', '隐患风险等级', 'smisRiskLevel', 6, '岗位安全责任制风险等级')
), inserted_root as (
  insert into public.sys_dict_type (
    id, parent_id, node_type, name, code, status, sort, remark,
    tenant_id, create_by, update_by
  )
  select
    seed.id, null, seed.node_type, seed.name, seed.code, '1', seed.sort, seed.remark,
    platform_tenant.id, '624944977@qq.com', '624944977@qq.com'
  from type_seed seed
  cross join platform_tenant
  where seed.parent_code is null
  on conflict (code) do update
  set name = excluded.name,
      node_type = excluded.node_type,
      status = excluded.status,
      sort = excluded.sort,
      remark = excluded.remark,
      tenant_id = excluded.tenant_id,
      update_by = excluded.update_by,
      update_time = now()
  returning id, code
)
insert into public.sys_dict_type (
  id, parent_id, node_type, name, code, status, sort, remark,
  tenant_id, create_by, update_by
)
select
  seed.id,
  parent_type.id,
  seed.node_type,
  seed.name,
  seed.code,
  '1',
  seed.sort,
  seed.remark,
  platform_tenant.id,
  '624944977@qq.com',
  '624944977@qq.com'
from type_seed seed
cross join platform_tenant
join inserted_root parent_type on parent_type.code = seed.parent_code
where seed.parent_code is not null
on conflict (code) do update
set parent_id = excluded.parent_id,
    name = excluded.name,
    node_type = excluded.node_type,
    status = excluded.status,
    sort = excluded.sort,
    remark = excluded.remark,
    tenant_id = excluded.tenant_id,
    update_by = excluded.update_by,
    update_time = now();

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform'
), dictionary_seed (
  id, type_code, parent_id, code, label, value, sort, tag_type, color, remark
) as (
  values
    ('d1530000-0000-4000-8101-000000000001'::uuid, 'smisPrimaryHazardCategory', null::uuid, 'basic_management', '基础管理', 'basic_management', 1, 'primary', null::text, null::text),
    ('d1530000-0000-4000-8101-000000000002'::uuid, 'smisPrimaryHazardCategory', null::uuid, 'site_management', '现场管理', 'site_management', 2, 'warning', null::text, null::text),

    ('d1530000-0000-4000-8102-000000000001'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000001'::uuid, 'safety_rules', '安全规章制度', 'safety_rules', 1, null::text, null::text, '基础管理'),
    ('d1530000-0000-4000-8102-000000000002'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'occupational_hazard', '职业病危害', 'occupational_hazard', 2, null::text, null::text, '现场管理'),
    ('d1530000-0000-4000-8102-000000000003'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'raw_material_product', '原辅物料、产品', 'raw_material_product', 3, null::text, null::text, '现场管理'),
    ('d1530000-0000-4000-8102-000000000004'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'equipment_facility', '设备设施', 'equipment_facility', 4, null::text, null::text, '现场管理'),
    ('d1530000-0000-4000-8102-000000000005'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'workplace', '作业场所', 'workplace', 5, null::text, null::text, '现场管理'),
    ('d1530000-0000-4000-8102-000000000006'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'protective_equipment', '防护、保险、信号等装置装备', 'protective_equipment', 6, null::text, null::text, '现场管理'),
    ('d1530000-0000-4000-8102-000000000007'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'safety_skill', '安全技能', 'safety_skill', 7, null::text, null::text, '现场管理'),
    ('d1530000-0000-4000-8102-000000000008'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'related_party_operation', '相关方作业', 'related_party_operation', 8, null::text, null::text, '现场管理'),
    ('d1530000-0000-4000-8102-000000000009'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'other', '其他', 'other', 9, null::text, null::text, '现场管理'),
    ('d1530000-0000-4000-8102-000000000010'::uuid, 'smisSecondaryHazardCategory', 'd1530000-0000-4000-8101-000000000002'::uuid, 'personal_protection', '个体防护', 'personal_protection', 10, null::text, null::text, '现场管理'),

    ('d1530000-0000-4000-8103-000000000001'::uuid, 'smisHazardLevel', null::uuid, 'general_a', '一般隐患A', 'general_a', 1, 'info', null::text, null::text),
    ('d1530000-0000-4000-8103-000000000002'::uuid, 'smisHazardLevel', null::uuid, 'general_b', '一般隐患B', 'general_b', 2, 'info', null::text, null::text),
    ('d1530000-0000-4000-8103-000000000003'::uuid, 'smisHazardLevel', null::uuid, 'general_c', '一般隐患C', 'general_c', 3, 'warning', null::text, null::text),
    ('d1530000-0000-4000-8103-000000000004'::uuid, 'smisHazardLevel', null::uuid, 'general_d', '一般隐患D', 'general_d', 4, 'warning', null::text, null::text),
    ('d1530000-0000-4000-8103-000000000005'::uuid, 'smisHazardLevel', null::uuid, 'major', '重大隐患', 'major', 5, 'danger', null::text, null::text),

    ('d1530000-0000-4000-8104-000000000001'::uuid, 'smisFrequencyUnit', null::uuid, 'shift', '班', 'shift', 1, null::text, null::text, null::text),
    ('d1530000-0000-4000-8104-000000000002'::uuid, 'smisFrequencyUnit', null::uuid, 'day', '日', 'day', 2, null::text, null::text, null::text),
    ('d1530000-0000-4000-8104-000000000003'::uuid, 'smisFrequencyUnit', null::uuid, 'week', '周', 'week', 3, null::text, null::text, null::text),
    ('d1530000-0000-4000-8104-000000000004'::uuid, 'smisFrequencyUnit', null::uuid, 'month', '月', 'month', 4, null::text, null::text, null::text),
    ('d1530000-0000-4000-8104-000000000005'::uuid, 'smisFrequencyUnit', null::uuid, 'quarter', '季', 'quarter', 5, null::text, null::text, null::text),
    ('d1530000-0000-4000-8104-000000000006'::uuid, 'smisFrequencyUnit', null::uuid, 'year', '年', 'year', 6, null::text, null::text, null::text),
    ('d1530000-0000-4000-8104-000000000007'::uuid, 'smisFrequencyUnit', null::uuid, 'ten_day', '旬', 'ten_day', 7, null::text, null::text, null::text),

    ('d1530000-0000-4000-8105-000000000001'::uuid, 'smisInspectionFrequency', null::uuid, '1', '1', '1', 1, null::text, null::text, null::text),
    ('d1530000-0000-4000-8105-000000000002'::uuid, 'smisInspectionFrequency', null::uuid, '2', '2', '2', 2, null::text, null::text, null::text),
    ('d1530000-0000-4000-8105-000000000003'::uuid, 'smisInspectionFrequency', null::uuid, '3', '3', '3', 3, null::text, null::text, null::text),

    ('d1530000-0000-4000-8106-000000000001'::uuid, 'smisRiskLevel', null::uuid, 'major_a', '重大风险(A级)', 'major_a', 1, 'danger', null::text, null::text),
    ('d1530000-0000-4000-8106-000000000002'::uuid, 'smisRiskLevel', null::uuid, 'higher_b', '较大风险(B级)', 'higher_b', 2, 'warning', null::text, null::text),
    ('d1530000-0000-4000-8106-000000000003'::uuid, 'smisRiskLevel', null::uuid, 'general_c', '一般风险(C级)', 'general_c', 3, 'info', null::text, null::text),
    ('d1530000-0000-4000-8106-000000000004'::uuid, 'smisRiskLevel', null::uuid, 'low_d', '低风险(D级)', 'low_d', 4, 'success', null::text, null::text)
)
insert into public.sys_dictionary (
  id, type_id, parent_id, code, status, label, value, sort, tag_type, color, remark,
  tenant_id, create_by, update_by
)
select
  seed.id,
  dictionary_type.id,
  null,
  seed.code,
  '1',
  seed.label,
  seed.value,
  seed.sort,
  seed.tag_type,
  seed.color,
  seed.remark,
  platform_tenant.id,
  '624944977@qq.com',
  '624944977@qq.com'
from dictionary_seed seed
join public.sys_dict_type dictionary_type on dictionary_type.code = seed.type_code
cross join platform_tenant
on conflict (id) do update
set type_id = excluded.type_id,
    parent_id = excluded.parent_id,
    code = excluded.code,
    status = excluded.status,
    label = excluded.label,
    value = excluded.value,
    sort = excluded.sort,
    tag_type = excluded.tag_type,
    color = excluded.color,
    remark = excluded.remark,
    tenant_id = excluded.tenant_id,
    update_by = excluded.update_by,
    update_time = now();

with button_seed (id, name, title, sort) as (
  values
    ('b1530000-0000-4000-8005-000000000001'::uuid, 'SmisPositionSafetyResponsibility:View', '查看岗位安全责任制', 1),
    ('b1530000-0000-4000-8005-000000000002'::uuid, 'SmisPositionSafetyResponsibility:Add', '新增隐患排查标准', 2),
    ('b1530000-0000-4000-8005-000000000003'::uuid, 'SmisPositionSafetyResponsibility:Edit', '编辑隐患排查标准', 3),
    ('b1530000-0000-4000-8005-000000000004'::uuid, 'SmisPositionSafetyResponsibility:Delete', '删除隐患排查标准', 4),
    ('b1530000-0000-4000-8005-000000000005'::uuid, 'SmisPositionSafetyResponsibility:Import', '导入隐患排查标准', 5),
    ('b1530000-0000-4000-8005-000000000006'::uuid, 'SmisPositionSafetyResponsibility:DownloadTemplate', '下载导入模板', 6)
)
insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select
  seed.id,
  'a1530000-0000-4000-8000-000000000005'::uuid,
  seed.name,
  '',
  '',
  jsonb_build_object(
    'title', seed.title,
    'icon', '',
    'roles', jsonb_build_array(),
    'is_enable', true,
    'is_auth_button', true
  ),
  seed.sort,
  'button',
  'smis',
  '624944977@qq.com',
  '624944977@qq.com'
from button_seed seed
on conflict (id) do update
set parent_id = excluded.parent_id,
    name = excluded.name,
    path = excluded.path,
    component = excluded.component,
    meta = excluded.meta,
    sort = excluded.sort,
    type = excluded.type,
    app_code = excluded.app_code,
    update_by = excluded.update_by,
    update_time = now();

with page_holders as (
  select role_id, tenant_id
  from public.sys_role_menu
  where menu_id = 'a1530000-0000-4000-8000-000000000005'::uuid
), target_user_roles as (
  select distinct role_row.id as role_id, role_row.tenant_id
  from public.sys_user user_row
  join public.sys_role role_row
    on role_row.role_code = any(coalesce(user_row.user_roles, array[]::text[]))
   and role_row.tenant_id = user_row.tenant_id
   and role_row.enabled
  where lower(user_row.user_email) = '67611039@qq.com'
    and user_row.status = '1'
    and user_row.deleted_at is null
), eligible_roles as (
  select role_id, tenant_id from page_holders
  union
  select role_id, tenant_id from target_user_roles
), grant_menu as (
  select 'a1530000-0000-4000-8000-000000000005'::uuid as menu_id
  union all select 'b1530000-0000-4000-8005-000000000001'::uuid
  union all select 'b1530000-0000-4000-8005-000000000002'::uuid
  union all select 'b1530000-0000-4000-8005-000000000003'::uuid
  union all select 'b1530000-0000-4000-8005-000000000004'::uuid
  union all select 'b1530000-0000-4000-8005-000000000005'::uuid
  union all select 'b1530000-0000-4000-8005-000000000006'::uuid
)
insert into public.sys_role_menu (
  id, role_id, menu_id, permission, create_by, update_by, tenant_id
)
select
  gen_random_uuid(),
  eligible_role.role_id,
  grant_menu.menu_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com',
  eligible_role.tenant_id
from eligible_roles eligible_role
cross join grant_menu
on conflict (role_id, menu_id) do update
set permission = excluded.permission,
    update_by = excluded.update_by,
    update_time = now(),
    tenant_id = excluded.tenant_id;

commit;

;
