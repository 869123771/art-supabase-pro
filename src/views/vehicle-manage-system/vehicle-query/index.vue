<template>
  <div class="art-full-height">
    <ArtTableQuery
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :search-bar-props="{ span: 6, labelWidth: 90 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    fetchVehicleArchiveList,
    fetchVehicleInspectionList,
    fetchVehicleInsuranceList,
    fetchVehicleMaintenanceList,
    fetchVehicleMileageList
  } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatDate, formatMileage, getLatestByDate } from './modules/query-format'
  import type {
    VehicleArchive,
    VehicleInspection,
    VehicleInsurance,
    VehicleMaintenanceRecord,
    VehicleMileageRecord
  } from './modules/types'
  import { isNil } from 'lodash-es'

  defineOptions({ name: 'VehicleQuery' })

  type SearchParams = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface VehicleQueryRow extends VehicleArchive {
    runningMileage?: number | null
    operationYears?: number | null
    commercialExpireDate?: string
    compulsoryExpireDate?: string
    inspectionExpireDate?: string
    maintenanceExpireDate?: string | null
    insuranceReady: boolean
    inspectionReady: boolean
    maintenanceReady: boolean
    threeGuaranteeReady: boolean
    warrantyReady: boolean
  }

  interface TableGroup {
    searchQuery: SearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    columnsFactory: () => ColumnOption<VehicleQueryRow>[]
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      companyName: '',
      plateNo: '',
      manufacturer: '',
      chassisNo: '',
      operationStatus: undefined
    },
    searchItems: computed<SearchFormItem[]>(() => [
      {
        label: '所属公司',
        key: 'companyName',
        type: 'input',
        props: { clearable: true }
      },
      {
        label: '车牌号',
        key: 'plateNo',
        type: 'input',
        props: { clearable: true }
      },
      {
        label: '车辆厂商',
        key: 'manufacturer',
        type: 'input',
        props: { clearable: true }
      },
      {
        label: '车架号',
        key: 'chassisNo',
        type: 'input',
        props: { clearable: true }
      },
      {
        label: '营运状态',
        key: 'operationStatus',
        type: 'select',
        props: { options: getDictMap.value.vehicleOperationStatus ?? [], clearable: true }
      }
    ]),
    columnsFactory: () => [
      { type: 'globalIndex', label: '序号', width: 70 },
      { prop: 'companyName', label: '所属公司', minWidth: 150 },
      { prop: 'plateNo', label: '车牌号', width: 130 },
      {
        prop: 'vehicleType',
        label: '车型',
        width: 130,
        dict: { code: 'vehicleType', display: 'text' }
      },
      { prop: 'manufacturer', label: '车型厂商', minWidth: 140 },
      { prop: 'vin', label: '车架号', minWidth: 170 },
      {
        prop: 'invoiceDate',
        label: '购入开票日期',
        width: 130,
        formatter: (row) => formatDate(row.invoiceDate)
      },
      {
        prop: 'startUseDate',
        label: '启用日期',
        width: 120,
        formatter: (row) => formatDate(row.startUseDate)
      },
      {
        prop: 'operationStatus',
        label: '营运状态',
        width: 120,
        dict: { code: 'vehicleOperationStatus', display: 'text' }
      },
      {
        prop: 'operationYears',
        label: '运营时长（年）',
        width: 130,
        formatter: (row) => formatDecimal(row.operationYears)
      },
      {
        prop: 'runningMileage',
        label: '运营行驶里程（里程）',
        width: 170,
        formatter: (row) => formatMileage(row.runningMileage)
      },
      { prop: 'serviceYears', label: '使用年限（年）', width: 130 },
      {
        prop: 'insuranceReady',
        label: '保险到期',
        width: 110,
        formatter: (row) => renderCheck(row.insuranceReady)
      },
      {
        prop: 'inspectionReady',
        label: '年检到期',
        width: 110,
        formatter: (row) => renderCheck(row.inspectionReady)
      },
      {
        prop: 'maintenanceReady',
        label: '保养到期',
        width: 110,
        formatter: (row) => renderCheck(row.maintenanceReady)
      },
      {
        prop: 'threeGuaranteeReady',
        label: '三包到期',
        width: 110,
        formatter: (row) => renderCheck(row.threeGuaranteeReady)
      },
      {
        prop: 'warrantyReady',
        label: '包修到期',
        width: 110,
        formatter: (row) => renderCheck(row.warrantyReady)
      },
      {
        prop: 'operation',
        label: '操作',
        width: 110,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex">
            <ArtButtonTable type="view" onClick={() => openDetail(row)} />
          </div>
        )
      }
    ]
  })

  const fetchTableData = async (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    const result = await fetchVehicleArchiveList({
      ...params,
      auditStatus: 'approved',
      from,
      to
    })

    return {
      ...result,
      data: await createQueryRows(result.data ?? [])
    }
  }

  const createQueryRows = async (rows: VehicleArchive[]): Promise<VehicleQueryRow[]> => {
    const summaries = await Promise.all(rows.map((row) => loadVehicleSummary(row)))
    return rows.map((row, index) => ({
      ...row,
      ...summaries[index]
    }))
  }

  const loadVehicleSummary = async (
    row: VehicleArchive
  ): Promise<Omit<VehicleQueryRow, keyof VehicleArchive>> => {
    const [insuranceResult, inspectionResult, maintenanceResult, mileageResult] = await Promise.all(
      [
        fetchVehicleInsuranceList({ plateNo: row.plateNo, from: 0, to: 9999 }),
        fetchVehicleInspectionList({ plateNo: row.plateNo, from: 0, to: 9999 }),
        fetchVehicleMaintenanceList({
          plateNo: row.plateNo,
          maintenanceType: 'maintenance',
          from: 0,
          to: 9999
        }),
        fetchVehicleMileageList({ plateNo: row.plateNo, from: 0, to: 9999 })
      ]
    )

    const latestInsurance = getLatestByDate<VehicleInsurance>(
      insuranceResult.data ?? [],
      (item) => item.createTime
    )
    const latestInspection = getLatestByDate<VehicleInspection>(
      inspectionResult.data ?? [],
      (item) => item.expireDate
    )
    const latestMaintenance = getLatestByDate<VehicleMaintenanceRecord>(
      maintenanceResult.data ?? [],
      (item) => item.startTime
    )
    const latestMileage = getLatestByDate<VehicleMileageRecord>(
      mileageResult.data ?? [],
      (item) => item.endTime || item.startTime
    )

    return {
      runningMileage: latestMileage?.endMileage ?? latestMileage?.runningMileage ?? null,
      operationYears: getOperationYears(row.startUseDate),
      commercialExpireDate: latestInsurance?.commercialExpireDate,
      compulsoryExpireDate: latestInsurance?.compulsoryExpireDate,
      inspectionExpireDate: latestInspection?.expireDate,
      maintenanceExpireDate: latestMaintenance?.startTime,
      insuranceReady: Boolean(
        latestInsurance?.commercialExpireDate || latestInsurance?.compulsoryExpireDate
      ),
      inspectionReady: Boolean(latestInspection?.expireDate),
      maintenanceReady: Boolean(latestMaintenance?.startTime),
      threeGuaranteeReady: !isNil(row.threeGuaranteeMileage) || !isNil(row.threeGuaranteeDuration),
      warrantyReady: !isNil(row.warrantyMileage) || !isNil(row.warrantyDuration)
    }
  }

  const openDetail = (row: VehicleArchive): void => {
    if (!row.id) return
    void router.push(`/vehicle-manage-system/vehicle-query/detail/${row.id}`)
  }

  const renderCheck = (checked: boolean): string => (checked ? '✓' : '')

  const getOperationYears = (startUseDate?: string): number | null => {
    if (!startUseDate) return null
    const start = new Date(startUseDate)
    if (Number.isNaN(start.getTime())) return null
    return Number(((Date.now() - start.getTime()) / (365.25 * 24 * 60 * 60 * 1000)).toFixed(1))
  }

  const formatDecimal = (value?: number | null): string => {
    if (isNil(value)) return '--'
    return String(value)
  }
</script>
