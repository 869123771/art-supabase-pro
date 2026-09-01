create table if not exists public.hr_position (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  position_code text not null,
  position_name text not null,
  position_kind text not null default 'standard',
  system_code text,
  enabled boolean not null default true,
  sort integer not null default 0,
  description text,
  create_by text not null default coalesce(auth.uid()::text, 'system'),
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint hr_position_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint hr_position_kind_check check (position_kind in ('standard', 'driver')),
  constraint hr_position_code_not_blank check (btrim(position_code) <> ''),
  constraint hr_position_name_not_blank check (btrim(position_name) <> ''),
  constraint hr_position_id_tenant_unique unique (id, tenant_id)
);

create unique index if not exists hr_position_tenant_code_unique
  on public.hr_position(tenant_id, lower(position_code));
create unique index if not exists hr_position_tenant_name_unique
  on public.hr_position(tenant_id, lower(position_name));
create unique index if not exists hr_position_tenant_system_unique
  on public.hr_position(tenant_id, system_code)
  where system_code is not null;
create index if not exists hr_position_tenant_enabled_sort_idx
  on public.hr_position(tenant_id, enabled, sort, position_name);

comment on table public.hr_position is
  'HR岗位主数据；position_kind承载业务行为，不依赖岗位显示名称判断';
comment on column public.hr_position.position_kind is
  'standard=普通岗位，driver=司机岗位；司机岗位触发员工与司机档案联动';

alter table public.hr_position enable row level security;
revoke all on table public.hr_position from anon, authenticated;
grant all on table public.hr_position to service_role;

insert into public.hr_position (
  tenant_id, position_code, position_name, position_kind, system_code,
  enabled, sort, description, create_by
)
select
  tenant_row.id, 'DRIVER', '司机', 'driver', 'driver', true, 10,
  '系统司机岗位；选择该岗位新增员工时同步创建司机档案', 'migration'
from public.sys_tenant tenant_row
on conflict (tenant_id, system_code) where system_code is not null do nothing;

insert into public.hr_position (
  tenant_id, position_code, position_name, position_kind, enabled, sort,
  description, create_by
)
select distinct
  employee_row.tenant_id,
  'LEGACY-' || upper(substr(md5(btrim(employee_row.job_title)), 1, 12)),
  btrim(employee_row.job_title),
  'standard', true, 100,
  '由员工花名册历史工作岗位自动迁移', 'migration'
from public.hr_employee employee_row
where nullif(btrim(employee_row.job_title), '') is not null
  and lower(btrim(employee_row.job_title)) <> '司机'
on conflict do nothing;

insert into public.hr_position (
  tenant_id, position_code, position_name, position_kind, system_code,
  enabled, sort, description, create_by
)
select distinct
  employee_row.tenant_id, 'UNASSIGNED', '待分配岗位', 'standard', 'unassigned',
  true, 9999, '用于承接历史未维护岗位的员工档案', 'migration'
from public.hr_employee employee_row
where nullif(btrim(employee_row.job_title), '') is null
on conflict (tenant_id, system_code) where system_code is not null do nothing;

alter table public.hr_employee
  add column if not exists position_id uuid;

update public.hr_employee employee_row
set position_id = position_row.id
from public.hr_position position_row
where position_row.tenant_id = employee_row.tenant_id
  and (
    lower(position_row.position_name) = lower(btrim(employee_row.job_title))
    or (
      nullif(btrim(employee_row.job_title), '') is null
      and position_row.system_code = 'unassigned'
    )
  )
  and employee_row.position_id is null;

alter table public.hr_employee
  drop constraint if exists hr_employee_position_tenant_fkey;
alter table public.hr_employee
  add constraint hr_employee_position_tenant_fkey
  foreign key (position_id, tenant_id)
  references public.hr_position(id, tenant_id)
  on delete restrict;
create index if not exists hr_employee_tenant_position_idx
  on public.hr_employee(tenant_id, position_id);

do $$
begin
  if not exists (select 1 from public.hr_employee where position_id is null) then
    alter table public.hr_employee alter column position_id set not null;
  end if;
end;
$$;

create or replace function app_private.sync_hr_employee_position_title()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_position public.hr_position%rowtype;
begin
  select * into v_position
  from public.hr_position position_row
  where position_row.id = new.position_id
    and position_row.tenant_id = new.tenant_id;

  if not found then
    raise exception '所选岗位不存在或不属于员工所在租户';
  end if;

  if not v_position.enabled then
    raise exception '所选岗位已停用';
  end if;

  if tg_op = 'UPDATE' and new.position_id is distinct from old.position_id then
    if exists (
      select 1 from public.tms_driver driver_row
      where driver_row.employee_id = new.id and driver_row.tenant_id = new.tenant_id
    ) and v_position.position_kind <> 'driver' then
      raise exception '该员工已有司机档案，请先在司机管理中处理后再调整岗位';
    end if;

    if v_position.position_kind = 'driver' and not exists (
      select 1 from public.tms_driver driver_row
      where driver_row.employee_id = new.id and driver_row.tenant_id = new.tenant_id
    ) then
      raise exception '已有员工转为司机岗位时，请从司机管理选择该员工并补齐司机资料';
    end if;
  end if;

  new.job_title := v_position.position_name;
  return new;
end;
$$;

drop trigger if exists trg_hr_employee_position_title on public.hr_employee;
create trigger trg_hr_employee_position_title
before insert or update of position_id, tenant_id
on public.hr_employee
for each row execute function app_private.sync_hr_employee_position_title();

create or replace function app_private.sync_linked_employee_driver_position()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_position_id uuid;
begin
  if new.employee_id is null then
    return new;
  end if;

  select position_row.id into v_position_id
  from public.hr_position position_row
  where position_row.tenant_id = new.tenant_id
    and position_row.system_code = 'driver';

  if v_position_id is null then
    raise exception '当前租户未配置系统司机岗位';
  end if;

  update public.hr_employee employee_row
  set position_id = v_position_id,
      update_by = coalesce(auth.uid()::text, employee_row.update_by),
      update_time = now()
  where employee_row.id = new.employee_id
    and employee_row.tenant_id = new.tenant_id
    and employee_row.position_id is distinct from v_position_id;

  return new;
end;
$$;

drop trigger if exists trg_tms_driver_employee_position on public.tms_driver;
create trigger trg_tms_driver_employee_position
after insert or update of employee_id, tenant_id
on public.tms_driver
for each row execute function app_private.sync_linked_employee_driver_position();

create or replace function public.hr_list_positions_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_enabled boolean default null,
  p_tenant_id uuid default null
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
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:View', null, false) then
    raise exception 'Missing position view permission' using errcode = '42501';
  end if;

  if not app_private.is_platform_super() then
    p_tenant_id := v_tenant_id;
  end if;

  v_limit := least(100, greatest(coalesce(p_to, 19) - greatest(coalesce(p_from, 0), 0) + 1, 1));

  with filtered as materialized (
    select
      position_row.*,
      tenant_row.tenant_code,
      tenant_row.tenant_name,
      (select count(*) from public.hr_employee employee_row
       where employee_row.position_id = position_row.id
         and employee_row.tenant_id = position_row.tenant_id) as employee_count
    from public.hr_position position_row
    join public.sys_tenant tenant_row on tenant_row.id = position_row.tenant_id
    where (p_tenant_id is null or position_row.tenant_id = p_tenant_id)
      and (p_enabled is null or position_row.enabled = p_enabled)
      and (
        nullif(btrim(p_keyword), '') is null
        or position_row.position_code ilike '%' || btrim(p_keyword) || '%'
        or position_row.position_name ilike '%' || btrim(p_keyword) || '%'
        or position_row.description ilike '%' || btrim(p_keyword) || '%'
      )
  ), paged as (
    select * from filtered
    order by tenant_name, sort, position_name
    offset greatest(coalesce(p_from, 0), 0)
    limit v_limit
  )
  select jsonb_build_object(
    'records', coalesce((select jsonb_agg(to_jsonb(paged) order by tenant_name, sort, position_name) from paged), '[]'::jsonb),
    'total', (select count(*) from filtered)
  ) into v_result;

  return v_result;
end;
$$;

create or replace function public.hr_list_position_options_secure(
  p_tenant_id uuid default null,
  p_include_disabled boolean default false
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
  if not (
    app_private.can_execute_business_action('HrEmployeeRoster', 'Hr:Employee:Add', null, false)
    or app_private.can_execute_business_action('HrEmployeeRoster', 'Hr:Employee:Edit', null, false)
    or app_private.can_execute_business_action('HrPosition', 'Hr:Position:View', null, false)
  ) then
    raise exception 'Missing employee or position permission' using errcode = '42501';
  end if;

  if not app_private.is_platform_super() then
    p_tenant_id := v_tenant_id;
  end if;
  if p_tenant_id is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', position_row.id,
      'tenant_id', position_row.tenant_id,
      'position_code', position_row.position_code,
      'position_name', position_row.position_name,
      'position_kind', position_row.position_kind,
      'system_code', position_row.system_code,
      'enabled', position_row.enabled
    ) order by position_row.sort, position_row.position_name)
    from public.hr_position position_row
    where position_row.tenant_id = p_tenant_id
      and (p_include_disabled or position_row.enabled)
  ), '[]'::jsonb);
end;
$$;

create or replace function public.hr_create_position_secure(p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid;
  v_id uuid;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:Add', null, false) then
    raise exception 'Missing position create permission' using errcode = '42501';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception '岗位数据格式不正确';
  end if;
  if exists (select 1 from jsonb_object_keys(p_payload) key where key <> all(array[
    'tenant_id','position_code','position_name','enabled','sort','description'
  ]::text[])) then
    raise exception '岗位数据包含不允许写入的字段';
  end if;

  v_tenant_id := case when app_private.is_platform_super()
    then nullif(p_payload->>'tenant_id', '')::uuid
    else app_private.current_user_tenant_id()
  end;
  if v_tenant_id is null then raise exception '请选择岗位所属租户'; end if;

  insert into public.hr_position (
    tenant_id, position_code, position_name, enabled, sort, description, create_by
  ) values (
    v_tenant_id, upper(btrim(p_payload->>'position_code')), btrim(p_payload->>'position_name'),
    coalesce((p_payload->>'enabled')::boolean, true),
    coalesce((p_payload->>'sort')::integer, 0), nullif(btrim(p_payload->>'description'), ''),
    coalesce(auth.uid()::text, 'system')
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.hr_update_position_secure(p_id uuid, p_payload jsonb)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_position public.hr_position%rowtype;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:Edit', null, false) then
    raise exception 'Missing position edit permission' using errcode = '42501';
  end if;
  select * into v_position from public.hr_position where id = p_id;
  if not found or (not app_private.is_platform_super() and v_position.tenant_id <> app_private.current_user_tenant_id()) then
    raise exception '岗位不存在或无权编辑';
  end if;
  if exists (select 1 from jsonb_object_keys(p_payload) key where key <> all(array[
    'position_code','position_name','enabled','sort','description'
  ]::text[])) then
    raise exception '岗位数据包含不允许写入的字段';
  end if;
  if v_position.system_code = 'driver' and (
    coalesce((p_payload->>'enabled')::boolean, v_position.enabled) = false
    or upper(coalesce(nullif(btrim(p_payload->>'position_code'), ''), v_position.position_code)) <> v_position.position_code
  ) then
    raise exception '系统司机岗位不可停用或修改编码';
  end if;

  update public.hr_position position_row
  set position_code = upper(coalesce(nullif(btrim(p_payload->>'position_code'), ''), position_row.position_code)),
      position_name = coalesce(nullif(btrim(p_payload->>'position_name'), ''), position_row.position_name),
      enabled = coalesce((p_payload->>'enabled')::boolean, position_row.enabled),
      sort = coalesce((p_payload->>'sort')::integer, position_row.sort),
      description = case when p_payload ? 'description' then nullif(btrim(p_payload->>'description'), '') else position_row.description end,
      update_by = coalesce(auth.uid()::text, 'system'),
      update_time = now()
  where position_row.id = p_id;

  update public.hr_employee employee_row
  set job_title = position_row.position_name,
      update_time = now()
  from public.hr_position position_row
  where position_row.id = p_id
    and employee_row.position_id = position_row.id
    and employee_row.tenant_id = position_row.tenant_id;
  return true;
end;
$$;

create or replace function public.hr_delete_position_secure(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_position public.hr_position%rowtype;
begin
  if not app_private.can_execute_business_action('HrPosition', 'Hr:Position:Delete', null, false) then
    raise exception 'Missing position delete permission' using errcode = '42501';
  end if;
  select * into v_position from public.hr_position where id = p_id;
  if not found or (not app_private.is_platform_super() and v_position.tenant_id <> app_private.current_user_tenant_id()) then
    raise exception '岗位不存在或无权删除';
  end if;
  if v_position.system_code is not null then raise exception '系统岗位不可删除'; end if;
  if exists (select 1 from public.hr_employee where position_id = p_id) then
    raise exception '该岗位已有员工使用，请先调整员工岗位';
  end if;
  delete from public.hr_position where id = p_id;
  return true;
end;
$$;

create or replace function public.hr_list_driver_carrier_options_secure(p_tenant_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
begin
  if not app_private.can_execute_business_action('HrEmployeeRoster', 'Hr:Employee:Add', null, false)
     or not app_private.can_execute_business_action('TmsDriver', 'TmsDriver:Add', null, false) then
    raise exception '创建司机员工需要员工新增与司机新增权限' using errcode = '42501';
  end if;
  if not app_private.is_platform_super() then p_tenant_id := v_tenant_id; end if;
  if p_tenant_id is null then return '[]'::jsonb; end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', carrier_row.id,
      'carrier_code', carrier_row.carrier_code,
      'company_name', carrier_row.company_name
    ) order by carrier_row.company_name)
    from public.tms_carrier carrier_row
    where carrier_row.tenant_id = p_tenant_id and carrier_row.enabled
  ), '[]'::jsonb);
end;
$$;

create or replace function public.hr_create_employee_with_driver_secure(
  p_employee jsonb,
  p_driver jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_employee public.hr_employee%rowtype;
  v_position public.hr_position%rowtype;
  v_tenant_id uuid;
  v_employee_id uuid;
  v_driver_id uuid;
begin
  if not app_private.can_execute_business_action('HrEmployeeRoster', 'Hr:Employee:Add', null, false) then
    raise exception 'Missing employee create permission' using errcode = '42501';
  end if;
  if p_employee is null or jsonb_typeof(p_employee) <> 'object' then
    raise exception '员工数据格式不正确';
  end if;
  if exists (select 1 from jsonb_object_keys(p_employee) key where key <> all(array[
    'tenant_id','organization_id','employee_no','employee_name','avatar_url','position_id',
    'employment_status','employment_type','gender','birth_date','phone','email','id_card_no',
    'ethnicity','education_level','school_name','major_name','marital_status','political_status',
    'native_place','home_address','hire_date','probation_end_date','leave_date',
    'contract_start_date','contract_end_date','emergency_contact_name',
    'emergency_contact_relation','emergency_contact_phone','remark'
  ]::text[])) then
    raise exception '员工数据包含不允许写入的字段';
  end if;

  select * into v_employee from jsonb_populate_record(null::public.hr_employee, p_employee);
  v_tenant_id := case when app_private.is_platform_super()
    then v_employee.tenant_id else app_private.current_user_tenant_id() end;
  if v_tenant_id is null then raise exception '请选择员工所属租户'; end if;

  select * into v_position
  from public.hr_position position_row
  where position_row.id = v_employee.position_id
    and position_row.tenant_id = v_tenant_id
    and position_row.enabled;
  if not found then raise exception '所选岗位不存在、已停用或不属于当前租户'; end if;

  if not exists (
    select 1 from public.sys_organization organization_row
    where organization_row.id = v_employee.organization_id
      and organization_row.tenant_id = v_tenant_id
      and organization_row.status = '1'
  ) then raise exception '所选组织不存在、已停用或不属于当前租户'; end if;

  if v_position.position_kind = 'driver' then
    if not app_private.can_execute_business_action('TmsDriver', 'TmsDriver:Add', null, false) then
      raise exception '创建司机员工还需要司机新增权限' using errcode = '42501';
    end if;
    if p_driver is null or jsonb_typeof(p_driver) <> 'object' then
      raise exception '司机岗位必须补齐司机任职资料';
    end if;
    if exists (select 1 from jsonb_object_keys(p_driver) key where key <> all(array[
      'carrier_id','driver_type','license_type','license_expire_date'
    ]::text[])) then raise exception '司机任职数据包含不允许写入的字段'; end if;
    if v_employee.employment_status not in ('probation', 'active') then
      raise exception '司机岗位员工必须处于试用或在职状态';
    end if;
    if nullif(btrim(v_employee.phone), '') is null
       or nullif(btrim(v_employee.gender), '') is null
       or nullif(btrim(v_employee.id_card_no), '') is null
       or nullif(btrim(p_driver->>'carrier_id'), '') is null
       or nullif(btrim(p_driver->>'license_type'), '') is null
       or nullif(btrim(p_driver->>'license_expire_date'), '') is null then
      raise exception '司机岗位必须填写手机号、性别、身份证号、承运商、驾照类型和驾照有效期';
    end if;
  elsif p_driver is not null then
    raise exception '仅司机岗位可以提交司机任职资料';
  end if;

  insert into public.hr_employee (
    tenant_id, organization_id, employee_no, employee_name, avatar_url, position_id,
    employment_status, employment_type, gender, birth_date, phone, email, id_card_no,
    ethnicity, education_level, school_name, major_name, marital_status, political_status,
    native_place, home_address, hire_date, probation_end_date, leave_date,
    contract_start_date, contract_end_date, emergency_contact_name,
    emergency_contact_relation, emergency_contact_phone, remark, create_by
  ) values (
    v_tenant_id, v_employee.organization_id, btrim(v_employee.employee_no),
    btrim(v_employee.employee_name), v_employee.avatar_url, v_employee.position_id,
    coalesce(v_employee.employment_status, 'active'),
    coalesce(v_employee.employment_type, 'full_time'), v_employee.gender,
    v_employee.birth_date, v_employee.phone, v_employee.email, v_employee.id_card_no,
    v_employee.ethnicity, v_employee.education_level, v_employee.school_name,
    v_employee.major_name, v_employee.marital_status, v_employee.political_status,
    v_employee.native_place, v_employee.home_address, v_employee.hire_date,
    v_employee.probation_end_date, v_employee.leave_date, v_employee.contract_start_date,
    v_employee.contract_end_date, v_employee.emergency_contact_name,
    v_employee.emergency_contact_relation, v_employee.emergency_contact_phone,
    v_employee.remark, coalesce(auth.uid()::text, 'system')
  ) returning id into v_employee_id;

  if v_position.position_kind = 'driver' then
    v_driver_id := public.tms_create_driver_secure(
      p_driver || jsonb_build_object(
        'employee_id', v_employee_id,
        'driver_name', btrim(v_employee.employee_name),
        'phone', btrim(v_employee.phone),
        'gender', btrim(v_employee.gender),
        'id_card_no', btrim(v_employee.id_card_no),
        'home_address', nullif(btrim(v_employee.home_address), ''),
        'emergency_contact_name', nullif(btrim(v_employee.emergency_contact_name), ''),
        'emergency_contact_phone', nullif(btrim(v_employee.emergency_contact_phone), ''),
        'enabled', true
      )
    );
  end if;

  return jsonb_build_object('employee_id', v_employee_id, 'driver_id', v_driver_id);
end;
$$;

revoke all on function public.hr_list_positions_secure(integer, integer, text, boolean, uuid) from public, anon;
revoke all on function public.hr_list_position_options_secure(uuid, boolean) from public, anon;
revoke all on function public.hr_create_position_secure(jsonb) from public, anon;
revoke all on function public.hr_update_position_secure(uuid, jsonb) from public, anon;
revoke all on function public.hr_delete_position_secure(uuid) from public, anon;
revoke all on function public.hr_list_driver_carrier_options_secure(uuid) from public, anon;
revoke all on function public.hr_create_employee_with_driver_secure(jsonb, jsonb) from public, anon;
grant execute on function public.hr_list_positions_secure(integer, integer, text, boolean, uuid) to authenticated, service_role;
grant execute on function public.hr_list_position_options_secure(uuid, boolean) to authenticated, service_role;
grant execute on function public.hr_create_position_secure(jsonb) to authenticated, service_role;
grant execute on function public.hr_update_position_secure(uuid, jsonb) to authenticated, service_role;
grant execute on function public.hr_delete_position_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_list_driver_carrier_options_secure(uuid) to authenticated, service_role;
grant execute on function public.hr_create_employee_with_driver_secure(jsonb, jsonb) to authenticated, service_role;

insert into public.sys_menu (id, parent_id, name, path, component, type, meta, sort, create_by)
values (
  '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c01'::uuid,
  'aa71d8bd-c141-4aef-9697-8e75433de2c2'::uuid,
  'HrPosition', 'position', '/hr/personnel/position', 'menu',
  '{"icon":"ri:briefcase-4-line","link":"","roles":["R_SUPER","R_ADMIN"],"title":"岗位管理","is_hide":false,"fixed_tab":false,"is_enable":true,"is_iframe":false,"keep_alive":true,"show_badge":false,"active_path":"","is_hide_tab":false,"is_full_page":false,"show_text_badge":""}'::jsonb,
  2, 'migration'
)
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, path = excluded.path,
  component = excluded.component, type = excluded.type, meta = excluded.meta,
  sort = excluded.sort, update_by = 'migration', update_time = now();

insert into public.sys_menu (id, parent_id, name, path, component, type, meta, sort, create_by)
values
  ('7a619f4f-68c5-4ab0-97f1-7dd3a7e06c02', '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c01', 'Hr:Position:View', '', '', 'button', '{"icon":"","roles":["R_SUPER","R_ADMIN"],"title":"查看岗位","is_enable":true}', 1, 'migration'),
  ('7a619f4f-68c5-4ab0-97f1-7dd3a7e06c03', '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c01', 'Hr:Position:Add', '', '', 'button', '{"icon":"","roles":["R_SUPER","R_ADMIN"],"title":"新增岗位","is_enable":true}', 2, 'migration'),
  ('7a619f4f-68c5-4ab0-97f1-7dd3a7e06c04', '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c01', 'Hr:Position:Edit', '', '', 'button', '{"icon":"","roles":["R_SUPER","R_ADMIN"],"title":"编辑岗位","is_enable":true}', 3, 'migration'),
  ('7a619f4f-68c5-4ab0-97f1-7dd3a7e06c05', '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c01', 'Hr:Position:Delete', '', '', 'button', '{"icon":"","roles":["R_SUPER","R_ADMIN"],"title":"删除岗位","is_enable":true}', 4, 'migration')
on conflict (id) do update set
  parent_id = excluded.parent_id, name = excluded.name, type = excluded.type,
  meta = excluded.meta, sort = excluded.sort, update_by = 'migration', update_time = now();

insert into public.sys_role_menu (role_id, menu_id, tenant_id, permission, create_by)
select source.role_id, mapping.target_menu_id, source.tenant_id, '{}'::jsonb, 'migration'
from (
  values
    ('71c46d59-3f0e-410d-9f26-9f96d34163a7'::uuid, '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c01'::uuid),
    ('83d8eb9e-7de4-4609-bfee-44c4563039bc'::uuid, '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c02'::uuid),
    ('84beb6cb-b1e1-4716-b96f-279ea7b03966'::uuid, '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c03'::uuid),
    ('13502c07-24c6-49bc-b28d-6219d6778692'::uuid, '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c04'::uuid),
    ('510bfd37-1ddb-4f78-9933-1cf3a3387319'::uuid, '7a619f4f-68c5-4ab0-97f1-7dd3a7e06c05'::uuid)
) mapping(source_menu_id, target_menu_id)
join public.sys_role_menu source on source.menu_id = mapping.source_menu_id
where not exists (
  select 1 from public.sys_role_menu existing
  where existing.role_id = source.role_id
    and existing.menu_id = mapping.target_menu_id
    and existing.tenant_id = source.tenant_id
);

;
