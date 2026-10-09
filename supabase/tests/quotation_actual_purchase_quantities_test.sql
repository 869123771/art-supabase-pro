-- Transactional regression against the quotation reported in this issue.
BEGIN;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
select set_config('request.headers','{}',true);
set local role authenticated;
DO $test$
declare result jsonb; created jsonb; repeated jsonb; v_lines jsonb; request uuid:=gen_random_uuid(); supplier uuid;
begin
 result:=public.scm_quotation_conversion_quantities('18631a03-d234-40d6-a4c6-968f74380fda');
 if not exists(select 1 from jsonb_array_elements(result) x where x->>'target_kind'='purchase_order' and x->>'line_id'='68d8395b-1610-4459-a5c1-cb43dc1880b8' and (x->>'quantity')::numeric=10)
 or not exists(select 1 from jsonb_array_elements(result) x where x->>'target_kind'='purchase_order' and x->>'line_id'='fe063b45-631c-42c3-9479-55d60a91480b' and (x->>'quantity')::numeric=20) then raise exception 'actual quantities mismatch'; end if;
 select supplier_id into supplier from public.scm_purchase_document where id='9e5ef0fb-abbe-4824-82de-54912ff9dbb7';
 created:=public.scm_convert_quotation_lines('18631a03-d234-40d6-a4c6-968f74380fda','purchase_order','[{"line_id":"68d8395b-1610-4459-a5c1-cb43dc1880b8","quantity":110},{"line_id":"fe063b45-631c-42c3-9479-55d60a91480b","quantity":100}]',request,supplier);
 select d.lines into v_lines from public.scm_purchase_document d where id=(created->>'id')::uuid;
 if (v_lines->0->>'line_no')::int<>10 or (v_lines->1->>'line_no')::int<>20 or (v_lines->0->>'source_line_no')::int<>20 or (v_lines->1->>'source_line_no')::int<>30 then raise exception 'source or target line numbers mismatch'; end if;
 repeated:=public.scm_convert_quotation_lines('18631a03-d234-40d6-a4c6-968f74380fda','purchase_order','[{"line_id":"68d8395b-1610-4459-a5c1-cb43dc1880b8","quantity":110},{"line_id":"fe063b45-631c-42c3-9479-55d60a91480b","quantity":100}]',request,supplier);
 if created->>'id'<>repeated->>'id' or not (repeated->>'reused')::boolean then raise exception 'idempotency mismatch'; end if;
 begin
 perform public.scm_convert_quotation_lines('18631a03-d234-40d6-a4c6-968f74380fda','purchase_order','[{"line_id":"68d8395b-1610-4459-a5c1-cb43dc1880b8","quantity":1}]',gen_random_uuid(),supplier);
 raise exception 'over-allocation accepted';
 exception when check_violation then null;
 end;
 -- Reducing a draft releases the remaining allowance; growing it after another
 -- batch consumes that allowance must still be rejected by the order guard.
 v_lines:=jsonb_set(jsonb_set(v_lines,'{0,quantity}','100'),'{0,base_quantity}','100');
 update public.scm_purchase_document set lines=v_lines where id=(created->>'id')::uuid;
 perform public.scm_convert_quotation_lines('18631a03-d234-40d6-a4c6-968f74380fda','purchase_order','[{"line_id":"68d8395b-1610-4459-a5c1-cb43dc1880b8","quantity":10}]',gen_random_uuid(),supplier);
 begin
 update public.scm_purchase_document set lines=jsonb_set(jsonb_set(v_lines,'{0,quantity}','101'),'{0,base_quantity}','101') where id=(created->>'id')::uuid;
 raise exception 'growing an earlier order exceeded the source quota';
 exception when check_violation then null;
 end;
end $test$;
select set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);
DO $test$ begin
 begin perform public.scm_quotation_conversion_quantities('18631a03-d234-40d6-a4c6-968f74380fda'); raise exception 'selected tenant leak'; exception when insufficient_privilege then null; end;
 if exists(select 1 from public.wms_sales_document_list where tenant_id<>'6675a0d6-3ff6-4ab7-bb09-232d85ae96ad') or exists(select 1 from public.wms_purchase_document_list where tenant_id<>'6675a0d6-3ff6-4ab7-bb09-232d85ae96ad') then raise exception 'list selected tenant leak'; end if;
end $test$;
select set_config('request.jwt.claims','{"sub":"5774aa51-3bbb-4da5-abd4-7ea44b44ea6a","role":"authenticated"}',true);
DO $test$ begin
 if exists(select 1 from public.wms_sales_document_list where tenant_id<>'7529f951-938e-4e2c-ac0d-316c136ae1f9') or exists(select 1 from public.wms_purchase_document_list where tenant_id<>'7529f951-938e-4e2c-ac0d-316c136ae1f9') then raise exception 'ordinary forged scope leak'; end if;
end $test$;
ROLLBACK;
