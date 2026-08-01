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
    <StatementDetailDrawer ref="drawerRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtTableQueryHeaderAction } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { useUserStore } from '@/store/modules/user'
  import { createScaffoldListApi, formatMoney, getStatementRows } from './finance-scaffold-data'
  import type {
    ScaffoldListParams,
    SettlementKind,
    SettlementStatementRecord
  } from './finance-types'
  import StatementDetailDrawer from './statement-detail-drawer.vue'

  defineOptions({ name: 'TmsFinanceStatementList' })

  const props = defineProps<{ kind: SettlementKind }>()
  interface DrawerExpose {
    handleOpen: (row: SettlementStatementRecord) => Promise<void>
  }

  const { getDictMap } = storeToRefs(useUserStore())
  const drawerRef = ref<DrawerExpose>()
  const searchQuery = reactive<ScaffoldListParams>({ keyword: '', status: '' })
  const statusOptions = computed(() => getDictMap.value.tmsSettlementStatus ?? [])

  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '对账状态',
      key: 'status',
      type: 'select',
      props: { options: statusOptions.value, clearable: true }
    },
    {
      label: '关键词',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '对账单号 / 结算对象' }
    }
  ])

  const fetchTableData = createScaffoldListApi(
    getStatementRows(props.kind) as Array<SettlementStatementRecord & Record<string, unknown>>,
    (row) => `${row.statementNo} ${row.counterpartyName}`
  )

  const columnsFactory = (): ColumnOption<SettlementStatementRecord>[] => [
    { type: 'globalIndex', label: '序号', width: 72 },
    { prop: 'statementNo', label: '对账单号', width: 185 },
    { prop: 'counterpartyName', label: '结算对象', minWidth: 210, showOverflowTooltip: true },
    { prop: 'period', label: '账期', width: 100 },
    {
      prop: 'waybillCount',
      label: '运单数',
      width: 90,
      formatter: (row) => `${row.waybillCount} 单`
    },
    {
      prop: 'statementAmount',
      label: '对账金额',
      width: 140,
      align: 'right',
      formatter: (row) => formatMoney(row.statementAmount)
    },
    {
      prop: 'settledAmount',
      label: '已结金额',
      width: 140,
      align: 'right',
      formatter: (row) => formatMoney(row.settledAmount)
    },
    {
      prop: 'outstandingAmount',
      label: '未结金额',
      width: 140,
      align: 'right',
      formatter: (row) => formatMoney(row.outstandingAmount)
    },
    {
      prop: 'status',
      label: '状态',
      width: 110,
      dict: { code: 'tmsSettlementStatus', display: 'tag' }
    },
    { prop: 'ownerName', label: '负责人', width: 100 },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      fixed: 'right',
      formatter: (row) => (
        <div>
          <ArtButtonTable type="view" onClick={() => void drawerRef.value?.handleOpen(row)} />
          <ArtButtonTable
            type="edit"
            onClick={() => ElMessage.info('下一阶段接入对账调整与审核流程')}
          />
        </div>
      )
    }
  ]

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label: props.kind === 'customer_receivable' ? '生成客户对账单' : '生成承运商对账单',
      onClick: () => {
        ElMessage.info('页面骨架已就绪，下一阶段接入按账期生成对账单')
      }
    }
  ])
</script>
