BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
SELECT set_config('request.headers','{}',true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE tenant uuid; supplier uuid; material uuid; unit_name text; order_id uuid; copied uuid; receipt uuid; line1 uuid:=gen_random_uuid(); line2 uuid:=gen_random_uuid(); lines jsonb; targets uuid[];
BEGIN
 SELECT m.tenant_id,m.id,coalesce(u.unit_name,m.basic_unit) INTO tenant,material,unit_name FROM public.mdm_material m LEFT JOIN public.mdm_unit_of_measure u ON u.id=m.base_unit_id WHERE (m.purchase_unit_id=m.base_unit_id OR m.purchase_unit_id IS NULL) AND m.auxiliary_unit_id IS NULL AND m.auxiliary_unit_2_id IS NULL LIMIT 1;
 SELECT id INTO supplier FROM public.mdm_supplier WHERE tenant_id=tenant LIMIT 1;
 IF supplier IS NULL THEN RAISE EXCEPTION 'Missing test supplier'; END IF;
 lines:=jsonb_build_array(jsonb_build_object('line_id',line1,'line_no',10,'material_id',material,'material_code','QA-ORDER','material_description','采购测试','unit',unit_name,'base_unit',unit_name,'quantity',10,'base_quantity',10,'unit_price',1.2345,'tax_rate',13,'tax_inclusive_unit_price',1.395,'discount_mode','none','discount_rate',0),jsonb_build_object('line_id',line2,'line_no',20,'material_id',material,'material_code','QA-ORDER2','material_description','采购测试2','unit',unit_name,'base_unit',unit_name,'quantity',20,'base_quantity',20,'unit_price',1.2345,'tax_rate',13,'tax_inclusive_unit_price',1.395,'discount_mode','none','discount_rate',0));
 INSERT INTO public.scm_purchase_document(tenant_id,kind,document_no,supplier_id,document_date,lines) VALUES(tenant,'purchase_order','AUTO',supplier,current_date,lines) RETURNING id INTO order_id;
 PERFORM public.scm_purchase_batch_secure('copy',jsonb_build_array(jsonb_build_object('document_id',order_id,'line_ids',jsonb_build_array(line2))));
 SELECT id INTO copied FROM public.scm_purchase_document d WHERE d.id<>order_id AND d.kind='purchase_order' AND d.tenant_id=tenant AND d.lines->0->>'material_code'='QA-ORDER2' ORDER BY created_at DESC LIMIT 1;
 IF copied IS NULL OR (SELECT jsonb_array_length(d.lines)<>1 OR d.lines->0->>'line_id'=line2::text FROM public.scm_purchase_document d WHERE id=copied) THEN RAISE EXCEPTION 'Order selected-line copy failed'; END IF;
 PERFORM public.scm_purchase_batch_secure('delete',jsonb_build_array(jsonb_build_object('document_id',order_id,'line_ids',jsonb_build_array(line2))));
 IF (SELECT jsonb_array_length(d.lines) FROM public.scm_purchase_document d WHERE id=order_id)<>1 THEN RAISE EXCEPTION 'Order selected-line delete failed'; END IF;
 PERFORM public.scm_purchase_batch_secure('submit',jsonb_build_array(jsonb_build_object('document_id',order_id,'line_ids',jsonb_build_array(line1))));
 UPDATE public.scm_purchase_document SET status='approved' WHERE id=order_id;
 INSERT INTO public.scm_purchase_document(tenant_id,kind,document_no,supplier_id,document_date,details,lines) VALUES(tenant,'receipt_notice','AUTO',supplier,current_date,'{"construction_no":"提醒，不阻断"}',jsonb_build_array((lines->0)||jsonb_build_object('line_id',gen_random_uuid(),'source_purchase_document_id',order_id,'source_line_id',line1,'quantity',2,'base_quantity',2))) RETURNING id INTO receipt;
 IF (SELECT d.lines->0->>'unit_price' FROM public.scm_purchase_document d WHERE id=receipt)<>'1.2345' THEN RAISE EXCEPTION 'Receipt lost four-decimal order price'; END IF;
 BEGIN UPDATE public.scm_purchase_document SET lines=jsonb_set(scm_purchase_document.lines,'{0,tax_rate}','17') WHERE id=receipt; RAISE EXCEPTION 'Invalid receipt dictionary tax accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 targets:=public.scm_push_purchase_orders_secure(jsonb_build_array(jsonb_build_object('document_id',order_id,'line_ids',jsonb_build_array(line1))));
 IF cardinality(targets)<>1 OR (SELECT count(*) FROM public.scm_order_target_line WHERE target_document_id=targets[1])<>1 THEN RAISE EXCEPTION 'Exact selected WMS push failed'; END IF;
 BEGIN PERFORM public.scm_push_purchase_orders_secure(jsonb_build_array(jsonb_build_object('document_id',order_id,'line_ids',jsonb_build_array(line1)))); RAISE EXCEPTION 'Duplicate push accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);
 BEGIN PERFORM public.scm_purchase_batch_secure('copy',jsonb_build_array(jsonb_build_object('document_id',order_id,'line_ids',null))); RAISE EXCEPTION 'Selected scope bypass'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $test$;
ROLLBACK;
