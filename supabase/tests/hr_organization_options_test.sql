begin;
do $test$
declare v_super uuid; v_user uuid; v_tenant uuid; v_other uuid; v_role uuid; v_code text := 'hr_tree_test_' || replace(gen_random_uuid()::text,'-',''); v_result jsonb; v_feature text;
begin
 select u.auth_user_id into v_super from public.sys_user u join public.sys_tenant t on t.id=u.tenant_id
 join public.sys_role r on r.tenant_id=u.tenant_id and r.role_code=any(u.user_roles)
 where t.builtin_type='platform' and r.builtin_type='platform_super' and u.status='1' and u.deleted_at is null limit 1;
 select u.auth_user_id,u.tenant_id into v_user,v_tenant from public.sys_user u join public.sys_tenant t on t.id=u.tenant_id
 where t.builtin_type is distinct from 'platform' and u.status='1' and u.deleted_at is null and u.auth_user_id is not null
 and exists(select 1 from public.mdm_organization o where o.tenant_id=u.tenant_id) limit 1;
 select tenant_id into v_other from public.mdm_organization where tenant_id<>v_tenant limit 1;
 if v_super is null or v_user is null or v_other is null then raise exception 'HR tree security test requires super, ordinary user and two organization tenants'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',v_super,'role','authenticated')::text,true);
 perform set_config('request.headers','{}',true);
 if not app_private.is_platform_super() then raise exception 'Selected test super is not platform super'; end if;
 foreach v_feature in array array['absence','performance','headcount','lifecycle','experience','compensationReview','contingentWorkforce','policyAcknowledgement','organizationDesign','internalMobility','personnelChange','recruitment','talent'] loop
 v_result:=public.hr_list_business_organization_options_secure(v_feature,null);
 if jsonb_array_length(v_result)<>(select count(*) from public.mdm_organization) then raise exception 'Platform all scope incomplete for %',v_feature; end if;
 end loop;
 v_result:=public.hr_list_contingent_workforce_options_secure('sponsor',null);
 if jsonb_array_length(v_result)<>(select count(*) from public.mdm_employee where employment_status='active') then raise exception 'Sponsor all scope incomplete'; end if;
 if exists(select 1 from jsonb_array_elements(v_result) x where x->>'tenant_id' is null) then raise exception 'Sponsor tenant projection missing'; end if;
 perform set_config('request.headers',jsonb_build_object('x-art-tenant-scope',v_other)::text,true);
 v_result:=public.hr_list_business_organization_options_secure('recruitment',null);
 if exists(select 1 from jsonb_array_elements(v_result) x where (x->>'tenant_id')::uuid<>v_other) then raise exception 'Platform selected tenant leak'; end if;
 if jsonb_array_length(v_result)<>(select count(*) from public.mdm_organization where tenant_id=v_other) then raise exception 'Selected scope incomplete'; end if;
 insert into public.sys_role(role_name,role_code,tenant_id,create_by) values('HR organization tree verification',v_code,v_tenant,'verification') returning id into v_role;
 insert into public.sys_role_menu(role_id,menu_id,tenant_id,create_by)
 select v_role,id,v_tenant,'verification' from public.sys_menu where name in ('HrRecruitment','Hr:Recruitment:View','HrContingentWorkforce','Hr:ContingentWorkforce:View');
 update public.sys_user set user_roles=array[v_code] where auth_user_id=v_user;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user,'role','authenticated')::text,true);
 perform set_config('request.headers','{}',true);
 if app_private.has_permission('Hr:Employee:View') then raise exception 'Test ordinary user unexpectedly has employee permission'; end if;
 v_result:=public.hr_list_business_organization_options_secure('recruitment',null);
 if jsonb_array_length(v_result)<>(select count(*) from public.mdm_organization where tenant_id=v_tenant) then raise exception 'Domain only ordinary scope incomplete'; end if;
 perform set_config('request.headers',jsonb_build_object('x-art-tenant-scope',v_other)::text,true);
 v_result:=public.hr_list_business_organization_options_secure('recruitment',v_other);
 if exists(select 1 from jsonb_array_elements(v_result) x where (x->>'tenant_id')::uuid<>v_tenant) then raise exception 'Forged ordinary scope leaked'; end if;
 if jsonb_array_length(v_result)<>(select count(*) from public.mdm_organization where tenant_id=v_tenant) then raise exception 'Forged scope hid own tenant'; end if;
 v_result:=public.hr_list_contingent_workforce_options_secure('sponsor',v_other);
 if exists(select 1 from jsonb_array_elements(v_result) x where x->>'tenant_id' is null or (x->>'tenant_id')::uuid<>v_tenant) then raise exception 'Sponsor forged scope leaked or tenant missing'; end if;
 if jsonb_array_length(v_result)<>(select count(*) from public.mdm_employee where tenant_id=v_tenant and employment_status='active') then raise exception 'Sponsor own scope incomplete'; end if;
 begin perform public.hr_list_business_organization_options_secure('organizationDesign',null); raise exception 'Unauthorized domain accepted'; exception when insufficient_privilege then null; end;
 begin perform public.hr_list_business_organization_options_secure('unknown',null); raise exception 'Unknown domain accepted'; exception when invalid_parameter_value then null; end;
 perform set_config('request.jwt.claims','{}',true);
 begin perform public.hr_list_business_organization_options_secure('recruitment',null); raise exception 'Unauthenticated call accepted'; exception when insufficient_privilege then null; end;
end;
$test$;
rollback;
