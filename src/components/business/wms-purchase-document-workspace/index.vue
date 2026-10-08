<template>
  <ArtPermissionGuard :permission="permission.View" :resource-name="title">
    <div class="business-workspace-page art-full-height min-w-0">
      <MasterDeleteProcessingNotice
        v-if="deleteContext.active"
        :location-ready="Boolean(locatedDocumentId && locatedDocumentId === matchedDocumentId)"
        action-hint="请核对关联采购单据，处理完成后返回原页面重新检查引用。"
      />
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
        :model-value="search"
        @update:model-value="replaceReactiveModel(search, $event)"
        :api-fn="fetchRows"
        :search-items="searchItems"
        :columns-factory="columnsFactory"
        :columns-context-key="displayMode"
        :header-actions="headerActions"
        header-actions-placement="workspace"
        :search-bar-props="{ span: 5, labelWidth: 76 }"
        :table-props="{
          rowKey: 'lineId',
          spanMethod: mergeDocumentCells,
          tableLayout: 'fixed',
          cellClassName: purchaseCellClassName,
          emptyText: deleteContext.active ? '未找到可查看的目标采购单据' : `当前范围暂无${title}`,
          emptyDescription: deleteContext.active
            ? '请核对单据类型、租户范围和查看权限，可重试或清除定位。'
            : '新建单据并选择物料，填写数量、价格与仓储信息。'
        }"
        focusable
        @selection-change="onSelectionChange"
      >
        <template #search-displayMode>
          <ElRadioGroup v-model="displayMode" aria-label="单据列表展示方式" @change="refresh">
            <ElRadioButton label="document" value="document">按单据</ElRadioButton>
            <ElRadioButton label="line" value="line">按明细</ElRadioButton>
          </ElRadioGroup>
        </template>
      </ArtTableQuery>
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
      <ArtDialog
        ref="orderTargetDialogRef"
        size="md"
        :show-footer="false"
        @close="closeOrderTargetPicker"
      >
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
        <ArtAsyncState
          :error="orderTargetError"
          error-title="来源单据加载失败"
          class="mt-5"
          @retry="loadOrderTargets"
        >
          <div v-if="orderTargets.length" class="flex flex-col gap-4 sm:flex-row sm:items-end">
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
              :disabled="orderTargetLoading || Boolean(orderTargetError) || !selectedOrderTargetId"
              @click="openSelectedOrderTarget"
            >
              {{ kind === 'other_inbound' ? '生成入库草稿' : '承接订单' }}
            </ElButton>
          </div>
          <ArtEmptyState
            v-else
            size="compact"
            title="暂无订单下推单"
            description="请先在 SCM 采购订单中审核并下推采购入库。"
          />
        </ArtAsyncState>
      </ArtDialog>
      <ArtDialog ref="pushDialogRef" size="sm" :show-footer="false">
        <ArtEntitySummary
          icon="ri:file-transfer-line"
          eyebrow="DOCUMENT PUSH"
          :title="
            isInitial
              ? '下推期初暂估应付'
              : isEntrustedProcessing
                ? '下推受托加工后续业务'
                : isReturn
                  ? '下推采购退货业务'
                  : '下推采购入库业务'
          "
          :description="
            isInitial
              ? '登记上线前未结清暂估应付；退货冲减应付，不影响库存。可在结束初始化的对账表核对。'
              : isEntrustedProcessing
                ? '勾选一张已审核单据，生成对应的受托收料或退料草稿。'
                : '选择后续业务目标。目标模块接入后将按当前已审核单据生成关联草稿。'
          "
        />
        <div v-if="isInitial" class="mt-5">
          <ElButton
            type="primary"
            class="w-full!"
            :loading="pushingInitialObligation"
            @click="pushInitialObligation"
            >{{ isReturn ? '期初暂估应付冲减' : '期初暂估应付单' }}</ElButton
          >
        </div>
        <div v-else-if="isEntrustedProcessing" class="mt-5">
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
      <MasterDataDeleteGuard ref="deleteGuardRef" />
    </div>
  </ArtPermissionGuard>
</template>

<script setup lang="tsx">
  import { useWmsInitialObligationPush } from '@/hooks/business/useWmsInitialObligationPush'
  import { replaceReactiveModel } from '@/utils/form/model'
  import { formatUnitDisplayName } from '@/utils/business/unit-display'
  import { formatCurrencyValue } from '@/utils/ui/format'
  import { useDictionaryOptions } from '@/hooks/core/useDictionaryOptions'
  import { ElMessage, ElTag } from 'element-plus'
  import { useRoute, useRouter } from 'vue-router'
  import { useRouteDocumentDrawer } from '@/hooks/core/useRouteDocumentDrawer'
  import { chunk } from 'lodash-es'
  import { useAuth } from '@/hooks/core/useAuth'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useDocumentBulkDelete } from '@/hooks/business/useDocumentBulkDelete'
  import { useRecordDeleteGuard } from '@/hooks/core/useRecordDeleteGuard'
  import { useMasterDataDeleteProcessingContext } from '@/hooks/core/useMasterDataDeleteProcessing'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'
  import MasterDataDeleteGuard from '@/components/business/master-data-delete-guard/index.vue'
  import ArtPermissionGuard from '@/components/core/feedback/art-permission-guard/index.vue'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtEntitySummary from '@/components/core/surfaces/art-entity-summary/index.vue'
  import ArtEmptyState from '@/components/core/feedback/art-empty-state/index.vue'
  import ArtAsyncState from '@/components/core/feedback/art-async-state/index.vue'
  import { useDetailRecord } from '@/hooks/core/useDetailRecord'
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
  import {
    documentGroupSpan,
    groupDocumentLines,
    loadAllLinePages
  } from '@/utils/business/document-detail-list'
  import { useTenantScopeStore } from '@/store/modules/tenant-scope'
  import { useUserStore } from '@/store/modules/user'
  import {
    changeWmsPurchaseStatus,
    fetchWmsPurchaseDocument,
    fetchWmsPurchasePage,
    fetchWmsPurchaseDocumentIdPage,
    fetchWmsPurchaseOrderTargets,
    type WmsPurchaseKind,
    type WmsPurchaseListRow
  } from '@/api/wms-purchase'
  import WmsPurchaseDocumentDrawer from './modules/wms-purchase-document-drawer.vue'

  const commonDocumentReviewStatusOptions = useDictionaryOptions('commonDocumentReviewStatus')

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
  const deleteResourceLabel = ref('')
  const { deleteGuardRef, inspectDeleteReferences } = useRecordDeleteGuard(
    'wms_purchase_document',
    () => deleteResourceLabel.value || title.value
  )
  const { hasAuth } = useAuth()
  const route = useRoute()
  const router = useRouter()
  const { effectiveTenantId } = storeToRefs(useTenantScopeStore())
  const deleteContext = useMasterDataDeleteProcessingContext()
  const locatedDocumentId = computed(() =>
    deleteContext.value.active && route.query.dependencyCode === 'wms_purchase_document'
      ? deleteContext.value.recordId
      : ''
  )
  const matchedDocumentId = ref('')
  let locationRequestSequence = 0
  watch(
    [locatedDocumentId, () => deleteContext.value.active, effectiveTenantId, () => props.kind],
    () => {
      locationRequestSequence += 1
      matchedDocumentId.value = ''
      void refresh()
    }
  )
  const userStore = useUserStore()
  void userStore.ensureDictLoaded('wmsInitialStockType')
  void userStore.ensureDictLoaded('wmsInitialStockCondition')
  const tableRef = ref<ArtTableQueryExpose>()
  const displayMode = ref<'document' | 'line'>('document')
  const visibleRows = ref<WmsPurchaseListRow[]>([])
  const lineProperties = new Set([
    'projectName',
    'materialCode',
    'materialDescription',
    'specificationModel',
    'inventoryUnitName',
    'quantity',
    'baseQuantity',
    'auxiliaryQuantity',
    'auxiliaryQuantity2',
    'discountAmount',
    'receivedQuantity',
    'unreceivedQuantity',
    'returnedQuantity',
    'unreturnedQuantity',
    'unitPrice',
    'taxInclusiveUnitPrice',
    'taxRate',
    'amount',
    'taxAmount',
    'totalAmount',
    'batchNo',
    'warehouseName',
    'binName',
    'stockType',
    'stockStatus',
    'gift'
  ])
  function mergeDocumentCells({
    rowIndex,
    column
  }: {
    rowIndex: number
    column: { property?: string }
  }) {
    return displayMode.value === 'line'
      ? documentGroupSpan(visibleRows.value, rowIndex, column.property, lineProperties)
      : ([1, 1] as [number, number])
  }
  const drawerRef = ref<InstanceType<typeof WmsPurchaseDocumentDrawer>>()
  const returnDrawerRef = ref<InstanceType<typeof WmsPurchaseDocumentDrawer>>()
  const entrustedTargetDrawerRef = ref<InstanceType<typeof WmsPurchaseDocumentDrawer>>()
  const pushDialogRef = ref<ArtDialogExpose>()
  const orderTargetDialogRef = ref<ArtDialogExpose>()
  const orderTargetPickerActive = ref(false)
  const {
    detail: orderTargetRows,
    loading: orderTargetLoading,
    loadError: orderTargetError,
    loadDetail: loadOrderTargetRows,
    openDetail: resetOrderTargetRows
  } = useDetailRecord<Awaited<ReturnType<typeof fetchWmsPurchaseOrderTargets>>>(
    async (tenantId) => ({
      data: await fetchWmsPurchaseOrderTargets(tenantId === '__all__' ? undefined : tenantId)
    }),
    '来源单据加载失败，请重新加载后再选择'
  )
  const orderTargets = computed(() => orderTargetRows.value ?? [])
  watch(orderTargetLoading, (loading) => orderTargetDialogRef.value?.setLoading(loading))
  watch(effectiveTenantId, () => {
    selectedOrderTargetId.value = ''
    resetOrderTargetRows('')
    if (orderTargetPickerActive.value) void loadOrderTargets()
  })
  const selectedOrderTargetId = ref('')
  const workingId = ref<string>()
  const selectedRows = ref<Array<{ documentId: string; kind: unknown; status: unknown }>>([])
  const { pushing: pushingInitialObligation, push: pushInitialObligation } =
    useWmsInitialObligationPush({
      area: 'purchase',
      getSelection: () => selectedRows.value,
      afterPush: async () => {
        await pushDialogRef.value?.handleClose()
      }
    })
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
    isInitial.value
      ? '记录上线前未结清采购往来，只初始化暂估应付，不更新库存。退货表单录入正数，列表以红色负数呈现。'
      : isReturn.value
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
    { label: '展示方式', key: 'displayMode', type: 'text', span: 6 },
    {
      label: '单据状态',
      key: 'status',
      type: 'select',
      props: {
        clearable: true,
        placeholder: '全部状态',
        options: commonDocumentReviewStatusOptions
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
  async function fetchRows(query: {
    exportAll?: boolean
    documentIds?: string[]
    status?: string
    supplier?: string
    projectName?: string
    materialDescription?: string
    materialCode?: string
    current: number
    size: number
  }) {
    const exportAll = query.exportAll === true
    const documentId = locatedDocumentId.value
    const tenantId = effectiveTenantId.value
    const kind = props.kind
    const locating = deleteContext.value.active
    const assertReadContext = () => {
      if (
        documentId !== locatedDocumentId.value ||
        tenantId !== effectiveTenantId.value ||
        kind !== props.kind ||
        locating !== deleteContext.value.active
      ) {
        throw new Error('查询范围已变化，请在当前范围重新查询或导出')
      }
    }
    const requestSequence = exportAll ? locationRequestSequence : ++locationRequestSequence
    if (!exportAll) matchedDocumentId.value = ''
    if (deleteContext.value.active && !locatedDocumentId.value) {
      matchedDocumentId.value = ''
      return { data: [], total: 0 }
    }
    const fetchPage = async (page: typeof query) => {
      assertReadContext()
      const result = await fetchWmsPurchasePage({
        ...(documentId ? { current: page.current, size: page.size } : page),
        documentId: documentId || undefined,
        kind,
        tenantId: tenantId || undefined
      })
      assertReadContext()
      if (
        !exportAll &&
        requestSequence === locationRequestSequence &&
        documentId === locatedDocumentId.value &&
        tenantId === effectiveTenantId.value &&
        kind === props.kind
      ) {
        matchedDocumentId.value = result.data.some((row) => row.documentId === documentId)
          ? documentId
          : ''
      }
      return result
    }
    if (displayMode.value === 'line') {
      if (exportAll) {
        const data = await loadAllLinePages(fetchPage, query)
        return { data, total: data.length }
      }
      const result = await fetchPage(query)
      if (requestSequence === locationRequestSequence) visibleRows.value = result.data
      return result
    }
    if (!exportAll) visibleRows.value = []
    let documentTotal: number | undefined
    let expectedDocumentCount: number | undefined
    let matchingDocumentIds: Set<string> | null = null
    let lines: WmsPurchaseListRow[]
    if (!exportAll && !documentId) {
      assertReadContext()
      const documents = await fetchWmsPurchaseDocumentIdPage({
        ...query,
        kind,
        tenantId: tenantId || undefined
      })
      assertReadContext()
      documentTotal = documents.total
      if (!documents.data.length) return { data: [], total: documentTotal }
      expectedDocumentCount = documents.data.length
      matchingDocumentIds = new Set(documents.data.map((row) => row.id))
      lines = await loadAllLinePages(fetchPage, {
        ...query,
        documentIds: documents.data.map((row) => row.id),
        projectName: undefined,
        materialCode: undefined,
        materialDescription: undefined
      })
    } else {
      const hasLineFilter = Boolean(
        !documentId &&
        (query.materialCode?.trim() ||
          query.materialDescription?.trim() ||
          query.projectName?.trim())
      )
      matchingDocumentIds = hasLineFilter
        ? new Set((await loadAllLinePages(fetchPage, query)).map((line) => line.documentId))
        : null
      if (matchingDocumentIds?.size === 0) return { data: [], total: 0 }
      const completeLineQuery = {
        ...query,
        projectName: undefined,
        materialCode: undefined,
        materialDescription: undefined
      }
      if (matchingDocumentIds) {
        lines = []
        for (const documentIds of chunk(Array.from(matchingDocumentIds), 20)) {
          lines.push(...(await loadAllLinePages(fetchPage, { ...completeLineQuery, documentIds })))
        }
        expectedDocumentCount = matchingDocumentIds.size
      } else {
        lines = await loadAllLinePages(fetchPage, completeLineQuery)
      }
    }
    const documents = groupDocumentLines(
      matchingDocumentIds
        ? lines.filter((line) => matchingDocumentIds.has(line.documentId))
        : lines,
      (line) => line.documentId
    ).map(({ first, lines: group }) => ({
      ...first,
      lineNo: group.length,
      materialCode: '',
      materialDescription: `共 ${group.length} 项物料`,
      amount: group.reduce((sum, line) => sum + Number(line.amount || 0), 0),
      discountAmount: group.reduce((sum, line) => sum + Number(line.discountAmount || 0), 0),
      taxAmount: group.reduce((sum, line) => sum + Number(line.taxAmount || 0), 0),
      totalAmount: group.reduce((sum, line) => sum + Number(line.totalAmount || 0), 0)
    }))
    if (expectedDocumentCount !== undefined && documents.length !== expectedDocumentCount) {
      throw new Error('单据或明细已变化，请刷新列表后重试')
    }
    return {
      data: (exportAll || documentTotal !== undefined
        ? documents
        : documents.slice((query.current - 1) * query.size, query.current * query.size)
      ).map((row) => ({
        ...row,
        inventoryUnitName: formatUnitDisplayName(row.inventoryUnitName)
      })),
      total: documentTotal ?? documents.length
    }
  }
  async function refresh(): Promise<void> {
    tableRef.value?.clearSelection()
    await tableRef.value?.refreshUpdate()
  }
  function purchaseCellClassName({
    row,
    column
  }: {
    row: Record<string, unknown>
    column: { property?: string }
  }): string {
    if (
      row.kind === 'initial_return' &&
      [
        'quantity',
        'baseQuantity',
        'auxiliaryQuantity',
        'auxiliaryQuantity2',
        'amount',
        'discountAmount',
        'totalAmount'
      ].includes(column.property || '')
    )
      return 'opening-return-negative-cell'
    return column.property === 'quantity' && returnKinds.some((kind) => kind === row.kind)
      ? 'wms-purchase-negative-cell'
      : ''
  }
  function onSelectionChange(rows: Record<string, unknown>[]): void {
    selectedRows.value = rows.flatMap(({ documentId, kind, status }) =>
      typeof documentId === 'string' ? [{ documentId, kind, status }] : []
    )
  }
  async function openDocument(
    mode: 'view' | 'edit' | 'copy',
    row: WmsPurchaseListRow
  ): Promise<void> {
    try {
      const target =
        props.kind === 'other_inbound' && row.kind === 'other_return'
          ? returnDrawerRef.value
          : drawerRef.value
      await target?.handleOpen({ mode, documentId: row.documentId })
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
  async function loadOrderTargets(): Promise<void> {
    if (!orderTargetPickerActive.value) return
    selectedOrderTargetId.value = ''
    await loadOrderTargetRows(effectiveTenantId.value ?? '__all__')
  }
  function closeOrderTargetPicker(): void {
    orderTargetPickerActive.value = false
    selectedOrderTargetId.value = ''
    resetOrderTargetRows('')
  }
  onUnmounted(closeOrderTargetPicker)
  async function openOrderTargetPicker(): Promise<void> {
    orderTargetPickerActive.value = true
    resetOrderTargetRows('')
    selectedOrderTargetId.value = ''
    await orderTargetDialogRef.value?.handleOpen(undefined, {
      title: props.kind === 'other_inbound' ? '选择来源单据' : '承接采购订单',
      loading: true,
      loadingText: '正在加载来源单据…',
      onOpen: () => {
        void loadOrderTargets()
      }
    })
  }
  async function openSelectedOrderTarget(): Promise<void> {
    if (
      !orderTargetPickerActive.value ||
      orderTargetLoading.value ||
      orderTargetError.value ||
      !orderTargets.value.some((row) => row.id === selectedOrderTargetId.value)
    )
      return
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
  useRouteDocumentDrawer({
    routeName: () => permission.value.View.split(':')[0],
    canOpen: () => props.kind.startsWith('initial_') && hasAuth(permission.value.View),
    fetchDocument: async (id) => {
      const document = await fetchWmsPurchaseDocument(id)
      if (document.kind !== props.kind) throw new Error('单据类型不匹配')
      return document
    },
    openDocument: async (document) => {
      await drawerRef.value?.handleOpen({ mode: 'view', document })
    },
    onError: () => ElMessage.error(`${title.value}加载失败，请刷新后重试`)
  })
  onMounted(async () => {
    if (typeof route.query.documentId === 'string' && props.kind.startsWith('initial_')) return
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
    if (workingId.value || bulkDeleting.value) return
    const label = { submit: '提交', approve: '审核', delete: '删除' }[action]
    const resources = [{ id: row.documentId, label: row.documentNo }]
    deleteResourceLabel.value = row.kind === 'other_return' ? '其他入库退回单' : title.value
    workingId.value = row.documentId
    try {
      if (action === 'delete' && (await inspectDeleteReferences(resources))) return
      await confirmAction(
        `确定${label} ${row.documentNo}？`,
        `${label}${deleteResourceLabel.value}`,
        {
          type: action === 'delete' ? 'warning' : 'info',
          confirmButtonText: `确定${label}`
        }
      )
      await changeWmsPurchaseStatus(row.documentId, action)
      await refresh()
    } catch (error) {
      if (action === 'delete' && error !== 'cancel' && error !== 'close') {
        await inspectDeleteReferences(resources)
      }
      /* 取消和接口错误由组件处理。 */
    } finally {
      workingId.value = undefined
    }
  }
  const { bulkDeleteAction, bulkDeleting } = useDocumentBulkDelete({
    permission: () => permission.value.Delete,
    resourceLabel: () => title.value,
    idKey: 'documentId',
    busy: () => Boolean(workingId.value),
    inspect: inspectDeleteReferences,
    remove: (id) => changeWmsPurchaseStatus(id, 'delete'),
    refresh,
    clearSelection: () => tableRef.value?.clearSelection()
  })
  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    bulkDeleteAction(),
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
      exportData: async () =>
        (await fetchRows({ ...search, current: 1, size: 500, exportAll: true })).data.map(
          (row) => ({ ...row, status: statusLabel(row.status) })
        ),
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
      void openDocument(item.key, row)
    } else if (item.key === 'submit' || item.key === 'approve' || item.key === 'delete') {
      void transition(row, item.key)
    }
  }
  function columnsFactory(): ColumnOption<WmsPurchaseListRow>[] {
    const columns: ColumnOption<WmsPurchaseListRow>[] = [
      { type: 'selection', width: 48, fixed: 'left' },
      {
        prop: 'documentNo',
        label: '单据编号',
        fixed: 'left',
        minWidth: 180,
        formatter: (row) => (
          <BusinessTableIdentityCell
            primary={row.documentNo}
            secondary={`${displayMode.value === 'document' ? `共 ${row.lineNo} 项物料` : `第 ${row.lineNo} 行`} · ${isEntrustedProcessing.value ? row.customerName || '未关联客户' : row.supplierName || '未关联供应商'}`}
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
      ...(displayMode.value === 'line'
        ? [{ prop: 'materialCode', label: '物料编码', minWidth: 125 }]
        : []),
      { prop: 'materialDescription', label: '物料描述', minWidth: 175, showOverflowTooltip: true },
      { prop: 'specificationModel', label: '规格型号', minWidth: 130 },
      {
        prop: 'inventoryUnitName',
        label: '库存单位',
        width: 98,
        formatter: (row) => formatUnitDisplayName(row.inventoryUnitName)
      },
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
      ...(displayMode.value === 'line' && props.kind === 'initial_return'
        ? ([
            { prop: 'baseQuantity', label: '基本数量', minWidth: 115, align: 'right' },
            { prop: 'auxiliaryQuantity', label: '辅助数量', minWidth: 115, align: 'right' },
            { prop: 'auxiliaryQuantity2', label: '辅助数量2', minWidth: 125, align: 'right' }
          ] as ColumnOption<WmsPurchaseListRow>[])
        : []),
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
      {
        prop: 'amount',
        label: '金额(元)',
        minWidth: 110,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.amount)
      },
      ...(props.kind === 'initial_return'
        ? ([
            {
              prop: 'discountAmount',
              label: '折扣额(元)',
              minWidth: 115,
              align: 'right',
              formatter: (row) => formatCurrencyValue(row.discountAmount)
            }
          ] as ColumnOption<WmsPurchaseListRow>[])
        : []),
      {
        prop: 'taxAmount',
        label: '税额(元)',
        minWidth: 110,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.taxAmount)
      },
      {
        prop: 'totalAmount',
        label: '价税合计(元)',
        minWidth: 130,
        align: 'right',
        formatter: (row) => formatCurrencyValue(row.totalAmount)
      },
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
              onClick={() => openDocument('view', row)}
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
    if (displayMode.value === 'line') return columns
    const detailOnly = new Set([
      'quantity',
      'specificationModel',
      'inventoryUnitName',
      'unitPrice',
      'taxInclusiveUnitPrice',
      'taxRate',
      'batchNo',
      'warehouseName',
      'binName',
      'stockType',
      'stockStatus',
      'gift',
      'receivedQuantity',
      'unreceivedQuantity',
      'returnedQuantity',
      'unreturnedQuantity'
    ])
    return columns.filter((column) => !detailOnly.has(String(column.prop)))
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

  :deep(td.el-table__cell.opening-return-negative-cell) {
    font-variant-numeric: tabular-nums;
    color: var(--el-color-danger);
  }
</style>
