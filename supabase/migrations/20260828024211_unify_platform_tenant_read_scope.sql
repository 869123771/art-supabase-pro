create or replace function app_private.current_read_tenant_id()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_scope_text text;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再读取租户数据' using errcode = '42501';
  end if;

  if not app_private.is_platform_super() then
    return app_private.auth_user_tenant_id();
  end if;

  v_scope_text := nullif(
    btrim(
      coalesce(
        current_setting('request.headers', true)::jsonb ->> 'x-art-tenant-scope',
        ''
      )
    ),
    ''
  );

  if v_scope_text is null then
    return null;
  end if;

  return app_private.current_user_tenant_id();
end;
$$;

revoke all on function app_private.current_read_tenant_id() from public, anon;
grant execute on function app_private.current_read_tenant_id() to authenticated, service_role;

comment on function app_private.current_read_tenant_id() is
  'Returns NULL only for the platform-super aggregate scope; otherwise returns the validated selected or authenticated tenant.';

do $$
declare
  v_function record;
  v_definition text;
  v_changed integer := 0;
begin
  for v_function in
    select
      procedure.oid,
      pg_get_functiondef(procedure.oid) as definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prosecdef
      and procedure.proname ~ '^(smis|hr|tms|fms|vms)_(list|search|get|overview|stats|summary|options|tree|report|dashboard)'
      and pg_get_functiondef(procedure.oid) ilike '%current_user_tenant_id%'
      and pg_get_functiondef(procedure.oid) !~* '\m(insert|update|delete|merge|truncate)\M'
  loop
    v_definition := regexp_replace(
      v_function.definition,
      '(([a-zA-Z_][a-zA-Z0-9_]*\.)?tenant_id)\s*=\s*(v_tenant_id|v_tenant|v_current_tenant_id|v_current_tenant)',
      '(app_private.current_read_tenant_id() is null or \1 = app_private.current_read_tenant_id())',
      'gi'
    );
    v_definition := regexp_replace(
      v_definition,
      '(v_tenant_id|v_tenant|v_current_tenant_id|v_current_tenant)\s*=\s*(([a-zA-Z_][a-zA-Z0-9_]*\.)?tenant_id)',
      '(app_private.current_read_tenant_id() is null or \2 = app_private.current_read_tenant_id())',
      'gi'
    );
    v_definition := regexp_replace(
      v_definition,
      '(([a-zA-Z_][a-zA-Z0-9_]*\.)?tenant_id)\s*=\s*app_private\.current_user_tenant_id\(\)',
      '(app_private.current_read_tenant_id() is null or \1 = app_private.current_read_tenant_id())',
      'gi'
    );

    if v_definition <> v_function.definition then
      execute v_definition;
      v_changed := v_changed + 1;
    end if;
  end loop;

  if v_changed = 0 then
    raise exception 'No tenant-scoped business read RPC was updated';
  end if;
end;
$$;

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
  v_read_tenant_id uuid := app_private.current_read_tenant_id();
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
  if p_status is not null and p_status not in ('enabled', 'disabled') then
    raise exception '启用状态不合法';
  end if;
  if p_ancestor_id is not null and not exists (
    select 1
    from public.smis_storage_location location
    where location.id = p_ancestor_id
      and (v_read_tenant_id is null or location.tenant_id = v_read_tenant_id)
  ) then
    raise exception '所选存放位置不存在或不属于当前查看范围';
  end if;

  with recursive scope_ids as (
    select location.id, location.tenant_id
    from public.smis_storage_location location
    where location.id = p_ancestor_id
      and (v_read_tenant_id is null or location.tenant_id = v_read_tenant_id)
    union all
    select child.id, child.tenant_id
    from public.smis_storage_location child
    join scope_ids parent
      on parent.id = child.parent_id
      and parent.tenant_id = child.tenant_id
  ), filtered as (
    select location.id
    from public.smis_storage_location location
    where (v_read_tenant_id is null or location.tenant_id = v_read_tenant_id)
      and (p_status is null or location.status = p_status)
      and (
        v_keyword is null
        or location.location_code ilike '%' || v_keyword || '%'
        or location.location_name ilike '%' || v_keyword || '%'
        or coalesce(location.location_short_name, '') ilike '%' || v_keyword || '%'
        or coalesce(location.detail_location, '') ilike '%' || v_keyword || '%'
        or coalesce(location.remark, '') ilike '%' || v_keyword || '%'
      )
      and (p_ancestor_id is null or location.id in (select scope_ids.id from scope_ids))
  )
  select count(*) into v_total from filtered;

  with recursive scope_ids as (
    select location.id, location.tenant_id
    from public.smis_storage_location location
    where location.id = p_ancestor_id
      and (v_read_tenant_id is null or location.tenant_id = v_read_tenant_id)
    union all
    select child.id, child.tenant_id
    from public.smis_storage_location child
    join scope_ids parent
      on parent.id = child.parent_id
      and parent.tenant_id = child.tenant_id
  )
  select coalesce(jsonb_agg(item.payload order by item.tenant_name, item.location_name), '[]'::jsonb)
  into v_records
  from (
    select tenant.tenant_name, location.location_name,
      jsonb_build_object(
        'id', location.id,
        'tenantId', location.tenant_id,
        'tenant', jsonb_build_object('id', tenant.id, 'tenantName', tenant.tenant_name),
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
          select count(*)
          from public.smis_storage_location child
          where child.tenant_id = location.tenant_id and child.parent_id = location.id
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
    join public.sys_tenant tenant on tenant.id = location.tenant_id
    join public.sys_organization organization
      on organization.tenant_id = location.tenant_id and organization.id = location.organization_id
    left join public.smis_storage_location parent
      on parent.tenant_id = location.tenant_id and parent.id = location.parent_id
    left join public.hr_employee employee
      on employee.tenant_id = location.tenant_id and employee.id = location.responsible_employee_id
    left join public.sys_organization employee_organization
      on employee_organization.tenant_id = employee.tenant_id
      and employee_organization.id = employee.organization_id
    where (v_read_tenant_id is null or location.tenant_id = v_read_tenant_id)
      and (p_status is null or location.status = p_status)
      and (
        v_keyword is null
        or location.location_code ilike '%' || v_keyword || '%'
        or location.location_name ilike '%' || v_keyword || '%'
        or coalesce(location.location_short_name, '') ilike '%' || v_keyword || '%'
        or coalesce(location.detail_location, '') ilike '%' || v_keyword || '%'
        or coalesce(location.remark, '') ilike '%' || v_keyword || '%'
      )
      and (p_ancestor_id is null or location.id in (select scope_ids.id from scope_ids))
    order by tenant.tenant_name, location.location_name, location.id
    offset v_from limit v_limit
  ) item;

  select coalesce(jsonb_agg(item.payload order by item.tenant_name, item.location_name), '[]'::jsonb)
  into v_tree
  from (
    select tenant.tenant_name, location.location_name,
      jsonb_build_object(
        'id', location.id,
        'tenantId', location.tenant_id,
        'tenant', jsonb_build_object('id', tenant.id, 'tenantName', tenant.tenant_name),
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
          select count(*)
          from public.smis_storage_location child
          where child.tenant_id = location.tenant_id and child.parent_id = location.id
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
    join public.sys_tenant tenant on tenant.id = location.tenant_id
    join public.sys_organization organization
      on organization.tenant_id = location.tenant_id and organization.id = location.organization_id
    left join public.hr_employee employee
      on employee.tenant_id = location.tenant_id and employee.id = location.responsible_employee_id
    left join public.sys_organization employee_organization
      on employee_organization.tenant_id = employee.tenant_id
      and employee_organization.id = employee.organization_id
    where v_read_tenant_id is null or location.tenant_id = v_read_tenant_id
  ) item;

  select jsonb_build_object(
    'total', count(*),
    'enabled', count(*) filter (where location.status = 'enabled'),
    'rootCount', count(*) filter (where location.parent_id is null),
    'managedCount', count(*) filter (where location.responsible_employee_id is not null)
  )
  into v_overview
  from public.smis_storage_location location
  where v_read_tenant_id is null or location.tenant_id = v_read_tenant_id;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'tree', v_tree,
    'overview', v_overview
  );
end;
$$;

create or replace function public.smis_save_storage_location_secure(p_id uuid, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_tenant_id uuid := app_private.auth_user_tenant_id();
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
  if (select auth.uid()) is null then raise exception '请先登录后再维护存放位置'; end if;
  if p_id is null and not app_private.has_permission('SmisStorageLocation:Add') then
    raise exception '当前账号无权新增存放位置';
  end if;
  if p_id is not null and not app_private.has_permission('SmisStorageLocation:Edit') then
    raise exception '当前账号无权编辑存放位置';
  end if;
  if v_actor_tenant_id is null then raise exception '当前账号未绑定有效租户'; end if;

  if p_id is null then
    v_tenant_id := v_actor_tenant_id;
  else
    select location.tenant_id into v_tenant_id
    from public.smis_storage_location location
    where location.id = p_id
      and (app_private.is_platform_super() or location.tenant_id = v_actor_tenant_id)
    for update;
    if not found then raise exception '待编辑的存放位置不存在或无权访问'; end if;
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
  ) then raise exception '所选归属部门不存在或不属于记录租户'; end if;
  if v_responsible_employee_id is not null and not exists (
    select 1 from public.hr_employee
    where id = v_responsible_employee_id and tenant_id = v_tenant_id
  ) then raise exception '所选位置负责人不存在或不属于记录租户'; end if;
  if v_parent_id is not null and not exists (
    select 1 from public.smis_storage_location
    where id = v_parent_id and tenant_id = v_tenant_id
  ) then raise exception '所选上级位置不存在或不属于记录租户'; end if;

  if p_id is not null then
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
    ) then raise exception '上级位置不能选择当前节点的下级位置'; end if;
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
  v_actor_tenant_id uuid := app_private.auth_user_tenant_id();
  v_ids uuid[];
  v_deleted integer;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再删除存放位置'; end if;
  if not app_private.has_permission('SmisStorageLocation:Delete') then
    raise exception '当前账号无权删除存放位置';
  end if;
  if v_actor_tenant_id is null then raise exception '当前账号未绑定有效租户'; end if;

  select array_agg(distinct id) into v_ids from unnest(coalesce(p_ids, '{}'::uuid[])) id;
  if coalesce(cardinality(v_ids), 0) = 0 then raise exception '请选择要删除的存放位置'; end if;
  if (
    select count(*)
    from public.smis_storage_location location
    where location.id = any(v_ids)
      and (app_private.is_platform_super() or location.tenant_id = v_actor_tenant_id)
  ) <> cardinality(v_ids) then
    raise exception '部分存放位置不存在或无权删除';
  end if;
  if exists (
    select 1
    from public.smis_storage_location child
    join public.smis_storage_location parent
      on parent.id = any(v_ids)
      and parent.id = child.parent_id
      and parent.tenant_id = child.tenant_id
    where not (child.id = any(v_ids))
  ) then raise exception '存在未选中的下级位置，请先删除或一并选择下级位置'; end if;

  delete from public.smis_storage_location location
  where location.id = any(v_ids)
    and (app_private.is_platform_super() or location.tenant_id = v_actor_tenant_id);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.smis_list_storage_locations_secure(integer, integer, text, text, uuid) from public, anon;
revoke all on function public.smis_save_storage_location_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_storage_locations_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_storage_locations_secure(integer, integer, text, text, uuid) to authenticated, service_role;
grant execute on function public.smis_save_storage_location_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.smis_delete_storage_locations_secure(uuid[]) to authenticated, service_role;

;
