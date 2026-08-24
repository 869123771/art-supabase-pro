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
