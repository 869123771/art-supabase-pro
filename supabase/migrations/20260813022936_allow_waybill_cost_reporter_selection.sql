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
  if tg_op = 'UPDATE'
     and new.tenant_id is not distinct from old.tenant_id
     and new.reporter_user_id is not distinct from old.reporter_user_id then
    new.reporter_user_id := old.reporter_user_id;
    new.reporter_name_snapshot := old.reporter_name_snapshot;
    new.reporter_department_snapshot := old.reporter_department_snapshot;
    return new;
  end if;

  if new.reporter_user_id is null then
    select u.id
    into v_reporter_user_id
    from public.sys_user u
    where u.auth_user_id = v_auth_user_id
      and u.tenant_id = new.tenant_id
      and u.status = '1'
      and u.deleted_at is null
    limit 1;
  else
    v_reporter_user_id := new.reporter_user_id;
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
  where u.id = v_reporter_user_id
    and u.tenant_id = new.tenant_id
    and u.status = '1'
    and u.deleted_at is null;

  if v_reporter_user_id is null or v_reporter_name is null then
    raise exception '所选填报人不存在、已停用或不属于当前费用租户'
      using errcode = 'P0001';
  end if;

  new.reporter_user_id := v_reporter_user_id;
  new.reporter_name_snapshot := v_reporter_name;
  new.reporter_department_snapshot := v_reporter_department;

  return new;
end;
$$;

revoke all on function app_private.trg_set_waybill_cost_reporter_snapshot()
  from public, anon, authenticated;

comment on function app_private.trg_set_waybill_cost_reporter_snapshot() is
  '按费用所属租户校验填报人，并由系统用户资料生成不可伪造的姓名与部门快照';;
