create table if not exists public.smis_position_risk_control (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  organization_id uuid not null,
  position_id uuid not null,
  hazard_factor text not null,
  control_measure text not null,
  control_measure_category text not null,
  control_level text not null,
  standard_basis text not null,
  failure_mode text not null,
  primary_hazard_category text not null,
  secondary_hazard_category text not null,
  hazard_level text not null,
  is_special_equipment boolean not null default false,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_position_risk_control_tenant_fkey
    foreign key (tenant_id) references public.sys_tenant(id) on delete restrict,
  constraint smis_position_risk_control_organization_tenant_fkey
    foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_position_risk_control_position_tenant_fkey
    foreign key (position_id, tenant_id)
    references public.hr_position(id, tenant_id) on delete restrict,
  constraint smis_position_risk_control_text_check check (
    btrim(hazard_factor) <> ''
    and btrim(control_measure) <> ''
    and btrim(standard_basis) <> ''
    and btrim(failure_mode) <> ''
  ),
  constraint smis_position_risk_control_measure_category_check check (
    control_measure_category = any(array[
      'emergency','education','engineering','management','personal_protection','other'
    ]::text[])
  ),
  constraint smis_position_risk_control_level_check check (
    control_level = any(array[
      'company','operation_department','operation_area','team',
      'project_department','branch_company','group'
    ]::text[])
  ),
  constraint smis_position_risk_control_primary_category_check check (
    primary_hazard_category = any(array['basic_management','site_management']::text[])
  ),
  constraint smis_position_risk_control_secondary_category_check check (
    secondary_hazard_category = any(array[
      'safety_rules','occupational_hazard','raw_material_product','equipment_facility',
      'workplace','protective_equipment','safety_skill','related_party_operation',
      'other','personal_protection'
    ]::text[])
  ),
  constraint smis_position_risk_control_hazard_level_check check (
    hazard_level = any(array[
      'general_a','general_b','general_c','general_d','major'
    ]::text[])
  )
);

comment on table public.smis_position_risk_control is
  'SMIS 岗位风险清单：按组织和 HR 岗位维护隐患控制措施标准';
comment on column public.smis_position_risk_control.hazard_factor is '危害因素';
comment on column public.smis_position_risk_control.control_measure is '管控措施';
comment on column public.smis_position_risk_control.control_measure_category is '管控措施类别';
comment on column public.smis_position_risk_control.control_level is '防控级别';
comment on column public.smis_position_risk_control.standard_basis is '标准依据';
comment on column public.smis_position_risk_control.failure_mode is '失效形式';
comment on column public.smis_position_risk_control.is_special_equipment is '是否特种设备';

create index if not exists smis_position_risk_control_scope_idx
  on public.smis_position_risk_control (
    tenant_id, organization_id, position_id, update_time desc
  );
create index if not exists smis_position_risk_control_category_idx
  on public.smis_position_risk_control (
    tenant_id, control_measure_category, control_level, hazard_level
  );

alter table public.smis_position_risk_control enable row level security;

drop policy if exists tenant_select on public.smis_position_risk_control;
create policy tenant_select
on public.smis_position_risk_control
for select
to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionRiskList:View'))
  )
);

drop policy if exists tenant_insert on public.smis_position_risk_control;
create policy tenant_insert
on public.smis_position_risk_control
for insert
to authenticated
with check (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionRiskList:Add'))
  )
);

drop policy if exists tenant_update on public.smis_position_risk_control;
create policy tenant_update
on public.smis_position_risk_control
for update
to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionRiskList:Edit'))
  )
)
with check (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionRiskList:Edit'))
  )
);

drop policy if exists tenant_delete on public.smis_position_risk_control;
create policy tenant_delete
on public.smis_position_risk_control
for delete
to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisPositionRiskList:Delete'))
  )
);

drop trigger if exists smis_position_risk_control_create_audit
  on public.smis_position_risk_control;
create trigger smis_position_risk_control_create_audit
before insert on public.smis_position_risk_control
for each row
execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists smis_position_risk_control_update_audit
  on public.smis_position_risk_control;
create trigger smis_position_risk_control_update_audit
before update on public.smis_position_risk_control
for each row
execute function public.trg_set_update_time_and_by();

revoke all on table public.smis_position_risk_control from public, anon;
grant select, insert, update, delete on table public.smis_position_risk_control
  to authenticated, service_role;

create or replace function public.smis_list_risk_positions_secure(
  p_organization_id uuid,
  p_from integer default 0,
  p_to integer default 499,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
  v_result jsonb;
begin
  if not app_private.can_execute_business_action(
    'SmisPositionRiskList',
    'SmisPositionRiskList:View',
    null,
    false
  ) then
    raise exception 'Missing SMIS position risk list view permission'
      using errcode = '42501';
  end if;

  if p_organization_id is null or not exists (
    select 1
    from public.sys_organization organization_row
    where organization_row.id = p_organization_id
      and organization_row.tenant_id = v_tenant_id
      and organization_row.status = '1'
  ) then
    raise exception '组织不存在、已停用或超出当前租户范围'
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
          and employee_row.organization_id = p_organization_id
          and employee_row.position_id = position_row.id
          and employee_row.employment_status <> 'terminated'
      )::integer as employee_count,
      (
        select count(*)
        from public.smis_position_risk_control risk_row
        where risk_row.tenant_id = v_tenant_id
          and risk_row.organization_id = p_organization_id
          and risk_row.position_id = position_row.id
      )::integer as control_count
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
        exists (
          select 1
          from public.hr_position_headcount headcount_row
          where headcount_row.tenant_id = v_tenant_id
            and headcount_row.organization_id = p_organization_id
            and headcount_row.position_id = position_row.id
            and headcount_row.enabled
            and headcount_row.effective_from <= current_date
            and (
              headcount_row.effective_to is null
              or headcount_row.effective_to >= current_date
            )
        )
        or exists (
          select 1
          from public.hr_employee employee_row
          where employee_row.tenant_id = v_tenant_id
            and employee_row.organization_id = p_organization_id
            and employee_row.position_id = position_row.id
            and employee_row.employment_status <> 'terminated'
        )
        or exists (
          select 1
          from public.smis_position_risk_control risk_row
          where risk_row.tenant_id = v_tenant_id
            and risk_row.organization_id = p_organization_id
            and risk_row.position_id = position_row.id
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
    'records', coalesce((
      select jsonb_agg(to_jsonb(paged) order by sort, position_name, position_code)
      from paged
    ), '[]'::jsonb),
    'total', (select count(*) from filtered)
  )
  into v_result;

  return v_result;
end;
$function$;

revoke all on function public.smis_list_risk_positions_secure(uuid, integer, integer, text)
  from public;
revoke all on function public.smis_list_risk_positions_secure(uuid, integer, integer, text)
  from anon;
grant execute on function public.smis_list_risk_positions_secure(uuid, integer, integer, text)
  to authenticated, service_role;

with platform_tenant as (
  select id
  from public.sys_tenant
  where tenant_code = 'platform'
  limit 1
), dictionary_types(name, code, sort) as (
  values
    ('防控级别', 'smisControlLevel', 7),
    ('管控措施类别', 'smisControlMeasureCategory', 8)
)
insert into public.sys_dict_type (
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select
  gen_random_uuid(),
  seed.name,
  seed.code,
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  'SMIS 岗位风险清单字典',
  platform_tenant.id,
  (select parent_id from public.sys_dict_type where code = 'smisHazardLevel' limit 1),
  'dictionary',
  seed.sort
from dictionary_types seed
cross join platform_tenant
on conflict (code) do update
set name = excluded.name,
    status = excluded.status,
    update_by = excluded.update_by,
    update_time = now(),
    remark = excluded.remark,
    sort = excluded.sort;

with platform_tenant as (
  select id
  from public.sys_tenant
  where tenant_code = 'platform'
  limit 1
), dictionary_items(type_code, value, label, sort, tag_type) as (
  values
    ('smisControlLevel', 'company', '公司级', 1, 'primary'),
    ('smisControlLevel', 'operation_department', '作业部级', 2, 'success'),
    ('smisControlLevel', 'operation_area', '作业区级', 3, 'warning'),
    ('smisControlLevel', 'team', '班组级', 4, 'info'),
    ('smisControlLevel', 'project_department', '项目部', 5, 'primary'),
    ('smisControlLevel', 'branch_company', '分公司', 6, 'success'),
    ('smisControlLevel', 'group', '集团', 7, 'danger'),
    ('smisControlMeasureCategory', 'emergency', '应急措施', 1, 'danger'),
    ('smisControlMeasureCategory', 'education', '教育措施', 2, 'primary'),
    ('smisControlMeasureCategory', 'engineering', '工程技术', 3, 'success'),
    ('smisControlMeasureCategory', 'management', '管理措施', 4, 'warning'),
    ('smisControlMeasureCategory', 'personal_protection', '个体防护', 5, 'info'),
    ('smisControlMeasureCategory', 'other', '其他', 6, 'info')
)
insert into public.sys_dictionary (
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select
  gen_random_uuid(),
  dictionary_type.id,
  seed.value,
  '1',
  '624944977@qq.com',
  '624944977@qq.com',
  'SMIS 岗位风险清单字典项',
  seed.value,
  seed.label,
  platform_tenant.id,
  seed.tag_type,
  seed.sort
from dictionary_items seed
join public.sys_dict_type dictionary_type on dictionary_type.code = seed.type_code
cross join platform_tenant
where not exists (
  select 1
  from public.sys_dictionary existing_item
  where existing_item.type_id = dictionary_type.id
    and existing_item.value = seed.value
);

with page_menu as (
  select id
  from public.sys_menu
  where name = 'SmisPositionRiskList'
  limit 1
), button_seed(name, title, sort) as (
  values
    ('SmisPositionRiskList:View', '查看岗位风险清单', 1),
    ('SmisPositionRiskList:Add', '新增隐患控制措施', 2),
    ('SmisPositionRiskList:Edit', '编辑隐患控制措施', 3),
    ('SmisPositionRiskList:Delete', '删除隐患控制措施', 4)
)
insert into public.sys_menu (
  id, parent_id, name, path, component, meta, sort, type, app_code,
  create_by, update_by
)
select
  gen_random_uuid(),
  page_menu.id,
  seed.name,
  '',
  '',
  jsonb_build_object(
    'title', seed.title,
    'icon', '',
    'is_hide', true,
    'is_enable', true,
    'roles', jsonb_build_array()
  ),
  seed.sort,
  'button',
  'smis',
  '624944977@qq.com',
  '624944977@qq.com'
from button_seed seed
cross join page_menu
where not exists (
  select 1
  from public.sys_menu existing_button
  where existing_button.parent_id = page_menu.id
    and existing_button.name = seed.name
);

insert into public.sys_role_menu (
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select
  page_grant.role_id,
  button_menu.id,
  page_grant.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_menu page_menu
  on page_menu.id = page_grant.menu_id
 and page_menu.name = 'SmisPositionRiskList'
join public.sys_menu button_menu
  on button_menu.parent_id = page_menu.id
 and button_menu.name in (
   'SmisPositionRiskList:View',
   'SmisPositionRiskList:Add',
   'SmisPositionRiskList:Edit',
   'SmisPositionRiskList:Delete'
 )
on conflict (role_id, menu_id) do nothing;

;
