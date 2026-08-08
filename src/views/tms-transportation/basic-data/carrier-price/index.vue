<template>
  <div class="tms-workspace-page art-full-height carrier-price">
    <TmsWorkspaceHeader
      eyebrow="CARRIER RATE CARD"
      title="承运商报价"
      description="维护承运线路、运输模式与结算计价规则，为调度决策和成本测算提供依据。"
      icon="ri:money-cny-circle-line"
      :tags="[
        { label: '采购运价', type: 'primary' },
        { label: '成本基线', type: 'warning' }
      ]"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{
        tableLayout: 'fixed',
        fit: false,
        showOverflowTooltip: false,
        emptyText: '暂无承运商报价',
        emptyDescription: '可新增承运商价，或调整线路、运输模式、计费方式和日期后查询。'
      }"
      focusable
    />
  </div>
</template>

<script setup lang="tsx">
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type {
    ArtTableQueryExcelColumn,
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchRegionOptions } from '@/api/common'
  import {
    deleteCarrierPrice,
    deleteCarrierPriceBatch,
    exportCarrierPriceList,
    fetchCarrierPriceList
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import TmsWorkspaceHeader from '@/views/tms-transportation/modules/tms-workspace-header.vue'

  defineOptions({ name: 'TmsCarrierPrice' })

  const { confirmAction } = useArtFeedback()

  type CarrierPrice = Api.Tms.BasicData.CarrierPrice
  type SearchParams = Api.Tms.BasicData.CarrierPriceSearchParams
  type SearchModel = SearchParams & {
    originRegionPath?: string[]
    destinationRegionPath?: string[]
  }
  type TableParams = SearchModel & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface TableGroup {
    searchQuery: SearchModel
    transportModeOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    billingMethodOptions: ComputedRef<Api.DataCenter.DictListItem[]>
    excelColumns: ComputedRef<ArtTableQueryExcelColumn[]>
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<CarrierPrice>[]
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      originRegionPath: [],
      destinationRegionPath: [],
      createTimeRange: [],
      keyword: ''
    },
    transportModeOptions: computed(getTransportModeOptions),
    billingMethodOptions: computed(getBillingMethodOptions),
    excelColumns: computed(createExcelColumns),
    searchItems: computed(createSearchItems),
    headerActions: computed(createHeaderActions),
    columnsFactory: createColumns
  })

  function getTransportModeOptions(): Api.DataCenter.DictListItem[] {
    return getDictMap.value.tmsCarrierPriceTransportMode ?? []
  }

  function getBillingMethodOptions(): Api.DataCenter.DictListItem[] {
    return getDictMap.value.tmsCustomerPriceBillingMethod ?? []
  }

  function createExcelColumns(): ArtTableQueryExcelColumn[] {
    return [
      { key: 'originRegion', title: '始发地' },
      { key: 'destinationRegion', title: '目的地' },
      { key: 'transportMode', title: '运输方式', formatter: (value) => formatTransportMode(value) },
      {
        key: 'carrierName',
        title: '承运商',
        formatter: (_value, row) => (row as CarrierPrice).carrier?.companyName || ''
      },
      {
        key: 'driverName',
        title: '司机',
        formatter: (_value, row) => (row as CarrierPrice).driverName || ''
      },
      {
        key: 'driverPhone',
        title: '手机号码',
        formatter: (_value, row) => (row as CarrierPrice).driverPhone || ''
      },
      {
        key: 'plateNo',
        title: '车牌号',
        formatter: (_value, row) => (row as CarrierPrice).plateNo || ''
      },
      { key: 'vehicleType', title: '车型', formatter: (value) => formatVehicleType(value) },
      { key: 'vehicleLength', title: '车长', formatter: (value) => formatVehicleLength(value) },
      { key: 'billingMethod', title: '计费方式', formatter: (value) => formatBillingMethod(value) },
      {
        key: 'totalFee',
        title: '运费合计（元）',
        formatter: (value) => formatMoney(value as string | number | null)
      },
      { key: 'createBy', title: '创建人' },
      {
        key: 'createTime',
        title: '创建时间',
        formatter: (value) => formatDateTime(value as string | null)
      }
    ]
  }

  function createSearchItems(): SearchFormItem[] {
    return [
      {
        label: '始发地',
        key: 'originRegionPath',
        type: 'cascader',
        api: fetchRegionOptions,
        labelField: 'name',
        valueField: 'name',
        childrenField: 'children',
        props: {
          class: 'w-full',
          clearable: true,
          filterable: true,
          placeholder: '请选择',
          props: {
            label: 'name',
            value: 'name',
            children: 'children',
            emitPath: true,
            checkStrictly: true
          }
        }
      },
      {
        label: '目的地',
        key: 'destinationRegionPath',
        type: 'cascader',
        api: fetchRegionOptions,
        labelField: 'name',
        valueField: 'name',
        childrenField: 'children',
        props: {
          class: 'w-full',
          clearable: true,
          filterable: true,
          placeholder: '请选择',
          props: {
            label: 'name',
            value: 'name',
            children: 'children',
            emitPath: true,
            checkStrictly: true
          }
        }
      },
      {
        label: '运输方式',
        key: 'transportMode',
        type: 'select',
        props: { options: table.transportModeOptions, clearable: true, placeholder: '请选择' }
      },
      {
        label: '创建日期',
        key: 'createTimeRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          startPlaceholder: '请选择日期',
          endPlaceholder: '请选择日期',
          rangeSeparator: '~'
        }
      },
      {
        label: '',
        key: 'keyword',
        type: 'input',
        props: { clearable: true, placeholder: '请输入关键词搜索' }
      }
    ]
  }

  function createHeaderActions(): ArtTableQueryHeaderAction[] {
    return [
      { type: 'add', label: '新增', onClick: () => openEditPage() },
      {
        type: 'delete',
        label: '批量操作',
        content: ({ selectedCount }: { selectedCount: number }) =>
          `确定删除选中的 ${selectedCount} 条承运商价格吗？删除后无法恢复。`,
        onClick: async ({ selectedRows }) => {
          await deleteCarrierPriceBatch(selectedRows.map((row) => String(row.id)).filter(Boolean))
          await tableQueryRef.value?.refreshRemove()
        }
      },
      {
        type: 'export',
        exportFilename: 'TMS承运商价格维护',
        exportSheetName: '承运商价格维护',
        exportColumns: createExcelColumns(),
        exportApi: ({ selectedIds, searchParams, maxRows }) =>
          exportCarrierPriceList({
            ...normalizeSearchParams(searchParams as SearchModel),
            ids: selectedIds.map(String),
            maxRows
          })
      }
    ]
  }

  function createColumns(): ColumnOption<CarrierPrice>[] {
    return [
      { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
      { prop: 'originRegion', label: '始发地', width: 170 },
      { prop: 'destinationRegion', label: '目的地', width: 170 },
      {
        prop: 'transportMode',
        label: '运输方式',
        width: 110,
        dict: { code: 'tmsCarrierPriceTransportMode', display: 'text' }
      },
      {
        prop: 'carrierName',
        label: '承运商',
        width: 190,
        formatter: (row) => row.carrier?.companyName || '-'
      },
      { prop: 'driverName', label: '司机', width: 110 },
      { prop: 'driverPhone', label: '手机号码', width: 130 },
      { prop: 'plateNo', label: '车牌号', width: 120 },
      {
        prop: 'vehicleType',
        label: '车型',
        width: 110,
        dict: { code: 'tmsCustomerPriceVehicleType', display: 'text' }
      },
      {
        prop: 'vehicleLength',
        label: '车长',
        width: 110,
        dict: { code: 'tmsCustomerPriceVehicleLength', display: 'text' }
      },
      {
        prop: 'billingMethod',
        label: '计费方式',
        width: 130,
        dict: { code: 'tmsCustomerPriceBillingMethod', display: 'text' }
      },
      {
        prop: 'totalFee',
        label: '运费合计（元）',
        width: 130,
        align: 'right',
        formatter: (row) => formatMoney(row.totalFee)
      },
      { prop: 'createBy', label: '创建人', width: 120 },
      {
        prop: 'createTime',
        label: '创建时间',
        width: 170,
        formatter: (row) => formatDateTime(row.createTime)
      },
      {
        prop: 'operation',
        label: '操作',
        width: 120,
        fixed: 'right',
        formatter: (row) => (
          <div>
            <ArtButtonTable type="edit" onClick={() => openEditPage(row)} />
            <ArtButtonTable type="delete" onClick={() => handleDelete(row)} />
          </div>
        )
      }
    ]
  }

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchCarrierPriceList({
      ...normalizeSearchParams(params),
      from,
      to
    })
  }

  function normalizeSearchParams(params: SearchModel): SearchParams {
    const { originRegionPath, destinationRegionPath, ...rest } = params
    return {
      ...rest,
      originRegion: joinRegionPath(originRegionPath),
      destinationRegion: joinRegionPath(destinationRegionPath)
    }
  }

  function joinRegionPath(regionPath?: string[]): string | undefined {
    const text = regionPath?.filter(Boolean).join('/')
    return text || undefined
  }

  function openEditPage(row?: CarrierPrice): void {
    if (row?.id) {
      void router.push({ name: 'TmsCarrierPriceEdit', params: { id: row.id } })
      return
    }
    void router.push({ name: 'TmsCarrierPriceEdit' })
  }

  async function handleDelete(row: CarrierPrice): Promise<void> {
    if (!row.id) return
    try {
      await confirmAction(
        `确定删除「${row.carrier?.companyName || '承运商价格'}」这条价格吗？`,
        '删除确认',
        {
          confirmButtonText: '删除',
          cancelButtonText: '取消',
          type: 'warning',
          confirmButtonClass: 'el-button--danger'
        }
      )
      await deleteCarrierPrice(row.id)
      await tableQueryRef.value?.refreshRemove()
    } catch {
      // 用户取消删除时无需提示。
    }
  }

  function formatTransportMode(value: unknown): string {
    return getLabel(table.transportModeOptions, value)
  }

  function formatBillingMethod(value: unknown): string {
    return getLabel(table.billingMethodOptions, value)
  }

  function formatVehicleType(value: unknown): string {
    return getLabel(getDictMap.value.tmsCustomerPriceVehicleType ?? [], value)
  }

  function formatVehicleLength(value: unknown): string {
    return getLabel(getDictMap.value.tmsCustomerPriceVehicleLength ?? [], value)
  }

  function getLabel(options: Api.DataCenter.DictListItem[], value: unknown): string {
    if (!value) return ''
    const text = String(value)
    const item = options.find((option) => option.value === text || option.label === text)
    return item?.label || text
  }

  function formatNumber(value?: number | string | null, precision = 2): string {
    const numberValue = Number(value ?? 0)
    if (Number.isNaN(numberValue)) return '0'
    return numberValue
      .toFixed(precision)
      .replace(/\.0+$/, '')
      .replace(/(\.\d*?)0+$/, '$1')
  }

  function formatMoney(value?: number | string | null): string {
    return formatNumber(value, 2)
  }

  function formatDateTime(value?: string | null): string {
    return value ? (formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') ?? '-') : '-'
  }
</script>
