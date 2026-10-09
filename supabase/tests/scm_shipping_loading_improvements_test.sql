BEGIN;
SELECT set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
SELECT set_config('request.headers','{}',true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE source public.scm_sales_document%rowtype; notice uuid; loading uuid; type_id uuid; l1 text:=gen_random_uuid()::text; l2 text:=gen_random_uuid()::text; lines jsonb; source_line jsonb; source_lines jsonb; own_tenant uuid;
BEGIN
 SELECT * INTO STRICT source FROM public.scm_sales_document WHERE kind='shipping_notice' AND project_id IS NOT NULL ORDER BY id LIMIT 1;
 source_line:=source.lines->0;
 source_line:=source_line-'source_line_id'-'source_document_id'-'source_document_no'-'stock_batch_id';
 lines:=jsonb_build_array(source_line||jsonb_build_object('line_id',l1,'quantity',100),source_line||jsonb_build_object('line_id',l2,'quantity',100));
 INSERT INTO public.scm_sales_document(tenant_id,kind,document_no,document_type_id,project_id,customer_id,document_date,details,lines)
 VALUES(source.tenant_id,'shipping_notice','QA-SHIPPING-DELETE',source.document_type_id,source.project_id,source.customer_id,current_date,source.details,lines) RETURNING id INTO notice;
 PERFORM public.scm_sales_delete_secure(jsonb_build_array(jsonb_build_object('document_id',notice,'line_ids',jsonb_build_array(l2))));
 IF (SELECT jsonb_array_length(d.lines) FROM public.scm_sales_document d WHERE d.id=notice)<>1 THEN RAISE EXCEPTION 'Shipping line deletion removed wrong rows'; END IF;
 UPDATE public.scm_sales_document SET status='submitted' WHERE id=notice;
 SELECT t.id INTO STRICT type_id FROM public.mdm_document_type t JOIN public.sys_menu m ON m.id=t.menu_id WHERE t.tenant_id=source.tenant_id AND t.enabled AND m.name='ScmLoading' ORDER BY t.id LIMIT 1;
 source_lines:=jsonb_build_array(source_line||jsonb_build_object('line_id',gen_random_uuid(),'source_line_id',l1,'source_document_id',notice,'quantity',30),source_line||jsonb_build_object('line_id',gen_random_uuid(),'source_line_id',l1,'source_document_id',notice,'quantity',20));
 INSERT INTO public.scm_sales_document(tenant_id,kind,document_no,document_type_id,project_id,customer_id,document_date,details,lines)
 VALUES(source.tenant_id,'loading','QA-LOADING-DELETE',type_id,source.project_id,source.customer_id,current_date,source.details,source_lines) RETURNING id INTO loading;
 IF NOT EXISTS(SELECT 1 FROM public.scm_sales_delete_dependencies_secure(jsonb_build_array(jsonb_build_object('document_id',notice,'line_ids',jsonb_build_array(l1)))) d WHERE d.record_id=loading::text) THEN RAISE EXCEPTION 'Loading reference not reported'; END IF;
 BEGIN PERFORM public.scm_sales_delete_secure(jsonb_build_array(jsonb_build_object('document_id',notice,'line_ids',jsonb_build_array(l1)))); RAISE EXCEPTION 'Referenced shipping line deleted'; EXCEPTION WHEN foreign_key_violation THEN NULL; END;
 PERFORM public.scm_sales_delete_secure(jsonb_build_array(jsonb_build_object('document_id',loading,'line_ids',jsonb_build_array(source_lines->0->>'line_id'))));
 IF (SELECT jsonb_array_length(d.lines) FROM public.scm_sales_document d WHERE d.id=loading)<>1 THEN RAISE EXCEPTION 'Loading line deletion mismatch'; END IF;
 BEGIN UPDATE public.scm_sales_document SET lines=jsonb_set(scm_sales_document.lines,'{0,quantity}','101') WHERE id=loading; RAISE EXCEPTION 'Overloading accepted'; EXCEPTION WHEN check_violation THEN NULL; END;
 UPDATE public.scm_sales_document SET status='loaded' WHERE id=loading;
 IF NOT EXISTS(SELECT 1 FROM public.scm_loading_line_progress_secure(array[loading]) p WHERE p.delivered_quantity=0) THEN RAISE EXCEPTION 'Submitted loading line not visible'; END IF;
 BEGIN PERFORM public.scm_sales_delete_secure(jsonb_build_array(jsonb_build_object('document_id',loading,'line_ids',null))); RAISE EXCEPTION 'Submitted loading deleted'; EXCEPTION WHEN check_violation THEN NULL; END;
 PERFORM set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);
 IF EXISTS(SELECT 1 FROM public.scm_loading_line_progress_secure(array[loading])) THEN RAISE EXCEPTION 'Selected tenant leaked loading'; END IF;
 BEGIN PERFORM public.scm_sales_delete_dependencies_secure(jsonb_build_array(jsonb_build_object('document_id',loading,'line_ids',null))); RAISE EXCEPTION 'Delete check crossed selected tenant'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claims','{"sub":"5774aa51-3bbb-4da5-abd4-7ea44b44ea6a","role":"authenticated"}',true);
 own_tenant:=app_private.current_user_tenant_id();
 IF app_private.current_read_tenant_id()<>own_tenant THEN RAISE EXCEPTION 'Forged tenant header accepted'; END IF;
 IF EXISTS(SELECT 1 FROM public.scm_loading_line_progress_secure(array[loading])) AND (own_tenant<>source.tenant_id OR NOT (app_private.has_permission('ScmLoading:View') OR app_private.has_permission('ScmLoadingOutbound:View'))) THEN RAISE EXCEPTION 'Loading progress permission bypass'; END IF;
END $test$;
ROLLBACK;
