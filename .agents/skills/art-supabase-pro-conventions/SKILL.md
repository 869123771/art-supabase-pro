---
name: art-supabase-pro-conventions
description: Apply the art-supabase-pro frontend architecture and coding conventions. Use for creating, refactoring, or reviewing Vue pages, CRUD modules, search forms, tables, dialogs, drawers, and business components under src, especially when choosing between ArtSearchBar, ArtTableHeader, ArtTable, ArtDialog, ArtDrawer, ArtForm, and Element Plus primitives.
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

Use raw `ElDialog` or `ElDrawer` only when the wrapper cannot support a documented platform requirement. Extend the core wrapper instead when the missing behavior is broadly reusable.

For remote option data in metadata forms, use `ArtForm` item-level API options instead of page-local `ref` state plus manual fetch/map code. Configure `api`, `resultField`, `labelField`, `valueField`, `labelFn`, `params`, `beforeFetch`, `afterFetch`, and `autoSelect` on the form item as needed. If a form control needs remote options but does not support the item-level `api` contract, extend `ArtForm` or the shared core control first, then consume it from business pages.

For dictionary-backed options, do not create page-local API calls or `ArtForm` item APIs. Dictionary data is already loaded into `useUserStore()`; consume it through `storeToRefs(useUserStore()).getDictMap` for option lists and `userStore.getDictLabelByValue(dictCode, value)` for display text. For dictionary-backed `ElTag` displays, use `userStore.getDictTagByValue(dictCode, value)` or `getDictTagTypeByValue` and configure the preset Element Plus tag type on `sys_dictionary.tag_type`; do not hardcode repeated page-local tag type maps for dictionary values. Use `ArtForm` item-level `api` only for non-dictionary business data such as tenants, roles, suppliers, categories, and other remote business entities.

For tree-shaped data operations, use the shared utilities in `src/utils/tree.ts` such as `TreeUtils.listToTree`, `treeToList`, and related helpers. Do not hand-write page-local list/tree conversion, node lookup, flattening, or descendant traversal logic. If the shared utility does not cover a needed tree operation, extend the utility first and then consume it from business pages.

For metadata form section titles such as "基础信息" or "供应信息", use `ArtForm` items with `type: 'divider'` and `span: 24`. Do not create business-page slots and local SCSS just to render a section divider; if the shared divider style or behavior is insufficient, extend `ArtForm` first.

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
- Prefer `unknown` plus narrowing over introducing new `any`.
- Keep unavoidable `any` local and explain why, such as undocumented Element Plus internals.
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
- Run independent initialization requests with `Promise.all`.
- On validation failure, return `false` without closing.
- On API failure, rely on the project's API response layer for user messages unless the feature needs a specific message, then return `false`.
- Emit `success` or `submit` only after persistence succeeds.

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

## Verify Before Finishing

Run focused checks first, then repository type checking:

```powershell
pnpm.cmd exec prettier --write <changed-files>
pnpm.cmd exec eslint <changed-files>
pnpm.cmd exec vue-tsc --noEmit --pretty false
```

Report pre-existing type errors separately from errors introduced by the change. For user-facing frontend changes, run the app and inspect the affected workflow when practical.
