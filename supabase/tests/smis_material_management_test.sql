begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(25);

select has_table('public', 'smis_material_category', 'material category table exists');
select has_table('public', 'smis_material', 'material master table exists');
select ok((select relrowsecurity from pg_class where oid = 'public.smis_material_category'::regclass), 'material categories enforce RLS');
select ok((select relrowsecurity from pg_class where oid = 'public.smis_material'::regclass), 'materials enforce RLS');
select is((select count(*)::integer from pg_policy where polrelid = 'public.smis_material_category'::regclass), 4, 'material category has four tenant policies');
select is((select count(*)::integer from pg_policy where polrelid = 'public.smis_material'::regclass), 4, 'material has four tenant policies');
select ok(exists(select 1 from pg_trigger where not tgisinternal and tgname = 'smis_material_category_create_audit'), 'material category create audit trigger exists');
select ok(exists(select 1 from pg_trigger where not tgisinternal and tgname = 'smis_material_update_audit'), 'material update audit trigger exists');

select has_function('public', 'smis_list_material_categories_secure', array['integer', 'integer', 'text', 'text', 'uuid'], 'material category list RPC exists');
select has_function('public', 'smis_save_material_category_secure', array['uuid', 'jsonb'], 'material category save RPC exists');
select has_function('public', 'smis_delete_material_categories_secure', array['uuid[]'], 'material category delete RPC exists');
select has_function('public', 'smis_list_materials_secure', array['integer', 'integer', 'text', 'text', 'text', 'text', 'uuid', 'text', 'text', 'text', 'uuid[]', 'text'], 'material list RPC exists');
select has_function('public', 'smis_save_material_secure', array['uuid', 'jsonb'], 'material save RPC exists');
select has_function('public', 'smis_delete_materials_secure', array['uuid[]'], 'material delete RPC exists');

select ok(not has_function_privilege('anon', 'public.smis_list_materials_secure(integer,integer,text,text,text,text,uuid,text,text,text,uuid[],text)', 'execute'), 'anonymous role cannot list materials');
select ok(has_function_privilege('authenticated', 'public.smis_list_materials_secure(integer,integer,text,text,text,text,uuid,text,text,text,uuid[],text)', 'execute'), 'authenticated role can list materials through RPC');
select ok(not has_function_privilege('anon', 'public.smis_save_material_secure(uuid,jsonb)', 'execute'), 'anonymous role cannot save materials');
select ok(has_function_privilege('authenticated', 'public.smis_save_material_secure(uuid,jsonb)', 'execute'), 'authenticated role can save materials through RPC');

select is((select count(*)::integer from sys_dictionary d join sys_dict_type t on t.id = d.type_id where t.code = 'smisMaterialEnableStatus' and d.status = '1'), 2, 'material status dictionary is complete');
select is((select count(*)::integer from sys_dictionary d join sys_dict_type t on t.id = d.type_id where t.code = 'smisMaterialType' and d.status = '1'), 3, 'material type dictionary is complete');
select is((select count(*)::integer from sys_dictionary d join sys_dict_type t on t.id = d.type_id where t.code = 'smisMaterialSource' and d.status = '1'), 2, 'material source dictionary is complete');
select is((select count(*)::integer from sys_dictionary d join sys_dict_type t on t.id = d.type_id where t.code = 'smisMaterialUnit' and d.status = '1'), 10, 'material unit dictionary is complete');

select is((select count(*)::integer from sys_menu where type = 'button' and name like 'SmisMaterialCategory:%'), 4, 'material category exposes four button permissions');
select is((select count(*)::integer from sys_menu where type = 'button' and name like 'SmisMaterialInformation:%'), 5, 'material information exposes five button permissions');
select is((select count(*)::integer from pg_constraint where conrelid = 'public.smis_material'::regclass and contype = 'f' and confrelid = 'public.smis_material_category'::regclass), 1, 'material keeps a normalized category foreign key');

select * from finish();
rollback;
