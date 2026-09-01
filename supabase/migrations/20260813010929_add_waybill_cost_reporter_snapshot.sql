alter table public.tms_waybill_cost
  add column if not exists reporter_user_id uuid,
  add column if not exists reporter_name_snapshot text,
  add column if not exists reporter_department_snapshot text;

comment on column public.tms_waybill_cost.reporter_user_id is
  '填报人的系统用户 ID；用户删除后保留费用历史快照';
comment on column public.tms_waybill_cost.reporter_name_snapshot is
  '费用创建时的填报人姓名快照';
comment on column public.tms_waybill_cost.reporter_department_snapshot is
  '费用创建时的填报人所属部门快照';

with reporter_snapshot as (
  select
    c.id as cost_id,
    u.id as reporter_user_id,
    coalesce(
      nullif(btrim(u.nick_name), ''),
      nullif(btrim(u.user_name), ''),
      nullif(btrim(u.user_email), ''),
      nullif(btrim(c.create_by), ''),
      '系统'
    ) as reporter_name_snapshot,
    coalesce(nullif(btrim(o.organization_name), ''), '未归属部门')
      as reporter_department_snapshot
  from public.tms_waybill_cost c
  join public.sys_user u
    on u.tenant_id = c.tenant_id
   and lower(u.user_email) = lower(c.create_by)
   and u.deleted_at is null
  left join public.sys_organization o on o.id = u.organization_id
)
update public.tms_waybill_cost c
set
  reporter_user_id = snapshot.reporter_user_id,
  reporter_name_snapshot = snapshot.reporter_name_snapshot,
  reporter_department_snapshot = snapshot.reporter_department_snapshot
from reporter_snapshot snapshot
where c.id = snapshot.cost_id;

update public.tms_waybill_cost
set
  reporter_name_snapshot = coalesce(nullif(btrim(create_by), ''), '系统'),
  reporter_department_snapshot = '未归属部门'
where reporter_name_snapshot is null
   or reporter_department_snapshot is null;

alter table public.tms_waybill_cost
  alter column reporter_name_snapshot set not null,
  alter column reporter_department_snapshot set not null;

alter table public.tms_waybill_cost
  drop constraint if exists tms_waybill_cost_reporter_user_id_fkey;

alter table public.tms_waybill_cost
  add constraint tms_waybill_cost_reporter_user_id_fkey
  foreign key (reporter_user_id)
  references public.sys_user(id)
  on delete set null;

create index if not exists tms_waybill_cost_reporter_user_id_idx
  on public.tms_waybill_cost(reporter_user_id);

create or replace function app_private.trg_set_waybill_cost_reporter_snapshot()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app_private
as $$
declare
  v_reporter_user_id uuid;
  v_reporter_name text;
  v_reporter_department text;
  v_auth_user_id uuid := (select auth.uid());
begin
  if tg_op = 'UPDATE' then
    new.reporter_user_id := old.reporter_user_id;
    new.reporter_name_snapshot := old.reporter_name_snapshot;
    new.reporter_department_snapshot := old.reporter_department_snapshot;
    return new;
  end if;

  select
    u.id,
    coalesce(
      nullif(btrim(u.nick_name), ''),
      nullif(btrim(u.user_name), ''),
      nullif(btrim(u.user_email), '')
    ),
    coalesce(nullif(btrim(o.organization_name), ''), '未归属部门')
  into v_reporter_user_id, v_reporter_name, v_reporter_department
  from public.sys_user u
  left join public.sys_organization o on o.id = u.organization_id
  where u.deleted_at is null
    and (
      (v_auth_user_id is not null and u.auth_user_id = v_auth_user_id)
      or (
        v_auth_user_id is null
        and u.tenant_id = new.tenant_id
        and lower(u.user_email) = lower(new.create_by)
      )
    )
  order by case when u.auth_user_id = v_auth_user_id then 0 else 1 end
  limit 1;

  new.reporter_user_id := v_reporter_user_id;
  new.reporter_name_snapshot := coalesce(
    v_reporter_name,
    nullif(btrim(new.create_by), ''),
    '系统'
  );
  new.reporter_department_snapshot := coalesce(v_reporter_department, '未归属部门');

  return new;
end;
$$;

revoke all on function app_private.trg_set_waybill_cost_reporter_snapshot()
  from public, anon, authenticated;

drop trigger if exists tms_waybill_cost_reporter_snapshot
  on public.tms_waybill_cost;

create trigger tms_waybill_cost_reporter_snapshot
before insert or update on public.tms_waybill_cost
for each row
execute function app_private.trg_set_waybill_cost_reporter_snapshot();;
