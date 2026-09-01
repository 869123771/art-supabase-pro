begin;

with target_tenant as (
  select id
  from public.sys_tenant
  where tenant_code = 'public-register'
  union
  select distinct assignment.tenant_id
  from public.sys_role_menu assignment
  join public.sys_menu page on page.id = assignment.menu_id
  where page.name = 'SmisRegisteredSafetyEngineerLedger'
  union
  select distinct certificate.tenant_id
  from public.smis_personnel_certificate certificate
  where certificate.certificate_category = 'registered_safety_engineer'
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
  'REGISTERED_SAFETY_ENGINEER',
  '注册安全工程师证有效期',
  20,
  'enabled',
  '注册安全工程师日期、提醒和复审记录的内部关联项，不在基础数据菜单维护。',
  '624944977@qq.com',
  '624944977@qq.com'
from target_tenant tenant
where not exists (
  select 1
  from public.smis_qualification_catalog existing
  where existing.tenant_id = tenant.id
    and existing.catalog_type = 'certificate_term'
    and existing.item_code = 'REGISTERED_SAFETY_ENGINEER'
);

with dictionary_parent as (
  select tenant_id, parent_id
  from public.sys_dict_type
  where code = 'smisCertificateCategory'
), dictionary(name, code, remark, sort) as (
  values
    ('注册安全工程师安全员类别', 'smisRegisteredSafetyOfficerType', '注册安全工程师兼职、专职分类。', 87),
    ('注册安全工程师工程师类别', 'smisRegisteredEngineerType', '注册安全工程师与注册助理安全工程师分类。', 88),
    ('注册安全工程师注册类别', 'smisRegisteredPracticeCategory', '注册安全工程师执业注册专业分类。', 89)
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
cross join dictionary
where not exists (
  select 1 from public.sys_dict_type existing where existing.code = dictionary.code
);

with dictionary_value(dict_code, value, label, sort, tag_type) as (
  values
    ('smisRegisteredSafetyOfficerType', 'part_time', '兼职', 1, 'info'),
    ('smisRegisteredSafetyOfficerType', 'full_time', '专职', 2, 'primary'),
    ('smisRegisteredEngineerType', 'registered_safety_engineer', '注册安全工程师', 1, 'success'),
    ('smisRegisteredEngineerType', 'registered_assistant_safety_engineer', '注册助理安全工程师', 2, 'warning'),
    ('smisRegisteredPracticeCategory', 'coal_mine_safety', '煤矿安全', 1, null),
    ('smisRegisteredPracticeCategory', 'non_coal_mine_safety', '非煤矿矿山安全', 2, null),
    ('smisRegisteredPracticeCategory', 'other_safety', '其他安全', 3, null),
    ('smisRegisteredPracticeCategory', 'hazardous_material_safety', '危险物品安全', 4, null),
    ('smisRegisteredPracticeCategory', 'construction_safety', '建筑施工安全', 5, null)
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
  value.tag_type
from dictionary_value value
join public.sys_dict_type type on type.code = value.dict_code
where not exists (
  select 1
  from public.sys_dictionary existing
  where existing.type_id = type.id
    and existing.value = value.value
);

alter table public.smis_personnel_certificate_item
  add column if not exists dismissed_at timestamptz,
  add column if not exists dismissed_by text;

create or replace function app_private.smis_stamp_certificate_dismissal()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if new.dismissal_reason is null then
    new.dismissed_at := null;
    new.dismissed_by := null;
  elsif tg_op = 'INSERT'
     or old.dismissal_reason is distinct from new.dismissal_reason then
    new.dismissed_at := now();
    new.dismissed_by := public.get_app_user_display_name();
  end if;
  return new;
end;
$function$;

drop trigger if exists smis_certificate_item_stamp_dismissal
  on public.smis_personnel_certificate_item;
create trigger smis_certificate_item_stamp_dismissal
before insert or update of dismissal_reason
on public.smis_personnel_certificate_item
for each row
execute function app_private.smis_stamp_certificate_dismissal();

with button_seed(page_name, action, title, sort) as (
  values
    ('SmisRegisteredSafetyEngineerLedger', 'View', '查看注册安全工程师台账', 1),
    ('SmisRegisteredSafetyEngineerLedger', 'Add', '新增注册安全工程师证', 2),
    ('SmisRegisteredSafetyEngineerLedger', 'Copy', '复制并新增', 3),
    ('SmisRegisteredSafetyEngineerLedger', 'Edit', '编辑注册安全工程师证', 4),
    ('SmisRegisteredSafetyEngineerLedger', 'Delete', '删除注册安全工程师证', 5),
    ('SmisRegisteredSafetyEngineerLedger', 'Export', '导出注册安全工程师台账', 6),
    ('SmisRegisteredSafetyEngineerLedger', 'ViewHistory', '查看注册安全工程师复审记录', 7),
    ('SmisSafetyQualificationReportAnalysis', 'View', '查看安全资质报表分析', 1)
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
 and page.name in (
   'SmisRegisteredSafetyEngineerLedger',
   'SmisSafetyQualificationReportAnalysis'
 )
join public.sys_menu button
  on button.parent_id = page.id
 and button.type = 'button'
where not exists (
  select 1
  from public.sys_role_menu existing
  where existing.role_id = page_assignment.role_id
    and existing.menu_id = button.id
    and existing.tenant_id = page_assignment.tenant_id
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
    when 'registered_safety_engineer'
      then 'SmisRegisteredSafetyEngineerLedger'
    else 'SmisPersonnelCertificateLedger'
  end;
$function$;

revoke all on function app_private.smis_certificate_permission_prefix(text) from public;

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
              when p_certificate_category in ('safety_manager', 'registered_safety_engineer')
                then employee.id_card_no
              else null
            end,
            'educationLevel', case
              when p_certificate_category in ('safety_manager', 'registered_safety_engineer')
                then employee.education_level
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
      when p_certificate_category in ('safety_manager', 'registered_safety_engineer')
        then employee.id_card_no
      else null
    end,
    'educationLevel', case
      when p_certificate_category in ('safety_manager', 'registered_safety_engineer')
        then employee.education_level
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
    when 'registered_safety_engineer' then 'certificate_term'
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
        and (
          p_certificate_category <> 'registered_safety_engineer'
          or catalog.item_code = 'REGISTERED_SAFETY_ENGINEER'
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

alter function public.smis_save_personnel_certificate_secure(uuid, jsonb)
  rename to smis_save_personnel_certificate_base_secure;

revoke all on function public.smis_save_personnel_certificate_base_secure(uuid, jsonb)
  from public, anon, authenticated, service_role;

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
  v_category text := p_payload->>'certificate_category';
  v_tenant uuid;
  v_employee uuid;
  v_number text := btrim(coalesce(p_payload->>'certificate_number', ''));
  v_extra jsonb := coalesce(p_payload->'extra_fields', '{}'::jsonb);
  v_items jsonb := coalesce(p_payload->'items', '[]'::jsonb);
  v_item jsonb;
  v_item_id uuid;
  v_catalog_id uuid;
  v_result uuid;
begin
  if v_category <> 'registered_safety_engineer' then
    return public.smis_save_personnel_certificate_base_secure(p_id, p_payload);
  end if;

  if (select auth.uid()) is null then
    raise exception '请先登录后再维护注册安全工程师台账' using errcode = '42501';
  end if;
  if not app_private.has_permission(
    'SmisRegisteredSafetyEngineerLedger'
      || case when p_id is null then ':Add' else ':Edit' end
  ) then
    raise exception '当前账号没有维护注册安全工程师台账的权限' using errcode = '42501';
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
  if jsonb_typeof(v_extra) <> 'object'
     or coalesce(v_extra->>'safety_officer_type', '') not in ('part_time', 'full_time')
     or coalesce(v_extra->>'engineer_type', '') not in (
       'registered_safety_engineer',
       'registered_assistant_safety_engineer'
     )
     or coalesce(v_extra->>'practice_category', '') not in (
       'coal_mine_safety',
       'non_coal_mine_safety',
       'other_safety',
       'hazardous_material_safety',
       'construction_safety'
     )
     or v_extra - 'safety_officer_type' - 'engineer_type' - 'practice_category'
        <> '{}'::jsonb then
    raise exception '请选择有效的安全员类别、工程师类别和注册类别' using errcode = '22023';
  end if;
  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) <> 1 then
    raise exception '注册安全工程师证只能维护一条当前有效期' using errcode = '22023';
  end if;

  v_item := v_items->0;
  begin
    v_catalog_id := (v_item->>'catalog_id')::uuid;
    v_item_id := nullif(v_item->>'id', '')::uuid;
    perform (v_item->>'approval_date')::date;
    perform (v_item->>'effective_date')::date;
  exception
    when invalid_text_representation or datetime_field_overflow then
      raise exception '注册日期、有效日期或证件有效期关联项无效' using errcode = '22023';
  end;

  if not exists (
    select 1
    from public.smis_qualification_catalog catalog
    where catalog.id = v_catalog_id
      and catalog.tenant_id = v_tenant
      and catalog.catalog_type = 'certificate_term'
      and catalog.item_code = 'REGISTERED_SAFETY_ENGINEER'
      and catalog.status = 'enabled'
  ) then
    raise exception '注册安全工程师证有效期关联项无效' using errcode = '22023';
  end if;
  if (v_item->>'effective_date')::date < (v_item->>'approval_date')::date then
    raise exception '有效日期不能早于注册日期' using errcode = '22023';
  end if;
  if coalesce(nullif(v_item->>'reminder_days', '')::integer, 30) not between 0 and 730 then
    raise exception '提前提醒时间无效' using errcode = '22023';
  end if;
  if nullif(v_item->>'dismissal_reason', '') is not null
     and v_item->>'dismissal_reason' not in ('offboarded', 'trained') then
    raise exception '消除提醒原因无效' using errcode = '22023';
  end if;
  if p_id is null and nullif(v_item->>'dismissal_reason', '') is not null then
    raise exception '新增证件时不能填写消除提醒原因' using errcode = '22023';
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
      and certificate_category = v_category
    returning id into v_result;

    if v_result is null then
      raise exception '注册安全工程师证不存在或已删除' using errcode = 'P0002';
    end if;
    if v_item_id is null then
      select item.id
      into v_item_id
      from public.smis_personnel_certificate_item item
      where item.certificate_id = v_result
        and item.tenant_id = v_tenant
      order by item.sort, item.id
      limit 1;
    elsif not exists (
      select 1
      from public.smis_personnel_certificate_item item
      where item.id = v_item_id
        and item.certificate_id = v_result
        and item.tenant_id = v_tenant
    ) then
      raise exception '证件有效期明细不属于当前证件' using errcode = '22023';
    end if;
  end if;

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
  ) values (
    coalesce(v_item_id, gen_random_uuid()),
    v_tenant,
    v_result,
    v_catalog_id,
    (v_item->>'approval_date')::date,
    (v_item->>'effective_date')::date,
    coalesce(nullif(v_item->>'reminder_days', '')::integer, 30),
    nullif(v_item->>'dismissal_reason', ''),
    0
  )
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
    raise exception '同类别证件编号已存在' using errcode = '23505';
  when foreign_key_violation then
    raise exception '所选员工或证件有效期关联项不存在' using errcode = '23503';
end;
$function$;

revoke all on function public.smis_save_personnel_certificate_secure(uuid, jsonb)
  from public, anon;
grant execute on function public.smis_save_personnel_certificate_secure(uuid, jsonb)
  to authenticated, service_role;

create or replace function public.smis_list_personnel_certificates_extended_secure(
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
begin
  v_payload := public.smis_list_personnel_certificates_secure(
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
      when certificate_row->>'certificateCategory' in (
        'safety_manager',
        'registered_safety_engineer'
      ) then jsonb_strip_nulls(jsonb_build_object(
        'idCardNo', employee.id_card_no,
        'educationLevel', employee.education_level
      ))
      else '{}'::jsonb
    end
  ), '[]'::jsonb)
  into v_records
  from jsonb_array_elements(v_payload->'records') certificate_row
  left join public.hr_employee employee
    on employee.id = (certificate_row->>'employeeId')::uuid
   and employee.tenant_id = (certificate_row->>'tenantId')::uuid;

  return jsonb_set(v_payload, '{records}', v_records, true);
end;
$function$;

revoke all on function public.smis_list_personnel_certificates_extended_secure(
  integer, integer, text, text, text, date, date, text, text
) from public, anon;
grant execute on function public.smis_list_personnel_certificates_extended_secure(
  integer, integer, text, text, text, date, date, text, text
) to authenticated, service_role;

create index if not exists smis_certificate_created_report_idx
  on public.smis_personnel_certificate (tenant_id, create_time, certificate_category);
create index if not exists smis_certificate_item_dismissed_report_idx
  on public.smis_personnel_certificate_item (tenant_id, dismissed_at)
  where dismissed_at is not null;

create or replace function public.smis_get_safety_qualification_analysis_secure(
  p_start_date date default null,
  p_end_date date default null,
  p_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_tenant uuid := app_private.current_read_tenant_id();
  v_start date := coalesce(p_start_date, date_trunc('year', current_date)::date);
  v_end date := coalesce(p_end_date, current_date);
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看安全资质报表' using errcode = '42501';
  end if;
  if not app_private.has_permission('SmisSafetyQualificationReportAnalysis:View') then
    raise exception '当前账号没有查看安全资质报表的权限' using errcode = '42501';
  end if;
  if v_start > v_end then
    raise exception '统计开始日期不能晚于结束日期' using errcode = '22023';
  end if;
  if p_organization_id is not null and not exists (
    select 1
    from public.sys_organization organization
    where organization.id = p_organization_id
      and organization.tenant_id = v_tenant
  ) then
    raise exception '所选组织不存在或不属于当前租户' using errcode = 'P0002';
  end if;

  return (
    with recursive organization_scope as (
      select
        organization.id,
        organization.parent_id,
        organization.organization_code,
        organization.organization_name,
        organization.sort
      from public.sys_organization organization
      where organization.tenant_id = v_tenant
        and (p_organization_id is null or organization.id = p_organization_id)
      union all
      select
        child.id,
        child.parent_id,
        child.organization_code,
        child.organization_name,
        child.sort
      from public.sys_organization child
      join organization_scope parent on parent.id = child.parent_id
      where child.tenant_id = v_tenant
        and p_organization_id is not null
    ), scoped_certificate as materialized (
      select
        certificate.id,
        certificate.tenant_id,
        certificate.employee_id,
        certificate.certificate_category,
        certificate.warning_status,
        certificate.extra_fields,
        certificate.create_time,
        employee.employee_no,
        employee.employee_name,
        employee.education_level,
        employee.organization_id,
        coalesce(organization.organization_name, '未分配组织') as organization_name
      from public.smis_personnel_certificate certificate
      join public.hr_employee employee
        on employee.id = certificate.employee_id
       and employee.tenant_id = certificate.tenant_id
      left join public.sys_organization organization
        on organization.id = employee.organization_id
       and organization.tenant_id = employee.tenant_id
      where certificate.tenant_id = v_tenant
        and (
          p_organization_id is null
          or exists (
            select 1
            from organization_scope scope
            where scope.id = employee.organization_id
          )
        )
    ), scoped_item as materialized (
      select
        item.id,
        item.certificate_id,
        item.catalog_id,
        item.approval_date,
        item.effective_date,
        item.reminder_days,
        item.dismissal_reason,
        item.dismissed_at,
        certificate.employee_id,
        certificate.certificate_category,
        certificate.organization_id,
        certificate.organization_name
      from public.smis_personnel_certificate_item item
      join scoped_certificate certificate on certificate.id = item.certificate_id
      where item.tenant_id = v_tenant
    ), organization_distribution as (
      select
        certificate.organization_id,
        certificate.organization_name,
        count(*) filter (
          where certificate.certificate_category = 'special_equipment_personnel'
        )::integer as special_equipment_personnel,
        count(*) filter (
          where certificate.certificate_category = 'special_equipment_operator'
        )::integer as special_equipment_operator,
        count(*) filter (
          where certificate.certificate_category = 'special_operation'
        )::integer as special_operation,
        count(*) filter (
          where certificate.certificate_category = 'safety_manager'
        )::integer as safety_manager,
        count(*) filter (
          where certificate.certificate_category = 'registered_safety_engineer'
        )::integer as registered_safety_engineer,
        count(*)::integer as total
      from scoped_certificate certificate
      group by certificate.organization_id, certificate.organization_name
    ), holder_stat as (
      select
        certificate.employee_id,
        max(certificate.employee_no) as employee_no,
        max(certificate.employee_name) as employee_name,
        max(certificate.organization_name) as organization_name,
        count(*)::integer as certificate_count,
        array_agg(distinct certificate.certificate_category order by certificate.certificate_category)
          as certificate_categories
      from scoped_certificate certificate
      group by certificate.employee_id
    ), period_event as (
      select distinct
        'reminder'::text as metric,
        item.certificate_id,
        item.organization_id,
        item.organization_name,
        item.certificate_category
      from scoped_item item
      where item.effective_date - item.reminder_days between v_start and v_end
        and item.dismissal_reason is null
      union all
      select distinct
        'dismissed'::text,
        item.certificate_id,
        item.organization_id,
        item.organization_name,
        item.certificate_category
      from scoped_item item
      where item.dismissed_at::date between v_start and v_end
      union all
      select
        'added'::text,
        certificate.id,
        certificate.organization_id,
        certificate.organization_name,
        certificate.certificate_category
      from scoped_certificate certificate
      where certificate.create_time::date between v_start and v_end
    ), period_stat as (
      select
        event.metric,
        event.organization_id,
        event.organization_name,
        count(distinct event.certificate_id) filter (
          where event.certificate_category = 'special_equipment_personnel'
        )::integer as special_equipment_personnel,
        count(distinct event.certificate_id) filter (
          where event.certificate_category = 'special_equipment_operator'
        )::integer as special_equipment_operator,
        count(distinct event.certificate_id) filter (
          where event.certificate_category = 'special_operation'
        )::integer as special_operation,
        count(distinct event.certificate_id) filter (
          where event.certificate_category = 'safety_manager'
        )::integer as safety_manager,
        count(distinct event.certificate_id) filter (
          where event.certificate_category = 'registered_safety_engineer'
        )::integer as registered_safety_engineer,
        count(distinct event.certificate_id)::integer as total
      from period_event event
      group by event.metric, event.organization_id, event.organization_name
    ), equipment_project as (
      select
        catalog.item_code as work_code,
        catalog.item_name as work_name,
        count(distinct item.employee_id) filter (
          where item.certificate_category = 'special_equipment_personnel'
        )::integer as safety_manager_count,
        count(distinct item.employee_id) filter (
          where item.certificate_category = 'special_equipment_operator'
        )::integer as operator_count,
        count(distinct item.employee_id)::integer as total
      from scoped_item item
      join public.smis_qualification_catalog catalog
        on catalog.id = item.catalog_id
       and catalog.tenant_id = v_tenant
      where item.certificate_category in (
        'special_equipment_personnel',
        'special_equipment_operator'
      )
      group by catalog.id, catalog.item_code, catalog.item_name, catalog.sort
      order by catalog.sort, catalog.item_code, catalog.item_name
    ), special_operation_stat as (
      select
        coalesce(category.item_name, '未维护作业类别') as work_category_name,
        catalog.item_name as work_name,
        count(distinct item.employee_id)::integer as count
      from scoped_item item
      join public.smis_qualification_catalog catalog
        on catalog.id = item.catalog_id
       and catalog.tenant_id = v_tenant
      left join public.smis_qualification_catalog category
        on category.id = catalog.work_category_id
       and category.tenant_id = catalog.tenant_id
      where item.certificate_category = 'special_operation'
      group by category.item_name, category.sort, catalog.item_name, catalog.sort
      order by category.sort, category.item_name, catalog.sort, catalog.item_name
    ), safety_manager_type as (
      select
        'unitType'::text as dimension,
        coalesce(nullif(certificate.extra_fields->>'unit_type', ''), 'unknown') as value,
        count(distinct certificate.employee_id)::integer as count
      from scoped_certificate certificate
      where certificate.certificate_category = 'safety_manager'
      group by coalesce(nullif(certificate.extra_fields->>'unit_type', ''), 'unknown')
      union all
      select
        'occupationType'::text,
        coalesce(nullif(certificate.extra_fields->>'occupation_type', ''), 'unknown'),
        count(distinct certificate.employee_id)::integer
      from scoped_certificate certificate
      where certificate.certificate_category = 'safety_manager'
      group by coalesce(nullif(certificate.extra_fields->>'occupation_type', ''), 'unknown')
    ), registered_engineer_type as (
      select
        'safetyOfficerType'::text as dimension,
        coalesce(nullif(certificate.extra_fields->>'safety_officer_type', ''), 'unknown') as value,
        count(distinct certificate.employee_id)::integer as count
      from scoped_certificate certificate
      where certificate.certificate_category = 'registered_safety_engineer'
      group by coalesce(nullif(certificate.extra_fields->>'safety_officer_type', ''), 'unknown')
      union all
      select
        'engineerType'::text,
        coalesce(nullif(certificate.extra_fields->>'engineer_type', ''), 'unknown'),
        count(distinct certificate.employee_id)::integer
      from scoped_certificate certificate
      where certificate.certificate_category = 'registered_safety_engineer'
      group by coalesce(nullif(certificate.extra_fields->>'engineer_type', ''), 'unknown')
      union all
      select
        'practiceCategory'::text,
        coalesce(nullif(certificate.extra_fields->>'practice_category', ''), 'unknown'),
        count(distinct certificate.employee_id)::integer
      from scoped_certificate certificate
      where certificate.certificate_category = 'registered_safety_engineer'
      group by coalesce(nullif(certificate.extra_fields->>'practice_category', ''), 'unknown')
    ), education_stat as (
      select
        coalesce(nullif(certificate.education_level, ''), 'unknown') as education_level,
        count(distinct certificate.employee_id) filter (
          where certificate.certificate_category = 'safety_manager'
        )::integer as safety_manager_count,
        count(distinct certificate.employee_id) filter (
          where certificate.certificate_category = 'registered_safety_engineer'
        )::integer as registered_safety_engineer_count,
        count(distinct certificate.employee_id)::integer as total
      from scoped_certificate certificate
      where certificate.certificate_category in (
        'safety_manager',
        'registered_safety_engineer'
      )
      group by coalesce(nullif(certificate.education_level, ''), 'unknown')
    )
    select jsonb_build_object(
      'overview', jsonb_build_object(
        'totalCertificates', (select count(*) from scoped_certificate),
        'certificateHolders', (select count(distinct employee_id) from scoped_certificate),
        'warningCount', (
          select count(*) from scoped_certificate where warning_status = 'warning'
        ),
        'expiringInRange', (
          select count(distinct certificate_id)
          from scoped_item
          where effective_date between v_start and v_end
        ),
        'dismissedInRange', (
          select count(*)
          from scoped_item
          where dismissed_at::date between v_start and v_end
        ),
        'addedInRange', (
          select count(*)
          from scoped_certificate
          where create_time::date between v_start and v_end
        )
      ),
      'organizationDistribution', coalesce((
        select jsonb_agg(jsonb_build_object(
          'organizationId', stat.organization_id,
          'organizationName', stat.organization_name,
          'specialEquipmentPersonnel', stat.special_equipment_personnel,
          'specialEquipmentOperator', stat.special_equipment_operator,
          'specialOperation', stat.special_operation,
          'safetyManager', stat.safety_manager,
          'registeredSafetyEngineer', stat.registered_safety_engineer,
          'total', stat.total
        ) order by stat.total desc, stat.organization_name)
        from organization_distribution stat
      ), '[]'::jsonb),
      'topHolders', coalesce((
        select jsonb_agg(jsonb_build_object(
          'employeeId', holder.employee_id,
          'employeeNo', holder.employee_no,
          'employeeName', holder.employee_name,
          'organizationName', holder.organization_name,
          'certificateCount', holder.certificate_count,
          'certificateCategories', to_jsonb(holder.certificate_categories)
        ) order by holder.certificate_count desc, holder.employee_name)
        from (
          select *
          from holder_stat
          order by certificate_count desc, employee_name, employee_no
          limit 10
        ) holder
      ), '[]'::jsonb),
      'periodStats', coalesce((
        select jsonb_agg(jsonb_build_object(
          'metric', stat.metric,
          'organizationId', stat.organization_id,
          'organizationName', stat.organization_name,
          'specialEquipmentPersonnel', stat.special_equipment_personnel,
          'specialEquipmentOperator', stat.special_equipment_operator,
          'specialOperation', stat.special_operation,
          'safetyManager', stat.safety_manager,
          'registeredSafetyEngineer', stat.registered_safety_engineer,
          'total', stat.total
        ) order by stat.metric, stat.total desc, stat.organization_name)
        from period_stat stat
      ), '[]'::jsonb),
      'equipmentProjects', coalesce((
        select jsonb_agg(jsonb_build_object(
          'workCode', stat.work_code,
          'workName', stat.work_name,
          'safetyManagerCount', stat.safety_manager_count,
          'operatorCount', stat.operator_count,
          'total', stat.total
        )) from equipment_project stat
      ), '[]'::jsonb),
      'specialOperations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'workCategoryName', stat.work_category_name,
          'workName', stat.work_name,
          'count', stat.count
        )) from special_operation_stat stat
      ), '[]'::jsonb),
      'safetyManagerTypes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'dimension', stat.dimension,
          'value', stat.value,
          'count', stat.count
        ) order by stat.dimension, stat.count desc, stat.value)
        from safety_manager_type stat
      ), '[]'::jsonb),
      'registeredEngineerTypes', coalesce((
        select jsonb_agg(jsonb_build_object(
          'dimension', stat.dimension,
          'value', stat.value,
          'count', stat.count
        ) order by stat.dimension, stat.count desc, stat.value)
        from registered_engineer_type stat
      ), '[]'::jsonb),
      'educationDistribution', coalesce((
        select jsonb_agg(jsonb_build_object(
          'educationLevel', stat.education_level,
          'safetyManagerCount', stat.safety_manager_count,
          'registeredSafetyEngineerCount', stat.registered_safety_engineer_count,
          'total', stat.total
        ) order by stat.total desc, stat.education_level)
        from education_stat stat
      ), '[]'::jsonb),
      'organizationOptions', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', organization.id,
          'parentId', organization.parent_id,
          'organizationCode', organization.organization_code,
          'organizationName', organization.organization_name,
          'sort', organization.sort
        ) order by organization.sort, organization.organization_name)
        from public.sys_organization organization
        where organization.tenant_id = v_tenant
          and organization.status = '1'
      ), '[]'::jsonb)
    )
  );
end;
$function$;

revoke all on function public.smis_get_safety_qualification_analysis_secure(
  date, date, uuid
) from public, anon;
grant execute on function public.smis_get_safety_qualification_analysis_secure(
  date, date, uuid
) to authenticated, service_role;

comment on function public.smis_get_safety_qualification_analysis_secure(
  date, date, uuid
) is 'Tenant-scoped safety qualification analytics for organization, holder, reminder, project, category, and education dimensions.';

commit;

;
