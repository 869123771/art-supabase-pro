alter table public.vehicle_supplier add column if not exists created_by_user_id uuid;

update public.vehicle_supplier supplier_row
set created_by_user_id = (
  select user_row.id from public.sys_user user_row
  where user_row.tenant_id = supplier_row.tenant_id
    and lower(user_row.user_email) = lower(supplier_row.create_by)
    and user_row.deleted_at is null
  order by user_row.create_time, user_row.id limit 1
)
where supplier_row.created_by_user_id is null;

do $$
begin
  if exists (select 1 from public.vehicle_supplier where created_by_user_id is null) then
    raise exception 'Vehicle supplier creator backfill is incomplete';
  end if;
end;
$$;

alter table public.vehicle_supplier alter column created_by_user_id set not null;
alter table public.vehicle_supplier drop constraint if exists vehicle_supplier_creator_tenant_fk;
alter table public.vehicle_supplier
  add constraint vehicle_supplier_creator_tenant_fk
  foreign key (created_by_user_id, tenant_id)
  references public.sys_user(id, tenant_id)
  on update restrict on delete restrict;
create index if not exists vehicle_supplier_creator_tenant_idx
  on public.vehicle_supplier(created_by_user_id, tenant_id);

create or replace function app_private.set_vehicle_supplier_creator_identity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_current_user_id uuid := app_private.current_app_user_id();
  v_current_user_tenant_id uuid;
begin
  if tg_op = 'INSERT' then
    if v_current_user_id is not null then
      select user_row.tenant_id into v_current_user_tenant_id
      from public.sys_user user_row where user_row.id = v_current_user_id;
    end if;
    if v_current_user_id is not null and v_current_user_tenant_id = new.tenant_id then
      new.created_by_user_id := v_current_user_id;
    elsif new.created_by_user_id is null and nullif(btrim(new.create_by), '') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
        and user_row.deleted_at is null
      order by user_row.create_time, user_row.id limit 1;
    end if;
    if new.created_by_user_id is null or not exists (
      select 1 from public.sys_user user_row
      where user_row.id = new.created_by_user_id and user_row.tenant_id = new.tenant_id
    ) then
      raise exception 'Vehicle supplier creator is missing or outside the record tenant'
        using errcode = '42501';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Vehicle supplier creator identity is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists vehicle_supplier_creator_identity on public.vehicle_supplier;
create trigger vehicle_supplier_creator_identity
before insert or update on public.vehicle_supplier
for each row execute function app_private.set_vehicle_supplier_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
rename to seed_field_permission_catalog_before_vms_supplier;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_vms_supplier(p_tenant_id);
  insert into public.sys_permission_resource(
    tenant_id, resource_key, resource_label, menu_name, owner_column, create_by, update_by
  ) values (
    p_tenant_id, 'vms.supplier', '车辆供应厂商', 'Supplier', 'created_by_user_id',
    '624944977@qq.com', '624944977@qq.com'
  )
  on conflict (tenant_id, resource_key) do update
    set resource_label=excluded.resource_label, menu_name=excluded.menu_name,
        owner_column=excluded.owner_column, enabled=true, update_by=excluded.update_by,
        update_time=now()
  returning id into v_resource_id;

  insert into public.sys_permission_field(
    tenant_id, resource_id, field_key, field_label, default_access, mask_strategy,
    owner_override_enabled, sensitive, enabled, sort, create_by, update_by
  ) values
    (p_tenant_id,v_resource_id,'contactDetails','联系人与联系电话','hidden','none',true,true,true,10,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'addressDetails','所在地区与详细地址','hidden','none',true,true,true,20,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'internalNotes','供应商内部备注','hidden','none',true,true,true,30,'624944977@qq.com','624944977@qq.com')
  on conflict (tenant_id, resource_id, field_key) do update
    set field_label=excluded.field_label, mask_strategy=excluded.mask_strategy,
        owner_override_enabled=true, sensitive=true, enabled=true, sort=excluded.sort,
        update_by=excluded.update_by, update_time=now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id) from public.sys_tenant tenant_row;

insert into public.sys_role_field_permission(
  tenant_id,role_id,resource_id,field_id,access_level,create_by,update_by
)
select distinct resource_row.tenant_id,role_menu.role_id,resource_row.id,field_row.id,
  'edit','624944977@qq.com','624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id=resource_row.tenant_id and field_row.resource_id=resource_row.id
join public.sys_menu menu_row on menu_row.type='menu' and menu_row.name='Supplier'
join public.sys_role_menu role_menu
  on role_menu.tenant_id=resource_row.tenant_id and role_menu.menu_id=menu_row.id
where resource_row.resource_key='vms.supplier' and resource_row.enabled and field_row.enabled
on conflict (tenant_id,role_id,resource_id,field_id) do nothing;

create or replace function app_private.can_access_vms_supplier_options()
returns boolean language sql stable security definer set search_path = '' as $$
  select app_private.is_platform_super() or exists (
    select 1 from public.sys_menu menu_row
    where menu_row.type='menu'
      and menu_row.name in ('Supplier','Parts','VehiclePartsManage')
      and app_private.can_access_business_menu(menu_row.name)
  );
$$;

create or replace function app_private.vehicle_supplier_to_secure_json(
  p_supplier public.vehicle_supplier,
  p_access jsonb default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_access jsonb := coalesce(
    p_access, app_private.field_access_map('vms.supplier',p_supplier.created_by_user_id)
  );
  v_data jsonb := to_jsonb(p_supplier)-'tenant_id'-'created_by_user_id';
  v_level text;
begin
  v_level := coalesce(v_access->>'contactDetails','hidden');
  if v_level='hidden' then
    v_data := v_data-'contact_person'-'contact_phone';
  elsif v_level='masked' then
    v_data := jsonb_set(v_data,'{contact_person}','"***"'::jsonb);
    v_data := jsonb_set(v_data,'{contact_phone}',coalesce(to_jsonb(
      app_private.mask_permission_value(p_supplier.contact_phone,'phone')
    ),'null'::jsonb));
  end if;

  v_level := coalesce(v_access->>'addressDetails','hidden');
  if v_level='hidden' then
    v_data := v_data-'region'-'address_detail';
  elsif v_level='masked' then
    v_data := jsonb_set(v_data,'{region}','"***"'::jsonb);
    v_data := jsonb_set(v_data,'{address_detail}','"***"'::jsonb);
  end if;

  v_level := coalesce(v_access->>'internalNotes','hidden');
  if v_level='hidden' then
    v_data := v_data-'remark';
  elsif v_level='masked' then
    v_data := jsonb_set(v_data,'{remark}','"***"'::jsonb);
  end if;

  return v_data || jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_supplier.created_by_user_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.vms_list_vehicle_suppliers_secure(
  p_from integer default 0,
  p_to integer default 9,
  p_supplier_name text default null,
  p_contact_person text default null,
  p_contact_phone text default null,
  p_ids uuid[] default null,
  p_purpose text default 'list'
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_limit integer;
  v_result jsonb;
begin
  if p_purpose not in ('list','export','options') then
    raise exception 'Invalid vehicle supplier read purpose';
  end if;
  if p_purpose='export' then
    if not app_private.can_execute_business_action('Supplier','Supplier:Export',null,false) then
      raise exception 'Missing vehicle supplier export permission' using errcode='42501';
    end if;
  elsif p_purpose='options' then
    if not app_private.can_access_vms_supplier_options() then
      raise exception 'Missing vehicle supplier option permission' using errcode='42501';
    end if;
  elsif not app_private.can_access_business_menu('Supplier') then
    raise exception 'Missing vehicle supplier read permission' using errcode='42501';
  end if;
  if v_tenant_id is null then raise exception 'Current tenant not found' using errcode='42501'; end if;

  v_limit := least(
    case when p_purpose in ('export','options') then 10000 else 500 end,
    greatest(coalesce(p_to,9)-greatest(coalesce(p_from,0),0)+1,1)
  );

  if p_purpose='options' then
    select jsonb_build_object(
      'records',coalesce(jsonb_agg(jsonb_build_object(
        'id',supplier_row.id,'supplier_name',supplier_row.supplier_name
      ) order by supplier_row.supplier_name,supplier_row.id),'[]'::jsonb),
      'total',count(*)
    ) into v_result
    from (
      select supplier_record.id,supplier_record.supplier_name
      from public.vehicle_supplier supplier_record
      where (app_private.is_platform_super() or supplier_record.tenant_id=v_tenant_id)
        and (p_ids is null or supplier_record.id=any(p_ids))
        and (nullif(btrim(p_supplier_name),'') is null
          or supplier_record.supplier_name ilike '%'||btrim(p_supplier_name)||'%')
      order by supplier_record.supplier_name,supplier_record.id
      limit v_limit
    ) supplier_row;
    return v_result;
  end if;

  with filtered as materialized (
    select supplier_row as supplier_record
    from public.vehicle_supplier supplier_row
    where (app_private.is_platform_super() or supplier_row.tenant_id=v_tenant_id)
      and (p_ids is null or supplier_row.id=any(p_ids))
      and (nullif(btrim(p_supplier_name),'') is null
        or supplier_row.supplier_name ilike '%'||btrim(p_supplier_name)||'%')
      and (
        nullif(btrim(p_contact_person),'') is null or (
          app_private.resolve_field_access('vms.supplier','contactDetails',supplier_row.created_by_user_id)
            in ('read','edit')
          and supplier_row.contact_person ilike '%'||btrim(p_contact_person)||'%'
        )
      )
      and (
        nullif(btrim(p_contact_phone),'') is null or (
          app_private.resolve_field_access('vms.supplier','contactDetails',supplier_row.created_by_user_id)
            in ('read','edit')
          and supplier_row.contact_phone ilike '%'||btrim(p_contact_phone)||'%'
        )
      )
  ), paged as (
    select filtered.supplier_record from filtered
    order by (filtered.supplier_record).create_time desc,(filtered.supplier_record).id
    offset greatest(coalesce(p_from,0),0) limit v_limit
  )
  select jsonb_build_object(
    'records',coalesce((select jsonb_agg(
      app_private.vehicle_supplier_to_secure_json(paged.supplier_record,null)
      order by (paged.supplier_record).create_time desc,(paged.supplier_record).id
    ) from paged),'[]'::jsonb),
    'total',(select count(*) from filtered),
    'fieldAccess',app_private.field_access_map('vms.supplier',null)
  ) into v_result;
  return v_result;
end;
$$;

create or replace function app_private.assert_vms_supplier_payload_keys(p_payload jsonb)
returns void language plpgsql immutable set search_path = '' as $$
declare
  v_key text;
  v_allowed constant text[] := array[
    'supplier_name','contact_person','contact_phone','region','address_detail','remark'
  ]::text[];
begin
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then
    raise exception 'Vehicle supplier payload must be a JSON object';
  end if;
  for v_key in select jsonb_object_keys(p_payload) loop
    if not (v_key=any(v_allowed)) then raise exception 'Unsupported vehicle supplier field: %',v_key; end if;
  end loop;
end;
$$;

create or replace function app_private.normalize_vms_supplier(
  p_input public.vehicle_supplier
)
returns public.vehicle_supplier language plpgsql immutable set search_path = '' as $$
declare v_input public.vehicle_supplier := p_input;
begin
  v_input.supplier_name := nullif(btrim(v_input.supplier_name),'');
  if v_input.supplier_name is null then raise exception 'Supplier name is required'; end if;
  v_input.contact_person := nullif(btrim(v_input.contact_person),'');
  v_input.contact_phone := nullif(btrim(v_input.contact_phone),'');
  v_input.region := nullif(btrim(v_input.region),'');
  v_input.address_detail := nullif(btrim(v_input.address_detail),'');
  v_input.remark := nullif(btrim(v_input.remark),'');
  return v_input;
end;
$$;

create or replace function public.vms_create_vehicle_supplier_secure(p_payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_input public.vehicle_supplier%rowtype;
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_user_id uuid := app_private.current_app_user_id();
  v_email text;
begin
  if not app_private.can_execute_business_action('Supplier','Supplier:Add',null,false) then
    raise exception 'Missing vehicle supplier add permission' using errcode='42501';
  end if;
  select user_row.user_email into v_email from public.sys_user user_row where user_row.id=v_user_id;
  if v_tenant_id is null or v_user_id is null or v_email is null then
    raise exception 'Current vehicle supplier operator not found' using errcode='42501';
  end if;
  perform app_private.assert_vms_supplier_payload_keys(p_payload);
  select * into v_input from jsonb_populate_record(null::public.vehicle_supplier,p_payload);
  v_input.id:=gen_random_uuid(); v_input.tenant_id:=v_tenant_id;
  v_input.created_by_user_id:=v_user_id; v_input.create_by:=v_email; v_input.update_by:=v_email;
  v_input.create_time:=now(); v_input.update_time:=now();
  v_input:=app_private.normalize_vms_supplier(v_input);
  insert into public.vehicle_supplier select (v_input).*;
  return v_input.id;
end;
$$;

create or replace function public.vms_update_vehicle_supplier_secure(p_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_old public.vehicle_supplier%rowtype;
  v_candidate public.vehicle_supplier%rowtype;
  v_updated public.vehicle_supplier%rowtype;
  v_operator_email text;
begin
  select * into v_old from public.vehicle_supplier supplier_row
  where supplier_row.id=p_id
    and (app_private.is_platform_super() or supplier_row.tenant_id=app_private.current_user_tenant_id())
  for update;
  if not found then raise exception 'Vehicle supplier not found'; end if;
  if not app_private.can_execute_business_action('Supplier','Supplier:Edit',v_old.created_by_user_id,true) then
    raise exception 'Missing vehicle supplier edit permission' using errcode='42501';
  end if;
  perform app_private.assert_vms_supplier_payload_keys(p_payload);
  select * into v_candidate from jsonb_populate_record(v_old,p_payload);
  v_candidate.id:=v_old.id; v_candidate.tenant_id:=v_old.tenant_id;
  v_candidate.created_by_user_id:=v_old.created_by_user_id;
  v_candidate.create_by:=v_old.create_by; v_candidate.create_time:=v_old.create_time;
  select user_row.user_email into v_operator_email
  from public.sys_user user_row where user_row.id=app_private.current_app_user_id();
  if v_operator_email is null then
    raise exception 'Current vehicle supplier operator not found' using errcode='42501';
  end if;
  v_candidate.update_by:=v_operator_email;
  v_candidate.update_time:=now();
  v_candidate:=app_private.normalize_vms_supplier(v_candidate);

  if (v_candidate.contact_person,v_candidate.contact_phone)
       is distinct from (v_old.contact_person,v_old.contact_phone)
     and app_private.resolve_field_access('vms.supplier','contactDetails',v_old.created_by_user_id)<>'edit' then
    raise exception 'No edit permission for vehicle supplier contacts' using errcode='42501';
  end if;
  if (v_candidate.region,v_candidate.address_detail)
       is distinct from (v_old.region,v_old.address_detail)
     and app_private.resolve_field_access('vms.supplier','addressDetails',v_old.created_by_user_id)<>'edit' then
    raise exception 'No edit permission for vehicle supplier address' using errcode='42501';
  end if;
  if v_candidate.remark is distinct from v_old.remark
     and app_private.resolve_field_access('vms.supplier','internalNotes',v_old.created_by_user_id)<>'edit' then
    raise exception 'No edit permission for vehicle supplier notes' using errcode='42501';
  end if;

  update public.vehicle_supplier set
    supplier_name=v_candidate.supplier_name,
    contact_person=v_candidate.contact_person,
    contact_phone=v_candidate.contact_phone,
    region=v_candidate.region,
    address_detail=v_candidate.address_detail,
    remark=v_candidate.remark,
    update_by=v_candidate.update_by,
    update_time=v_candidate.update_time
  where id=v_old.id returning * into v_updated;
  return app_private.vehicle_supplier_to_secure_json(v_updated,null);
end;
$$;

create or replace function public.vms_delete_vehicle_suppliers_secure(p_ids uuid[])
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_ids uuid[]:=array(select distinct unnest(coalesce(p_ids,'{}'::uuid[])));
  v_supplier public.vehicle_supplier%rowtype;
  v_deleted integer;
begin
  if coalesce(array_length(v_ids,1),0)=0 then return 0; end if;
  if exists (
    select 1 from public.vehicle_supplier supplier_row where supplier_row.id=any(v_ids)
      and not (app_private.is_platform_super() or supplier_row.tenant_id=app_private.current_user_tenant_id())
  ) or (select count(*) from public.vehicle_supplier supplier_row where supplier_row.id=any(v_ids))
       <> array_length(v_ids,1) then
    raise exception 'One or more vehicle suppliers are missing or outside the current tenant';
  end if;
  for v_supplier in select * from public.vehicle_supplier supplier_row
    where supplier_row.id=any(v_ids) for update loop
    if not app_private.can_execute_business_action('Supplier','Supplier:Delete',v_supplier.created_by_user_id,true) then
      raise exception 'Missing vehicle supplier delete permission' using errcode='42501';
    end if;
  end loop;
  delete from public.vehicle_supplier supplier_row where supplier_row.id=any(v_ids);
  get diagnostics v_deleted=row_count;
  return v_deleted;
end;
$$;

create or replace function public.vms_import_vehicle_suppliers_secure(p_rows jsonb)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_tenant_id uuid:=app_private.current_user_tenant_id();
  v_user_id uuid:=app_private.current_app_user_id();
  v_email text;
  v_row jsonb;
  v_input public.vehicle_supplier%rowtype;
  v_count integer:=0;
begin
  if not app_private.can_execute_business_action('Supplier','Supplier:Import',null,false) then
    raise exception 'Missing vehicle supplier import permission' using errcode='42501';
  end if;
  if jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows)>1000 then
    raise exception 'Vehicle supplier import must be an array with at most 1000 rows';
  end if;
  select user_row.user_email into v_email from public.sys_user user_row where user_row.id=v_user_id;
  if v_tenant_id is null or v_user_id is null or v_email is null then
    raise exception 'Current vehicle supplier operator not found' using errcode='42501';
  end if;
  for v_row in select value from jsonb_array_elements(p_rows) loop
    perform app_private.assert_vms_supplier_payload_keys(v_row);
    select * into v_input from jsonb_populate_record(null::public.vehicle_supplier,v_row);
    v_input.id:=gen_random_uuid(); v_input.tenant_id:=v_tenant_id;
    v_input.created_by_user_id:=v_user_id; v_input.create_by:=v_email; v_input.update_by:=v_email;
    v_input.create_time:=now(); v_input.update_time:=now();
    v_input:=app_private.normalize_vms_supplier(v_input);
    insert into public.vehicle_supplier select (v_input).*
    on conflict (create_by,supplier_name) do update set
      contact_person=excluded.contact_person,
      contact_phone=excluded.contact_phone,
      region=excluded.region,
      address_detail=excluded.address_detail,
      remark=excluded.remark,
      update_by=excluded.update_by,
      update_time=now();
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

revoke all on table public.vehicle_supplier from anon,authenticated;
drop policy if exists tenant_insert on public.vehicle_supplier;
drop policy if exists tenant_update on public.vehicle_supplier;
drop policy if exists tenant_delete on public.vehicle_supplier;
drop policy if exists vehicle_supplier_service_all on public.vehicle_supplier;
create policy vehicle_supplier_service_all on public.vehicle_supplier
for all to service_role using (true) with check (true);

revoke all on function app_private.seed_field_permission_catalog(uuid) from public,anon,authenticated;
grant execute on function app_private.seed_field_permission_catalog(uuid) to service_role;
revoke all on function app_private.set_vehicle_supplier_creator_identity() from public,anon,authenticated;
revoke all on function app_private.can_access_vms_supplier_options() from public,anon,authenticated;
revoke all on function app_private.vehicle_supplier_to_secure_json(public.vehicle_supplier,jsonb) from public,anon,authenticated;
revoke all on function app_private.assert_vms_supplier_payload_keys(jsonb) from public,anon,authenticated;
revoke all on function app_private.normalize_vms_supplier(public.vehicle_supplier) from public,anon,authenticated;
grant execute on function app_private.set_vehicle_supplier_creator_identity() to service_role;
grant execute on function app_private.can_access_vms_supplier_options() to service_role;
grant execute on function app_private.vehicle_supplier_to_secure_json(public.vehicle_supplier,jsonb) to service_role;
grant execute on function app_private.assert_vms_supplier_payload_keys(jsonb) to service_role;
grant execute on function app_private.normalize_vms_supplier(public.vehicle_supplier) to service_role;

revoke all on function public.vms_list_vehicle_suppliers_secure(integer,integer,text,text,text,uuid[],text) from public,anon;
revoke all on function public.vms_create_vehicle_supplier_secure(jsonb) from public,anon;
revoke all on function public.vms_update_vehicle_supplier_secure(uuid,jsonb) from public,anon;
revoke all on function public.vms_delete_vehicle_suppliers_secure(uuid[]) from public,anon;
revoke all on function public.vms_import_vehicle_suppliers_secure(jsonb) from public,anon;
grant execute on function public.vms_list_vehicle_suppliers_secure(integer,integer,text,text,text,uuid[],text) to authenticated,service_role;
grant execute on function public.vms_create_vehicle_supplier_secure(jsonb) to authenticated,service_role;
grant execute on function public.vms_update_vehicle_supplier_secure(uuid,jsonb) to authenticated,service_role;
grant execute on function public.vms_delete_vehicle_suppliers_secure(uuid[]) to authenticated,service_role;
grant execute on function public.vms_import_vehicle_suppliers_secure(jsonb) to authenticated,service_role;

;
