<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="tableState.searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
    />

    <StationDialog ref="dialogRef" @success="handleSaveSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessage, ElMessageBox, ElSwitch } from 'element-plus'
  import { trim, uniq } from 'lodash-es'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import { ColumnOption, DialogType } from '@/types'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteStation,
    deleteStationBatch,
    exportStationList,
    fetchStationList,
    importStations,
    updateStationEnabled
  } from '@/api/tms'
  import StationDialog from './modules/station-dialog.vue'

  defineOptions({ name: 'TmsStation' })

  type Station = Api.Tms.Station.StationRecord
  type StationSavePayload = Api.Tms.Station.StationSavePayload
  type SearchParams = Api.Tms.Station.StationSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface StationDialogExpose {
    handleOpen: (row?: Station) => Promise<void>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<StationDialogExpose>()

  const tableState = reactive<{ searchQuery: SearchParams }>({
    searchQuery: {
      stationType: '',
      enabled: undefined,
      keyword: ''
    }
  })

  const stationTypeOptions = computed(() => getDictMap.value.tmsStationType ?? [])
  const commonBooleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const stationTypeLabelToValue = computed(() => {
    const map = new Map<string, string>()
    stationTypeOptions.value.forEach((item) => {
      if (item.label && item.value) map.set(item.label, item.value)
    })
    return map
  })

  const stationTypeValueToLabel = computed(() => {
    const map = new Map<string, string>()
    stationTypeOptions.value.forEach((item) => {
      if (item.label && item.value) map.set(item.value, item.label)
    })
    return map
  })

  const getStationTypes = (station: Station): string[] => {
    const roleTypes = (station.stationRoles ?? []).map((item) => String(item.roleType))
    return uniq(roleTypes.length ? roleTypes : [String(station.stationType || '')]).filter(Boolean)
  }

  const stationExcelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'stationCode', title: '编号' },
    { key: 'stationName', title: '站名称', required: true },
    {
      key: 'stationTypes',
      title: '类型',
      required: true,
      formatter: (_value, row) =>
        getStationTypes(row as Station)
          .map((type) => stationTypeValueToLabel.value.get(type) || type)
          .join('、')
    },
    { key: 'regionCode', title: '地区编码' },
    { key: 'managerName', title: '负责人' },
    { key: 'contactPhone', title: '联系电话' },
    { key: 'enabled', title: '状态' },
    { key: 'remark', title: '备注' }
  ]

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '关键字',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '站点编码、名称、负责人或电话'
      }
    },
    {
      label: '站点类型',
      key: 'stationType',
      type: 'select',
      props: {
        options: stationTypeOptions.value,
        clearable: true,
        placeholder: '请选择站点类型'
      }
    },
    {
      label: '状态',
      key: 'enabled',
      type: 'select',
      props: {
        options: commonBooleanOptions.value,
        clearable: true,
        placeholder: '请选择状态'
      }
    }
  ])

  const columnsFactory = (): ColumnOption<Station>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { prop: 'stationCode', label: '编号', width: 120 },
    {
      prop: 'stationName',
      label: '站名称',
      minWidth: 180,
      showOverflowTooltip: true
    },
    {
      prop: 'stationRoles',
      label: '类型',
      minWidth: 220,
      formatter: (row) => (
        <div class="flex flex-wrap gap-1">
          {getStationTypes(row).map((type) => (
            <ArtDictDisplay key={type} dictCode="tmsStationType" value={type} display="tag" />
          ))}
        </div>
      )
    },
    {
      prop: 'regionCode',
      label: '地区编码',
      minWidth: 130,
      formatter: (row) => row.regionCode || '-'
    },
    {
      prop: 'managerName',
      label: '负责人',
      width: 120,
      formatter: (row) => row.managerName || '-'
    },
    {
      prop: 'contactPhone',
      label: '联系电话',
      width: 150,
      formatter: (row) => row.contactPhone || '-'
    },
    {
      prop: 'enabled',
      label: '状态',
      width: 100,
      formatter: (row) => (
        <ElSwitch
          modelValue={row.enabled}
          inlinePrompt
          activeText="启"
          inactiveText="停"
          onChange={(value) => handleStatusChange(row, Boolean(value))}
        />
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
          <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    { type: 'add', onClick: () => openDialog() },
    {
      type: 'import',
      importColumns: stationExcelColumns,
      importTransformer: (rows) =>
        rows.map((row) => normalizeImportRow(row as Record<string, unknown>)),
      importApi: async (rows) => {
        await importStations(rows as StationSavePayload[])
      },
      onImportError: () => {
        ElMessage.error('导入文件解析失败')
      }
    },
    {
      type: 'export',
      exportFilename: 'TMS站点资料',
      exportSheetName: '站点管理',
      exportColumns: stationExcelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportStationList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    },
    {
      type: 'delete',
      content: ({ selectedCount }: { selectedCount: number }) =>
        `确定删除选中的 ${selectedCount} 条站点资料吗？删除后无法恢复。`,
      onClick: async ({ selectedRows }) => {
        await deleteStationBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
        await tableQueryRef.value?.refreshRemove()
      }
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchStationList({ ...params, from, to })
  }

  const normalizeEnabled = (value: unknown): boolean => {
    if (value === false || value === 'false' || value === '停用' || value === '否') return false
    return true
  }

  const normalizeStationTypes = (value: unknown): string[] =>
    uniq(
      String(value ?? '')
        .split(/[、,，;；]/)
        .map((item) => trim(item))
        .filter(Boolean)
        .map((item) => stationTypeLabelToValue.value.get(item) || item)
    )

  const normalizeImportRow = (row: Record<string, unknown>): StationSavePayload =>
    ({
      ...row,
      stationTypes: normalizeStationTypes(row.stationTypes),
      enabled: normalizeEnabled(row.enabled)
    }) as StationSavePayload

  const openDialog = (row?: Station): void => {
    void dialogRef.value?.handleOpen(row)
  }

  const handleSaveSuccess = (type: DialogType): void => {
    void (type === 'add'
      ? tableQueryRef.value?.refreshCreate()
      : tableQueryRef.value?.refreshUpdate())
  }

  const handleStatusChange = async (row: Station, enabled: boolean): Promise<void> => {
    if (!row.id) return
    const previous = row.enabled
    row.enabled = enabled
    try {
      await updateStationEnabled(row.id, enabled)
    } catch {
      row.enabled = previous
    }
  }

  const handleDelete = async (row: Station): Promise<void> => {
    if (!row.id) return
    try {
      await ElMessageBox.confirm(
        `确定删除站点“${row.stationName}”吗？删除后无法恢复。`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteStation(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时不需要提示。
    }
  }
</script>
