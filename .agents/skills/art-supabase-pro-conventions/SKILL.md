---
name: art-supabase-pro-conventions
description: Apply the art-supabase-pro frontend architecture and coding conventions. Use for creating, refactoring, or reviewing Vue pages, CRUD modules, search forms, tables, dialogs, drawers, business components, write payloads, and API provider boundaries under src.
---

# Art Supabase Pro Conventions

Build features in the project's established Vue 3, TypeScript, Element Plus, and Art Design Pro style. Prefer project core components and typed imperative business APIs over page-local infrastructure.

## Start With Local Context

1. Read the target page, its `modules` directory, API types, and one recently migrated neighboring module.
2. Reuse aliases, naming, layout classes, hooks, and response handling already present in the repository.
3. Check the core component README and types before extending a wrapper:
   - `src/components/core/dialogs/art-dialog/README.md`
   - `src/components/core/drawers/art-drawer/README.md`
   - `src/hooks/core/useTable.ts`
4. Keep changes inside the feature boundary unless a shared abstraction is genuinely required.

## Choose Project Components First

Use these components before assembling equivalent Element Plus plumbing:

| Need                            | Preferred component                                          |
| ------------------------------- | ------------------------------------------------------------ |
| Query table composition         | `ArtTableQuery`                                              |
| Search/filter area              | `ArtSearchBar` or the feature's search component built on it |
| Table tools and column controls | `ArtTableHeader`                                             |
| Data table and pagination       | `ArtTable`                                                   |
| Table data lifecycle            | `useTable<TRecord>`                                          |
| Modal business workflow         | `ArtDialog`                                                  |
| Side-panel business workflow    | `ArtDrawer`                                                  |
| Metadata-driven form            | `ArtForm`                                                    |
| Uploads and common actions      | Existing `Art*` core form/action component                   |
| Business section title          | `ArtSectionTitle`                                            |

When a project wrapper already exists, use it before raw Element Plus primitives. For example, prefer `ArtExcelImport`, `ArtUploadImage`, `ArtButtonTable`, `ArtButtonMore`, and similar `src/components/core` wrappers over page-local `ElUpload`, ad hoc action buttons, or custom dropdown wiring. If the wrapper is close but missing a broadly reusable capability, extend the wrapper first and consume that extension from the business page.

Use raw `ElDialog` or `ElDrawer` only when the wrapper cannot support a documented platform requirement. Extend the core wrapper instead when the missing behavior is broadly reusable.

For remote option data in metadata forms, use `ArtForm` item-level API options instead of page-local `ref` state plus manual fetch/map code. Configure `api`, `resultField`, `labelField`, `valueField`, `labelFn`, `params`, `beforeFetch`, `afterFetch`, and `autoSelect` on the form item as needed. If a form control needs remote options but does not support the item-level `api` contract, extend `ArtForm` or the shared core control first, then consume it from business pages.

Business pages and business components must call backend data through exported functions from `src/api/**`, such as `@/api/vehicle-manage-system` or `@/api/common`. Do not import provider modules, `useSupabase`, `supabase.from(...)`, `request`, or other transport clients directly from `src/views/**`. Keep direct transport access inside API providers only. If a view needs a new backend read/write or option list, add or expose an API function first, then consume that function from the page or `ArtForm` item-level `api`.

For dictionary-backed options, do not create page-local API calls or `ArtForm` item APIs. Dictionary data is already loaded into `useUserStore()`; consume it through `storeToRefs(useUserStore()).getDictMap` for option lists. Values that are reusable, persisted, filtered, or displayed as an enumerable business meaning must be dictionaries instead of page-local arrays or maps. This includes yes/no, status, processed state, source, type, category-like enums, responsibility, mode, and tag/badge choices. Shared yes/no values must use the public `commonBoolean` dictionary. For boolean form fields, keep the form model boolean and map dictionary values with a small helper such as `value: item.value === 'true'`; for display, pass `String(value)` to `ArtDictDisplay`.

For table dictionary display, use the table column dictionary configuration, for example `dict: { code: 'status', display: 'auto' }`, so `ArtTable` renders through `ArtDictDisplay`. Use `display: 'auto'` when the dictionary item should decide between tag, badge, and plain text from `sys_dictionary.tag_type` / color; use `display: 'tag'`, `display: 'badge'`, or `display: 'text'` only for a deliberate UI requirement. In non-`ArtTable` dictionary display surfaces, render `ArtDictDisplay` directly. Do not call `userStore.getDictLabelByValue`, `getDictTagByValue`, or `getDictTagTypeByValue` from business views for display rendering, and do not hardcode repeated page-local tag type maps for dictionary values. Use `ArtForm` item-level `api` only for non-dictionary business data such as tenants, roles, suppliers, categories, and other remote business entities. When adding many dictionaries under a domain directory, group them with child directories such as archive, parts, and business records instead of leaving every type directly under the root domain directory.

For tree-shaped data operations, use the shared utilities in `src/utils/tree.ts` such as `TreeUtils.listToTree`, `treeToList`, and related helpers. Do not hand-write page-local list/tree conversion, node lookup, flattening, or descendant traversal logic. If the shared utility does not cover a needed tree operation, extend the utility first and then consume it from business pages.

For business section titles such as "基础信息", "车辆证件", or "车辆档案附件", use `ArtSectionTitle` to keep the visual language consistent. In `ArtForm`, use items with `type: 'divider'` and `span: 24`, because the divider is rendered through `ArtSectionTitle`. Do not create page-local `h3` headings and SCSS for section titles. Use the default right-side line for ordinary section breaks; pass `:show-line="false"` only for compact header rows where the line should be hidden, such as a title with a right-aligned action button.

## Build CRUD Pages

Use `ArtTableQuery` as the default composition for list pages that combine filters, table toolbar, table body, and pagination. Split into separate `ArtSearchBar` + `ArtTableHeader` + `ArtTable` only when the layout is genuinely non-standard and `ArtTableQuery` cannot express it cleanly.

```vue
<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :search-items="searchItems"
      :header-actions="headerActions"
    />

    <FeatureDialog ref="dialogRef" @success="tableQueryRef?.refreshData()" />
  </div>
</template>
```

Prefer `headerActions` for common toolbar actions instead of `#header-left`; only use the slot when the action cannot be expressed with `ArtTableQueryHeaderAction`. Search form action buttons should remain aligned to the right side of the card, including reset/search and expand/collapse controls.

Type table records at the hook boundary:

```ts
type RecordItem = Api.Module.RecordItem

const table = useTable<RecordItem>({
  core: {
    apiFn: fetchList,
    columnsFactory: (): ColumnOption<RecordItem>[] => []
  }
})
```

Do not repair template type errors with `as Record<string, any>[]`. Fix the generic source so `data`, columns, formatters, and selections share the same record type.

## Build Business Dialogs

The list page renders only the business dialog component and controls it through a typed Ref:

```vue
<FeatureDialog ref="featureDialogRef" @success="refreshData" />
```

```ts
interface FeatureDialogExpose {
  handleOpen: (data: FeatureDialogOpenData) => Promise<void>
}

const featureDialogRef = ref<FeatureDialogExpose>()
void featureDialogRef.value?.handleOpen({ type: 'edit', editData: row })
```

The business component owns `ArtDialog`, form state, initialization, submission, and reset:

```vue
<ArtDialog ref="dialogRef">
  <ArtForm
    ref="formRef"
    v-model="form"
    :items="formItems"
    :rules="rules"
    :show-reset="false"
    :show-submit="false"
  />
</ArtDialog>
```

```ts
const handleSubmit = async (): Promise<boolean> => {
  try {
    await formRef.value?.validate()
    await save(toRaw(form))
    emit('success')
    return true
  } catch {
    return false
  }
}

const handleOpen = async (data: FeatureDialogOpenData): Promise<void> => {
  await initializeForm(data)
  await dialogRef.value?.handleOpen(data, {
    title: getTitle(data),
    contentHeight: '70vh',
    onConfirm: handleSubmit,
    onReset: () => void resetForm()
  })
}

defineExpose({ handleOpen })
```

Follow these rules:

- Business dialogs that contain forms must use `ArtDialog + ArtForm`. Do not place a raw `ElForm` or page-local `ElFormItem` layout directly under `ArtDialog`.
- Express standard layout with `ArtForm` items, responsive `span`, `divider`, `hidden`, field slots, `render`, and shared core controls.
- If a required form layout or reusable control cannot be expressed by `ArtForm`, extend `src/components/core/forms/art-form` or the relevant shared core control first, document the capability beside that component, and then consume it from the business dialog. Do not bypass `ArtForm` with a business-page-only `ElForm` implementation.
- Do not expose `visible`, `modelValue`, `type`, or edit-data props to the list page.
- Do not make the parent compose `<ArtDialog><FeatureForm /></ArtDialog>`.
- Return `false` from `onConfirm` when validation or persistence fails.
- Let `ArtDialog` manage confirm loading, automatic close, and close-time reset.
- Initialize from a fresh default factory and clone mutable edit data.
- Use `contentMaxHeight` when dialog content should size naturally until a maximum height and then scroll. Use `contentHeight` only when a fixed content area is required. Do not nest page-local `ElScrollbar` for ordinary dialog content scrolling.
- Use the `#footer="{ loading, api }"` slot only for workflows requiring extra actions; route the primary action through `api.handleConfirm()`.
- Put one-off `ElDialog` props in `handleOpen(..., { dialogProps })`; keep reusable defaults on the component.

Apply the same ownership model to `ArtDrawer`.

## Type And State Rules

- Prefer `interface` for component contracts and `type` for aliases/unions.
- Type `defineEmits`, exposed Ref APIs, table rows, columns, and open payloads.
- Group related page variables by business responsibility instead of scattering top-level refs and computed values. Use typed `table`, `form`, or `dialog` groups containing their model, items, rules, columns, actions, and component props. Keep component refs and reusable utilities outside these groups.
- Use `reactive<GroupInterface>()` when the group contains ordinary reactive state. Use `Ref<GroupInterface>` only when the whole group or nested model is intentionally replaced.
- Do not create one large untyped page state object. Define an interface for each group and keep unrelated workflows in separate groups.
- Prefer `unknown` plus narrowing over introducing new `any`.
- Keep unavoidable `any` local and explain why, such as undocumented Element Plus internals.
- Prefer lodash helpers from `lodash-es` for null/undefined/empty checks and value normalization, such as `isNil`, `isEmpty`, `isString`, `toNumber`, and `cloneDeep`, instead of repeating manual `value === undefined || value === null` checks across business pages.
- Use `Object.assign(state, createInitialState())` for reactive resets, and include every mutable optional key such as `id` in the factory with an `undefined` default so stale edit state is overwritten.
- Use `shallowRef` for selected business records that are replaced rather than mutated.
- Do not mutate table rows to stage edit state.
- Prefix intentionally unawaited calls with `void`.
- Remove debug logging unless it is an explicit diagnostic action.

## Style Rules

- In Vue SFCs with `lang="scss"`, write styles with SCSS nesting under the feature/root class instead of repeating flat sibling selectors.
- Keep responsive overrides nested under the same root selector and place `:deep(...)` rules inside the relevant component block.
- Avoid adding scattered top-level selectors in scoped SCSS unless the selector genuinely targets an independent root.

## Async And Error Semantics

- Keep list loading in `useTable`.
- Keep dialog content loading separate from confirm loading when opening requires data.
- For vehicle management CRUD dialogs and similar edit dialogs, open `ArtDialog` immediately. Do not await detail or option-list APIs in the parent page or at the top of `handleOpen` before `dialogRef.handleOpen()`, because that delays the modal appearing. Pass `loading: true` when needed and run dialog-dependent API work inside the `onOpen` callback, using `api.setLoading(false)` in `finally`.
- `ArtDialog` uses `destroyOnClose`; do not call child-component methods such as `formRef.reloadOptions()` before `dialogRef.handleOpen()`, because the child ref may not exist.
- Load dialog-dependent remote form options through the `onOpen` callback passed to `handleOpen`. At that point the dialog content has mounted.
- When remote option parameters depend on the current form model, derive them in the form item's `beforeFetch` callback. Do not rely on a computed `params` object having refreshed in the same tick as form initialization.
- Keep `immediate: false` for options that require dialog data, then explicitly call `reloadOptions(fieldKey)` from `onOpen`.
- Run independent initialization requests with `Promise.all`.
- On validation failure, return `false` without closing.
- On API failure, rely on the project's API response layer for user messages unless the feature needs a specific message, then return `false`.
- Emit `success` or `submit` only after persistence succeeds.

## Own Write Payloads In The Business Layer

- Build and normalize create/update payloads in the owning page, business dialog, feature composable, or feature module before calling an API function.
- Keep business rules out of `src/api` providers. Do not put form defaults, conditional fields, empty-string-to-null conversion, date formatting, attachment shaping, validation-derived values, or feature-specific field removal in API request functions.
- Keep API providers transport-focused: choose the table or endpoint, extract path/query identifiers required by the request, convert key naming such as camelCase to snake_case, execute the request, and apply generic response handling.
- Treat identifier extraction for an update request as transport work; treat deciding whether an identifier or field belongs in the payload as business work.
- Remove audit/read-only fields such as `tenantId`, `createBy`, `createTime`, `updateBy`, and `updateTime` while constructing the business payload, not inside the API provider.
- Normalize optional database values according to the schema after validation. For nullable non-text values such as dates, numbers, and UUIDs, convert blank form values to `null` before the API call.
- If payload construction is reused by multiple screens in one feature, place it in that feature's `modules` or feature composable. Do not turn the API provider into a domain service.

## File Organization

- Page entry: `src/views/<domain>/<feature>/index.vue`
- Feature-only components: `src/views/<domain>/<feature>/modules`
- Reusable UI wrappers: `src/components/core`
- Shared composables: `src/hooks/core`
- Keep wrapper types and detailed usage docs beside the wrapper.

## Supabase Table Rules

When creating or changing Supabase tables for this project, first inspect the closest existing table and match its conventions. New business tables must include the standard audit columns and `tenant_id` unless the user explicitly says otherwise:

```sql
create_by text,
create_time timestamptz not null default now(),
update_by text,
update_time timestamptz not null default now(),
tenant_id uuid not null default app_private.current_user_tenant_id()
```

Do not use `uuid default auth.uid()` for `create_by` or `update_by` in this project. These fields are display strings and map to frontend `createBy` / `updateBy`. Do not ask business forms to pass `tenant_id` for ordinary inserts. Business tables should derive the tenant from the authenticated user with `app_private.current_user_tenant_id()` at the database default/policy layer. Use `app_private.default_register_tenant_id()` only for registration/default-user flows that intentionally land in the public registration tenant.

For project-provided setup SQL, assign system configuration rows in `sys_role`, `sys_menu`, `sys_dict_type`, and `sys_dictionary` to the platform administrator tenant (`tenant_code = 'platform'`). The protected built-in `R_REGISTER` role is the exception when it already belongs to the public registration tenant; do not move or recreate it under `platform`, but platform super administrators must be able to grant its menu permissions. Use `6249` for `create_by` / `update_by`. Business seed rows that belong to ordinary feature tables should use the public registration tenant (`tenant_code = 'public-register'`) with `create_by` / `update_by = '6249'`.

Bind the existing project audit triggers on every new business table:

```sql
create trigger <table>_create_audit
before insert on public.<table>
for each row
execute function public.trg_set_create_time_and_by('true', 'true');

create trigger <table>_update_audit
before update on public.<table>
for each row
execute function public.trg_set_update_time_and_by();
```

Also include the table's tenant isolation policies in the SQL itself: `tenant_select`, `tenant_insert`, `tenant_update`, and `tenant_delete` or the closest existing variant for the table's access model. Prefer `app_private.is_platform_super()` for platform-wide access, `app_private.current_user_tenant_id()` for tenant scoping, and `app_private.owns_record(create_by)` when creator ownership should be preserved. Do not ship a new business table without its RLS enabled and matching policies.

Frontend API insert/update helpers should omit `createBy`, `createTime`, `updateBy`, and `updateTime` before writing, unless the existing neighboring module intentionally supplies audit values.

## Relational Data And Joined Queries

- Normalize master and reference data. Store foreign keys such as `category_id`, `supplier_id`, `company_id`, or `user_id`; do not also add copied display columns such as `category_name`, `supplier_name`, or `company_name` merely for list display.
- Define real Postgres foreign-key constraints so Supabase/PostgREST can discover relationships.
- Read related display data with Supabase nested selects and aliases instead of making extra lookup requests:

```ts
supabase.from('vehicle_parts').select(`
  *,
  category:vehicle_parts_category(id, category_name),
  supplier:vehicle_supplier(id, supplier_name)
`)
```

- Model joined data as nested frontend objects such as `category?.categoryName` and `supplier?.supplierName`. Do not flatten joined names back into persisted columns.
- Keep create/update payloads limited to fields owned by the table, including foreign-key IDs. Do not query related tables inside `add*` or `edit*` merely to copy names into the payload.
- Prefer one joined list/detail query over a base query followed by per-row or per-write lookup requests.
- Add indexes for foreign-key columns used by joins and filters.
- Duplicate a related name only when the record is intentionally a historical snapshot, legal document, transaction line, audit record, or other immutable point-in-time fact that must preserve the original text after the source record is renamed. Name the snapshot field clearly, document the reason, and do not treat ordinary master-data screens as snapshots.

## Verify Before Finishing

Run focused checks first, then repository type checking:

```powershell
pnpm.cmd exec prettier --write <changed-files>
pnpm.cmd exec eslint <changed-files>
pnpm.cmd exec vue-tsc --noEmit --pretty false
```

Report pre-existing type errors separately from errors introduced by the change. For user-facing frontend changes, run the app and inspect the affected workflow when practical.
