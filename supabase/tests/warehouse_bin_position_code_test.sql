-- Transactional regression: only synthetic warehouse/bin records, always rolled back.
BEGIN;
CREATE TEMP TABLE bin_test_context AS
WITH ordinary AS (
 SELECT u.auth_user_id,u.tenant_id FROM public.sys_user u
 WHERE u.status='1' AND u.deleted_at IS NULL AND u.auth_user_id IS NOT NULL
 AND (SELECT count(DISTINCT m.name) FROM public.sys_role r
 JOIN public.sys_role_menu rm ON rm.role_id=r.id AND rm.tenant_id=r.tenant_id
 JOIN public.sys_menu m ON m.id=rm.menu_id
 WHERE r.tenant_id=u.tenant_id AND r.enabled AND r.role_code=ANY(u.user_roles)
 AND m.name=ANY(ARRAY['MdmWarehouseBin:Generate','MdmWarehouseBin:Add','MdmWarehouseBin:Edit','MdmWarehouseBin:Delete']))=4
 AND NOT EXISTS(SELECT 1 FROM public.sys_role r WHERE r.tenant_id=u.tenant_id AND r.builtin_type='platform_super' AND r.role_code=ANY(u.user_roles))
 ORDER BY u.create_time LIMIT 1
), super_user AS (
 SELECT u.auth_user_id,u.tenant_id FROM public.sys_user u JOIN public.sys_role r
 ON r.tenant_id=u.tenant_id AND r.role_code=ANY(u.user_roles)
 WHERE u.status='1' AND r.builtin_type='platform_super' AND r.enabled LIMIT 1
)
SELECT ordinary.auth_user_id ordinary_id,ordinary.tenant_id,
 super_user.auth_user_id super_id,super_user.tenant_id other_tenant,
 gen_random_uuid() warehouse_id,gen_random_uuid() other_warehouse_id,
 (SELECT auth_user_id FROM public.sys_user WHERE status='1' AND auth_user_id IS NOT NULL AND coalesce(cardinality(user_roles),0)=0 LIMIT 1) denied_id
FROM ordinary CROSS JOIN super_user;
DO $$ BEGIN IF (SELECT count(*) FROM bin_test_context)<>1 THEN RAISE EXCEPTION 'Missing tenant test principals'; END IF; END $$;
GRANT SELECT ON bin_test_context TO authenticated;
INSERT INTO public.mdm_warehouse(id,tenant_id,warehouse_code,warehouse_name,enable_locations,enable_zones,warehouse_type)
SELECT warehouse_id,tenant_id,'QA-BIN-'||upper(left(warehouse_id::text,8)),'库位编码事务测试',true,false,'raw_material' FROM bin_test_context
UNION ALL SELECT other_warehouse_id,other_tenant,'QA-BIN-'||upper(left(other_warehouse_id::text,8)),'跨租户事务测试',true,false,'raw_material' FROM bin_test_context;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',super_id,'role','authenticated')::text,true) FROM bin_test_context;
SELECT set_config('request.headers','{}',true);
SET LOCAL ROLE authenticated;
DO $$
DECLARE ctx record; ids uuid[]; child_id uuid; count_before integer; n integer;
BEGIN
 SELECT * INTO ctx FROM bin_test_context;
 IF public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'a1',2,4,NULL,'-')<>8 THEN RAISE EXCEPTION 'Expected 8 bins'; END IF;
 IF (SELECT array_agg(bin_code ORDER BY bin_code) FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id)
 IS DISTINCT FROM ARRAY['A1-01-01','A1-01-02','A1-01-03','A1-01-04','A1-02-01','A1-02-02','A1-02-03','A1-02-04'] THEN RAISE EXCEPTION 'Coordinate order/padding failed'; END IF;
 IF EXISTS(SELECT 1 FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND tenant_id<>ctx.tenant_id) THEN RAISE EXCEPTION 'Platform all did not inherit warehouse tenant'; END IF;
 IF public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'A1',2,4,99,'-')<>0 THEN RAISE EXCEPTION 'Duplicate generation was not idempotent'; END IF;
 IF EXISTS(SELECT 1 FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND max_quantity IS NOT NULL) THEN RAISE EXCEPTION 'Existing capacities overwritten'; END IF;
 BEGIN
  PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'A1',2,4,NULL,'_');
  RAISE EXCEPTION 'Separator changed on existing shelf';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 BEGIN
  PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'INVALID',1,1,NULL,'/');
  RAISE EXCEPTION 'Invalid separator accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
 PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'B1',1,2,NULL,'_');
 PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'C1',1,2,NULL,'');
 IF NOT EXISTS(SELECT 1 FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND bin_code='B1_01_02') OR
 NOT EXISTS(SELECT 1 FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND bin_code='C10102') THEN RAISE EXCEPTION 'Alternative separator failed'; END IF;
 SELECT array_agg(id ORDER BY id) INTO ids FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND shelf_code='B1';
 PERFORM public.mdm_update_warehouse_shelf_secure(ctx.warehouse_id,NULL,'B1','B1',2,3,false,NULL,ids);
 IF NOT EXISTS(SELECT 1 FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND bin_code='B1_02_03') OR
 (SELECT count(*) FROM public.mdm_warehouse_bin WHERE id=ANY(ids))<>2 THEN RAISE EXCEPTION 'Expansion failed or replaced original IDs'; END IF;
 BEGIN
  UPDATE public.mdm_warehouse_bin SET code_separator='-',bin_code=replace(bin_code,'_','-') WHERE id=ids[1];
  RAISE EXCEPTION 'Generated identity mutation accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 SELECT array_agg(id ORDER BY id) INTO ids FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND shelf_code='A1';
 INSERT INTO public.mdm_warehouse_bin(tenant_id,warehouse_id,parent_id,bin_code,bin_name,bin_type)
 SELECT ctx.tenant_id,ctx.warehouse_id,id,'CHILD-01','测试子单元','floor'
 FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND bin_code='A1-02-04' RETURNING id INTO child_id;
 SELECT count(*) INTO count_before FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id;
 BEGIN
  PERFORM public.mdm_update_warehouse_shelf_secure(ctx.warehouse_id,NULL,'A1','A1',1,4,true,88,ids);
  RAISE EXCEPTION 'Shrink deleted referenced bins';
 EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 IF (SELECT count(*) FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id)<>count_before OR
 EXISTS(SELECT 1 FROM public.mdm_warehouse_bin WHERE id=ANY(ids) AND max_quantity IS NOT NULL) THEN RAISE EXCEPTION 'Rejected shrink left partial mutations'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.get_record_delete_dependency_details('mdm_warehouse_bin',ARRAY(SELECT id::text FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND bin_code='A1-02-04')) WHERE record_no IN ('测试子单元','CHILD-01')) THEN RAISE EXCEPTION 'Missing recognizable delete reference'; END IF;
 PERFORM public.mdm_delete_warehouse_bins_secure(ARRAY[child_id]);
 PERFORM public.mdm_update_warehouse_shelf_secure(ctx.warehouse_id,NULL,'A1','A1',1,4,false,NULL,ids);
 IF (SELECT count(*) FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND shelf_code='A1')<>4 THEN RAISE EXCEPTION 'Unreferenced shrink failed'; END IF;
 BEGIN
  PERFORM public.mdm_update_warehouse_shelf_secure(ctx.warehouse_id,NULL,'A1','A1',1,4,false,NULL,ids);
  RAISE EXCEPTION 'Stale expected IDs accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO public.mdm_warehouse_bin(tenant_id,warehouse_id,bin_code,bin_name,bin_type)
 VALUES(ctx.tenant_id,ctx.warehouse_id,'D1-01-02','冲突测试','floor');
 BEGIN
  PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'D1',1,2,NULL,'-');
  RAISE EXCEPTION 'Conflicting code accepted';
 EXCEPTION WHEN unique_violation THEN NULL; END;
 IF EXISTS(SELECT 1 FROM public.mdm_warehouse_bin WHERE warehouse_id=ctx.warehouse_id AND bin_code='D1-01-01') THEN RAISE EXCEPTION 'Conflict left partial shelf'; END IF;
 BEGIN
  INSERT INTO public.mdm_warehouse_bin(tenant_id,warehouse_id,bin_code,bin_name,bin_type)
  VALUES(ctx.tenant_id,ctx.warehouse_id,'','空编码测试','floor');
  RAISE EXCEPTION 'Blank code still auto-numbered';
 EXCEPTION WHEN check_violation THEN NULL; END;
 -- Platform-selected reads and writes.
 PERFORM set_config('request.headers',jsonb_build_object('x-art-tenant-scope',ctx.tenant_id)::text,true);
 PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'SELECTED',1,1,NULL,'-');
 BEGIN
  PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.other_warehouse_id,NULL,'CROSS',1,1,NULL,'-');
  RAISE EXCEPTION 'Platform-selected escaped tenant';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 -- Ordinary user: forged scope must not grant a cross-tenant capability.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',ctx.ordinary_id,'role','authenticated')::text,true);
 PERFORM set_config('request.headers',jsonb_build_object('x-art-tenant-scope',ctx.other_tenant)::text,true);
 PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'OWN',1,1,NULL,'-');
 BEGIN
  PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.other_warehouse_id,NULL,'FORGED',1,1,NULL,'-');
  RAISE EXCEPTION 'Forged header escaped tenant';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 -- No business permission.
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',ctx.denied_id,'role','authenticated')::text,true);
 BEGIN
  PERFORM public.mdm_generate_warehouse_shelf_secure(ctx.warehouse_id,NULL,'DENIED',1,1,NULL,'-');
  RAISE EXCEPTION 'Missing generation permission accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.sys_document_number_rule WHERE rule_key='master.warehouse_bin') OR
 EXISTS(SELECT 1 FROM public.sys_document_number_scene WHERE rule_key='master.warehouse_bin') OR
 to_regprocedure('app_private.trg_number_warehouse_bin()') IS NOT NULL THEN RAISE EXCEPTION 'Old bin numbering remains'; END IF;
 PERFORM app_private.seed_document_number_rules((SELECT tenant_id FROM bin_test_context));
 IF EXISTS(SELECT 1 FROM public.sys_document_number_rule WHERE rule_key='master.warehouse_bin') THEN RAISE EXCEPTION 'Tenant seed restored obsolete bin rule'; END IF;
END $$;
ROLLBACK;
