
create or replace function public.trg_guard_sys_user_authorization_fields()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  v_is_service_role boolean := current_user in ('postgres', 'service_role')
    or coalesce(auth.jwt() ->> 'role', '') = 'service_role';
  v_is_self boolean := old.auth_user_id = auth.uid();
  v_roles_changed boolean := new.user_roles is distinct from old.user_roles;
  v_authorization_changed boolean :=
    new.tenant_id is distinct from old.tenant_id
    or new.organization_id is distinct from old.organization_id
    or new.user_type is distinct from old.user_type
    or new.status is distinct from old.status
    or new.auth_user_id is distinct from old.auth_user_id;
  v_profile_changed boolean :=
    new.user_name is distinct from old.user_name
    or new.nick_name is distinct from old.nick_name
    or new.user_gender is distinct from old.user_gender
    or new.user_phone is distinct from old.user_phone
    or new.user_email is distinct from old.user_email
    or new.extra is distinct from old.extra
    or new.remark is distinct from old.remark
    or new.avatar is distinct from old.avatar;
begin
  if v_is_service_role then
    return new;
  end if;

  if new.id is distinct from old.id
    or new.create_by is distinct from old.create_by
    or new.create_time is distinct from old.create_time
  then
    raise exception '用户主键和创建信息不可修改';
  end if;

  if v_roles_changed
    and not app_private.has_permission('System:User:AssignRole')
  then
    raise exception '缺少用户角色分配权限';
  end if;

  if v_authorization_changed
    and not app_private.has_permission('System:User:Edit')
  then
    raise exception '缺少用户管理权限，不能修改租户、组织、类型或账号状态';
  end if;

  if v_profile_changed
    and not v_is_self
    and not app_private.has_permission('System:User:Edit')
  then
    raise exception '缺少用户编辑权限';
  end if;

  return new;
end;
$function$;
;
