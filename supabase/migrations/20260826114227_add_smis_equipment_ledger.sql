create unique index if not exists vehicle_supplier_id_tenant_uq
  on public.vehicle_supplier(id, tenant_id);
create unique index if not exists sys_attachment_id_tenant_uq
  on public.sys_attachment(id, tenant_id);

create table public.smis_equipment (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  category_id uuid not null,
  location_id uuid,
  using_organization_id uuid not null,
  managing_organization_id uuid not null,
  responsible_employee_id uuid,
  supplier_id uuid,
  equipment_code text not null,
  equipment_name text not null,
  equipment_short_name text,
  equipment_kind text not null default 'general',
  specification text,
  model text,
  manufacturer text,
  factory_no text,
  manufacture_date date,
  installation_date date,
  commissioning_date date,
  enable_date date,
  use_status text not null default 'in_use',
  operation_status text not null default 'normal',
  asset_status text not null default 'active',
  importance_level text not null default 'general',
  asset_original_value numeric(18, 2),
  service_life_years numeric(8, 2),
  net_value numeric(18, 2),
  fixed_asset_no text,
  erp_code text,
  electronic_tag_code text,
  qr_token uuid not null default gen_random_uuid(),
  is_major_hazard_source boolean not null default false,
  is_special_equipment boolean not null default false,
  remark text,
  status text not null default 'enabled',
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_equipment_id_tenant_unique unique (id, tenant_id),
  constraint smis_equipment_category_fkey foreign key (category_id, tenant_id)
    references public.smis_equipment_category(id, tenant_id) on delete restrict,
  constraint smis_equipment_location_fkey foreign key (location_id, tenant_id)
    references public.smis_storage_location(id, tenant_id) on delete restrict,
  constraint smis_equipment_using_organization_fkey
    foreign key (tenant_id, using_organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_equipment_managing_organization_fkey
    foreign key (tenant_id, managing_organization_id)
    references public.sys_organization(tenant_id, id) on delete restrict,
  constraint smis_equipment_responsible_employee_fkey
    foreign key (responsible_employee_id, tenant_id)
    references public.hr_employee(id, tenant_id) on delete restrict,
  constraint smis_equipment_supplier_fkey foreign key (supplier_id, tenant_id)
    references public.vehicle_supplier(id, tenant_id) on delete restrict,
  constraint smis_equipment_code_not_blank check (btrim(equipment_code) <> ''),
  constraint smis_equipment_name_not_blank check (btrim(equipment_name) <> ''),
  constraint smis_equipment_code_length check (char_length(equipment_code) <= 60),
  constraint smis_equipment_name_length check (char_length(equipment_name) <= 120),
  constraint smis_equipment_short_name_length check (
    equipment_short_name is null or char_length(equipment_short_name) <= 60
  ),
  constraint smis_equipment_kind_check check (
    equipment_kind in ('general', 'boiler', 'pressure_gauge', 'safety_valve')
  ),
  constraint smis_equipment_use_status_check check (
    use_status in ('in_use', 'stopped', 'scrapped', 'dismantled', 'installing')
  ),
  constraint smis_equipment_operation_status_check check (
    operation_status in ('normal', 'maintenance', 'fault', 'idle')
  ),
  constraint smis_equipment_asset_status_check check (
    asset_status in ('active', 'pending_disposal', 'disposed')
  ),
  constraint smis_equipment_importance_check check (
    importance_level in ('general', 'important', 'critical')
  ),
  constraint smis_equipment_status_check check (status in ('enabled', 'disabled')),
  constraint smis_equipment_asset_original_value_check check (
    asset_original_value is null or asset_original_value >= 0
  ),
  constraint smis_equipment_service_life_check check (
    service_life_years is null or service_life_years > 0
  ),
  constraint smis_equipment_net_value_check check (net_value is null or net_value >= 0),
  constraint smis_equipment_remark_length check (remark is null or char_length(remark) <= 1000)
);

comment on table public.smis_equipment is
  '跨安全、资产与设备管理系统共享的租户级设备台账主档';
comment on column public.smis_equipment.qr_token is
  '每台设备唯一二维码防猜测令牌，与设备主键共同构成二维码内容';
comment on column public.smis_equipment.equipment_kind is
  '设备类型扩展路由：通用设备、锅炉、压力表、安全阀';

create unique index smis_equipment_code_unique
  on public.smis_equipment(tenant_id, lower(btrim(equipment_code)));
create unique index smis_equipment_qr_token_unique on public.smis_equipment(qr_token);
create index smis_equipment_category_idx
  on public.smis_equipment(tenant_id, category_id, status);
create index smis_equipment_category_fk_idx
  on public.smis_equipment(category_id, tenant_id);
create index smis_equipment_location_idx
  on public.smis_equipment(tenant_id, location_id, status);
create index smis_equipment_location_fk_idx
  on public.smis_equipment(location_id, tenant_id)
  where location_id is not null;
create index smis_equipment_supplier_idx
  on public.smis_equipment(supplier_id, tenant_id)
  where supplier_id is not null;
create index smis_equipment_responsible_idx
  on public.smis_equipment(responsible_employee_id, tenant_id)
  where responsible_employee_id is not null;
create index smis_equipment_query_idx
  on public.smis_equipment(tenant_id, equipment_kind, use_status, operation_status, asset_status);
create index smis_equipment_enable_date_idx
  on public.smis_equipment(tenant_id, enable_date desc)
  where enable_date is not null;

create table public.smis_equipment_attachment (
  equipment_id uuid not null,
  attachment_id uuid not null,
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  attachment_type text not null default 'other',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_attachment_pkey primary key (equipment_id, attachment_id),
  constraint smis_equipment_attachment_equipment_fkey
    foreign key (equipment_id, tenant_id)
    references public.smis_equipment(id, tenant_id) on delete cascade,
  constraint smis_equipment_attachment_file_fkey
    foreign key (attachment_id, tenant_id)
    references public.sys_attachment(id, tenant_id) on delete restrict,
  constraint smis_equipment_attachment_type_check check (
    attachment_type in (
      'certificate', 'license', 'nameplate', 'photo', 'manual', 'inspection_report', 'other'
    )
  ),
  constraint smis_equipment_attachment_remark_length check (
    remark is null or char_length(remark) <= 500
  )
);

create index smis_equipment_attachment_equipment_idx
  on public.smis_equipment_attachment(equipment_id, tenant_id);
create index smis_equipment_attachment_file_idx
  on public.smis_equipment_attachment(attachment_id, tenant_id);

create table public.smis_equipment_inspection (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  equipment_id uuid not null,
  inspection_category_id uuid not null,
  attachment_id uuid,
  inspection_no text,
  inspection_date date not null,
  conclusion text,
  next_due_date date,
  reminder_days integer not null default 30,
  institution text,
  status text not null default 'completed',
  remark text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_inspection_tenant_fkey foreign key (tenant_id)
    references public.sys_tenant(id) on delete restrict,
  constraint smis_equipment_inspection_equipment_fkey
    foreign key (equipment_id, tenant_id)
    references public.smis_equipment(id, tenant_id) on delete cascade,
  constraint smis_equipment_inspection_category_fkey
    foreign key (inspection_category_id, tenant_id)
    references public.smis_inspection_category(id, tenant_id) on delete restrict,
  constraint smis_equipment_inspection_attachment_fkey
    foreign key (attachment_id, tenant_id)
    references public.sys_attachment(id, tenant_id) on delete restrict,
  constraint smis_equipment_inspection_status_check check (
    status in ('planned', 'completed', 'overdue', 'cancelled')
  ),
  constraint smis_equipment_inspection_reminder_check check (reminder_days between 0 and 3650),
  constraint smis_equipment_inspection_due_check check (
    next_due_date is null or next_due_date >= inspection_date
  ),
  constraint smis_equipment_inspection_remark_length check (
    remark is null or char_length(remark) <= 1000
  )
);

create index smis_equipment_inspection_equipment_idx
  on public.smis_equipment_inspection(equipment_id, tenant_id, inspection_date desc);
create index smis_equipment_inspection_category_idx
  on public.smis_equipment_inspection(inspection_category_id, tenant_id);
create index smis_equipment_inspection_due_idx
  on public.smis_equipment_inspection(tenant_id, next_due_date, status)
  where next_due_date is not null and status in ('planned', 'completed');
create index smis_equipment_inspection_attachment_idx
  on public.smis_equipment_inspection(attachment_id, tenant_id)
  where attachment_id is not null;

create table public.smis_equipment_boiler (
  equipment_id uuid primary key,
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  boiler_type text not null,
  registration_code text,
  use_certificate_no text,
  internal_no text,
  rated_evaporation numeric(12, 3),
  design_pressure numeric(12, 3),
  working_pressure numeric(12, 3),
  working_temperature numeric(12, 3),
  fuel_type text,
  purpose text,
  maintenance_organization text,
  installation_organization text,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_boiler_equipment_fkey
    foreign key (equipment_id, tenant_id)
    references public.smis_equipment(id, tenant_id) on delete cascade,
  constraint smis_equipment_boiler_type_check check (boiler_type in ('water', 'steam')),
  constraint smis_equipment_boiler_evaporation_check check (
    rated_evaporation is null or rated_evaporation >= 0
  ),
  constraint smis_equipment_boiler_design_pressure_check check (
    design_pressure is null or design_pressure >= 0
  ),
  constraint smis_equipment_boiler_working_pressure_check check (
    working_pressure is null or working_pressure >= 0
  )
);

create index smis_equipment_boiler_tenant_idx
  on public.smis_equipment_boiler(tenant_id, boiler_type);

create table public.smis_equipment_relation (
  source_equipment_id uuid not null,
  target_equipment_id uuid not null,
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  relation_type text not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  constraint smis_equipment_relation_pkey primary key (
    source_equipment_id, target_equipment_id, relation_type
  ),
  constraint smis_equipment_relation_source_fkey
    foreign key (source_equipment_id, tenant_id)
    references public.smis_equipment(id, tenant_id) on delete cascade,
  constraint smis_equipment_relation_target_fkey
    foreign key (target_equipment_id, tenant_id)
    references public.smis_equipment(id, tenant_id) on delete restrict,
  constraint smis_equipment_relation_type_check check (
    relation_type in ('pressure_gauge', 'safety_valve')
  ),
  constraint smis_equipment_relation_not_self check (source_equipment_id <> target_equipment_id)
);

create index smis_equipment_relation_source_idx
  on public.smis_equipment_relation(source_equipment_id, tenant_id);
create index smis_equipment_relation_target_idx
  on public.smis_equipment_relation(target_equipment_id, tenant_id);

create trigger smis_equipment_create_audit
before insert on public.smis_equipment
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_equipment_update_audit
before update on public.smis_equipment
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_equipment_attachment_create_audit
before insert on public.smis_equipment_attachment
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_equipment_attachment_update_audit
before update on public.smis_equipment_attachment
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_equipment_inspection_create_audit
before insert on public.smis_equipment_inspection
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_equipment_inspection_update_audit
before update on public.smis_equipment_inspection
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_equipment_boiler_create_audit
before insert on public.smis_equipment_boiler
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_equipment_boiler_update_audit
before update on public.smis_equipment_boiler
for each row execute function public.trg_set_update_time_and_by();
create trigger smis_equipment_relation_create_audit
before insert on public.smis_equipment_relation
for each row execute function public.trg_set_create_time_and_by('true', 'true');
create trigger smis_equipment_relation_update_audit
before update on public.smis_equipment_relation
for each row execute function public.trg_set_update_time_and_by();

alter table public.smis_equipment enable row level security;
alter table public.smis_equipment_attachment enable row level security;
alter table public.smis_equipment_inspection enable row level security;
alter table public.smis_equipment_boiler enable row level security;
alter table public.smis_equipment_relation enable row level security;

create policy smis_equipment_tenant_select on public.smis_equipment
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentLedger:View')))
  or (select app_private.is_platform_super())
);
create policy smis_equipment_tenant_insert on public.smis_equipment
for insert to authenticated with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Add'))
);
create policy smis_equipment_tenant_update on public.smis_equipment
for update to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Edit'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Edit'))
);
create policy smis_equipment_tenant_delete on public.smis_equipment
for delete to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Delete'))
);

create policy smis_equipment_attachment_select on public.smis_equipment_attachment
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentLedger:View')))
  or (select app_private.is_platform_super())
);
create policy smis_equipment_attachment_insert on public.smis_equipment_attachment
for insert to authenticated with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Attachment'))
);
create policy smis_equipment_attachment_update on public.smis_equipment_attachment
for update to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Attachment'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Attachment'))
);
create policy smis_equipment_attachment_delete on public.smis_equipment_attachment
for delete to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Attachment'))
);

create policy smis_equipment_inspection_select on public.smis_equipment_inspection
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentLedger:View')))
  or (select app_private.is_platform_super())
);
create policy smis_equipment_inspection_insert on public.smis_equipment_inspection
for insert to authenticated with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
);
create policy smis_equipment_inspection_update on public.smis_equipment_inspection
for update to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
);
create policy smis_equipment_inspection_delete on public.smis_equipment_inspection
for delete to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Inspection'))
);

create policy smis_equipment_boiler_select on public.smis_equipment_boiler
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentLedger:View')))
  or (select app_private.is_platform_super())
);
create policy smis_equipment_boiler_write on public.smis_equipment_boiler
for all to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Edit'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Edit'))
);
create policy smis_equipment_relation_select on public.smis_equipment_relation
for select to authenticated using (
  (tenant_id = (select app_private.current_user_tenant_id())
    and (select app_private.has_permission('SmisEquipmentLedger:View')))
  or (select app_private.is_platform_super())
);
create policy smis_equipment_relation_write on public.smis_equipment_relation
for all to authenticated using (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Edit'))
) with check (
  tenant_id = (select app_private.current_user_tenant_id())
  and (select app_private.has_permission('SmisEquipmentLedger:Edit'))
);

revoke all on table public.smis_equipment from public, anon, authenticated;
revoke all on table public.smis_equipment_boiler from public, anon, authenticated;
revoke all on table public.smis_equipment_relation from public, anon, authenticated;
grant select, insert, update, delete on table public.smis_equipment to service_role;
grant select, insert, update, delete on table public.smis_equipment_boiler to service_role;
grant select, insert, update, delete on table public.smis_equipment_relation to service_role;
grant select, insert, update, delete on table public.smis_equipment_attachment to authenticated, service_role;
grant select, insert, update, delete on table public.smis_equipment_inspection to authenticated, service_role;

create or replace function public.smis_list_equipment_ledger_secure(
  p_from integer default 0,
  p_to integer default 19,
  p_keyword text default null,
  p_category_id uuid default null,
  p_location_id uuid default null,
  p_equipment_kind text default null,
  p_model text default null,
  p_operation_status text default null,
  p_supplier_id uuid default null,
  p_importance_level text default null,
  p_enable_date_from date default null,
  p_enable_date_to date default null,
  p_asset_status text default null,
  p_use_status text default null
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
  v_model text := nullif(btrim(coalesce(p_model, '')), '');
  v_records jsonb := '[]'::jsonb;
  v_category_tree jsonb := '[]'::jsonb;
  v_location_tree jsonb := '[]'::jsonb;
  v_total bigint := 0;
  v_overview jsonb := '{}'::jsonb;
begin
  if (select auth.uid()) is null then raise exception '请先登录后再查看设备台账'; end if;
  if not app_private.has_permission('SmisEquipmentLedger:View') then
    raise exception '当前账号无权查看设备台账';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if v_tenant_id is null then raise exception '当前账号未绑定有效租户'; end if;

  with recursive category_scope as (
    select id from public.smis_equipment_category
    where tenant_id = v_tenant_id and id = p_category_id
    union all
    select child.id from public.smis_equipment_category child
    join category_scope parent on parent.id = child.parent_id
    where child.tenant_id = v_tenant_id
  ), location_scope as (
    select id from public.smis_storage_location
    where tenant_id = v_tenant_id and id = p_location_id
    union all
    select child.id from public.smis_storage_location child
    join location_scope parent on parent.id = child.parent_id
    where child.tenant_id = v_tenant_id
  )
  select count(*) into v_total
  from public.smis_equipment equipment
  where equipment.tenant_id = v_tenant_id
    and (p_category_id is null or equipment.category_id in (select id from category_scope))
    and (p_location_id is null or equipment.location_id in (select id from location_scope))
    and (p_equipment_kind is null or equipment.equipment_kind = p_equipment_kind)
    and (v_model is null or coalesce(equipment.model, '') ilike '%' || v_model || '%')
    and (p_operation_status is null or equipment.operation_status = p_operation_status)
    and (p_supplier_id is null or equipment.supplier_id = p_supplier_id)
    and (p_importance_level is null or equipment.importance_level = p_importance_level)
    and (p_enable_date_from is null or equipment.enable_date >= p_enable_date_from)
    and (p_enable_date_to is null or equipment.enable_date <= p_enable_date_to)
    and (p_asset_status is null or equipment.asset_status = p_asset_status)
    and (p_use_status is null or equipment.use_status = p_use_status)
    and (
      v_keyword is null
      or equipment.equipment_code ilike '%' || v_keyword || '%'
      or equipment.equipment_name ilike '%' || v_keyword || '%'
      or coalesce(equipment.equipment_short_name, '') ilike '%' || v_keyword || '%'
      or coalesce(equipment.specification, '') ilike '%' || v_keyword || '%'
      or coalesce(equipment.model, '') ilike '%' || v_keyword || '%'
      or coalesce(equipment.factory_no, '') ilike '%' || v_keyword || '%'
    );

  with recursive category_scope as (
    select id from public.smis_equipment_category
    where tenant_id = v_tenant_id and id = p_category_id
    union all
    select child.id from public.smis_equipment_category child
    join category_scope parent on parent.id = child.parent_id
    where child.tenant_id = v_tenant_id
  ), location_scope as (
    select id from public.smis_storage_location
    where tenant_id = v_tenant_id and id = p_location_id
    union all
    select child.id from public.smis_storage_location child
    join location_scope parent on parent.id = child.parent_id
    where child.tenant_id = v_tenant_id
  )
  select coalesce(jsonb_agg(item.payload order by item.equipment_name, item.equipment_code), '[]'::jsonb)
  into v_records
  from (
    select equipment.equipment_name, equipment.equipment_code,
      jsonb_build_object(
        'id', equipment.id,
        'categoryId', equipment.category_id,
        'locationId', equipment.location_id,
        'usingOrganizationId', equipment.using_organization_id,
        'managingOrganizationId', equipment.managing_organization_id,
        'responsibleEmployeeId', equipment.responsible_employee_id,
        'supplierId', equipment.supplier_id,
        'equipmentCode', equipment.equipment_code,
        'equipmentName', equipment.equipment_name,
        'equipmentShortName', equipment.equipment_short_name,
        'equipmentKind', equipment.equipment_kind,
        'specification', equipment.specification,
        'model', equipment.model,
        'manufacturer', equipment.manufacturer,
        'factoryNo', equipment.factory_no,
        'manufactureDate', equipment.manufacture_date,
        'installationDate', equipment.installation_date,
        'commissioningDate', equipment.commissioning_date,
        'enableDate', equipment.enable_date,
        'useStatus', equipment.use_status,
        'operationStatus', equipment.operation_status,
        'assetStatus', equipment.asset_status,
        'importanceLevel', equipment.importance_level,
        'assetOriginalValue', equipment.asset_original_value,
        'serviceLifeYears', equipment.service_life_years,
        'netValue', equipment.net_value,
        'fixedAssetNo', equipment.fixed_asset_no,
        'erpCode', equipment.erp_code,
        'electronicTagCode', equipment.electronic_tag_code,
        'qrToken', equipment.qr_token,
        'isMajorHazardSource', equipment.is_major_hazard_source,
        'isSpecialEquipment', equipment.is_special_equipment,
        'remark', equipment.remark,
        'status', equipment.status,
        'createBy', equipment.create_by,
        'createTime', equipment.create_time,
        'updateBy', equipment.update_by,
        'updateTime', equipment.update_time,
        'category', jsonb_build_object(
          'id', category.id,
          'categoryCode', category.category_code,
          'categoryName', category.category_name
        ),
        'location', case when location.id is null then null else jsonb_build_object(
          'id', location.id,
          'locationCode', location.location_code,
          'locationName', location.location_name,
          'detailLocation', location.detail_location
        ) end,
        'usingOrganization', jsonb_build_object(
          'id', using_org.id,
          'organizationCode', using_org.organization_code,
          'organizationName', using_org.organization_name
        ),
        'managingOrganization', jsonb_build_object(
          'id', managing_org.id,
          'organizationCode', managing_org.organization_code,
          'organizationName', managing_org.organization_name
        ),
        'responsible', case when employee.id is null then null else jsonb_build_object(
          'id', employee.id,
          'employeeNo', employee.employee_no,
          'employeeName', employee.employee_name,
          'jobTitle', employee.job_title,
          'employmentStatus', employee.employment_status,
          'organizationId', employee.organization_id,
          'organizationCode', employee_org.organization_code,
          'organizationName', employee_org.organization_name
        ) end,
        'supplier', case when supplier.id is null then null else jsonb_build_object(
          'id', supplier.id,
          'supplierCode', supplier.supplier_code,
          'supplierName', supplier.supplier_name
        ) end,
        'boiler', case when boiler.equipment_id is null then null else jsonb_build_object(
          'boilerType', boiler.boiler_type,
          'registrationCode', boiler.registration_code,
          'useCertificateNo', boiler.use_certificate_no,
          'internalNo', boiler.internal_no,
          'ratedEvaporation', boiler.rated_evaporation,
          'designPressure', boiler.design_pressure,
          'workingPressure', boiler.working_pressure,
          'workingTemperature', boiler.working_temperature,
          'fuelType', boiler.fuel_type,
          'purpose', boiler.purpose,
          'maintenanceOrganization', boiler.maintenance_organization,
          'installationOrganization', boiler.installation_organization
        ) end,
        'pressureGaugeIds', coalesce((
          select jsonb_agg(relation.target_equipment_id order by relation.target_equipment_id)
          from public.smis_equipment_relation relation
          where relation.tenant_id = v_tenant_id
            and relation.source_equipment_id = equipment.id
            and relation.relation_type = 'pressure_gauge'
        ), '[]'::jsonb),
        'safetyValveIds', coalesce((
          select jsonb_agg(relation.target_equipment_id order by relation.target_equipment_id)
          from public.smis_equipment_relation relation
          where relation.tenant_id = v_tenant_id
            and relation.source_equipment_id = equipment.id
            and relation.relation_type = 'safety_valve'
        ), '[]'::jsonb),
        'attachmentCount', (
          select count(*) from public.smis_equipment_attachment attachment
          where attachment.tenant_id = v_tenant_id and attachment.equipment_id = equipment.id
        ),
        'inspectionCount', (
          select count(*) from public.smis_equipment_inspection inspection
          where inspection.tenant_id = v_tenant_id and inspection.equipment_id = equipment.id
        ),
        'nextInspectionDueDate', (
          select min(inspection.next_due_date)
          from public.smis_equipment_inspection inspection
          where inspection.tenant_id = v_tenant_id
            and inspection.equipment_id = equipment.id
            and inspection.next_due_date is not null
            and inspection.status in ('planned', 'completed')
        )
      ) as payload
    from public.smis_equipment equipment
    join public.smis_equipment_category category
      on category.tenant_id = equipment.tenant_id and category.id = equipment.category_id
    left join public.smis_storage_location location
      on location.tenant_id = equipment.tenant_id and location.id = equipment.location_id
    join public.sys_organization using_org
      on using_org.tenant_id = equipment.tenant_id and using_org.id = equipment.using_organization_id
    join public.sys_organization managing_org
      on managing_org.tenant_id = equipment.tenant_id and managing_org.id = equipment.managing_organization_id
    left join public.hr_employee employee
      on employee.tenant_id = equipment.tenant_id and employee.id = equipment.responsible_employee_id
    left join public.sys_organization employee_org
      on employee_org.tenant_id = employee.tenant_id and employee_org.id = employee.organization_id
    left join public.vehicle_supplier supplier
      on supplier.tenant_id = equipment.tenant_id and supplier.id = equipment.supplier_id
    left join public.smis_equipment_boiler boiler
      on boiler.tenant_id = equipment.tenant_id and boiler.equipment_id = equipment.id
    where equipment.tenant_id = v_tenant_id
      and (p_category_id is null or equipment.category_id in (select id from category_scope))
      and (p_location_id is null or equipment.location_id in (select id from location_scope))
      and (p_equipment_kind is null or equipment.equipment_kind = p_equipment_kind)
      and (v_model is null or coalesce(equipment.model, '') ilike '%' || v_model || '%')
      and (p_operation_status is null or equipment.operation_status = p_operation_status)
      and (p_supplier_id is null or equipment.supplier_id = p_supplier_id)
      and (p_importance_level is null or equipment.importance_level = p_importance_level)
      and (p_enable_date_from is null or equipment.enable_date >= p_enable_date_from)
      and (p_enable_date_to is null or equipment.enable_date <= p_enable_date_to)
      and (p_asset_status is null or equipment.asset_status = p_asset_status)
      and (p_use_status is null or equipment.use_status = p_use_status)
      and (
        v_keyword is null
        or equipment.equipment_code ilike '%' || v_keyword || '%'
        or equipment.equipment_name ilike '%' || v_keyword || '%'
        or coalesce(equipment.equipment_short_name, '') ilike '%' || v_keyword || '%'
        or coalesce(equipment.specification, '') ilike '%' || v_keyword || '%'
        or coalesce(equipment.model, '') ilike '%' || v_keyword || '%'
        or coalesce(equipment.factory_no, '') ilike '%' || v_keyword || '%'
      )
    order by equipment.equipment_name, equipment.equipment_code
    offset v_from limit v_limit
  ) item;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', category.id,
    'parentId', category.parent_id,
    'categoryCode', category.category_code,
    'categoryName', category.category_name,
    'status', category.status,
    'childCount', (
      select count(*) from public.smis_equipment_category child
      where child.tenant_id = v_tenant_id and child.parent_id = category.id
    )
  ) order by category.category_name), '[]'::jsonb)
  into v_category_tree
  from public.smis_equipment_category category
  where category.tenant_id = v_tenant_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', location.id,
    'parentId', location.parent_id,
    'locationCode', location.location_code,
    'locationName', location.location_name,
    'status', location.status,
    'childCount', (
      select count(*) from public.smis_storage_location child
      where child.tenant_id = v_tenant_id and child.parent_id = location.id
    )
  ) order by location.location_name), '[]'::jsonb)
  into v_location_tree
  from public.smis_storage_location location
  where location.tenant_id = v_tenant_id;

  select jsonb_build_object(
    'total', count(*),
    'inUse', count(*) filter (where use_status = 'in_use'),
    'boilerCount', count(*) filter (where equipment_kind = 'boiler'),
    'dueSoon', (
      select count(distinct inspection.equipment_id)
      from public.smis_equipment_inspection inspection
      where inspection.tenant_id = v_tenant_id
        and inspection.status in ('planned', 'completed')
        and inspection.next_due_date between current_date and current_date + 30
    )
  ) into v_overview
  from public.smis_equipment
  where tenant_id = v_tenant_id;

  return jsonb_build_object(
    'records', v_records,
    'total', v_total,
    'categoryTree', v_category_tree,
    'locationTree', v_location_tree,
    'overview', v_overview
  );
end;
$$;

create or replace function public.smis_save_equipment_ledger_secure(
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
  v_category_id uuid := nullif(p_payload ->> 'category_id', '')::uuid;
  v_location_id uuid := nullif(p_payload ->> 'location_id', '')::uuid;
  v_using_organization_id uuid := nullif(p_payload ->> 'using_organization_id', '')::uuid;
  v_managing_organization_id uuid := nullif(p_payload ->> 'managing_organization_id', '')::uuid;
  v_responsible_employee_id uuid := nullif(p_payload ->> 'responsible_employee_id', '')::uuid;
  v_supplier_id uuid := nullif(p_payload ->> 'supplier_id', '')::uuid;
  v_equipment_code text := upper(btrim(coalesce(p_payload ->> 'equipment_code', '')));
  v_equipment_name text := btrim(coalesce(p_payload ->> 'equipment_name', ''));
  v_equipment_short_name text := nullif(btrim(coalesce(p_payload ->> 'equipment_short_name', '')), '');
  v_equipment_kind text := coalesce(nullif(p_payload ->> 'equipment_kind', ''), 'general');
  v_use_status text := coalesce(nullif(p_payload ->> 'use_status', ''), 'in_use');
  v_operation_status text := coalesce(nullif(p_payload ->> 'operation_status', ''), 'normal');
  v_asset_status text := coalesce(nullif(p_payload ->> 'asset_status', ''), 'active');
  v_importance_level text := coalesce(nullif(p_payload ->> 'importance_level', ''), 'general');
  v_status text := coalesce(nullif(p_payload ->> 'status', ''), 'enabled');
  v_result_id uuid;
  v_boiler jsonb := coalesce(p_payload -> 'boiler', '{}'::jsonb);
  v_pressure_gauge_ids uuid[];
  v_safety_valve_ids uuid[];
begin
  if (select auth.uid()) is null then raise exception '请先登录后再维护设备台账'; end if;
  if p_id is null and not app_private.has_permission('SmisEquipmentLedger:Add') then
    raise exception '当前账号无权新增设备';
  end if;
  if p_id is not null and not app_private.has_permission('SmisEquipmentLedger:Edit') then
    raise exception '当前账号无权编辑设备';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  if v_tenant_id is null then raise exception '当前账号未绑定有效租户'; end if;

  if v_equipment_name = '' then raise exception '请输入设备名称'; end if;
  if char_length(v_equipment_name) > 120 then raise exception '设备名称不能超过120个字符'; end if;
  if v_category_id is null then raise exception '请选择设备分类'; end if;
  if v_using_organization_id is null then raise exception '请选择使用部门'; end if;
  if v_managing_organization_id is null then raise exception '请选择管理部门'; end if;
  if v_equipment_kind not in ('general', 'boiler', 'pressure_gauge', 'safety_valve') then
    raise exception '设备类型不合法';
  end if;
  if v_use_status not in ('in_use', 'stopped', 'scrapped', 'dismantled', 'installing') then
    raise exception '使用状态不合法';
  end if;
  if v_operation_status not in ('normal', 'maintenance', 'fault', 'idle') then
    raise exception '运行状态不合法';
  end if;
  if v_asset_status not in ('active', 'pending_disposal', 'disposed') then
    raise exception '资产状态不合法';
  end if;
  if v_importance_level not in ('general', 'important', 'critical') then
    raise exception '重要级别不合法';
  end if;
  if v_status not in ('enabled', 'disabled') then raise exception '启用状态不合法'; end if;

  if not exists (
    select 1 from public.smis_equipment_category
    where id = v_category_id and tenant_id = v_tenant_id
      and (p_id is not null or status = 'enabled')
  ) then raise exception '所选设备分类不存在、已停用或不属于当前租户'; end if;
  if v_location_id is not null and not exists (
    select 1 from public.smis_storage_location
    where id = v_location_id and tenant_id = v_tenant_id
      and (p_id is not null or status = 'enabled')
  ) then raise exception '所选安装位置不存在、已停用或不属于当前租户'; end if;
  if not exists (
    select 1 from public.sys_organization
    where id = v_using_organization_id and tenant_id = v_tenant_id
  ) then raise exception '所选使用部门不存在或不属于当前租户'; end if;
  if not exists (
    select 1 from public.sys_organization
    where id = v_managing_organization_id and tenant_id = v_tenant_id
  ) then raise exception '所选管理部门不存在或不属于当前租户'; end if;
  if v_responsible_employee_id is not null and not exists (
    select 1 from public.hr_employee
    where id = v_responsible_employee_id and tenant_id = v_tenant_id
  ) then raise exception '所选运行负责人不存在或不属于当前租户'; end if;
  if v_supplier_id is not null and not exists (
    select 1 from public.vehicle_supplier
    where id = v_supplier_id and tenant_id = v_tenant_id
  ) then raise exception '所选供应商不存在或不属于当前租户'; end if;

  if p_id is null then
    if v_equipment_code = '' then
      v_equipment_code := app_private.next_document_number('smis.equipment', v_tenant_id);
    end if;
  else
    select equipment_code into v_equipment_code
    from public.smis_equipment
    where id = p_id and tenant_id = v_tenant_id
    for update;
    if not found then raise exception '待编辑设备不存在或无权访问'; end if;
  end if;
  if char_length(v_equipment_code) > 60 then raise exception '设备编码不能超过60个字符'; end if;
  if exists (
    select 1 from public.smis_equipment
    where tenant_id = v_tenant_id
      and lower(btrim(equipment_code)) = lower(v_equipment_code)
      and (p_id is null or id <> p_id)
  ) then raise exception '设备编码已存在'; end if;

  if p_id is null then
    insert into public.smis_equipment(
      tenant_id, category_id, location_id, using_organization_id, managing_organization_id,
      responsible_employee_id, supplier_id, equipment_code, equipment_name,
      equipment_short_name, equipment_kind, specification, model, manufacturer, factory_no,
      manufacture_date, installation_date, commissioning_date, enable_date,
      use_status, operation_status, asset_status, importance_level,
      asset_original_value, service_life_years, net_value, fixed_asset_no, erp_code,
      electronic_tag_code, is_major_hazard_source, is_special_equipment, remark, status
    ) values (
      v_tenant_id, v_category_id, v_location_id, v_using_organization_id,
      v_managing_organization_id, v_responsible_employee_id, v_supplier_id,
      v_equipment_code, v_equipment_name, v_equipment_short_name, v_equipment_kind,
      nullif(btrim(p_payload ->> 'specification'), ''), nullif(btrim(p_payload ->> 'model'), ''),
      nullif(btrim(p_payload ->> 'manufacturer'), ''), nullif(btrim(p_payload ->> 'factory_no'), ''),
      nullif(p_payload ->> 'manufacture_date', '')::date,
      nullif(p_payload ->> 'installation_date', '')::date,
      nullif(p_payload ->> 'commissioning_date', '')::date,
      nullif(p_payload ->> 'enable_date', '')::date,
      v_use_status, v_operation_status, v_asset_status, v_importance_level,
      nullif(p_payload ->> 'asset_original_value', '')::numeric,
      nullif(p_payload ->> 'service_life_years', '')::numeric,
      nullif(p_payload ->> 'net_value', '')::numeric,
      nullif(btrim(p_payload ->> 'fixed_asset_no'), ''),
      nullif(btrim(p_payload ->> 'erp_code'), ''),
      nullif(btrim(p_payload ->> 'electronic_tag_code'), ''),
      coalesce((p_payload ->> 'is_major_hazard_source')::boolean, false),
      coalesce((p_payload ->> 'is_special_equipment')::boolean, false),
      nullif(btrim(p_payload ->> 'remark'), ''), v_status
    ) returning id into v_result_id;
  else
    update public.smis_equipment set
      category_id = v_category_id,
      location_id = v_location_id,
      using_organization_id = v_using_organization_id,
      managing_organization_id = v_managing_organization_id,
      responsible_employee_id = v_responsible_employee_id,
      supplier_id = v_supplier_id,
      equipment_name = v_equipment_name,
      equipment_short_name = v_equipment_short_name,
      equipment_kind = v_equipment_kind,
      specification = nullif(btrim(p_payload ->> 'specification'), ''),
      model = nullif(btrim(p_payload ->> 'model'), ''),
      manufacturer = nullif(btrim(p_payload ->> 'manufacturer'), ''),
      factory_no = nullif(btrim(p_payload ->> 'factory_no'), ''),
      manufacture_date = nullif(p_payload ->> 'manufacture_date', '')::date,
      installation_date = nullif(p_payload ->> 'installation_date', '')::date,
      commissioning_date = nullif(p_payload ->> 'commissioning_date', '')::date,
      enable_date = nullif(p_payload ->> 'enable_date', '')::date,
      use_status = v_use_status,
      operation_status = v_operation_status,
      asset_status = v_asset_status,
      importance_level = v_importance_level,
      asset_original_value = nullif(p_payload ->> 'asset_original_value', '')::numeric,
      service_life_years = nullif(p_payload ->> 'service_life_years', '')::numeric,
      net_value = nullif(p_payload ->> 'net_value', '')::numeric,
      fixed_asset_no = nullif(btrim(p_payload ->> 'fixed_asset_no'), ''),
      erp_code = nullif(btrim(p_payload ->> 'erp_code'), ''),
      electronic_tag_code = nullif(btrim(p_payload ->> 'electronic_tag_code'), ''),
      is_major_hazard_source = coalesce((p_payload ->> 'is_major_hazard_source')::boolean, false),
      is_special_equipment = coalesce((p_payload ->> 'is_special_equipment')::boolean, false),
      remark = nullif(btrim(p_payload ->> 'remark'), ''),
      status = v_status
    where id = p_id and tenant_id = v_tenant_id
    returning id into v_result_id;
  end if;

  if v_equipment_kind = 'boiler' then
    if coalesce(v_boiler ->> 'boiler_type', '') not in ('water', 'steam') then
      raise exception '请选择锅炉种类';
    end if;
    insert into public.smis_equipment_boiler(
      equipment_id, tenant_id, boiler_type, registration_code, use_certificate_no,
      internal_no, rated_evaporation, design_pressure, working_pressure,
      working_temperature, fuel_type, purpose, maintenance_organization,
      installation_organization
    ) values (
      v_result_id, v_tenant_id, v_boiler ->> 'boiler_type',
      nullif(btrim(v_boiler ->> 'registration_code'), ''),
      nullif(btrim(v_boiler ->> 'use_certificate_no'), ''),
      nullif(btrim(v_boiler ->> 'internal_no'), ''),
      nullif(v_boiler ->> 'rated_evaporation', '')::numeric,
      nullif(v_boiler ->> 'design_pressure', '')::numeric,
      nullif(v_boiler ->> 'working_pressure', '')::numeric,
      nullif(v_boiler ->> 'working_temperature', '')::numeric,
      nullif(btrim(v_boiler ->> 'fuel_type'), ''),
      nullif(btrim(v_boiler ->> 'purpose'), ''),
      nullif(btrim(v_boiler ->> 'maintenance_organization'), ''),
      nullif(btrim(v_boiler ->> 'installation_organization'), '')
    )
    on conflict (equipment_id) do update set
      boiler_type = excluded.boiler_type,
      registration_code = excluded.registration_code,
      use_certificate_no = excluded.use_certificate_no,
      internal_no = excluded.internal_no,
      rated_evaporation = excluded.rated_evaporation,
      design_pressure = excluded.design_pressure,
      working_pressure = excluded.working_pressure,
      working_temperature = excluded.working_temperature,
      fuel_type = excluded.fuel_type,
      purpose = excluded.purpose,
      maintenance_organization = excluded.maintenance_organization,
      installation_organization = excluded.installation_organization;
  else
    delete from public.smis_equipment_boiler
    where equipment_id = v_result_id and tenant_id = v_tenant_id;
  end if;

  select array_agg(value::uuid) into v_pressure_gauge_ids
  from jsonb_array_elements_text(coalesce(p_payload -> 'pressure_gauge_ids', '[]'::jsonb)) value;
  select array_agg(value::uuid) into v_safety_valve_ids
  from jsonb_array_elements_text(coalesce(p_payload -> 'safety_valve_ids', '[]'::jsonb)) value;

  if exists (
    select 1 from public.smis_equipment
    where id = any(coalesce(v_pressure_gauge_ids, '{}'::uuid[]))
      and (tenant_id <> v_tenant_id or equipment_kind <> 'pressure_gauge')
  ) or (
    select count(*) from public.smis_equipment
    where tenant_id = v_tenant_id and equipment_kind = 'pressure_gauge'
      and id = any(coalesce(v_pressure_gauge_ids, '{}'::uuid[]))
  ) <> cardinality(coalesce(v_pressure_gauge_ids, '{}'::uuid[])) then
    raise exception '所选压力表不存在或类型不正确';
  end if;
  if exists (
    select 1 from public.smis_equipment
    where id = any(coalesce(v_safety_valve_ids, '{}'::uuid[]))
      and (tenant_id <> v_tenant_id or equipment_kind <> 'safety_valve')
  ) or (
    select count(*) from public.smis_equipment
    where tenant_id = v_tenant_id and equipment_kind = 'safety_valve'
      and id = any(coalesce(v_safety_valve_ids, '{}'::uuid[]))
  ) <> cardinality(coalesce(v_safety_valve_ids, '{}'::uuid[])) then
    raise exception '所选安全阀不存在或类型不正确';
  end if;

  delete from public.smis_equipment_relation
  where source_equipment_id = v_result_id and tenant_id = v_tenant_id;
  insert into public.smis_equipment_relation(
    source_equipment_id, target_equipment_id, tenant_id, relation_type
  )
  select v_result_id, id, v_tenant_id, 'pressure_gauge'
  from unnest(coalesce(v_pressure_gauge_ids, '{}'::uuid[])) id;
  insert into public.smis_equipment_relation(
    source_equipment_id, target_equipment_id, tenant_id, relation_type
  )
  select v_result_id, id, v_tenant_id, 'safety_valve'
  from unnest(coalesce(v_safety_valve_ids, '{}'::uuid[])) id;

  return v_result_id;
end;
$$;

create or replace function public.smis_delete_equipment_ledger_secure(p_ids uuid[])
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
  if (select auth.uid()) is null then raise exception '请先登录后再删除设备'; end if;
  if not app_private.has_permission('SmisEquipmentLedger:Delete') then
    raise exception '当前账号无权删除设备';
  end if;
  v_tenant_id := app_private.current_user_tenant_id();
  select array_agg(distinct id) into v_ids from unnest(coalesce(p_ids, '{}'::uuid[])) id;
  if coalesce(cardinality(v_ids), 0) = 0 then raise exception '请选择要删除的设备'; end if;
  if (select count(*) from public.smis_equipment where tenant_id = v_tenant_id and id = any(v_ids))
      <> cardinality(v_ids) then raise exception '部分设备不存在或无权删除'; end if;
  if exists (
    select 1 from public.smis_equipment_relation
    where tenant_id = v_tenant_id
      and target_equipment_id = any(v_ids)
      and not (source_equipment_id = any(v_ids))
  ) then raise exception '设备已被其他设备关联，请先解除压力表或安全阀关系'; end if;

  delete from public.smis_equipment
  where tenant_id = v_tenant_id and id = any(v_ids);
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function public.smis_list_equipment_ledger_secure(
  integer, integer, text, uuid, uuid, text, text, text, uuid, text, date, date, text, text
) from public, anon;
revoke all on function public.smis_save_equipment_ledger_secure(uuid, jsonb) from public, anon;
revoke all on function public.smis_delete_equipment_ledger_secure(uuid[]) from public, anon;
grant execute on function public.smis_list_equipment_ledger_secure(
  integer, integer, text, uuid, uuid, text, text, text, uuid, text, date, date, text, text
) to authenticated, service_role;
grant execute on function public.smis_save_equipment_ledger_secure(uuid, jsonb)
  to authenticated, service_role;
grant execute on function public.smis_delete_equipment_ledger_secure(uuid[])
  to authenticated, service_role;

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
)
insert into public.sys_document_number_scene(
  rule_key, rule_name, field_label, category, menu_id, target_table, target_column,
  default_template, default_reset_cycle, manual_required, enabled, remark,
  create_by, update_by, tenant_id
)
select 'smis.equipment', '设备编码', '设备编码', 'master_data',
  'a1530000-0000-4000-8000-000000000016'::uuid,
  'smis_equipment', 'equipment_code', 'SB{YYYY}-{SEQ:6}', 'year', false, true,
  '设备台账编码；默认按年度重置六位流水，可在编号规则中心按租户配置',
  'number-engine', 'number-engine', platform_tenant.id
from platform_tenant
on conflict (rule_key) do update set
  rule_name = excluded.rule_name,
  field_label = excluded.field_label,
  category = excluded.category,
  menu_id = excluded.menu_id,
  target_table = excluded.target_table,
  target_column = excluded.target_column,
  default_template = excluded.default_template,
  default_reset_cycle = excluded.default_reset_cycle,
  manual_required = excluded.manual_required,
  enabled = excluded.enabled,
  remark = excluded.remark,
  update_by = excluded.update_by,
  update_time = now();

insert into public.sys_document_number_rule(
  tenant_id, rule_key, rule_name, category, target_table, target_column,
  auto_enabled, template, reset_cycle, sequence_start, timezone, manual_required,
  builtin, enabled, remark, create_by, update_by
)
select tenant.id, 'smis.equipment', '设备编码', 'master_data',
  'smis_equipment', 'equipment_code', true, 'SB{YYYY}-{SEQ:6}', 'year', 1,
  'Asia/Shanghai', false, true, true,
  '设备台账默认编号规则，可按租户在编号规则中心调整', 'number-engine', 'number-engine'
from public.sys_tenant tenant
on conflict (tenant_id, rule_key) do nothing;

create or replace function app_private.trg_seed_smis_equipment_number_rule()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.sys_document_number_rule(
    tenant_id, rule_key, rule_name, category, target_table, target_column,
    auto_enabled, template, reset_cycle, sequence_start, timezone, manual_required,
    builtin, enabled, remark, create_by, update_by
  ) values (
    new.id, 'smis.equipment', '设备编码', 'master_data',
    'smis_equipment', 'equipment_code', true, 'SB{YYYY}-{SEQ:6}', 'year', 1,
    'Asia/Shanghai', false, true, true,
    '设备台账默认编号规则，可按租户在编号规则中心调整', 'number-engine', 'number-engine'
  ) on conflict (tenant_id, rule_key) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_seed_smis_equipment_number_rule on public.sys_tenant;
create trigger trg_seed_smis_equipment_number_rule
after insert on public.sys_tenant
for each row execute function app_private.trg_seed_smis_equipment_number_rule();

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), dictionary_types(name, code, remark, sort) as (values
  ('设备类型', 'smisEquipmentKind', '设备台账主档类型', 10),
  ('设备使用状态', 'smisEquipmentUseStatus', '设备使用生命周期状态', 11),
  ('设备运行状态', 'smisEquipmentOperationStatus', '设备当前运行状态', 12),
  ('设备资产状态', 'smisEquipmentAssetStatus', '设备资产管理状态', 13),
  ('设备重要级别', 'smisEquipmentImportanceLevel', '设备重要性分级', 14),
  ('设备启用状态', 'smisEquipmentStatus', '设备台账启停状态', 15),
  ('锅炉种类', 'smisBoilerType', '锅炉设备介质分类', 16),
  ('设备检验状态', 'smisEquipmentInspectionStatus', '设备检验计划与完成状态', 17),
  ('设备附件类型', 'smisEquipmentAttachmentType', '设备全生命周期附件分类', 18)
)
insert into public.sys_dict_type(
  id, name, code, status, create_by, update_by, remark,
  tenant_id, parent_id, node_type, sort
)
select gen_random_uuid(), dictionary_types.name, dictionary_types.code, '1',
  '624944977@qq.com', '624944977@qq.com', dictionary_types.remark,
  platform_tenant.id,
  (select id from public.sys_dict_type where code = 'smisEquipmentLedger' limit 1),
  'dictionary', dictionary_types.sort
from dictionary_types cross join platform_tenant
on conflict (code) do update set
  name = excluded.name,
  status = excluded.status,
  remark = excluded.remark,
  parent_id = excluded.parent_id,
  sort = excluded.sort,
  update_by = excluded.update_by,
  update_time = now();

with platform_tenant as (
  select id from public.sys_tenant where tenant_code = 'platform' limit 1
), items(type_code, value, label, sort, tag_type, remark) as (values
  ('smisEquipmentKind', 'general', '通用设备', 1, 'info', '未使用专用扩展表的设备'),
  ('smisEquipmentKind', 'boiler', '锅炉', 2, 'warning', '使用锅炉扩展字段并可关联压力表、安全阀'),
  ('smisEquipmentKind', 'pressure_gauge', '压力表', 3, 'primary', '可作为锅炉安全附件被关联'),
  ('smisEquipmentKind', 'safety_valve', '安全阀', 4, 'danger', '可作为锅炉安全附件被关联'),
  ('smisEquipmentUseStatus', 'in_use', '在用', 1, 'success', null),
  ('smisEquipmentUseStatus', 'stopped', '停用', 2, 'info', null),
  ('smisEquipmentUseStatus', 'scrapped', '报废', 3, 'danger', null),
  ('smisEquipmentUseStatus', 'dismantled', '拆除', 4, 'warning', null),
  ('smisEquipmentUseStatus', 'installing', '安装中', 5, 'primary', null),
  ('smisEquipmentOperationStatus', 'normal', '正常', 1, 'success', null),
  ('smisEquipmentOperationStatus', 'maintenance', '检修中', 2, 'warning', null),
  ('smisEquipmentOperationStatus', 'fault', '故障', 3, 'danger', null),
  ('smisEquipmentOperationStatus', 'idle', '闲置', 4, 'info', null),
  ('smisEquipmentAssetStatus', 'active', '在账', 1, 'success', null),
  ('smisEquipmentAssetStatus', 'pending_disposal', '待处置', 2, 'warning', null),
  ('smisEquipmentAssetStatus', 'disposed', '已处置', 3, 'info', null),
  ('smisEquipmentImportanceLevel', 'general', '一般', 1, 'info', null),
  ('smisEquipmentImportanceLevel', 'important', '重要', 2, 'warning', null),
  ('smisEquipmentImportanceLevel', 'critical', '关键', 3, 'danger', null),
  ('smisEquipmentStatus', 'enabled', '启用', 1, 'success', null),
  ('smisEquipmentStatus', 'disabled', '停用', 2, 'info', null),
  ('smisBoilerType', 'water', '热水锅炉', 1, 'primary', '以热水为工作介质'),
  ('smisBoilerType', 'steam', '蒸汽锅炉', 2, 'warning', '以蒸汽为工作介质'),
  ('smisEquipmentInspectionStatus', 'planned', '待检验', 1, 'primary', null),
  ('smisEquipmentInspectionStatus', 'completed', '已完成', 2, 'success', null),
  ('smisEquipmentInspectionStatus', 'overdue', '已逾期', 3, 'danger', null),
  ('smisEquipmentInspectionStatus', 'cancelled', '已取消', 4, 'info', null),
  ('smisEquipmentAttachmentType', 'certificate', '合格证', 1, 'success', null),
  ('smisEquipmentAttachmentType', 'license', '使用证', 2, 'primary', null),
  ('smisEquipmentAttachmentType', 'nameplate', '铭牌', 3, 'info', null),
  ('smisEquipmentAttachmentType', 'photo', '设备照片', 4, 'primary', null),
  ('smisEquipmentAttachmentType', 'manual', '使用说明书', 5, 'info', null),
  ('smisEquipmentAttachmentType', 'inspection_report', '检验报告', 6, 'warning', null),
  ('smisEquipmentAttachmentType', 'other', '其他', 7, 'info', null)
)
insert into public.sys_dictionary(
  id, type_id, code, status, create_by, update_by, remark,
  value, label, tenant_id, tag_type, sort
)
select gen_random_uuid(), dictionary_type.id,
  items.type_code || '_' || items.value, '1',
  '624944977@qq.com', '624944977@qq.com', items.remark,
  items.value, items.label, platform_tenant.id, items.tag_type, items.sort
from items
join public.sys_dict_type dictionary_type on dictionary_type.code = items.type_code
cross join platform_tenant
where not exists (
  select 1 from public.sys_dictionary existing
  where existing.type_id = dictionary_type.id and existing.value = items.value
);

insert into public.sys_menu(
  id, parent_id, name, path, component, meta, sort, type, app_code, create_by, update_by
)
select seed.id, 'a1530000-0000-4000-8000-000000000016'::uuid,
  seed.name, '', '',
  jsonb_build_object(
    'title', seed.title, 'icon', '', 'is_hide', true,
    'is_enable', true, 'roles', jsonb_build_array()
  ), seed.sort, 'button', 'smis', '624944977@qq.com', '624944977@qq.com'
from (values
  ('a1530000-0000-4000-8160-000000000001'::uuid, 'SmisEquipmentLedger:View', '查看设备台账', 1),
  ('a1530000-0000-4000-8160-000000000002'::uuid, 'SmisEquipmentLedger:Add', '新增设备', 2),
  ('a1530000-0000-4000-8160-000000000003'::uuid, 'SmisEquipmentLedger:Edit', '编辑设备', 3),
  ('a1530000-0000-4000-8160-000000000004'::uuid, 'SmisEquipmentLedger:Delete', '删除设备', 4),
  ('a1530000-0000-4000-8160-000000000005'::uuid, 'SmisEquipmentLedger:Attachment', '维护设备附件', 5),
  ('a1530000-0000-4000-8160-000000000006'::uuid, 'SmisEquipmentLedger:Inspection', '维护设备检验', 6)
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
  ('a1530000-0000-4000-8160-000000000001'::uuid),
  ('a1530000-0000-4000-8160-000000000002'::uuid),
  ('a1530000-0000-4000-8160-000000000003'::uuid),
  ('a1530000-0000-4000-8160-000000000004'::uuid),
  ('a1530000-0000-4000-8160-000000000005'::uuid),
  ('a1530000-0000-4000-8160-000000000006'::uuid)
) button(id)
where page_grant.menu_id = 'a1530000-0000-4000-8000-000000000016'::uuid
on conflict (role_id, menu_id) do nothing;

;
