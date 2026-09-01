create table public.smis_storage_location (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  parent_id uuid,
  organization_id uuid not null,
  responsible_employee_id uuid,
  location_code text not null,
  location_name text not null,
  location_short_name text,
  detail_location text,
  remark text,
  status text not null default 'enabled',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_storage_location_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_storage_location_id_tenant_unique unique (id, tenant_id),
  constraint smis_storage_location_parent_fkey foreign key (parent_id, tenant_id)
    references public.smis_storage_location(id, tenant_id) on delete restrict,
  constraint smis_storage_location_organization_fkey foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_storage_location_responsible_employee_fkey
    foreign key (responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_storage_location_not_self_parent check (parent_id is null or parent_id <> id),
  constraint smis_storage_location_code_not_blank check (btrim(location_code) <> ''),
  constraint smis_storage_location_name_not_blank check (btrim(location_name) <> ''),
  constraint smis_storage_location_code_length check (char_length(location_code) <= 40),
  constraint smis_storage_location_name_length check (char_length(location_name) <= 100),
  constraint smis_storage_location_short_name_length check (
    location_short_name is null or char_length(location_short_name) <= 50
  ),
  constraint smis_storage_location_detail_length check (
    detail_location is null or char_length(detail_location) <= 300
  ),
  constraint smis_storage_location_remark_length check (
    remark is null or char_length(remark) <= 500
  ),
  constraint smis_storage_location_status_check check (status in ('enabled', 'disabled'))
);

comment on table public.smis_storage_location is
  '共享设备台账主数据：租户级树形存放位置';
comment on column public.smis_storage_location.organization_id is
  '位置归属的系统组织管理部门';
comment on column public.smis_storage_location.responsible_employee_id is
  '来源于员工花名册的位置负责人';

create unique index smis_storage_location_code_unique
  on public.smis_storage_location(tenant_id, lower(btrim(location_code)));
create unique index smis_storage_location_name_unique
  on public.smis_storage_location(tenant_id, lower(btrim(location_name)));
create index smis_storage_location_parent_idx
  on public.smis_storage_location(tenant_id, parent_id, status, location_name);
create index smis_storage_location_parent_fk_idx
  on public.smis_storage_location(parent_id, tenant_id)
  where parent_id is not null;
create index smis_storage_location_organization_idx
  on public.smis_storage_location(tenant_id, organization_id, status);
create index smis_storage_location_responsible_idx
  on public.smis_storage_location(responsible_employee_id, tenant_id)
  where responsible_employee_id is not null;

create trigger smis_storage_location_create_audit
before insert on public.smis_storage_location
for each row execute function public.trg_set_create_time_and_by('true', 'true');

create trigger smis_storage_location_update_audit
before update on public.smis_storage_location
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_storage_location enable row level security;

create policy smis_storage_location_tenant_select
on public.smis_storage_location for select
to authenticated
using (
  (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisStorageLocation:View'))
  )
  or (select app_private.is_platform_super())
);

create policy smis_storage_location_tenant_insert
on public.smis_storage_location for insert
to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisStorageLocation:Add'))
);

create policy smis_storage_location_tenant_update
on public.smis_storage_location for update
to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisStorageLocation:Edit'))
)
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisStorageLocation:Edit'))
);

create policy smis_storage_location_tenant_delete
on public.smis_storage_location for delete
to authenticated
using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisStorageLocation:Delete'))
);

revoke all on table public.smis_storage_location from public, anon, authenticated;
grant select, insert, update, delete on table public.smis_storage_location to service_role;

create or replace function public.smis_list_storage_locations_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_status text default null,
  p_ancestor_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_limit integer := greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1);
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
  v_records jsonb := '[]'::jsonb;
  v_tree jsonb := '[]'::jsonb;
  v_total bigint := 0;
  v_overview jsonb := '{}'::jsonb;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看存放位置';
  end if;
  if not app_private.has_permission('SmisStorageLocation:View') then
    raise exception '当前账号无权查看存放位置';
  end if;

  v_tenant_id := app_private.current_user_tenant_id();
  if v_tenant_id is null then
    raise exception '当前账号未绑定有效租户';
  end if;
  if p_status is not null and p_status not in ('enabled', 'disabled') then
    raise exception '启用状态不合法';
  end if;
  if p_ancestor_id is not null and not exists (
    select 1 from public.smis_storage_location
    where id = p_ancestor_id and tenant_id = v_tenant_id
  ) then
    raise exception '所选存放位置不存在或不属于当前租户';
  end if;

  with recursive scope_ids as (
    select id
    from public.smis_storage_location
    where tenant_id = v_tenant_id and id = p_ancestor_id
    union all
    select child.id
    from public.smis_storage_location child
    join scope_ids parent on parent.id = child.parent_id
    where child.tenant_id = v_tenant_id
  ), filtered as (
    select location.id
    from public.smis_storage_location location
    where location.tenant_id = v_tenant_id
      and (p_status is null or location.status = p_status)
      and (
        v_keyword is null
        or location.location_code ilike '%' || v_keyword || '%'
        or location.location_name ilike '%' || v_keyword || '%'
        or coalesce(location.location_short_name, '') ilike '%' || v_keyword || '%'
        or coalesce(location.detail_location, '') ilike '%' || v_keyword || '%'
        or coalesce(location.remark, '') ilike '%' || v_keyword || '%'
      )
      and (p_ancestor_id is null or location.id in (select id from scope_ids))
  )
  select count(*) into v_total from filtered;

  with recursive scope_ids as (
    select id
    from public.smis_storage_location
    where tenant_id = v_tenant_id and id = p_ancestor_id
    union all
    select child.id
    from public.smis_storage_location child
    join scope_ids parent on parent.id = child.parent_id
    where child.tenant_id = v_tenant_id
  )
  select coalesce(jsonb_agg(item.payload order by item.location_name), '[]'::jsonb)
  into v_records
  from (
    select location.location_name,
      jsonb_build_object(
        'id', location.id,
        'parentId', location.parent_id,
        'organizationId', location.organization_id,
        'responsibleEmployeeId', location.responsible_employee_id,
        'locationCode', location.location_code,
        'locationName', location.location_name,
        'locationShortName', location.location_short_name,
        'detailLocation', location.detail_location,
        'remark', location.remark,
        'status', location.status,
        'createBy', location.create_by,
        'createTime', location.create_time,
        'updateBy', location.update_by,
        'updateTime', location.update_time,
        'parentLocationName', parent.location_name,
        'childCount', (
          select count(*) from public.smis_storage_location child
          where child.tenant_id = v_tenant_id and child.parent_id = location.id
        ),
        'organization', jsonb_build_object(
          'id', organization.id,
          'organizationCode', organization.organization_code,
          'organizationName', organization.organization_name
        ),
        'responsible', case when employee.id is null then null else jsonb_build_object(
          'id', employee.id,
          'employeeNo', employee.employee_no,
          'employeeName', employee.employee_name,
          'jobTitle', employee.job_title,
          'employmentStatus', employee.employment_status,
          'organizationId', employee.organization_id,
          'organizationCode', employee_organization.organization_code,
          'organizationName', employee_organization.organization_name
        ) end
      ) as payload
    from public.smis_storage_location location
    join public.sys_organization organization
      on organization.tenant_id = location.tenant_id
      and organization.id = location.organization_id
    left join public.smis_storage_location parent
      on parent.tenant_id = location.tenant_id and parent.id = location.parent_id
    left join public.hr_employee employee
      on employee.tenant_id = location.tenant_id and employee.id = location.responsible_employee_id
    left join public.sys_organization employee_organization
      on employee_organization.tenant_id = employee.tenant_id
      and employee_organization.id = employee.organization_id
    where location.tenant_id = v_tenant_id
      and (p_status is null or location.status = p_status)
      and (
        v_keyword is null
        or location.location_code ilike '%' || v_keyword || '%'
        or location.location_name ilike '%' || v_keyword || '%'
        or coalesce(location.location_short_name, '') ilike '%' || v_keyword || '%'
        or coalesce(location.detail_location, '') ilike '%' || v_keyword || '%'
        or coalesce(location.remark, '') ilike '%' || v_keyword || '%'
      )
      and (p_ancestor_id is null or location.id in (select id from scope_ids))
    order by location.location_name, location.id
    offset v_from limit v_limit
  ) item;

  select coalesce(jsonb_agg(item.payload order by item.location_name), '[]'::jsonb)
  into v_tree
  from (
    select location.location_name,
      jsonb_build_object(
        'id', location.id,
        'parentId', location.parent_id,
        'organizationId', location.organization_id,
        'responsibleEmployeeId', location.responsible_employee_id,
        'locationCode', location.location_code,
        'locationName', location.location_name,
        'locationShortName', location.location_short_name,
        'detailLocation', location.detail_location,
        'remark', location.remark,
        'status', location.status,
        'childCount', (
          select count(*) from public.smis_storage_location child
          where child.tenant_id = v_tenant_id and child.parent_id = location.id
        ),
        'organization', jsonb_build_object(
          'id', organization.id,
          'organizationCode', organization.organization_code,
          'organizationName', organization.organization_name
        ),
        'responsible', case when employee.id is null then null else jsonb_build_object(
          'id', employee.id,
          'employeeNo', employee.employee_no,
          'employeeName', employee.employee_name,
          'jobTitle', employee.job_title,
          'employmentStatus', employee.employment_status,
          'organizationId', employee.organization_id,
          'organizationCode', employee_organization.organization_code,
          'organizationName', employee_organization.organization_name
        ) end
      ) as payload
    from public.smis_storage_location location
    join public.sys_organization organization
      on organization.tenant_id = location.tenant_id
      and organization.id = location.organization_id
    left join public.hr_employee employee
      on employee.tenant_id = location.tenant_id and employee.id = location.responsible_employee_id
    left join public.sys_organization employee_organization
      on employee_organization.tenant_id = employee.tenant_id
      and employee_organization.id = employee.organization_id
    where location.tenant_id = v_tenant_id
  ) item;

  select jsonb_build_object(
    'total', count(*),
    'enabled', count(*) filter (where status = 'enabled'),
    'rootCount', count(*) filter (where parent_id is null),
    'managedCount', count(*) filter (where responsible_employee_id is not null)
  )
  into v_overview
  from public.smis_storage_location
  where tenant_id = v_tenant_id;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'tree', v_tree,
    'overview', v_overview
  );
end;
$$;

create or replace function public.smis_save_storage_location_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_parent_id uuid := nullif(p_payload ->> 'parent_id', '')::uuid;
  v_organization_id uuid := nullif(p_payload ->> 'organization_id', '')::uuid;
  v_responsible_employee_id uuid := nullif(p_payload ->> 'responsible_employee_id', '')::uuid;
  v_location_code text := upper(btrim(coalesce(p_payload ->> 'location_code', '')));
  v_location_name text := btrim(coalesce(p_payload ->> 'location_name', ''));
  v_location_short_name text := nullif(btrim(coalesce(p_payload ->> 'location_short_name', '')), '');
  v_detail_location text := nullif(btrim(coalesce(p_payload ->> 'detail_location', '')), '');
  v_remark text := nullif(btrim(coalesce(p_payload ->> 'remark', '')), '');
  v_status text := coalesce(nullif(p_payload ->> 'status', ''), 'enabled');
  v_result_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护存放位置';
  end if;
  if p_id is null and not app_private.has_permission('SmisStorageLocation:Add') then
    raise exception '当前账号无权新增存放位置';
  end if;
  if p_id is not null and not app_private.has_permission('SmisStorageLocation:Edit') then
    raise exception '当前账号无权编辑存放位置';
  end if;

  v_tenant_id := app_private.current_user_tenant_id();
  if v_tenant_id is null then
    raise exception '当前账号未绑定有效租户';
  end if;
  if v_location_code = '' then raise exception '请输入设备位置编码'; end if;
  if v_location_code !~ '^[A-Z][A-Z0-9_\-]*$' then
    raise exception '设备位置编码须以字母开头，仅支持字母、数字、下划线和短横线';
  end if;
  if char_length(v_location_code) > 40 then raise exception '设备位置编码不能超过40个字符'; end if;
  if v_location_name = '' then raise exception '请输入位置名称'; end if;
  if char_length(v_location_name) > 100 then raise exception '位置名称不能超过100个字符'; end if;
  if char_length(coalesce(v_location_short_name, '')) > 50 then raise exception '位置简称不能超过50个字符'; end if;
  if char_length(coalesce(v_detail_location, '')) > 300 then raise exception '详细位置不能超过300个字符'; end if;
  if char_length(coalesce(v_remark, '')) > 500 then raise exception '备注不能超过500个字符'; end if;
  if v_status not in ('enabled', 'disabled') then raise exception '启用状态不合法'; end if;
  if v_organization_id is null then raise exception '请选择归属部门'; end if;

  if not exists (
    select 1 from public.sys_organization
    where id = v_organization_id and tenant_id = v_tenant_id
  ) then
    raise exception '所选归属部门不存在或不属于当前租户';
  end if;
  if v_responsible_employee_id is not null and not exists (
    select 1 from public.hr_employee
    where id = v_responsible_employee_id and tenant_id = v_tenant_id
  ) then
    raise exception '所选位置负责人不存在或不属于当前租户';
  end if;
  if v_parent_id is not null and not exists (
    select 1 from public.smis_storage_location
    where id = v_parent_id and tenant_id = v_tenant_id
  ) then
    raise exception '所选上级位置不存在或不属于当前租户';
  end if;

  if p_id is not null then
    perform 1 from public.smis_storage_location
    where id = p_id and tenant_id = v_tenant_id
    for update;
    if not found then raise exception '待编辑的存放位置不存在或无权访问'; end if;
    if v_parent_id = p_id then raise exception '上级位置不能选择当前节点'; end if;
    if v_parent_id is not null and exists (
      with recursive descendants as (
        select id from public.smis_storage_location
        where tenant_id = v_tenant_id and parent_id = p_id
        union all
        select child.id
        from public.smis_storage_location child
        join descendants parent on parent.id = child.parent_id
        where child.tenant_id = v_tenant_id
      )
      select 1 from descendants where id = v_parent_id
    ) then
      raise exception '上级位置不能选择当前节点的下级位置';
    end if;
  end if;

  if exists (
    select 1 from public.smis_storage_location
    where tenant_id = v_tenant_id
      and lower(btrim(location_code)) = lower(v_location_code)
      and (p_id is null or id <> p_id)
  ) then raise exception '设备位置编码已存在'; end if;
  if exists (
    select 1 from public.smis_storage_location
    where tenant_id = v_tenant_id
      and lower(btrim(location_name)) = lower(v_location_name)
      and (p_id is null or id <> p_id)
  ) then raise exception '位置名称已存在'; end if;

  if p_id is null then
    insert into public.smis_storage_location(
      tenant_id, parent_id, organization_id, responsible_employee_id,
      location_code, location_name, location_short_name, detail_location, remark, status
    ) values (
      v_tenant_id, v_parent_id, v_organization_id, v_responsible_employee_id,
      v_location_code, v_location_name, v_location_short_name, v_detail_location, v_remark, v_status
    ) returning id into v_result_id;
  else
    update public.smis_storage_location set
      parent_id = v_parent_id,
      organization_id = v_organization_id,
      responsible_employee_id = v_responsible_employee_id,
      location_code = v_location_code,
      location_name = v_location_name,
      location_short_name = v_location_short_name,
      detail_location = v_detail_location,
      remark = v_remark,
      status = v_status
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result_id;
  end if;

  return v_result_id;
end;
$$;

create or replace function public.smis_delete_storage_locations_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_ids uuid[];
  v_deleted integer;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再删除存放位置'; end if;
  if not app_private.has_permission('SmisStorageLocation:Delete') then
    raise exception '当前账号无权删除存放位置';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  select array_agg(distinct id) into v_ids from unnest(coalesce(p_ids, '{}'::uuid[])) id;
  if coalesce(cardinality(v_ids), 0) = 0 then raise exception '请选择要删除的存放位置'; end if;
  if (select count(*) from public.smis_storage_location where tenant_id = v_tenant_id and id = any(v_ids))
      <> cardinality(v_ids) then
    raise exception '部分存放位置不存在或无权删除';
  end if;
  if exists (
    select 1 from public.smis_storage_location
    where tenant_id = v_tenant_id
      and parent_id = any(v_ids)
      and not (id = any(v_ids))
  ) then raise exception '存在未选中的下级位置，请先删除或一并选择下级位置'; end if;

  delete from public.smis_storage_location
  where tenant_id = v_tenant_id and id = any(v_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.smis_list_storage_locations_secure(integer, integer, text, text, uuid)
  from public, anon;
revoke all on function public.smis_save_storage_location_secure(uuid, jsonb)
  from public, anon;
revoke all on function public.smis_delete_storage_locations_secure(uuid[])
  from public, anon;
grant execute on function public.smis_list_storage_locations_secure(integer, integer, text, text, uuid)
  to authenticated, service_role;
grant execute on function public.smis_save_storage_location_secure(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.smis_delete_storage_locations_secure(uuid[])
  to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), '存放位置启用状态', 'smisStorageLocationStatus', '1',
  '624944977@qq.com', '624944977@qq.com', '存放位置启停状态',
  platform_tenant.id,
  (select id from public.sys_dict_type where code = 'smisEquipmentLedger' limit 1),
  'dictionary', 2
from platform_tenant
on conflict (code) do update set
  name = excluded.name,
  status = excluded.status,
  update_by = excluded.update_by,
  update_time = now(),
  remark = excluded.remark,
  parent_id = excluded.parent_id,
  sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(value, label, sort, tag_type) as (values
  ('enabled', '启用', 1, 'success'),
  ('disabled', '停用', 2, 'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id,
  'smisStorageLocationStatus_' || items.value,
  '1', '624944977@qq.com', '624944977@qq.com', '存放位置启停状态字典项',
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type
  on dictionary_type.code = 'smisStorageLocationStatus'
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'a1530000-0000-4000-8000-000000000014'::uuid,
  seed.name, '', '',
  jsonb_build_object(
    'title', seed.title,
    'icon', '',
    'is_hide', true,
    'is_enable', true,
    'roles', jsonb_build_array()
  ), seed.sort, 'button', 'smis', '624944977@qq.com', '624944977@qq.com'
from (values
  ('a1530000-0000-4000-8140-000000000001'::uuid, 'SmisStorageLocation:View', '查看存放位置', 1),
  ('a1530000-0000-4000-8140-000000000002'::uuid, 'SmisStorageLocation:Add', '新增存放位置', 2),
  ('a1530000-0000-4000-8140-000000000003'::uuid, 'SmisStorageLocation:Edit', '编辑存放位置', 3),
  ('a1530000-0000-4000-8140-000000000004'::uuid, 'SmisStorageLocation:Delete', '删除存放位置', 4)
) seed(id, name, title, sort)
on conflict (id) do update set
  parent_id = excluded.parent_id,
  name = excluded.name,
  meta = excluded.meta,
  sort = excluded.sort,
  type = excluded.type,
  app_code = excluded.app_code,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_role_menu(
  role_id, menu_id, tenant_id, permission, create_by, update_by
)
select page_grant.role_id, button.id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_role role on role.id = page_grant.role_id
cross join (values
  ('a1530000-0000-4000-8140-000000000001'::uuid),
  ('a1530000-0000-4000-8140-000000000002'::uuid),
  ('a1530000-0000-4000-8140-000000000003'::uuid),
  ('a1530000-0000-4000-8140-000000000004'::uuid)
) button(id)
where page_grant.menu_id = 'a1530000-0000-4000-8000-000000000014'::uuid
on conflict (role_id, menu_id) do nothing;

;
