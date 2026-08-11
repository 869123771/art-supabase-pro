<template>
  <div class="vehicle-query-page art-full-height">
    <section class="vehicle-query-page__overview art-card-xs">
      <header class="vehicle-query-page__hero">
        <div class="vehicle-query-page__identity">
          <div class="vehicle-query-page__brand" aria-hidden="true">
            <ArtSvgIcon icon="ri:roadster-line" />
          </div>
          <div>
            <span>FLEET INTELLIGENCE</span>
            <h1>车辆全景查询</h1>
            <p>以车辆档案为主线，集中核验运营状态、里程、保险、年检与维保资料。</p>
          </div>
        </div>
        <div class="vehicle-query-page__hero-status">
          <ElTag type="success" effect="light" round>仅展示已审核档案</ElTag>
          <ElTag type="primary" effect="plain" round>一车一档</ElTag>
        </div>
      </header>

      <div class="vehicle-query-page__metrics" aria-label="车辆档案概览">
        <article>
          <div class="vehicle-query-page__metric-icon is-primary">
            <ArtSvgIcon icon="ri:truck-line" />
          </div>
          <div>
            <span>当前结果</span>
            <strong>{{ overview.total }}</strong>
            <small>随筛选条件实时更新</small>
          </div>
        </article>
        <article>
          <div class="vehicle-query-page__metric-icon is-success">
            <ArtSvgIcon icon="ri:shield-check-line" />
          </div>
          <div>
            <span>本页运营资料齐全</span>
            <strong>{{ coverageCompleteCount }}</strong>
            <small>保险、年检与保养均有记录</small>
          </div>
        </article>
        <article>
          <div class="vehicle-query-page__metric-icon is-warning">
            <ArtSvgIcon icon="ri:file-warning-line" />
          </div>
          <div>
            <span>本页资料待补</span>
            <strong>{{ coverageMissingCount }}</strong>
            <small>至少一项运营保障记录缺失</small>
          </div>
        </article>
      </div>
    </section>

    <ArtTableQuery
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :search-bar-props="{ span: 6, labelWidth: 90 }"
      :table-props="table.props"
      :on-success="handleTableSuccess"
      focusable
    />
  </div>
</template>

<script setup lang="tsx">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryProps } from '@/components/core/tables/art-table-query/index.vue'
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
  import { mapWithConcurrency } from '@/utils/async'
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
    props: {
      rowKey: string
      tableLayout: 'fixed'
      emptyText: string
      emptyDescription: string
    }
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const overview = reactive<{ total: number; rows: VehicleQueryRow[] }>({
    total: 0,
    rows: []
  })
  const coverageCompleteCount = computed(
    () =>
      overview.rows.filter(
        (row) => row.insuranceReady && row.inspectionReady && row.maintenanceReady
      ).length
  )
  const coverageMissingCount = computed(() => overview.rows.length - coverageCompleteCount.value)

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      companyName: '',
      plateNo: '',
      manufacturer: '',
      vin: '',
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
        label: '车架号（VIN）',
        key: 'vin',
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
      { type: 'globalIndex', label: '序号', width: 64 },
      {
        prop: 'vehicleIdentity',
        label: '车辆档案',
        minWidth: 240,
        formatter: (row) => renderVehicleIdentity(row)
      },
      { prop: 'companyName', label: '所属公司', minWidth: 170, showOverflowTooltip: true },
      {
        prop: 'vehicleType',
        label: '车型',
        width: 110,
        dict: { code: 'vehicleType', display: 'auto' }
      },
      {
        prop: 'operationStatus',
        label: '营运状态',
        width: 110,
        dict: { code: 'vehicleOperationStatus', display: 'auto' }
      },
      {
        prop: 'lifecycle',
        label: '车辆周期',
        minWidth: 190,
        formatter: (row) => renderLifecycle(row)
      },
      {
        prop: 'runningMileage',
        label: '累计里程',
        width: 130,
        formatter: (row) => (
          <span class="vehicle-query-page__mileage">{formatMileage(row.runningMileage)}</span>
        )
      },
      {
        prop: 'operationCoverage',
        label: '运营保障资料',
        minWidth: 230,
        formatter: (row) =>
          renderDocumentStatus([
            { label: '保险', ready: row.insuranceReady },
            { label: '年检', ready: row.inspectionReady },
            { label: '保养', ready: row.maintenanceReady }
          ])
      },
      {
        prop: 'warrantyCoverage',
        label: '质保资料',
        minWidth: 165,
        formatter: (row) =>
          renderDocumentStatus([
            { label: '三包', ready: row.threeGuaranteeReady },
            { label: '包修', ready: row.warrantyReady }
          ])
      },
      {
        prop: 'operation',
        label: '操作',
        width: 96,
        fixed: 'right',
        formatter: (row) => (
          <div class="vehicle-query-page__operation">
            <ArtButtonTable type="view" onClick={() => openDetail(row)} />
          </div>
        )
      }
    ],
    props: {
      rowKey: 'id',
      tableLayout: 'fixed',
      emptyText: '暂无符合条件的车辆档案',
      emptyDescription: '可调整公司、车牌号、厂商或营运状态后重新查询。'
    }
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
    const summaries = await mapWithConcurrency(rows, 4, (row) => loadVehicleSummary(row))
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

  const handleTableSuccess: NonNullable<ArtTableQueryProps['onSuccess']> = (rows, response) => {
    overview.rows = rows as VehicleQueryRow[]
    overview.total = response.total ?? rows.length
  }

  const renderVehicleIdentity = (row: VehicleQueryRow) => (
    <div class="vehicle-query-page__vehicle-cell">
      <div>
        <strong>{row.plateNo || '未录入车牌'}</strong>
        <span>{row.manufacturer || '厂商待补充'}</span>
      </div>
      <small title={row.vin}>{row.vin || 'VIN 待补充'}</small>
    </div>
  )

  const renderLifecycle = (row: VehicleQueryRow) => (
    <div class="vehicle-query-page__lifecycle">
      <p>
        <span>启用</span>
        <strong>{formatDate(row.startUseDate)}</strong>
      </p>
      <small>
        购入 {formatDate(row.invoiceDate)} · 已运营 {formatDecimal(row.operationYears)} 年
      </small>
    </div>
  )

  const renderDocumentStatus = (items: Array<{ label: string; ready: boolean }>) => (
    <div class="vehicle-query-page__document-status">
      {items.map((item) => (
        <span
          class={item.ready ? 'is-ready' : 'is-missing'}
          title={`${item.label}${item.ready ? '已有记录' : '待补充记录'}`}
        >
          <i aria-hidden="true"></i>
          {item.label}
        </span>
      ))}
    </div>
  )

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

<style scoped lang="scss">
  .vehicle-query-page {
    gap: 12px;
    min-width: 0;

    &__overview {
      flex: 0 0 auto;
      min-width: 0;
      overflow: hidden;
    }

    &__hero,
    &__identity,
    &__hero-status,
    &__metrics article,
    &__brand,
    &__metric-icon {
      display: flex;
      align-items: center;
    }

    &__hero {
      gap: 20px;
      justify-content: space-between;
      padding: 20px 24px 18px;
      background: radial-gradient(
        circle at 92% 0%,
        var(--el-color-primary-light-9),
        transparent 34%
      );
    }

    &__identity {
      min-width: 0;

      > div:last-child {
        min-width: 0;
      }

      > div > span {
        display: block;
        margin-bottom: 3px;
        font-size: 10px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.14em;
      }

      h1 {
        margin: 0 0 3px;
        font-size: 22px;
        line-height: 1.35;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 13px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__brand {
      flex: 0 0 50px;
      justify-content: center;
      width: 50px;
      height: 50px;
      margin-right: 16px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), var(--el-color-primary-dark-2));
      border-radius: var(--custom-radius);

      :deep(svg) {
        width: 23px;
        height: 23px;
      }
    }

    &__hero-status {
      flex: none;
      gap: 8px;
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      border-top: 1px solid var(--el-border-color-lighter);

      article {
        gap: 12px;
        min-width: 0;
        padding: 14px 24px;

        &:not(:last-child) {
          border-right: 1px solid var(--el-border-color-lighter);
        }

        > div:last-child {
          display: grid;
          min-width: 0;
        }

        span,
        small {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }

        span {
          font-size: 12px;
        }

        strong {
          margin: 1px 0;
          font-size: 20px;
          line-height: 1.25;
          color: var(--el-text-color-primary);
        }

        small {
          font-size: 11px;
        }
      }
    }

    &__metric-icon {
      flex: 0 0 38px;
      justify-content: center;
      width: 38px;
      height: 38px;
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 18px;
        height: 18px;
      }

      &.is-primary {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-success {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      &.is-warning {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
      }
    }

    :deep(.vehicle-query-page__vehicle-cell),
    :deep(.vehicle-query-page__lifecycle) {
      display: grid;
      min-width: 0;
      line-height: 20px;
    }

    :deep(.vehicle-query-page__vehicle-cell > div) {
      display: flex;
      gap: 8px;
      align-items: center;
      min-width: 0;
    }

    :deep(.vehicle-query-page__vehicle-cell strong) {
      flex: none;
      padding: 1px 8px;
      font-weight: 700;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: 4px;
    }

    :deep(.vehicle-query-page__vehicle-cell span),
    :deep(.vehicle-query-page__vehicle-cell small),
    :deep(.vehicle-query-page__lifecycle small) {
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      white-space: nowrap;
    }

    :deep(.vehicle-query-page__lifecycle p) {
      display: flex;
      gap: 6px;
      margin: 0;

      span {
        color: var(--el-text-color-secondary);
      }

      strong {
        color: var(--el-text-color-primary);
      }
    }

    :deep(.vehicle-query-page__mileage) {
      font-weight: 600;
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-primary);
    }

    :deep(.vehicle-query-page__document-status) {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      align-items: center;

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        padding: 2px 7px;
        font-size: 12px;
        line-height: 20px;
        border-radius: 999px;

        i {
          width: 6px;
          height: 6px;
          border-radius: 50%;
        }
      }

      .is-ready {
        color: var(--el-color-success-dark-2);
        background: var(--el-color-success-light-9);

        i {
          background: var(--el-color-success);
        }
      }

      .is-missing {
        color: var(--el-text-color-secondary);
        background: var(--el-fill-color-light);

        i {
          background: var(--el-text-color-placeholder);
        }
      }
    }

    :deep(.vehicle-query-page__operation) {
      display: flex;
      gap: 8px;
      align-items: center;

      .art-button-table {
        margin-right: 0;
      }
    }

    @media (width <= 900px) {
      &__hero {
        align-items: flex-start;
      }

      &__hero-status {
        flex-direction: column;
        align-items: flex-end;
      }

      &__metrics article {
        padding-inline: 16px;
      }
    }

    @media (width <= 640px) {
      &__hero {
        flex-direction: column;
        padding: 18px;
      }

      &__hero-status {
        flex-direction: row;
        align-items: center;
        margin-left: 66px;
      }

      &__metrics {
        grid-template-columns: 1fr;

        article:not(:last-child) {
          border-right: 0;
          border-bottom: 1px solid var(--el-border-color-lighter);
        }
      }
    }
  }
</style>
