-- Rollback-only checks: no user, role, parameter, or tenant changes survive.
begin;
do $$
declare
  v_super public.sys_user%rowtype;
  v_ordinary public.sys_user%rowtype;
  v_other_tenant uuid;
  v_role_name text;
  v_blocked boolean;
begin
  -- Exercise membership triggers for built-in and ordinary tenants too.
  update public.sys_user_tenant set role_codes=role_codes;
  select * into strict v_super from public.sys_user where system_protected;
  select * into strict v_ordinary from public.sys_user
  where not system_protected and deleted_at is null and status='1' and auth_user_id is not null
  order by create_time limit 1;
  select id into strict v_other_tenant from public.sys_tenant
  where id <> v_ordinary.tenant_id and builtin_type is distinct from 'platform' limit 1;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_super.auth_user_id,'role','authenticated')::text,true);
  perform set_config('request.headers','{}',true);
  assert app_private.is_platform_super(), 'protected identity lost platform access';
  assert app_private.current_read_tenant_id() is null, 'platform all scope must be null';
  perform set_config('request.headers',jsonb_build_object('x-art-tenant-scope',v_other_tenant)::text,true);
  assert app_private.current_read_tenant_id() = v_other_tenant, 'selected tenant must remain scoped';
  assert app_private.is_platform_super(), 'selected tenant must not alter capability';
  select role_name into v_role_name from public.sys_role
  where tenant_id=v_super.tenant_id and role_code=v_super.user_roles[1];
  assert v_role_name = any(public.current_user_role_names()), 'role display must use database names';

  v_blocked := false;
  begin update public.sys_user set system_protected=false where id=v_super.id;
  exception when others then v_blocked := true; end;
  assert v_blocked, 'protected identity must be immutable';
  v_blocked := false;
  begin update public.sys_user set deleted_at=now() where id=v_super.id;
  exception when others then v_blocked := true; end;
  assert v_blocked, 'protected identity must reject soft deletion';
  v_blocked := false;
  begin update public.sys_user set auth_user_id=gen_random_uuid() where id=v_super.id;
  exception when others then v_blocked := true; end;
  assert v_blocked, 'protected auth identity must be immutable';
  v_blocked := false;
  begin update public.sys_user set status='2' where id=v_super.id;
  exception when others then v_blocked := true; end;
  assert v_blocked, 'protected identity must reject disable';
  v_blocked := false;
  begin update public.sys_user set user_roles='{}' where id=v_super.id;
  exception when others then v_blocked := true; end;
  assert v_blocked, 'protected identity must retain super role';
  v_blocked := false;
  begin delete from public.sys_user where id=v_super.id;
  exception when others then v_blocked := true; end;
  assert v_blocked, 'protected identity must reject deletion';

  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_ordinary.auth_user_id,'role','authenticated')::text,true);
  perform set_config('request.headers','{}',true);
  assert not app_private.is_platform_super(), 'ordinary identity gained platform access';
  assert app_private.current_read_tenant_id()=v_ordinary.tenant_id, 'ordinary own tenant';
  perform set_config('request.headers',jsonb_build_object('x-art-tenant-scope',v_other_tenant)::text,true);
  assert app_private.current_read_tenant_id()=v_ordinary.tenant_id, 'forged header must be ignored';
  assert not app_private.is_platform_super(), 'forged header must not grant capability';
  v_blocked := false;
  begin update public.sys_user set system_protected=true where id=v_ordinary.id;
  exception when others then v_blocked := true; end;
  assert v_blocked, 'ordinary identity must not become protected';

  v_blocked := false;
  begin update public.sys_param set enabled=true where param_key='audit.logs.retention_days';
  exception when others then v_blocked := true; end;
  assert v_blocked, 'unimplemented policy must not pretend to be enabled';
  assert not exists(select 1 from public.sys_param where param_key like 'audit.%' and enabled);
  assert public.get_login_default_language() in ('zh','en'), 'default language must be usable before login';
  assert not has_function_privilege('anon','public.current_user_role_names()','execute');
  assert has_function_privilege('anon','public.get_login_default_language()','execute');
end $$;
rollback;
