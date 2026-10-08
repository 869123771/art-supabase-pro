-- Authenticated regression; all fixture writes are rolled back.
BEGIN;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true); select set_config('request.headers','{}',true); set local role authenticated;
do $t$
declare source public.scm_sales_document%rowtype; q uuid; u uuid; fallback uuid; category uuid; material_type uuid; rule uuid; config jsonb; r jsonb; row_line jsonb; a uuid; b uuid; parent uuid; bom1 jsonb; bom2 jsonb; wtype uuid; before_count int;
begin
 select * into source from public.scm_sales_document where id='06d60a38-7a21-4225-9515-9e7ec0d09676';
 select id into u from public.mdm_unit_of_measure where tenant_id=source.tenant_id and unit_name='米' and status='enabled' limit 1;
 select id into fallback from public.mdm_unit_of_measure where tenant_id=source.tenant_id and unit_name='件' and status='enabled' limit 1;
 select id into category from public.mdm_material_category where tenant_id=source.tenant_id and status='enabled' order by sort limit 1;
 select id into material_type from public.mdm_material_type where tenant_id=source.tenant_id and status='enabled' order by sort limit 1;
 select id into rule from public.mdm_material_code_rule where tenant_id=source.tenant_id and status='enabled' order by sort limit 1;
 source.lines:=jsonb_build_array(source.lines->0||jsonb_build_object('base_unit','米','specification','QA-SCM-SPEC','brand','QA-SCM-BRAND'),source.lines->1||jsonb_build_object('base_unit','件'));
 insert into public.scm_sales_document(tenant_id,kind,document_type_id,project_id,customer_id,document_no,document_date,details,lines) values(source.tenant_id,'sales_quotation',source.document_type_id,source.project_id,source.customer_id,'QA-SCM-ROLLBACK',current_date,'{"quotation_scene":"project"}',source.lines) returning id into q;
 if (select details->>'quotation_scene' from public.scm_sales_document where id=q)<>'standard' then raise exception 'scene not standardized'; end if;
 config:=jsonb_build_object('category_id',category,'material_type_id',material_type,'base_unit_id',fallback,'code_rule_id',rule,'material_source','self_made','image_urls','[]'::jsonb);
 r:=public.scm_batch_quotation_action('materials',jsonb_build_array(jsonb_build_object('quotation_id',q,'line_ids',jsonb_build_array(source.lines->0->>'line_id'))),config);
 select lines->0 into row_line from public.scm_sales_document where id=q;
 a:=(row_line->>'material_id')::uuid;
 if row_line->>'sales_unit'<>'米' or not exists(select 1 from public.mdm_material where id=a and base_unit_id=u and purchase_unit_id=u and sales_unit_id=u and inventory_unit_id=u and production_unit_id=u and cost_unit_id=u and specification_model='QA-SCM-SPEC' and brand='QA-SCM-BRAND') then raise exception 'source units/spec/brand/defaults not inherited'; end if;
 if nullif((select lines->1->>'material_id' from public.scm_sales_document where id=q),'') is not null then raise exception 'unselected line changed'; end if;
 perform public.scm_batch_quotation_action('materials',jsonb_build_array(jsonb_build_object('quotation_id',q,'line_ids',jsonb_build_array(source.lines->1->>'line_id'))),config);
 perform set_config('app.scm_quotation_approval',q::text,true);
 update public.scm_sales_document set status='effective' where id=q;
 perform set_config('app.scm_quotation_approval','',true);
 select id into parent from public.mdm_material where tenant_id=source.tenant_id and base_unit_id is not null and status='enabled' and id<>a limit 1;
 bom1:=public.scm_convert_quotation_to_bom(q,parent,array[source.lines->0->>'line_id']);
 bom2:=public.scm_convert_quotation_to_bom(q,parent,array[source.lines->1->>'line_id']);
 if bom1->>'id'=bom2->>'id' then raise exception 'partial BOM batches collapsed'; end if;
 if (public.scm_convert_quotation_to_bom(q,parent,array[source.lines->0->>'line_id'])->>'id')<>bom1->>'id' then raise exception 'BOM retry duplicated'; end if;
end $t$; reset role; select 'source metadata/unit defaults/subset material generation/partial BOM passed' result;
ROLLBACK;

