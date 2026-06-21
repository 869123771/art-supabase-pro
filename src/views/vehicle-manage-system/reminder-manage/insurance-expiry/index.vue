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
  import { fetchVehicleInsuranceList } from '@/api/vehicle-manage-system'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import dayjs from 'dayjs'
  import { isNil } from 'lodash-es'

  defineOptions({ name: 'VehicleInsuranceExpiry' })

  type InsuranceRow = Api.VehicleMgtSys.VehicleManage.VehicleInsurance
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
      { prop: 'insuranceTypeName', label: '保险类别', width: 130 },
      { prop: 'expireDate', label: '保险到期日期', width: 150 },
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
    const result = await fetchVehicleInsuranceList({
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

  const createReminderRows = (rows: InsuranceRow[]): ReminderRow[] =>
    rows.flatMap((row) => {
      const common = {
        sourceId: row.id,
        vehicleId: row.vehicleId,
        companyName: row.companyName,
        plateNo: row.plateNo
      }
      const reminders: ReminderRow[] = []

      if (!isNil(row.commercialExpireDate) && row.commercialExpireDate !== '') {
        const remainingDays = getRemainingDays(row.commercialExpireDate)
        reminders.push({
          ...common,
          id: `${row.id ?? row.plateNo}-commercial`,
          insuranceType: 'commercial',
          insuranceTypeName: '商业险',
          expireDate: row.commercialExpireDate,
          remainingDays,
          expired: isExpired(remainingDays)
        })
      }

      if (!isNil(row.compulsoryExpireDate) && row.compulsoryExpireDate !== '') {
        const remainingDays = getRemainingDays(row.compulsoryExpireDate)
        reminders.push({
          ...common,
          id: `${row.id ?? row.plateNo}-compulsory`,
          insuranceType: 'compulsory',
          insuranceTypeName: '交强险',
          expireDate: row.compulsoryExpireDate,
          remainingDays,
          expired: isExpired(remainingDays)
        })
      }

      return reminders
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
