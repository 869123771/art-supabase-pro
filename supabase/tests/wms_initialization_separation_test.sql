-- Real RPC/RLS regression; every business mutation and audit entry rolls back.
BEGIN;
CREATE TEMP TABLE initialization_test_context AS
WITH ordinary AS (
 SELECT u.auth_user_id,u.tenant_id FROM public.sys_user u
 JOIN public.sys_role r ON r.tenant_id=u.tenant_id AND r.role_code=ANY(u.user_roles) AND r.enabled
 JOIN public.sys_role_menu rm ON rm.role_id=r.id AND rm.tenant_id=r.tenant_id
 JOIN public.sys_menu m ON m.id=rm.menu_id
 WHERE u.status='1' AND r.builtin_type IS DISTINCT FROM 'platform_super'
 AND m.name='WmsInitializationClose:View' LIMIT 1
), super_user AS (
 SELECT u.auth_user_id,u.tenant_id FROM public.sys_user u
 JOIN public.sys_role r ON r.tenant_id=u.tenant_id AND r.role_code=ANY(u.user_roles)
 WHERE u.status='1' AND r.enabled AND r.builtin_type='platform_super' LIMIT 1
)
SELECT ordinary.auth_user_id ordinary_id,ordinary.tenant_id,super_user.auth_user_id super_id,
 super_user.tenant_id other_tenant,i.organization_id,
 (SELECT id FROM public.wms_purchase_document WHERE tenant_id=ordinary.tenant_id AND status='approved' AND kind='initial_inbound' LIMIT 1) purchase_id,
 (SELECT id FROM public.wms_purchase_document WHERE tenant_id=ordinary.tenant_id AND status='draft' AND kind='initial_return' LIMIT 1) purchase_return_id,
 (SELECT id FROM public.wms_sales_document WHERE tenant_id=ordinary.tenant_id AND status='draft' AND kind='initial_return' LIMIT 1) sales_return_id
FROM ordinary CROSS JOIN super_user JOIN public.wms_inventory_initialization i ON i.tenant_id=ordinary.tenant_id;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM initialization_test_context WHERE purchase_id IS NOT NULL AND purchase_return_id IS NOT NULL AND sales_return_id IS NOT NULL) THEN
  RAISE EXCEPTION 'Missing initialization regression fixtures'; END IF;
END $$;
GRANT SELECT ON initialization_test_context TO authenticated;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',super_id,'role','authenticated')::text,true) FROM initialization_test_context;
SELECT set_config('request.headers','{}',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE ctx record; first_id uuid; before_stock jsonb; before_movements bigint; rows jsonb; BEGIN
 SELECT * INTO ctx FROM initialization_test_context;
 SELECT jsonb_agg(jsonb_build_array(id,quantity,unit_cost) ORDER BY id) INTO before_stock FROM public.wms_inventory_batch;
 SELECT count(*) INTO before_movements FROM public.wms_inventory_movement;
 first_id:=public.wms_push_initial_obligation_secure('purchase',ctx.purchase_id);
 IF public.wms_push_initial_obligation_secure('purchase',ctx.purchase_id)<>first_id THEN RAISE EXCEPTION 'Duplicate push created another balance'; END IF;
 IF (SELECT total_amount FROM public.wms_initial_obligation WHERE id=first_id) IS DISTINCT FROM
  (SELECT sum(total_amount) FROM public.wms_purchase_document_line WHERE document_id=ctx.purchase_id) THEN RAISE EXCEPTION 'Payable amount differs from source'; END IF;
 IF before_movements<>(SELECT count(*) FROM public.wms_inventory_movement) OR before_stock IS DISTINCT FROM
  (SELECT jsonb_agg(jsonb_build_array(id,quantity,unit_cost) ORDER BY id) FROM public.wms_inventory_batch) THEN RAISE EXCEPTION 'Opening payable changed stock/cost'; END IF;
 rows:=public.wms_initialization_reconciliation_secure(ctx.organization_id);
 IF jsonb_array_length(rows)=0 THEN RAISE EXCEPTION 'Empty reconciliation fixture'; END IF;
 PERFORM set_config('request.headers',jsonb_build_object('x-art-tenant-scope',ctx.other_tenant)::text,true);
 BEGIN PERFORM public.wms_initialization_reconciliation_secure(ctx.organization_id); RAISE EXCEPTION 'Selected scope leaked another tenant'; EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN NULL; END;
 BEGIN PERFORM public.wms_push_initial_obligation_secure('purchase',ctx.purchase_id); RAISE EXCEPTION 'Selected scope wrote another tenant'; EXCEPTION WHEN insufficient_privilege OR invalid_parameter_value THEN NULL; END;
 PERFORM set_config('request.headers',jsonb_build_object('x-art-tenant-scope',ctx.tenant_id)::text,true);
 IF public.wms_push_initial_obligation_secure('purchase',ctx.purchase_id)<>first_id THEN RAISE EXCEPTION 'Selected scope push is not idempotent'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',ctx.ordinary_id,'role','authenticated')::text,true);
 PERFORM set_config('request.headers',jsonb_build_object('x-art-tenant-scope',ctx.other_tenant)::text,true);
 IF app_private.current_read_tenant_id()<>ctx.tenant_id OR public.wms_initialization_reconciliation_secure(ctx.organization_id) IS DISTINCT FROM rows THEN RAISE EXCEPTION 'Ordinary forged header changed scope'; END IF;
 IF public.wms_push_initial_obligation_secure('purchase',ctx.purchase_id)<>first_id THEN RAISE EXCEPTION 'Ordinary authorized push failed'; END IF;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',super_id,'role','authenticated')::text,true) FROM initialization_test_context;
SELECT set_config('request.headers','{}',true);
-- Align test-only legacy dates to the activation date before exercising the real status RPCs.
UPDATE public.wms_purchase_document d SET business_date=i.enabled_on FROM public.wms_inventory_initialization i,initialization_test_context ctx WHERE d.id=ctx.purchase_return_id AND i.organization_id=ctx.organization_id;
UPDATE public.wms_sales_document d SET business_date=i.enabled_on FROM public.wms_inventory_initialization i,initialization_test_context ctx WHERE d.id=ctx.sales_return_id AND i.organization_id=ctx.organization_id;
SET LOCAL ROLE authenticated;
DO $$ DECLARE ctx record; before_stock jsonb; before_movements bigint; ledger_id uuid; BEGIN
 SELECT * INTO ctx FROM initialization_test_context;
 SELECT jsonb_agg(jsonb_build_array(id,quantity,unit_cost) ORDER BY id) INTO before_stock FROM public.wms_inventory_batch;
 SELECT count(*) INTO before_movements FROM public.wms_inventory_movement;
 PERFORM public.wms_change_purchase_document_status_secure(ctx.purchase_return_id,'submit');
 PERFORM public.wms_change_purchase_document_status_secure(ctx.purchase_return_id,'approve');
 PERFORM public.wms_change_sales_document_status_secure(ctx.sales_return_id,'submit');
 PERFORM public.wms_change_sales_document_status_secure(ctx.sales_return_id,'approve');
 ledger_id:=public.wms_push_initial_obligation_secure('purchase',ctx.purchase_return_id);
 IF (SELECT total_amount FROM public.wms_initial_obligation WHERE id=ledger_id)>=0 THEN RAISE EXCEPTION 'Purchase return did not reduce payable'; END IF;
 ledger_id:=public.wms_push_initial_obligation_secure('sales',ctx.sales_return_id);
 IF (SELECT total_amount FROM public.wms_initial_obligation WHERE id=ledger_id)>=0 THEN RAISE EXCEPTION 'Sales return did not reduce receivable'; END IF;
 IF before_movements<>(SELECT count(*) FROM public.wms_inventory_movement) OR before_stock IS DISTINCT FROM
  (SELECT jsonb_agg(jsonb_build_array(id,quantity,unit_cost) ORDER BY id) FROM public.wms_inventory_batch) THEN RAISE EXCEPTION 'Opening returns changed stock/cost'; END IF;
END $$;
RESET ROLE;
-- Formal movement period gates are tested inside this same rollback transaction.
DO $$ DECLARE ctx record; d public.wms_initial_stock_document%rowtype; l public.wms_initial_stock_line%rowtype;
 new_document uuid:=gen_random_uuid(); new_line uuid:=gen_random_uuid(); posted uuid; before_movements bigint; line_columns text; BEGIN
 SELECT * INTO ctx FROM initialization_test_context;
 SELECT * INTO d FROM public.wms_initial_stock_document WHERE organization_id=ctx.organization_id AND status='approved' LIMIT 1;
 SELECT * INTO l FROM public.wms_initial_stock_line WHERE document_id=d.id LIMIT 1;
 IF l.id IS NULL THEN RAISE EXCEPTION 'Missing opening stock regression fixture'; END IF;
 INSERT INTO public.wms_initial_stock_document SELECT (jsonb_populate_record(NULL::public.wms_initial_stock_document,
  to_jsonb(d)||jsonb_build_object('id',new_document,'document_no','QA-OPENING-'||new_document,'status','draft'))).*;
 SELECT string_agg(quote_ident(attname),',' ORDER BY attnum) INTO line_columns FROM pg_attribute
 WHERE attrelid='public.wms_initial_stock_line'::regclass AND attnum>0 AND NOT attisdropped AND attgenerated='';
 EXECUTE format('INSERT INTO public.wms_initial_stock_line(%s) SELECT %s FROM jsonb_populate_record(NULL::public.wms_initial_stock_line,$1)',line_columns,line_columns)
 USING to_jsonb(l)||jsonb_build_object('id',new_line,'document_id',new_document,'movement_id',NULL);
 PERFORM public.wms_change_initial_stock_status_secure(new_document,'submit');
 BEGIN PERFORM public.wms_change_initial_stock_status_secure(new_document,'approve');
  RAISE EXCEPTION 'Repeated opening grain accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 UPDATE public.mdm_material SET batch_management_enabled=true,
 batch_rule_id=(SELECT id FROM public.mdm_supply_chain_code_rule WHERE tenant_id=ctx.tenant_id LIMIT 1)
 WHERE id=l.material_id;
 UPDATE public.wms_initial_stock_line SET batch_no=NULL WHERE id=new_line;
 BEGIN PERFORM public.wms_change_initial_stock_status_secure(new_document,'approve');
  RAISE EXCEPTION 'Managed opening material without batch accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 UPDATE public.wms_initial_stock_line SET batch_no='QA-OPENING-'||new_line,opening_quantity=3,base_quantity=3,amount=15 WHERE id=new_line;
 PERFORM public.wms_change_initial_stock_status_secure(new_document,'approve');
 SELECT movement_id INTO posted FROM public.wms_initial_stock_line WHERE id=new_line;
 IF (SELECT unit_cost FROM public.wms_inventory_movement WHERE id=posted)<>5 THEN RAISE EXCEPTION 'Opening cost ignored explicit amount'; END IF;
 SELECT count(*) INTO before_movements FROM public.wms_inventory_movement;
 BEGIN PERFORM public.wms_change_initial_stock_status_secure(new_document,'approve'); EXCEPTION WHEN check_violation THEN NULL; END;
 IF before_movements<>(SELECT count(*) FROM public.wms_inventory_movement) THEN RAISE EXCEPTION 'Opening approval duplicated movements'; END IF;
END $$;
DO $$ DECLARE ctx record; b public.wms_inventory_batch%rowtype; BEGIN
 SELECT * INTO ctx FROM initialization_test_context;
 SELECT * INTO b FROM public.wms_inventory_batch WHERE organization_id=ctx.organization_id AND quantity>0 LIMIT 1;
 IF b.id IS NULL THEN RAISE EXCEPTION 'Missing stocked batch for period regression'; END IF;
 BEGIN
  INSERT INTO public.wms_inventory_movement(tenant_id,movement_type,target_batch_id,material_id,quantity,unit_cost,reference_no,occurred_at)
  VALUES(b.tenant_id,'other_in',b.id,b.material_id,1,b.unit_cost,'QA-INITIALIZATION-PERIOD',now());
  RAISE EXCEPTION 'Formal movement before initialization close accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
UPDATE public.wms_inventory_initialization i SET initialization_closed_at=now() FROM initialization_test_context ctx WHERE i.organization_id=ctx.organization_id;
DO $$ DECLARE ctx record; BEGIN
 SELECT * INTO ctx FROM initialization_test_context;
 BEGIN UPDATE public.wms_purchase_document SET remark='FORGED' WHERE id=ctx.purchase_id; RAISE EXCEPTION 'Closed document mutation allowed'; EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN UPDATE public.wms_sales_document_line SET quantity=quantity WHERE document_id=ctx.sales_return_id; RAISE EXCEPTION 'Closed line mutation allowed'; EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM public.sys_audit_log WHERE command_tag='WMS_INITIALIZATION_UPDATE' AND tenant_id=ctx.tenant_id AND create_time=now()) THEN RAISE EXCEPTION 'Initialization audit missing'; END IF;
 IF EXISTS(SELECT 1 FROM public.wms_inventory_batch b JOIN public.wms_inventory_movement m ON m.target_batch_id=b.id WHERE m.movement_type='initial_purchase_in' AND b.quantity<>0) THEN RAISE EXCEPTION 'Legacy opening purchases still inflate stock'; END IF;
 IF has_function_privilege('anon','public.wms_push_initial_obligation_secure(text,uuid)','EXECUTE') OR has_table_privilege('authenticated','public.wms_initial_obligation','INSERT') THEN RAISE EXCEPTION 'Opening ledger bypass exposed'; END IF;
END $$;
DO $$ DECLARE ctx record; b public.wms_inventory_batch%rowtype; BEGIN
 SELECT * INTO ctx FROM initialization_test_context;
 SELECT * INTO b FROM public.wms_inventory_batch WHERE organization_id=ctx.organization_id AND quantity>0 LIMIT 1;
 BEGIN
  INSERT INTO public.wms_inventory_movement(tenant_id,movement_type,target_batch_id,material_id,quantity,unit_cost,reference_no,occurred_at)
  SELECT b.tenant_id,'other_in',b.id,b.material_id,1,b.unit_cost,'QA-INITIALIZATION-PERIOD',enabled_on-interval '1 day'
  FROM public.wms_inventory_initialization WHERE organization_id=ctx.organization_id;
  RAISE EXCEPTION 'Formal movement predating activation accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO public.wms_inventory_movement(tenant_id,movement_type,target_batch_id,material_id,quantity,unit_cost,reference_no,occurred_at)
 VALUES(b.tenant_id,'other_in',b.id,b.material_id,1,b.unit_cost,'QA-INITIALIZATION-PERIOD',now());
END $$;
ROLLBACK;
