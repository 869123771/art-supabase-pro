<template>
  <ArtPermissionGuard :permission="permission.View" :resource-name="title">
    <div class="business-workspace-page art-full-height min-w-0">
      <BusinessWorkspaceHeader
        class="wms-initialization-header"
        :eyebrow="isInitial ? 'OPENING PURCHASE DOCUMENT' : 'INBOUND INVENTORY DOCUMENT'"
        :title="title"
        :description="description"
        :icon="isReturn ? 'ri:inbox-unarchive-line' : 'ri:inbox-archive-line'"
        density="compact"
        :tags="[
          { label: isInitial ? '初始化单据' : businessTag, type: 'primary' },
          { label: '税价联动', type: 'success' },
          { label: '物料与项目', type: 'info' }
        ]"
      >
        <template #actions><BusinessTableWorkspaceActions :table="tableRef" /></template>
      </BusinessWorkspaceHeader>
      <ArtTableQuery
        ref="tableRef"
        v-model="search"
        :api-fn="fetchRows"
        :search-items="searchItems"
        :columns-factory="columnsFactory"
        :header-actions="headerActions"
        header-actions-placement="workspace"
        :search-bar-props="{ span: 5, labelWidth: 76 }"
        :table-props="{
          rowKey: 'lineId',
          tableLayout: 'fixed',
          cellClassName: purchaseCellClassName,
          emptyText: `当前范围暂无${title}`,
          emptyDescription: '新建单据并选择物料，填写数量、价格与仓储信息。'
        }"
        focusable
        @selection-change="onSelectionChange"
      />
      <WmsPurchaseDocumentDrawer
        ref="drawerRef"
        :kind="kind"
        :permission-prefix="permission.View.split(':')[0]"
        :import-permission="permission.Import"
        @success="refresh"
      />
      <WmsPurchaseDocumentDrawer
        v-if="kind === 'other_inbound'"
        ref="returnDrawerRef"
        kind="other_return"
        :permission-prefix="permission.View.split(':')[0]"
        :import-permission="permission.Import"
        @success="refresh"
      />
      <WmsPurchaseDocumentDrawer
        v-if="isEntrustedProcessing"
        ref="entrustedTargetDrawerRef"
        :kind="entrustedTargetKind"
        :permission-prefix="permission.View.split(':')[0]"
        :import-permission="permission.Import"
        @success="refresh"
      />
      <ArtDialog ref="orderTargetDialogRef" size="md" :show-footer="false">
        <ArtEntitySummary
          icon="ri:link-m"
          :eyebrow="kind === 'other_inbound' ? 'SOURCE DOCUMENT' : 'PURCHASE ORDER'"
          :title="kind === 'other_inbound' ? '选择来源单据' : '承接采购订单'"
          :description="
            kind === 'other_inbound'
              ? '选择已下推的来源单据明细，生成其他入库草稿。'
              : '选择 SCM 已下推的订单明细，生成可分批办理的采购入库草稿。'
          "
        />
        <div v-if="orderTargets.length" class="mt-5 flex flex-col gap-4 sm:flex-row sm:items-end">
          <div class="min-w-0 flex-1">
            <label class="mb-2 block text-sm font-medium" for="wms-purchase-order-target"
              >订单下推单</label
            >
            <ElSelect
              id="wms-purchase-order-target"
              v-model="selectedOrderTargetId"
              class="w-full"
              filterable
              placeholder="选择订单下推单"
            >
              <ElOption
                v-for="target in orderTargets"
                :key="target.id"
                :label="`${target.documentNo} · ${target.source?.documentNo || '采购订单'} · ${target.status === 'partial' ? '部分入库' : '待入库'}`"
                :value="target.id"
              />
            </ElSelect>
          </div>
          <ElButton
            type="primary"
            :disabled="!selectedOrderTargetId"
            @click="openSelectedOrderTarget"
          >
            {{ kind === 'other_inbound' ? '生成入库草稿' : '承接订单' }}
          </ElButton>
        </div>
        <ArtEmptyState
          v-else
          class="mt-5"
          size="compact"
          title="暂无订单下推单"
          description="请先在 SCM 采购订单中审核并下推采购入库。"
        />
      </ArtDialog>
      <ArtDialog ref="pushDialogRef" size="sm" :show-footer="false">
        <ArtEntitySummary
          icon="ri:file-transfer-line"
          eyebrow="DOCUMENT PUSH"
          :title="
            isEntrustedProcessing
              ? '下推受托加工后续业务'
              : isReturn
                ? '下推采购退货业务'
                : '下推采购入库业务'
          "
          :description="
            isEntrustedProcessing
              ? '勾选一张已审核单据，生成对应的受托收料或退料草稿。'
              : '选择后续业务目标。目标模块接入后将按当前已审核单据生成关联草稿。'
          "
        />
        <div v-if="isEntrustedProcessing" class="mt-5">
          <ElButton type="primary" class="w-full!" @click="pushEntrustedCounterpart">
            {{ kind === 'entrusted_processing_inbound' ? '受托退料' : '受托收料' }}
          </ElButton>
        </div>
        <div v-else class="mt-5 grid gap-3 sm:grid-cols-2">
          <ElButton disabled class="w-full!">{{
            isReturn ? '暂估应付冲销' : '暂估应付单'
          }}</ElButton>
          <ElButton disabled class="w-full!">{{ isReturn ? '其他出库单' : '到货确认单' }}</ElButton>
        </div>
      </ArtDialog>
    </div>
  </ArtPermissionGuard>
</template>

<script setup lang="tsx">
  import { ElMessage, ElTag } from 'element-plus'
  import { useRoute, useRouter } from 'vue-router'
  import { useAuth } from '@/hooks/core/useAuth'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import ArtPermissionGuard from '@/components/core/feedback/art-permission-guard/index.vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtEntitySummary from '@/components/core/surfaces/art-entity-summary/index.vue'
  import ArtEmptyState from '@/components/core/feedback/art-empty-state/index.vue'
  import ArtTableQuery, {
    type ArtTableQueryExpose,
    type ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessTableIdentityCell from '@/components/business/business-table-identity-cell/index.vue'
  import BusinessTableRowActions from '@/components/business/business-table-row-actions/index.vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ColumnOption } from '@/types'
  import { useTenantScopeStore } from '@/store/modules/tenantScope'
  import { useUserStore } from '@/store/modules/user'
  import {
    changeWmsPurchaseStatus,
    fetchWmsPurchasePage,
    fetchWmsPurchaseOrderTargets,
    type WmsPurchaseKind,
    type WmsPurchaseListRow
  } from '@/api/wms-purchase'
  import WmsPurchaseDocumentDrawer from './modules/wms-purchase-document-drawer.vue'

  type PurchaseAction =
    | 'View'
    | 'Add'
    | 'Copy'
    | 'Edit'
    | 'Delete'
    | 'Import'
    | 'Export'
    | 'Push'
    | 'Submit'
    | 'Approve'

  const props = defineProps<{
    kind: WmsPurchaseKind
    permissions: Record<PurchaseAction, string>
  }>()
  const { confirmAction } = useArtFeedback()
  const { hasAuth } = useAuth()
  const route = useRoute()
  const router = useRouter()
  const { effectiveTenantId } = storeToRefs(useTenantScopeStore())
  const userStore = useUserStore()
  void userStore.ensureDictLoaded('wmsInitialStockType')
  void userStore.ensureDictLoaded('wmsInitialStockCondition')
  const tableRef = ref<ArtTableQueryExpose>()
  const drawerRef = ref<InstanceType<typeof WmsPurchaseDocumentDrawer>>()
  const returnDrawerRef = ref<InstanceType<typeof WmsPurchaseDocumentDrawer>>()
  const entrustedTargetDrawerRef = ref<InstanceType<typeof WmsPurchaseDocumentDrawer>>()
  const pushDialogRef = ref<ArtDialogExpose>()
  const orderTargetDialogRef = ref<ArtDialogExpose>()
  const orderTargets = ref<Awaited<ReturnType<typeof fetchWmsPurchaseOrderTargets>>>([])
  const selectedOrderTargetId = ref('')
  const workingId = ref<string>()
  const selectedRows = ref<WmsPurchaseListRow[]>([])
  const returnKinds: WmsPurchaseKind[] = [
    'initial_return',
    'purchase_return',
    'other_return',
    'entrusted_processing_return'
  ]
  const isReturn = computed(() => returnKinds.includes(props.kind))
  const isInitial = computed(() => props.kind.startsWith('initial_'))
  const isEntrustedProcessing = computed(() => props.kind.startsWith('entrusted_processing_'))
  const entrustedTargetKind = computed<WmsPurchaseKind>(() =>
    props.kind === 'entrusted_processing_inbound'
      ? 'entrusted_processing_return'
      : 'entrusted_processing_inbound'
  )
  const businessTag = computed(() =>
    props.kind.startsWith('entrusted_processing_') ? '受托加工' : '入库业务'
  )
  const title = computed(
    () =>
      ({
        initial_inbound: '期初采购入库单',
        initial_return: '期初采购退料单',
        purchase_inbound: '采购入库单',
        purchase_return: '采购退货单',
        other_inbound: '其他入库单',
        other_return: '其他入库退回单',
        entrusted_processing_inbound: '受托加工材料入库单',
        entrusted_processing_return: '受托加工材料退料单'
      })[props.kind]
  )
  const description = computed(() =>
    isReturn.value
      ? `${isInitial.value ? '登记库存初始化前' : '登记入库业务过程'}的退料，数量以负数醒目标识，税价与折扣自动核算。`
      : `${isInitial.value ? '登记库存初始化前' : '登记日常'}的入库业务，支持供应商、项目与物料组合查询。`
  )
  const permission = computed(() => props.permissions)
  const search = reactive({
    status: '',
    supplier: '',
    projectName: '',
    materialDescription: '',
    materialCode: ''
  })
  const searchItems = computed<SearchFormItem[]>(() => [
    {
      label: '单据状态',
      key: 'status',
      type: 'select',
      props: {
        clearable: true,
        placeholder: '全部状态',
        options: [
          { label: '暂存', value: 'draft' },
          { label: '已提交', value: 'submitted' },
          { label: '已审核', value: 'approved' }
        ]
      }
    },
    {
      label: isEntrustedProcessing.value ? '客户全称' : '供应商',
      key: 'supplier',
      type: 'input',
      props: {
        clearable: true,
        placeholder: isEntrustedProcessing.value ? '客户名称' : '供应商名称'
      }
    },
    {
      label: '项目名称',
      key: 'projectName',
      type: 'input',
      props: { clearable: true, placeholder: '项目名称' }
    },
    {
      label: '物料描述',
      key: 'materialDescription',
      type: 'input',
      props: { clearable: true, placeholder: '物料描述' }
    },
    {
      label: '物料编码',
      key: 'materialCode',
      type: 'input',
      props: { clearable: true, placeholder: '物料编码' }
    }
  ])
  function fetchRows(query: {
    status?: string
    supplier?: string
    projectName?: string
    materialDescription?: string
    materialCode?: string
    current: number
    size: number
  }) {
    return fetchWmsPurchasePage({
      ...query,
      kind: props.kind,
      tenantId: effectiveTenantId.value || undefined
    })
  }
  async function refresh(): Promise<void> {
    await tableRef.value?.refreshUpdate()
  }
  function purchaseCellClassName({
    row,
    column
  }: {
    row: Record<string, unknown>
    column: { property?: string }
  }): string {
    return column.property === 'quantity' && returnKinds.includes(row.kind as WmsPurchaseKind)
      ? 'wms-purchase-negative-cell'
      : ''
  }
  function onSelectionChange(rows: Record<string, unknown>[]): void {
    selectedRows.value = rows as unknown as WmsPurchaseListRow[]
  }
  async function openDocument(mode: 'view' | 'edit' | 'copy', documentId: string): Promise<void> {
    try {
      await drawerRef.value?.handleOpen({ mode, documentId })
    } catch {
      ElMessage.error('单据加载失败，请重试')
    }
  }
  async function openOrderTarget(targetId: string): Promise<boolean> {
    try {
      await drawerRef.value?.handleOpen({ mode: 'create', orderTargetId: targetId })
      return true
    } catch {
      ElMessage.error('订单下推单无法承接，请核对未入库数量、物料与单位配置')
      return false
    }
  }
  async function openOrderTargetPicker(): Promise<void> {
    try {
      orderTargets.value = await fetchWmsPurchaseOrderTargets(effectiveTenantId.value || undefined)
      selectedOrderTargetId.value = ''
      await orderTargetDialogRef.value?.handleOpen(undefined, {
        title: props.kind === 'other_inbound' ? '选择来源单据' : '承接采购订单'
      })
    } catch {
      ElMessage.error('订单下推单加载失败，请重试')
    }
  }
  async function openSelectedOrderTarget(): Promise<void> {
    if (!selectedOrderTargetId.value) return
    const targetId = selectedOrderTargetId.value
    await orderTargetDialogRef.value?.handleClose()
    await openOrderTarget(targetId)
  }
  async function pushOtherInboundReturn(): Promise<void> {
    const documents = new Map(selectedRows.value.map((row) => [row.documentId, row]))
    if (documents.size !== 1) {
      ElMessage.warning('请先勾选一张已审核的其他入库单')
      return
    }
    const source = [...documents.values()][0]
    if (source.status !== 'approved' || source.kind !== 'other_inbound') {
      ElMessage.warning('仅支持下推已审核的其他入库单')
      return
    }
    try {
      await returnDrawerRef.value?.handleOpen({ mode: 'copy', documentId: source.documentId })
    } catch {
      ElMessage.error('入库退回草稿生成失败，请重试')
    }
  }
  async function pushEntrustedCounterpart(): Promise<void> {
    const documents = new Map(selectedRows.value.map((row) => [row.documentId, row]))
    if (documents.size !== 1) {
      ElMessage.warning(`请先勾选一张已审核的${title.value}`)
      return
    }
    const source = [...documents.values()][0]
    if (source.status !== 'approved' || source.kind !== props.kind) {
      ElMessage.warning(`仅支持下推已审核的${title.value}`)
      return
    }
    try {
      await pushDialogRef.value?.handleClose()
      await entrustedTargetDrawerRef.value?.handleOpen({
        mode: 'copy',
        documentId: source.documentId
      })
    } catch {
      ElMessage.error('受托加工后续业务草稿生成失败，请重试')
    }
  }
  onMounted(async () => {
    const targetId = route.query.targetId
    if (
      !['purchase_inbound', 'other_inbound'].includes(props.kind) ||
      typeof targetId !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(targetId) ||
      !hasAuth(permission.value.Add)
    )
      return
    if (await openOrderTarget(targetId)) {
      await router.replace({ path: route.path, query: { ...route.query, targetId: undefined } })
    }
  })
  async function transition(
    row: WmsPurchaseListRow,
    action: 'submit' | 'approve' | 'delete'
  ): Promise<void> {
    if (workingId.value) return
    const label = { submit: '提交', approve: '审核', delete: '删除' }[action]
    try {
      await confirmAction(`确定${label} ${row.documentNo}？`, `${label}${title.value}`, {
        type: action === 'delete' ? 'warning' : 'info',
        confirmButtonText: `确定${label}`
      })
      workingId.value = row.documentId
      await changeWmsPurchaseStatus(row.documentId, action)
      await refresh()
    } catch {
      /* 取消和接口错误由组件处理。 */
    } finally {
      workingId.value = undefined
    }
  }
  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    ...(['purchase_inbound', 'other_inbound'].includes(props.kind)
      ? [
          {
            key: 'receive-order',
            label: props.kind === 'other_inbound' ? '选单' : '承接订单',
            icon: 'ri:link-m',
            permission: permission.value.Add,
            buttonProps: { type: 'primary' as const, plain: true },
            onClick: openOrderTargetPicker
          }
        ]
      : []),
    {
      type: 'add',
      label: `新增${title.value}`,
      permission: permission.value.Add,
      buttonProps: { plain: false },
      onClick: () => drawerRef.value?.handleOpen({ mode: 'create' })
    },
    {
      key: 'import',
      label: '导入',
      icon: 'ri:file-upload-line',
      permission: permission.value.Import,
      buttonProps: { type: 'success', plain: true },
      onClick: () => drawerRef.value?.handleOpen({ mode: 'create', importIntent: true })
    },
    {
      type: 'export',
      label: '导出当前范围',
      permission: permission.value.Export,
      buttonProps: { type: 'warning', plain: true },
      exportFilename: title.value,
      exportData: async () => (await fetchRows({ ...search, current: 1, size: 5000 })).data,
      exportColumns: [
        { title: '单据编号', key: 'documentNo' },
        { title: '业务日期', key: 'businessDate' },
        { title: '单据状态', key: 'status' },
        {
          title: isEntrustedProcessing.value ? '客户全称' : '供应商',
          key: isEntrustedProcessing.value ? 'customerName' : 'supplierName'
        },
        { title: '项目名称', key: 'projectName' },
        { title: '物料编码', key: 'materialCode' },
        { title: '物料描述', key: 'materialDescription' },
        { title: '规格型号', key: 'specificationModel' },
        { title: '库存单位', key: 'inventoryUnitName' },
        { title: '数量', key: 'quantity' },
        { title: '单价(元)', key: 'unitPrice' },
        { title: '含税单价(元)', key: 'taxInclusiveUnitPrice' },
        { title: '税率(%)', key: 'taxRate' },
        { title: '金额(元)', key: 'amount' },
        { title: '税额(元)', key: 'taxAmount' },
        { title: '价税合计(元)', key: 'totalAmount' },
        ...(isEntrustedProcessing.value
          ? [
              { title: '已收料数量', key: 'receivedQuantity' },
              { title: '未收料数量', key: 'unreceivedQuantity' },
              { title: '已退库数量', key: 'returnedQuantity' },
              { title: '未退库数量', key: 'unreturnedQuantity' }
            ]
          : [])
      ]
    },
    {
      key: 'push',
      label: '下推',
      icon: 'ri:file-transfer-line',
      permission: permission.value.Push,
      buttonProps: { type: 'info', plain: true },
      onClick: () =>
        props.kind === 'other_inbound'
          ? pushOtherInboundReturn()
          : pushDialogRef.value?.handleOpen(undefined, { title: '下推业务' })
    }
  ])
  function statusLabel(value: WmsPurchaseListRow['status']): string {
    return { draft: '暂存', submitted: '已提交', approved: '已审核' }[value]
  }
  function dictionaryLabel(code: string, value: string): string {
    return userStore.getDictMap[code]?.find((item) => item.value === value)?.label || value
  }
  function moreActions(row: WmsPurchaseListRow): ButtonMoreItem[] {
    return [
      { key: 'copy', label: '复制单据', icon: 'ri:file-copy-line', auth: permission.value.Copy },
      ...(row.status === 'draft'
        ? [
            { key: 'edit', label: '编辑单据', icon: 'ri:edit-line', auth: permission.value.Edit },
            {
              key: 'submit',
              label: '提交单据',
              icon: 'ri:send-plane-line',
              auth: permission.value.Submit
            },
            {
              key: 'delete',
              label: '删除单据',
              icon: 'ri:delete-bin-line',
              auth: permission.value.Delete,
              color: 'var(--el-color-danger)'
            }
          ]
        : []),
      ...(row.status === 'submitted'
        ? [
            {
              key: 'approve',
              label: '审核单据',
              icon: 'ri:checkbox-circle-line',
              auth: permission.value.Approve
            }
          ]
        : [])
    ]
  }
  function onMoreAction(item: ButtonMoreItem, row: WmsPurchaseListRow): void {
    if (item.key === 'copy' || item.key === 'edit') {
      void openDocument(item.key, row.documentId)
    } else if (item.key === 'submit' || item.key === 'approve' || item.key === 'delete') {
      void transition(row, item.key)
    }
  }
  function columnsFactory(): ColumnOption<WmsPurchaseListRow>[] {
    return [
      ...(props.kind === 'other_inbound' || isEntrustedProcessing.value
        ? [{ type: 'selection' as const, width: 48, fixed: 'left' as const }]
        : []),
      {
        prop: 'documentNo',
        label: '单据编号',
        fixed: 'left',
        minWidth: 180,
        formatter: (row) => (
          <BusinessTableIdentityCell
            primary={row.documentNo}
            secondary={`第 ${row.lineNo} 行 · ${isEntrustedProcessing.value ? row.customerName : row.supplierName}`}
            icon={isReturn.value ? 'ri:inbox-unarchive-line' : 'ri:inbox-archive-line'}
          />
        )
      },
      { prop: 'businessDate', label: '业务日期', minWidth: 118 },
      {
        prop: 'status',
        label: '单据状态',
        width: 98,
        formatter: (row) => (
          <ElTag
            size="small"
            type={
              row.status === 'approved'
                ? 'success'
                : row.status === 'submitted'
                  ? 'warning'
                  : 'info'
            }
          >
            {statusLabel(row.status)}
          </ElTag>
        )
      },
      {
        prop: isEntrustedProcessing.value ? 'customerName' : 'supplierName',
        label: isEntrustedProcessing.value ? '客户全称' : '供应商',
        minWidth: 190,
        showOverflowTooltip: true
      },
      { prop: 'projectName', label: '项目名称', minWidth: 165, showOverflowTooltip: true },
      { prop: 'materialCode', label: '物料编码', minWidth: 125 },
      { prop: 'materialDescription', label: '物料描述', minWidth: 175, showOverflowTooltip: true },
      { prop: 'specificationModel', label: '规格型号', minWidth: 130 },
      { prop: 'inventoryUnitName', label: '库存单位', width: 98 },
      {
        prop: 'quantity',
        label: '数量',
        fixed: 'right',
        minWidth: 115,
        align: 'right',
        formatter: (row) => (
          <span
            class={
              returnKinds.includes(row.kind)
                ? 'wms-purchase-negative'
                : 'font-semibold tabular-nums'
            }
          >
            {Number(row.quantity).toFixed(4)}
          </span>
        )
      },
      ...(isEntrustedProcessing.value
        ? [
            {
              prop: 'receivedQuantity',
              label: '已收料数量',
              minWidth: 116,
              align: 'right' as const
            },
            {
              prop: 'unreceivedQuantity',
              label: '未收料数量',
              minWidth: 116,
              align: 'right' as const
            },
            {
              prop: 'returnedQuantity',
              label: '已退库数量',
              minWidth: 116,
              align: 'right' as const
            },
            {
              prop: 'unreturnedQuantity',
              label: '未退库数量',
              minWidth: 116,
              align: 'right' as const
            }
          ]
        : []),
      { prop: 'unitPrice', label: '单价(元)', minWidth: 108, align: 'right' },
      { prop: 'taxInclusiveUnitPrice', label: '含税单价(元)', minWidth: 125, align: 'right' },
      { prop: 'taxRate', label: '税率(%)', minWidth: 100, align: 'right' },
      { prop: 'amount', label: '金额(元)', minWidth: 110, align: 'right' },
      { prop: 'taxAmount', label: '税额(元)', minWidth: 110, align: 'right' },
      { prop: 'totalAmount', label: '价税合计(元)', minWidth: 130, align: 'right' },
      { prop: 'batchNo', label: '批号', minWidth: 120 },
      { prop: 'warehouseName', label: '仓库', minWidth: 140 },
      { prop: 'binName', label: '仓位', minWidth: 120 },
      {
        prop: 'stockType',
        label: '库存类型',
        minWidth: 100,
        formatter: (row) => dictionaryLabel('wmsInitialStockType', row.stockType)
      },
      {
        prop: 'stockStatus',
        label: '库存状态',
        minWidth: 100,
        formatter: (row) => dictionaryLabel('wmsInitialStockCondition', row.stockStatus)
      },
      {
        prop: 'gift',
        label: '赠品',
        width: 78,
        align: 'center',
        formatter: (row) => (row.gift ? '✓' : '—')
      },
      {
        prop: 'operation',
        label: '操作',
        fixed: 'right',
        width: 112,
        formatter: (row) => (
          <BusinessTableRowActions>
            <ArtButtonTable
              type="view"
              label="查看"
              icon="ri:eye-line"
              permission={permission.value.View}
              onClick={() => openDocument('view', row.documentId)}
            />
            <ArtButtonMore
              list={moreActions(row)}
              trigger="click"
              onClick={(item: ButtonMoreItem) => onMoreAction(item, row)}
            />
          </BusinessTableRowActions>
        )
      }
    ]
  }
</script>

<style scoped>
  :deep(.wms-initialization-header .business-workspace-header__aside) {
    max-width: min(72%, 980px);
  }

  @media (width <= 1280px) {
    :deep(.wms-initialization-header .business-workspace-header__hero) {
      flex-wrap: wrap;
    }

    :deep(.wms-initialization-header .business-workspace-header__aside) {
      width: 100%;
      max-width: none;
      margin-left: 0;
    }
  }

  :deep(td.el-table__cell.wms-purchase-negative-cell) {
    background-color: var(--el-color-warning-light-9) !important;
  }

  :deep(.wms-purchase-negative) {
    font-weight: 800;
    font-variant-numeric: tabular-nums;
    color: var(--el-color-danger);
  }
</style>
