begin;

alter table public.smis_qualification_catalog
  drop constraint if exists smis_qualification_catalog_type_check;
alter table public.smis_qualification_catalog
  add constraint smis_qualification_catalog_type_check
  check (
    catalog_type = any(array[
      'work_item'::text,
      'work_category'::text,
      'permitted_operation_item'::text,
      'certificate_term'::text
    ])
  );

with target_tenant as (
  select id
  from public.sys_tenant
  where tenant_code = 'public-register'
  union
  select distinct assignment.tenant_id
  from public.sys_role_menu assignment
  join public.sys_menu page on page.id = assignment.menu_id
  where page.name = 'SmisSafetyManagerCertificate'
  union
  select distinct certificate.tenant_id
  from public.smis_personnel_certificate certificate
  where certificate.certificate_category = 'safety_manager'
)
insert into public.smis_qualification_catalog (
  tenant_id,
  catalog_type,
  parent_id,
  work_category_id,
  item_code,
  item_name,
  sort,
  status,
  remark,
  create_by,
  update_by
)
select
  tenant.id,
  'certificate_term',
  null,
  null,
  'SAFETY_MANAGER',
  '安全管理人员证有效期',
  10,
  'enabled',
  '安全管理人员证日期、提醒和复审记录的内部关联项，不在基础数据菜单维护。',
  '624944977@qq.com',
  '624944977@qq.com'
from target_tenant tenant
where not exists (
  select 1
  from public.smis_qualification_catalog existing
  where existing.tenant_id = tenant.id
    and existing.catalog_type = 'certificate_term'
    and existing.item_code = 'SAFETY_MANAGER'
);

with dictionary_parent as (
  select tenant_id, parent_id
  from public.sys_dict_type
  where code = 'smisCertificateCategory'
)
insert into public.sys_dict_type (
  id,
  name,
  code,
  status,
  create_by,
  create_time,
  update_by,
  update_time,
  remark,
  tenant_id,
  parent_id,
  node_type,
  sort
)
select
  gen_random_uuid(),
  dictionary.name,
  dictionary.code,
  '1',
  '624944977@qq.com',
  now(),
  '624944977@qq.com',
  now(),
  dictionary.remark,
  parent.tenant_id,
  parent.parent_id,
  'dictionary',
  dictionary.sort
from dictionary_parent parent
cross join (
  values
    (
      '安全管理人员证单位类型',
      'smisSafetyManagerUnitType',
      '安全管理人员证适用的单位行业类型。',
      85
    ),
    (
      '安全管理人员证职业类型',
      'smisSafetyManagerOccupationType',
      '安全管理人员证持证人的职业身份。',
      86
    )
) dictionary(name, code, remark, sort)
where not exists (
  select 1 from public.sys_dict_type existing where existing.code = dictionary.code
);

with dictionary_value(dict_code, value, label, sort) as (
  values
    ('smisSafetyManagerUnitType', 'metallurgical', '冶金企业', 1),
    ('smisSafetyManagerUnitType', 'hazardous_chemical', '危险化学品企业', 2),
    ('smisSafetyManagerUnitType', 'non_coal_mine', '非煤矿山企业', 3),
    ('smisSafetyManagerUnitType', 'other', '其他企业', 4),
    (
      'smisSafetyManagerOccupationType',
      'safety_production_manager',
      '安全生产管理人员',
      1
    ),
    ('smisSafetyManagerOccupationType', 'principal', '主要负责人', 2)
)
insert into public.sys_dictionary (
  id,
  type_id,
  code,
  status,
  create_by,
  create_time,
  update_by,
  update_time,
  value,
  label,
  sort,
  tenant_id,
  tag_type
)
select
  gen_random_uuid(),
  type.id,
  value.dict_code || '_' || value.value,
  '1',
  '624944977@qq.com',
  now(),
  '624944977@qq.com',
  now(),
  value.value,
  value.label,
  value.sort,
  type.tenant_id,
  null
from dictionary_value value
join public.sys_dict_type type on type.code = value.dict_code
where not exists (
  select 1
  from public.sys_dictionary existing
  where existing.type_id = type.id
    and existing.value = value.value
);

update public.sys_menu
set meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object(
      'title', '安全管理人员证',
      'is_hide', false,
      'is_enable', true
    ),
    update_by = '624944977@qq.com',
    update_time = now()
where name = 'SmisSafetyManagerCertificate';

with button_seed(page_name, action, title, sort) as (
  values
    ('SmisSpecialOperationCertificate', 'View', '查看特种作业操作证', 1),
    ('SmisSpecialOperationCertificate', 'Add', '新增特种作业操作证', 2),
    ('SmisSpecialOperationCertificate', 'Copy', '复制并新增', 3),
    ('SmisSpecialOperationCertificate', 'Edit', '编辑特种作业操作证', 4),
    ('SmisSpecialOperationCertificate', 'Delete', '删除特种作业操作证', 5),
    ('SmisSpecialOperationCertificate', 'Export', '导出特种作业操作证', 6),
    ('SmisSpecialOperationCertificate', 'ViewHistory', '查看特种作业复审记录', 7),
    ('SmisSafetyManagerCertificate', 'View', '查看安全管理人员证', 1),
    ('SmisSafetyManagerCertificate', 'Add', '新增安全管理人员证', 2),
    ('SmisSafetyManagerCertificate', 'Copy', '复制并新增', 3),
    ('SmisSafetyManagerCertificate', 'Edit', '编辑安全管理人员证', 4),
    ('SmisSafetyManagerCertificate', 'Delete', '删除安全管理人员证', 5),
    ('SmisSafetyManagerCertificate', 'Export', '导出安全管理人员证', 6),
    ('SmisSafetyManagerCertificate', 'ViewHistory', '查看安全管理人员证复审记录', 7)
)
insert into public.sys_menu (
  id,
  parent_id,
  name,
  path,
  component,
  meta,
  sort,
  create_by,
  create_time,
  update_by,
  update_time,
  type,
  app_code
)
select
  gen_random_uuid(),
  page.id,
  seed.page_name || ':' || seed.action,
  '',
  null,
  jsonb_build_object(
    'icon', '',
    'roles', jsonb_build_array(),
    'title', seed.title,
    'is_hide', true,
    'is_enable', true
  ),
  seed.sort,
  '624944977@qq.com',
  now(),
  '624944977@qq.com',
  now(),
  'button',
  page.app_code
from button_seed seed
join public.sys_menu page on page.name = seed.page_name
where not exists (
  select 1
  from public.sys_menu existing
  where existing.parent_id = page.id
    and existing.name = seed.page_name || ':' || seed.action
);

insert into public.sys_role_menu (
  id,
  role_id,
  menu_id,
  tenant_id,
  permission,
  create_by,
  create_time,
  update_by,
  update_time
)
select
  gen_random_uuid(),
  page_assignment.role_id,
  button.id,
  page_assignment.tenant_id,
  '{}'::jsonb,
  '624944977@qq.com',
  now(),
  '624944977@qq.com',
  now()
from public.sys_role_menu page_assignment
join public.sys_menu page
  on page.id = page_assignment.menu_id
 and page.name in ('SmisSpecialOperationCertificate', 'SmisSafetyManagerCertificate')
join public.sys_menu button
  on button.parent_id = page.id
 and button.type = 'button'
where not exists (
  select 1
  from public.sys_role_menu existing
  where existing.role_id = page_assignment.role_id
    and existing.menu_id = button.id
);

create or replace function app_private.smis_certificate_permission_prefix(p_category text)
returns text
language sql
immutable
set search_path = ''
as $function$
  select case p_category
    when 'special_equipment_operator'
      then 'SmisSpecialEquipmentOperatorCertificateLedger'
    when 'special_operation'
      then 'SmisSpecialOperationCertificate'
    when 'safety_manager'
      then 'SmisSafetyManagerCertificate'
    else 'SmisPersonnelCertificateLedger'
  end;
$function$;

revoke all on function app_private.smis_certificate_permission_prefix(text) from public;

create or replace function app_private.smis_has_certificate_permission(
  p_category text,
  p_action text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select app_private.is_platform_super()
    or app_private.has_permission(
      app_private.smis_certificate_permission_prefix(p_category) || ':' || p_action
    );
$function$;

revoke all on function app_private.smis_has_certificate_permission(text, text)
  from public, anon, authenticated;

create or replace function public.smis_list_certificate_employees_secure(
  p_certificate_category text,
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid := app_private.current_read_tenant_id();
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再选择持证人员' using errcode = '42501';
  end if;

  if app_private.smis_certificate_permission_prefix(p_certificate_category)
     = 'SmisPersonnelCertificateLedger'
     and p_certificate_category not in (
       'special_equipment_personnel',
       'registered_safety_engineer'
     ) then
    raise exception '证件类别无效' using errcode = '22023';
  end if;

  if not (
    app_private.smis_has_certificate_permission(p_certificate_category, 'Add')
    or app_private.smis_has_certificate_permission(p_certificate_category, 'Edit')
  ) then
    raise exception '当前账号没有维护此类人员证件的权限' using errcode = '42501';
  end if;

  return (
    with filtered as materialized (
      select
        employee.id,
        employee.tenant_id,
        employee.organization_id,
        employee.employee_no,
        employee.employee_name,
        employee.avatar_url,
        employee.job_title,
        employee.employment_status,
        employee.gender,
        employee.phone,
        employee.email,
        employee.id_card_no,
        employee.education_level,
        organization.organization_code,
        organization.organization_name
      from public.hr_employee employee
      left join public.sys_organization organization
        on organization.id = employee.organization_id
       and organization.tenant_id = employee.tenant_id
      where employee.tenant_id = v_tenant
        and employee.employment_status in ('probation', 'active')
        and (
          v_keyword is null
          or employee.employee_no ilike '%' || v_keyword || '%'
          or employee.employee_name ilike '%' || v_keyword || '%'
          or employee.job_title ilike '%' || v_keyword || '%'
          or organization.organization_name ilike '%' || v_keyword || '%'
        )
    ), paged as (
      select *
      from filtered
      order by employee_name, employee_no, id
      offset v_from
      limit v_to - v_from + 1
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          jsonb_strip_nulls(jsonb_build_object(
            'id', employee.id,
            'tenantId', employee.tenant_id,
            'organizationId', employee.organization_id,
            'employeeNo', employee.employee_no,
            'employeeName', employee.employee_name,
            'avatarUrl', employee.avatar_url,
            'jobTitle', employee.job_title,
            'employmentStatus', employee.employment_status,
            'gender', employee.gender,
            'phone', employee.phone,
            'email', employee.email,
            'idCardNo', case
              when p_certificate_category = 'safety_manager' then employee.id_card_no
              else null
            end,
            'educationLevel', case
              when p_certificate_category = 'safety_manager' then employee.education_level
              else null
            end,
            'organization', case
              when employee.organization_id is null then null
              else jsonb_build_object(
                'id', employee.organization_id,
                'organizationCode', employee.organization_code,
                'organizationName', employee.organization_name
              )
            end
          ))
          order by employee.employee_name, employee.employee_no, employee.id
        )
        from paged employee
      ), '[]'::jsonb),
      'total', (select count(*) from filtered)
    )
  );
end;
$function$;

create or replace function public.smis_get_certificate_employee_secure(
  p_certificate_category text,
  p_employee_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看持证人员信息' using errcode = '42501';
  end if;

  if not (
    app_private.smis_has_certificate_permission(p_certificate_category, 'Add')
    or app_private.smis_has_certificate_permission(p_certificate_category, 'Edit')
  ) then
    raise exception '当前账号没有维护此类人员证件的权限' using errcode = '42501';
  end if;

  select jsonb_strip_nulls(jsonb_build_object(
    'id', employee.id,
    'tenantId', employee.tenant_id,
    'organizationId', employee.organization_id,
    'employeeNo', employee.employee_no,
    'employeeName', employee.employee_name,
    'avatarUrl', employee.avatar_url,
    'jobTitle', employee.job_title,
    'employmentStatus', employee.employment_status,
    'gender', employee.gender,
    'phone', employee.phone,
    'email', employee.email,
    'idCardNo', case
      when p_certificate_category = 'safety_manager' then employee.id_card_no
      else null
    end,
    'educationLevel', case
      when p_certificate_category = 'safety_manager' then employee.education_level
      else null
    end,
    'organization', case
      when organization.id is null then null
      else jsonb_build_object(
        'id', organization.id,
        'organizationCode', organization.organization_code,
        'organizationName', organization.organization_name
      )
    end
  ))
  into v_result
  from public.hr_employee employee
  left join public.sys_organization organization
    on organization.id = employee.organization_id
   and organization.tenant_id = employee.tenant_id
  where employee.id = p_employee_id
    and employee.tenant_id = app_private.current_read_tenant_id();

  if v_result is null then
    raise exception '员工不存在或不属于当前租户' using errcode = 'P0002';
  end if;
  return v_result;
end;
$function$;

create or replace function public.smis_list_certificate_catalog_options_secure(
  p_certificate_category text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_catalog_type text := case p_certificate_category
    when 'special_equipment_personnel' then 'work_item'
    when 'special_equipment_operator' then 'work_item'
    when 'special_operation' then 'permitted_operation_item'
    when 'safety_manager' then 'certificate_term'
    when 'registered_safety_engineer' then 'work_category'
    else null
  end;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看证件项目选项' using errcode = '42501';
  end if;
  if v_catalog_type is null then
    raise exception '证件类别无效' using errcode = '22023';
  end if;
  if not (
    app_private.smis_has_certificate_permission(p_certificate_category, 'View')
    or app_private.smis_has_certificate_permission(p_certificate_category, 'Add')
    or app_private.smis_has_certificate_permission(p_certificate_category, 'Edit')
  ) then
    raise exception '当前账号没有查看此类证件项目的权限' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'records',
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', catalog.id,
          'tenantId', catalog.tenant_id,
          'parentId', catalog.parent_id,
          'workCategoryId', catalog.work_category_id,
          'workCategoryName', category.item_name,
          'workCategoryStatus', category.status,
          'catalogType', catalog.catalog_type,
          'itemCode', catalog.item_code,
          'itemName', catalog.item_name,
          'sort', catalog.sort,
          'status', catalog.status,
          'remark', catalog.remark,
          'childCount', 0
        )
        order by catalog.catalog_type, catalog.sort, catalog.item_name
      )
      from public.smis_qualification_catalog catalog
      left join public.smis_qualification_catalog category
        on category.id = catalog.work_category_id
       and category.tenant_id = catalog.tenant_id
       and category.catalog_type = 'work_category'
      where catalog.tenant_id = app_private.current_read_tenant_id()
        and (
          catalog.catalog_type = v_catalog_type
          or (
            p_certificate_category = 'special_operation'
            and catalog.catalog_type = 'work_category'
          )
        )
        and (
          p_certificate_category <> 'special_equipment_personnel'
          or left(upper(btrim(catalog.item_code)), 1) = 'A'
        )
        and (
          p_certificate_category <> 'special_equipment_operator'
          or left(upper(btrim(catalog.item_code)), 1)
            = any(array['G', 'R', 'D', 'T', 'Q', 'N', 'F']::text[])
        )
        and (
          p_certificate_category <> 'safety_manager'
          or catalog.item_code = 'SAFETY_MANAGER'
        )
    ), '[]'::jsonb)
  );
end;
$function$;

revoke all on function public.smis_list_certificate_employees_secure(
  text, integer, integer, text
) from public, anon;
revoke all on function public.smis_get_certificate_employee_secure(text, uuid)
  from public, anon;
revoke all on function public.smis_list_certificate_catalog_options_secure(text)
  from public, anon;
grant execute on function public.smis_list_certificate_employees_secure(
  text, integer, integer, text
) to authenticated, service_role;
grant execute on function public.smis_get_certificate_employee_secure(text, uuid)
  to authenticated, service_role;
grant execute on function public.smis_list_certificate_catalog_options_secure(text)
  to authenticated, service_role;

create or replace function public.smis_save_personnel_certificate_secure(
  p_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid;
  v_employee uuid;
  v_category text := p_payload->>'certificate_category';
  v_catalog_type text;
  v_permission_prefix text;
  v_number text := btrim(coalesce(p_payload->>'certificate_number', ''));
  v_extra jsonb := coalesce(p_payload->'extra_fields', '{}'::jsonb);
  v_items jsonb := coalesce(p_payload->'items', '[]'::jsonb);
  v_result uuid;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再维护人员证件台账' using errcode = '42501';
  end if;

  v_catalog_type := case v_category
    when 'special_equipment_personnel' then 'work_item'
    when 'special_equipment_operator' then 'work_item'
    when 'special_operation' then 'permitted_operation_item'
    when 'safety_manager' then 'certificate_term'
    when 'registered_safety_engineer' then 'work_category'
    else null
  end;

  if v_catalog_type is null then
    raise exception '证件类别无效' using errcode = '22023';
  end if;

  v_permission_prefix := app_private.smis_certificate_permission_prefix(v_category);
  if not app_private.has_permission(
    v_permission_prefix || case when p_id is null then ':Add' else ':Edit' end
  ) then
    raise exception '当前账号没有维护此类人员证件台账的权限' using errcode = '42501';
  end if;

  v_tenant := app_private.resolve_mutation_tenant_id(
    (select tenant_id from public.smis_personnel_certificate where id = p_id)
  );

  if p_id is not null and exists (
    select 1
    from public.smis_personnel_certificate existing
    where existing.id = p_id
      and existing.tenant_id = v_tenant
      and existing.certificate_category <> v_category
  ) then
    raise exception '证件类别创建后不能修改' using errcode = '22023';
  end if;

  begin
    v_employee := (p_payload->>'employee_id')::uuid;
  exception
    when invalid_text_representation then
      raise exception '请选择员工' using errcode = '22023';
  end;

  if not exists (
    select 1
    from public.hr_employee employee
    where employee.id = v_employee
      and employee.tenant_id = v_tenant
  ) then
    raise exception '所选员工不存在或不属于当前租户' using errcode = 'P0002';
  end if;

  if v_number = '' or char_length(v_number) > 100 then
    raise exception '请输入不超过 100 个字符的证件编号' using errcode = '22023';
  end if;

  if coalesce(p_payload->>'warning_status', 'normal') not in ('normal', 'warning') then
    raise exception '预警状态无效' using errcode = '22023';
  end if;

  if jsonb_typeof(v_extra) <> 'object' then
    raise exception '证件类别特有信息格式无效' using errcode = '22023';
  end if;

  if v_category = 'safety_manager' then
    if coalesce(v_extra->>'unit_type', '') not in (
      'metallurgical',
      'hazardous_chemical',
      'non_coal_mine',
      'other'
    ) then
      raise exception '请选择有效的单位类型' using errcode = '22023';
    end if;
    if coalesce(v_extra->>'occupation_type', '') not in (
      'safety_production_manager',
      'principal'
    ) then
      raise exception '请选择有效的职业类型' using errcode = '22023';
    end if;
    if v_extra - 'unit_type' - 'occupation_type' <> '{}'::jsonb then
      raise exception '安全管理人员证包含不支持的类别字段' using errcode = '22023';
    end if;
  end if;

  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    raise exception '请至少维护一条证件有效期或作业项目' using errcode = '22023';
  end if;

  if v_category = 'safety_manager' and jsonb_array_length(v_items) <> 1 then
    raise exception '安全管理人员证只能维护一条当前有效期' using errcode = '22023';
  end if;

  if p_id is null and exists (
    select 1
    from jsonb_array_elements(v_items) item
    where nullif(item->>'id', '') is not null
  ) then
    raise exception '新增证件不能引用已有作业项目' using errcode = '22023';
  end if;

  if p_id is null and exists (
    select 1
    from jsonb_array_elements(v_items) item
    where nullif(item->>'dismissal_reason', '') is not null
  ) then
    raise exception '新增证件时不能填写消除提醒原因' using errcode = '22023';
  end if;

  if p_id is not null and exists (
    select 1
    from jsonb_array_elements(v_items) item
    where nullif(item->>'id', '') is not null
      and not exists (
        select 1
        from public.smis_personnel_certificate_item existing
        where existing.id = (item->>'id')::uuid
          and existing.certificate_id = p_id
          and existing.tenant_id = v_tenant
      )
  ) then
    raise exception '证件明细不属于当前证件' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_items) item
    left join public.smis_qualification_catalog catalog
      on catalog.id = (item->>'catalog_id')::uuid
     and catalog.tenant_id = v_tenant
    where catalog.id is null
       or catalog.catalog_type <> v_catalog_type
  ) then
    raise exception '所选项目与证件类别不匹配' using errcode = '22023';
  end if;

  if v_category = 'safety_manager' and exists (
    select 1
    from jsonb_array_elements(v_items) item
    join public.smis_qualification_catalog catalog
      on catalog.id = (item->>'catalog_id')::uuid
     and catalog.tenant_id = v_tenant
    where catalog.item_code <> 'SAFETY_MANAGER'
  ) then
    raise exception '安全管理人员证有效期关联项无效' using errcode = '22023';
  end if;

  if v_category = 'special_equipment_personnel' and exists (
    select 1
    from jsonb_array_elements(v_items) item
    join public.smis_qualification_catalog catalog
      on catalog.id = (item->>'catalog_id')::uuid
     and catalog.tenant_id = v_tenant
    where left(upper(btrim(catalog.item_code)), 1) <> 'A'
  ) then
    raise exception '特种设备安全管理人员证只能选择 A 类作业项目' using errcode = '22023';
  end if;

  if v_category = 'special_equipment_operator' and exists (
    select 1
    from jsonb_array_elements(v_items) item
    join public.smis_qualification_catalog catalog
      on catalog.id = (item->>'catalog_id')::uuid
     and catalog.tenant_id = v_tenant
    where not (
      left(upper(btrim(catalog.item_code)), 1)
      = any(array['G', 'R', 'D', 'T', 'Q', 'N', 'F']::text[])
    )
  ) then
    raise exception '特种设备作业人员证只能选择 G、R、D、T、Q、N、F 类作业项目'
      using errcode = '22023';
  end if;

  if v_category = 'special_operation' and exists (
    select 1
    from jsonb_array_elements(v_items) item
    join public.smis_qualification_catalog catalog
      on catalog.id = (item->>'catalog_id')::uuid
     and catalog.tenant_id = v_tenant
    left join public.smis_qualification_catalog category
      on category.id = catalog.work_category_id
     and category.tenant_id = catalog.tenant_id
     and category.catalog_type = 'work_category'
    where category.id is null or category.status <> 'enabled'
  ) then
    raise exception '准操项目必须属于已启用的作业类别' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_items) item
    join public.smis_qualification_catalog catalog
      on catalog.id = (item->>'catalog_id')::uuid
     and catalog.tenant_id = v_tenant
    where catalog.status <> 'enabled'
      and not exists (
        select 1
        from public.smis_personnel_certificate_item existing
        where existing.certificate_id = p_id
          and existing.catalog_id = catalog.id
          and existing.tenant_id = v_tenant
      )
  ) then
    raise exception '已停用的项目不能新增到证件' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_personnel_certificate (
      tenant_id,
      employee_id,
      certificate_category,
      certificate_number,
      issuing_authority,
      archive_number,
      certificate_photo_url,
      warning_status,
      extra_fields,
      remark
    ) values (
      v_tenant,
      v_employee,
      v_category,
      v_number,
      nullif(btrim(p_payload->>'issuing_authority'), ''),
      nullif(btrim(p_payload->>'archive_number'), ''),
      nullif(btrim(p_payload->>'certificate_photo_url'), ''),
      coalesce(nullif(p_payload->>'warning_status', ''), 'normal'),
      v_extra,
      nullif(btrim(p_payload->>'remark'), '')
    )
    returning id into v_result;
  else
    update public.smis_personnel_certificate
    set employee_id = v_employee,
        certificate_number = v_number,
        issuing_authority = nullif(btrim(p_payload->>'issuing_authority'), ''),
        archive_number = nullif(btrim(p_payload->>'archive_number'), ''),
        certificate_photo_url = nullif(btrim(p_payload->>'certificate_photo_url'), ''),
        warning_status = coalesce(nullif(p_payload->>'warning_status', ''), 'normal'),
        extra_fields = v_extra,
        remark = nullif(btrim(p_payload->>'remark'), '')
    where id = p_id
      and tenant_id = v_tenant
    returning id into v_result;

    if v_result is null then
      raise exception '证件不存在或已删除' using errcode = 'P0002';
    end if;
  end if;

  if exists (
    select 1
    from public.smis_personnel_certificate_item existing
    where existing.certificate_id = v_result
      and not exists (
        select 1
        from jsonb_array_elements(v_items) item
        where nullif(item->>'id', '')::uuid = existing.id
      )
      and exists (
        select 1
        from public.smis_personnel_certificate_review_history history
        where history.certificate_item_id = existing.id
      )
  ) then
    raise exception '已有复审记录的证件项目不能移除' using errcode = '22023';
  end if;

  delete from public.smis_personnel_certificate_item existing
  where existing.certificate_id = v_result
    and not exists (
      select 1
      from jsonb_array_elements(v_items) item
      where nullif(item->>'id', '')::uuid = existing.id
    );

  insert into public.smis_personnel_certificate_item (
    id,
    tenant_id,
    certificate_id,
    catalog_id,
    approval_date,
    effective_date,
    reminder_days,
    dismissal_reason,
    sort
  )
  select
    coalesce(nullif(item.value->>'id', '')::uuid, gen_random_uuid()),
    v_tenant,
    v_result,
    (item.value->>'catalog_id')::uuid,
    (item.value->>'approval_date')::date,
    (item.value->>'effective_date')::date,
    coalesce(nullif(item.value->>'reminder_days', '')::integer, 30),
    nullif(item.value->>'dismissal_reason', ''),
    (item.ordinality - 1) * 10
  from jsonb_array_elements(v_items) with ordinality item(value, ordinality)
  on conflict (id) do update
  set catalog_id = excluded.catalog_id,
      approval_date = excluded.approval_date,
      effective_date = excluded.effective_date,
      reminder_days = excluded.reminder_days,
      dismissal_reason = excluded.dismissal_reason,
      sort = excluded.sort
  where public.smis_personnel_certificate_item.certificate_id = v_result
    and public.smis_personnel_certificate_item.tenant_id = v_tenant;

  return v_result;
exception
  when unique_violation then
    raise exception '同类别证件编号或作业项目已存在' using errcode = '23505';
  when foreign_key_violation then
    raise exception '所选项目不存在、已删除或不属于当前租户' using errcode = '23503';
  when invalid_text_representation or datetime_field_overflow then
    raise exception '证件项目或日期格式无效' using errcode = '22023';
end;
$function$;

revoke all on function public.smis_save_personnel_certificate_secure(uuid, jsonb)
  from public, anon;
grant execute on function public.smis_save_personnel_certificate_secure(uuid, jsonb)
  to authenticated, service_role;

create or replace function public.smis_list_personnel_certificates_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_employee_name text default null,
  p_certificate_number text default null,
  p_certificate_category text default null,
  p_start_date date default null,
  p_end_date date default null,
  p_warning_status text default null,
  p_purpose text default 'list'
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_payload jsonb;
  v_records jsonb;
  v_permission_prefix text := app_private.smis_certificate_permission_prefix(
    p_certificate_category
  );
begin
  v_payload := public.smis_list_personnel_certificates_raw_secure(
    p_from,
    p_to,
    p_employee_name,
    p_certificate_number,
    p_certificate_category,
    p_start_date,
    p_end_date,
    p_warning_status,
    p_purpose
  );

  select coalesce(jsonb_agg(
    certificate_row
    || case
      when certificate_row->>'certificateCategory' = 'safety_manager' then
        jsonb_strip_nulls(jsonb_build_object(
          'idCardNo', employee.id_card_no,
          'educationLevel', employee.education_level
        ))
      else '{}'::jsonb
    end
    || jsonb_build_object(
      'items',
      coalesce((
        select jsonb_agg(
          item_row
          || jsonb_strip_nulls(jsonb_build_object(
            'workCategoryId', catalog.work_category_id,
            'workCategoryName', category.item_name
          ))
        )
        from jsonb_array_elements(certificate_row->'items') item_row
        left join public.smis_qualification_catalog catalog
          on catalog.id = (item_row->>'catalogId')::uuid
         and catalog.tenant_id = (certificate_row->>'tenantId')::uuid
        left join public.smis_qualification_catalog category
          on category.id = catalog.work_category_id
         and category.tenant_id = catalog.tenant_id
         and category.catalog_type = 'work_category'
      ), '[]'::jsonb)
    )
  ))
  into v_records
  from jsonb_array_elements(v_payload->'records') certificate_row
  left join public.hr_employee employee
    on employee.id = (certificate_row->>'employeeId')::uuid
   and employee.tenant_id = (certificate_row->>'tenantId')::uuid;

  v_payload := jsonb_set(
    v_payload,
    '{records}',
    coalesce(v_records, '[]'::jsonb),
    true
  );

  if app_private.is_platform_super()
     or app_private.has_permission(v_permission_prefix || ':ViewHistory') then
    return v_payload;
  end if;

  return jsonb_set(
    v_payload,
    '{records}',
    coalesce((
      select jsonb_agg(
        certificate_row
        || jsonb_build_object(
          'items',
          coalesce((
            select jsonb_agg(
              (item_row - 'reviewHistory' - 'reviewCount')
              || jsonb_build_object('reviewHistory', '[]'::jsonb, 'reviewCount', 0)
            )
            from jsonb_array_elements(certificate_row->'items') item_row
          ), '[]'::jsonb)
        )
      )
      from jsonb_array_elements(v_payload->'records') certificate_row
    ), '[]'::jsonb),
    true
  );
end;
$function$;

revoke all on function public.smis_list_personnel_certificates_secure(
  integer, integer, text, text, text, date, date, text, text
) from public, anon;
grant execute on function public.smis_list_personnel_certificates_secure(
  integer, integer, text, text, text, date, date, text, text
) to authenticated, service_role;

comment on function app_private.smis_certificate_permission_prefix(text) is
  'Maps certificate categories to their exact page-level permission boundary.';
comment on function public.smis_list_certificate_employees_secure(
  text, integer, integer, text
) is 'Tenant-scoped active employee selector for certificate maintenance; safety-manager identity and education fields are returned only in that category.';
comment on function public.smis_list_certificate_catalog_options_secure(text) is
  'Returns tenant-scoped project, work-category, or internal validity-term options for one authorized certificate category.';
comment on function public.smis_save_personnel_certificate_secure(uuid, jsonb) is
  'Tenant-scoped certificate save with exact category permissions, category-specific fields, catalog validation, and immutable review protection.';

commit;

;
