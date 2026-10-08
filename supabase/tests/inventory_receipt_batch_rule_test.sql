-- Receipt entry regression on this project's existing verification fixtures; always rolled back.
BEGIN;
CREATE TEMP TABLE opening_receipt_test AS SELECT gen_random_uuid() document_id,gen_random_uuid() line_id;
INSERT INTO public.wms_initial_stock_document
SELECT (jsonb_populate_record(null::public.wms_initial_stock_document,to_jsonb(d)||jsonb_build_object(
'id',ctx.document_id,'document_no','QA-OPEN-'||left(ctx.document_id::text,8),'status','submitted','approved_at',null))).*
FROM public.wms_initial_stock_document d CROSS JOIN opening_receipt_test ctx
WHERE d.tenant_id='7529f951-938e-4e2c-ac0d-316c136ae1f9' AND d.status='approved' LIMIT 1;
INSERT INTO public.wms_initial_stock_line (id,tenant_id,document_id,line_no,material_id,project_id,construction_no,gift,unit_price,amount,inventory_unit_id,opening_quantity,base_unit_id,base_quantity,yearly_received_quantity,yearly_issued_quantity,batch_no,inbound_date,warehouse_id,bin_id,stock_type,owner_type,owner_id,stock_status,keeper_id,auxiliary_unit_id,opening_aux_quantity,yearly_received_aux_quantity,yearly_issued_aux_quantity,production_date,expiry_date,tracking_no,source_document,remark,serial_nos,movement_id)
SELECT ctx.line_id,l.tenant_id,ctx.document_id,l.line_no,l.material_id,l.project_id,l.construction_no,l.gift,l.unit_price,l.amount,l.inventory_unit_id,l.opening_quantity,l.base_unit_id,l.base_quantity,l.yearly_received_quantity,l.yearly_issued_quantity,null::text,l.inbound_date,'d97f5bc1-73c4-4617-9225-b0af0327875f'::uuid,null::uuid,l.stock_type,l.owner_type,l.owner_id,l.stock_status,l.keeper_id,l.auxiliary_unit_id,l.opening_aux_quantity,l.yearly_received_aux_quantity,l.yearly_issued_aux_quantity,l.production_date,l.expiry_date,l.tracking_no,l.source_document,l.remark,l.serial_nos,null::uuid
FROM public.wms_initial_stock_line l CROSS JOIN opening_receipt_test ctx
WHERE l.tenant_id='7529f951-938e-4e2c-ac0d-316c136ae1f9' AND l.material_id='48f856a4-f34d-4573-b30a-8d7681ec74d0' LIMIT 1;
UPDATE public.mdm_material SET batch_management_enabled=true,batch_rule_id='8a018dfe-8314-4922-996c-79cb96454a63' WHERE id='48f856a4-f34d-4573-b30a-8d7681ec74d0';
SELECT set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
SELECT set_config('request.headers','{}',true);
SELECT public.wms_change_initial_stock_status_secure(document_id,'approve') FROM opening_receipt_test;
SELECT jsonb_build_object('lineBatch',l.batch_no,'stockBatch',b.batch_no,'quantity',b.quantity) result FROM opening_receipt_test ctx JOIN public.wms_initial_stock_line l ON l.id=ctx.line_id JOIN wms_inventory_movement m ON m.id=l.movement_id JOIN wms_inventory_batch b ON b.id=m.target_batch_id;
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM opening_receipt_test ctx
 JOIN public.wms_initial_stock_line l ON l.id=ctx.line_id
 JOIN public.wms_inventory_movement m ON m.id=l.movement_id
 JOIN public.wms_inventory_batch b ON b.id=m.target_batch_id
 WHERE nullif(l.batch_no,'') IS NOT NULL AND l.batch_no=b.batch_no) THEN
 RAISE EXCEPTION 'Initial stock approval did not persist generated batch'; END IF;
END $$;
ROLLBACK;
BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
SELECT set_config('request.headers','{}',true);
UPDATE public.wms_inventory_initialization SET initialization_closed_at=now() WHERE organization_id='8fbc1836-d0ea-4afd-98c6-f557ab40fe4f';
UPDATE public.mdm_material SET batch_management_enabled=true,batch_rule_id='8a018dfe-8314-4922-996c-79cb96454a63' WHERE id IN(SELECT material_id FROM wms_purchase_document_line WHERE document_id='fee3c0cd-ad85-4c67-b83a-5629d475da4b');
UPDATE public.wms_purchase_document_line SET batch_no=null WHERE document_id='fee3c0cd-ad85-4c67-b83a-5629d475da4b';
SELECT app_private.wms_post_purchase_document_stock('fee3c0cd-ad85-4c67-b83a-5629d475da4b');
SELECT b.batch_no,l.batch_no line_batch FROM public.wms_purchase_document_line l JOIN wms_inventory_movement m ON m.id=l.movement_id JOIN wms_inventory_batch b ON b.id=m.target_batch_id WHERE l.document_id='fee3c0cd-ad85-4c67-b83a-5629d475da4b';
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.wms_purchase_document_line WHERE document_id='fee3c0cd-ad85-4c67-b83a-5629d475da4b' AND movement_id IS NOT NULL) THEN
 RAISE EXCEPTION 'Purchase receipt fixture did not post'; END IF;
 IF EXISTS(SELECT 1 FROM public.wms_purchase_document_line l
 JOIN public.wms_inventory_movement m ON m.id=l.movement_id JOIN public.wms_inventory_batch b ON b.id=m.target_batch_id
 WHERE l.document_id='fee3c0cd-ad85-4c67-b83a-5629d475da4b'
 AND (nullif(l.batch_no,'') IS NULL OR l.batch_no IS DISTINCT FROM b.batch_no)) THEN
 RAISE EXCEPTION 'Purchase receipt generated batch differs between document and stock'; END IF;
END $$;
ROLLBACK;

