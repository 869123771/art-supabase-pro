<template>
  <div class="art-full-height">
    <ArtTableQuery
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />
    <WaybillProfitAnalysisDrawer ref="profitAnalysisDrawerRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElTag, ElTooltip } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExcelColumn,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import WaybillProfitAnalysisDrawer from './modules/waybill-profit-analysis-drawer.vue'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'
  import { exportWaybillProfitList, fetchWaybillProfitList } from '@/api/tms'

  defineOptions({ name: 'TmsWaybillProfit' })

  type WaybillProfit = Api.Tms.Finance.WaybillProfitRecord
  type SearchParams = Api.Tms.Finance.WaybillProfitSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface ProfitAnalysisDrawerExpose {
    handleOpen: () => Promise<void>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const profitAnalysisDrawerRef = ref<ProfitAnalysisDrawerExpose>()
  const searchQuery = reactive<SearchParams>({
    keyword: '',
    waybillStatus: '',
    completedAtRange: []
  })

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '运单状态',
      key: 'waybillStatus',
      type: 'select',
      props: {
        options: getDictMap.value.tmsWaybillStatus ?? [],
        clearable: true
      }
    },
    {
      label: '完成日期',
      key: 'completedAtRange',
      type: 'date',
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        rangeSeparator: '至',
        class: '!w-full'
      }
    },
    {
      label: '关键词',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder: '运单号、客户、承运商、车辆或司机'
      }
    }
  ])

  const formatMoney = (value?: number | null): string =>
    `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`

  const columnsFactory = (): ColumnOption<WaybillProfit>[] => [
    { type: 'selection', width: 50, fixed: 'left', reserveSelection: true },
    { type: 'globalIndex', label: '序号', width: 72 },
    { prop: 'waybillNo', label: '运单号', width: 175 },
    {
      prop: 'route',
      label: '运输路线',
      minWidth: 185,
      showOverflowTooltip: true,
      formatter: (row) =>
        [row.originStation, row.destinationStation].filter(Boolean).join(' → ') || '-'
    },
    {
      prop: 'customerName',
      label: '客户',
      minWidth: 170,
      showOverflowTooltip: true,
      formatter: (row) => row.customerName || '未关联客户'
    },
    {
      prop: 'carrierName',
      label: '承运商 / 车辆',
      minWidth: 170,
      showOverflowTooltip: true,
      formatter: (row) => row.carrierName || row.plateNo || '未关联承运商'
    },
    {
      prop: 'waybillStatus',
      label: '运单状态',
      width: 110,
      dict: { code: 'tmsWaybillStatus', display: 'tag' }
    },
    {
      prop: 'receivableAmount',
      label: '订单应收',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.receivableAmount)
    },
    {
      prop: 'carrierPayableAmount',
      label: '承运运费',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.carrierPayableAmount)
    },
    {
      prop: 'otherCostAmount',
      label: '附加成本',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.otherCostAmount)
    },
    {
      prop: 'totalCostAmount',
      label: '成本状态',
      width: 110,
      align: 'center',
      formatter: (row) =>
        row.totalCostAmount > 0 ? (
          <ElTooltip content={`已审核成本 ${formatMoney(row.totalCostAmount)}`} placement="top">
            <ElTag type="success">已核成本</ElTag>
          </ElTooltip>
        ) : (
          <ElTooltip content="尚无审核通过的费用，当前利润仅供参考" placement="top">
            <ElTag type="warning">未核成本</ElTag>
          </ElTooltip>
        )
    },
    {
      prop: 'grossProfit',
      label: '毛利额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.grossProfit)
    },
    {
      prop: 'grossMargin',
      label: '毛利率',
      width: 105,
      align: 'right',
      formatter: (row) => {
        if (row.totalCostAmount <= 0) return <ElTag type="warning">待核算</ElTag>
        const type = row.grossMargin < 15 ? 'danger' : row.grossMargin < 25 ? 'warning' : 'success'
        return <ElTag type={type}>{Number(row.grossMargin).toFixed(2)}%</ElTag>
      }
    },
    {
      prop: 'completedAt',
      label: '完成时间',
      width: 165,
      formatter: (row) =>
        row.completedAt ? formatWithDayjs(row.completedAt, 'YYYY-MM-DD HH:mm') : '-'
    }
  ]

  const excelColumns: ArtTableQueryExcelColumn[] = [
    { key: 'waybillNo', title: '运单号' },
    { key: 'originStation', title: '起始站' },
    { key: 'destinationStation', title: '目的站' },
    { key: 'customerName', title: '客户' },
    { key: 'carrierName', title: '承运商' },
    { key: 'plateNo', title: '车牌号' },
    { key: 'waybillStatus', title: '运单状态' },
    { key: 'receivableAmount', title: '订单应收' },
    { key: 'carrierPayableAmount', title: '承运运费' },
    { key: 'otherCostAmount', title: '附加成本' },
    { key: 'totalCostAmount', title: '总成本' },
    { key: 'grossProfit', title: '毛利额' },
    { key: 'grossMargin', title: '毛利率(%)' },
    { key: 'completedAt', title: '完成时间' }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      key: 'ai-profit-analysis',
      label: 'AI 利润诊断',
      icon: 'ri:sparkling-2-line',
      buttonProps: { type: 'primary' },
      onClick: () => void profitAnalysisDrawerRef.value?.handleOpen()
    },
    {
      type: 'export',
      label: '导出利润明细',
      exportFilename: 'TMS运单利润明细',
      exportSheetName: '运单利润',
      exportColumns: excelColumns,
      exportApi: ({ selectedIds, searchParams, maxRows }) =>
        exportWaybillProfitList({
          ...(searchParams as SearchParams),
          ids: selectedIds.map(String),
          maxRows
        })
    }
  ])

  const fetchTableData = (params: TableParams) => {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchWaybillProfitList({ ...params, from, to })
  }
</script>
