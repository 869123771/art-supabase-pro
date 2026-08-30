<template>
  <ArtTableSingleSelect
    :model-value="modelValue"
    :selected-data="selectedData"
    :api-fn="fetchEmployees"
    :columns="columns"
    :placeholder="placeholder"
    :disabled="disabled"
    :clearable="clearable"
    row-key="id"
    :label-key="getEmployeeLabel"
    :description-key="getEmployeeDescription"
    :title="title"
    :subtitle="subtitle"
    :search-placeholder="searchPlaceholder"
    empty-text="暂无可选员工"
    empty-description="当前租户没有可选的在职或试用期员工，请先完善员工花名册。"
    :show-pagination="true"
    :page-size="10"
    :page-sizes="[10, 20, 30, 50]"
    @update:model-value="emit('update:modelValue', normalizeValue($event))"
    @update:selected-data="handleSelectedDataChange"
    @change="handleChange"
    @confirm="handleConfirm"
    @clear="emit('clear')"
  >
    <template #empty>
      <ArtDataSourceEmptyActions resource-name="员工花名册" :actions="employeeMaintenanceActions" />
    </template>
  </ArtTableSingleSelect>
</template>

<script setup lang="ts">
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import ArtDataSourceEmptyActions, {
    type ArtDataSourceEmptyAction
  } from '@/components/business/art-data-source-empty-actions/index.vue'
  import type {
    DataSelectColumn,
    DataSelectFetchParams,
    DataSelectKey,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchEmployeeSelectorList,
    type EmployeeIntegrationItem
  } from '@/api/integration/employees'

  defineOptions({ name: 'ArtEmployeeSelect' })

  interface Props {
    modelValue?: string
    selectedData?: EmployeeIntegrationItem[]
    tenantId?: string
    title?: string
    subtitle?: string
    placeholder?: string
    searchPlaceholder?: string
    disabled?: boolean
    clearable?: boolean
    apiFn?: typeof fetchEmployeeSelectorList
  }

  const props = withDefaults(defineProps<Props>(), {
    modelValue: undefined,
    selectedData: () => [],
    tenantId: '',
    title: '选择员工',
    subtitle: '按姓名、工号、组织或岗位检索员工档案',
    placeholder: '请选择员工',
    searchPlaceholder: '搜索姓名、工号、组织或岗位',
    disabled: false,
    clearable: true
  })

  const emit = defineEmits<{
    'update:modelValue': [value: string | undefined]
    'update:selectedData': [rows: EmployeeIntegrationItem[]]
    change: [value: string | undefined, rows: EmployeeIntegrationItem[]]
    confirm: [value: string | undefined, rows: EmployeeIntegrationItem[]]
    clear: []
  }>()

  const userStore = useUserStore()
  const { getUserInfo } = storeToRefs(userStore)
  const resolvedTenantId = computed(() => props.tenantId || getUserInfo.value.tenantId || '')
  const employeeMaintenanceActions = [
    {
      label: '去维护员工花名册',
      routeName: 'HrEmployeeRoster',
      permission: 'Hr:Employee:View',
      icon: 'ri:contacts-book-3-line'
    }
  ] as const satisfies readonly ArtDataSourceEmptyAction[]

  const getEmployee = (row: DataSelectRecord): EmployeeIntegrationItem =>
    row as EmployeeIntegrationItem

  const getEmployeeLabel = (row: DataSelectRecord): string => {
    const employee = getEmployee(row)
    const employeeName = employee.employeeName || '未命名员工'
    return employee.employeeNo ? `${employeeName} · ${employee.employeeNo}` : employeeName
  }

  const getEmployeeDescription = (row: DataSelectRecord): string => {
    const employee = getEmployee(row)
    return [employee.organization?.organizationName, employee.jobTitle, employee.phone]
      .filter(Boolean)
      .join(' · ')
  }

  const columns: DataSelectColumn[] = [
    { prop: 'employeeName', label: '员工姓名', minWidth: 130 },
    { prop: 'employeeNo', label: '员工工号', minWidth: 130 },
    {
      prop: 'organization',
      label: '所属组织',
      minWidth: 160,
      formatter: (row) => getEmployee(row).organization?.organizationName || '未分配组织'
    },
    {
      prop: 'jobTitle',
      label: '工作岗位',
      minWidth: 140,
      formatter: (row) => getEmployee(row).jobTitle || '未分配岗位'
    },
    { prop: 'phone', label: '手机号码', width: 140 },
    {
      prop: 'employmentStatus',
      label: '任职状态',
      width: 110,
      dict: { code: 'hrEmploymentStatus', display: 'auto' }
    }
  ]

  const normalizeValue = (
    value: DataSelectKey | DataSelectKey[] | undefined
  ): string | undefined => {
    const selectedValue = Array.isArray(value) ? value[0] : value
    return selectedValue == null ? undefined : String(selectedValue)
  }

  const normalizeRows = (rows: DataSelectRecord[]): EmployeeIntegrationItem[] =>
    rows.map(getEmployee)

  const fetchEmployees = async (params: DataSelectFetchParams) => {
    const from = Math.max((params.page - 1) * params.pageSize, 0)
    const result = await (props.apiFn ?? fetchEmployeeSelectorList)({
      tenantId: resolvedTenantId.value,
      keyword: params.keyword,
      from,
      to: from + params.pageSize - 1
    })
    return { data: result.data, total: result.total }
  }

  const handleSelectedDataChange = (rows: DataSelectRecord[]): void =>
    emit('update:selectedData', normalizeRows(rows))

  const handleChange = (
    value: DataSelectKey | DataSelectKey[] | undefined,
    rows: DataSelectRecord[]
  ): void => emit('change', normalizeValue(value), normalizeRows(rows))

  const handleConfirm = (
    value: DataSelectKey | DataSelectKey[] | undefined,
    rows: DataSelectRecord[]
  ): void => emit('confirm', normalizeValue(value), normalizeRows(rows))
</script>
