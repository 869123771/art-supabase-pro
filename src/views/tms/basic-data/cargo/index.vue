<template>
  <div class="business-workspace-page art-full-height">
    <BusinessWorkspaceHeader
      eyebrow="CARGO CATALOG"
      title="货物资料"
      description="沉淀货物名称、计量单位、体积重量与启用状态，提升开单录入和计价准确性。"
      icon="ri:archive-stack-line"
      :tags="[
        { label: '货品标准化', type: 'primary' },
        { label: '计量一致性', type: 'success' }
      ]"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="tableQueryRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      header-actions-placement="workspace"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        emptyText: '暂无货物资料',
        emptyDescription: '可新增常用货物，或调整计量单位、状态、时间和关键字后重新查询。'
      }"
      focusable
    />

    <CargoDialog ref="dialogRef" @success="handleSaveSuccess" />
    <MasterDataDeleteGuard ref="deleteGuardRef" @cleared="handleDeleteGuardCleared" />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteCargo,
    deleteCargoBatch,
    exportCargoList,
    fetchCargoList,
    importCargoes
  } from '@/api/tms'
  import CargoDialog from './modules/cargo-dialog.vue'
  import MasterDataDeleteGuard, {
    type MasterDataDeleteGuardOpenOptions
  } from '@/components/business/master-data-delete-guard/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'

  defineOptions({ name: 'TmsCargo' })

  const { confirmAction } = useArtFeedback()

  type Cargo = Api.Tms.BasicData.Cargo
  type SearchParams = Api.Tms.BasicData.CargoSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface CargoDialogExpose {
    handleOpen: (row?: Cargo) => Promise<void>
  }

  interface MasterDataDeleteGuardExpose {
    inspect: (options: MasterDataDeleteGuardOpenOptions) => Promise<boolean>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const route = useRoute()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<CargoDialogExpose>()
  const deleteGuardRef = ref<MasterDataDeleteGuardExpose>()

  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: {
      unit: '',
      enabled: undefined,
      createTimeRange: [],
      recordId: typeof route.query.recordId === 'string' ? route.query.recordId : '',
      keyword: ''
    }
  })

  const cargoUnitOptions = computed(() => getDictMap.value.tmsCargoUnit ?? [])
  const commonBooleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const cargoExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'cargoName', title: '货物名称', required: true },
    { key: 'unit', title: '计量单位', required: true },
    { key: 'lengthM', title: '长(m)' },
    { key: 'widthM', title: '宽(m)' },
    { key: 'heightM', title: '高(m)' },
    { key: 'volumeM3', title: '体积(m³)' },
    { key: 'weightKg', title: '重量(kg)' },
    { key: 'valueAmount', title: '价值(元)' },
    { key: 'enabled', title: '状态' },
    { key: 'remark', title: '备注' }
  ]

  const unitLabelToValue = computed(() => {
    const map = new Map<string, string>()
    cargoUnitOptions.value.forEach((item) => {
      if (item.label && item.value) map.set(item.label, item.value)
    })
    return map
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '计量单位',
      key: 'unit',
      type: 'select',
      props: { options: cargoUnitOptions.value, clearable: true }
    },
    {
      label: '状态',
      key: 'enabled',
      type: 'select',
      props: { options: commonBooleanOptions.value, clearable: true }
    },
    {
      label: '创建日期',
      key: 'createTimeRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        rangeSeparator: '至'
      }
    },
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '货物名称、编号、单位或备注'
      }
    }
  ])

  const columnsFactory = (): ColumnOption<Cargo>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    {
      prop: 'cargoName',
      label: '货物名称',
      minWidth: 180,
      showOverflowTooltip: true
    },
    {
      prop: 'unit',
      label: '单位',
      width: 90,
      dict: { code: 'tmsCargoUnit', display: 'text' }
    },
    {
      prop: 'lengthM',
      label: '长(m)',
      width: 95,
      align: 'right',
      formatter: (row) => formatNumber(row.lengthM, 2)
    },
    {
      prop: 'widthM',
      label: '宽(m)',
      width: 95,
      align: 'right',
      formatter: (row) => formatNumber(row.widthM, 2)
    },
    {
      prop: 'heightM',
      label: '高(m)',
      width: 95,
      align: 'right',
      formatter: (row) => formatNumber(row.heightM, 2)
    },
    {
      prop: 'volumeM3',
      label: '体积(m³)',
      width: 110,
      align: 'right',
      formatter: (row) => formatNumber(row.volumeM3, 3)
    },
    {
      prop: 'weightKg',
      label: '重量(kg)',
      width: 110,
      align: 'right',
      formatter: (row) => formatNumber(row.weightKg, 2)
    },
    {
      prop: 'valueAmount',
      label: '价值(元)',
      width: 120,
      align: 'right',
      formatter: (row) => formatNumber(row.valueAmount, 2)
    },
    {
      prop: 'enabled',
      label: '状态',
      width: 90,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.enabled) }
    },
    {
      prop: 'createTime',
      label: '创建时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.createTime, 'YYYY-MM-DD HH:mm')
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable type="edit" permission="TmsCargo:Edit" onClick={() => openDialog(row)} />
          <ArtButtonTable
            type="delete"
            permission="TmsCargo:Delete"
            onClick={() => handleDelete(row)}
          />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', permission: 'TmsCargo:Add', onClick: () => openDialog() },
    {
      type: 'import',
      permission: 'TmsCargo:Import',
      importColumns: cargoExcelColumns,
      importTransformer: (rows) =>
        rows.map((row) => normalizeImportRow(row as Record<string, unknown>)),
      importApi: async (rows) => {
        await importCargoes(rows as Cargo[])
      },
      onImportError: () => {
        ElMessage.error('导入文件解析失败')
      }
    },
    {
      type: 'export',
      permission: 'TmsCargo:Export',
      exportFilename: 'TMS货物资料',
      exportSheetName: '货物管理',
      exportColumns: cargoExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportCargoList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    },
    {
      type: 'delete',
      permission: 'TmsCargo:Delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 条货物资料吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        const rows = selectedRows as Cargo[]
        if (await inspectDeleteDependencies(rows)) return
        await deleteCargoBatch(rows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCargoList({ ...params, from, to })
  }

  const formatNumber = (value?: number | null, digits = 2): string => {
    if (value === null || value === undefined || Number.isNaN(Number(value))) return '-'
    return Number(value).toFixed(digits)
  }

  const parseOptionalNumber = (value: unknown): number | null => {
    if (value === '' || value === null || value === undefined) return null
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : null
  }

  const normalizeEnabled = (value: unknown): boolean => {
    if (value === false || value === 'false' || value === '停用' || value === '否') return false
    return true
  }

  const normalizeImportRow = (row: Record<string, unknown>): Cargo =>
    ({
      ...row,
      unit: unitLabelToValue.value.get(String(row.unit ?? '')) || String(row.unit ?? ''),
      lengthM: parseOptionalNumber(row.lengthM),
      widthM: parseOptionalNumber(row.widthM),
      heightM: parseOptionalNumber(row.heightM),
      volumeM3: parseOptionalNumber(row.volumeM3),
      weightKg: parseOptionalNumber(row.weightKg),
      valueAmount: parseOptionalNumber(row.valueAmount),
      enabled: normalizeEnabled(row.enabled)
    }) as Cargo

  const openDialog = (row?: Cargo): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const inspectDeleteDependencies = async (rows: Cargo[]): Promise<boolean> => {
    const resources = rows
      .filter((item) => item.id)
      .map((item) => ({ id: String(item.id), label: item.cargoName }))
    if (!resources.length) return false
    return (
      (await deleteGuardRef.value?.inspect({
        resourceType: 'cargo',
        resourceLabel: '货物',
        resources
      })) ?? false
    )
  }

  const handleDeleteGuardCleared = (): void => {
    void tableQueryRef.value?.getData()
  }

  const syncMasterDeleteReturn = (forceRefresh = false): void => {
    if (route.query.resumeMasterDelete !== '1') return
    const recordId = typeof route.query.recordId === 'string' ? route.query.recordId : ''
    const changed = tableState.searchQuery.recordId !== recordId
    Object.assign(tableState.searchQuery, { recordId, keyword: '' })
    if (changed || forceRefresh) void nextTick().then(() => tableQueryRef.value?.getData())
  }

  watch(
    () => route.fullPath,
    () => syncMasterDeleteReturn(),
    { flush: 'post' }
  )
  onActivated(() => syncMasterDeleteReturn(true))

  const handleDelete = async (row: Cargo): Promise<void> => {
    if (!row.id) return
    try {
      if (await inspectDeleteDependencies([row])) return
      await confirmAction(`确定删除货物“${row.cargoName}”吗？删除后无法恢复。`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      await deleteCargo(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }
</script>
