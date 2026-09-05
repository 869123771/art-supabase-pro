# ArtEmployeeSelect

`ArtEmployeeSelect` is the platform employee/person selector. It owns tenant-scoped secure search, pagination, employee identity labels, and the shared selection-dialog layout.

```vue
<ArtEmployeeSelect
  v-model="form.employeeId"
  v-model:selected-data="selectedEmployees"
  :tenant-id="form.tenantId"
/>
```

When editing an existing record, pass its employee reference through `selectedData` so the control can display `员工姓名 · 工号` before the dialog is opened. Persist only the employee ID. Use `ArtUserSelect` instead when the field refers to a login account or approval account.

For multiple people, use `multiple` with `v-model:model-values="personIds"`. The `confirmMultiple` event returns `(ids, rows)`; the existing single-value contract is unchanged. A feature may supply `apiFn` with the employee selector API shape to select its own tenant-scoped personnel records, preserving their IDs and recognizable name, employee number and phone fields.

## Source-specific display fields

`display-fields` declares which optional columns the source provides: `organization`, `jobTitle`, `phone`, `employmentStatus`. Name and employee number are always retained. By default all four optional fields remain available for existing employee workflows.

For minimal production references, use `:display-fields="['jobTitle', 'employmentStatus']"`. The same field selection controls secondary text in the selected summary, so hidden phone/organization values are not repeated there. This only controls presentation; the server must independently restrict private fields.

An omitted organization/job-title field means “未提供…信息”; an explicitly empty/null field means “未分配…”. Do not infer missing business assignments from a source that never supplies those fields.
