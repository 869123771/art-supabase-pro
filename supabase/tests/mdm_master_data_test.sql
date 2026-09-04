begin;

do $test$
declare
  invalid_relation_count integer;
  remaining_routine_reference_count integer;
  source_partner_count bigint;
begin
  with mapping(old_name, new_name) as (
    values
      ('sys_organization', 'mdm_organization'),
      ('hr_job_family', 'mdm_job_family'),
      ('hr_grade', 'mdm_grade'),
      ('hr_job_profile', 'mdm_job_profile'),
      ('hr_position', 'mdm_position'),
      ('hr_employee', 'mdm_employee'),
      ('hr_employee_assignment', 'mdm_employee_assignment'),
      ('tms_customer', 'mdm_customer'),
      ('tms_customer_address', 'mdm_customer_address'),
      ('tms_carrier', 'mdm_carrier'),
      ('tms_driver', 'mdm_driver'),
      ('vehicle_supplier', 'mdm_supplier'),
      ('vehicle_insurance_company', 'mdm_insurance_company'),
      ('hr_external_vendor', 'mdm_external_vendor'),
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
  )
  select count(*)
  into invalid_relation_count
  from mapping
  left join pg_class old_relation
    on old_relation.oid = to_regclass('public.' || mapping.old_name)
  left join pg_class new_relation
    on new_relation.oid = to_regclass('public.' || mapping.new_name)
  where old_relation.relkind <> 'v'
     or new_relation.relkind <> 'r'
     or new_relation.relrowsecurity is not true
     or coalesce(
          (
            select option_value
            from pg_options_to_table(old_relation.reloptions)
            where option_name = 'security_invoker'
          ),
          'false'
        ) <> 'true';

  if invalid_relation_count <> 0 then
    raise exception '% MDM relation mappings are invalid', invalid_relation_count;
  end if;

  if not (select relrowsecurity from pg_class where oid = 'public.mdm_business_partner'::regclass)
     or not (select relrowsecurity from pg_class where oid = 'public.mdm_business_partner_role'::regclass) then
    raise exception 'Business-partner registry must have RLS enabled';
  end if;

  if exists (
    select 1
    from information_schema.role_table_grants
    where table_schema = 'public'
      and table_name like 'mdm\_%' escape '\'
      and grantee = 'anon'
  ) then
    raise exception 'Anonymous role must not have privileges on MDM relations';
  end if;

  select
    (select count(*) from public.mdm_customer)
    + (select count(*) from public.mdm_carrier)
    + (select count(*) from public.mdm_supplier)
    + (select count(*) from public.mdm_insurance_company)
    + (select count(*) from public.mdm_external_vendor)
  into source_partner_count;

  if (select count(*) from public.mdm_business_partner) <> source_partner_count
     or (select count(*) from public.mdm_business_partner_role) <> source_partner_count then
    raise exception 'Business-partner registry is not synchronized with role records';
  end if;

  select count(*)
  into remaining_routine_reference_count
  from pg_proc routine
  join pg_namespace namespace on namespace.oid = routine.pronamespace
  where namespace.nspname = 'public'
    and routine.prokind in ('f', 'p')
    and routine.prosrc ~ '\m(sys_organization|hr_job_family|hr_grade|hr_job_profile|hr_position|hr_employee|hr_employee_assignment|tms_customer|tms_customer_address|tms_carrier|tms_driver|vehicle_supplier|vehicle_insurance_company|hr_external_vendor|tms_station|tms_cargo|vehicle_archive|vehicle_parts_category|vehicle_parts|smis_site|smis_storage_location|smis_equipment_category|smis_equipment|smis_material_category|smis_material)\M';

  if remaining_routine_reference_count <> 0 then
    raise exception '% public routines still reference legacy master-data relations', remaining_routine_reference_count;
  end if;
end;
$test$;

rollback;
