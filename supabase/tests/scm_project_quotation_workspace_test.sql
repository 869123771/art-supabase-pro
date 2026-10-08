-- Transactional regression; test writes and temporary permission grants are rolled back.
BEGIN;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);select set_config('request.headers','{}',true);set local role authenticated;
DO $t$ DECLARE r record; tab text; v jsonb; BEGIN
 FOR r IN SELECT id FROM public.mdm_project WHERE id IN('fffaf2e8-8344-4ba4-9bef-1c488c54322f','4cf56c0b-8350-4be5-876d-dcd70bc2e589') LOOP
  v:=public.scm_project_quotation_profile(r.id); IF v->>'id'<>r.id::text THEN RAISE EXCEPTION 'profile mismatch'; END IF;
  FOREACH tab IN ARRAY ARRAY['categories','quotation_lines','contracts','purchase_requests','purchase_orders','stock','movements'] LOOP
    v:=public.scm_project_quotation_tab(r.id,tab,null,20,0);
    IF jsonb_typeof(v->'records')<>'array' OR (v->>'total')::int<0 THEN RAISE EXCEPTION 'invalid tab %',tab; END IF;
  END LOOP;
 END LOOP;
END $t$;reset role;select 'project profiles and all seven data tabs passed' result;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
select set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);set local role authenticated;
DO $t$ BEGIN
 IF (public.scm_project_quotation_projects(null,null,20,0)->>'total')::int<>0 THEN RAISE EXCEPTION 'selected tenant leaked'; END IF;
 BEGIN PERFORM public.scm_project_quotation_profile('fffaf2e8-8344-4ba4-9bef-1c488c54322f'); RAISE EXCEPTION 'selected profile leaked'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $t$; reset role;
INSERT INTO public.sys_role_menu(tenant_id,role_id,menu_id)
SELECT r.tenant_id,r.id,m.id FROM public.sys_user u JOIN public.sys_role r ON r.tenant_id=u.tenant_id AND r.role_code=ANY(u.user_roles) AND r.enabled JOIN public.sys_menu m ON m.name IN('ScmProjectQuotation:View','ScmQuoteCategory:View','ScmSalesQuotationDoc:View') WHERE u.auth_user_id='5774aa51-3bbb-4da5-abd4-7ea44b44ea6a' ON CONFLICT DO NOTHING;
select set_config('request.jwt.claims','{"sub":"5774aa51-3bbb-4da5-abd4-7ea44b44ea6a","role":"authenticated"}',true);
select set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);set local role authenticated;
DO $t$ DECLARE v jsonb; BEGIN
 v:=public.scm_project_quotation_projects(null,null,20,0);
 IF (v->>'total')::int=0 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v->'records') x WHERE x->>'tenant_id'<>'7529f951-938e-4e2c-ac0d-316c136ae1f9') THEN RAISE EXCEPTION 'ordinary own scope incorrect'; END IF;
 PERFORM public.scm_project_quotation_profile('fffaf2e8-8344-4ba4-9bef-1c488c54322f');
 PERFORM public.scm_project_quotation_tab('fffaf2e8-8344-4ba4-9bef-1c488c54322f','categories',null,20,0);
 BEGIN PERFORM public.scm_project_quotation_tab('fffaf2e8-8344-4ba4-9bef-1c488c54322f','stock',null,20,0); RAISE EXCEPTION 'tab permission bypassed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $t$;reset role;select 'selected/ordinary/forged header/tab permission tests passed' result;

select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);select set_config('request.headers','{}',true);
DO $t$
DECLARE source public.scm_sales_document%rowtype; a uuid; b uuid; ca uuid; cb uuid; manual_before int; v jsonb; req uuid; po uuid; batch public.wms_inventory_batch%rowtype; movement public.wms_inventory_movement%rowtype; purchase_lines jsonb;
BEGIN
 SELECT * INTO source FROM public.scm_sales_document WHERE id='06d60a38-7a21-4225-9515-9e7ec0d09676';
 SELECT count(*) INTO manual_before FROM public.scm_quote_category WHERE source_quotation_id IS NULL;
 INSERT INTO public.scm_sales_document(tenant_id,kind,document_type_id,project_id,customer_id,document_no,document_date,details,lines)
 VALUES(source.tenant_id,'sales_quotation',source.document_type_id,source.project_id,source.customer_id,'QA-PROJECT-CAT-A',current_date,source.details||'{"product_category":"QA-逐单分类","quotation_quantity":3}',source.lines) RETURNING id INTO a;
 INSERT INTO public.scm_sales_document(tenant_id,kind,document_type_id,project_id,customer_id,document_no,document_date,details,lines)
 VALUES(source.tenant_id,'sales_quotation',source.document_type_id,source.project_id,source.customer_id,'QA-PROJECT-CAT-B',current_date,source.details||'{"product_category":"QA-逐单分类","quotation_quantity":7}',source.lines) RETURNING id INTO b;
 IF EXISTS(SELECT 1 FROM public.scm_quote_category WHERE source_quotation_id IN(a,b)) THEN RAISE EXCEPTION 'draft generated category'; END IF;
 PERFORM app_private.execute_scm_quotation_workflow_callback(a,'approved','QA','rollback test');
 PERFORM app_private.execute_scm_quotation_workflow_callback(b,'approved','QA','rollback test');
 SELECT id INTO ca FROM public.scm_quote_category WHERE source_quotation_id=a AND quotation_no=(SELECT document_no FROM public.scm_sales_document WHERE id=a) AND quantity=3;
 SELECT id INTO cb FROM public.scm_quote_category WHERE source_quotation_id=b AND quotation_no=(SELECT document_no FROM public.scm_sales_document WHERE id=b) AND quantity=7;
 IF ca IS NULL OR cb IS NULL OR ca=cb THEN RAISE EXCEPTION 'quotes combined or incorrect quantity'; END IF;
 PERFORM app_private.sync_scm_quote_categories_for_project(source.tenant_id,source.project_id,'QA-逐单分类');
 PERFORM app_private.execute_scm_quotation_workflow_callback(a,'approved','QA','retry');
 IF (SELECT count(*) FROM public.scm_quote_category WHERE source_quotation_id IN(a,b))<>2 OR (SELECT id FROM public.scm_quote_category WHERE source_quotation_id=a)<>ca THEN RAISE EXCEPTION 'duplicate category on retry'; END IF;
 IF EXISTS(SELECT 1 FROM public.scm_quote_category c JOIN public.scm_sales_document q ON q.id=c.source_quotation_id WHERE c.source_quotation_id IN(a,b) AND c.total_amount<>q.total_amount) THEN RAISE EXCEPTION 'category amount mismatch'; END IF;
 IF (SELECT count(*) FROM public.scm_quote_category WHERE source_quotation_id IS NULL)<>manual_before THEN RAISE EXCEPTION 'manual category changed'; END IF;
 v:=public.scm_project_quotation_tab(source.project_id,'categories',null,200,0);
 IF (SELECT count(*) FROM jsonb_array_elements(v->'records') r WHERE r->>'document_id' IN(a::text,b::text))<>2 THEN RAISE EXCEPTION 'project category missing'; END IF;
 SELECT lines INTO purchase_lines FROM public.scm_purchase_document WHERE tenant_id=source.tenant_id AND kind='purchase_request' LIMIT 1;
 INSERT INTO public.scm_purchase_document(tenant_id,kind,project_id,document_no,document_date,lines) VALUES(source.tenant_id,'purchase_request',source.project_id,'QA-PROJECT-REQUEST',current_date,purchase_lines) RETURNING id INTO req;

 SELECT (public.scm_convert_quotation_lines('18631a03-d234-40d6-a4c6-968f74380fda','purchase_order',jsonb_build_array(jsonb_build_object('line_id','beb941de-126c-41c1-9426-b89a7cefe034','quantity',1)),gen_random_uuid(),(SELECT id FROM public.mdm_supplier WHERE tenant_id=source.tenant_id LIMIT 1))->>'id')::uuid INTO po;
 UPDATE public.scm_purchase_document SET project_id=source.project_id WHERE id=po;
 v:=public.scm_project_quotation_tab(source.project_id,'purchase_requests',null,200,0);
 IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v->'records') r WHERE r->>'document_id'=req::text AND r->>'status'='draft') THEN RAISE EXCEPTION 'saved request missing'; END IF;
 v:=public.scm_project_quotation_tab(source.project_id,'purchase_orders',null,200,0);
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v->'records') r WHERE r->>'document_id'=po::text) THEN RAISE EXCEPTION 'draft order included'; END IF;
 SELECT * INTO batch FROM public.wms_inventory_batch WHERE tenant_id=source.tenant_id AND quantity>0 LIMIT 1;
 IF batch.id IS NOT NULL THEN
  INSERT INTO public.mdm_project_construction(tenant_id,project_id,construction_no,section_name,status) VALUES(source.tenant_id,source.project_id,'QA-PROJECT-SECTION','QA section','active');
  INSERT INTO public.wms_inventory_batch(tenant_id,warehouse_id,bin_id,material_id,batch_no,quantity,unit_cost,project_id,construction_no) VALUES(batch.tenant_id,batch.warehouse_id,batch.bin_id,batch.material_id,'QA-PROJECT-BATCH',batch.quantity,batch.unit_cost,source.project_id,'QA-PROJECT-SECTION') RETURNING id INTO batch.id;
  v:=public.scm_project_quotation_tab(source.project_id,'stock',null,200,0);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v->'records') r WHERE r->>'id'=batch.id::text AND (r->>'quantity')::numeric=batch.quantity) THEN RAISE EXCEPTION 'real stock missing'; END IF;
 END IF;
 SELECT * INTO movement FROM public.wms_inventory_movement WHERE tenant_id=source.tenant_id LIMIT 1;
 IF movement.id IS NOT NULL THEN
  INSERT INTO public.wms_inventory_movement(tenant_id,movement_type,source_batch_id,target_batch_id,material_id,quantity,unit_cost,reference_no) VALUES(source.tenant_id,'initialization_correction',(SELECT id FROM public.wms_inventory_batch WHERE tenant_id=source.tenant_id AND material_id=batch.material_id AND id<>batch.id AND project_id IS DISTINCT FROM source.project_id LIMIT 1),batch.id,batch.material_id,1,batch.unit_cost,'QA-PROJECT-MOVE') RETURNING id INTO movement.id;
  v:=public.scm_project_quotation_tab(source.project_id,'movements',null,200,0);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v->'records') r WHERE r->>'id'=movement.id::text) THEN RAISE EXCEPTION 'target project movement missing'; END IF;
 END IF;
END $t$;select 'approval/category idempotency/saved requests/draft orders/real stock and movement passed' result;
ROLLBACK;

