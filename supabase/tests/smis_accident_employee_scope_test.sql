-- Transactional regression: no test roles, employee records or user-role changes persist.
begin;
create temporary table accident_employee_scope_fixture(super_id uuid, user_id uuid, tenant_id uuid, other_id uuid, code text) on commit drop;
do $test$
declare
  v_super uuid;
  v_user uuid;
  v_tenant uuid;
  v_other uuid;
  v_position_own uuid;
  v_position_other uuid;
  v_role uuid;
  v_code text := 'smis_employee_test_' || replace(gen_random_uuid()::text, '-', '');
begin
  select u.auth_user_id into v_super
  from public.sys_user u
  join public.sys_tenant t on t.id = u.tenant_id
  join public.sys_role r on r.tenant_id = u.tenant_id and r.role_code = any(u.user_roles)
  where t.builtin_type = 'platform' and r.builtin_type = 'platform_super'
    and u.status = '1' and u.deleted_at is null and u.auth_user_id is not null
  limit 1;
  select u.auth_user_id, u.tenant_id into v_user, v_tenant
  from public.sys_user u join public.sys_tenant t on t.id = u.tenant_id
  where t.builtin_type is distinct from 'platform' and u.status = '1'
    and u.deleted_at is null and u.auth_user_id is not null
    and exists (select 1 from public.mdm_position p where p.tenant_id = u.tenant_id)
  limit 1;
  select id into v_other from public.sys_tenant where id <> v_tenant
    and builtin_type is distinct from 'platform'
    and exists (select 1 from public.mdm_position p where p.tenant_id = sys_tenant.id) limit 1;
  if v_super is null or v_user is null or v_other is null then
    raise exception 'Requires a platform super, an ordinary user and two business tenants';
  end if;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_super, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{}', true);
  select id into v_position_own from public.mdm_position where tenant_id = v_tenant limit 1;
  select id into v_position_other from public.mdm_position where tenant_id = v_other limit 1;
  insert into public.mdm_position(tenant_id, position_code, position_name, organization_id, job_profile_id, grade_id)
  select tenant_id, v_code || '_position_own', v_code || '_position_own', organization_id, job_profile_id, grade_id
  from public.mdm_position where id = v_position_own returning id into v_position_own;
  insert into public.mdm_position(tenant_id, position_code, position_name, organization_id, job_profile_id, grade_id)
  select tenant_id, v_code || '_position_other', v_code || '_position_other', organization_id, job_profile_id, grade_id
  from public.mdm_position where id = v_position_other returning id into v_position_other;
  insert into public.mdm_employee(tenant_id, employee_no, employee_name, employment_status, position_id, organization_id, phone, email, id_card_no)
  select v_tenant, v_code || '_own', v_code || '_own', 'active', id, organization_id, '13900000001', v_code || '_own@example.invalid', '110101199001010011'
  from public.mdm_position where id = v_position_own
  union all
  select v_other, v_code || '_other', v_code || '_other', 'probation', id, organization_id, '13900000002', v_code || '_other@example.invalid', '110101199001010022'
  from public.mdm_position where id = v_position_other;
  insert into public.sys_role(role_name, role_code, tenant_id, create_by)
  values ('Accident employee scope verification', v_code, v_tenant, 'verification') returning id into v_role;
  insert into public.sys_role_menu(role_id, menu_id, tenant_id, create_by)
  select v_role, id, v_tenant, 'verification' from public.sys_menu where name = 'SmisAccidentFlashReport:Add';
  update public.sys_user set user_roles = array[v_code] where auth_user_id = v_user;
  insert into accident_employee_scope_fixture values (v_super, v_user, v_tenant, v_other, v_code);
end;
$test$;
do $test$
declare
  v_super uuid;
  v_user uuid;
  v_tenant uuid;
  v_other uuid;
  v_code text;
  v_result jsonb;
  v_scope text;
  v_expected integer;
begin
  select super_id, user_id, tenant_id, other_id, code into v_super, v_user, v_tenant, v_other, v_code
  from accident_employee_scope_fixture;
  foreach v_scope in array array['platform_all', 'platform_selected', 'ordinary_own', 'ordinary_forged'] loop
    perform set_config('request.jwt.claims', jsonb_build_object(
      'sub', case when v_scope like 'platform%' then v_super else v_user end, 'role', 'authenticated')::text, true);
    perform set_config('request.headers', case when v_scope in ('platform_selected', 'ordinary_forged')
      then jsonb_build_object('x-art-tenant-scope', v_other)::text else '{}' end, true);
    v_result := public.smis_list_accident_employee_candidates_secure(0, 199, v_code);
    v_expected := case when v_scope = 'platform_all' then 2 else 1 end;
    if (v_result->>'total')::integer <> v_expected or jsonb_array_length(v_result->'records') <> v_expected then
      raise exception 'Wrong candidate count for %: %', v_scope, v_result;
    end if;
    if exists (select 1 from jsonb_array_elements(v_result->'records') item
      where jsonb_typeof(item) <> 'object' or item->>'id' is null or item->>'tenantId' is null
        or item->>'employeeName' is null or item->>'employeeNo' is null) then
      raise exception 'Missing employee snapshot in %', v_scope;
    end if;
    if v_scope <> 'platform_all' and exists (select 1 from jsonb_array_elements(v_result->'records') item
      where (item->>'tenantId')::uuid <> case when v_scope = 'platform_selected' then v_other else v_tenant end) then
      raise exception 'Tenant projection leak for %', v_scope;
    end if;
    if not exists (select 1 from jsonb_array_elements(v_result->'records') item
      where item->>'employeeName' = v_code || case when v_scope = 'platform_selected' then '_other' else '_own' end) then
      raise exception 'Expected employee snapshot absent for %', v_scope;
    end if;
  end loop;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_super, 'role', 'authenticated')::text, true);
  perform set_config('request.headers', '{}', true);
  update public.sys_user set user_roles = array[]::text[] where auth_user_id = v_user;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  begin
    perform public.smis_list_accident_employee_candidates_secure(0, 199, v_code);
    raise exception 'Unauthorized employee read accepted';
  exception when raise_exception then
    if sqlerrm <> '当前账号无权选择事故相关人员' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '{}', true);
  begin
    perform public.smis_list_accident_employee_candidates_secure(0, 199, v_code);
    raise exception 'Unauthenticated employee read accepted';
  exception when raise_exception then
    if sqlerrm <> '当前账号无权选择事故相关人员' then raise; end if;
  end;
  if has_function_privilege('anon', 'public.smis_list_accident_employee_candidates_secure(integer,integer,text)', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.smis_list_accident_employee_candidates_secure(integer,integer,text)', 'EXECUTE') then
    raise exception 'Accident employee RPC execution grants changed';
  end if;
end;
$test$;
rollback;
