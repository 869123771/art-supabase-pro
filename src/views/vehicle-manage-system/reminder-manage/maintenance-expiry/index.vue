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
  import { fetchVehicleMaintenanceList, fetchVehicleMileageList } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import dayjs from 'dayjs'
  import { isNil } from 'lodash-es'

  defineOptions({ name: 'VehicleMaintenanceExpiry' })

  type MaintenanceRow = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceRecord
  type MileageRow = Api.VehicleMgtSys.VehicleManage.VehicleMileageRecord
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

  const MAINTENANCE_INTERVAL_MONTHS = 6
  const MAINTENANCE_INTERVAL_MILEAGE = 5000
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
          prop: 'currentMaintenanceDate',
          label: '当前保养时间',
          width: 170,
          formatter: (row) => formatWithDayjs(row.currentMaintenanceDate, 'YYYY-MM-DD')
        },
        {
          prop: 'currentMileage',
          label: '当前里程（公里）',
          width: 150,
          formatter: (row) => formatMileage(row.currentMileage)
        },
        {
          prop: 'nextMaintenanceMileage',
          label: '下次保养里程（公里）',
          width: 185,
          formatter: (row) => formatMileage(row.nextMaintenanceMileage)
        },
        { prop: 'nextMaintenanceDate', label: '下次保养时间', width: 150 },
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
    const result = await fetchVehicleMaintenanceList({
      companyName: params.companyName,
      plateNo: params.plateNo,
      maintenanceType: 'maintenance',
      from,
      to
    })
    const rows = await createReminderRows(result.data ?? [])

    return {
      ...result,
      data: filterReminderRows(rows, params)
    }
  }

  const createReminderRows = async (rows: MaintenanceRow[]): Promise<ReminderRow[]> => {
    const mileageMap = await fetchMileageMap(rows)

    return rows.map((row) => {
      const mileageRows = mileageMap.get(row.plateNo) ?? []
      const currentMileage = getLatestMileage(mileageRows)
      const maintenanceMileage = getMileageAtTime(mileageRows, row.startTime) ?? currentMileage
      const nextMaintenanceMileage = isNil(maintenanceMileage)
        ? null
        : maintenanceMileage + MAINTENANCE_INTERVAL_MILEAGE
      const nextMaintenanceDate = getNextMaintenanceDate(row.startTime)
      const remainingDays = getRemainingDays(nextMaintenanceDate)
      const mileageExpired =
        !isNil(currentMileage) &&
        !isNil(nextMaintenanceMileage) &&
        currentMileage >= nextMaintenanceMileage
      const dateExpired = !isNil(remainingDays) && remainingDays < 0

      return {
        id: row.id ?? `${row.plateNo}-${row.startTime}`,
        sourceId: row.id,
        vehicleId: row.vehicleId,
        companyName: row.companyName,
        plateNo: row.plateNo,
        currentMaintenanceDate: row.startTime,
        currentMileage,
        nextMaintenanceMileage,
        nextMaintenanceDate,
        expireDate: nextMaintenanceDate,
        remainingDays,
        expired: dateExpired || mileageExpired
      }
    })
  }

  const fetchMileageMap = async (rows: MaintenanceRow[]): Promise<Map<string, MileageRow[]>> => {
    const plateNos = [
      ...new Set(rows.map((row) => row.plateNo).filter((plateNo) => plateNo !== ''))
    ]
    const entries = await Promise.all(
      plateNos.map(async (plateNo) => {
        const result = await fetchVehicleMileageList({ plateNo, from: 0, to: 9999 })
        return [plateNo, result.data ?? []] as const
      })
    )

    return new Map(entries)
  }

  const filterReminderRows = (rows: ReminderRow[], params: ReminderSearchParams): ReminderRow[] => {
    const expired = normalizeBoolean(params.expired)
    return rows.filter((row) => (isNil(expired) ? true : row.expired === expired))
  }

  const normalizeBoolean = (value: unknown): boolean | undefined => {
    if (value === true || value === 'true') return true
    if (value === false || value === 'false') return false
    return undefined
  }

  const getNextMaintenanceDate = (startTime?: string): string | null => {
    if (isNil(startTime) || startTime === '' || !dayjs(startTime).isValid()) return null
    return dayjs(startTime).add(MAINTENANCE_INTERVAL_MONTHS, 'month').format('YYYY-MM-DD')
  }

  const getRemainingDays = (expireDate?: string | null): number | null => {
    if (isNil(expireDate) || expireDate === '' || !dayjs(expireDate).isValid()) return null
    return dayjs(expireDate).startOf('day').diff(dayjs().startOf('day'), 'day')
  }

  const getMileageValue = (row?: MileageRow): number | null => {
    const value = row?.endMileage ?? row?.runningMileage ?? row?.startMileage
    return isNil(value) ? null : Number(value)
  }

  const getMileageTime = (row: MileageRow): number => {
    const value = row.endTime || row.startTime || row.createTime
    return isNil(value) || value === '' || !dayjs(value).isValid() ? 0 : dayjs(value).valueOf()
  }

  const sortMileageRows = (rows: MileageRow[]): MileageRow[] =>
    [...rows].sort((first, second) => getMileageTime(second) - getMileageTime(first))

  const getLatestMileage = (rows: MileageRow[]): number | null =>
    getMileageValue(sortMileageRows(rows)[0])

  const getMileageAtTime = (rows: MileageRow[], targetTime?: string): number | null => {
    if (isNil(targetTime) || targetTime === '' || !dayjs(targetTime).isValid()) return null
    const target = dayjs(targetTime).valueOf()
    const row = sortMileageRows(rows).find((item) => getMileageTime(item) <= target)
    return getMileageValue(row)
  }

  const formatMileage = (value?: number | null): string =>
    isNil(value) ? '--' : Number(value).toLocaleString()
</script>
