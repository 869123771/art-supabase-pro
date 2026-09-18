# ArtMaterialSelect

`ArtMaterialSelect` is the shared material-record selector for MDM, MES, and other business modules. It standardizes the material-category navigator, searchable material table, selected-record summary, pagination, and the canonical material columns used by production workflows.

```vue
<ArtMaterialSelect
  v-model="form.materialId"
  :selected-data="selectedMaterials"
  :api-fn="fetchMaterials"
  :categories="materialCategories"
  subtitle="选择后自动带入生产单位"
/>
```

The supplied `apiFn` receives `DataSelectFetchParams`. Read the selected category from `params.filters.categoryId`, keep tenant and permission enforcement in the API/database boundary, and return `{ data, total }`. Records must expose the canonical material selector fields (`materialCode`, `materialName`, `specificationModel`, `drawingNo`, category and material-type references).

Use `multiple` with `v-model:model-values` for batch selection. Single-selection workflows show the selected summary by default so the category, result, and confirmation regions remain consistent; pass `:show-selected-panel="false"` only when the available width cannot support it.
