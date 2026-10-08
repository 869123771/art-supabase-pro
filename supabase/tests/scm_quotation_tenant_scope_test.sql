-- Authenticated regression; all fixture writes are rolled back.
BEGIN;
select set_config('request.jwt.claims','{"sub":"0a872664-874c-447d-a256-d0dbdca6ed45","role":"authenticated"}',true);
select set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true); set local role authenticated;
do $t$ begin
 begin perform public.scm_quotation_conversion_quantities('18631a03-d234-40d6-a4c6-968f74380fda'); raise exception 'selected tenant leaked'; exception when insufficient_privilege then null; end;
 if exists(select 1 from jsonb_array_elements(public.material_unit_compatibility_options()) x where x->>'tenant_id'<>'6675a0d6-3ff6-4ab7-bb09-232d85ae96ad') then raise exception 'unit tenant leak'; end if;
end $t$;
select set_config('request.jwt.claims','{"sub":"5774aa51-3bbb-4da5-abd4-7ea44b44ea6a","role":"authenticated"}',true);
select set_config('request.headers','{"x-art-tenant-scope":"6675a0d6-3ff6-4ab7-bb09-232d85ae96ad"}',true);
do $t$ begin
 if exists(select 1 from jsonb_array_elements(public.material_unit_compatibility_options()) x where x->>'tenant_id'<>'7529f951-938e-4e2c-ac0d-316c136ae1f9') then raise exception 'forged tenant accepted'; end if;
 begin perform public.scm_quotation_conversion_quantities('d41d573f-28d4-4786-b3ca-59740d85f15c'); raise exception 'unknown quotation accepted'; exception when insufficient_privilege then null; end;
end $t$;
reset role; select 'tenant scope and forged-header isolation passed' result;
ROLLBACK;

