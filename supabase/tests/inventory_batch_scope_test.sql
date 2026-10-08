-- Exercise real RPCs and RLS; all stock, rule counters and configuration changes roll back.
BEGIN;
CREATE TEMP TABLE inventory_test_context AS
WITH ordinary AS (
  SELECT u.auth_user_id, u.tenant_id FROM public.sys_user u
  WHERE u.status='1' AND u.deleted_at IS NULL AND u.auth_user_id IS NOT NULL
    AND EXISTS (SELECT 1 FROM public.sys_role r JOIN public.sys_role_menu rm ON rm.role_id=r.id
      JOIN public.sys_menu menu ON menu.id=rm.menu_id
      WHERE r.tenant_id=u.tenant_id AND r.enabled AND r.role_code=ANY(u.user_roles)
        AND menu.name='WmsStockOperation:Receive')
    AND NOT EXISTS (SELECT 1 FROM public.sys_role r WHERE r.tenant_id=u.tenant_id
      AND r.role_code=ANY(u.user_roles) AND r.builtin_type='platform_super')
    AND EXISTS (SELECT 1 FROM public.wms_initial_stock_line WHERE tenant_id=u.tenant_id)
  LIMIT 1
), super_user AS (
  SELECT u.auth_user_id,u.tenant_id FROM public.sys_user u JOIN public.sys_role r
    ON r.tenant_id=u.tenant_id AND r.role_code=ANY(u.user_roles)
  WHERE u.status='1' AND r.enabled AND r.builtin_type='platform_super' LIMIT 1
)
SELECT ordinary.auth_user_id ordinary_id,ordinary.tenant_id,super_user.auth_user_id super_id,
  super_user.tenant_id other_tenant,
  (SELECT id FROM public.mdm_material WHERE tenant_id=ordinary.tenant_id AND status='enabled'
    AND NOT serial_management_enabled AND NOT batch_management_enabled LIMIT 1) material_id,
  (SELECT id FROM public.mdm_warehouse WHERE tenant_id=ordinary.tenant_id AND status='enabled'
    AND NOT enable_locations AND warehouse_type='raw_material' LIMIT 1) warehouse_id,
  (SELECT id FROM public.mdm_supply_chain_code_rule WHERE tenant_id=ordinary.tenant_id
    AND status='enabled' AND apply_batch LIMIT 1) rule_id
FROM ordinary CROSS JOIN super_user;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM inventory_test_context WHERE material_id IS NOT NULL
    AND warehouse_id IS NOT NULL AND rule_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Missing authorized inventory test fixtures';
  END IF;
END $$;
GRANT SELECT ON inventory_test_context TO authenticated;
-- Formal movements require an activated, closed initialization period.
UPDATE public.wms_inventory_initialization i
SET initialization_closed_at=coalesce(i.initialization_closed_at,now())
FROM inventory_test_context ctx
WHERE i.tenant_id=ctx.tenant_id;
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',super_id,'role','authenticated')::text,true)
FROM inventory_test_context;
SELECT set_config('request.headers','{}',true);
SET LOCAL ROLE authenticated;
DO $$ DECLARE ctx record; all_count integer; selected_count integer; BEGIN
  SELECT * INTO ctx FROM inventory_test_context;
  all_count:=(public.wms_inventory_report_secure('stock')->>'total')::integer;
  PERFORM set_config('request.headers',jsonb_build_object('x-art-tenant-scope',ctx.tenant_id)::text,true);
  selected_count:=(public.wms_inventory_report_secure('stock')->>'total')::integer;
  IF all_count<selected_count OR selected_count=0 THEN RAISE EXCEPTION 'Platform scope fixture failed'; END IF;
  IF (public.wms_inventory_report_secure('stock',p_tenant_id=>ctx.other_tenant)->>'total')::integer<>0 THEN
    RAISE EXCEPTION 'Platform selected scope leaked other tenant'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',ctx.ordinary_id,'role','authenticated')::text,true);
  PERFORM set_config('request.headers',jsonb_build_object('x-art-tenant-scope',ctx.other_tenant)::text,true);
  IF app_private.current_read_tenant_id()<>ctx.tenant_id THEN RAISE EXCEPTION 'Forged header changed ordinary tenant'; END IF;
  IF (public.wms_inventory_report_secure('stock')->>'total')::integer<>selected_count THEN
    RAISE EXCEPTION 'Ordinary own inventory differs from selected platform inventory'; END IF;
  IF (public.wms_inventory_report_secure('stock',p_tenant_id=>ctx.other_tenant)->>'total')::integer<>0 THEN
    RAISE EXCEPTION 'Ordinary report leaked another tenant'; END IF;
END $$;
DO $$ DECLARE ctx record; movement_id uuid; batch_id uuid; batch_no text; supplied text; ledger_row jsonb; BEGIN
  SELECT * INTO ctx FROM inventory_test_context;
  FOREACH supplied IN ARRAY ARRAY['','QA-MANUAL-BATCH'] LOOP
    movement_id:=public.wms_post_inventory_movement_secure(jsonb_build_object(
      'movement_type','other_in','quantity',1,'material_id',ctx.material_id,
      'warehouse_id',ctx.warehouse_id,'batch_no',supplied,'reference_no','QA-BATCH-ROLLBACK'));
    SELECT b.batch_no,b.id INTO batch_no,batch_id FROM public.wms_inventory_movement m
      JOIN public.wms_inventory_batch b ON b.id=m.target_batch_id WHERE m.id=movement_id;
    IF batch_no IS DISTINCT FROM supplied THEN RAISE EXCEPTION 'Optional/manual batch was not preserved'; END IF;
    SELECT value INTO ledger_row FROM jsonb_array_elements(public.wms_inventory_report_secure('ledger',p_limit=>200)->'data')
      WHERE value->>'batch_id'=batch_id::text;
    IF ledger_row IS NULL OR (ledger_row->>'opening_quantity')::numeric<>0
      OR (ledger_row->>'inbound_quantity')::numeric<>1 OR (ledger_row->>'closing_quantity')::numeric<>1 THEN
      RAISE EXCEPTION 'Daily receipt did not reconcile with ledger'; END IF;
    SELECT value INTO ledger_row FROM jsonb_array_elements(public.wms_inventory_report_secure('ledger',p_date_start=>current_date+1,p_limit=>200)->'data')
      WHERE value->>'batch_id'=batch_id::text;
    IF ledger_row IS NULL OR (ledger_row->>'opening_quantity')::numeric<>1
      OR (ledger_row->>'inbound_quantity')::numeric<>0 OR (ledger_row->>'closing_quantity')::numeric<>1 THEN
      RAISE EXCEPTION 'Date range did not carry earlier receipt into opening'; END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.wms_inventory_report_secure('stock',p_limit=>200)->'data')
      WHERE value->>'batch_id'=batch_id::text AND (value->>'inventory_quantity')::numeric=1) THEN
      RAISE EXCEPTION 'Daily receipt missing from immediate stock'; END IF;
    IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.wms_inventory_report_secure('movement',p_limit=>200)->'data')
      WHERE value->>'batch_id'=batch_id::text AND (value->>'inbound_quantity')::numeric=1)
      OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(public.wms_inventory_report_secure('receipt-issue',p_limit=>200)->'data')
      WHERE value->>'batch_id'=batch_id::text AND (value->>'inbound_quantity')::numeric=1) THEN
      RAISE EXCEPTION 'Daily receipt missing from movement or material receipt-issue report'; END IF;
  END LOOP;
END $$;
RESET ROLE;
UPDATE public.mdm_material SET batch_management_enabled=true,batch_rule_id=ctx.rule_id
FROM inventory_test_context ctx WHERE id=ctx.material_id;
SET LOCAL ROLE authenticated;
DO $$ DECLARE ctx record; movement_id uuid; generated text; BEGIN
  SELECT * INTO ctx FROM inventory_test_context;
  movement_id:=public.wms_post_inventory_movement_secure(jsonb_build_object(
    'movement_type','other_in','quantity',1,'material_id',ctx.material_id,
    'warehouse_id',ctx.warehouse_id,'batch_no','FORGED-MANUAL','reference_no','QA-AUTO-ROLLBACK'));
  SELECT b.batch_no INTO generated FROM public.wms_inventory_movement m
    JOIN public.wms_inventory_batch b ON b.id=m.target_batch_id WHERE m.id=movement_id;
  IF nullif(generated,'') IS NULL OR generated='FORGED-MANUAL' THEN
    RAISE EXCEPTION 'Managed batch did not use server code rule'; END IF;
END $$;
-- A source balance with an empty batch number must also support a normal issue.
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',super_id,'role','authenticated')::text,true),
  set_config('request.headers',jsonb_build_object('x-art-tenant-scope',tenant_id)::text,true)
FROM inventory_test_context;
DO $$ DECLARE ctx record; source_id uuid; movement_id uuid; BEGIN
  SELECT * INTO ctx FROM inventory_test_context;
  SELECT m.target_batch_id INTO source_id FROM public.wms_inventory_movement m
    JOIN public.wms_inventory_batch b ON b.id=m.target_batch_id
    WHERE m.reference_no='QA-BATCH-ROLLBACK' AND b.batch_no=''
      AND b.material_id=ctx.material_id AND b.warehouse_id=ctx.warehouse_id
    ORDER BY m.occurred_at DESC LIMIT 1;
  IF source_id IS NULL THEN RAISE EXCEPTION 'Missing empty-batch receipt fixture'; END IF;
  movement_id:=public.wms_post_inventory_movement_secure(jsonb_build_object(
    'movement_type','other_out','quantity',1,'batch_id',source_id,
    'warehouse_id',ctx.warehouse_id,'reference_no','QA-EMPTY-BATCH-ISSUE'));
  IF NOT EXISTS(SELECT 1 FROM public.wms_inventory_movement WHERE id=movement_id
    AND source_batch_id=source_id AND movement_type='other_out') THEN
    RAISE EXCEPTION 'Empty batch could not be issued'; END IF;
END $$;
ROLLBACK;
