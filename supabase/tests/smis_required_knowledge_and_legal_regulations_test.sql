begin;

create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_catalog;

select plan(24);

select has_column('public', 'smis_document', 'document_kind', 'document kind column exists');
select has_column('public', 'smis_document', 'document_code', 'document code column exists');
select has_column(
  'public', 'smis_document', 'obtained_organization_id',
  'legal regulation acquiring organization column exists'
);
select has_column(
  'public', 'smis_document', 'is_special_equipment',
  'special-equipment dictionary column exists'
);
select has_table(
  'public', 'smis_legal_compliance_evaluation',
  'legal compliance evaluation ledger exists'
);
select col_type_is(
  'public', 'smis_legal_compliance_evaluation', 'evaluation_date', 'date',
  'compliance evaluation date uses a date type'
);
select col_not_null(
  'public', 'smis_legal_compliance_evaluation', 'evaluation_conclusion',
  'compliance evaluation conclusion is required'
);

select ok(
  (select relrowsecurity
   from pg_class
   where oid = 'public.smis_legal_compliance_evaluation'::regclass),
  'compliance evaluation ledger enforces RLS'
);
select ok(
  has_table_privilege('authenticated', 'public.smis_legal_compliance_evaluation', 'SELECT')
  and not has_table_privilege('authenticated', 'public.smis_legal_compliance_evaluation', 'INSERT')
  and not has_table_privilege('authenticated', 'public.smis_legal_compliance_evaluation', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.smis_legal_compliance_evaluation', 'DELETE'),
  'authenticated callers can read tenant-safe rows but cannot bypass RPC writes'
);
select ok(
  not has_table_privilege('anon', 'public.smis_legal_compliance_evaluation', 'SELECT'),
  'anonymous callers have no compliance ledger access'
);

select has_function(
  'public', 'smis_list_document_registers_secure',
  array[
    'integer', 'integer', 'text', 'text', 'uuid', 'text', 'boolean',
    'date', 'date', 'date', 'date', 'uuid[]', 'text'
  ],
  'document-register list RPC exists'
);
select has_function(
  'public', 'smis_save_document_register_secure',
  array['uuid', 'text', 'jsonb', 'uuid'],
  'document-register save and copy RPC exists'
);
select has_function(
  'public', 'smis_delete_document_registers_secure',
  array['text', 'uuid[]'],
  'document-register delete RPC exists'
);
select has_function(
  'public', 'smis_list_legal_compliance_evaluations_secure',
  array['uuid', 'integer', 'integer', 'text'],
  'compliance evaluation list RPC exists'
);
select has_function(
  'public', 'smis_save_legal_compliance_evaluation_secure',
  array['uuid', 'uuid', 'jsonb', 'uuid'],
  'compliance evaluation save and copy RPC exists'
);
select has_function(
  'public', 'smis_delete_legal_compliance_evaluations_secure',
  array['uuid', 'uuid[]'],
  'compliance evaluation delete RPC exists'
);

select ok(
  to_regclass('public.smis_document_kind_code_unique') is not null
  and to_regclass('public.smis_document_kind_category_idx') is not null,
  'document register uniqueness and category search indexes exist'
);
select ok(
  to_regclass('public.smis_legal_compliance_document_date_idx') is not null,
  'compliance document and date lookup index exists'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.smis_legal_compliance_evaluation'::regclass
      and confrelid = 'public.smis_document'::regclass
      and contype = 'f'
      and conname = 'smis_legal_compliance_evaluation_document_fkey'
  ),
  'compliance records reference the legal document ledger'
);

select results_eq(
  $$select path from public.sys_menu where name = 'SmisLegalRegulation'$$,
  array['legal-regulation']::text[],
  'legal regulation menu route is registered'
);
select results_eq(
  $$select component from public.sys_menu where name = 'SmisLegalRegulation'$$,
  array['/smis/safety-production/document-center/legal-regulation']::text[],
  'legal regulation menu component is registered'
);
select results_eq(
  $$select sort from public.sys_menu where name = 'SmisLegalRegulation'$$,
  array[4]::integer[],
  'legal regulation follows the safety management system menu'
);
select is(
  (select count(*)::integer
   from public.sys_menu
   where parent_id = (select id from public.sys_menu where name = 'SmisLegalRegulation')
     and type = 'button'),
  11,
  'legal regulation exposes all required operation permissions'
);
select ok(
  exists (
    select 1 from public.smis_document_category
    where category_name in ('应知应会', '安全管理制度', '法律法规')
    group by tenant_id
    having count(distinct category_name) = 3
  ),
  'document classification roots are seeded for active tenants'
);

select * from finish();
rollback;
