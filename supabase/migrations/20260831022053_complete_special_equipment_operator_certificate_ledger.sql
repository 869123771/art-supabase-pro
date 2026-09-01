begin;

-- Seed the statutory G/R/D/T/Q/N/F operator project catalog for every tenant
-- that already uses this ledger, plus the public registration seed tenant.
with target_tenants as (
  select tenant.id
  from public.sys_tenant tenant
  where tenant.tenant_code = 'public-register'

  union

  select distinct assignment.tenant_id
  from public.sys_role_menu assignment
  join public.sys_menu menu on menu.id = assignment.menu_id
  where menu.name = 'SmisSpecialEquipmentOperatorCertificateLedger'

  union

  select distinct catalog.tenant_id
  from public.smis_qualification_catalog catalog
  where catalog.catalog_type = 'work_item'
), seed(item_code, item_name, sort) as (
  values
    ('G1', '一级锅炉司炉', 110),
    ('G2', '二级锅炉司炉', 120),
    ('G3', '三级锅炉司炉', 130),
    ('G4', '一级锅炉水质处理', 140),
    ('G5', '二级锅炉水质处理', 150),
    ('G6', '锅炉能效作业', 160),
    ('R1', '固定式压力容器操作', 210),
    ('R2', '移动式压力容器充装', 220),
    ('D1', '压力管道巡检维护', 310),
    ('D2', '带压封堵', 320),
    ('D3', '带压密封', 330),
    ('T1', '电梯机械安装维修', 410),
    ('T2', '电梯电气安装维修', 420),
    ('T3', '电梯司机', 430),
    ('Q1', '起重机械机械安装维修', 510),
    ('Q2', '起重机械电气安装维修', 520),
    ('Q3', '起重机械指挥', 530),
    ('Q4', '桥门式起重机司机', 540),
    ('Q5', '塔式起重机司机', 550),
    ('Q6', '门座式起重机司机', 560),
    ('Q7', '缆索式起重机司机', 570),
    ('Q8', '流动式起重机司机', 580),
    ('Q9', '升降机司机', 590),
    ('Q10', '机械式停车设备司机', 600),
    ('N1', '车辆维修', 610),
    ('N2', '叉车司机', 620),
    ('F1', '安全阀校验', 710),
    ('F2', '安全阀维修', 720)
)
insert into public.smis_qualification_catalog (
  id,
  tenant_id,
  catalog_type,
  parent_id,
  item_code,
  item_name,
  sort,
  status,
  remark,
  create_by,
  create_time,
  update_by,
  update_time
)
select
  gen_random_uuid(),
  tenant.id,
  'work_item',
  null,
  seed.item_code,
  seed.item_name,
  seed.sort,
  'enabled',
  '特种设备作业人员证法定作业项目',
  '624944977@qq.com',
  now(),
  '624944977@qq.com',
  now()
from target_tenants tenant
cross join seed
where not exists (
  select 1
  from public.smis_qualification_catalog existing
  where existing.tenant_id = tenant.id
    and existing.catalog_type = 'work_item'
    and upper(existing.item_code) = seed.item_code
);

-- Register category-specific actions under the exact operator-ledger menu.
with button_seed(suffix, title, sort) as (
  values
    ('View', '查看作业人员证件台账', 1),
    ('Add', '新增作业人员证件', 2),
    ('Copy', '复制并新增', 3),
    ('Edit', '编辑作业人员证件', 4),
    ('Delete', '删除作业人员证件', 5),
    ('Export', '导出作业人员证件台账', 6),
    ('ViewHistory', '查看作业人员复审记录', 7)
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
  parent.id,
  parent.name || ':' || button.suffix,
  '',
  null,
  jsonb_build_object(
    'icon', '',
    'roles', jsonb_build_array(),
    'title', button.title,
    'is_hide', true,
    'is_enable', true
  ),
  button.sort,
  '624944977@qq.com',
  now(),
  '624944977@qq.com',
  now(),
  'button',
  parent.app_code
from public.sys_menu parent
cross join button_seed button
where parent.name = 'SmisSpecialEquipmentOperatorCertificateLedger'
  and not exists (
    select 1
    from public.sys_menu existing
    where existing.name = parent.name || ':' || button.suffix
  );

-- Preserve existing access: roles that already own the page receive its new actions once.
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
 and page.name = 'SmisSpecialEquipmentOperatorCertificateLedger'
join public.sys_menu button
  on button.parent_id = page.id
 and button.type = 'button'
 and button.name like 'SmisSpecialEquipmentOperatorCertificateLedger:%'
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
    else 'SmisPersonnelCertificateLedger'
  end;
$function$;

revoke all on function app_private.smis_certificate_permission_prefix(text) from public;

create or replace function public.smis_delete_personnel_certificates_secure(p_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_count integer;
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再删除人员证件' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.smis_personnel_certificate certificate
    where certificate.tenant_id = app_private.current_read_tenant_id()
      and certificate.id = any(coalesce(p_ids, '{}'::uuid[]))
      and not app_private.has_permission(
        app_private.smis_certificate_permission_prefix(certificate.certificate_category)
        || ':Delete'
      )
  ) then
    raise exception '当前账号没有删除所选人员证件的权限' using errcode = '42501';
  end if;

  delete from public.smis_personnel_certificate certificate
  where certificate.tenant_id = app_private.current_read_tenant_id()
    and certificate.id = any(coalesce(p_ids, '{}'::uuid[]));

  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

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
    when 'safety_manager' then 'work_category'
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
    from public.hr_employee
    where id = v_employee
      and tenant_id = v_tenant
  ) then
    raise exception '所选员工不存在或不属于当前租户' using errcode = 'P0002';
  end if;

  if v_number = '' or char_length(v_number) > 100 then
    raise exception '请输入不超过 100 个字符的证件编号' using errcode = '22023';
  end if;

  if coalesce(p_payload->>'warning_status', 'normal') not in ('normal', 'warning') then
    raise exception '预警状态无效' using errcode = '22023';
  end if;

  if jsonb_typeof(coalesce(p_payload->'extra_fields', '{}'::jsonb)) <> 'object' then
    raise exception '证件类别特有信息格式无效' using errcode = '22023';
  end if;

  if jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) = 0 then
    raise exception '请至少维护一个作业项目' using errcode = '22023';
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
    raise exception '作业项目明细不属于当前证件' using errcode = '22023';
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
    raise exception '所选作业项目与证件类别不匹配' using errcode = '22023';
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
    raise exception '已停用的作业项目不能新增到证件' using errcode = '22023';
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
      coalesce(p_payload->'extra_fields', '{}'::jsonb),
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
        extra_fields = coalesce(p_payload->'extra_fields', '{}'::jsonb),
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
    raise exception '已有复审记录的作业项目不能移除' using errcode = '22023';
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
    raise exception '所选作业项目不存在、已删除或不属于当前租户' using errcode = '23503';
  when invalid_text_representation or datetime_field_overflow then
    raise exception '证件项目或日期格式无效' using errcode = '22023';
end;
$function$;

create or replace function public.smis_list_personnel_certificates_raw_secure(
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
  v_from integer := greatest(coalesce(p_from, 0), 0);
  v_to integer := greatest(coalesce(p_to, 19), greatest(coalesce(p_from, 0), 0));
  v_name text := nullif(lower(btrim(coalesce(p_employee_name, ''))), '');
  v_number text := nullif(lower(btrim(coalesce(p_certificate_number, ''))), '');
  v_permission_prefix text := app_private.smis_certificate_permission_prefix(
    p_certificate_category
  );
begin
  if (select auth.uid()) is null then
    raise exception '请先登录后再查看人员证件台账' using errcode = '42501';
  end if;

  if not (
    (select app_private.is_platform_super())
    or app_private.has_permission(v_permission_prefix || ':View')
  ) then
    raise exception '当前账号没有查看此类人员证件台账的权限' using errcode = '42501';
  end if;

  if p_purpose = 'export'
     and not app_private.has_permission(v_permission_prefix || ':Export') then
    raise exception '当前账号没有导出此类台账的权限' using errcode = '42501';
  end if;

  return (
    with enriched as (
      select
        certificate.*,
        employee.employee_no,
        employee.employee_name,
        employee.gender,
        employee.phone,
        employee.job_title,
        employee.avatar_url,
        organization.organization_name,
        coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', item.id,
              'catalogId', catalog.id,
              'workCode', catalog.item_code,
              'workName', catalog.item_name,
              'catalogType', catalog.catalog_type,
              'approvalDate', item.approval_date,
              'effectiveDate', item.effective_date,
              'reminderDays', item.reminder_days,
              'dismissalReason', item.dismissal_reason,
              'sort', item.sort,
              'reminderState', case
                when item.dismissal_reason is not null then 'dismissed'
                when item.effective_date < current_date then 'expired'
                when item.effective_date <= current_date + item.reminder_days then 'warning'
                else 'normal'
              end,
              'reviewCount', (
                select count(*)
                from public.smis_personnel_certificate_review_history history
                where history.certificate_item_id = item.id
              ),
              'reviewHistory', coalesce((
                select jsonb_agg(
                  jsonb_build_object(
                    'id', history.id,
                    'previousApprovalDate', history.previous_approval_date,
                    'previousEffectiveDate', history.previous_effective_date,
                    'approvalDate', history.approval_date,
                    'effectiveDate', history.effective_date,
                    'reviewBy', history.review_by,
                    'reviewTime', history.review_time
                  ) order by history.review_time desc
                )
                from public.smis_personnel_certificate_review_history history
                where history.certificate_item_id = item.id
              ), '[]'::jsonb)
            ) order by item.sort, catalog.item_name
          )
          from public.smis_personnel_certificate_item item
          join public.smis_qualification_catalog catalog on catalog.id = item.catalog_id
          where item.certificate_id = certificate.id
        ), '[]'::jsonb) as items,
        case
          when exists (
            select 1
            from public.smis_personnel_certificate_item item
            where item.certificate_id = certificate.id
              and item.dismissal_reason is null
              and item.effective_date < current_date
          ) then 'expired'
          when exists (
            select 1
            from public.smis_personnel_certificate_item item
            where item.certificate_id = certificate.id
              and item.dismissal_reason is null
              and item.effective_date <= current_date + item.reminder_days
          ) then 'warning'
          else 'normal'
        end as reminder_state,
        (
          select min(item.effective_date)
          from public.smis_personnel_certificate_item item
          where item.certificate_id = certificate.id
            and item.dismissal_reason is null
        ) as nearest_effective_date
      from public.smis_personnel_certificate certificate
      join public.hr_employee employee
        on employee.id = certificate.employee_id
       and employee.tenant_id = certificate.tenant_id
      left join public.sys_organization organization
        on organization.id = employee.organization_id
      where certificate.tenant_id = app_private.current_read_tenant_id()
    ), filtered as (
      select *
      from enriched certificate
      where (v_name is null or lower(certificate.employee_name) like '%' || v_name || '%')
        and (
          v_number is null
          or lower(certificate.certificate_number) like '%' || v_number || '%'
        )
        and (
          p_certificate_category is null
          or certificate.certificate_category = p_certificate_category
        )
        and (p_warning_status is null or certificate.warning_status = p_warning_status)
        and (
          (p_start_date is null and p_end_date is null)
          or exists (
            select 1
            from public.smis_personnel_certificate_item item
            where item.certificate_id = certificate.id
              and (p_start_date is null or item.effective_date >= p_start_date)
              and (p_end_date is null or item.effective_date <= p_end_date)
          )
        )
    )
    select jsonb_build_object(
      'records', coalesce((
        select jsonb_agg(
          to_jsonb(record)
          order by record."nearestEffectiveDate" nulls last, record."employeeName"
        )
        from (
          select
            id,
            tenant_id as "tenantId",
            employee_id as "employeeId",
            employee_no as "employeeNo",
            employee_name as "employeeName",
            gender,
            phone,
            job_title as "jobTitle",
            avatar_url as "avatarUrl",
            organization_name as "organizationName",
            certificate_category as "certificateCategory",
            certificate_number as "certificateNumber",
            issuing_authority as "issuingAuthority",
            archive_number as "archiveNumber",
            certificate_photo_url as "certificatePhotoUrl",
            warning_status as "warningStatus",
            reminder_state as "reminderState",
            nearest_effective_date as "nearestEffectiveDate",
            extra_fields as "extraFields",
            remark,
            items,
            create_by as "createBy",
            create_time as "createTime",
            update_by as "updateBy",
            update_time as "updateTime"
          from filtered
          offset v_from
          limit v_to - v_from + 1
        ) record
      ), '[]'::jsonb),
      'total', (select count(*) from filtered),
      'overview', (
        select jsonb_build_object(
          'total', count(*),
          'normal', count(*) filter (where reminder_state = 'normal'),
          'warning', count(*) filter (where reminder_state = 'warning'),
          'expired', count(*) filter (where reminder_state = 'expired'),
          'employees', count(distinct employee_id)
        )
        from filtered
      )
    )
  );
end;
$function$;

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

revoke all on function public.smis_list_personnel_certificates_raw_secure(
  integer, integer, text, text, text, date, date, text, text
) from public, anon, authenticated;

revoke all on function public.smis_list_personnel_certificates_secure(
  integer, integer, text, text, text, date, date, text, text
) from public, anon;
grant execute on function public.smis_list_personnel_certificates_secure(
  integer, integer, text, text, text, date, date, text, text
) to authenticated;

revoke all on function public.smis_save_personnel_certificate_secure(uuid, jsonb)
  from public, anon;
grant execute on function public.smis_save_personnel_certificate_secure(uuid, jsonb)
  to authenticated;

revoke all on function public.smis_delete_personnel_certificates_secure(uuid[])
  from public, anon;
grant execute on function public.smis_delete_personnel_certificates_secure(uuid[])
  to authenticated;

comment on function app_private.smis_certificate_permission_prefix(text) is
  'Maps certificate categories to their exact page-level permission boundary.';
comment on function public.smis_save_personnel_certificate_secure(uuid, jsonb) is
  'Tenant-scoped certificate master/detail save with exact category permissions and statutory project-scope validation.';
comment on function public.smis_list_personnel_certificates_raw_secure(
  integer, integer, text, text, text, date, date, text, text
) is 'Internal tenant-scoped certificate query with exact category view/export permissions.';

commit;

;
