-- Secure fixed asset and depreciation reads/writes with tenant field permissions.
-- Button permission definitions remain unchanged.

alter table public.fms_fixed_asset
  add column if not exists created_by_user_id uuid;

update public.fms_fixed_asset asset_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = asset_row.tenant_id
    and lower(user_row.user_email) = lower(asset_row.create_by)
  order by user_row.create_time, user_row.id
  limit 1
)
where asset_row.created_by_user_id is null
  and nullif(btrim(coalesce(asset_row.create_by, '')), '') is not null;

do $$
begin
  if exists (select 1 from public.fms_fixed_asset where created_by_user_id is null) then
    raise exception 'Unable to backfill fms_fixed_asset.created_by_user_id';
  end if;
end;
$$;

alter table public.fms_fixed_asset
  alter column created_by_user_id set not null;

create index if not exists fms_fixed_asset_tenant_creator_idx
  on public.fms_fixed_asset(tenant_id, created_by_user_id);
create index if not exists fms_fixed_asset_creator_tenant_idx
  on public.fms_fixed_asset(created_by_user_id, tenant_id);

alter table public.fms_fixed_asset
  drop constraint if exists fms_fixed_asset_creator_tenant_fkey;
alter table public.fms_fixed_asset
  add constraint fms_fixed_asset_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

alter table public.fms_asset_depreciation_run
  add column if not exists created_by_user_id uuid;

update public.fms_asset_depreciation_run run_row
set created_by_user_id = (
  select user_row.id
  from public.sys_user user_row
  where user_row.tenant_id = run_row.tenant_id
    and lower(user_row.user_email) = lower(run_row.create_by)
  order by user_row.create_time, user_row.id
  limit 1
)
where run_row.created_by_user_id is null
  and nullif(btrim(coalesce(run_row.create_by, '')), '') is not null;

create index if not exists fms_asset_depreciation_run_tenant_creator_idx
  on public.fms_asset_depreciation_run(tenant_id, created_by_user_id);

alter table public.fms_asset_depreciation_run
  drop constraint if exists fms_asset_depreciation_run_creator_tenant_fkey;
alter table public.fms_asset_depreciation_run
  add constraint fms_asset_depreciation_run_creator_tenant_fkey
  foreign key (tenant_id, created_by_user_id)
  references public.sys_user(tenant_id, id);

create or replace function app_private.set_fms_fixed_asset_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.created_by_user_id is null then
      new.created_by_user_id := app_private.current_app_user_id();
    end if;
    if new.created_by_user_id is null
       and nullif(btrim(coalesce(new.create_by, '')), '') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve fixed asset creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Fixed asset creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_fixed_asset_creator_identity on public.fms_fixed_asset;
create trigger fms_fixed_asset_creator_identity
before insert or update of created_by_user_id on public.fms_fixed_asset
for each row execute function app_private.set_fms_fixed_asset_creator_identity();

create or replace function app_private.set_fms_asset_depreciation_run_creator_identity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if new.created_by_user_id is null then
      new.created_by_user_id := app_private.current_app_user_id();
    end if;
    if new.created_by_user_id is null
       and nullif(btrim(coalesce(new.create_by, '')), '') is not null then
      select user_row.id into new.created_by_user_id
      from public.sys_user user_row
      where user_row.tenant_id = new.tenant_id
        and lower(user_row.user_email) = lower(new.create_by)
      order by user_row.create_time, user_row.id
      limit 1;
    end if;
    if new.created_by_user_id is null then
      raise exception 'Unable to resolve depreciation run creator';
    end if;
  elsif new.created_by_user_id is distinct from old.created_by_user_id then
    raise exception 'Depreciation run creator cannot be changed';
  end if;
  return new;
end;
$$;

drop trigger if exists fms_asset_depreciation_run_creator_identity
  on public.fms_asset_depreciation_run;
create trigger fms_asset_depreciation_run_creator_identity
before insert or update of created_by_user_id on public.fms_asset_depreciation_run
for each row execute function app_private.set_fms_asset_depreciation_run_creator_identity();

alter function app_private.seed_field_permission_catalog(uuid)
  rename to seed_field_permission_catalog_before_fixed_asset;

create or replace function app_private.seed_field_permission_catalog(p_tenant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_resource_id uuid;
begin
  perform app_private.seed_field_permission_catalog_before_fixed_asset(p_tenant_id);
  insert into public.sys_permission_resource (
    tenant_id,resource_key,resource_label,menu_name,owner_column,create_by,update_by
  ) values (
    p_tenant_id,'fms.fixed_asset','固定资产','FinanceFixedAsset','created_by_user_id',
    '624944977@qq.com','624944977@qq.com'
  )
  on conflict (tenant_id,resource_key) do update
    set resource_label=excluded.resource_label,
        menu_name=excluded.menu_name,
        owner_column=excluded.owner_column,
        enabled=true,
        update_by=excluded.update_by,
        update_time=now()
  returning id into v_resource_id;

  insert into public.sys_permission_field (
    tenant_id,resource_id,field_key,field_label,default_access,mask_strategy,
    owner_override_enabled,sort,create_by,update_by
  ) values
    (p_tenant_id,v_resource_id,'assetValues','资产原值、折旧、减值、净值与处置金额',
      'hidden','amount',true,10,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'assetCustody','保管部门、责任人与存放地点',
      'hidden','address',true,20,'624944977@qq.com','624944977@qq.com'),
    (p_tenant_id,v_resource_id,'assetReferences','序列号、规格型号与来源单据',
      'hidden','bank_account',true,30,'624944977@qq.com','624944977@qq.com')
  on conflict (tenant_id,resource_id,field_key) do update
    set field_label=excluded.field_label,
        mask_strategy=excluded.mask_strategy,
        owner_override_enabled=excluded.owner_override_enabled,
        sort=excluded.sort,
        sensitive=true,
        enabled=true,
        update_by=excluded.update_by,
        update_time=now();
end;
$$;

select app_private.seed_field_permission_catalog(tenant_row.id)
from public.sys_tenant tenant_row;

insert into public.sys_role_field_permission (
  tenant_id,role_id,resource_id,field_id,access_level,create_by,update_by
)
select distinct resource_row.tenant_id,role_menu.role_id,resource_row.id,field_row.id,
       'edit','624944977@qq.com','624944977@qq.com'
from public.sys_permission_resource resource_row
join public.sys_permission_field field_row
  on field_row.tenant_id=resource_row.tenant_id and field_row.resource_id=resource_row.id
join public.sys_menu menu_row
  on menu_row.type='menu' and menu_row.name='FinanceFixedAsset'
join public.sys_role_menu role_menu
  on role_menu.tenant_id=resource_row.tenant_id and role_menu.menu_id=menu_row.id
where resource_row.resource_key='fms.fixed_asset'
  and resource_row.enabled and field_row.enabled
on conflict (tenant_id,role_id,resource_id,field_id) do nothing;

create or replace function app_private.fms_fixed_asset_raw_json(p_asset_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select (to_jsonb(asset_row) - 'tenant_id' - 'created_by_user_id') ||
         jsonb_build_object(
           'category',jsonb_build_object(
             'id',category_row.id,
             'category_code',category_row.category_code,
             'category_name',category_row.category_name
           )
         )
  from public.fms_fixed_asset asset_row
  join public.fms_asset_category category_row
    on category_row.id=asset_row.category_id and category_row.tenant_id=asset_row.tenant_id
  where asset_row.id=p_asset_id
    and asset_row.tenant_id=app_private.current_user_tenant_id();
$$;

create or replace function app_private.fms_fixed_asset_to_secure_json(
  p_asset jsonb,p_owner_id uuid,p_access jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := coalesce(p_access,app_private.field_access_map('fms.fixed_asset',p_owner_id));
  v_data jsonb := coalesce(p_asset,'{}'::jsonb)-'tenant_id'-'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['original_value','residual_value','accumulated_depreciation','impairment_amount','disposal_amount']::text[],
    coalesce(v_access->>'assetValues','hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,array['department_id','employee_id','location']::text[],
    coalesce(v_access->>'assetCustody','hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,array['specification','serial_no','source_type','source_id','source_no']::text[],
    coalesce(v_access->>'assetReferences','hidden')
  );
  return v_data || jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_asset_depreciation_run_to_secure_json(
  p_run jsonb,p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.fixed_asset',p_owner_id);
  v_data jsonb := coalesce(p_run,'{}'::jsonb)-'tenant_id'-'created_by_user_id';
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,array['total_amount']::text[],coalesce(v_access->>'assetValues','hidden')
  );
  v_data := app_private.apply_jsonb_text_access(
    v_data,array['voucher_id']::text[],coalesce(v_access->>'assetReferences','hidden')
  );
  return v_data || jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function app_private.fms_asset_depreciation_line_to_secure_json(
  p_line jsonb,p_owner_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_access jsonb := app_private.field_access_map('fms.fixed_asset',p_owner_id);
  v_data jsonb := coalesce(p_line,'{}'::jsonb)-'tenant_id';
begin
  v_data := app_private.apply_jsonb_amount_access(
    v_data,
    array['opening_accumulated_depreciation','depreciation_amount','closing_accumulated_depreciation']::text[],
    coalesce(v_access->>'assetValues','hidden')
  );
  return v_data || jsonb_build_object(
    'field_access',v_access,
    'is_record_owner',p_owner_id=app_private.current_app_user_id()
  );
end;
$$;

create or replace function public.fms_list_asset_categories_secure(
  p_account_set_id uuid default null,p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_result jsonb;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant asset category access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinanceFixedAsset',null,null,false) then
    raise exception 'Missing fixed asset menu permission' using errcode='42501';
  end if;
  if p_account_set_id is not null and not exists(
    select 1 from public.fms_account_set s where s.id=p_account_set_id and s.tenant_id=v_tenant_id
  ) then
    raise exception 'Asset category account set is outside the current tenant' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(to_jsonb(category_row)-'tenant_id'
    order by category_row.sort,category_row.category_code),'[]'::jsonb)
  into v_result
  from public.fms_asset_category category_row
  where category_row.tenant_id=v_tenant_id
    and (p_account_set_id is null or category_row.account_set_id=p_account_set_id);
  return v_result;
end;
$$;

create or replace function public.fms_list_fixed_assets_secure(
  p_from integer default 0,p_to integer default 19,p_account_set_id uuid default null,
  p_category_id uuid default null,p_status text default null,p_keyword text default null,
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
  v_from integer := greatest(coalesce(p_from,0),0);
  v_limit integer := least(greatest(coalesce(p_to,19)-v_from+1,1),1000);
  v_total integer;
  v_records jsonb := '[]'::jsonb;
  v_base_access jsonb := app_private.field_access_map('fms.fixed_asset',null);
  v_row record;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant fixed asset access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinanceFixedAsset',null,null,false) then
    raise exception 'Missing fixed asset menu permission' using errcode='42501';
  end if;
  if p_account_set_id is not null and not exists(
    select 1 from public.fms_account_set s where s.id=p_account_set_id and s.tenant_id=v_tenant_id
  ) then
    raise exception 'Fixed asset account set is outside the current tenant' using errcode='42501';
  end if;

  select count(*)::integer into v_total
  from public.fms_fixed_asset asset_row
  where asset_row.tenant_id=v_tenant_id
    and (p_account_set_id is null or asset_row.account_set_id=p_account_set_id)
    and (p_category_id is null or asset_row.category_id=p_category_id)
    and (p_status is null or asset_row.status=p_status)
    and (
      nullif(btrim(coalesce(p_keyword,'')),'') is null
      or asset_row.asset_no ilike '%'||btrim(p_keyword)||'%'
      or asset_row.asset_name ilike '%'||btrim(p_keyword)||'%'
      or (
        app_private.resolve_field_access('fms.fixed_asset','assetCustody',asset_row.created_by_user_id) in ('read','edit')
        and asset_row.location ilike '%'||btrim(p_keyword)||'%'
      )
      or (
        app_private.resolve_field_access('fms.fixed_asset','assetReferences',asset_row.created_by_user_id) in ('read','edit')
        and (asset_row.serial_no ilike '%'||btrim(p_keyword)||'%'
             or asset_row.source_no ilike '%'||btrim(p_keyword)||'%')
      )
    );

  for v_row in
    select asset_row.id,asset_row.created_by_user_id
    from public.fms_fixed_asset asset_row
    where asset_row.tenant_id=v_tenant_id
      and (p_account_set_id is null or asset_row.account_set_id=p_account_set_id)
      and (p_category_id is null or asset_row.category_id=p_category_id)
      and (p_status is null or asset_row.status=p_status)
      and (
        nullif(btrim(coalesce(p_keyword,'')),'') is null
        or asset_row.asset_no ilike '%'||btrim(p_keyword)||'%'
        or asset_row.asset_name ilike '%'||btrim(p_keyword)||'%'
        or (
          app_private.resolve_field_access('fms.fixed_asset','assetCustody',asset_row.created_by_user_id) in ('read','edit')
          and asset_row.location ilike '%'||btrim(p_keyword)||'%'
        )
        or (
          app_private.resolve_field_access('fms.fixed_asset','assetReferences',asset_row.created_by_user_id) in ('read','edit')
          and (asset_row.serial_no ilike '%'||btrim(p_keyword)||'%'
               or asset_row.source_no ilike '%'||btrim(p_keyword)||'%')
        )
      )
    order by asset_row.asset_no,asset_row.id
    offset v_from limit v_limit
  loop
    v_records := v_records || jsonb_build_array(
      app_private.fms_fixed_asset_to_secure_json(
        app_private.fms_fixed_asset_raw_json(v_row.id),v_row.created_by_user_id
      )
    );
  end loop;
  return jsonb_build_object('records',v_records,'total',coalesce(v_total,0),'field_access',v_base_access);
end;
$$;

create or replace function public.fms_get_fixed_asset_secure(p_asset_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_owner_id uuid;
begin
  if not app_private.can_execute_business_action('FinanceFixedAsset',null,null,false) then
    raise exception 'Missing fixed asset menu permission' using errcode='42501';
  end if;
  select created_by_user_id into v_owner_id
  from public.fms_fixed_asset
  where id=p_asset_id and tenant_id=app_private.current_user_tenant_id();
  if not found then raise exception 'Fixed asset does not exist in the current tenant' using errcode='P0002'; end if;
  return app_private.fms_fixed_asset_to_secure_json(
    app_private.fms_fixed_asset_raw_json(p_asset_id),v_owner_id
  );
end;
$$;

create or replace function public.fms_list_asset_depreciation_runs_secure(
  p_account_set_id uuid default null,p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_records jsonb := '[]'::jsonb;
  v_row record;
  v_raw jsonb;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant depreciation run access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinanceFixedAsset',null,null,false) then
    raise exception 'Missing fixed asset menu permission' using errcode='42501';
  end if;
  if p_account_set_id is not null and not exists(
    select 1 from public.fms_account_set s where s.id=p_account_set_id and s.tenant_id=v_tenant_id
  ) then
    raise exception 'Depreciation account set is outside the current tenant' using errcode='42501';
  end if;
  for v_row in
    select run_row.id,run_row.created_by_user_id
    from public.fms_asset_depreciation_run run_row
    where run_row.tenant_id=v_tenant_id
      and (p_account_set_id is null or run_row.account_set_id=p_account_set_id)
    order by run_row.create_time desc,run_row.id
  loop
    select (to_jsonb(run_row)-'tenant_id'-'created_by_user_id') ||
           jsonb_build_object('period',to_jsonb(period_row)-'tenant_id')
    into v_raw
    from public.fms_asset_depreciation_run run_row
    join public.fms_accounting_period period_row on period_row.id=run_row.accounting_period_id
    where run_row.id=v_row.id and run_row.tenant_id=v_tenant_id;
    v_records := v_records || jsonb_build_array(
      app_private.fms_asset_depreciation_run_to_secure_json(v_raw,v_row.created_by_user_id)
    );
  end loop;
  return jsonb_build_object(
    'records',v_records,
    'field_access',app_private.field_access_map('fms.fixed_asset',null)
  );
end;
$$;

create or replace function public.fms_list_asset_depreciation_lines_secure(p_run_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_records jsonb := '[]'::jsonb;
  v_row record;
  v_raw jsonb;
begin
  if not app_private.can_execute_business_action('FinanceFixedAsset',null,null,false) then
    raise exception 'Missing fixed asset menu permission' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.fms_asset_depreciation_run r where r.id=p_run_id and r.tenant_id=v_tenant_id
  ) then
    raise exception 'Depreciation run does not exist in the current tenant' using errcode='P0002';
  end if;
  for v_row in
    select line_row.id,asset_row.created_by_user_id
    from public.fms_asset_depreciation_line line_row
    join public.fms_fixed_asset asset_row
      on asset_row.id=line_row.asset_id and asset_row.tenant_id=line_row.tenant_id
    where line_row.run_id=p_run_id and line_row.tenant_id=v_tenant_id
    order by line_row.create_time,line_row.id
  loop
    select (to_jsonb(line_row)-'tenant_id') || jsonb_build_object(
      'asset',jsonb_build_object('id',asset_row.id,'asset_no',asset_row.asset_no,'asset_name',asset_row.asset_name)
    ) into v_raw
    from public.fms_asset_depreciation_line line_row
    join public.fms_fixed_asset asset_row on asset_row.id=line_row.asset_id
    where line_row.id=v_row.id and line_row.tenant_id=v_tenant_id;
    v_records := v_records || jsonb_build_array(
      app_private.fms_asset_depreciation_line_to_secure_json(v_raw,v_row.created_by_user_id)
    );
  end loop;
  return jsonb_build_object(
    'records',v_records,
    'field_access',app_private.field_access_map('fms.fixed_asset',null)
  );
end;
$$;

create or replace function public.fms_fixed_asset_summary_secure(
  p_account_set_id uuid,p_period_id uuid default null,p_tenant_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_access jsonb := app_private.field_access_map('fms.fixed_asset',null);
  v_value_access text := coalesce(v_access->>'assetValues','hidden');
  v_summary record;
begin
  if p_tenant_id is not null and p_tenant_id<>v_tenant_id then
    raise exception 'Cross-tenant fixed asset summary access is forbidden' using errcode='42501';
  end if;
  if not app_private.can_execute_business_action('FinanceFixedAsset',null,null,false) then
    raise exception 'Missing fixed asset menu permission' using errcode='42501';
  end if;
  if p_account_set_id is null or not exists(
    select 1 from public.fms_account_set s where s.id=p_account_set_id and s.tenant_id=v_tenant_id
  ) then
    raise exception 'Fixed asset account set is outside the current tenant' using errcode='42501';
  end if;
  if p_period_id is not null and not exists(
    select 1 from public.fms_accounting_period p
    where p.id=p_period_id and p.account_set_id=p_account_set_id and p.tenant_id=v_tenant_id
  ) then
    raise exception 'Accounting period is outside the current tenant' using errcode='42501';
  end if;
  select
    (select count(*) from public.fms_asset_category c
      where c.tenant_id=v_tenant_id and c.account_set_id=p_account_set_id and c.is_enabled) category_count,
    count(*) asset_count,
    count(*) filter(where a.status='active') active_count,
    coalesce(sum(a.original_value),0) original_value,
    coalesce(sum(a.original_value-a.accumulated_depreciation-a.impairment_amount),0) net_value,
    coalesce((select r.total_amount from public.fms_asset_depreciation_run r
      where r.tenant_id=v_tenant_id and r.accounting_period_id=p_period_id and r.status<>'cancelled'),0) period_depreciation
  into v_summary
  from public.fms_fixed_asset a
  where a.tenant_id=v_tenant_id and a.account_set_id=p_account_set_id;
  return jsonb_build_object(
    'category_count',v_summary.category_count,
    'asset_count',v_summary.asset_count,
    'active_count',v_summary.active_count,
    'original_value',case when v_value_access in ('read','edit') then to_jsonb(v_summary.original_value)
      when v_value_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'net_value',case when v_value_access in ('read','edit') then to_jsonb(v_summary.net_value)
      when v_value_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'period_depreciation',case when v_value_access in ('read','edit') then to_jsonb(v_summary.period_depreciation)
      when v_value_access='masked' then to_jsonb('***'::text) else 'null'::jsonb end,
    'field_access',v_access
  );
end;
$$;

create or replace function public.save_fms_asset_category_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_account_set_id uuid := nullif(p_payload->>'accountSetId','')::uuid;
  v_id uuid := nullif(p_payload->>'id','')::uuid;
  v_saved public.fms_asset_category%rowtype;
begin
  if v_account_set_id is null or not exists(
    select 1 from public.fms_account_set s where s.id=v_account_set_id and s.tenant_id=v_tenant_id
  ) then raise exception 'Asset category account set is outside the current tenant' using errcode='42501'; end if;
  if v_id is not null and not exists(
    select 1 from public.fms_asset_category c where c.id=v_id and c.tenant_id=v_tenant_id
  ) then raise exception 'Asset category does not exist in the current tenant' using errcode='P0002'; end if;
  v_saved := public.save_fms_asset_category(p_payload);
  if v_saved.tenant_id<>v_tenant_id then raise exception 'Cross-tenant asset category write is forbidden' using errcode='42501'; end if;
  return to_jsonb(v_saved)-'tenant_id';
end;
$$;

create or replace function public.delete_fms_asset_category_secure(p_category_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists(select 1 from public.fms_asset_category c
    where c.id=p_category_id and c.tenant_id=app_private.current_user_tenant_id()) then
    raise exception 'Asset category does not exist in the current tenant' using errcode='P0002';
  end if;
  perform public.delete_fms_asset_category(p_category_id);
  return p_category_id;
end;
$$;

create or replace function public.save_fms_fixed_asset_secure(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant_id uuid := app_private.current_user_tenant_id();
  v_id uuid := nullif(p_payload->>'id','')::uuid;
  v_account_set_id uuid := nullif(p_payload->>'accountSetId','')::uuid;
  v_existing public.fms_fixed_asset%rowtype;
  v_saved public.fms_fixed_asset%rowtype;
  v_payload jsonb := coalesce(p_payload,'{}'::jsonb);
  v_access jsonb;
begin
  if v_account_set_id is null or not exists(select 1 from public.fms_account_set s
    where s.id=v_account_set_id and s.tenant_id=v_tenant_id) then
    raise exception 'Fixed asset account set is outside the current tenant' using errcode='42501';
  end if;
  if v_id is not null then
    select * into v_existing from public.fms_fixed_asset a
    where a.id=v_id and a.tenant_id=v_tenant_id for update;
    if not found then raise exception 'Fixed asset does not exist in the current tenant' using errcode='P0002'; end if;
    v_access := app_private.field_access_map('fms.fixed_asset',v_existing.created_by_user_id);
    if coalesce(v_access->>'assetValues','hidden')<>'edit' then
      if (v_payload?'originalValue' and nullif(v_payload->>'originalValue','')::numeric is distinct from v_existing.original_value)
         or (v_payload?'residualValue' and nullif(v_payload->>'residualValue','')::numeric is distinct from v_existing.residual_value) then
        raise exception 'Fixed asset value fields are not editable' using errcode='42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'originalValue',v_existing.original_value,'residualValue',v_existing.residual_value
      );
    end if;
    if coalesce(v_access->>'assetCustody','hidden')<>'edit' then
      if (v_payload?'departmentId' and nullif(v_payload->>'departmentId','')::uuid is distinct from v_existing.department_id)
         or (v_payload?'employeeId' and nullif(v_payload->>'employeeId','')::uuid is distinct from v_existing.employee_id)
         or (v_payload?'location' and nullif(btrim(v_payload->>'location'),'') is distinct from v_existing.location) then
        raise exception 'Fixed asset custody fields are not editable' using errcode='42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'departmentId',v_existing.department_id,'employeeId',v_existing.employee_id,'location',v_existing.location
      );
    end if;
    if coalesce(v_access->>'assetReferences','hidden')<>'edit' then
      if (v_payload?'specification' and nullif(btrim(v_payload->>'specification'),'') is distinct from v_existing.specification)
         or (v_payload?'serialNo' and nullif(btrim(v_payload->>'serialNo'),'') is distinct from v_existing.serial_no)
         or (v_payload?'sourceType' and nullif(v_payload->>'sourceType','') is distinct from v_existing.source_type)
         or (v_payload?'sourceId' and nullif(v_payload->>'sourceId','')::uuid is distinct from v_existing.source_id)
         or (v_payload?'sourceNo' and nullif(btrim(v_payload->>'sourceNo'),'') is distinct from v_existing.source_no) then
        raise exception 'Fixed asset reference fields are not editable' using errcode='42501';
      end if;
      v_payload := v_payload || jsonb_build_object(
        'specification',v_existing.specification,'serialNo',v_existing.serial_no,
        'sourceType',v_existing.source_type,'sourceId',v_existing.source_id,'sourceNo',v_existing.source_no
      );
    end if;
  end if;
  v_saved := public.save_fms_fixed_asset(v_payload);
  if v_saved.tenant_id<>v_tenant_id then raise exception 'Cross-tenant fixed asset write is forbidden' using errcode='42501'; end if;
  return app_private.fms_fixed_asset_to_secure_json(
    app_private.fms_fixed_asset_raw_json(v_saved.id),v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.delete_fms_fixed_asset_secure(p_asset_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists(select 1 from public.fms_fixed_asset a
    where a.id=p_asset_id and a.tenant_id=app_private.current_user_tenant_id()) then
    raise exception 'Fixed asset does not exist in the current tenant' using errcode='P0002';
  end if;
  perform public.delete_fms_fixed_asset(p_asset_id);
  return p_asset_id;
end;
$$;

create or replace function public.act_fms_fixed_asset_secure(
  p_asset_id uuid,p_action text,p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_asset public.fms_fixed_asset%rowtype;
  v_saved public.fms_fixed_asset%rowtype;
  v_access jsonb;
begin
  select * into v_asset from public.fms_fixed_asset a
  where a.id=p_asset_id and a.tenant_id=app_private.current_user_tenant_id() for update;
  if not found then raise exception 'Fixed asset does not exist in the current tenant' using errcode='P0002'; end if;
  v_access := app_private.field_access_map('fms.fixed_asset',v_asset.created_by_user_id);
  if p_action='activate' and coalesce(v_access->>'assetValues','hidden') not in ('read','edit') then
    raise exception 'Fixed asset value access is required for activation' using errcode='42501';
  end if;
  if p_action='dispose' and coalesce(v_access->>'assetValues','hidden')<>'edit' then
    raise exception 'Fixed asset value fields are not editable' using errcode='42501';
  end if;
  if p_action='dispose'
     and (
       nullif(p_payload->>'fundAccountId','') is not null
       or nullif(btrim(coalesce(p_payload->>'referenceNo','')),'') is not null
     )
     and coalesce(v_access->>'assetReferences','hidden')<>'edit' then
    raise exception 'Fixed asset disposal references are not editable' using errcode='42501';
  end if;
  v_saved := public.act_fms_fixed_asset(p_asset_id,p_action,p_payload);
  return app_private.fms_fixed_asset_to_secure_json(
    app_private.fms_fixed_asset_raw_json(v_saved.id),v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.calculate_fms_asset_depreciation_secure(
  p_accounting_period_id uuid,p_remark text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_period public.fms_accounting_period%rowtype; v_saved public.fms_asset_depreciation_run%rowtype;
begin
  select * into v_period from public.fms_accounting_period p
  where p.id=p_accounting_period_id and p.tenant_id=app_private.current_user_tenant_id();
  if not found then raise exception 'Accounting period does not exist in the current tenant' using errcode='P0002'; end if;
  if app_private.resolve_field_access('fms.fixed_asset','assetValues',null)<>'edit' then
    raise exception 'Fixed asset value fields are not editable' using errcode='42501';
  end if;
  v_saved := public.calculate_fms_asset_depreciation(p_accounting_period_id,p_remark);
  return app_private.fms_asset_depreciation_run_to_secure_json(
    to_jsonb(v_saved)-'tenant_id'-'created_by_user_id',v_saved.created_by_user_id
  );
end;
$$;

create or replace function public.act_fms_asset_depreciation_run_secure(
  p_run_id uuid,p_action text,p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare v_run public.fms_asset_depreciation_run%rowtype; v_saved public.fms_asset_depreciation_run%rowtype;
begin
  select * into v_run from public.fms_asset_depreciation_run r
  where r.id=p_run_id and r.tenant_id=app_private.current_user_tenant_id() for update;
  if not found then raise exception 'Depreciation run does not exist in the current tenant' using errcode='P0002'; end if;
  if p_action='post' and app_private.resolve_field_access('fms.fixed_asset','assetValues',null)<>'edit' then
    raise exception 'Fixed asset value fields are not editable' using errcode='42501';
  end if;
  v_saved := public.act_fms_asset_depreciation_run(p_run_id,p_action,p_reason);
  return app_private.fms_asset_depreciation_run_to_secure_json(
    to_jsonb(v_saved)-'tenant_id'-'created_by_user_id',v_saved.created_by_user_id
  );
end;
$$;

revoke all on table public.fms_fixed_asset from anon,authenticated;
revoke all on table public.fms_asset_category from anon,authenticated;
revoke all on table public.fms_asset_depreciation_run from anon,authenticated;
revoke all on table public.fms_asset_depreciation_line from anon,authenticated;

revoke execute on function public.save_fms_asset_category(jsonb) from public,anon,authenticated;
revoke execute on function public.delete_fms_asset_category(uuid) from public,anon,authenticated;
revoke execute on function public.save_fms_fixed_asset(jsonb) from public,anon,authenticated;
revoke execute on function public.delete_fms_fixed_asset(uuid) from public,anon,authenticated;
revoke execute on function public.act_fms_fixed_asset(uuid,text,jsonb) from public,anon,authenticated;
revoke execute on function public.calculate_fms_asset_depreciation(uuid,text) from public,anon,authenticated;
revoke execute on function public.act_fms_asset_depreciation_run(uuid,text,text) from public,anon,authenticated;
revoke execute on function public.fms_fixed_asset_summary(uuid,uuid) from public,anon,authenticated;

revoke all on function public.fms_list_asset_categories_secure(uuid,uuid) from public,anon,authenticated;
revoke all on function public.fms_list_fixed_assets_secure(integer,integer,uuid,uuid,text,text,uuid) from public,anon,authenticated;
revoke all on function public.fms_get_fixed_asset_secure(uuid) from public,anon,authenticated;
revoke all on function public.fms_list_asset_depreciation_runs_secure(uuid,uuid) from public,anon,authenticated;
revoke all on function public.fms_list_asset_depreciation_lines_secure(uuid) from public,anon,authenticated;
revoke all on function public.fms_fixed_asset_summary_secure(uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.save_fms_asset_category_secure(jsonb) from public,anon,authenticated;
revoke all on function public.delete_fms_asset_category_secure(uuid) from public,anon,authenticated;
revoke all on function public.save_fms_fixed_asset_secure(jsonb) from public,anon,authenticated;
revoke all on function public.delete_fms_fixed_asset_secure(uuid) from public,anon,authenticated;
revoke all on function public.act_fms_fixed_asset_secure(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.calculate_fms_asset_depreciation_secure(uuid,text) from public,anon,authenticated;
revoke all on function public.act_fms_asset_depreciation_run_secure(uuid,text,text) from public,anon,authenticated;

grant execute on function public.fms_list_asset_categories_secure(uuid,uuid) to authenticated;
grant execute on function public.fms_list_fixed_assets_secure(integer,integer,uuid,uuid,text,text,uuid) to authenticated;
grant execute on function public.fms_get_fixed_asset_secure(uuid) to authenticated;
grant execute on function public.fms_list_asset_depreciation_runs_secure(uuid,uuid) to authenticated;
grant execute on function public.fms_list_asset_depreciation_lines_secure(uuid) to authenticated;
grant execute on function public.fms_fixed_asset_summary_secure(uuid,uuid,uuid) to authenticated;
grant execute on function public.save_fms_asset_category_secure(jsonb) to authenticated;
grant execute on function public.delete_fms_asset_category_secure(uuid) to authenticated;
grant execute on function public.save_fms_fixed_asset_secure(jsonb) to authenticated;
grant execute on function public.delete_fms_fixed_asset_secure(uuid) to authenticated;
grant execute on function public.act_fms_fixed_asset_secure(uuid,text,jsonb) to authenticated;
grant execute on function public.calculate_fms_asset_depreciation_secure(uuid,text) to authenticated;
grant execute on function public.act_fms_asset_depreciation_run_secure(uuid,text,text) to authenticated;

do $$
begin
  if exists(select 1 from public.sys_tenant t where not exists(
    select 1 from public.sys_permission_resource r
    where r.tenant_id=t.id and r.resource_key='fms.fixed_asset'
      and r.owner_column='created_by_user_id' and r.enabled
  )) then raise exception 'Missing fms.fixed_asset permission resource'; end if;
  if exists(select 1 from public.sys_permission_resource r
    where r.resource_key='fms.fixed_asset' and (
      select count(*) from public.sys_permission_field f
      where f.tenant_id=r.tenant_id and f.resource_id=r.id and f.enabled
    )<>3) then raise exception 'Unexpected fms.fixed_asset field catalog'; end if;
  if has_table_privilege('authenticated','public.fms_fixed_asset','select')
     or has_table_privilege('authenticated','public.fms_asset_category','select')
     or has_table_privilege('authenticated','public.fms_asset_depreciation_run','select')
     or has_table_privilege('authenticated','public.fms_asset_depreciation_line','select')
     or has_table_privilege('anon','public.fms_fixed_asset','select')
     or has_table_privilege('anon','public.fms_asset_category','select')
     or has_table_privilege('anon','public.fms_asset_depreciation_run','select')
     or has_table_privilege('anon','public.fms_asset_depreciation_line','select') then
    raise exception 'Direct fixed asset reads remain exposed';
  end if;
  if has_function_privilege('anon','public.fms_list_fixed_assets_secure(integer,integer,uuid,uuid,text,text,uuid)','execute')
     or has_function_privilege('authenticated','public.save_fms_fixed_asset(jsonb)','execute') then
    raise exception 'Fixed asset function privileges are not secure';
  end if;
end;
$$;

;
