BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
SELECT set_config('request.headers','{}',true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE
  tenant uuid; material uuid; supplier uuid; employee uuid; base_name text; purchase_name text;
  req uuid; req2 uuid; contract uuid; child uuid; copied uuid; type_id uuid; selection jsonb; lines jsonb; line1 uuid:=gen_random_uuid(); line2 uuid:=gen_random_uuid();
BEGIN
  SELECT tenant_id,id INTO tenant,type_id FROM public.mdm_document_type WHERE document_type_name='框架采购合同' LIMIT 1;
  SELECT m.id,coalesce(b.unit_name,m.basic_unit),coalesce(p.unit_name,b.unit_name,m.basic_unit)
    INTO material,base_name,purchase_name FROM public.mdm_material m
    LEFT JOIN public.mdm_unit_of_measure b ON b.id=m.base_unit_id
    LEFT JOIN public.mdm_unit_of_measure p ON p.id=m.purchase_unit_id
    WHERE m.tenant_id=tenant AND (m.purchase_unit_id=m.base_unit_id OR m.purchase_unit_id IS NULL)
      AND m.auxiliary_unit_id IS NULL AND m.auxiliary_unit_2_id IS NULL LIMIT 1;
  SELECT id INTO supplier FROM public.mdm_supplier WHERE tenant_id=tenant LIMIT 1;
  IF material IS NULL OR supplier IS NULL THEN RAISE EXCEPTION 'Required test reference data unavailable'; END IF;
  lines:=jsonb_build_array(jsonb_build_object('line_id',line1,'line_no',10,'material_id',material,'material_description','QA物料','material_code','QA','unit',base_name,'base_unit',base_name,'quantity',10,'unit_price',5,'tax_rate',13,'discount_rate',0),jsonb_build_object('line_id',line2,'line_no',20,'material_id',material,'material_description','QA物料2','material_code','QA2','unit',base_name,'base_unit',base_name,'quantity',20,'unit_price',5,'tax_rate',13,'discount_rate',0));
  INSERT INTO public.scm_purchase_document(tenant_id,kind,document_no,project_id,document_date,lines) VALUES(tenant,'purchase_request','AUTO',NULL,current_date,lines) RETURNING id INTO req;
  INSERT INTO public.scm_purchase_document(tenant_id,kind,document_no,project_id,document_date,lines) VALUES(tenant,'purchase_request','AUTO',NULL,current_date,lines) RETURNING id INTO req2;
  selection:=jsonb_build_array(jsonb_build_object('document_id',req,'line_ids',jsonb_build_array(line2)));
  PERFORM public.scm_purchase_batch_secure('copy',selection);
  SELECT d.id INTO copied FROM public.scm_purchase_document d WHERE d.id NOT IN(req,req2) AND d.kind='purchase_request' AND d.tenant_id=tenant AND d.lines->0->>'material_code'='QA2' ORDER BY d.created_at DESC LIMIT 1;
  IF copied IS NULL OR (SELECT jsonb_array_length(d.lines)<>1 OR d.lines->0->>'line_id'=line2::text FROM public.scm_purchase_document d WHERE d.id=copied) THEN RAISE EXCEPTION 'Selected-line copy mismatch'; END IF;
  SELECT id INTO employee FROM public.hr_employee WHERE tenant_id=tenant LIMIT 1;
  IF employee IS NOT NULL THEN
    PERFORM public.scm_purchase_batch_secure('buyer',selection,employee);
    IF (SELECT details->>'buyer' FROM public.scm_purchase_document WHERE id=req)<>employee::text THEN RAISE EXCEPTION 'Buyer update mismatch'; END IF;
  END IF;
  INSERT INTO public.scm_purchase_document(tenant_id,kind,document_no,document_type_id,project_id,supplier_id,document_date,lines)
    VALUES(tenant,'purchase_contract','AUTO',type_id,NULL,supplier,current_date,jsonb_build_array(jsonb_set(lines->0,'{quantity}','null'))) RETURNING id INTO contract;
  IF (SELECT total_amount FROM public.scm_purchase_document WHERE id=contract)<>0 THEN RAISE EXCEPTION 'Null quantity amount mismatch'; END IF;
  SELECT id INTO type_id FROM public.mdm_document_type WHERE tenant_id=tenant AND document_type_name='价值合同' LIMIT 1;
  IF type_id IS NULL THEN RAISE EXCEPTION 'Value contract test type unavailable'; END IF;
  UPDATE public.scm_purchase_document SET document_type_id=type_id WHERE id=contract;
  IF (SELECT d.lines->0->>'quantity' FROM public.scm_purchase_document d WHERE d.id=contract) IS NOT NULL THEN RAISE EXCEPTION 'Value contract null quantity mismatch'; END IF;
  SELECT id INTO type_id FROM public.mdm_document_type WHERE tenant_id=tenant AND document_type_name='标准采购合同' LIMIT 1;
  BEGIN
    UPDATE public.scm_purchase_document SET document_type_id=type_id WHERE id=contract;
    RAISE EXCEPTION 'Standard contract accepted null quantity';
  EXCEPTION WHEN check_violation THEN NULL; END;
  INSERT INTO public.scm_purchase_document(tenant_id,kind,document_no,project_id,supplier_id,document_date,lines)
    VALUES(tenant,'purchase_order','AUTO',NULL,supplier,current_date,jsonb_build_array((lines->0)||jsonb_build_object('line_id',gen_random_uuid(),'quantity',1,'base_quantity',1,'unit',purchase_name,'tax_inclusive_unit_price',5.65,'discount_mode','none','source_purchase_document_id',req,'source_line_id',line1,'source_quantity',1))) RETURNING id INTO child;
  IF NOT EXISTS(SELECT 1 FROM public.scm_purchase_delete_dependencies_secure(jsonb_build_array(jsonb_build_object('document_id',req,'line_ids',jsonb_build_array(line1))))) THEN RAISE EXCEPTION 'JSON line reference missing'; END IF;
  -- An unreferenced sibling must remain independently deletable. Use the second draft.
  PERFORM public.scm_purchase_batch_secure('delete',jsonb_build_array(jsonb_build_object('document_id',req2,'line_ids',jsonb_build_array(line2))));
  IF (SELECT jsonb_array_length(d.lines) FROM public.scm_purchase_document d WHERE id=req2)<>1 THEN RAISE EXCEPTION 'Sibling line deletion mismatch'; END IF;
  PERFORM public.scm_purchase_batch_secure('submit',jsonb_build_array(jsonb_build_object('document_id',req2,'line_ids',NULL)));
  IF (SELECT status FROM public.scm_purchase_document WHERE id=req2)<>'submitted' THEN RAISE EXCEPTION 'Submit state mismatch'; END IF;
  BEGIN
    PERFORM public.scm_purchase_batch_secure('delete',jsonb_build_array(jsonb_build_object('document_id',copied,'line_ids',NULL),jsonb_build_object('document_id',req2,'line_ids',NULL)));
    RAISE EXCEPTION 'Invalid bulk deletion succeeded';
  EXCEPTION WHEN check_violation THEN NULL; END;
  IF NOT EXISTS(SELECT 1 FROM public.scm_purchase_document WHERE id=copied) THEN RAISE EXCEPTION 'Batch operation was not atomic'; END IF;
  PERFORM set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);
  BEGIN
    PERFORM public.scm_purchase_batch_secure('copy',selection);
    RAISE EXCEPTION 'Platform selected scope bypass';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('request.jwt.claims','{"sub":"5774aa51-3bbb-4da5-abd4-7ea44b44ea6a","role":"authenticated"}',true);
  IF app_private.current_read_tenant_id()<>tenant THEN RAISE EXCEPTION 'Forged ordinary header changed scope'; END IF;
  IF app_private.has_permission('ScmPurchaseRequest:Copy') THEN
    PERFORM public.scm_purchase_batch_secure('copy',jsonb_build_array(jsonb_build_object('document_id',req2,'line_ids',NULL)));
  ELSE
    BEGIN
      PERFORM public.scm_purchase_batch_secure('copy',jsonb_build_array(jsonb_build_object('document_id',req2,'line_ids',NULL)));
      RAISE EXCEPTION 'Ordinary user bypassed Copy permission';
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END IF;
END $test$;
ROLLBACK;
