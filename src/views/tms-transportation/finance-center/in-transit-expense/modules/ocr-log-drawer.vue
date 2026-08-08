<template>
  <ArtDrawer ref="drawerRef">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="search.data"
      :search-items="search.items"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :search-bar-props="{ span: 8, labelWidth: 78, showExpand: false }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import type { ComputedRef } from 'vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryExpose } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchInTransitExpenseOcrRunList } from '@/api/tms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'TmsInTransitExpenseOcrLogDrawer' })

  type OcrRun = Api.Tms.Finance.InTransitExpenseOcrRunRecord
  type SearchParams = Api.Tms.Finance.InTransitExpenseOcrRunSearchParams
  type TableParams = SearchParams & Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface SearchGroup {
    data: SearchParams
    items: ComputedRef<SearchFormItem[]>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const drawerRef = ref<ArtDrawerExpose<Record<string, never>>>()
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const search = reactive<SearchGroup>({
    data: { keyword: '', status: '', createTimeRange: [] },
    items: computed<SearchFormItem[]>(() => [
      {
        label: '运行状态',
        key: 'status',
        type: 'select',
        props: { options: getDictMap.value.aiRunStatus ?? [], clearable: true }
      },
      {
        label: '识别时间',
        key: 'createTimeRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          startPlaceholder: '开始日期',
          endPlaceholder: '结束日期'
        }
      },
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { clearable: true, placeholder: '模型、错误码、错误详情或发起人' }
      }
    ])
  })

  const columnsFactory = (): ColumnOption<OcrRun>[] => [
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'status',
      label: '识别结果',
      width: 110,
      dict: { code: 'aiRunStatus', display: 'tag' }
    },
    { prop: 'model', label: '识别模型', minWidth: 190, showOverflowTooltip: true },
    {
      prop: 'startedAt',
      label: '开始时间',
      width: 170,
      formatter: (row) => formatWithDayjs(row.startedAt, 'YYYY-MM-DD HH:mm:ss')
    },
    {
      prop: 'latencyMs',
      label: '耗时',
      width: 100,
      align: 'right',
      formatter: (row) =>
        row.latencyMs === null || row.latencyMs === undefined ? '--' : `${row.latencyMs} ms`
    },
    { prop: 'errorCode', label: '失败事项', width: 150, formatter: (row) => row.errorCode || '--' },
    {
      prop: 'errorMessage',
      label: '失败详情',
      minWidth: 260,
      showOverflowTooltip: true,
      formatter: (row) => row.errorMessage || (row.status === 'succeeded' ? '识别成功' : '--')
    },
    { prop: 'createBy', label: '发起人', width: 170, showOverflowTooltip: true }
  ]

  function fetchTableData(params: TableParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchInTransitExpenseOcrRunList({ ...params, from, to })
  }

  async function handleOpen(): Promise<void> {
    await drawerRef.value?.handleOpen(
      {},
      {
        title: 'OCR 识别记录',
        subtitle: '统一查询在途费用票据的识别成功、失败事项与错误详情',
        size: 'xl',
        showFooter: false,
        contentHeight: 'calc(100vh - 120px)',
        onOpen: async () => {
          await nextTick()
          await tableQueryRef.value?.getData()
        },
        drawerProps: { appendToBody: true, resizable: true }
      }
    )
  }

  defineExpose({ handleOpen })
</script>
