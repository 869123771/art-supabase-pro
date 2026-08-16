<template>
  <ArtDialog ref="dialogRef" size="xl">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="isCompact ? 24 : 12"
      :gutter="20"
      label-width="108px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #carrierId>
        <ArtTableSingleSelect
          v-model="form.data.carrierId"
          v-model:selected-data="selection.carriers"
          :api-fn="fetchCarrierSelectorData"
          :columns="carrierColumns"
          title="选择付款承运商"
          subtitle="付款申请与应付对账单必须属于同一承运商"
          row-key="id"
          label-key="companyName"
          description-key="carrierCode"
          placeholder="请选择承运商"
          search-placeholder="承运商名称、编码或联系人"
          dialog-width="lg"
          @change="handleCarrierChange"
        />
      </template>

      <template #statementIds>
        <ArtTableMultipleSelect
          ref="statementSelectRef"
          v-model="form.data.statementIds"
          v-model:selected-data="selection.statements"
          :api-fn="fetchStatementSelectorData"
          :columns="statementSelectorColumns"
          title="选择待付款承运商对账单"
          subtitle="可申请余额已扣除其他审批中和已批准待付款申请"
          row-key="id"
          label-key="statementNo"
          description-key="periodLabel"
          placeholder="请选择一份或多份对账单"
          search-placeholder="对账单号或承运商名称"
          dialog-width="xl"
          show-pagination
          show-selected-panel
          :page-size="10"
          :disabled="!form.data.carrierId"
          @change="handleStatementChange"
        />
      </template>

      <template #basisUrls>
        <ArtUploadImage
          v-model="form.data.basisUrls"
          title="付款依据"
          :size="84"
          :limit="5"
          multiple
        />
      </template>
    </ArtForm>

    <section v-if="allocationRows.length" class="payment-application-dialog__allocation">
      <div class="payment-application-dialog__allocation-header">
        <ArtSectionTitle :show-line="false">付款分配</ArtSectionTitle>
        <ElButton link type="primary" @click="autoAllocate">按可申请余额自动分配</ElButton>
      </div>
      <ArtTable
        :data="allocationRows"
        :columns="allocationColumns"
        :pagination="false"
        :show-table-header="false"
        table-layout="fixed"
        max-height="300px"
        border
      />
    </section>

    <ElAlert
      class="payment-application-dialog__summary"
      :type="allocationSummary.remaining === 0 ? 'success' : 'warning'"
      :closable="false"
      show-icon
      :title="summaryText"
    />
  </ArtDialog>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import type { ComputedRef } from 'vue'
  import { useMediaQuery } from '@vueuse/core'
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
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    fetchCarrierOptions,
    fetchCarrierPaymentApplicationDetail,
    fetchCarrierStatementAllocatableList,
    saveCarrierPaymentApplication
  } from '@/api/finance'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'

  defineOptions({ name: 'FinancePaymentApplicationDialog' })

  type Application = Api.Finance.CarrierPaymentApplicationRecord
  type Statement = Api.Finance.CarrierStatementAllocatable

  interface PaymentApplicationForm {
    id?: string
    applicationNo: string
    carrierId: string
    plannedPaymentDate: string
    amount: number
    paymentMethod: Api.Finance.CashPaymentMethod
    basisUrls: string[]
    remark: string
    statementIds: string[]
  }

  interface AllocationRow extends Statement {
    allocationAmount: number
  }

  interface FormGroup {
    data: PaymentApplicationForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<PaymentApplicationForm>
  }

  interface SelectionGroup {
    carriers: DataSelectRecord[]
    statements: DataSelectRecord[]
    amounts: Record<string, number>
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const isCompact = useMediaQuery('(max-width: 767px)')
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Application>>()
  const formRef = ref<FormExpose>()
  const statementSelectRef = ref<ArtDataSelectExpose>()
  const applicationNumber = useDocumentNumberRule('tms.carrier_payment_application')

  const createInitialForm = (): PaymentApplicationForm => ({
    id: undefined,
    applicationNo: '',
    carrierId: '',
    plannedPaymentDate: dayjs().format('YYYY-MM-DD'),
    amount: 0,
    paymentMethod: 'bank_transfer',
    basisUrls: [],
    remark: '',
    statementIds: []
  })

  const selection = reactive<SelectionGroup>({ carriers: [], statements: [], amounts: {} })
  const formData = reactive<PaymentApplicationForm>(createInitialForm())
  const form = reactive<FormGroup>({
    data: formData,
    rules: {
      applicationNo: [
        {
          validator: (_rule, value, callback) =>
            applicationNumber.manualRequired(Boolean(formData.id)) && !String(value || '').trim()
              ? callback(new Error('请输入付款申请号'))
              : callback(),
          trigger: 'blur'
        }
      ],
      carrierId: [{ required: true, message: '请选择付款承运商', trigger: 'change' }],
      plannedPaymentDate: [{ required: true, message: '请选择计划付款日期', trigger: 'change' }],
      amount: [
        {
          validator: (_rule, value, callback) =>
            Number(value) > 0 ? callback() : callback(new Error('申请付款金额必须大于 0')),
          trigger: 'change'
        }
      ],
      paymentMethod: [{ required: true, message: '请选择付款方式', trigger: 'change' }]
    },
    items: computed<FormItem[]>(() => [
      { label: '申请信息', key: 'base', type: 'divider', span: 24 },
      {
        label: '申请单号',
        key: 'applicationNo',
        type: 'input',
        span: isCompact.value ? 24 : 12,
        props: {
          maxlength: 50,
          ...applicationNumber.inputProps(Boolean(formData.id), '请输入付款申请号', true)
        },
        description: applicationNumber.description.value
      },
      { label: '付款承运商', key: 'carrierId', type: 'input', span: isCompact.value ? 24 : 12 },
      {
        label: '计划付款日期',
        key: 'plannedPaymentDate',
        type: 'date',
        span: isCompact.value ? 24 : 12,
        props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
      },
      {
        label: '申请付款金额',
        key: 'amount',
        type: 'number',
        span: isCompact.value ? 24 : 12,
        props: {
          min: 0.01,
          precision: 2,
          controlsPosition: 'right',
          class: '!w-full',
          onChange: autoAllocate
        }
      },
      {
        label: '计划付款方式',
        key: 'paymentMethod',
        type: 'select',
        span: isCompact.value ? 24 : 12,
        props: { options: getDictMap.value.tmsCashPaymentMethod ?? [] }
      },
      {
        label: '申请说明',
        key: 'remark',
        type: 'textarea',
        span: 24,
        props: {
          rows: 3,
          maxlength: 500,
          showWordLimit: true,
          placeholder: '说明付款用途、账期或其他审批要点'
        }
      },
      { label: '付款依据', key: 'evidence', type: 'divider', span: 24 },
      { label: '依据附件', key: 'basisUrls', type: 'input', span: 24 },
      { label: '应付核销', key: 'allocation', type: 'divider', span: 24 },
      { label: '承运商对账单', key: 'statementIds', type: 'input', span: 24 }
    ])
  })

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
    return {
      allocated,
      limit: round(Number(form.data.amount || 0)),
      remaining: round(Number(form.data.amount || 0) - allocated)
    }
  })
  const summaryText = computed(
    () =>
      `申请金额 ${money(allocationSummary.value.limit)}，已分配 ${money(allocationSummary.value.allocated)}，待分配 ${money(allocationSummary.value.remaining)}`
  )

  const carrierColumns: DataSelectColumn[] = [
    { prop: 'carrierCode', label: '承运商编码', width: 150 },
    { prop: 'companyName', label: '承运商名称', minWidth: 240 },
    { prop: 'contactName', label: '联系人', width: 120 },
    { prop: 'contactPhone', label: '联系电话', width: 150 }
  ]
  const statementSelectorColumns: DataSelectColumn[] = [
    { prop: 'statementNo', label: '对账单号', width: 190 },
    { prop: 'periodLabel', label: '对账账期', width: 205 },
    {
      prop: 'statementOutstandingAmount',
      label: '账面未付',
      width: 130,
      align: 'right',
      formatter: (row) => money(Number((row as Statement).statementOutstandingAmount ?? 0))
    },
    {
      prop: 'reservedAmount',
      label: '审批占用',
      width: 130,
      align: 'right',
      formatter: (row) => money(Number((row as Statement).reservedAmount ?? 0))
    },
    {
      prop: 'outstandingAmount',
      label: '可申请余额',
      width: 135,
      align: 'right',
      formatter: (row) => money(Number((row as Statement).outstandingAmount))
    }
  ]
  const allocationColumns: ColumnOption<AllocationRow>[] = [
    { prop: 'statementNo', label: '对账单号', width: 190 },
    {
      prop: 'period',
      label: '账期',
      minWidth: 190,
      formatter: (row) => (row.periodStart ? `${row.periodStart} 至 ${row.periodEnd}` : '--')
    },
    {
      prop: 'outstandingAmount',
      label: '可申请余额',
      width: 135,
      align: 'right',
      formatter: (row) => money(row.outstandingAmount)
    },
    {
      prop: 'allocationAmount',
      label: '本次申请',
      width: 180,
      formatter: (row) => (
        <ElInputNumber
          modelValue={Number(selection.amounts[row.id] ?? 0)}
          min={0}
          max={Math.min(Number(row.outstandingAmount), Number(form.data.amount || 0))}
          precision={2}
          controlsPosition="right"
          class="w-full!"
          onUpdate:modelValue={(value) => {
            selection.amounts[row.id] = round(Number(value ?? 0))
          }}
        />
      )
    }
  ]

  const round = (value: number): number =>
    Math.round((Number(value || 0) + Number.EPSILON) * 100) / 100
  const money = (value: number): string => formatCurrencyValue(value)

  async function fetchCarrierSelectorData(params: DataSelectFetchParams) {
    const { data } = await fetchCarrierOptions({ companyName: params.keyword })
    return { data: data ?? [], total: data?.length ?? 0 }
  }

  async function fetchStatementSelectorData(params: DataSelectFetchParams) {
    if (!form.data.carrierId) return { data: [], total: 0 }
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCarrierStatementAllocatableList({
      carrierId: form.data.carrierId,
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

  function clearStatements(): void {
    form.data.statementIds = []
    selection.statements = []
    selection.amounts = {}
  }

  function handleCarrierChange(): void {
    clearStatements()
    void statementSelectRef.value?.reload()
  }

  function handleStatementChange(): void {
    const ids = new Set(selection.statements.map((item) => String(item.id)))
    Object.keys(selection.amounts).forEach((id) => {
      if (!ids.has(id)) delete selection.amounts[id]
    })
    autoAllocate()
  }

  function autoAllocate(): void {
    let remaining = round(Number(form.data.amount || 0))
    selectedStatements.value.forEach((statement) => {
      const amount = round(Math.min(remaining, Number(statement.outstandingAmount)))
      selection.amounts[statement.id] = Math.max(amount, 0)
      remaining = round(remaining - amount)
    })
  }

  function buildAllocations(): Api.Finance.CashAllocationInput[] {
    return allocationRows.value
      .map((row) => ({
        statementId: row.id,
        amount: round(Number(selection.amounts[row.id] ?? 0))
      }))
      .filter((item) => item.amount > 0)
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    if (!buildAllocations().length) {
      ElMessage.warning('请至少选择一份待付款对账单')
      return false
    }
    if (allocationSummary.value.remaining !== 0) {
      ElMessage.warning('申请付款金额必须与对账单分配合计一致')
      return false
    }
    try {
      await saveCarrierPaymentApplication({
        id: form.data.id,
        applicationNo: form.data.applicationNo.trim() || null,
        carrierId: form.data.carrierId,
        plannedPaymentDate: form.data.plannedPaymentDate,
        amount: Number(form.data.amount),
        paymentMethod: form.data.paymentMethod,
        basisUrls: [...form.data.basisUrls],
        remark: form.data.remark.trim() || null,
        allocations: buildAllocations()
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function resetForm(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    selection.carriers = []
    clearStatements()
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function loadApplication(id: string): Promise<void> {
    const { data } = await fetchCarrierPaymentApplicationDetail(id)
    if (!data) throw new Error('付款申请不存在')
    Object.assign(form.data, {
      id: data.id,
      applicationNo: data.applicationNo,
      carrierId: data.carrierId,
      plannedPaymentDate: data.plannedPaymentDate,
      amount: Number(data.amount),
      paymentMethod: data.paymentMethod,
      basisUrls: [...(data.basisUrls ?? [])],
      remark: data.remark ?? '',
      statementIds: (data.items ?? []).map((item) => item.statementId)
    })
    selection.carriers = [
      { id: data.carrierId, companyName: data.carrierName, carrierCode: data.applicationNo }
    ]
    selection.statements = (data.items ?? []).map((item) => ({
      id: item.statementId,
      statementNo: item.statementNoSnapshot,
      carrierId: item.carrierId,
      carrierName: data.carrierName,
      periodStart: '',
      periodEnd: '',
      periodLabel: '申请明细',
      costCount: 0,
      waybillCount: 0,
      statementAmount: item.statementAmountSnapshot,
      settledAmount: round(item.statementAmountSnapshot - item.outstandingAmountSnapshot),
      outstandingAmount: item.outstandingAmountSnapshot,
      statementOutstandingAmount: item.outstandingAmountSnapshot,
      reservedAmount: 0,
      status: 'confirmed',
      createTime: item.createTime
    }))
    selection.amounts = Object.fromEntries(
      (data.items ?? []).map((item) => [item.statementId, Number(item.appliedAmount)])
    )
  }

  async function handleOpen(row?: Application): Promise<void> {
    await Promise.all([resetForm(), applicationNumber.loadRule()])
    await dialogRef.value?.handleOpen(row, {
      title: row ? `编辑付款申请 · ${row.applicationNo}` : '新建承运商付款申请',
      subtitle: '审批通过前锁定可付款额度，通过后再登记实际付款凭证并自动核销',
      confirmText: row ? '保存修改' : '保存草稿',
      contentMaxHeight: '78vh',
      loading: Boolean(row),
      onOpen: async (_data, api) => {
        if (!row) return
        try {
          await loadApplication(row.id)
        } finally {
          api.setLoading(false)
        }
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .payment-application-dialog {
    &__allocation {
      margin-top: var(--art-space-4);
    }

    &__allocation-header {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      justify-content: space-between;
      margin-bottom: var(--art-space-3);
    }

    &__summary {
      margin-top: var(--art-space-4);
    }
  }
</style>
