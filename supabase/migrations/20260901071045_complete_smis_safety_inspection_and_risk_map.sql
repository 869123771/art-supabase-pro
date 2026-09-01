create table if not exists public.smis_safety_inspection (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  inspection_type_id uuid not null references public.smis_inspection_type(id),
  inspection_type_name_snapshot text not null,
  inspection_name text not null,
  inspection_organization_id uuid not null,
  inspection_organization_name_snapshot text not null,
  inspected_organization_id uuid not null,
  inspected_organization_name_snapshot text not null,
  inspection_time timestamptz not null,
  plan_attachment_urls jsonb not null default '[]'::jsonb,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_safety_inspection_name_check
    check (char_length(btrim(inspection_name)) between 1 and 160),
  constraint smis_safety_inspection_attachments_check
    check (jsonb_typeof(plan_attachment_urls) = 'array'),
  constraint smis_safety_inspection_inspection_org_fk
    foreign key (tenant_id, inspection_organization_id)
    references public.sys_organization(tenant_id, id),
  constraint smis_safety_inspection_inspected_org_fk
    foreign key (tenant_id, inspected_organization_id)
    references public.sys_organization(tenant_id, id),
  constraint smis_safety_inspection_tenant_id_id_key unique (tenant_id, id)
);

create table if not exists public.smis_safety_inspection_inspector (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  inspection_id uuid not null,
  employee_id uuid not null,
  employee_name_snapshot text not null,
  employee_no_snapshot text not null,
  sort integer not null default 0 check (sort >= 0),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_safety_inspection_inspector_inspection_fk
    foreign key (tenant_id, inspection_id)
    references public.smis_safety_inspection(tenant_id, id) on delete cascade,
  constraint smis_safety_inspection_inspector_employee_fk
    foreign key (tenant_id, employee_id)
    references public.hr_employee(tenant_id, id),
  constraint smis_safety_inspection_inspector_unique
    unique (tenant_id, inspection_id, employee_id)
);

create table if not exists public.smis_risk_map_scene (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  parent_id uuid,
  scene_name text not null,
  background_url text,
  canvas_width integer not null default 1000 check (canvas_width between 480 and 4000),
  canvas_height integer not null default 650 check (canvas_height between 320 and 3000),
  sort integer not null default 0 check (sort >= 0),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_map_scene_name_check
    check (char_length(btrim(scene_name)) between 1 and 80),
  constraint smis_risk_map_scene_tenant_id_id_key unique (tenant_id, id),
  constraint smis_risk_map_scene_parent_fk
    foreign key (tenant_id, parent_id)
    references public.smis_risk_map_scene(tenant_id, id)
);

create table if not exists public.smis_risk_map_shape (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id()
    references public.sys_tenant(id),
  scene_id uuid not null,
  shape_type text not null check (shape_type in ('rectangle', 'circle', 'polygon', 'text')),
  x numeric(10, 2) not null default 0,
  y numeric(10, 2) not null default 0,
  width numeric(10, 2) not null default 140 check (width between 8 and 4000),
  height numeric(10, 2) not null default 90 check (height between 8 and 3000),
  rotation numeric(7, 2) not null default 0,
  fill_color text not null default '#22C55E',
  fill_opacity numeric(4, 3) not null default 0.82 check (fill_opacity between 0 and 1),
  border_color text not null default '#15803D',
  border_opacity numeric(4, 3) not null default 1 check (border_opacity between 0 and 1),
  border_width numeric(6, 2) not null default 2 check (border_width between 0 and 40),
  label text,
  points jsonb not null default '[]'::jsonb,
  risk_point_id uuid,
  sort integer not null default 0 check (sort >= 0),
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_risk_map_shape_fill_color_check
    check (fill_color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint smis_risk_map_shape_border_color_check
    check (border_color ~ '^#[0-9A-Fa-f]{6}$'),
  constraint smis_risk_map_shape_points_check
    check (jsonb_typeof(points) = 'array'),
  constraint smis_risk_map_shape_scene_fk
    foreign key (tenant_id, scene_id)
    references public.smis_risk_map_scene(tenant_id, id) on delete cascade,
  constraint smis_risk_map_shape_risk_point_fk
    foreign key (tenant_id, risk_point_id)
    references public.smis_risk_point(tenant_id, id)
);

create index if not exists idx_smis_safety_inspection_tenant_time
  on public.smis_safety_inspection(tenant_id, inspection_time desc);
create index if not exists idx_smis_safety_inspection_type
  on public.smis_safety_inspection(tenant_id, inspection_type_id);
create index if not exists idx_smis_safety_inspection_inspected_org
  on public.smis_safety_inspection(tenant_id, inspected_organization_id);
create index if not exists idx_smis_safety_inspection_inspector_employee
  on public.smis_safety_inspection_inspector(tenant_id, employee_id, inspection_id);
create index if not exists idx_smis_risk_map_scene_parent
  on public.smis_risk_map_scene(tenant_id, parent_id, sort);
create index if not exists idx_smis_risk_map_shape_scene
  on public.smis_risk_map_shape(tenant_id, scene_id, sort);
create index if not exists idx_smis_risk_map_shape_risk_point
  on public.smis_risk_map_shape(tenant_id, risk_point_id)
  where risk_point_id is not null;

drop trigger if exists smis_safety_inspection_create_audit on public.smis_safety_inspection;
create trigger smis_safety_inspection_create_audit
before insert on public.smis_safety_inspection
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_safety_inspection_update_audit on public.smis_safety_inspection;
create trigger smis_safety_inspection_update_audit
before update on public.smis_safety_inspection
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists smis_safety_inspection_inspector_create_audit
  on public.smis_safety_inspection_inspector;
create trigger smis_safety_inspection_inspector_create_audit
before insert on public.smis_safety_inspection_inspector
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_safety_inspection_inspector_update_audit
  on public.smis_safety_inspection_inspector;
create trigger smis_safety_inspection_inspector_update_audit
before update on public.smis_safety_inspection_inspector
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists smis_risk_map_scene_create_audit on public.smis_risk_map_scene;
create trigger smis_risk_map_scene_create_audit
before insert on public.smis_risk_map_scene
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_risk_map_scene_update_audit on public.smis_risk_map_scene;
create trigger smis_risk_map_scene_update_audit
before update on public.smis_risk_map_scene
for each row execute function public.trg_set_update_time_and_by();

drop trigger if exists smis_risk_map_shape_create_audit on public.smis_risk_map_shape;
create trigger smis_risk_map_shape_create_audit
before insert on public.smis_risk_map_shape
for each row execute function public.trg_set_create_time_and_by('true', 'true');
drop trigger if exists smis_risk_map_shape_update_audit on public.smis_risk_map_shape;
create trigger smis_risk_map_shape_update_audit
before update on public.smis_risk_map_shape
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_safety_inspection enable row level security;
alter table public.smis_safety_inspection_inspector enable row level security;
alter table public.smis_risk_map_scene enable row level security;
alter table public.smis_risk_map_shape enable row level security;

drop policy if exists smis_safety_inspection_select on public.smis_safety_inspection;
create policy smis_safety_inspection_select on public.smis_safety_inspection
for select to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlSafetyInspection:View'))
);
drop policy if exists smis_safety_inspection_insert on public.smis_safety_inspection;
create policy smis_safety_inspection_insert on public.smis_safety_inspection
for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlSafetyInspection:Add'))
);
drop policy if exists smis_safety_inspection_update on public.smis_safety_inspection;
create policy smis_safety_inspection_update on public.smis_safety_inspection
for update to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlSafetyInspection:Edit'))
)
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlSafetyInspection:Edit'))
);
drop policy if exists smis_safety_inspection_delete on public.smis_safety_inspection;
create policy smis_safety_inspection_delete on public.smis_safety_inspection
for delete to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlSafetyInspection:Delete'))
);

drop policy if exists smis_safety_inspection_inspector_select
  on public.smis_safety_inspection_inspector;
create policy smis_safety_inspection_inspector_select on public.smis_safety_inspection_inspector
for select to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlSafetyInspection:View'))
);
drop policy if exists smis_safety_inspection_inspector_insert
  on public.smis_safety_inspection_inspector;
create policy smis_safety_inspection_inspector_insert on public.smis_safety_inspection_inspector
for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (
    (select app_private.has_permission('SmisDualControlSafetyInspection:Add'))
    or (select app_private.has_permission('SmisDualControlSafetyInspection:Edit'))
    or (select app_private.has_permission('SmisDualControlSafetyInspection:Copy'))
  )
);
drop policy if exists smis_safety_inspection_inspector_update
  on public.smis_safety_inspection_inspector;
create policy smis_safety_inspection_inspector_update on public.smis_safety_inspection_inspector
for update to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlSafetyInspection:Edit'))
)
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlSafetyInspection:Edit'))
);
drop policy if exists smis_safety_inspection_inspector_delete
  on public.smis_safety_inspection_inspector;
create policy smis_safety_inspection_inspector_delete on public.smis_safety_inspection_inspector
for delete to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (
    (select app_private.has_permission('SmisDualControlSafetyInspection:Edit'))
    or (select app_private.has_permission('SmisDualControlSafetyInspection:Delete'))
  )
);

drop policy if exists smis_risk_map_scene_select on public.smis_risk_map_scene;
create policy smis_risk_map_scene_select on public.smis_risk_map_scene
for select to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:View'))
);
drop policy if exists smis_risk_map_scene_insert on public.smis_risk_map_scene;
create policy smis_risk_map_scene_insert on public.smis_risk_map_scene
for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:AddScene'))
);
drop policy if exists smis_risk_map_scene_update on public.smis_risk_map_scene;
create policy smis_risk_map_scene_update on public.smis_risk_map_scene
for update to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:EditScene'))
)
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:EditScene'))
);
drop policy if exists smis_risk_map_scene_delete on public.smis_risk_map_scene;
create policy smis_risk_map_scene_delete on public.smis_risk_map_scene
for delete to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:DeleteScene'))
);

drop policy if exists smis_risk_map_shape_select on public.smis_risk_map_shape;
create policy smis_risk_map_shape_select on public.smis_risk_map_shape
for select to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:View'))
);
drop policy if exists smis_risk_map_shape_insert on public.smis_risk_map_shape;
create policy smis_risk_map_shape_insert on public.smis_risk_map_shape
for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:Save'))
);
drop policy if exists smis_risk_map_shape_update on public.smis_risk_map_shape;
create policy smis_risk_map_shape_update on public.smis_risk_map_shape
for update to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:Save'))
)
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:Save'))
);
drop policy if exists smis_risk_map_shape_delete on public.smis_risk_map_shape;
create policy smis_risk_map_shape_delete on public.smis_risk_map_shape
for delete to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisDualControlRiskFourColorMap:Save'))
);

grant select, insert, update, delete on public.smis_safety_inspection to authenticated;
grant select, insert, update, delete on public.smis_safety_inspection_inspector to authenticated;
grant select, insert, update, delete on public.smis_risk_map_scene to authenticated;
grant select, insert, update, delete on public.smis_risk_map_shape to authenticated;

create or replace function public.smis_list_safety_inspection_options_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not (
    app_private.has_permission('SmisDualControlSafetyInspection:View')
    or app_private.has_permission('SmisDualControlSafetyInspection:Add')
    or app_private.has_permission('SmisDualControlSafetyInspection:Edit')
  ) then
    raise exception '当前账号没有查看安全检查选项的权限' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'inspectionTypes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', inspection_type.id,
        'typeCode', inspection_type.type_code,
        'typeName', inspection_type.type_name,
        'textColor', inspection_type.text_color,
        'tagStyle', inspection_type.tag_style
      ) order by inspection_type.sort, inspection_type.type_name)
      from public.smis_inspection_type inspection_type
      where inspection_type.tenant_id = v_tenant_id
        and inspection_type.status = 'enabled'
    ), '[]'::jsonb),
    'organizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', organization.id,
        'parentId', organization.parent_id,
        'organizationCode', organization.organization_code,
        'organizationName', organization.organization_name,
        'organizationType', organization.organization_type,
        'sort', organization.sort
      ) order by organization.sort, organization.organization_name)
      from public.sys_organization organization
      where organization.tenant_id = v_tenant_id
        and organization.status = '1'
    ), '[]'::jsonb)
  );
end
$$;

create or replace function public.smis_list_safety_inspections_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_inspection_name text default null,
  p_inspection_from timestamptz default null,
  p_inspection_to timestamptz default null,
  p_inspected_organization_id uuid default null,
  p_inspection_type_id uuid default null,
  p_inspector_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.has_permission('SmisDualControlSafetyInspection:View') then
    raise exception '当前账号没有查看安全检查的权限' using errcode = '42501';
  end if;

  return (
    with records as (
      select
        inspection.*,
        coalesce(inspectors.rows, '[]'::jsonb) as inspectors,
        coalesce(inspectors.names, '') as inspector_names
      from public.smis_safety_inspection inspection
      left join lateral (
        select
          jsonb_agg(jsonb_build_object(
            'id', inspector.employee_id,
            'employeeName', inspector.employee_name_snapshot,
            'employeeNo', inspector.employee_no_snapshot,
            'organizationId', employee.organization_id,
            'jobTitle', employee.job_title,
            'employmentStatus', employee.employment_status,
            'tenantId', inspector.tenant_id
          ) order by inspector.sort, inspector.employee_name_snapshot) as rows,
          string_agg(inspector.employee_name_snapshot, '、' order by inspector.sort) as names
        from public.smis_safety_inspection_inspector inspector
        left join public.hr_employee employee
          on employee.tenant_id = inspector.tenant_id
         and employee.id = inspector.employee_id
        where inspector.tenant_id = inspection.tenant_id
          and inspector.inspection_id = inspection.id
      ) inspectors on true
      where inspection.tenant_id = v_tenant_id
        and (
          p_inspection_name is null
          or btrim(p_inspection_name) = ''
          or inspection.inspection_name ilike '%' || btrim(p_inspection_name) || '%'
        )
        and (p_inspection_from is null or inspection.inspection_time >= p_inspection_from)
        and (p_inspection_to is null or inspection.inspection_time <= p_inspection_to)
        and (
          p_inspected_organization_id is null
          or inspection.inspected_organization_id = p_inspected_organization_id
        )
        and (p_inspection_type_id is null or inspection.inspection_type_id = p_inspection_type_id)
        and (
          p_inspector_keyword is null
          or btrim(p_inspector_keyword) = ''
          or exists (
            select 1
            from public.smis_safety_inspection_inspector inspector_filter
            where inspector_filter.tenant_id = inspection.tenant_id
              and inspector_filter.inspection_id = inspection.id
              and (
                inspector_filter.employee_name_snapshot ilike '%' || btrim(p_inspector_keyword) || '%'
                or inspector_filter.employee_no_snapshot ilike '%' || btrim(p_inspector_keyword) || '%'
              )
          )
        )
    ), paged as (
      select *
      from records
      order by inspection_time desc, create_time desc
      offset greatest(coalesce(p_from, 0), 0)
      limit greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1)
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', row_item.id,
          'tenantId', row_item.tenant_id,
          'inspectionTypeId', row_item.inspection_type_id,
          'inspectionTypeName', row_item.inspection_type_name_snapshot,
          'inspectionName', row_item.inspection_name,
          'inspectionOrganizationId', row_item.inspection_organization_id,
          'inspectionOrganizationName', row_item.inspection_organization_name_snapshot,
          'inspectedOrganizationId', row_item.inspected_organization_id,
          'inspectedOrganizationName', row_item.inspected_organization_name_snapshot,
          'inspectionTime', row_item.inspection_time,
          'planAttachmentUrls', row_item.plan_attachment_urls,
          'remark', row_item.remark,
          'inspectors', row_item.inspectors,
          'inspectorNames', row_item.inspector_names,
          'createBy', row_item.create_by,
          'createTime', row_item.create_time,
          'updateBy', row_item.update_by,
          'updateTime', row_item.update_time
        ) order by row_item.inspection_time desc, row_item.create_time desc)
        from paged row_item
      ), '[]'::jsonb),
      'total', (select count(*) from records),
      'overview', jsonb_build_object(
        'total', (select count(*) from records),
        'thisMonth', (select count(*) from records where inspection_time >= date_trunc('month', now())),
        'organizationCount', (select count(distinct inspected_organization_id) from records),
        'inspectorCount', (
          select count(distinct inspector.employee_id)
          from public.smis_safety_inspection_inspector inspector
          join records record on record.id = inspector.inspection_id
          where inspector.tenant_id = v_tenant_id
        )
      )
    )
  );
end
$$;

create or replace function public.smis_save_safety_inspection_secure(
  p_id uuid,
  p_payload jsonb,
  p_inspector_ids jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid := p_id;
  v_type_id uuid;
  v_inspection_org_id uuid;
  v_inspected_org_id uuid;
  v_employee_id uuid;
  v_sort integer := 0;
  v_type_name text;
  v_inspection_org_name text;
  v_inspected_org_name text;
begin
  if p_id is null and not app_private.has_permission('SmisDualControlSafetyInspection:Add') then
    raise exception '当前账号没有新增安全检查的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisDualControlSafetyInspection:Edit') then
    raise exception '当前账号没有编辑安全检查的权限' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_inspector_ids, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_inspector_ids, '[]'::jsonb)) = 0 then
    raise exception '请至少选择一名检查人' using errcode = '22023';
  end if;

  begin
    v_type_id := (p_payload->>'inspection_type_id')::uuid;
    v_inspection_org_id := (p_payload->>'inspection_organization_id')::uuid;
    v_inspected_org_id := (p_payload->>'inspected_organization_id')::uuid;
  exception when others then
    raise exception '检查类别或组织单位格式无效' using errcode = '22023';
  end;

  select type_name into v_type_name
  from public.smis_inspection_type
  where tenant_id = v_tenant_id and id = v_type_id and status = 'enabled';
  select organization_name into v_inspection_org_name
  from public.sys_organization
  where tenant_id = v_tenant_id and id = v_inspection_org_id and status = '1';
  select organization_name into v_inspected_org_name
  from public.sys_organization
  where tenant_id = v_tenant_id and id = v_inspected_org_id and status = '1';

  if v_type_name is null then
    raise exception '检查类别不存在、已停用或不属于当前租户' using errcode = '22023';
  end if;
  if v_inspection_org_name is null or v_inspected_org_name is null then
    raise exception '检查单位或被检查单位不存在、已停用或不属于当前租户' using errcode = '22023';
  end if;
  if nullif(btrim(coalesce(p_payload->>'inspection_name', '')), '') is null then
    raise exception '请输入检查名称' using errcode = '22023';
  end if;

  if v_id is null then
    insert into public.smis_safety_inspection(
      tenant_id, inspection_type_id, inspection_type_name_snapshot, inspection_name,
      inspection_organization_id, inspection_organization_name_snapshot,
      inspected_organization_id, inspected_organization_name_snapshot,
      inspection_time, plan_attachment_urls, remark
    ) values (
      v_tenant_id, v_type_id, v_type_name, btrim(p_payload->>'inspection_name'),
      v_inspection_org_id, v_inspection_org_name,
      v_inspected_org_id, v_inspected_org_name,
      (p_payload->>'inspection_time')::timestamptz,
      coalesce(p_payload->'plan_attachment_urls', '[]'::jsonb),
      nullif(btrim(coalesce(p_payload->>'remark', '')), '')
    ) returning id into v_id;
  else
    update public.smis_safety_inspection
    set inspection_type_id = v_type_id,
        inspection_type_name_snapshot = v_type_name,
        inspection_name = btrim(p_payload->>'inspection_name'),
        inspection_organization_id = v_inspection_org_id,
        inspection_organization_name_snapshot = v_inspection_org_name,
        inspected_organization_id = v_inspected_org_id,
        inspected_organization_name_snapshot = v_inspected_org_name,
        inspection_time = (p_payload->>'inspection_time')::timestamptz,
        plan_attachment_urls = coalesce(p_payload->'plan_attachment_urls', '[]'::jsonb),
        remark = nullif(btrim(coalesce(p_payload->>'remark', '')), '')
    where tenant_id = v_tenant_id and id = v_id;
    if not found then
      raise exception '安全检查记录不存在或不属于当前租户' using errcode = 'P0002';
    end if;
    delete from public.smis_safety_inspection_inspector
    where tenant_id = v_tenant_id and inspection_id = v_id;
  end if;

  for v_employee_id in
    select distinct value::text::uuid from jsonb_array_elements_text(p_inspector_ids)
  loop
    insert into public.smis_safety_inspection_inspector(
      tenant_id, inspection_id, employee_id,
      employee_name_snapshot, employee_no_snapshot, sort
    )
    select v_tenant_id, v_id, employee.id, employee.employee_name, employee.employee_no, v_sort
    from public.hr_employee employee
    where employee.tenant_id = v_tenant_id
      and employee.id = v_employee_id
      and employee.employment_status in ('active', 'probation');
    if not found then
      raise exception '检查人不存在、已离职或不属于当前租户' using errcode = '22023';
    end if;
    v_sort := v_sort + 1;
  end loop;

  return v_id;
end
$$;

create or replace function public.smis_copy_safety_inspection_secure(p_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_new_id uuid;
begin
  if not app_private.has_permission('SmisDualControlSafetyInspection:Copy') then
    raise exception '当前账号没有复制安全检查的权限' using errcode = '42501';
  end if;

  insert into public.smis_safety_inspection(
    tenant_id, inspection_type_id, inspection_type_name_snapshot, inspection_name,
    inspection_organization_id, inspection_organization_name_snapshot,
    inspected_organization_id, inspected_organization_name_snapshot,
    inspection_time, plan_attachment_urls, remark
  )
  select tenant_id, inspection_type_id, inspection_type_name_snapshot,
         left(inspection_name || '（复制）', 160), inspection_organization_id,
         inspection_organization_name_snapshot, inspected_organization_id,
         inspected_organization_name_snapshot, now(), plan_attachment_urls, remark
  from public.smis_safety_inspection
  where tenant_id = v_tenant_id and id = p_id
  returning id into v_new_id;

  if v_new_id is null then
    raise exception '安全检查记录不存在或不属于当前租户' using errcode = 'P0002';
  end if;

  insert into public.smis_safety_inspection_inspector(
    tenant_id, inspection_id, employee_id,
    employee_name_snapshot, employee_no_snapshot, sort
  )
  select tenant_id, v_new_id, employee_id,
         employee_name_snapshot, employee_no_snapshot, sort
  from public.smis_safety_inspection_inspector
  where tenant_id = v_tenant_id and inspection_id = p_id;

  return v_new_id;
end
$$;

create or replace function public.smis_delete_safety_inspections_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_count integer;
begin
  if not app_private.has_permission('SmisDualControlSafetyInspection:Delete') then
    raise exception '当前账号没有删除安全检查的权限' using errcode = '42501';
  end if;
  delete from public.smis_safety_inspection
  where tenant_id = v_tenant_id and id = any(coalesce(p_ids, '{}'::uuid[]));
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

create or replace function public.smis_list_risk_map_scenes_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.has_permission('SmisDualControlRiskFourColorMap:View') then
    raise exception '当前账号没有查看风险四色图的权限' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', scene.id,
      'tenantId', scene.tenant_id,
      'parentId', scene.parent_id,
      'sceneName', scene.scene_name,
      'backgroundUrl', scene.background_url,
      'canvasWidth', scene.canvas_width,
      'canvasHeight', scene.canvas_height,
      'sort', scene.sort,
      'createBy', scene.create_by,
      'createTime', scene.create_time,
      'updateBy', scene.update_by,
      'updateTime', scene.update_time,
      'shapes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', shape.id,
          'sceneId', shape.scene_id,
          'shapeType', shape.shape_type,
          'x', shape.x,
          'y', shape.y,
          'width', shape.width,
          'height', shape.height,
          'rotation', shape.rotation,
          'fillColor', shape.fill_color,
          'fillOpacity', shape.fill_opacity,
          'borderColor', shape.border_color,
          'borderOpacity', shape.border_opacity,
          'borderWidth', shape.border_width,
          'label', shape.label,
          'points', shape.points,
          'riskPointId', shape.risk_point_id,
          'riskPointName', risk_point.point_name,
          'riskPointNo', risk_point.point_no,
          'riskLevelCode', evaluated.level_code,
          'riskLevelName', evaluated.level_name,
          'riskLevelColor', evaluated.level_color,
          'sort', shape.sort
        ) order by shape.sort, shape.create_time)
        from public.smis_risk_map_shape shape
        left join public.smis_risk_point risk_point
          on risk_point.tenant_id = shape.tenant_id
         and risk_point.id = shape.risk_point_id
        left join lateral (
          select level.level_code, level.level_name, level.color as level_color
          from public.smis_risk_item item
          join public.smis_risk_evaluation evaluation
            on evaluation.tenant_id = item.tenant_id
           and evaluation.risk_item_id = item.id
          join public.smis_risk_assessment_level level
            on level.tenant_id = evaluation.tenant_id
           and level.id = evaluation.risk_level_id
          where item.tenant_id = risk_point.tenant_id
            and item.risk_point_id = risk_point.id
            and item.status <> 'voided'
          order by level.sort
          limit 1
        ) evaluated on true
        where shape.tenant_id = scene.tenant_id and shape.scene_id = scene.id
      ), '[]'::jsonb)
    ) order by scene.sort, scene.scene_name)
    from public.smis_risk_map_scene scene
    where scene.tenant_id = v_tenant_id
  ), '[]'::jsonb);
end
$$;

create or replace function public.smis_list_risk_map_points_secure()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.has_permission('SmisDualControlRiskFourColorMap:View') then
    raise exception '当前账号没有查看风险点的权限' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', point.id,
      'pointNo', point.point_no,
      'pointName', point.point_name,
      'riskType', point.risk_type,
      'siteName', site.site_name,
      'riskLevelCode', evaluated.level_code,
      'riskLevelName', evaluated.level_name,
      'riskLevelColor', evaluated.level_color
    ) order by point.sort, point.point_no)
    from public.smis_risk_point point
    join public.smis_site site
      on site.tenant_id = point.tenant_id and site.id = point.site_id
    left join lateral (
      select level.level_code, level.level_name, level.color as level_color
      from public.smis_risk_item item
      join public.smis_risk_evaluation evaluation
        on evaluation.tenant_id = item.tenant_id and evaluation.risk_item_id = item.id
      join public.smis_risk_assessment_level level
        on level.tenant_id = evaluation.tenant_id and level.id = evaluation.risk_level_id
      where item.tenant_id = point.tenant_id
        and item.risk_point_id = point.id
        and item.status <> 'voided'
      order by level.sort
      limit 1
    ) evaluated on true
    where point.tenant_id = v_tenant_id and point.status = 'enabled'
  ), '[]'::jsonb);
end
$$;

create or replace function public.smis_save_risk_map_scene_secure(
  p_id uuid,
  p_parent_id uuid,
  p_scene_name text,
  p_background_url text,
  p_canvas_width integer,
  p_canvas_height integer,
  p_sort integer
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid := p_id;
begin
  if p_id is null and not app_private.has_permission('SmisDualControlRiskFourColorMap:AddScene') then
    raise exception '当前账号没有新增场景的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisDualControlRiskFourColorMap:EditScene') then
    raise exception '当前账号没有编辑场景的权限' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_scene_name, '')), '') is null then
    raise exception '请输入场景名称' using errcode = '22023';
  end if;
  if p_parent_id is not null and not exists (
    select 1 from public.smis_risk_map_scene
    where tenant_id = v_tenant_id and id = p_parent_id
  ) then
    raise exception '上级场景不存在或不属于当前租户' using errcode = '22023';
  end if;
  if p_id is not null and p_parent_id = p_id then
    raise exception '上级场景不能选择当前场景' using errcode = '22023';
  end if;
  if p_id is not null and p_parent_id is not null and exists (
    with recursive descendants as (
      select id from public.smis_risk_map_scene
      where tenant_id = v_tenant_id and parent_id = p_id
      union all
      select child.id
      from public.smis_risk_map_scene child
      join descendants parent on child.parent_id = parent.id
      where child.tenant_id = v_tenant_id
    )
    select 1 from descendants where id = p_parent_id
  ) then
    raise exception '不能将场景移动到自己的下级场景' using errcode = '22023';
  end if;

  if v_id is null then
    insert into public.smis_risk_map_scene(
      tenant_id, parent_id, scene_name, background_url, canvas_width, canvas_height, sort
    ) values (
      v_tenant_id, p_parent_id, btrim(p_scene_name),
      nullif(btrim(coalesce(p_background_url, '')), ''),
      greatest(coalesce(p_canvas_width, 1000), 480),
      greatest(coalesce(p_canvas_height, 650), 320),
      greatest(coalesce(p_sort, 0), 0)
    ) returning id into v_id;
  else
    update public.smis_risk_map_scene
    set parent_id = p_parent_id,
        scene_name = btrim(p_scene_name),
        background_url = nullif(btrim(coalesce(p_background_url, '')), ''),
        canvas_width = greatest(coalesce(p_canvas_width, canvas_width), 480),
        canvas_height = greatest(coalesce(p_canvas_height, canvas_height), 320),
        sort = greatest(coalesce(p_sort, sort), 0)
    where tenant_id = v_tenant_id and id = v_id;
    if not found then
      raise exception '场景不存在或不属于当前租户' using errcode = 'P0002';
    end if;
  end if;
  return v_id;
end
$$;

create or replace function public.smis_save_risk_map_shapes_secure(
  p_scene_id uuid,
  p_shapes jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_shape jsonb;
  v_risk_point_id uuid;
  v_count integer := 0;
begin
  if not app_private.has_permission('SmisDualControlRiskFourColorMap:Save') then
    raise exception '当前账号没有保存四色图的权限' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.smis_risk_map_scene
    where tenant_id = v_tenant_id and id = p_scene_id
  ) then
    raise exception '场景不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  if jsonb_typeof(coalesce(p_shapes, '[]'::jsonb)) <> 'array' then
    raise exception '图形配置格式无效' using errcode = '22023';
  end if;

  delete from public.smis_risk_map_shape
  where tenant_id = v_tenant_id and scene_id = p_scene_id;

  for v_shape in select * from jsonb_array_elements(coalesce(p_shapes, '[]'::jsonb))
  loop
    if coalesce(v_shape->>'shape_type', '') not in ('rectangle', 'circle', 'polygon', 'text') then
      raise exception '图形类型无效' using errcode = '22023';
    end if;
    v_risk_point_id := null;
    if nullif(v_shape->>'risk_point_id', '') is not null then
      begin
        v_risk_point_id := (v_shape->>'risk_point_id')::uuid;
      exception when others then
        raise exception '关联风险点格式无效' using errcode = '22023';
      end;
      if not exists (
        select 1 from public.smis_risk_point
        where tenant_id = v_tenant_id and id = v_risk_point_id and status = 'enabled'
      ) then
        raise exception '关联风险点不存在、已停用或不属于当前租户' using errcode = '22023';
      end if;
    end if;

    insert into public.smis_risk_map_shape(
      id, tenant_id, scene_id, shape_type, x, y, width, height, rotation,
      fill_color, fill_opacity, border_color, border_opacity, border_width,
      label, points, risk_point_id, sort
    ) values (
      coalesce(nullif(v_shape->>'id', '')::uuid, gen_random_uuid()),
      v_tenant_id,
      p_scene_id,
      v_shape->>'shape_type',
      greatest(coalesce((v_shape->>'x')::numeric, 0), 0),
      greatest(coalesce((v_shape->>'y')::numeric, 0), 0),
      greatest(coalesce((v_shape->>'width')::numeric, 140), 8),
      greatest(coalesce((v_shape->>'height')::numeric, 90), 8),
      coalesce((v_shape->>'rotation')::numeric, 0),
      coalesce(nullif(v_shape->>'fill_color', ''), '#22C55E'),
      least(greatest(coalesce((v_shape->>'fill_opacity')::numeric, 0.82), 0), 1),
      coalesce(nullif(v_shape->>'border_color', ''), '#15803D'),
      least(greatest(coalesce((v_shape->>'border_opacity')::numeric, 1), 0), 1),
      least(greatest(coalesce((v_shape->>'border_width')::numeric, 2), 0), 40),
      nullif(btrim(coalesce(v_shape->>'label', '')), ''),
      coalesce(v_shape->'points', '[]'::jsonb),
      v_risk_point_id,
      greatest(coalesce((v_shape->>'sort')::integer, v_count), 0)
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end
$$;

create or replace function public.smis_delete_risk_map_scene_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.has_permission('SmisDualControlRiskFourColorMap:DeleteScene') then
    raise exception '当前账号没有删除场景的权限' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.smis_risk_map_scene
    where tenant_id = v_tenant_id and parent_id = p_id
  ) then
    raise exception '请先删除当前场景的下级场景' using errcode = '23503';
  end if;
  delete from public.smis_risk_map_scene where tenant_id = v_tenant_id and id = p_id;
  if not found then
    raise exception '场景不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  return true;
end
$$;

revoke all on function public.smis_list_safety_inspection_options_secure() from public;
revoke all on function public.smis_list_safety_inspections_secure(integer, integer, text, timestamptz, timestamptz, uuid, uuid, text) from public;
revoke all on function public.smis_save_safety_inspection_secure(uuid, jsonb, jsonb) from public;
revoke all on function public.smis_copy_safety_inspection_secure(uuid) from public;
revoke all on function public.smis_delete_safety_inspections_secure(uuid[]) from public;
revoke all on function public.smis_list_risk_map_scenes_secure() from public;
revoke all on function public.smis_list_risk_map_points_secure() from public;
revoke all on function public.smis_save_risk_map_scene_secure(uuid, uuid, text, text, integer, integer, integer) from public;
revoke all on function public.smis_save_risk_map_shapes_secure(uuid, jsonb) from public;
revoke all on function public.smis_delete_risk_map_scene_secure(uuid) from public;

grant execute on function public.smis_list_safety_inspection_options_secure() to authenticated;
grant execute on function public.smis_list_safety_inspections_secure(integer, integer, text, timestamptz, timestamptz, uuid, uuid, text) to authenticated;
grant execute on function public.smis_save_safety_inspection_secure(uuid, jsonb, jsonb) to authenticated;
grant execute on function public.smis_copy_safety_inspection_secure(uuid) to authenticated;
grant execute on function public.smis_delete_safety_inspections_secure(uuid[]) to authenticated;
grant execute on function public.smis_list_risk_map_scenes_secure() to authenticated;
grant execute on function public.smis_list_risk_map_points_secure() to authenticated;
grant execute on function public.smis_save_risk_map_scene_secure(uuid, uuid, text, text, integer, integer, integer) to authenticated;
grant execute on function public.smis_save_risk_map_shapes_secure(uuid, jsonb) to authenticated;
grant execute on function public.smis_delete_risk_map_scene_secure(uuid) to authenticated;

do $$
declare
  v_definition record;
  v_parent public.sys_menu%rowtype;
begin
  for v_definition in
    select * from (values
      ('SmisDualControlSafetyInspection', 'SmisDualControlSafetyInspection:View', '查看安全检查', 1),
      ('SmisDualControlSafetyInspection', 'SmisDualControlSafetyInspection:Add', '新增安全检查', 2),
      ('SmisDualControlSafetyInspection', 'SmisDualControlSafetyInspection:Copy', '复制安全检查', 3),
      ('SmisDualControlSafetyInspection', 'SmisDualControlSafetyInspection:Edit', '编辑安全检查', 4),
      ('SmisDualControlSafetyInspection', 'SmisDualControlSafetyInspection:Delete', '删除安全检查', 5),
      ('SmisDualControlSafetyInspection', 'SmisDualControlSafetyInspection:Export', '导出安全检查', 6),
      ('SmisDualControlSafetyInspection', 'SmisDualControlSafetyInspection:RectificationNotice', '安全检查整改指令书', 7),
      ('SmisDualControlRiskFourColorMap', 'SmisDualControlRiskFourColorMap:View', '查看风险四色图', 1),
      ('SmisDualControlRiskFourColorMap', 'SmisDualControlRiskFourColorMap:AddScene', '新增四色图场景', 2),
      ('SmisDualControlRiskFourColorMap', 'SmisDualControlRiskFourColorMap:EditScene', '编辑四色图场景', 3),
      ('SmisDualControlRiskFourColorMap', 'SmisDualControlRiskFourColorMap:DeleteScene', '删除四色图场景', 4),
      ('SmisDualControlRiskFourColorMap', 'SmisDualControlRiskFourColorMap:Save', '保存四色图配置', 5),
      ('SmisDualControlRiskFourColorMap', 'SmisDualControlRiskFourColorMap:Export', '下载四色图', 6)
    ) as definitions(parent_name, permission_code, title, sort_value)
  loop
    select * into v_parent from public.sys_menu where name = v_definition.parent_name limit 1;
    if v_parent.id is null then
      raise exception '未找到菜单：%', v_definition.parent_name;
    end if;

    insert into public.sys_menu(
      parent_id, name, path, component, type, sort, app_code,
      meta, create_by, update_by
    )
    select
      v_parent.id, v_definition.permission_code, null, null, 'button',
      v_definition.sort_value, v_parent.app_code,
      jsonb_build_object(
        'title', v_definition.title,
        'icon', '',
        'is_hide', true,
        'is_enable', true,
        'roles', '[]'::jsonb
      ),
      '624944977@qq.com', '624944977@qq.com'
    where not exists (
      select 1 from public.sys_menu existing
      where existing.name = v_definition.permission_code
        and existing.parent_id = v_parent.id
    );

    update public.sys_menu
    set sort = v_definition.sort_value,
        meta = jsonb_set(
          jsonb_set(coalesce(meta, '{}'::jsonb), '{title}', to_jsonb(v_definition.title), true),
          '{is_enable}', 'true'::jsonb, true
        ),
        update_by = '624944977@qq.com',
        update_time = now()
    where name = v_definition.permission_code and parent_id = v_parent.id;
  end loop;

  insert into public.sys_role_menu(
    role_id, menu_id, tenant_id, permission, create_by, update_by
  )
  select distinct
    page_grant.role_id,
    button.id,
    page_grant.tenant_id,
    '{}'::jsonb,
    '624944977@qq.com',
    '624944977@qq.com'
  from public.sys_role_menu page_grant
  join public.sys_menu page on page.id = page_grant.menu_id
  join public.sys_menu button on button.parent_id = page.id and button.type = 'button'
  where page.name in ('SmisDualControlSafetyInspection', 'SmisDualControlRiskFourColorMap')
  on conflict (role_id, menu_id) do nothing;

  update public.sys_menu
  set meta = jsonb_set(
        coalesce(meta, '{}'::jsonb),
        '{icon}',
        to_jsonb(case name
          when 'SmisDualControlSafetyInspection' then 'ri:shield-check-line'
          when 'SmisDualControlRiskFourColorMap' then 'ri:map-2-line'
        end),
        true
      ),
      update_by = '624944977@qq.com',
      update_time = now()
  where name in ('SmisDualControlSafetyInspection', 'SmisDualControlRiskFourColorMap')
    and coalesce(meta->>'icon', '') = '';
end
$$;

;
