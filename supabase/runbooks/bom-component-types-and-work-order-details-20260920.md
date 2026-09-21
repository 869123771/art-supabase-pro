# BOM component types and work-order details — 2026-09-20

Project: `ckbftoopuyophiebamwy`.

## Recovery point

Before applying database changes, a JSON backup was created in
`app_private.codex_backup_20260920_bom_workorder`. It contains the original
`mdm_bom_item` (26 rows), `mdm_document_type` (10 rows), `mes_work_order`
(3 rows), `mdm_master_group` (27 rows), engineering menu and role-menu rows,
and the prior BOM-save and document-type-copy function definitions. Keep this
table until the feature is accepted. Restore individual records or function
definitions from its named snapshots if a rollback is needed; do not drop
the new columns while business records reference them.

## Applied changes

- Added `component-type` to the master-group domain, created tenant-scoped
  `mdm_component_type`, and added `mdm_bom_item.component_type_id`.
- Added BOM component-type menu and button permissions above BOM maintenance.
  Existing BOM role grants were mapped to the new menu and actions.
- Added guarded industry-group save/delete functions and extended the BOM
  assignment save function to persist component types.
- Added document-type `extension_fields` with validation and copy support.
  Production orders store `extension_values` and an extension schema snapshot.
  Extension keys use lower camel case so JSON keys survive the client's
  snake/camel conversion. A copy RPC overload accepts the edited field list.
- Added tenant-scoped `mes_work_order_detail` with database-side calculations
  for linear metres and area, plus an atomic guarded save function for the
  order and its detail rows.
- Work-order BOM snapshots retain each source item's component type; the MES
  snapshot viewer and editor now show that type, including historical disabled
  values. Disabled types cannot be selected for a new assignment.
- Added covering indexes for the component-type group and work-order detail
  foreign keys after reviewing the database performance advisor.
- Seeded four industry groups and 24 example component types in the public
  registration and existing manufacturing tenants. Configured the existing
  `PP20` plate-processing document type with 10 fields and BOM sources for
  core, outer and inner panels.

## Verification

Each schema/data batch was validated in a transaction and rolled back before
being committed. A signed-in manufacturing-tenant role was simulated inside a
rollback transaction to create an order with one 2440 × 1220 mm detail row;
the database returned 2.44 linear metres and 2.9768 square metres. The same
role resolves the new menu permission, and the registration tenant sees its
own 24 component types through RLS.
