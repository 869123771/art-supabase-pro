<template>
  <ArtDialog ref="dialogRef" size="xl">
    <InvoiceOcrPanel
      ref="ocrPanelRef"
      v-model="attachmentUrls"
      :direction="form.data.direction"
      @apply="handleApplyOcrResult"
    />

    <ArtForm
      ref="formRef"
      class="invoice-dialog__form"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="8"
      :gutter="20"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #counterpartyId>
        <div class="invoice-dialog__counterparty-field">
          <ArtTableSingleSelect
            v-model="form.data.counterpartyId"
            v-model:selected-data="selection.parties"
            :api-fn="fetchPartySelectorData"
            :columns="partyColumns"
            :title="form.data.direction === 'output' ? '选择开票客户' : '选择来票承运商'"
            :subtitle="
              form.data.direction === 'output'
                ? '销项发票关联客户对账单'
                : '进项发票关联承运商对账单'
            "
            row-key="id"
            label-key="partyName"
            description-key="partyCode"
            placeholder="请选择往来单位"
            search-placeholder="名称、编码、联系人或电话"
            dialog-width="lg"
            show-pagination
            :page-size="10"
            @change="handlePartyChange"
          />

          <div
            v-if="counterpartyResolution.status !== 'idle'"
            class="invoice-dialog__counterparty-resolution"
            aria-live="polite"
          >
            <ElAlert
              class="invoice-dialog__counterparty-alert"
              :type="counterpartyResolutionAlertType"
              :closable="false"
              show-icon
              :title="counterpartyResolution.message"
              :description="counterpartyResolutionDescription"
            />
            <ElButton
              v-if="showCreateCounterpartyAction"
              type="primary"
              plain
              @click="handleOpenCounterpartyCreate"
            >
              建档并带入
            </ElButton>
            <ElButton
              v-else-if="counterpartyResolution.status === 'error'"
              plain
              @click="retryCounterpartyResolution"
            >
              重新匹配
            </ElButton>
          </div>
        </div>
      </template>

      <template #statementIds>
        <ArtTableMultipleSelect
          ref="statementSelectRef"
          v-model="form.data.statementIds"
          v-model:selected-data="selection.statements"
          :api-fn="fetchStatementSelectorData"
          :columns="statementColumns"
          title="选择关联对账单"
          subtitle="仅显示当前往来单位已确认、部分结算或已结清的对账单"
          row-key="statementId"
          label-key="statementNo"
          description-key="periodLabel"
          placeholder="可选择一个或多个对账单"
          search-placeholder="对账单号或往来单位"
          dialog-width="xl"
          show-pagination
          show-selected-panel
          :page-size="10"
          :disabled="!form.data.counterpartyId"
        />
      </template>
    </ArtForm>

    <div class="invoice-dialog__feedback-stack">
      <ElAlert
        v-if="ocrInvoiceNoWarning"
        class="invoice-dialog__notice"
        type="warning"
        :closable="false"
        show-icon
        title="识别出的发票号码未自动填入"
        :description="ocrInvoiceNoWarning"
      />

      <div
        v-if="duplicateCheckPending"
        class="invoice-dialog__checking"
        role="status"
        aria-live="polite"
      >
        正在核验发票号码是否重复…
      </div>
      <ElAlert
        v-else-if="effectiveDuplicateInvoice"
        class="invoice-dialog__notice"
        :type="canMergeDuplicate ? 'warning' : 'error'"
        :closable="false"
        show-icon
        :title="duplicateAlertTitle"
        :description="duplicateAlertDescription"
      />

      <ElAlert
        :type="selection.statements.length ? 'success' : 'info'"
        :closable="false"
        show-icon
        :title="selectionSummary"
      />
    </div>

    <section v-if="selection.statements.length" class="invoice-dialog__links art-card-xs">
      <ArtSectionTitle>对账单关联金额</ArtSectionTitle>
      <ArtTable
        :data="selection.statements"
        :columns="linkedStatementColumns"
        :pagination="false"
        table-layout="fixed"
      >
        <template #linkedAmount="{ row }">
          <ElInputNumber
            v-model="selection.linkAmounts[row.statementId]"
            :min="0.01"
            :max="getAvailableAmount(row)"
            :precision="2"
            :step="100"
            controls-position="right"
          />
        </template>
      </ArtTable>
    </section>
  </ArtDialog>

  <InvoiceCounterpartyCreateDialog
    ref="counterpartyCreateDialogRef"
    @success="handleCounterpartyCreated"
  />
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { ElMessage, type FormRules } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { ColumnOption } from '@/types'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtTableMultipleSelect from '@/components/core/forms/art-data-select/table-multiple.vue'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    ArtDataSelectExpose,
    DataSelectColumn,
    DataSelectFetchParams,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import InvoiceCounterpartyCreateDialog from './invoice-counterparty-create-dialog.vue'
  import InvoiceOcrPanel from './invoice-ocr-panel.vue'
  import {
    reviewInvoiceOcrArtifact,
    fetchCarrierOptions,
    fetchCustomerSelectorList,
    fetchActiveInvoiceByLegalNo,
    fetchInvoiceDetail,
    fetchInvoiceableStatementList,
    isInvoiceLegalNumberConflict,
    resolveInvoiceCounterparty,
    saveInvoice
  } from '@/api/fms'
  import { fetchRecognitionArtifactDetail } from '@/api/intelligent-recognition'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { toInvoiceOcrAnalyzeResponse } from '@/utils/intelligent-recognition'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import {
    buildInvoicePayload,
    createInitialInvoiceForm,
    INVOICE_NO_PATTERN,
    normalizeInvoiceNo,
    roundInvoiceMoney,
    type Invoice,
    type InvoiceFormModel
  } from './invoice-dialog-model'

  defineOptions({ name: 'FinanceInvoiceDialog' })

  type InvoiceableStatement = Api.Fms.InvoiceableStatement
  type CounterpartyResolutionStatus =
    Api.Fms.InvoiceCounterpartyResolutionStatus | 'idle' | 'loading' | 'error'

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface InvoiceOcrPanelExpose {
    reset: () => void
  }

  interface CounterpartyCreateDialogExpose {
    handleOpen: (data: {
      artifactId: string
      direction: Api.Fms.InvoiceDirection
      name: string
      taxNo?: string | null
      requiresReview: boolean
    }) => Promise<void>
  }

  interface FormGroup {
    data: InvoiceFormModel
    items: ComputedRef<FormItem[]>
    rules: FormRules<InvoiceFormModel>
  }

  interface SelectionGroup {
    parties: DataSelectRecord[]
    statements: DataSelectRecord[]
    linkAmounts: Record<string, number>
    originalLinkAmounts: Record<string, number>
  }

  interface CounterpartyResolutionGroup {
    status: CounterpartyResolutionStatus
    message: string
    artifactId?: string
    result?: Api.Fms.InvoiceCounterpartyResolution | null
  }

  interface InvoiceOcrContext {
    direction: Api.Fms.InvoiceDirection
    result: Api.Fms.InvoiceOcrAnalyzeResponse
  }

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Invoice | undefined>>()
  const formRef = ref<FormExpose>()
  const statementSelectRef = ref<ArtDataSelectExpose>()
  const ocrPanelRef = ref<InvoiceOcrPanelExpose>()
  const counterpartyCreateDialogRef = ref<CounterpartyCreateDialogExpose>()
  const ocrArtifactId = ref<string>()
  const ocrInvoiceNoWarning = ref('')
  const duplicateInvoice = ref<Api.Fms.InvoiceDuplicateRecord>()
  const ocrSourceDuplicateInvoice = ref<Api.Fms.InvoiceDuplicateRecord>()
  const duplicateCheckPending = ref(false)
  const invoiceRecordNumber = useDocumentNumberRule('tms.invoice_record')
  let duplicateCheckSequence = 0

  const createInitialForm = createInitialInvoiceForm

  const selection = reactive<SelectionGroup>({
    parties: [],
    statements: [],
    linkAmounts: {},
    originalLinkAmounts: {}
  })

  const counterpartyResolution = reactive<CounterpartyResolutionGroup>({
    status: 'idle',
    message: '',
    artifactId: undefined,
    result: null
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: reactive<InvoiceFormModel>(createInitialForm()),
    items: computed(() => [
      { label: '基本信息', key: 'baseSection', type: 'divider', span: 24 },
      {
        label: '登记单号',
        key: 'invoiceRecordNo',
        type: 'input',
        span: 8,
        props: {
          maxlength: 50,
          ...invoiceRecordNumber.inputProps(Boolean(form.data.id), '请输入开票登记号', true)
        },
        description: invoiceRecordNumber.description.value
      },
      {
        label: '发票方向',
        key: 'direction',
        type: 'select',
        span: 8,
        props: {
          options: getDictMap.value.tmsInvoiceDirection ?? [],
          disabled: Boolean(form.data.id),
          onChange: handleDirectionChange
        }
      },
      { label: '往来单位', key: 'counterpartyId', type: 'input', span: 16 },
      {
        label: '发票类型',
        key: 'invoiceType',
        type: 'select',
        span: 8,
        props: { options: getDictMap.value.tmsInvoiceType ?? [] }
      },
      {
        label: '开票日期',
        key: 'issueDate',
        type: 'date',
        span: 8,
        props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
      },
      {
        label: '税率（%）',
        key: 'taxRate',
        type: 'number',
        span: 8,
        props: {
          min: 0,
          max: 100,
          precision: 2,
          controlsPosition: 'right',
          class: '!w-full',
          onChange: recalculateTax
        }
      },
      { label: '发票抬头', key: 'invoiceTitle', type: 'input', span: 12 },
      { label: '纳税人识别号', key: 'taxNumber', type: 'input', span: 12 },
      { label: '发票代码', key: 'invoiceCode', type: 'input', span: 12 },
      {
        label: '发票号码',
        key: 'invoiceNo',
        type: 'input',
        span: 12,
        props: {
          maxlength: 30,
          placeholder: '请输入 6–30 位数字或字母',
          onInput: clearInvoiceDuplicate,
          onBlur: handleInvoiceNoBlur
        }
      },
      { label: '金额信息', key: 'amountSection', type: 'divider', span: 24 },
      {
        label: '不含税金额',
        key: 'amountExcludingTax',
        type: 'number',
        span: 8,
        props: {
          min: 0,
          precision: 2,
          controlsPosition: 'right',
          class: '!w-full',
          onChange: recalculateTax
        }
      },
      {
        label: '税额',
        key: 'taxAmount',
        type: 'number',
        span: 8,
        props: {
          min: 0,
          precision: 2,
          controlsPosition: 'right',
          class: '!w-full',
          onChange: recalculateTotal
        }
      },
      {
        label: '价税合计',
        key: 'totalAmount',
        type: 'number',
        span: 8,
        props: {
          min: 0.01,
          precision: 2,
          controlsPosition: 'right',
          class: '!w-full',
          disabled: true
        }
      },
      { label: '对账关联', key: 'linkSection', type: 'divider', span: 24 },
      { label: '关联对账单', key: 'statementIds', type: 'input', span: 24 },
      {
        label: '备注',
        key: 'remark',
        type: 'input',
        span: 24,
        props: {
          type: 'textarea',
          rows: 3,
          maxlength: 500,
          showWordLimit: true,
          placeholder: '填写开票说明、认证信息或内部备注'
        }
      }
    ]),
    rules: {
      invoiceRecordNo: [
        {
          validator: (_rule, value, callback) =>
            invoiceRecordNumber.manualRequired(Boolean(form.data.id)) && !String(value || '').trim()
              ? callback(new Error('请输入开票登记号'))
              : callback(),
          trigger: 'blur'
        }
      ],
      direction: [{ required: true, message: '请选择发票方向', trigger: 'change' }],
      counterpartyId: [{ required: true, message: '请选择往来单位', trigger: 'change' }],
      invoiceType: [{ required: true, message: '请选择发票类型', trigger: 'change' }],
      issueDate: [{ required: true, message: '请选择开票日期', trigger: 'change' }],
      invoiceNo: [
        { required: true, message: '请输入发票号码', trigger: 'blur' },
        { validator: validateInvoiceNo, trigger: 'blur' }
      ],
      amountExcludingTax: [
        { required: true, type: 'number', min: 0, message: '不含税金额不能小于 0', trigger: 'blur' }
      ],
      totalAmount: [
        {
          required: true,
          type: 'number',
          min: 0.01,
          message: '价税合计必须大于 0',
          trigger: 'blur'
        }
      ],
      remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
    }
  })

  const partyColumns: DataSelectColumn[] = [
    { prop: 'partyCode', label: '编码', width: 150 },
    { prop: 'partyName', label: '名称', minWidth: 230 },
    { prop: 'contactName', label: '联系人', width: 120 },
    { prop: 'contactPhone', label: '联系电话', width: 145 }
  ]

  const statementColumns: DataSelectColumn[] = [
    { prop: 'statementNo', label: '对账单号', width: 190 },
    {
      prop: 'periodLabel',
      label: '账期',
      width: 205,
      formatter: (row) => `${row.periodStart} 至 ${row.periodEnd}`
    },
    {
      prop: 'statementAmount',
      label: '对账金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney((row as InvoiceableStatement).statementAmount)
    },
    {
      prop: 'availableAmount',
      label: '可开票金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(getAvailableAmount(row))
    }
  ]

  const linkedStatementColumns: ColumnOption<DataSelectRecord>[] = [
    { prop: 'statementNo', label: '对账单号', minWidth: 180 },
    {
      prop: 'periodLabel',
      label: '账期',
      width: 205,
      formatter: (row) => `${row.periodStart} 至 ${row.periodEnd}`
    },
    {
      prop: 'statementAmount',
      label: '对账金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(Number(row.statementAmount))
    },
    {
      prop: 'availableAmount',
      label: '可开票金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(getAvailableAmount(row))
    },
    {
      prop: 'linkedAmount',
      label: '本次关联',
      width: 190,
      align: 'right',
      useSlot: true
    }
  ]

  const selectedLinkedAmount = computed(() =>
    selection.statements.reduce(
      (total, row) => total + Number(selection.linkAmounts[String(row.statementId)] ?? 0),
      0
    )
  )

  const effectiveDuplicateInvoice = computed(
    () => duplicateInvoice.value ?? ocrSourceDuplicateInvoice.value
  )

  const canMergeDuplicate = computed(
    () =>
      Boolean(ocrArtifactId.value) &&
      !form.data.id &&
      effectiveDuplicateInvoice.value?.status === 'draft'
  )

  const duplicateStatusLabel = computed(() => {
    const status = effectiveDuplicateInvoice.value?.status
    if (!status) return ''
    return (
      getDictMap.value.tmsInvoiceStatus?.find((item) => item.value === status)?.label ??
      {
        draft: '草稿',
        pending_review: '待审核',
        issued: '已开票',
        certified: '已认证',
        voided: '已作废'
      }[status]
    )
  })

  const duplicateAlertTitle = computed(() =>
    canMergeDuplicate.value ? '已发现关联草稿，本次保存将安全归并' : '该票据已登记'
  )

  const duplicateAlertDescription = computed(() => {
    const invoice = effectiveDuplicateInvoice.value
    if (!invoice) return ''
    const identity = `${invoice.invoiceRecordNo}（${duplicateStatusLabel.value}）`
    return canMergeDuplicate.value
      ? `识别来源已对应记录 ${identity}。补正票号并保存时将更新该草稿，同时保留原有关联，避免重复建单。`
      : `已有记录 ${identity}，不能重复创建。请修改发票号码，或返回台账处理已有记录。`
  })

  const attachmentUrls = computed<string[]>({
    get: () =>
      form.data.attachments
        .map((item) => (typeof item.url === 'string' ? item.url : ''))
        .filter(Boolean),
    set: (urls) => {
      form.data.attachments = urls.map((url) => ({
        url,
        name: decodeURIComponent(url.split('/').pop() || '发票附件'),
        category: 'invoice_image'
      }))
    }
  })

  const selectionSummary = computed(() =>
    selection.statements.length
      ? `已选择 ${selection.statements.length} 份对账单，本次关联 ${formatMoney(selectedLinkedAmount.value)}，发票价税合计 ${formatMoney(form.data.totalAmount)}`
      : form.data.counterpartyId
        ? '可以关联已确认的对账单；暂不关联时，发票将进入待匹配状态'
        : '请先选择发票方向和往来单位，再关联对账单'
  )

  const counterpartyResolutionAlertType = computed<'success' | 'warning' | 'error' | 'info'>(() => {
    if (counterpartyResolution.status === 'matched') return 'success'
    if (
      counterpartyResolution.status === 'conflict' ||
      counterpartyResolution.status === 'ambiguous' ||
      counterpartyResolution.status === 'disabled' ||
      counterpartyResolution.status === 'invalid' ||
      counterpartyResolution.status === 'error'
    ) {
      return 'error'
    }
    return counterpartyResolution.status === 'unmatched' ? 'warning' : 'info'
  })

  const counterpartyResolutionDescription = computed(() => {
    if (counterpartyResolution.status === 'loading') return '正在租户内按税号和完整名称查重'
    const result = counterpartyResolution.result
    if (!result?.name && !result?.taxNo) return ''
    return [`识别主体：${result.name || '未识别'}`, `税号：${result.taxNo || '未识别'}`].join('；')
  })

  const showCreateCounterpartyAction = computed(
    () =>
      counterpartyResolution.status === 'unmatched' &&
      Boolean(counterpartyResolution.result?.canCreate)
  )

  watch(
    () => selection.statements.map((row) => String(row.statementId)),
    (statementIds) => {
      const nextAmounts: Record<string, number> = {}
      for (const statementId of statementIds) {
        const row = selection.statements.find((item) => String(item.statementId) === statementId)
        const availableAmount = row ? getAvailableAmount(row) : 0
        nextAmounts[statementId] =
          selection.linkAmounts[statementId] ??
          Math.min(availableAmount, form.data.totalAmount || availableAmount)
      }
      selection.linkAmounts = nextAmounts
    },
    { deep: true }
  )

  function roundMoney(value: number): number {
    return roundInvoiceMoney(value)
  }

  function validateInvoiceNo(
    _rule: unknown,
    value: unknown,
    callback: (error?: Error) => void
  ): void {
    const normalized = normalizeInvoiceNo(value)
    if (!normalized || INVOICE_NO_PATTERN.test(normalized)) {
      callback()
      return
    }
    callback(new Error('发票号码应为 6–30 位数字或字母，不能包含小数点或金额符号'))
  }

  function clearInvoiceDuplicate(): void {
    duplicateCheckSequence += 1
    duplicateInvoice.value = undefined
    duplicateCheckPending.value = false
  }

  async function handleInvoiceNoBlur(): Promise<void> {
    form.data.invoiceNo = normalizeInvoiceNo(form.data.invoiceNo)
    if (INVOICE_NO_PATTERN.test(form.data.invoiceNo)) ocrInvoiceNoWarning.value = ''
    await checkDuplicateInvoice()
  }

  async function checkDuplicateInvoice(): Promise<Api.Fms.InvoiceDuplicateRecord | undefined> {
    const invoiceNo = normalizeInvoiceNo(form.data.invoiceNo)
    const sequence = ++duplicateCheckSequence
    duplicateInvoice.value = undefined
    if (!INVOICE_NO_PATTERN.test(invoiceNo)) {
      duplicateCheckPending.value = false
      return undefined
    }

    duplicateCheckPending.value = true
    try {
      const { data, error } = await fetchActiveInvoiceByLegalNo({
        direction: form.data.direction,
        invoiceNo,
        excludeId: form.data.id
      })
      if (sequence !== duplicateCheckSequence) return duplicateInvoice.value
      if (error) return undefined
      duplicateInvoice.value = data ?? undefined
      return duplicateInvoice.value
    } finally {
      if (sequence === duplicateCheckSequence) duplicateCheckPending.value = false
    }
  }

  async function checkOcrSourceDuplicate(invoiceNo?: string | null): Promise<void> {
    ocrSourceDuplicateInvoice.value = undefined
    const sourceInvoiceNo = String(invoiceNo ?? '').trim()
    if (!sourceInvoiceNo) return
    const { data } = await fetchActiveInvoiceByLegalNo({
      direction: form.data.direction,
      invoiceNo: sourceInvoiceNo,
      excludeId: form.data.id
    })
    ocrSourceDuplicateInvoice.value = data ?? undefined
  }

  function recalculateTax(): void {
    form.data.taxAmount = roundMoney(
      Number(form.data.amountExcludingTax || 0) * (Number(form.data.taxRate || 0) / 100)
    )
    recalculateTotal()
  }

  function recalculateTotal(): void {
    form.data.totalAmount = roundMoney(
      Number(form.data.amountExcludingTax || 0) + Number(form.data.taxAmount || 0)
    )
  }

  function formatMoney(value?: number | null): string {
    return `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  function getAvailableAmount(row: Record<string, unknown>): number {
    const statementId = String(row.statementId)
    return roundMoney(
      Number(row.uninvoicedAmount ?? 0) + Number(selection.originalLinkAmounts[statementId] ?? 0)
    )
  }

  async function fetchPartySelectorData(params: DataSelectFetchParams) {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    if (form.data.direction === 'output') {
      const { data, total } = await fetchCustomerSelectorList({ keyword: params.keyword, from, to })
      return {
        data: (data ?? []).map((item) => ({
          ...item,
          partyName: item.customerName,
          partyCode: item.customerCode
        })),
        total: total ?? 0
      }
    }

    const { data } = await fetchCarrierOptions({ companyName: params.keyword })
    const records = (data ?? []).map((item) => ({
      ...item,
      partyName: item.companyName,
      partyCode: item.carrierCode
    }))
    return { data: records.slice(from, to + 1), total: records.length }
  }

  async function fetchStatementSelectorData(params: DataSelectFetchParams) {
    if (!form.data.counterpartyId) return { data: [], total: 0 }
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchInvoiceableStatementList({
      direction: form.data.direction,
      counterpartyId: form.data.counterpartyId,
      keyword: params.keyword,
      includeFullyInvoiced: Boolean(form.data.id),
      from,
      to
    })
    return {
      data: (data ?? []).map((item) => ({
        ...item,
        periodLabel: `${item.periodStart} 至 ${item.periodEnd}`,
        availableAmount: roundMoney(
          item.uninvoicedAmount + Number(selection.originalLinkAmounts[item.statementId] ?? 0)
        )
      })),
      total: total ?? 0
    }
  }

  function clearStatements(): void {
    form.data.statementIds = []
    selection.statements = []
    selection.linkAmounts = {}
    selection.originalLinkAmounts = {}
    void statementSelectRef.value?.reload()
  }

  function resetCounterpartyResolution(): void {
    Object.assign(counterpartyResolution, {
      status: 'idle',
      message: '',
      artifactId: undefined,
      result: null
    } satisfies CounterpartyResolutionGroup)
  }

  function handleDirectionChange(): void {
    form.data.counterpartyId = ''
    selection.parties = []
    clearStatements()
    resetCounterpartyResolution()
    clearInvoiceDuplicate()
    ocrSourceDuplicateInvoice.value = undefined
    ocrArtifactId.value = undefined
    ocrPanelRef.value?.reset()
  }

  function handlePartyChange(): void {
    clearStatements()
    if (form.data.counterpartyId) resetCounterpartyResolution()
  }

  function replaceForm(nextForm: InvoiceFormModel): void {
    Object.assign(form.data, createInitialForm(), nextForm)
  }

  async function resetForm(): Promise<void> {
    replaceForm(createInitialForm())
    selection.parties = []
    selection.statements = []
    selection.linkAmounts = {}
    selection.originalLinkAmounts = {}
    resetCounterpartyResolution()
    ocrArtifactId.value = undefined
    ocrInvoiceNoWarning.value = ''
    clearInvoiceDuplicate()
    ocrSourceDuplicateInvoice.value = undefined
    ocrPanelRef.value?.reset()
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleApplyOcrResult(result: Api.Fms.InvoiceOcrAnalyzeResponse): Promise<void> {
    const invoice = result.invoice
    const patch: Partial<InvoiceFormModel> = {}
    const recognizedCounterpartyName =
      form.data.direction === 'output' ? invoice.buyerName : invoice.sellerName
    const recognizedCounterpartyTaxNo =
      form.data.direction === 'output' ? invoice.buyerTaxNumber : invoice.sellerTaxNumber
    const textFields = ['invoiceCode', 'issueDate'] as const
    const numberFields = ['taxRate', 'amountExcludingTax', 'taxAmount', 'totalAmount'] as const

    if (invoice.invoiceType) patch.invoiceType = invoice.invoiceType
    patch.invoiceTitle = invoice.invoiceTitle || recognizedCounterpartyName || ''
    patch.taxNumber = invoice.taxNumber || recognizedCounterpartyTaxNo || ''
    for (const field of textFields) {
      const value = invoice[field]
      if (value) Object.assign(patch, { [field]: value })
    }
    const recognizedInvoiceNo = normalizeInvoiceNo(invoice.invoiceNo)
    if (invoice.invoiceNo && !INVOICE_NO_PATTERN.test(recognizedInvoiceNo)) {
      patch.invoiceNo = ''
      ocrInvoiceNoWarning.value = `识别值“${String(invoice.invoiceNo).slice(0, 40)}”不像有效票号，请对照票面手工补录后再保存。`
    } else if (recognizedInvoiceNo) {
      patch.invoiceNo = recognizedInvoiceNo
      ocrInvoiceNoWarning.value = ''
    }
    for (const field of numberFields) {
      const value = invoice[field]
      if (value !== null && value !== undefined) Object.assign(patch, { [field]: Number(value) })
    }

    Object.assign(form.data, patch)
    form.data.counterpartyId = ''
    selection.parties = []
    clearStatements()
    ocrArtifactId.value = result.artifactId
    await Promise.all([
      resolveRecognizedCounterparty(result.artifactId),
      checkDuplicateInvoice(),
      checkOcrSourceDuplicate(invoice.invoiceNo)
    ])
    await nextTick(() => formRef.value?.clearValidate())
    ElMessage.success(
      counterpartyResolution.status === 'matched'
        ? '识别结果已填入，往来单位已自动匹配'
        : '识别结果已填入，请继续核对往来单位和低置信字段'
    )
  }

  async function resolveRecognizedCounterparty(artifactId: string): Promise<void> {
    Object.assign(counterpartyResolution, {
      status: 'loading',
      message: '正在匹配往来单位',
      artifactId,
      result: null
    } satisfies CounterpartyResolutionGroup)

    try {
      const { data, error } = await resolveInvoiceCounterparty(artifactId)
      if (error || !data) throw error || new Error('往来单位匹配结果为空')

      Object.assign(counterpartyResolution, {
        status: data.status,
        message: data.message,
        artifactId,
        result: data
      } satisfies CounterpartyResolutionGroup)

      if (data.status === 'matched' && data.party) {
        applyCounterparty(data.party)
      }
    } catch {
      Object.assign(counterpartyResolution, {
        status: 'error',
        message: '往来单位自动匹配失败，可重试或手动选择',
        artifactId,
        result: null
      } satisfies CounterpartyResolutionGroup)
    }
  }

  function applyCounterparty(party: Api.Fms.InvoiceCounterpartyOption): void {
    form.data.counterpartyId = party.id
    selection.parties = [
      {
        id: party.id,
        partyName: party.partyName,
        partyCode: party.partyCode ?? '',
        taxNo: party.taxNo ?? ''
      }
    ]
    clearStatements()
    void nextTick(() => formRef.value?.clearValidate())
  }

  function handleOpenCounterpartyCreate(): void {
    const result = counterpartyResolution.result
    const artifactId = counterpartyResolution.artifactId
    if (!artifactId || !result?.name || !showCreateCounterpartyAction.value) return
    void counterpartyCreateDialogRef.value?.handleOpen({
      artifactId,
      direction: result.direction,
      name: result.name,
      taxNo: result.taxNo,
      requiresReview: result.requiresReview
    })
  }

  function handleCounterpartyCreated(
    result: Api.Fms.CreateInvoiceCounterpartyFromOcrResponse
  ): void {
    applyCounterparty(result.party)
    Object.assign(counterpartyResolution, {
      status: 'matched',
      message: result.created ? '往来单位已建档并自动带入' : '已复用现有往来单位并自动带入',
      artifactId: counterpartyResolution.artifactId,
      result: {
        ...(counterpartyResolution.result as Api.Fms.InvoiceCounterpartyResolution),
        status: 'matched',
        canCreate: false,
        matchMethod: result.created ? null : 'name',
        party: result.party,
        message: result.created ? '往来单位已建档并自动带入' : '已复用现有往来单位并自动带入'
      }
    } satisfies CounterpartyResolutionGroup)
  }

  function retryCounterpartyResolution(): void {
    if (!counterpartyResolution.artifactId) return
    void resolveRecognizedCounterparty(counterpartyResolution.artifactId)
  }

  async function loadDetail(id: string): Promise<void> {
    const { data } = await fetchInvoiceDetail(id)
    if (!data) return
    const links = data.statementLinks ?? []
    const counterpartyId = data.direction === 'output' ? data.customerId : data.carrierId
    const linkAmounts = Object.fromEntries(
      links.map((item) => [item.statementId, Number(item.linkedAmount)])
    )
    replaceForm({
      id: data.id,
      invoiceRecordNo: data.invoiceRecordNo,
      direction: data.direction,
      counterpartyId: counterpartyId ?? '',
      invoiceType: data.invoiceType,
      invoiceTitle: data.invoiceTitle ?? '',
      taxNumber: data.taxNumber ?? '',
      invoiceCode: data.invoiceCode ?? '',
      invoiceNo: data.invoiceNo ?? '',
      issueDate: data.issueDate,
      taxRate: Number(data.taxRate),
      amountExcludingTax: Number(data.amountExcludingTax),
      taxAmount: Number(data.taxAmount),
      totalAmount: Number(data.totalAmount),
      statementIds: links.map((item) => item.statementId),
      attachments: data.attachments ?? [],
      remark: data.remark ?? ''
    })
    selection.parties = [
      {
        id: counterpartyId,
        partyName: data.counterpartyNameSnapshot,
        partyCode: data.taxNumber ?? ''
      }
    ]
    selection.originalLinkAmounts = { ...linkAmounts }
    selection.linkAmounts = { ...linkAmounts }
    selection.statements = links.map((item) => ({
      ...item,
      statementId: item.statementId,
      uninvoicedAmount: 0,
      periodLabel: `${item.periodStart} 至 ${item.periodEnd}`
    }))
  }

  async function handleSubmit(): Promise<boolean> {
    form.data.invoiceNo = normalizeInvoiceNo(form.data.invoiceNo)
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    const activeDuplicate = (await checkDuplicateInvoice()) ?? ocrSourceDuplicateInvoice.value
    const shouldMergeDuplicate =
      Boolean(ocrArtifactId.value) && !form.data.id && activeDuplicate?.status === 'draft'
    if (activeDuplicate && !shouldMergeDuplicate) {
      ElMessage.warning('该发票号码已登记，请处理已有记录或修改票号')
      return false
    }

    let statementLinks = selection.statements.map((row) => ({
      statementId: String(row.statementId),
      linkedAmount: Number(selection.linkAmounts[String(row.statementId)] ?? 0)
    }))
    if (shouldMergeDuplicate && activeDuplicate && !statementLinks.length) {
      const { data: existingInvoice } = await fetchInvoiceDetail(activeDuplicate.id)
      if (!existingInvoice) {
        ElMessage.error('已有草稿读取失败，为避免覆盖原有关联，本次未保存')
        return false
      }
      statementLinks = (existingInvoice.statementLinks ?? []).map((item) => ({
        statementId: item.statementId,
        linkedAmount: Number(item.linkedAmount)
      }))
    }
    if (statementLinks.some((item) => item.linkedAmount <= 0)) return false
    const linkedAmountTotal = statementLinks.reduce((total, item) => total + item.linkedAmount, 0)
    if (linkedAmountTotal > form.data.totalAmount + 0.01) {
      ElMessage.warning('关联对账金额不能超过发票价税合计')
      return false
    }

    const payload = buildInvoicePayload({
      form: form.data,
      statementLinks,
      duplicate: activeDuplicate,
      mergeDuplicate: shouldMergeDuplicate
    })

    try {
      const { data: savedInvoiceId } = await saveInvoice(payload)
      form.data.id = savedInvoiceId ?? payload.id ?? undefined
      await recordInvoiceOcrReview(savedInvoiceId ?? form.data.id)
      ElMessage.success(
        shouldMergeDuplicate
          ? `已归并更新草稿 ${activeDuplicate?.invoiceRecordNo ?? ''}`
          : '发票草稿保存成功'
      )
      emit('success')
      return true
    } catch (error) {
      if (isInvoiceLegalNumberConflict(error)) {
        await checkDuplicateInvoice()
        ElMessage.warning('该发票号码刚刚被登记，请核对已有记录后再保存')
        return false
      }
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '发票保存失败，请稍后重试'))
      return false
    }
  }

  async function recordInvoiceOcrReview(invoiceId?: string): Promise<void> {
    if (!ocrArtifactId.value || !invoiceId) return
    const finalPayload = {
      invoiceType: form.data.invoiceType,
      invoiceTitle: form.data.invoiceTitle.trim() || null,
      taxNumber: form.data.taxNumber.trim() || null,
      invoiceCode: form.data.invoiceCode.trim() || null,
      invoiceNo: form.data.invoiceNo.trim() || null,
      issueDate: form.data.issueDate,
      taxRate: Number(form.data.taxRate),
      amountExcludingTax: Number(form.data.amountExcludingTax),
      taxAmount: Number(form.data.taxAmount),
      totalAmount: Number(form.data.totalAmount)
    }
    const { error } = await reviewInvoiceOcrArtifact({
      action: 'review',
      artifactId: ocrArtifactId.value,
      entityId: invoiceId,
      outcome: 'applied',
      finalPayload
    })
    if (error) {
      ElMessage.warning('发票已保存，但 AI 识别质量记录失败；不影响正式数据')
      return
    }
    ocrArtifactId.value = undefined
  }

  async function handleOpen(row?: Invoice, ocrContext?: InvoiceOcrContext): Promise<void> {
    await Promise.all([resetForm(), invoiceRecordNumber.loadRule()])
    if (ocrContext) form.data.direction = ocrContext.direction
    await dialogRef.value?.handleOpen(row, {
      title: row ? '编辑发票' : ocrContext ? '复核识别发票' : '登记发票',
      subtitle: ocrContext
        ? '识别结果已恢复，请重点核对低置信字段、往来单位和金额勾稽关系'
        : '发票可以关联一个或多个已确认对账单，未关联金额会进入财务工作台待办',
      confirmText: row ? '保存修改' : '保存草稿',
      contentMaxHeight: '76vh',
      loading: Boolean(row),
      onOpen: async (_data, api) => {
        if (ocrContext) {
          await handleApplyOcrResult(ocrContext.result)
          return
        }
        if (!row) return
        try {
          await loadDetail(row.id)
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  function handleOpenFromOcr(
    result: Api.Fms.InvoiceOcrAnalyzeResponse,
    direction: Api.Fms.InvoiceDirection
  ): Promise<void> {
    return handleOpen(undefined, { result, direction })
  }

  async function handleOpenFromArtifact(artifactId: string): Promise<boolean> {
    let restored = false
    let closeAfterLoad = false

    await dialogRef.value?.handleOpen(undefined, {
      title: '复核识别发票',
      subtitle: '正在恢复识别结果与原始票据，请稍候',
      confirmText: '保存草稿',
      contentMaxHeight: '76vh',
      loading: true,
      loadingText: '正在恢复识别结果…',
      onOpen: async (_data, api) => {
        try {
          await Promise.all([resetForm(), invoiceRecordNumber.loadRule()])
          const { data, error } = await fetchRecognitionArtifactDetail(artifactId)
          if (error || !data || data.feature !== 'invoice_ocr') {
            ElMessage.error('识别任务恢复失败，请返回待复核后重试')
            closeAfterLoad = true
            return
          }
          if (data.status !== 'pending') {
            ElMessage.info('该识别任务已处理，已为你保留发票台账页面')
            closeAfterLoad = true
            return
          }

          form.data.direction = data.metadata?.direction === 'input' ? 'input' : 'output'
          const retainedImageUrls = data.metadata?.imageUrls
          if (Array.isArray(retainedImageUrls)) {
            attachmentUrls.value = retainedImageUrls.filter(
              (url): url is string => typeof url === 'string' && /^https?:\/\//i.test(url)
            )
          }
          await handleApplyOcrResult(toInvoiceOcrAnalyzeResponse(data))
          api.setOptions({
            subtitle: '识别结果已恢复，请重点核对低置信字段、往来单位和金额勾稽关系'
          })
          restored = true
        } catch {
          ElMessage.error('识别任务恢复失败，请返回待复核后重试')
          closeAfterLoad = true
        } finally {
          api.setLoading(false)
          if (closeAfterLoad) await api.handleClose(true)
        }
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })

    return restored
  }

  defineExpose({ handleOpen, handleOpenFromOcr, handleOpenFromArtifact })
</script>

<style scoped lang="scss">
  .invoice-dialog {
    &__form {
      :deep(.el-input-number) {
        width: 100%;
      }
    }

    &__counterparty-field {
      display: grid;
      gap: 8px;
      min-width: 0;
    }

    &__counterparty-resolution {
      display: flex;
      gap: 8px;
      align-items: flex-start;
      min-width: 0;

      > .el-button {
        flex: 0 0 auto;
        height: 34px;
        margin-top: 1px;
      }
    }

    &__counterparty-alert {
      flex: 1;
      min-width: 0;
      padding: 7px 10px;

      :deep(.el-alert__icon) {
        width: 18px;
        margin-right: 8px;
        font-size: 16px;
      }

      :deep(.el-alert__content) {
        min-width: 0;
      }

      :deep(.el-alert__title) {
        font-size: 13px;
        font-weight: 600;
        line-height: 1.4;
      }

      :deep(.el-alert__description) {
        margin-top: 2px;
        font-size: 12px;
        line-height: 1.45;
      }
    }

    &__links {
      padding: 16px;
      margin-top: 16px;
    }

    &__feedback-stack {
      display: grid;
      gap: 12px;
      margin-top: 16px;
    }

    &__notice {
      :deep(.el-alert__title) {
        font-weight: 650;
      }

      :deep(.el-alert__description) {
        line-height: 1.55;
      }
    }

    &__checking {
      padding: 9px 12px;
      font-size: 13px;
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-lighter);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: 8px;
    }

    @media (width <= 768px) {
      &__counterparty-resolution {
        flex-direction: column;

        > .el-button {
          width: 100%;
        }
      }
    }
  }
</style>
