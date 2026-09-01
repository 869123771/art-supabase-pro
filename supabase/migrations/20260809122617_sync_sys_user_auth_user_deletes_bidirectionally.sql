
create or replace function public.sync_delete_app_user_on_auth_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  delete from public.sys_user
  where auth_user_id = old.id;

  return old;
end;
$function$;

comment on function public.sync_delete_app_user_on_auth_delete()
  is 'Auth 用户硬删除后同步硬删除 public.sys_user 记录';

revoke all on function public.sync_delete_app_user_on_auth_delete() from public;
revoke all on function public.sync_delete_app_user_on_auth_delete() from anon;
revoke all on function public.sync_delete_app_user_on_auth_delete() from authenticated;

create or replace function app_private.sync_delete_auth_user_on_app_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if old.auth_user_id is not null
     and exists (
       select 1
       from auth.users
       where id = old.auth_user_id
     )
  then
    delete from auth.users
    where id = old.auth_user_id;
  end if;

  return old;
end;
$function$;

comment on function app_private.sync_delete_auth_user_on_app_delete()
  is 'public.sys_user 硬删除后同步硬删除 auth.users 记录';

revoke all on function app_private.sync_delete_auth_user_on_app_delete() from public;
revoke all on function app_private.sync_delete_auth_user_on_app_delete() from anon;
revoke all on function app_private.sync_delete_auth_user_on_app_delete() from authenticated;

drop trigger if exists sys_user_after_delete_sync_auth_user on public.sys_user;

create trigger sys_user_after_delete_sync_auth_user
after delete on public.sys_user
for each row
execute function app_private.sync_delete_auth_user_on_app_delete();
;
