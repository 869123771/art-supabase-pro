-- SMIS statutory holiday calendar and hierarchical site master data.

create table public.smis_statutory_holiday (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  organization_id uuid not null,
  holiday_type text not null,
  start_date date not null,
  end_date date not null,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_statutory_holiday_tenant_id_id_key unique (tenant_id, id),
  constraint smis_statutory_holiday_organization_fk foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_statutory_holiday_type_not_blank check (btrim(holiday_type) <> ''),
  constraint smis_statutory_holiday_date_range_check check (end_date >= start_date),
  constraint smis_statutory_holiday_remark_length_check check (char_length(coalesce(remark, '')) <= 500),
  constraint smis_statutory_holiday_natural_key unique (
    tenant_id, organization_id, holiday_type, start_date, end_date
  )
);

create index smis_statutory_holiday_tenant_period_idx
  on public.smis_statutory_holiday(tenant_id, start_date, end_date);
create index smis_statutory_holiday_organization_idx
  on public.smis_statutory_holiday(organization_id, tenant_id);
create index smis_statutory_holiday_type_idx
  on public.smis_statutory_holiday(tenant_id, holiday_type);

create trigger smis_statutory_holiday_create_audit before insert on public.smis_statutory_holiday
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_statutory_holiday_update_audit before update on public.smis_statutory_holiday
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_statutory_holiday enable row level security;
grant select on public.smis_statutory_holiday to authenticated;
revoke insert, update, delete on public.smis_statutory_holiday from authenticated;
revoke all on public.smis_statutory_holiday from anon;

create policy smis_statutory_holiday_select on public.smis_statutory_holiday for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisStatutoryHoliday:View'))
  )
);
create policy smis_statutory_holiday_insert on public.smis_statutory_holiday for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisStatutoryHoliday:Add'))
);
create policy smis_statutory_holiday_update on public.smis_statutory_holiday for update to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisStatutoryHoliday:Edit'))
  )
)
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy smis_statutory_holiday_delete on public.smis_statutory_holiday for delete to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisStatutoryHoliday:Delete'))
  )
);

create table public.smis_site (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  organization_id uuid not null,
  parent_id uuid,
  site_name text not null,
  category_code text not null,
  sort integer not null default 0,
  responsible_employee_id uuid,
  address_detail text,
  longitude numeric(10, 7),
  latitude numeric(10, 7),
  coordinate_system text not null default 'gcj02',
  image_urls jsonb not null default '[]'::jsonb,
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_site_tenant_id_id_key unique (tenant_id, id),
  constraint smis_site_organization_fk foreign key (tenant_id, organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_site_parent_fk foreign key (tenant_id, parent_id)
    references public.smis_site(tenant_id, id) on delete restrict,
  constraint smis_site_responsible_fk foreign key (responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_site_name_not_blank check (btrim(site_name) <> ''),
  constraint smis_site_name_length_check check (char_length(site_name) <= 120),
  constraint smis_site_category_check check (category_code in ('unit', 'area', 'building', 'yard', 'other')),
  constraint smis_site_parent_self_check check (parent_id is null or parent_id <> id),
  constraint smis_site_sort_check check (sort between 0 and 999999),
  constraint smis_site_longitude_check check (longitude is null or longitude between -180 and 180),
  constraint smis_site_latitude_check check (latitude is null or latitude between -90 and 90),
  constraint smis_site_coordinate_pair_check check ((longitude is null) = (latitude is null)),
  constraint smis_site_image_urls_array_check check (jsonb_typeof(image_urls) = 'array'),
  constraint smis_site_address_length_check check (char_length(coalesce(address_detail, '')) <= 300),
  constraint smis_site_remark_length_check check (char_length(coalesce(remark, '')) <= 500)
);

create index smis_site_parent_idx on public.smis_site(parent_id, tenant_id) where parent_id is not null;
create index smis_site_organization_idx on public.smis_site(organization_id, tenant_id);
create index smis_site_responsible_idx on public.smis_site(responsible_employee_id, tenant_id)
  where responsible_employee_id is not null;
create index smis_site_category_idx on public.smis_site(tenant_id, category_code);
create index smis_site_sort_idx on public.smis_site(tenant_id, sort, site_name);

create trigger smis_site_create_audit before insert on public.smis_site
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_site_update_audit before update on public.smis_site
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_site enable row level security;
grant select on public.smis_site to authenticated;
revoke insert, update, delete on public.smis_site from authenticated;
revoke all on public.smis_site from anon;

create policy smis_site_select on public.smis_site for select to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisSite:View'))
  )
);
create policy smis_site_insert on public.smis_site for insert to authenticated
with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisSite:Add'))
);
create policy smis_site_update on public.smis_site for update to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisSite:Edit'))
  )
)
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);
create policy smis_site_delete on public.smis_site for delete to authenticated
using (
  (select app_private.is_platform_super())
  or (
    tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisSite:Delete'))
  )
);

create or replace function public.smis_list_statutory_holidays_secure(
  p_from integer default 0,
  p_to integer default 999,
  p_organization_id uuid default null,
  p_holiday_type text default null,
  p_year integer default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_records jsonb;
  v_total bigint;
begin
  if not (app_private.is_platform_super() or app_private.has_permission('SmisStatutoryHoliday:View')) then
    raise exception '当前账号没有查看法定节假日的权限' using errcode = '42501';
  end if;

  select count(*) into v_total
  from public.smis_statutory_holiday holiday
  where holiday.tenant_id = v_tenant_id
    and (p_organization_id is null or holiday.organization_id = p_organization_id)
    and (p_holiday_type is null or holiday.holiday_type = p_holiday_type)
    and (p_year is null or holiday.start_date <= make_date(p_year, 12, 31)
      and holiday.end_date >= make_date(p_year, 1, 1));

  select coalesce(jsonb_agg(to_jsonb(record_row) order by record_row."startDate", record_row."createTime"), '[]'::jsonb)
  into v_records
  from (
    select holiday.id,
      holiday.organization_id as "organizationId",
      holiday.holiday_type as "holidayType",
      holiday.start_date as "startDate",
      holiday.end_date as "endDate",
      holiday.remark,
      holiday.create_time as "createTime",
      holiday.update_time as "updateTime",
      jsonb_build_object(
        'id', organization.id,
        'organizationCode', organization.organization_code,
        'organizationName', organization.organization_name,
        'organizationType', organization.organization_type
      ) as organization
    from public.smis_statutory_holiday holiday
    join public.sys_organization organization
      on organization.id = holiday.organization_id and organization.tenant_id = holiday.tenant_id
    where holiday.tenant_id = v_tenant_id
      and (p_organization_id is null or holiday.organization_id = p_organization_id)
      and (p_holiday_type is null or holiday.holiday_type = p_holiday_type)
      and (p_year is null or holiday.start_date <= make_date(p_year, 12, 31)
        and holiday.end_date >= make_date(p_year, 1, 1))
    order by holiday.start_date, holiday.create_time
    offset greatest(coalesce(p_from, 0), 0)
    limit greatest(coalesce(p_to, 999) - greatest(coalesce(p_from, 0), 0) + 1, 0)
  ) record_row;

  return jsonb_build_object('records', v_records, 'total', v_total);
end;
$$;

create or replace function public.smis_save_statutory_holiday_secure(
  p_id uuid,
  p_payload jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_organization_id uuid := nullif(p_payload->>'organization_id', '')::uuid;
  v_type text := btrim(coalesce(p_payload->>'holiday_type', ''));
  v_start date := nullif(p_payload->>'start_date', '')::date;
  v_end date := nullif(p_payload->>'end_date', '')::date;
begin
  if p_id is null and not app_private.has_permission('SmisStatutoryHoliday:Add') then
    raise exception '当前账号没有新增法定节假日的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisStatutoryHoliday:Edit') then
    raise exception '当前账号没有编辑法定节假日的权限' using errcode = '42501';
  end if;
  if v_organization_id is null or not exists (
    select 1 from public.sys_organization organization
    where organization.id = v_organization_id and organization.tenant_id = v_tenant_id and organization.status = '1'
  ) then raise exception '请选择当前租户的有效公司或组织' using errcode = '22023'; end if;
  if v_type not in ('compensatory_leave', 'spring_festival', 'new_year', 'qingming', 'labor_day', 'dragon_boat', 'mid_autumn', 'national_day') then
    raise exception '假期类型无效' using errcode = '22023';
  end if;
  if v_start is null or v_end is null or v_end < v_start then
    raise exception '结束日期不能早于开始日期' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.smis_statutory_holiday(
      tenant_id, organization_id, holiday_type, start_date, end_date, remark
    ) values (
      v_tenant_id, v_organization_id, v_type, v_start, v_end, nullif(btrim(p_payload->>'remark'), '')
    ) returning id into v_id;
  else
    update public.smis_statutory_holiday set
      organization_id = v_organization_id,
      holiday_type = v_type,
      start_date = v_start,
      end_date = v_end,
      remark = nullif(btrim(p_payload->>'remark'), '')
    where id = p_id and tenant_id = v_tenant_id returning id into v_id;
    if v_id is null then raise exception '法定节假日记录不存在或已删除' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.smis_delete_statutory_holidays_secure(p_ids uuid[]) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_count integer; begin
  if not app_private.has_permission('SmisStatutoryHoliday:Delete') then
    raise exception '当前账号没有删除法定节假日的权限' using errcode = '42501';
  end if;
  delete from public.smis_statutory_holiday
  where tenant_id = app_private.current_user_tenant_id() and id = any(p_ids);
  get diagnostics v_count = row_count;
  return v_count;
end; $$;

create or replace function public.smis_list_sites_secure() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_tenant_id uuid := app_private.current_user_tenant_id(); begin
  if not (app_private.is_platform_super() or app_private.has_permission('SmisSite:View')) then
    raise exception '当前账号没有查看场所的权限' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(record_row) order by record_row.sort, record_row."siteName")
    from (
      select site.id,
        site.parent_id as "parentId",
        site.organization_id as "organizationId",
        site.site_name as "siteName",
        site.category_code as "categoryCode",
        site.sort,
        site.responsible_employee_id as "responsibleEmployeeId",
        site.address_detail as "addressDetail",
        site.longitude,
        site.latitude,
        site.coordinate_system as "coordinateSystem",
        site.image_urls as "imageUrls",
        site.remark,
        site.create_time as "createTime",
        site.update_time as "updateTime",
        parent_site.site_name as "parentSiteName",
        jsonb_build_object(
          'id', organization.id,
          'organizationCode', organization.organization_code,
          'organizationName', organization.organization_name,
          'parentOrganizationName', parent_organization.organization_name
        ) as organization,
        case when employee.id is null then null else jsonb_build_object(
          'id', employee.id,
          'employeeNo', employee.employee_no,
          'employeeName', employee.employee_name,
          'phone', employee.phone,
          'jobTitle', employee.job_title
        ) end as responsible
      from public.smis_site site
      join public.sys_organization organization
        on organization.id = site.organization_id and organization.tenant_id = site.tenant_id
      left join public.sys_organization parent_organization
        on parent_organization.id = organization.parent_id and parent_organization.tenant_id = organization.tenant_id
      left join public.smis_site parent_site
        on parent_site.id = site.parent_id and parent_site.tenant_id = site.tenant_id
      left join public.hr_employee employee
        on employee.id = site.responsible_employee_id and employee.tenant_id = site.tenant_id
      where site.tenant_id = v_tenant_id
      order by site.sort, site.site_name
    ) record_row
  ), '[]'::jsonb);
end; $$;

create or replace function public.smis_list_site_employees_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_keyword text := nullif(btrim(coalesce(p_keyword, '')), '');
  v_total bigint;
  v_records jsonb;
begin
  if not (
    app_private.is_platform_super()
    or app_private.has_permission('SmisSite:View')
    or app_private.has_permission('SmisSite:Add')
    or app_private.has_permission('SmisSite:Edit')
  ) then raise exception '当前账号没有选择场所责任人的权限' using errcode = '42501'; end if;

  select count(*) into v_total
  from public.hr_employee employee
  left join public.sys_organization organization
    on organization.id = employee.organization_id and organization.tenant_id = employee.tenant_id
  where employee.tenant_id = v_tenant_id
    and employee.employment_status in ('active', 'probation')
    and (v_keyword is null or employee.employee_name ilike '%' || v_keyword || '%'
      or employee.employee_no ilike '%' || v_keyword || '%'
      or organization.organization_name ilike '%' || v_keyword || '%'
      or employee.job_title ilike '%' || v_keyword || '%');

  select coalesce(jsonb_agg(to_jsonb(record_row) order by record_row."employeeName"), '[]'::jsonb)
  into v_records
  from (
    select employee.id,
      employee.tenant_id as "tenantId",
      employee.organization_id as "organizationId",
      employee.employee_no as "employeeNo",
      employee.employee_name as "employeeName",
      employee.avatar_url as "avatarUrl",
      employee.job_title as "jobTitle",
      employee.employment_status as "employmentStatus",
      case when organization.id is null then null else jsonb_build_object(
        'id', organization.id,
        'organizationCode', organization.organization_code,
        'organizationName', organization.organization_name
      ) end as organization
    from public.hr_employee employee
    left join public.sys_organization organization
      on organization.id = employee.organization_id and organization.tenant_id = employee.tenant_id
    where employee.tenant_id = v_tenant_id
      and employee.employment_status in ('active', 'probation')
      and (v_keyword is null or employee.employee_name ilike '%' || v_keyword || '%'
        or employee.employee_no ilike '%' || v_keyword || '%'
        or organization.organization_name ilike '%' || v_keyword || '%'
        or employee.job_title ilike '%' || v_keyword || '%')
    order by employee.employee_name
    offset greatest(coalesce(p_from, 0), 0)
    limit greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 0)
  ) record_row;
  return jsonb_build_object('records', v_records, 'total', v_total);
end; $$;

create or replace function public.smis_save_site_secure(p_id uuid, p_payload jsonb) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid;
  v_organization_id uuid := nullif(p_payload->>'organization_id', '')::uuid;
  v_parent_id uuid := nullif(p_payload->>'parent_id', '')::uuid;
  v_employee_id uuid := nullif(p_payload->>'responsible_employee_id', '')::uuid;
  v_site_name text := btrim(coalesce(p_payload->>'site_name', ''));
  v_category text := btrim(coalesce(p_payload->>'category_code', ''));
begin
  if p_id is null and not app_private.has_permission('SmisSite:Add') then
    raise exception '当前账号没有新增场所的权限' using errcode = '42501';
  end if;
  if p_id is not null and not app_private.has_permission('SmisSite:Edit') then
    raise exception '当前账号没有编辑场所的权限' using errcode = '42501';
  end if;
  if v_site_name = '' then raise exception '请输入场所名称' using errcode = '22023'; end if;
  if v_category not in ('unit', 'area', 'building', 'yard', 'other') then
    raise exception '属性类别无效' using errcode = '22023';
  end if;
  if not exists (select 1 from public.sys_organization where id = v_organization_id and tenant_id = v_tenant_id and status = '1') then
    raise exception '请选择当前租户的有效部门' using errcode = '22023';
  end if;
  if v_employee_id is not null and not exists (
    select 1 from public.hr_employee where id = v_employee_id and tenant_id = v_tenant_id
      and employment_status in ('active', 'probation')
  ) then raise exception '责任人不是当前租户的有效员工' using errcode = '22023'; end if;
  if v_parent_id is not null and not exists (
    select 1 from public.smis_site where id = v_parent_id and tenant_id = v_tenant_id
  ) then raise exception '上级场所不存在或已删除' using errcode = '22023'; end if;
  if p_id is not null and v_parent_id is not null and exists (
    with recursive descendants as (
      select id from public.smis_site where parent_id = p_id and tenant_id = v_tenant_id
      union all
      select child.id from public.smis_site child join descendants parent on child.parent_id = parent.id
      where child.tenant_id = v_tenant_id
    ) select 1 from descendants where id = v_parent_id
  ) then raise exception '上级场所不能选择当前场所的下级节点' using errcode = '22023'; end if;

  if p_id is null then
    insert into public.smis_site(
      tenant_id, organization_id, parent_id, site_name, category_code, sort,
      responsible_employee_id, address_detail, longitude, latitude, coordinate_system,
      image_urls, remark
    ) values (
      v_tenant_id, v_organization_id, v_parent_id, v_site_name, v_category,
      coalesce((p_payload->>'sort')::integer, 0), v_employee_id,
      nullif(btrim(p_payload->>'address_detail'), ''),
      nullif(p_payload->>'longitude', '')::numeric, nullif(p_payload->>'latitude', '')::numeric,
      coalesce(nullif(p_payload->>'coordinate_system', ''), 'gcj02'),
      coalesce(p_payload->'image_urls', '[]'::jsonb), nullif(btrim(p_payload->>'remark'), '')
    ) returning id into v_id;
  else
    update public.smis_site set
      organization_id = v_organization_id,
      parent_id = v_parent_id,
      site_name = v_site_name,
      category_code = v_category,
      sort = coalesce((p_payload->>'sort')::integer, 0),
      responsible_employee_id = v_employee_id,
      address_detail = nullif(btrim(p_payload->>'address_detail'), ''),
      longitude = nullif(p_payload->>'longitude', '')::numeric,
      latitude = nullif(p_payload->>'latitude', '')::numeric,
      coordinate_system = coalesce(nullif(p_payload->>'coordinate_system', ''), 'gcj02'),
      image_urls = coalesce(p_payload->'image_urls', '[]'::jsonb),
      remark = nullif(btrim(p_payload->>'remark'), '')
    where id = p_id and tenant_id = v_tenant_id returning id into v_id;
    if v_id is null then raise exception '场所记录不存在或已删除' using errcode = 'P0002'; end if;
  end if;
  return v_id;
end; $$;

create or replace function public.smis_delete_sites_secure(p_ids uuid[]) returns integer
language plpgsql security definer set search_path = '' as $$
declare v_count integer; begin
  if not app_private.has_permission('SmisSite:Delete') then
    raise exception '当前账号没有删除场所的权限' using errcode = '42501';
  end if;
  delete from public.smis_site
  where tenant_id = app_private.current_user_tenant_id() and id = any(p_ids);
  get diagnostics v_count = row_count;
  return v_count;
end; $$;

revoke all on function public.smis_list_statutory_holidays_secure(integer, integer, uuid, text, integer) from public, anon;
revoke all on function public.smis_save_statutory_holiday_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_statutory_holidays_secure(uuid[]) from public, anon;
revoke all on function public.smis_list_sites_secure() from public, anon;
revoke all on function public.smis_list_site_employees_secure(integer, integer, text) from public, anon;
revoke all on function public.smis_save_site_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_sites_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_statutory_holidays_secure(integer, integer, uuid, text, integer) to authenticated, service_role;
grant execute on function public.smis_save_statutory_holiday_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.smis_delete_statutory_holidays_secure(uuid[]) to authenticated, service_role;
grant execute on function public.smis_list_sites_secure() to authenticated, service_role;
grant execute on function public.smis_list_site_employees_secure(integer, integer, text) to authenticated, service_role;
grant execute on function public.smis_save_site_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.smis_delete_sites_secure(uuid[]) to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_types(name, code, sort) as (
  values ('法定假期类型', 'smisHolidayType', 220), ('场所属性类别', 'smisSiteCategory', 221)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), seed.name, seed.code, '1',
  '624944977@qq.com', '624944977@qq.com', 'SMIS 基础数据字典', platform_tenant.id,
  (select id from public.sys_dict_type where code = 'hrManage' limit 1), 'dictionary', seed.sort
from dictionary_types seed cross join platform_tenant
on conflict (code) do update set name = excluded.name, status = excluded.status,
  update_by = excluded.update_by, update_time = now(), remark = excluded.remark, sort = excluded.sort;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_items(type_code, value, label, sort, tag_type) as (
  values
    ('smisHolidayType', 'compensatory_leave', '调休', 1, 'info'),
    ('smisHolidayType', 'spring_festival', '春节', 2, 'danger'),
    ('smisHolidayType', 'new_year', '元旦', 3, 'success'),
    ('smisHolidayType', 'qingming', '清明节', 4, 'success'),
    ('smisHolidayType', 'labor_day', '劳动节', 5, 'warning'),
    ('smisHolidayType', 'dragon_boat', '端午节', 6, 'primary'),
    ('smisHolidayType', 'mid_autumn', '中秋节', 7, 'warning'),
    ('smisHolidayType', 'national_day', '国庆节', 8, 'danger'),
    ('smisSiteCategory', 'unit', '单元', 1, 'primary'),
    ('smisSiteCategory', 'area', '区域', 2, 'success'),
    ('smisSiteCategory', 'building', '建筑', 3, 'warning'),
    ('smisSiteCategory', 'yard', '场地', 4, 'info'),
    ('smisSiteCategory', 'other', '其他', 5, 'info')
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id, seed.type_code || '_' || seed.value, '1',
  '624944977@qq.com', '624944977@qq.com', 'SMIS 基础数据字典项',
  seed.value, seed.label, platform_tenant.id, seed.tag_type, seed.sort
from dictionary_items seed
join public.sys_dict_type dictionary_type on dictionary_type.code = seed.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = seed.value
);

with button_seed(page_name, code, title, sort) as (
  values
    ('SmisStatutoryHoliday', 'SmisStatutoryHoliday:View', '查看法定节假日', 1),
    ('SmisStatutoryHoliday', 'SmisStatutoryHoliday:Add', '新增法定节假日', 2),
    ('SmisStatutoryHoliday', 'SmisStatutoryHoliday:Edit', '编辑法定节假日', 3),
    ('SmisStatutoryHoliday', 'SmisStatutoryHoliday:Delete', '删除法定节假日', 4),
    ('SmisStatutoryHoliday', 'SmisStatutoryHoliday:Import', '导入法定节假日', 5),
    ('SmisStatutoryHoliday', 'SmisStatutoryHoliday:Export', '导出法定节假日', 6),
    ('SmisSite', 'SmisSite:View', '查看场所', 1),
    ('SmisSite', 'SmisSite:Add', '新增场所', 2),
    ('SmisSite', 'SmisSite:Edit', '编辑场所', 3),
    ('SmisSite', 'SmisSite:Delete', '删除场所', 4),
    ('SmisSite', 'SmisSite:Import', '导入场所', 5),
    ('SmisSite', 'SmisSite:Export', '导出场所', 6)
)
insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select gen_random_uuid(), page.id, seed.code, '', '',
  jsonb_build_object('title', seed.title, 'icon', '', 'is_hide', true, 'is_enable', true, 'roles', jsonb_build_array()),
  seed.sort, 'button', 'smis', '624944977@qq.com', '624944977@qq.com'
from button_seed seed
join public.sys_menu page on page.name = seed.page_name
where not exists (select 1 from public.sys_menu existing where existing.name = seed.code);

insert into public.sys_role_menu(role_id, menu_id, tenant_id, permission, create_by, update_by)
select page_grant.role_id, button.id, role.tenant_id, '{}'::jsonb,
  '624944977@qq.com', '624944977@qq.com'
from public.sys_role_menu page_grant
join public.sys_menu page on page.id = page_grant.menu_id
join public.sys_role role on role.id = page_grant.role_id
join public.sys_menu button on button.parent_id = page.id and button.type = 'button'
where page.name in ('SmisStatutoryHoliday', 'SmisSite')
on conflict (role_id, menu_id) do nothing;

;
