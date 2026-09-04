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
        ('tms_customer', 'mdm_customer'),
        ('tms_customer_address', 'mdm_customer_address'),
        ('tms_carrier', 'mdm_carrier'),
        ('tms_driver', 'mdm_driver'),
        ('vehicle_supplier', 'mdm_supplier'),
        ('vehicle_insurance_company', 'mdm_insurance_company'),
        ('hr_external_vendor', 'mdm_external_vendor')
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

alter table public.tms_customer rename to mdm_customer;
alter table public.tms_customer_address rename to mdm_customer_address;
alter table public.tms_carrier rename to mdm_carrier;
alter table public.tms_driver rename to mdm_driver;
alter table public.vehicle_supplier rename to mdm_supplier;
alter table public.vehicle_insurance_company rename to mdm_insurance_company;
alter table public.hr_external_vendor rename to mdm_external_vendor;

comment on table public.mdm_customer is
  'MDM 客户主数据；租户级客户主体、开票、结算与默认联系信息。';
comment on table public.mdm_customer_address is
  'MDM 客户地址主数据；维护客户收发货地址、联系人、坐标与电子围栏。';
comment on table public.mdm_carrier is
  'MDM 承运商主数据；租户级承运主体、合同、结算与联系信息。';
comment on table public.mdm_driver is
  'MDM 驾驶员主数据；连接承运商、内部员工身份与驾驶资质。';
comment on table public.mdm_supplier is
  'MDM 供应商主数据；跨 SMIS、VMS、FMS 与其他业务应用复用。';
comment on table public.mdm_insurance_company is
  'MDM 保险机构主数据；供车辆、设备与保险业务统一引用。';
comment on table public.mdm_external_vendor is
  'MDM 外部服务商主数据；记录外包服务范围、合同与合规状态。';

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
        '\m(tms_customer|tms_customer_address|tms_carrier|tms_driver|vehicle_supplier|vehicle_insurance_company|hr_external_vendor)\M'
  loop
    rewritten_definition := routine.definition;
    rewritten_definition := regexp_replace(rewritten_definition, '\mtms_customer\M', 'mdm_customer', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mtms_customer_address\M', 'mdm_customer_address', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mtms_carrier\M', 'mdm_carrier', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mtms_driver\M', 'mdm_driver', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mvehicle_supplier\M', 'mdm_supplier', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mvehicle_insurance_company\M', 'mdm_insurance_company', 'g');
    rewritten_definition := regexp_replace(rewritten_definition, '\mhr_external_vendor\M', 'mdm_external_vendor', 'g');
    execute rewritten_definition;
  end loop;
end;
$$;

create view public.tms_customer
with (security_invoker = true)
as select * from public.mdm_customer;

create view public.tms_customer_address
with (security_invoker = true)
as select * from public.mdm_customer_address;

create view public.tms_carrier
with (security_invoker = true)
as select * from public.mdm_carrier;

create view public.tms_driver
with (security_invoker = true)
as select * from public.mdm_driver;

create view public.vehicle_supplier
with (security_invoker = true)
as select * from public.mdm_supplier;

create view public.vehicle_insurance_company
with (security_invoker = true)
as select * from public.mdm_insurance_company;

create view public.hr_external_vendor
with (security_invoker = true)
as select * from public.mdm_external_vendor;

comment on view public.tms_customer is
  'Deprecated compatibility view. Use public.mdm_customer for new integrations.';
comment on view public.tms_customer_address is
  'Deprecated compatibility view. Use public.mdm_customer_address for new integrations.';
comment on view public.tms_carrier is
  'Deprecated compatibility view. Use public.mdm_carrier for new integrations.';
comment on view public.tms_driver is
  'Deprecated compatibility view. Use public.mdm_driver for new integrations.';
comment on view public.vehicle_supplier is
  'Deprecated compatibility view. Use public.mdm_supplier for new integrations.';
comment on view public.vehicle_insurance_company is
  'Deprecated compatibility view. Use public.mdm_insurance_company for new integrations.';
comment on view public.hr_external_vendor is
  'Deprecated compatibility view. Use public.mdm_external_vendor for new integrations.';

revoke all on
  public.tms_customer,
  public.tms_customer_address,
  public.tms_carrier,
  public.tms_driver,
  public.vehicle_supplier,
  public.vehicle_insurance_company,
  public.hr_external_vendor
from public, anon, authenticated;

-- Anonymous users had table grants on the legacy insurance-company table but
-- no matching RLS policy. Remove that unnecessary privilege at the source.
revoke all on public.mdm_insurance_company from anon;

grant select, insert, update, delete on public.vehicle_insurance_company to authenticated;

grant select, insert, update, delete on
  public.tms_customer,
  public.tms_customer_address,
  public.tms_carrier,
  public.tms_driver,
  public.vehicle_supplier,
  public.vehicle_insurance_company,
  public.hr_external_vendor
to service_role;

commit;
