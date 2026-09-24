<template>
  <ArtPermissionGuard :permission="viewPermission" :resource-name="title">
    <div class="business-workspace-page art-full-height">
      <BusinessWorkspaceHeader
        density="compact"
        :eyebrow="kind === 'inbound' ? 'WAREHOUSE RECEIPTS' : 'ASSET PAYABLES'"
        :title="title"
        :description="description"
        :icon="kind === 'inbound' ? 'ri:inbox-archive-line' : 'ri:bill-line'"
        :tags="[
          { label: kind === 'inbound' ? '仓储管理' : '财务管理', type: 'primary' },
          { label: '收料通知单下推', type: 'info' }
        ]"
      >
        <template #actions><BusinessTableWorkspaceActions :table="tableRef" /></template>
      </BusinessWorkspaceHeader>
      <ArtTableQuery
        ref="tableRef"
        v-model="search"
        :search-items="searchItems"
        :api-fn="fetchPage"
        :columns-factory="columnsFactory"
        :header-actions="headerActions"
        header-actions-placement="workspace"
        :search-bar-props="{ span: 8, labelWidth: 82, showExpand: false }"
        :table-props="{
          rowKey: 'id',
          tableLayout: 'fixed',
          emptyText: `暂无${title}`,
          emptyDescription: '从已确认的收料通知单选择明细下推后，会在这里生成草稿。'
        }"
        focusable
      />
      <ArtDrawer ref="detailRef" :show-footer="false">
        <div v-if="activeDocument" class="receipt-target-detail">
          <div class="receipt-target-detail__summary">
            <div>
              <span>{{ title }}单号</span>
              <strong>{{ activeDocument.documentNo }}</strong>
              <small>来源通知单：{{ activeDocument.source?.documentNo || '—' }}</small>
              <small>项目：{{ activeDocument.project?.projectName || '—' }}</small>
              <small>供应商：{{ activeDocument.supplier?.supplierName || '—' }}</small>
            </div>
            <ElTag :type="activeDocument.status === 'draft' ? 'warning' : 'success'">
              {{ statusLabel(activeDocument.status) }}
            </ElTag>
          </div>
          <ArtTable
            :data="activeLines"
            :columns="lineColumns"
            :pagination="false"
            row-key="id"
            table-layout="fixed"
            scrollbar-always-on
            :max-height="480"
            empty-text="暂无明细"
          />
          <div v-if="kind === 'asset_payable'" class="receipt-target-detail__total">
            应付金额 <strong>{{ formatCurrencyValue(activeDocument.totalAmount) }}</strong>
          </div>
        </div>
      </ArtDrawer>
    </div>
  </ArtPermissionGuard>
</template>

<script setup lang="tsx">
  import { ElTag } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import ArtPermissionGuard from '@/components/core/feedback/art-permission-guard/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { formatCurrencyValue } from '@/utils/ui/format'
  import { useAuth } from '@/hooks/core/useAuth'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useTenantScopeStore } from '@/store/modules/tenantScope'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchScmReceiptTargets,
    fetchScmReceiptTargetLines,
    transitionScmReceiptTarget,
    type ScmReceiptTargetDocument,
    type ScmReceiptTargetKind,
    type ScmReceiptTargetLine,
    type ScmReceiptTargetQuery,
    type ScmReceiptTargetStatus
  } from '@/api/scm-receipt-target'

  defineOptions({ name: 'ScmReceiptTargetWorkspace' })
  const props = defineProps<{
    kind: ScmReceiptTargetKind
    viewPermission: string
    actionPermission: string
  }>()
  const title = computed(() => (props.kind === 'inbound' ? '收料入库' : '资产应付'))
  const description = computed(() =>
    props.kind === 'inbound'
      ? '核对收料明细的仓库、批号与库存数量，确认后写入库存台账和流水。'
      : '核对收料明细与应付金额，审核后形成资产应付记录。'
  )
  const viewPermission = computed(() => props.viewPermission)
  const actionPermission = computed(() => props.actionPermission)
  const { hasAuth } = useAuth()
  const { confirmAction } = useArtFeedback()
  const { isPlatformSuper } = storeToRefs(useUserStore())
  const { effectiveTenantId, tenantOptions } = storeToRefs(useTenantScopeStore())
  const tableRef = ref<ArtTableQueryExpose>()
  const detailRef = ref<ArtDrawerExpose<ScmReceiptTargetDocument>>()
  const activeDocument = ref<ScmReceiptTargetDocument>()
  const activeLines = ref<ScmReceiptTargetLine[]>([])
  const search = ref<ScmReceiptTargetQuery>({ keyword: '' })
  const searchItems = computed<SearchFormItem[]>(() => [
    ...(isPlatformSuper.value && !effectiveTenantId.value
      ? [
          {
            label: '所属租户',
            key: 'tenantId',
            type: 'select' as const,
            props: {
              clearable: true,
              filterable: true,
              options: tenantOptions.value.map((item) => ({
                label: `${item.tenantName}（${item.tenantCode}）`,
                value: item.id
              }))
            }
          }
        ]
      : []),
    {
      label: '单据编号',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: `搜索${title.value}单号` }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        clearable: true,
        options: [
          { label: '草稿', value: 'draft' },
          {
            label: props.kind === 'inbound' ? '已入库' : '已审核',
            value: props.kind === 'inbound' ? 'confirmed' : 'approved'
          }
        ]
      }
    }
  ])
  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      permission: viewPermission.value,
      type: 'export',
      exportFilename: title.value,
      exportSheetName: title.value,
      exportColumns: [
        { key: 'documentNo', title: `${title.value}单号` },
        { key: 'sourceNo', title: '来源通知单' },
        { key: 'projectName', title: '项目名称' },
        { key: 'supplierName', title: '供应商全称' },
        { key: 'statusName', title: '状态' },
        { key: 'totalAmount', title: '金额' },
        { key: 'createdAt', title: '创建时间' }
      ],
      exportData: async () => {
        const { data } = await fetchScmReceiptTargets(props.kind, {
          ...search.value,
          tenantId: effectiveTenantId.value || search.value.tenantId,
          from: 0,
          to: 9999
        })
        return (data ?? []).map((row) => ({
          ...row,
          sourceNo: row.source?.documentNo || '',
          projectName: row.project?.projectName || '',
          supplierName: row.supplier?.supplierName || '',
          statusName: statusLabel(row.status)
        }))
      }
    }
  ])
  function statusLabel(status: ScmReceiptTargetStatus) {
    return status === 'draft' ? '草稿' : status === 'confirmed' ? '已入库' : '已审核'
  }
  function fetchPage(query: ScmReceiptTargetQuery) {
    return fetchScmReceiptTargets(props.kind, {
      ...query,
      tenantId: effectiveTenantId.value || query.tenantId
    })
  }
  async function openDetail(row: ScmReceiptTargetDocument) {
    const { data } = await fetchScmReceiptTargetLines(row.id)
    activeDocument.value = row
    activeLines.value = data ?? []
    await detailRef.value?.handleOpen(row, { title: row.documentNo })
  }
  async function complete(row: ScmReceiptTargetDocument) {
    try {
      const action = props.kind === 'inbound' ? '确认入库' : '审核应付'
      await confirmAction(`确定对“${row.documentNo}”执行${action}吗？`, action, {
        type: 'warning',
        confirmButtonText: action,
        cancelButtonText: '取消'
      })
      await transitionScmReceiptTarget(row.id, props.kind)
      await tableRef.value?.refreshUpdate()
    } catch {
      /* 用户取消或 API 已提示错误。 */
    }
  }
  function columnsFactory(): ColumnOption<ScmReceiptTargetDocument>[] {
    return [
      {
        prop: 'documentNo',
        label: `${title.value}单号`,
        minWidth: 205,
        fixed: 'left',
        formatter: (row) => (
          <button
            type="button"
            class="font-semibold text-[var(--el-color-primary)] hover:underline focus-visible:outline-2"
            onClick={() => void openDetail(row)}
          >
            {row.documentNo}
          </button>
        )
      },
      {
        prop: 'source',
        label: '来源通知单',
        minWidth: 190,
        formatter: (row) => row.source?.documentNo || '—'
      },
      {
        prop: 'project',
        label: '项目名称',
        minWidth: 170,
        formatter: (row) => row.project?.projectName || '—'
      },
      {
        prop: 'supplier',
        label: '供应商全称',
        minWidth: 185,
        formatter: (row) => row.supplier?.supplierName || '—'
      },
      {
        prop: 'status',
        label: '状态',
        width: 110,
        formatter: (row) => (
          <ElTag size="small" type={row.status === 'draft' ? 'warning' : 'success'}>
            {statusLabel(row.status)}
          </ElTag>
        )
      },
      {
        prop: 'totalAmount',
        label: '金额',
        minWidth: 140,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.totalAmount)
      },
      {
        prop: 'createdAt',
        label: '创建时间',
        minWidth: 180,
        formatter: (row) => row.createdAt?.replace('T', ' ').slice(0, 19) || '—'
      },
      {
        prop: 'actions',
        label: '操作',
        width: 170,
        fixed: 'right',
        formatter: (row) => (
          <div class="flex items-center gap-2">
            <ArtButtonTable
              type="view"
              label="查看"
              permission={viewPermission.value}
              onClick={() => void openDetail(row)}
            />
            {row.status === 'draft' && hasAuth(actionPermission.value) ? (
              <ArtButtonTable
                type="sign"
                icon="ri:check-line"
                label={props.kind === 'inbound' ? '确认入库' : '审核应付'}
                permission={actionPermission.value}
                showLabel
                onClick={() => void complete(row)}
              />
            ) : null}
          </div>
        )
      }
    ]
  }
  const lineColumns: ColumnOption<ScmReceiptTargetLine>[] = [
    {
      prop: 'lineNo',
      label: '行号',
      width: 80,
      formatter: (row) => row.lineSnapshot.lineNo || '—'
    },
    {
      prop: 'materialCode',
      label: '物料编码',
      minWidth: 130,
      formatter: (row) => row.lineSnapshot.materialCode || '—'
    },
    {
      prop: 'materialDescription',
      label: '物料名称',
      minWidth: 190,
      formatter: (row) => row.lineSnapshot.materialDescription || '—'
    },
    {
      prop: 'quantity',
      label: '收料数量',
      minWidth: 105,
      formatter: (row) => row.lineSnapshot.quantity || 0
    },
    {
      prop: 'stockQuantity',
      label: '库存数量',
      minWidth: 105,
      formatter: (row) => row.lineSnapshot.stockQuantity || 0
    },
    {
      prop: 'stockUnit',
      label: '库存单位',
      minWidth: 95,
      formatter: (row) => row.lineSnapshot.stockUnit || '—'
    },
    {
      prop: 'warehouse',
      label: '仓库',
      minWidth: 125,
      formatter: (row) => row.lineSnapshot.warehouse || '—'
    },
    {
      prop: 'batchNo',
      label: '批号',
      minWidth: 155,
      formatter: (row) => row.lineSnapshot.batchNo || '—'
    },
    {
      prop: 'amount',
      label: '价税合计',
      minWidth: 135,
      align: 'right',
      formatter: (row) => formatCurrencyValue(row.amount)
    }
  ]
</script>

<style scoped lang="scss">
  .receipt-target-detail {
    display: grid;
    gap: 16px;
    min-width: 0;
  }

  .receipt-target-detail__summary {
    display: flex;
    gap: 16px;
    align-items: start;
    justify-content: space-between;
    padding: 16px;
    background: var(--el-fill-color-light);
    border-radius: 8px;

    > div {
      display: grid;
      gap: 4px;
      min-width: 0;
    }

    span,
    small {
      color: var(--el-text-color-secondary);
    }

    strong {
      overflow-wrap: anywhere;
    }
  }

  .receipt-target-detail__total {
    justify-self: end;
    color: var(--el-text-color-secondary);

    strong {
      margin-left: 12px;
      color: var(--el-text-color-primary);
    }
  }
</style>
