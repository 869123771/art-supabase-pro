create table if not exists public.tms_station_role (
  id uuid primary key default gen_random_uuid(),
  station_id uuid not null,
  role_type text not null,
  create_by text,
  create_time timestamptz not null default now(),
  update_by text,
  update_time timestamptz not null default now(),
  tenant_id uuid not null default app_private.current_user_tenant_id(),
  constraint tms_station_role_station_id_fkey
    foreign key (station_id) references public.tms_station(id) on delete cascade,
  constraint tms_station_role_station_type_key unique (station_id, role_type),
  constraint tms_station_role_type_check
    check (role_type in ('shipping', 'transfer', 'arrival'))
);

comment on table public.tms_station_role is 'TMS 站点业务能力；一个站点可同时作为发货站、到达站或中转站';
comment on column public.tms_station_role.role_type is '站点业务能力：shipping 发货、arrival 到达、transfer 中转';
comment on column public.tms_station.station_type is '兼容字段，保存站点主类型；完整能力以 tms_station_role 为准';

create index if not exists tms_station_role_tenant_type_station_idx
  on public.tms_station_role (tenant_id, role_type, station_id);
create index if not exists tms_station_role_station_id_idx
  on public.tms_station_role (station_id);

create or replace function public.trg_validate_tms_station_role()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_station_tenant_id uuid;
begin
  select station.tenant_id
    into v_station_tenant_id
  from public.tms_station station
  where station.id = new.station_id;

  if not found then
    raise exception '站点不存在或无权维护该站点';
  end if;

  new.tenant_id := v_station_tenant_id;
  new.role_type := btrim(new.role_type);

  if new.role_type not in ('shipping', 'transfer', 'arrival') then
    raise exception '站点类型不正确';
  end if;

  return new;
end;
$$;

drop trigger if exists tms_station_role_validate on public.tms_station_role;
create trigger tms_station_role_validate
before insert or update on public.tms_station_role
for each row execute function public.trg_validate_tms_station_role();

drop trigger if exists tms_station_role_create_audit on public.tms_station_role;
create trigger tms_station_role_create_audit
before insert on public.tms_station_role
for each row execute function public.trg_set_create_time_and_by('true', 'true');

drop trigger if exists tms_station_role_update_audit on public.tms_station_role;
create trigger tms_station_role_update_audit
before update on public.tms_station_role
for each row execute function public.trg_set_update_time_and_by();

alter table public.tms_station_role enable row level security;

drop policy if exists tenant_select on public.tms_station_role;
create policy tenant_select on public.tms_station_role
for select to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

drop policy if exists tenant_insert on public.tms_station_role;
create policy tenant_insert on public.tms_station_role
for insert to authenticated
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

drop policy if exists tenant_update on public.tms_station_role;
create policy tenant_update on public.tms_station_role
for update to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
)
with check (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

drop policy if exists tenant_delete on public.tms_station_role;
create policy tenant_delete on public.tms_station_role
for delete to authenticated
using (
  (select app_private.is_platform_super())
  or tenant_id = (select app_private.current_user_tenant_id())
);

revoke all on table public.tms_station_role from public, anon;
grant select, insert, update, delete on table public.tms_station_role to authenticated;
grant all on table public.tms_station_role to service_role;

insert into public.tms_station_role (
  station_id,
  role_type,
  tenant_id,
  create_by,
  create_time,
  update_by,
  update_time
)
select
  station.id,
  station.station_type,
  station.tenant_id,
  station.create_by,
  station.create_time,
  station.update_by,
  station.update_time
from public.tms_station station
where station.station_type in ('shipping', 'transfer', 'arrival')
on conflict (station_id, role_type) do nothing;

create or replace function public.trg_sync_tms_station_primary_role()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  insert into public.tms_station_role (station_id, role_type, tenant_id)
  values (new.id, new.station_type, new.tenant_id)
  on conflict (station_id, role_type) do nothing;
  return new;
end;
$$;

drop trigger if exists tms_station_sync_primary_role on public.tms_station;
create trigger tms_station_sync_primary_role
after insert or update of station_type on public.tms_station
for each row execute function public.trg_sync_tms_station_primary_role();

create or replace function public.save_tms_station(
  p_station jsonb,
  p_role_types text[]
)
returns public.tms_station
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_station public.tms_station;
  v_station_id uuid;
  v_tenant_id uuid;
  v_station_code text;
  v_station_name text;
  v_role_types text[];
begin
  if p_station is null or jsonb_typeof(p_station) <> 'object' then
    raise exception '站点资料格式不正确';
  end if;

  if p_role_types is null or cardinality(p_role_types) = 0 then
    raise exception '请至少选择一个站点类型';
  end if;

  if exists (
    select 1
    from unnest(p_role_types) role_value
    where btrim(role_value) not in ('shipping', 'transfer', 'arrival')
  ) then
    raise exception '站点类型不正确';
  end if;

  select array_agg(role_type order by role_sort)
    into v_role_types
  from (
    select distinct
      btrim(role_value) as role_type,
      case btrim(role_value)
        when 'shipping' then 10
        when 'transfer' then 20
        when 'arrival' then 30
      end as role_sort
    from unnest(p_role_types) role_value
  ) normalized_roles;

  v_station_id := nullif(p_station ->> 'id', '')::uuid;
  v_station_code := nullif(btrim(coalesce(p_station ->> 'station_code', '')), '');
  v_station_name := btrim(coalesce(p_station ->> 'station_name', ''));

  if v_station_name = '' then
    raise exception '站点名称不能为空';
  end if;

  if v_station_code is null then
    v_station_code := 'ST' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  end if;

  if v_station_id is null then
    v_tenant_id := app_private.current_user_tenant_id();
    if v_tenant_id is null then
      raise exception '当前用户未绑定租户';
    end if;
  else
    select station.tenant_id
      into v_tenant_id
    from public.tms_station station
    where station.id = v_station_id;

    if not found then
      raise exception '站点不存在或无权维护该站点';
    end if;
  end if;

  if exists (
    select 1
    from public.tms_station station
    where station.tenant_id = v_tenant_id
      and station.station_name = v_station_name
      and station.id is distinct from v_station_id
  ) then
    raise exception '站点名称已存在，请编辑已有站点并增加业务类型';
  end if;

  if exists (
    select 1
    from public.tms_station station
    where station.tenant_id = v_tenant_id
      and station.station_code = v_station_code
      and station.id is distinct from v_station_id
  ) then
    raise exception '站点编码已存在';
  end if;

  if v_station_id is null then
    insert into public.tms_station (
      station_code,
      station_name,
      station_type,
      region_code,
      manager_name,
      contact_phone,
      enabled,
      sort,
      remark
    ) values (
      v_station_code,
      v_station_name,
      v_role_types[1],
      nullif(btrim(coalesce(p_station ->> 'region_code', '')), ''),
      nullif(btrim(coalesce(p_station ->> 'manager_name', '')), ''),
      nullif(btrim(coalesce(p_station ->> 'contact_phone', '')), ''),
      coalesce((p_station ->> 'enabled')::boolean, true),
      coalesce((p_station ->> 'sort')::integer, 0),
      nullif(btrim(coalesce(p_station ->> 'remark', '')), '')
    )
    returning * into v_station;
  else
    update public.tms_station station
    set station_code = v_station_code,
        station_name = v_station_name,
        station_type = v_role_types[1],
        region_code = nullif(btrim(coalesce(p_station ->> 'region_code', '')), ''),
        manager_name = nullif(btrim(coalesce(p_station ->> 'manager_name', '')), ''),
        contact_phone = nullif(btrim(coalesce(p_station ->> 'contact_phone', '')), ''),
        enabled = coalesce((p_station ->> 'enabled')::boolean, station.enabled),
        sort = coalesce((p_station ->> 'sort')::integer, station.sort),
        remark = nullif(btrim(coalesce(p_station ->> 'remark', '')), '')
    where station.id = v_station_id
    returning * into v_station;

    if not found then
      raise exception '站点不存在或无权维护该站点';
    end if;
  end if;

  insert into public.tms_station_role (station_id, role_type, tenant_id)
  select v_station.id, role_type, v_station.tenant_id
  from unnest(v_role_types) role_type
  on conflict (station_id, role_type) do nothing;

  delete from public.tms_station_role station_role
  where station_role.station_id = v_station.id
    and not (station_role.role_type = any(v_role_types));

  return v_station;
end;
$$;

create or replace function public.import_tms_stations(p_rows jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row jsonb;
  v_station_json jsonb;
  v_role_types text[];
  v_station_id uuid;
  v_count integer := 0;
begin
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception '导入站点数据格式不正确';
  end if;

  for v_row in select value from jsonb_array_elements(p_rows)
  loop
    select coalesce(array_agg(value), array[]::text[])
      into v_role_types
    from jsonb_array_elements_text(coalesce(v_row -> 'station_types', '[]'::jsonb));

    if cardinality(v_role_types) = 0 and nullif(v_row ->> 'station_type', '') is not null then
      v_role_types := array[v_row ->> 'station_type'];
    end if;

    select station.id
      into v_station_id
    from public.tms_station station
    where station.tenant_id = app_private.current_user_tenant_id()
      and station.station_code = btrim(coalesce(v_row ->> 'station_code', ''));

    v_station_json := (v_row - 'station_types' - 'station_roles' - 'station_type')
      || case
        when v_station_id is null then '{}'::jsonb
        else jsonb_build_object('id', v_station_id)
      end;

    perform public.save_tms_station(v_station_json, v_role_types);
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

revoke all on function public.save_tms_station(jsonb, text[]) from public, anon;
grant execute on function public.save_tms_station(jsonb, text[]) to authenticated, service_role;
revoke all on function public.import_tms_stations(jsonb) from public, anon;
grant execute on function public.import_tms_stations(jsonb) to authenticated, service_role;

notify pgrst, 'reload schema';

;
