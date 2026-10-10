<template>
  <ArtPermissionGuard :permission="viewPermission" :resource-name="title">
    <div class="business-workspace-page art-full-height min-w-0">
      <BusinessWorkspaceHeader
        :title="title"
        eyebrow="PURCHASE PAYABLES"
        description="由已审核采购入库明细生成应付草稿，保留入库来源、项目和金额。"
        icon="ri:bill-line"
        density="compact"
      >
        <template #actions><BusinessTableWorkspaceActions :table="tableRef" /></template>
      </BusinessWorkspaceHeader>
      <ArtTableQuery
        ref="tableRef"
        v-model="search"
        :api-fn="fetchRows"
        :search-items="searchItems"
        :columns-factory="columnsFactory"
        :table-props="{
          rowKey: 'id',
          emptyText: '暂无应付单',
          emptyDescription: '在采购入库单勾选已审核单据或明细，通过下推生成。'
        }"
        focusable
      />
      <ArtDrawer ref="drawerRef" size="xl" :show-footer="false">
        <template v-if="current">
          <ArtEntitySummary
            icon="ri:bill-line"
            :title="current.documentNo"
            :description="`来源采购入库单：${current.sourceDocumentNo}`"
          />
          <ArtDescriptions class="mt-4" :data="current" :items="descriptionItems" />
          <ArtSectionCard class="mt-4" title="应付明细" :subtitle="`共 ${current.lines.length} 行`">
            <ArtTable
              :data="current.lines"
              :columns="lineColumns"
              :pagination="false"
              row-key="id"
            />
          </ArtSectionCard>
        </template>
      </ArtDrawer>
    </div>
  </ArtPermissionGuard>
</template>
<script setup lang="tsx">
  import {
    fetchPurchasePayables,
    type PurchasePayableDocument,
    type PurchasePayableKind,
    type PurchasePayableLine
  } from '@/api/purchase-payable'
  import ArtTableQuery from '@/components/core/tables/art-table-query/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import ArtSectionCard from '@/components/core/surfaces/art-section-card/index.vue'
  import ArtEntitySummary from '@/components/core/surfaces/art-entity-summary/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessTableRowActions from '@/components/business/business-table-row-actions/index.vue'
  import type { ColumnOption } from '@/types'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import { formatCurrencyValue } from '@/utils/ui/format'
  const props = defineProps<{ kind: PurchasePayableKind; viewPermission: string }>()
  const route = useRoute()
  const title = computed(() => (props.kind === 'estimated' ? '暂估应付单' : '财务应付单'))
  const tableRef = ref<InstanceType<typeof ArtTableQuery>>()
  const drawerRef = ref<ArtDrawerExpose>()
  const current = ref<PurchasePayableDocument>()
  const search = reactive({ keyword: '' })
  const searchItems: SearchFormItem[] = [
    {
      key: 'keyword',
      label: '组合查询',
      type: 'input',
      props: { placeholder: '应付单号、来源入库单号', clearable: true }
    }
  ]
  function fetchRows(query: { current: number; size: number; keyword?: string }) {
    return fetchPurchasePayables(props.kind, {
      ...query,
      id: typeof route.query.recordId === 'string' ? route.query.recordId : undefined
    })
  }
  function open(row: PurchasePayableDocument): void {
    current.value = row
    drawerRef.value?.handleOpen(undefined, { title: `${title.value}详情`, showFooter: false })
  }
  const columnsFactory = (): ColumnOption<PurchasePayableDocument>[] => [
    { prop: 'documentNo', label: '应付单号', minWidth: 200 },
    { prop: 'sourceDocumentNo', label: '来源入库单', minWidth: 190 },
    { prop: 'businessDate', label: '业务日期', width: 120 },
    { prop: 'supplierName', label: '供应商全称', minWidth: 180 },
    { prop: 'status', label: '状态', width: 100, formatter: () => '暂存' },
    {
      prop: 'amount',
      label: '金额(元)',
      minWidth: 130,
      align: 'right',
      formatter: (row) => formatCurrencyValue(row.amount)
    },
    {
      prop: 'taxAmount',
      label: '税额(元)',
      minWidth: 120,
      align: 'right',
      formatter: (row) => formatCurrencyValue(row.taxAmount)
    },
    {
      prop: 'totalAmount',
      label: '价税合计(元)',
      minWidth: 150,
      align: 'right',
      formatter: (row) => formatCurrencyValue(row.totalAmount)
    },
    {
      prop: 'operation',
      label: '操作',
      width: 90,
      fixed: 'right',
      formatter: (row) => (
        <BusinessTableRowActions>
          <ArtButtonTable
            type="view"
            permission={props.viewPermission}
            label="查看"
            onClick={() => open(row)}
          />
        </BusinessTableRowActions>
      )
    }
  ]
  const descriptionItems: ArtDescriptionItem<PurchasePayableDocument>[] = [
    { key: 'sourceDocumentNo', label: '来源入库单', field: 'sourceDocumentNo' },
    { key: 'supplierName', label: '供应商', field: 'supplierName' },
    { key: 'businessDate', label: '业务日期', field: 'businessDate' },
    {
      key: 'totalAmount',
      label: '价税合计',
      field: 'totalAmount',
      formatter: (value) => formatCurrencyValue(Number(value))
    }
  ]
  const lineColumns: ColumnOption<PurchasePayableLine>[] = [
    { prop: 'lineNo', label: '源行号', width: 80 },
    { prop: 'materialCode', label: '物料编码', minWidth: 140 },
    { prop: 'materialDescription', label: '物料描述', minWidth: 190 },
    { prop: 'projectName', label: '项目名称', minWidth: 160 },
    { prop: 'constructionNo', label: '施工号', width: 140 },
    { prop: 'unitName', label: '单位', width: 90 },
    { prop: 'quantity', label: '数量', width: 120 },
    {
      prop: 'unitPrice',
      label: '单价(元)',
      width: 130,
      formatter: (row) => formatCurrencyValue(row.unitPrice)
    },
    {
      prop: 'amount',
      label: '金额(元)',
      width: 130,
      formatter: (row) => formatCurrencyValue(row.amount)
    },
    {
      prop: 'taxAmount',
      label: '税额(元)',
      width: 120,
      formatter: (row) => formatCurrencyValue(row.taxAmount)
    },
    {
      prop: 'totalAmount',
      label: '价税合计(元)',
      width: 150,
      formatter: (row) => formatCurrencyValue(row.totalAmount)
    }
  ]
</script>
