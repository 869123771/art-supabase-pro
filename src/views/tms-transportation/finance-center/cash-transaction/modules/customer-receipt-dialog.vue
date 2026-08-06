<template>
  <ArtDialog ref="dialogRef" size="xl">
    <CashVoucherOcrPanel
      v-if="dialog.mode === 'create'"
      ref="ocrPanelRef"
      v-model="form.data.voucherUrls"
      direction="receipt"
      @apply="handleApplyOcrResult"
    />
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="12"
      :gutter="20"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #customerId>
        <ArtTableSingleSelect
          v-model="form.data.customerId"
          v-model:selected-data="selection.customers"
          :api-fn="fetchCustomerSelectorData"
          :columns="customerColumns"
          title="选择收款客户"
          subtitle="收款客户必须与待核销客户对账单一致"
          row-key="id"
          label-key="customerName"
          description-key="customerCode"
          placeholder="请选择收款客户"
          search-placeholder="客户名称、编码、联系人或电话"
          dialog-width="lg"
          show-pagination
          :page-size="10"
          :disabled="dialog.mode === 'allocate'"
          @change="handleCustomerChange"
        />
      </template>

      <template #statementIds>
        <div class="receipt-allocation">
          <ArtTableMultipleSelect
            ref="statementSelectRef"
            v-model="form.data.statementIds"
            v-model:selected-data="selection.statements"
            :api-fn="fetchStatementSelectorData"
            :columns="statementSelectorColumns"
            title="选择待核销客户对账单"
            subtitle="仅显示该客户已确认且仍有未结金额的对账单"
            row-key="id"
            label-key="statementNo"
            description-key="periodLabel"
            placeholder="可暂不核销，后续再分配收款"
            search-placeholder="对账单号或客户名称"
            dialog-width="xl"
            show-pagination
            show-selected-panel
            :page-size="10"
            :disabled="!form.data.customerId"
            @change="handleStatementChange"
          />

          <div v-if="allocationRows.length" class="receipt-allocation__selected">
            <div class="receipt-allocation__header">
              <ArtSectionTitle :show-line="false">本次核销分配</ArtSectionTitle>
              <ElButton type="primary" plain @click="autoAllocate">自动分配</ElButton>
            </div>
            <ArtTable
              :data="allocationRows"
              :columns="allocationColumns"
              :pagination="false"
              :show-table-header="false"
              max-height="260px"
              border
            />
          </div>

          <ElAlert
            class="receipt-allocation__summary"
            :type="allocationSummary.remaining >= 0 ? 'success' : 'error'"
            :closable="false"
            show-icon
            :title="allocationSummaryText"
          />
        </div>
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import { ElInputNumber, type FormRules } from 'element-plus'
  import { round, toNumber } from 'lodash-es'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
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
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    allocateCustomerReceipt,
    createCustomerReceipt,
    fetchCustomerSelectorList,
    fetchCustomerStatementAllocatableList,
    reviewCashVoucherOcrArtifact
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import CashVoucherOcrPanel from './cash-voucher-ocr-panel.vue'

  defineOptions({ name: 'TmsCustomerReceiptDialog' })

  type CashTransaction = Api.Tms.Finance.CashTransactionRecord
  type AllocatableStatement = Api.Tms.Finance.CustomerStatementAllocatable
  type AllocationRow = AllocatableStatement & { allocationAmount: number }
  type DialogMode = 'create' | 'allocate'

  interface ReceiptForm {
    customerId: string
    transactionDate: string
    amount: number | undefined
    paymentMethod: Api.Tms.Finance.CashPaymentMethod
    bankReference: string
    voucherUrls: string[]
    statementIds: string[]
    remark: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: ReceiptForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<ReceiptForm>
  }

  interface DialogGroup {
    mode: DialogMode
    transaction?: CashTransaction
  }

  interface SelectionGroup {
    customers: DataSelectRecord[]
    statements: DataSelectRecord[]
    allocationAmounts: Record<string, number>
  }

  interface OcrPanelExpose {
    reset: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<FormExpose>()
  const statementSelectRef = ref<ArtDataSelectExpose>()
  const ocrPanelRef = ref<OcrPanelExpose>()
  const ocrResult = ref<Api.Tms.Finance.CashVoucherOcrAnalyzeResponse>()

  const dialog = reactive<DialogGroup>({ mode: 'create', transaction: undefined })
  const selection = reactive<SelectionGroup>({
    customers: [],
    statements: [],
    allocationAmounts: {}
  })

  const createInitialForm = (): ReceiptForm => ({
    customerId: '',
    transactionDate: dayjs().format('YYYY-MM-DD'),
    amount: undefined,
    paymentMethod: 'bank_transfer',
    bankReference: '',
    voucherUrls: [],
    statementIds: [],
    remark: ''
  })

  const moneyProps = {
    min: 0.01,
    precision: 2,
    controlsPosition: 'right' as const,
    class: '!w-full'
  }

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      customerId: [{ required: true, message: '请选择收款客户', trigger: 'change' }],
      transactionDate: [{ required: true, message: '请选择收款日期', trigger: 'change' }],
      amount: [
        { required: true, message: '请输入收款金额', trigger: 'blur' },
        {
          validator: (_rule, value, callback) =>
            numericValue(value) > 0 ? callback() : callback(new Error('收款金额必须大于 0')),
          trigger: 'blur'
        }
      ],
      paymentMethod: [{ required: true, message: '请选择收款方式', trigger: 'change' }],
      bankReference: [{ max: 120, message: '银行流水号不能超过 120 个字符', trigger: 'blur' }],
      remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
    },
    items: computed<FormItem[]>(() => {
      const baseItems: FormItem[] = [
        { label: '收款信息', key: 'baseSection', type: 'divider', span: 24 },
        { label: '收款客户', key: 'customerId', type: 'input', span: 12 },
        {
          label: '收款日期',
          key: 'transactionDate',
          type: 'date',
          span: 12,
          props: {
            valueFormat: 'YYYY-MM-DD',
            placeholder: '请选择收款日期',
            class: '!w-full',
            disabled: dialog.mode === 'allocate'
          }
        },
        {
          label: dialog.mode === 'allocate' ? '收款总额' : '收款金额',
          key: 'amount',
          type: 'number',
          span: 12,
          props: { ...moneyProps, disabled: dialog.mode === 'allocate' }
        },
        {
          label: '收款方式',
          key: 'paymentMethod',
          type: 'select',
          span: 12,
          props: {
            options: getDictMap.value.tmsCashPaymentMethod ?? [],
            disabled: dialog.mode === 'allocate'
          }
        }
      ]

      if (dialog.mode === 'create') {
        baseItems.push(
          {
            label: '银行流水号',
            key: 'bankReference',
            type: 'input',
            span: 12,
            props: { placeholder: '选填，可用于检索和对账' }
          },
          {
            label: '收款备注',
            key: 'remark',
            type: 'input',
            span: 24,
            props: {
              type: 'textarea',
              rows: 2,
              maxlength: 500,
              showWordLimit: true,
              placeholder: '选填，可记录付款账户、业务说明等'
            }
          }
        )
      }

      baseItems.push(
        { label: '核销信息', key: 'allocationSection', type: 'divider', span: 24 },
        { label: '客户对账单', key: 'statementIds', type: 'input', span: 24 }
      )
      return baseItems
    })
  })

  const allocationLimit = computed(() =>
    round(
      dialog.mode === 'allocate'
        ? numericValue(dialog.transaction?.unallocatedAmount)
        : numericValue(form.data.amount),
      2
    )
  )

  const selectedStatements = computed<AllocatableStatement[]>(() =>
    selection.statements.map((item) => item as AllocatableStatement)
  )

  const allocationRows = computed<AllocationRow[]>(() =>
    selectedStatements.value.map((item) => ({
      ...item,
      allocationAmount: numericValue(selection.allocationAmounts[item.id])
    }))
  )

  const allocationSummary = computed(() => {
    const allocated = round(
      allocationRows.value.reduce((total, row) => total + numericValue(row.allocationAmount), 0),
      2
    )
    return {
      limit: allocationLimit.value,
      allocated,
      remaining: round(allocationLimit.value - allocated, 2)
    }
  })

  const allocationSummaryText = computed(() => {
    const { allocated, limit, remaining } = allocationSummary.value
    const prefix = allocationRows.value.length
      ? `已选 ${allocationRows.value.length} 份对账单`
      : '本次可以暂不选择对账单'
    return `${prefix}，可核销 ${formatMoney(limit)}，本次核销 ${formatMoney(allocated)}，剩余 ${formatMoney(remaining)}`
  })

  const customerColumns: DataSelectColumn[] = [
    { prop: 'customerCode', label: '客户编码', width: 145 },
    { prop: 'customerName', label: '客户名称', minWidth: 210 },
    { prop: 'contactName', label: '联系人', width: 120 },
    { prop: 'contactPhone', label: '联系电话', width: 145 },
    { prop: 'region', label: '所在区域', minWidth: 150 }
  ]

  const statementSelectorColumns: DataSelectColumn[] = [
    { prop: 'statementNo', label: '对账单号', width: 190 },
    {
      prop: 'periodLabel',
      label: '对账账期',
      width: 205,
      formatter: (row) =>
        `${(row as AllocatableStatement).periodStart} 至 ${(row as AllocatableStatement).periodEnd}`
    },
    { prop: 'waybillCount', label: '运单数', width: 90, align: 'center' },
    {
      prop: 'statementAmount',
      label: '对账金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney((row as AllocatableStatement).statementAmount)
    },
    {
      prop: 'settledAmount',
      label: '已结金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney((row as AllocatableStatement).settledAmount)
    },
    {
      prop: 'outstandingAmount',
      label: '未结金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney((row as AllocatableStatement).outstandingAmount)
    }
  ]

  const allocationColumns: ColumnOption<AllocationRow>[] = [
    { prop: 'statementNo', label: '对账单号', width: 190 },
    {
      prop: 'period',
      label: '账期',
      minWidth: 190,
      formatter: (row) => `${row.periodStart} 至 ${row.periodEnd}`
    },
    {
      prop: 'outstandingAmount',
      label: '未结金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.outstandingAmount)
    },
    {
      prop: 'allocationAmount',
      label: '本次核销',
      width: 180,
      formatter: (row) =>
        h(ElInputNumber, {
          modelValue: numericValue(selection.allocationAmounts[row.id]),
          min: 0,
          max: Math.min(numericValue(row.outstandingAmount), allocationLimit.value),
          precision: 2,
          controlsPosition: 'right',
          class: 'w-full!',
          'onUpdate:modelValue': (value: number | undefined) => {
            selection.allocationAmounts[row.id] = round(numericValue(value), 2)
          }
        })
    }
  ]

  function numericValue(value?: number | string | null): number {
    const result = toNumber(value)
    return Number.isFinite(result) ? result : 0
  }

  function formatMoney(value?: number | null): string {
    return `¥${numericValue(value).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`
  }

  async function fetchCustomerSelectorData(params: DataSelectFetchParams) {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCustomerSelectorList({
      keyword: params.keyword,
      from,
      to
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  async function fetchStatementSelectorData(params: DataSelectFetchParams) {
    if (!form.data.customerId) return { data: [], total: 0 }
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCustomerStatementAllocatableList({
      customerId: form.data.customerId,
      keyword: params.keyword,
      from,
      to
    })
    const records = (data ?? []).map((item) => ({
      ...item,
      periodLabel: `${item.periodStart} 至 ${item.periodEnd}`
    }))
    return { data: records, total: total ?? 0 }
  }

  function clearStatementSelection(): void {
    form.data.statementIds = []
    selection.statements = []
    selection.allocationAmounts = {}
  }

  function handleApplyOcrResult(result: Api.Tms.Finance.CashVoucherOcrAnalyzeResponse): void {
    ocrResult.value = result
    const voucher = result.voucher
    Object.assign(form.data, {
      transactionDate: voucher.transactionDate || form.data.transactionDate,
      amount: voucher.amount ?? form.data.amount,
      paymentMethod: voucher.paymentMethod,
      bankReference: voucher.bankReference || form.data.bankReference
    })

    const topMatch = result.matches[0]
    if (topMatch) {
      form.data.customerId = topMatch.counterpartyId
      selection.customers = [
        {
          id: topMatch.counterpartyId,
          customerName: topMatch.counterpartyName,
          customerCode: 'AI 推荐'
        }
      ]
      applyRecommendedStatements(result.matches, topMatch.counterpartyId)
    }
    void nextTick(() => formRef.value?.clearValidate())
    ElMessage.success(
      topMatch ? '识别结果和推荐对账单已填入，请确认核销金额' : '识别结果已填入，请手工选择对账单'
    )
  }

  function applyRecommendedStatements(
    matches: Api.Tms.Finance.CashVoucherStatementMatch[],
    customerId: string
  ): void {
    clearStatementSelection()
    let remaining = numericValue(form.data.amount)
    const selected: DataSelectRecord[] = []
    for (const match of matches) {
      if (remaining <= 0 || match.counterpartyId !== customerId || match.score < 60) continue
      const allocation = round(Math.min(remaining, numericValue(match.outstandingAmount)), 2)
      if (allocation <= 0) continue
      remaining = round(remaining - allocation, 2)
      selection.allocationAmounts[match.statementId] = allocation
      selected.push({
        id: match.statementId,
        statementNo: match.statementNo,
        customerId: match.counterpartyId,
        customerName: match.counterpartyName,
        periodStart: match.periodStart,
        periodEnd: match.periodEnd,
        statementAmount: match.statementAmount,
        settledAmount: match.settledAmount,
        outstandingAmount: match.outstandingAmount,
        periodLabel: `${match.periodStart} 至 ${match.periodEnd}`
      })
    }
    selection.statements = selected
    form.data.statementIds = selected.map((item) => String(item.id))
  }

  function handleCustomerChange(): void {
    if (dialog.mode === 'allocate') return
    clearStatementSelection()
    void statementSelectRef.value?.reload()
  }

  function handleStatementChange(): void {
    const selectedIds = new Set(selection.statements.map((item) => String(item.id)))
    Object.keys(selection.allocationAmounts).forEach((id) => {
      if (!selectedIds.has(id)) delete selection.allocationAmounts[id]
    })
    autoAllocate()
  }

  function autoAllocate(): void {
    let remaining = allocationLimit.value
    selectedStatements.value.forEach((statement) => {
      const amount = round(Math.min(remaining, numericValue(statement.outstandingAmount)), 2)
      selection.allocationAmounts[statement.id] = Math.max(amount, 0)
      remaining = round(remaining - amount, 2)
    })
  }

  function buildAllocations(): Api.Tms.Finance.CashAllocationInput[] {
    return allocationRows.value
      .map((row) => ({
        statementId: row.id,
        amount: round(numericValue(selection.allocationAmounts[row.id]), 2)
      }))
      .filter((item) => item.amount > 0)
  }

  function validateAllocations(): boolean {
    if (allocationSummary.value.allocated > allocationLimit.value) {
      ElMessage.warning('核销合计不能超过本次可核销金额')
      return false
    }
    const invalidRow = allocationRows.value.find(
      (row) => numericValue(row.allocationAmount) > numericValue(row.outstandingAmount)
    )
    if (invalidRow) {
      ElMessage.warning(`对账单 ${invalidRow.statementNo} 的核销金额超过未结金额`)
      return false
    }
    if (dialog.mode === 'allocate' && !buildAllocations().length) {
      ElMessage.warning('请至少填写一条核销金额')
      return false
    }
    return true
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    if (!validateAllocations()) return false

    try {
      if (dialog.mode === 'allocate' && dialog.transaction) {
        await allocateCustomerReceipt({
          transactionId: dialog.transaction.id,
          allocations: buildAllocations()
        })
      } else {
        const { data: transactionId } = await createCustomerReceipt({
          customerId: form.data.customerId,
          transactionDate: form.data.transactionDate,
          amount: numericValue(form.data.amount),
          paymentMethod: form.data.paymentMethod,
          bankReference: form.data.bankReference.trim() || null,
          voucherUrls: [...form.data.voucherUrls],
          remark: form.data.remark.trim() || null,
          allocations: buildAllocations()
        })
        await recordOcrReview(transactionId)
      }
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function resetForm(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    dialog.transaction = undefined
    selection.customers = []
    clearStatementSelection()
    ocrResult.value = undefined
    ocrPanelRef.value?.reset()
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleOpen(transaction?: CashTransaction): Promise<void> {
    await resetForm()
    dialog.mode = transaction ? 'allocate' : 'create'
    dialog.transaction = transaction

    if (transaction) {
      Object.assign(form.data, {
        customerId: transaction.customerId ?? '',
        transactionDate: transaction.transactionDate,
        amount: transaction.amount,
        paymentMethod: transaction.paymentMethod,
        bankReference: transaction.bankReference ?? '',
        voucherUrls: [...(transaction.voucherUrls ?? [])]
      })
      selection.customers = [
        {
          id: transaction.customerId,
          customerName: transaction.counterpartyName,
          customerCode: transaction.transactionNo
        }
      ]
    }

    await dialogRef.value?.handleOpen(undefined, {
      title: transaction ? `继续核销 · ${transaction.transactionNo}` : '登记客户收款',
      subtitle: transaction
        ? `本笔收款尚有 ${formatMoney(transaction.unallocatedAmount)} 未核销`
        : '登记客户实际到账流水，可同时核销一份或多份已确认对账单',
      confirmText: transaction ? '确认核销' : '登记收款',
      contentMaxHeight: '76vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })

  async function recordOcrReview(transactionId?: string | null): Promise<void> {
    if (!ocrResult.value || !transactionId) return
    const { error } = await reviewCashVoucherOcrArtifact({
      action: 'review',
      artifactId: ocrResult.value.artifactId,
      entityId: transactionId,
      outcome: 'applied',
      finalPayload: {
        payerName: selection.customers[0]?.customerName ?? null,
        payeeName: ocrResult.value.voucher.payeeName,
        transactionDate: form.data.transactionDate,
        amount: numericValue(form.data.amount),
        bankReference: form.data.bankReference.trim() || null,
        paymentMethod: form.data.paymentMethod,
        statementIds: [...form.data.statementIds]
      }
    })
    if (error) ElMessage.warning('收款已登记，但 AI 质量记录失败；不影响正式业务数据')
  }
</script>

<style scoped lang="scss">
  .receipt-allocation {
    width: 100%;

    &__selected {
      margin-top: 16px;
    }

    &__header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 10px;
    }

    &__summary {
      margin-top: 12px;
    }
  }
</style>
