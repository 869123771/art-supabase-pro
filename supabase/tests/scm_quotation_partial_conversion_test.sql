-- Authenticated regression; all fixture writes are rolled back.
BEGIN;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
select set_config('request.headers','{}',true);
set local role authenticated;
do $t$
declare q uuid; source public.scm_sales_document%rowtype; l text:='beb941de-126c-41c1-9426-b89a7cefe034'; r jsonb; again jsonb; request uuid:=gen_random_uuid(); s uuid;
begin
 if not app_private.is_platform_super() then raise exception 'test requires platform super'; end if;
 select * into source from public.scm_sales_document where id='18631a03-d234-40d6-a4c6-968f74380fda';
 insert into public.scm_sales_document(tenant_id,kind,document_no,document_type_id,project_id,customer_id,document_date,details,lines) values(source.tenant_id,'sales_quotation','QA-SCM-CONVERT',source.document_type_id,source.project_id,source.customer_id,current_date,source.details,source.lines) returning id into q;
 perform set_config('app.scm_quotation_approval',q::text,true); update public.scm_sales_document set status='effective' where id=q; perform set_config('app.scm_quotation_approval','',true);
 r:=public.scm_convert_quotation_lines(q,'sales_order',jsonb_build_array(jsonb_build_object('line_id',l,'quantity',1)),request,null);
 again:=public.scm_convert_quotation_lines(q,'sales_order',jsonb_build_array(jsonb_build_object('line_id',l,'quantity',1)),request,null);
 if again->>'id'<>r->>'id' or not(again->>'reused')::boolean then raise exception 'retry not idempotent'; end if;
 if (select document_type_id from public.scm_sales_document where id=(r->>'id')::uuid) is not null then raise exception 'draft type unexpectedly required'; end if;
 begin
  perform set_config('app.scm_sales_approval',r->>'id',true);
  update public.scm_sales_document set status='submitted' where id=(r->>'id')::uuid;
  raise exception 'missing type submitted';
 exception when check_violation then null; end;
 perform set_config('app.scm_sales_approval','',true);
 perform public.scm_convert_quotation_lines(q,'sales_order',jsonb_build_array(jsonb_build_object('line_id',l,'quantity',119)),gen_random_uuid(),null);
 begin perform public.scm_convert_quotation_lines(q,'sales_order',jsonb_build_array(jsonb_build_object('line_id',l,'quantity',0.001)),gen_random_uuid(),null); raise exception 'over-limit accepted'; exception when check_violation then null; end;
 select id into s from public.mdm_supplier where tenant_id='7529f951-938e-4e2c-ac0d-316c136ae1f9' limit 1;
 r:=public.scm_convert_quotation_lines(q,'purchase_order',jsonb_build_array(jsonb_build_object('line_id',l,'quantity',1)),gen_random_uuid(),s);
 if (select nullif(details->>'buyer','') from public.scm_purchase_document where id=(r->>'id')::uuid) is not null then raise exception 'buyer unexpectedly filled'; end if;
 begin update public.scm_purchase_document set lines=(select jsonb_agg(lineval||jsonb_build_object('quantity',2,'base_quantity',2)) from jsonb_array_elements(lines) lineval) where id=(r->>'id')::uuid; raise exception 'edited purchase exceeded reservation'; exception when check_violation then null; end;
 perform public.material_unit_compatibility_options('tmsCargoUnit');
end $t$;
reset role;
select 'conversion partial/idempotency/limit/optional type and buyer/MDM units passed' result;
ROLLBACK;

