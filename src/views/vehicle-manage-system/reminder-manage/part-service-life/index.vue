<template>
  <div class="art-full-height">
    <ArtTableQuery
      v-model="tableState.searchQuery"
      v-model:show-search-bar="tableState.showSearchBar"
      :search-items="tableConfig.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="tableConfig.columnsFactory"
      :search-bar-props="tableConfig.searchBarProps"
      :table-props="tableConfig.tableProps"
    />
  </div>
</template>

<script setup lang="tsx">
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehiclePartUsageList } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import dayjs from 'dayjs'
  import { isNil } from 'lodash-es'

  defineOptions({ name: 'VehiclePartServiceLife' })

  type PartUsageRow = Api.VehicleMgtSys.VehicleManage.VehiclePartUsage
  type ReminderRow = Api.VehicleMgtSys.ReminderManage.VehicleReminderRow
  type ReminderSearchParams = Api.VehicleMgtSys.ReminderManage.VehicleReminderSearchParams
  type ReminderTableParams = ReminderSearchParams &
    Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableState {
    showSearchBar: boolean
    searchQuery: ReminderSearchParams
  }

  interface TableConfig {
    searchItems: SearchFormItem[]
    searchBarProps: { span: number; labelWidth: number; showExpand: boolean }
    tableProps: { rowKey: string; tableLayout: 'fixed' }
    columnsFactory: () => ColumnOption<ReminderRow>[]
  }

  const { getDictMap } = storeToRefs(useUserStore())

  const tableState = reactive<TableState>({
    showSearchBar: false,
    searchQuery: {
      companyName: '',
      plateNo: '',
      expired: undefined
    }
  })

  const tableConfig = computed<TableConfig>(() => {
    const commonBooleanOptions = getDictMap.value.commonBoolean

    return {
      searchItems: [
        { label: '所属公司', key: 'companyName', type: 'input' },
        { label: '车牌号', key: 'plateNo', type: 'input' },
        {
          label: '是否到期',
          key: 'expired',
          type: 'select',
          props: {
            options: (isNil(commonBooleanOptions) ? [] : commonBooleanOptions).map((item) => ({
              ...item,
              value: item.value === 'true'
            }))
          }
        }
      ],
      searchBarProps: { span: 6, labelWidth: 100, showExpand: false },
      tableProps: { rowKey: 'id', tableLayout: 'fixed' },
      columnsFactory: () => [
        { type: 'globalIndex', label: '序号', width: 72 },
        { prop: 'companyName', label: '所属公司', minWidth: 170 },
        { prop: 'plateNo', label: '车牌号', width: 130 },
        {
          prop: 'partType',
          label: '零部件类型',
          width: 125,
          dict: { code: 'vehiclePartType', display: 'auto' }
        },
        { prop: 'partName', label: '零部件名称', minWidth: 170 },
        { prop: 'categoryName', label: '类别', minWidth: 130 },
        { prop: 'brand', label: '品牌', width: 110 },
        { prop: 'model', label: '型号', minWidth: 130 },
        { prop: 'rfidTag', label: 'RFID标签', minWidth: 150 },
        {
          prop: 'usedMileage',
          label: '已使用里程（公里）',
          width: 175,
          formatter: (row) => formatMileage(row.usedMileage)
        },
        {
          prop: 'serviceMileage',
          label: '可使用里程（公里）',
          width: 175,
          formatter: (row) => formatMileage(row.serviceMileage)
        },
        { prop: 'expireDate', label: '零部件使用到期日期', width: 190 },
        {
          prop: 'expired',
          label: '是否到期',
          width: 110,
          dict: { code: 'commonBoolean', display: 'auto', value: (row) => String(row.expired) }
        }
      ]
    }
  })

  const fetchTableData = async (params: ReminderTableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchVehiclePartUsageList({
      companyName: params.companyName,
      plateNo: params.plateNo,
      from,
      to
    })

    return {
      ...result,
      data: filterReminderRows(createReminderRows(result.data ?? []), params)
    }
  }

  const createReminderRows = (rows: PartUsageRow[]): ReminderRow[] =>
    rows.map((row) => {
      const expireDate = getExpireDate(row)
      const remainingDays = getRemainingDays(expireDate)
      const dateExpired = !isNil(remainingDays) && remainingDays < 0
      const mileageExpired =
        row.serviceMileageEnabled &&
        !isNil(row.usedMileage) &&
        !isNil(row.serviceMileage) &&
        row.usedMileage >= row.serviceMileage

      return {
        id: row.id ?? `${row.plateNo}-${row.partName}`,
        sourceId: row.id,
        vehicleId: row.vehicleId,
        companyName: row.companyName,
        plateNo: row.plateNo,
        partType: row.partType,
        partName: row.partName,
        categoryName: row.categoryName,
        brand: row.brand,
        model: row.model,
        rfidTag: row.rfidTag,
        usedMileage: row.usedMileage,
        serviceMileage: row.serviceMileage,
        expireDate,
        remainingDays,
        expired: dateExpired || mileageExpired
      }
    })

  const filterReminderRows = (rows: ReminderRow[], params: ReminderSearchParams): ReminderRow[] => {
    const expired = normalizeBoolean(params.expired)
    return rows.filter((row) => (isNil(expired) ? true : row.expired === expired))
  }

  const normalizeBoolean = (value: unknown): boolean | undefined => {
    if (value === true || value === 'true') return true
    if (value === false || value === 'false') return false
    return undefined
  }

  const getExpireDate = (row: PartUsageRow): string | null => {
    if (!row.serviceYearsEnabled || isNil(row.serviceYears) || isNil(row.enableDate)) return null
    if (row.enableDate === '' || !dayjs(row.enableDate).isValid()) return null
    return dayjs(row.enableDate).add(row.serviceYears, 'year').format('YYYY-MM-DD')
  }

  const getRemainingDays = (expireDate?: string | null): number | null => {
    if (isNil(expireDate) || expireDate === '' || !dayjs(expireDate).isValid()) return null
    return dayjs(expireDate).startOf('day').diff(dayjs().startOf('day'), 'day')
  }

  const formatMileage = (value?: number | null): string =>
    isNil(value) ? '--' : Number(value).toLocaleString()
</script>
