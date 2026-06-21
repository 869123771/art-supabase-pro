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
  import { fetchVehicleArchiveList } from '@/api/vehicle-manage-system'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import dayjs from 'dayjs'
  import { isNil } from 'lodash-es'

  defineOptions({ name: 'VehicleServiceLife' })

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
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

  const tableState = reactive<TableState>({
    showSearchBar: false,
    searchQuery: {
      companyName: '',
      plateNo: '',
      reminderDays: undefined
    }
  })

  const tableConfig: TableConfig = {
    searchItems: [
      { label: '所属公司', key: 'companyName', type: 'input' },
      { label: '车牌号', key: 'plateNo', type: 'input' },
      {
        label: '未来到期天数',
        key: 'reminderDays',
        type: 'number',
        props: { min: 0, controls: false, placeholder: '全部' }
      }
    ],
    searchBarProps: { span: 6, labelWidth: 100, showExpand: false },
    tableProps: { rowKey: 'id', tableLayout: 'fixed' },
    columnsFactory: () => [
      { type: 'globalIndex', label: '序号', width: 72 },
      { prop: 'companyName', label: '所属公司', minWidth: 170 },
      { prop: 'plateNo', label: '车牌号', width: 130 },
      { prop: 'startUseDate', label: '启用日期', width: 140 },
      { prop: 'serviceYears', label: '使用年限（年）', width: 150 },
      { prop: 'expireDate', label: '车辆使用到期日期', minWidth: 190 },
      {
        prop: 'remainingDays',
        label: '到期提醒',
        minWidth: 150,
        sortable: true,
        formatter: (row) => formatRemainingDays(row.remainingDays)
      }
    ]
  }

  const fetchTableData = async (params: ReminderTableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchVehicleArchiveList({
      companyName: params.companyName,
      plateNo: params.plateNo,
      auditStatus: 'approved',
      from,
      to
    })

    return {
      ...result,
      data: filterReminderRows(createReminderRows(result.data ?? []), params)
    }
  }

  const createReminderRows = (rows: VehicleArchive[]): ReminderRow[] =>
    rows.map((row) => {
      const expireDate = getExpireDate(row)
      const remainingDays = getRemainingDays(expireDate)
      return {
        id: row.id ?? row.plateNo,
        sourceId: row.id,
        vehicleId: row.id,
        companyName: row.companyName,
        plateNo: row.plateNo,
        startUseDate: row.startUseDate,
        serviceYears: row.serviceYears,
        expireDate,
        remainingDays,
        expired: isExpired(remainingDays)
      }
    })

  const filterReminderRows = (rows: ReminderRow[], params: ReminderSearchParams): ReminderRow[] => {
    const reminderDays = isNil(params.reminderDays) ? undefined : Number(params.reminderDays)
    return rows.filter((row) => {
      if (!isNil(reminderDays) && (isNil(row.remainingDays) || row.remainingDays > reminderDays)) {
        return false
      }
      return true
    })
  }

  const getExpireDate = (row: VehicleArchive): string | null => {
    if (isNil(row.startUseDate) || row.startUseDate === '' || isNil(row.serviceYears)) return null
    if (!dayjs(row.startUseDate).isValid()) return null
    return dayjs(row.startUseDate).add(row.serviceYears, 'year').format('YYYY-MM-DD')
  }

  const getRemainingDays = (expireDate?: string | null): number | null => {
    if (isNil(expireDate) || expireDate === '' || !dayjs(expireDate).isValid()) return null
    return dayjs(expireDate).startOf('day').diff(dayjs().startOf('day'), 'day')
  }

  const isExpired = (remainingDays?: number | null): boolean =>
    !isNil(remainingDays) && remainingDays < 0

  const formatRemainingDays = (days?: number | null): string => {
    if (isNil(days)) return '--'
    if (days < 0) return `过期${Math.abs(days)}天`
    return `${days}天`
  }
</script>
