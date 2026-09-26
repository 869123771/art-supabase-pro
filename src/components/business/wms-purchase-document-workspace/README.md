# WMS purchase document workspace

Shared purchase inventory document UI for the two opening purchase routes in WMS and the two regular purchase routes in SCM.

- `kind` selects the business name, permission prefix, default document type, date rule, return quantity treatment, and push targets.
- The workspace owns search, ArtTable rendering, row operations, import/export entry points, and the shared drawer.
- All reads and writes go through `src/api/wms-purchase.ts`; the component never accesses the transport client directly.
- Loading, empty, validation, permission, error, and success states use the existing Art and Element Plus feedback components.
