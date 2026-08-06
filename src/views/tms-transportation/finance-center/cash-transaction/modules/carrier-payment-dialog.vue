<template>
  <ArtDialog ref="dialogRef" size="xl">
    <CashVoucherOcrPanel
      v-if="dialog.mode === 'create'"
      ref="ocrPanelRef"
      v-model="form.voucherUrls"
      direction="payment"
      @apply="handleApplyOcrResult"
    />
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #carrierId>
        <ArtTableSingleSelect
          v-model="form.carrierId"
          v-model:selected-data="selection.carriers"
          :api-fn="fetchCarrierSelectorData"
          :columns="carrierColumns"
          title="选择付款承运商"
          subtitle="付款和应付对账单必须属于同一承运商"
          row-key="id"
          label-key="companyName"
          description-key="carrierCode"
          placeholder="请选择承运商"
          search-placeholder="承运商名称、编码或联系人"
          dialog-width="lg"
          :disabled="dialog.mode === 'allocate'"
          @change="handleCarrierChange"
        />
      </template>
      <template #statementIds>
        <ArtTableMultipleSelect
          ref="statementSelectRef"
          v-model="form.statementIds"
          v-model:selected-data="selection.statements"
          :api-fn="fetchStatementSelectorData"
          :columns="statementSelectorColumns"
          title="选择待核销承运商对账单"
          subtitle="仅显示该承运商已确认、且仍有未付金额的对账单"
          row-key="id"
          label-key="statementNo"
          description-key="periodLabel"
          placeholder="可选择一份或多份对账单"
          search-placeholder="对账单号或承运商名称"
          dialog-width="xl"
          show-pagination
          show-selected-panel
          :page-size="10"
          :disabled="!form.carrierId"
          @change="handleStatementChange"
        />
      </template>
    </ArtForm>
    <div v-if="allocationRows.length" class="payment-allocation">
      <div class="payment-allocation__header"
        ><span>核销明细</span
        ><ElButton link type="primary" @click="autoAllocate">按未付金额自动分配</ElButton></div
      >
      <ArtTable
        :data="allocationRows"
        :columns="allocationColumns"
        :pagination="false"
        :show-table-header="false"
        max-height="300px"
        border
      />
    </div>
    <ElAlert
      class="mt-4"
      :type="allocationSummary.allocated > allocationSummary.limit ? 'error' : 'info'"
      :closable="false"
      show-icon
      :title="summaryText"
    />
  </ArtDialog>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import { ElInputNumber, ElMessage, type FormRules } from 'element-plus'
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
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    allocateCarrierPayment,
    createCarrierPayment,
    fetchCarrierOptions,
    fetchCarrierStatementAllocatableList,
    reviewCashVoucherOcrArtifact
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import CashVoucherOcrPanel from './cash-voucher-ocr-panel.vue'

  defineOptions({ name: 'TmsCarrierPaymentDialog' })
  type CashTransaction = Api.Tms.Finance.CashTransactionRecord
  type Statement = Api.Tms.Finance.CarrierStatementAllocatable
  interface PaymentForm {
    carrierId: string
    transactionDate: string
    amount: number
    paymentMethod: Api.Tms.Finance.CashPaymentMethod
    bankReference: string
    remark: string
    statementIds: string[]
    voucherUrls: string[]
  }
  interface AllocationRow extends Statement {
    allocationAmount: number
  }
  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
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
  const dialog = reactive<{ mode: 'create' | 'allocate'; transaction?: CashTransaction }>({
    mode: 'create'
  })
  const selection = reactive<{
    carriers: DataSelectRecord[]
    statements: DataSelectRecord[]
    amounts: Record<string, number>
  }>({ carriers: [], statements: [], amounts: {} })
  const initialForm = (): PaymentForm => ({
    carrierId: '',
    transactionDate: dayjs().format('YYYY-MM-DD'),
    amount: 0,
    paymentMethod: 'bank_transfer',
    bankReference: '',
    remark: '',
    statementIds: [],
    voucherUrls: []
  })
  const form = reactive<PaymentForm>(initialForm())

  const limit = computed(() =>
    round(
      dialog.mode === 'allocate'
        ? Number(dialog.transaction?.unallocatedAmount ?? 0)
        : Number(form.amount || 0)
    )
  )
  const selectedStatements = computed(() => selection.statements as Statement[])
  const allocationRows = computed<AllocationRow[]>(() =>
    selectedStatements.value.map((item) => ({
      ...item,
      allocationAmount: Number(selection.amounts[item.id] ?? 0)
    }))
  )
  const allocationSummary = computed(() => {
    const allocated = round(
      allocationRows.value.reduce((sum, row) => sum + Number(row.allocationAmount || 0), 0)
    )
    return { allocated, limit: limit.value, remaining: round(limit.value - allocated) }
  })
  const summaryText = computed(
    () =>
      `可核销 ${money(allocationSummary.value.limit)}，本次核销 ${money(allocationSummary.value.allocated)}，剩余 ${money(allocationSummary.value.remaining)}`
  )
  const round = (value: number) => Math.round((value + Number.EPSILON) * 100) / 100
  const money = (value: number) =>
    `¥${Number(value || 0).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

  const carrierColumns: DataSelectColumn[] = [
    { prop: 'carrierCode', label: '承运商编码', width: 150 },
    { prop: 'companyName', label: '承运商名称', minWidth: 240 },
    { prop: 'contactName', label: '联系人', width: 120 },
    { prop: 'contactPhone', label: '联系电话', width: 150 }
  ]
  const statementSelectorColumns: DataSelectColumn[] = [
    { prop: 'statementNo', label: '对账单号', width: 190 },
    { prop: 'periodLabel', label: '对账账期', width: 205 },
    { prop: 'costCount', label: '费用数', width: 90 },
    {
      prop: 'statementAmount',
      label: '应付金额',
      width: 130,
      align: 'right',
      formatter: (r) => money(Number((r as Statement).statementAmount))
    },
    {
      prop: 'settledAmount',
      label: '已付金额',
      width: 130,
      align: 'right',
      formatter: (r) => money(Number((r as Statement).settledAmount))
    },
    {
      prop: 'outstandingAmount',
      label: '未付金额',
      width: 130,
      align: 'right',
      formatter: (r) => money(Number((r as Statement).outstandingAmount))
    }
  ]
  const allocationColumns: ColumnOption<AllocationRow>[] = [
    { prop: 'statementNo', label: '对账单号', width: 190 },
    {
      prop: 'period',
      label: '账期',
      minWidth: 190,
      formatter: (r) => `${r.periodStart} 至 ${r.periodEnd}`
    },
    {
      prop: 'outstandingAmount',
      label: '未付金额',
      width: 130,
      align: 'right',
      formatter: (r) => money(r.outstandingAmount)
    },
    {
      prop: 'allocationAmount',
      label: '本次核销',
      width: 180,
      formatter: (r) => (
        <ElInputNumber
          modelValue={Number(selection.amounts[r.id] ?? 0)}
          min={0}
          max={Math.min(Number(r.outstandingAmount), limit.value)}
          precision={2}
          controlsPosition="right"
          class="w-full!"
          onUpdate:modelValue={(v) => {
            selection.amounts[r.id] = round(Number(v ?? 0))
          }}
        />
      )
    }
  ]

  const formRules: FormRules<PaymentForm> = {
    carrierId: [{ required: true, message: '请选择付款承运商', trigger: 'change' }],
    transactionDate: [{ required: true, message: '请选择付款日期', trigger: 'change' }],
    amount: [
      {
        validator: (_r, v, cb) => (Number(v) > 0 ? cb() : cb(new Error('付款金额必须大于 0'))),
        trigger: 'change'
      }
    ],
    paymentMethod: [{ required: true, message: '请选择付款方式', trigger: 'change' }]
  }
  const formItems = computed<FormItem[]>(() => [
    { label: '付款信息', key: 'base', type: 'divider', span: 24 },
    { label: '付款承运商', key: 'carrierId', type: 'input', span: 12 },
    {
      label: '付款日期',
      key: 'transactionDate',
      type: 'date',
      span: 12,
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full', disabled: dialog.mode === 'allocate' }
    },
    {
      label: '付款金额',
      key: 'amount',
      type: 'number',
      span: 12,
      props: {
        min: 0.01,
        precision: 2,
        controlsPosition: 'right',
        class: '!w-full',
        disabled: dialog.mode === 'allocate',
        onChange: autoAllocate
      }
    },
    {
      label: '付款方式',
      key: 'paymentMethod',
      type: 'select',
      span: 12,
      props: {
        options: getDictMap.value.tmsCashPaymentMethod ?? [],
        disabled: dialog.mode === 'allocate'
      }
    },
    {
      label: '银行流水号',
      key: 'bankReference',
      type: 'input',
      span: 12,
      props: { disabled: dialog.mode === 'allocate', placeholder: '选填' }
    },
    {
      label: '付款备注',
      key: 'remark',
      type: 'input',
      span: 12,
      props: { disabled: dialog.mode === 'allocate', maxlength: 500, placeholder: '选填' }
    },
    { label: '核销信息', key: 'allocation', type: 'divider', span: 24 },
    { label: '承运商对账单', key: 'statementIds', type: 'input', span: 24 }
  ])

  async function fetchCarrierSelectorData(params: DataSelectFetchParams) {
    const { data } = await fetchCarrierOptions({ companyName: params.keyword })
    return { data: data ?? [], total: data?.length ?? 0 }
  }
  async function fetchStatementSelectorData(params: DataSelectFetchParams) {
    if (!form.carrierId) return { data: [], total: 0 }
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCarrierStatementAllocatableList({
      carrierId: form.carrierId,
      keyword: params.keyword,
      from,
      to
    })
    return {
      data: (data ?? []).map((item) => ({
        ...item,
        periodLabel: `${item.periodStart} 至 ${item.periodEnd}`
      })),
      total: total ?? 0
    }
  }
  function clearStatements() {
    form.statementIds = []
    selection.statements = []
    selection.amounts = {}
  }
  function handleApplyOcrResult(result: Api.Tms.Finance.CashVoucherOcrAnalyzeResponse) {
    ocrResult.value = result
    const voucher = result.voucher
    Object.assign(form, {
      transactionDate: voucher.transactionDate || form.transactionDate,
      amount: voucher.amount ?? form.amount,
      paymentMethod: voucher.paymentMethod,
      bankReference: voucher.bankReference || form.bankReference
    })
    const topMatch = result.matches[0]
    if (topMatch) {
      form.carrierId = topMatch.counterpartyId
      selection.carriers = [
        {
          id: topMatch.counterpartyId,
          companyName: topMatch.counterpartyName,
          carrierCode: 'AI 推荐'
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
    carrierId: string
  ) {
    clearStatements()
    let remaining = Number(form.amount || 0)
    const selected: DataSelectRecord[] = []
    for (const match of matches) {
      if (remaining <= 0 || match.counterpartyId !== carrierId || match.score < 60) continue
      const allocation = round(Math.min(remaining, Number(match.outstandingAmount || 0)))
      if (allocation <= 0) continue
      remaining = round(remaining - allocation)
      selection.amounts[match.statementId] = allocation
      selected.push({
        id: match.statementId,
        statementNo: match.statementNo,
        carrierId: match.counterpartyId,
        carrierName: match.counterpartyName,
        periodStart: match.periodStart,
        periodEnd: match.periodEnd,
        statementAmount: match.statementAmount,
        settledAmount: match.settledAmount,
        outstandingAmount: match.outstandingAmount,
        periodLabel: `${match.periodStart} 至 ${match.periodEnd}`
      })
    }
    selection.statements = selected
    form.statementIds = selected.map((item) => String(item.id))
  }
  function handleCarrierChange() {
    if (dialog.mode === 'allocate') return
    clearStatements()
    void statementSelectRef.value?.reload()
  }
  function handleStatementChange() {
    const ids = new Set(selection.statements.map((x) => String(x.id)))
    Object.keys(selection.amounts).forEach((id) => {
      if (!ids.has(id)) delete selection.amounts[id]
    })
    autoAllocate()
  }
  function autoAllocate() {
    let remaining = limit.value
    selectedStatements.value.forEach((s) => {
      const amount = round(Math.min(remaining, Number(s.outstandingAmount)))
      selection.amounts[s.id] = Math.max(amount, 0)
      remaining = round(remaining - amount)
    })
  }
  function allocations() {
    return allocationRows.value
      .map((r) => ({ statementId: r.id, amount: round(Number(selection.amounts[r.id] ?? 0)) }))
      .filter((x) => x.amount > 0)
  }
  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    if (allocationSummary.value.allocated > limit.value) {
      ElMessage.warning('核销合计不能超过可核销金额')
      return false
    }
    if (dialog.mode === 'allocate' && !allocations().length) {
      ElMessage.warning('请至少填写一条核销金额')
      return false
    }
    try {
      if (dialog.mode === 'allocate' && dialog.transaction)
        await allocateCarrierPayment({
          transactionId: dialog.transaction.id,
          allocations: allocations()
        })
      else {
        const { data: transactionId } = await createCarrierPayment({
          carrierId: form.carrierId,
          transactionDate: form.transactionDate,
          amount: Number(form.amount),
          paymentMethod: form.paymentMethod,
          bankReference: form.bankReference.trim() || null,
          voucherUrls: [...form.voucherUrls],
          remark: form.remark.trim() || null,
          allocations: allocations()
        })
        await recordOcrReview(transactionId)
      }
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function resetForm() {
    Object.assign(form, initialForm())
    dialog.transaction = undefined
    selection.carriers = []
    clearStatements()
    ocrResult.value = undefined
    ocrPanelRef.value?.reset()
    await nextTick()
    formRef.value?.clearValidate()
  }
  async function handleOpen(transaction?: CashTransaction) {
    await resetForm()
    dialog.mode = transaction ? 'allocate' : 'create'
    dialog.transaction = transaction
    if (transaction) {
      Object.assign(form, {
        carrierId: transaction.carrierId ?? '',
        transactionDate: transaction.transactionDate,
        amount: transaction.amount,
        paymentMethod: transaction.paymentMethod,
        bankReference: transaction.bankReference ?? '',
        voucherUrls: [...(transaction.voucherUrls ?? [])]
      })
      selection.carriers = [
        {
          id: transaction.carrierId,
          companyName: transaction.counterpartyName,
          carrierCode: transaction.transactionNo
        }
      ]
    }
    await dialogRef.value?.handleOpen(undefined, {
      title: transaction ? `继续核销 · ${transaction.transactionNo}` : '登记承运商付款',
      subtitle: transaction
        ? `本笔付款尚有 ${money(transaction.unallocatedAmount)} 未核销`
        : '登记实际付款流水，可同时核销一份或多份已确认承运商对账单',
      confirmText: transaction ? '确认核销' : '登记付款',
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
        payerName: ocrResult.value.voucher.payerName,
        payeeName: selection.carriers[0]?.companyName ?? null,
        transactionDate: form.transactionDate,
        amount: Number(form.amount),
        bankReference: form.bankReference.trim() || null,
        paymentMethod: form.paymentMethod,
        statementIds: [...form.statementIds]
      }
    })
    if (error) ElMessage.warning('付款已登记，但 AI 质量记录失败；不影响正式业务数据')
  }
</script>

<style scoped lang="scss">
  .payment-allocation {
    margin-top: 16px;

    &__header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 10px;
      font-weight: 600;
    }
  }
</style>
