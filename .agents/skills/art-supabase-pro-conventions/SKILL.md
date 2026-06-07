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
| Search/filter area              | `ArtSearchBar` or the feature's search component built on it |
| Table tools and column controls | `ArtTableHeader`                                             |
| Data table and pagination       | `ArtTable`                                                   |
| Table data lifecycle            | `useTable<TRecord>`                                          |
| Modal business workflow         | `ArtDialog`                                                  |
| Side-panel business workflow    | `ArtDrawer`                                                  |
| Metadata-driven form            | `ArtForm`                                                    |
| Uploads and common actions      | Existing `Art*` core form/action component                   |

Use raw `ElDialog` or `ElDrawer` only when the wrapper cannot support a documented platform requirement. Extend the core wrapper instead when the missing behavior is broadly reusable.

## Build CRUD Pages

Use the standard page composition:

```vue
<template>
  <FeatureSearch v-model="searchForm" @search="handleSearch" @reset="resetSearchParams" />

  <ElCard class="art-table-card" shadow="never">
    <ArtTableHeader v-model:columns="columnChecks" :loading="loading" @refresh="refreshData" />
    <ArtTable
      :data="data"
      :columns="columns"
      :loading="loading"
      :pagination="pagination"
      @pagination:size-change="handleSizeChange"
      @pagination:current-change="handleCurrentChange"
    />
  </ElCard>

  <FeatureDialog ref="dialogRef" @success="refreshData" />
</template>
```

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
  <ElForm ref="formRef" :model="form" :rules="rules">
    <!-- business fields -->
  </ElForm>
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
- Use `contentHeight` for long content instead of nesting another `ElScrollbar`.
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

## Verify Before Finishing

Run focused checks first, then repository type checking:

```powershell
pnpm.cmd exec prettier --write <changed-files>
pnpm.cmd exec eslint <changed-files>
pnpm.cmd exec vue-tsc --noEmit --pretty false
```

Report pre-existing type errors separately from errors introduced by the change. For user-facing frontend changes, run the app and inspect the affected workflow when practical.
