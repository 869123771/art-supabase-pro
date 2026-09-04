begin;

do $$
declare
  source_name text;
  target_name text;
begin
  for source_name, target_name in
    select *
    from (
      values
        ('tms_station', 'mdm_station'),
        ('tms_cargo', 'mdm_cargo'),
        ('vehicle_archive', 'mdm_vehicle'),
        ('vehicle_parts_category', 'mdm_part_category'),
        ('vehicle_parts', 'mdm_part'),
        ('smis_site', 'mdm_site'),
        ('smis_storage_location', 'mdm_storage_location'),
        ('smis_equipment_category', 'mdm_equipment_category'),
        ('smis_equipment', 'mdm_equipment'),
        ('smis_material_category', 'mdm_material_category'),
        ('smis_material', 'mdm_material')
    ) as rename_map(source_name, target_name)
  loop
    if to_regclass(format('public.%I', source_name)) is null then
      raise exception 'MDM migration source table public.% does not exist', source_name;
    end if;

    if to_regclass(format('public.%I', target_name)) is not null then
      raise exception 'MDM migration target public.% already exists', target_name;
    end if;
  end loop;
end;
$$;

alter table public.tms_station rename to mdm_station;
alter table public.tms_cargo rename to mdm_cargo;
alter table public.vehicle_archive rename to mdm_vehicle;
alter table public.vehicle_parts_category rename to mdm_part_category;
alter table public.vehicle_parts rename to mdm_part;
alter table public.smis_site rename to mdm_site;
alter table public.smis_storage_location rename to mdm_storage_location;
alter table public.smis_equipment_category rename to mdm_equipment_category;
alter table public.smis_equipment rename to mdm_equipment;
alter table public.smis_material_category rename to mdm_material_category;
alter table public.smis_material rename to mdm_material;

comment on table public.mdm_station is
  'MDM 运输站点主数据；供线路、订单、运单与站点能力配置统一引用。';
comment on table public.mdm_cargo is
  'MDM 货物主数据；供合同、价格、订单和运单统一引用。';
comment on table public.mdm_vehicle is
  'MDM 车辆主数据；供 VMS、TMS、FMS 与安全业务统一引用。';
comment on table public.mdm_part_category is
  'MDM 零部件分类主数据；租户级树形分类。';
comment on table public.mdm_part is
  'MDM 零部件主数据；连接分类、供应商与维护业务。';
comment on table public.mdm_site is
  'MDM 场所主数据；连接组织、负责人、行政区域和空间坐标。';
comment on table public.mdm_storage_location is
  'MDM 存放位置主数据；租户级树形库位和设备位置。';
comment on table public.mdm_equipment_category is
  'MDM 设备分类主数据；跨安全、资产与设备管理应用复用。';
comment on table public.mdm_equipment is
  'MDM 设备主数据；跨安全、资产与设备管理应用共享的设备台账。';
comment on table public.mdm_material_category is
  'MDM 物料分类主数据；租户级树形物料分类。';
comment on table public.mdm_material is
  'MDM 物料主数据；供劳保、工器具、危废及其他领用业务统一引用。';

do $$
declare
  routine record;
  rewritten_definition text;
begin
  for routine in
    select procedure.oid, pg_get_functiondef(procedure.oid) as definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.prokind in ('f', 'p')
      and procedure.prosrc ~
        '\m(tms_station|tms_cargo|vehicle_archive|vehicle_parts_category|vehicle_parts|smis_site|smis_storage_location|smis_equipment_category|smis_equipment|smis_material_category|smis_material)\M'
  loop
    rewritten_definition := routine.definition;
    rewritten_definition := regexp_replace(rewritten_definition, '\mtms_station\M', 'mdm_station', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mtms_cargo\M', 'mdm_cargo', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mvehicle_archive\M', 'mdm_vehicle', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mvehicle_parts_category\M', 'mdm_part_category', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mvehicle_parts\M', 'mdm_part', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\msmis_site\M', 'mdm_site', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\msmis_storage_location\M', 'mdm_storage_location', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\msmis_equipment_category\M', 'mdm_equipment_category', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\msmis_equipment\M', 'mdm_equipment', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\msmis_material_category\M', 'mdm_material_category', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\msmis_material\M', 'mdm_material', 'g');
    execute rewritten_definition;
  end loop;
end;
$$;

create view public.tms_station with (security_invoker = true)
as select * from public.mdm_station;
create view public.tms_cargo with (security_invoker = true)
as select * from public.mdm_cargo;
create view public.vehicle_archive with (security_invoker = true)
as select * from public.mdm_vehicle;
create view public.vehicle_parts_category with (security_invoker = true)
as select * from public.mdm_part_category;
create view public.vehicle_parts with (security_invoker = true)
as select * from public.mdm_part;
create view public.smis_site with (security_invoker = true)
as select * from public.mdm_site;
create view public.smis_storage_location with (security_invoker = true)
as select * from public.mdm_storage_location;
create view public.smis_equipment_category with (security_invoker = true)
as select * from public.mdm_equipment_category;
create view public.smis_equipment with (security_invoker = true)
as select * from public.mdm_equipment;
create view public.smis_material_category with (security_invoker = true)
as select * from public.mdm_material_category;
create view public.smis_material with (security_invoker = true)
as select * from public.mdm_material;

comment on view public.tms_station is
  'Deprecated compatibility view. Use public.mdm_station for new integrations.';
comment on view public.tms_cargo is
  'Deprecated compatibility view. Use public.mdm_cargo for new integrations.';
comment on view public.vehicle_archive is
  'Deprecated compatibility view. Use public.mdm_vehicle for new integrations.';
comment on view public.vehicle_parts_category is
  'Deprecated compatibility view. Use public.mdm_part_category for new integrations.';
comment on view public.vehicle_parts is
  'Deprecated compatibility view. Use public.mdm_part for new integrations.';
comment on view public.smis_site is
  'Deprecated compatibility view. Use public.mdm_site for new integrations.';
comment on view public.smis_storage_location is
  'Deprecated compatibility view. Use public.mdm_storage_location for new integrations.';
comment on view public.smis_equipment_category is
  'Deprecated compatibility view. Use public.mdm_equipment_category for new integrations.';
comment on view public.smis_equipment is
  'Deprecated compatibility view. Use public.mdm_equipment for new integrations.';
comment on view public.smis_material_category is
  'Deprecated compatibility view. Use public.mdm_material_category for new integrations.';
comment on view public.smis_material is
  'Deprecated compatibility view. Use public.mdm_material for new integrations.';

revoke all on
  public.tms_station,
  public.tms_cargo,
  public.vehicle_archive,
  public.vehicle_parts_category,
  public.vehicle_parts,
  public.smis_site,
  public.smis_storage_location,
  public.smis_equipment_category,
  public.smis_equipment,
  public.smis_material_category,
  public.smis_material
from public, anon, authenticated;

revoke all on
  public.mdm_station,
  public.mdm_cargo,
  public.mdm_part_category,
  public.mdm_part
from anon;

grant select, insert, update, delete on
  public.tms_station,
  public.tms_cargo,
  public.vehicle_parts_category,
  public.vehicle_parts,
  public.smis_material_category,
  public.smis_material
to authenticated;

grant select on public.smis_site to authenticated;

grant select, insert, update, delete on
  public.tms_station,
  public.tms_cargo,
  public.vehicle_archive,
  public.vehicle_parts_category,
  public.vehicle_parts,
  public.smis_site,
  public.smis_storage_location,
  public.smis_equipment_category,
  public.smis_equipment,
  public.smis_material_category,
  public.smis_material
to service_role;

commit;
