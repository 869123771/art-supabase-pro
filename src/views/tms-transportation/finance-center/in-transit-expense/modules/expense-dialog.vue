<template>
  <ArtDialog ref="dialogRef" size="xl">
    <ExpenseOcrPanel
      ref="ocrPanelRef"
      v-model="form.data.attachments"
      :enabled="state.ocrEnabled"
      @apply="applyOcrResult"
      @failed="form.data.ocrStatus = 'failed'"
    />

    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="isCompact ? 24 : 12"
      :gutter="20"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #waybillId>
        <ArtTableSingleSelect
          v-model="form.data.waybillId"
          v-model:selected-data="selection.waybills"
          :api-fn="fetchWaybillSelectorData"
          :columns="waybillColumns"
          title="选择关联运单"
          subtitle="支持按运单号、订单号、车牌号或司机检索，选中后自动带出司机和车辆"
          row-key="id"
          label-key="waybillNo"
          description-key="summary"
          placeholder="请选择运单或输入车牌号检索"
          search-placeholder="运单号、订单号、车牌号、司机"
          dialog-width="xl"
          show-pagination
          :page-size="10"
        />
      </template>
    </ArtForm>

    <ElAlert
      v-if="selectedWaybill"
      class="expense-dialog__waybill-summary"
      type="info"
      :closable="false"
      show-icon
      :title="waybillSummary"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import { useMediaQuery } from '@vueuse/core'
  import type { ComputedRef } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    DataSelectColumn,
    DataSelectFetchParams,
    DataSelectRecord
  } from '@/components/core/forms/art-data-select/types'
  import {
    addInTransitExpense,
    editInTransitExpense,
    fetchInTransitExpenseOcrEnabled,
    fetchInTransitWaybillOptions,
    reviewInTransitExpenseOcrArtifact
  } from '@/api/tms'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { useUserStore } from '@/store/modules/user'
  import ExpenseOcrPanel from './expense-ocr-panel.vue'

  defineOptions({ name: 'TmsInTransitExpenseDialog' })

  type Expense = Api.Tms.Finance.InTransitExpenseRecord
  type Waybill = Api.Tms.Finance.InTransitWaybillOption

  interface ExpenseDialogOpenData {
    row?: Expense
    orderId?: string
  }

  interface ExpenseFormGroup {
    data: Expense
    items: ComputedRef<FormItem[]>
    rules: FormRules<Expense>
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [type: 'add' | 'edit'] }>()
  const isCompact = useMediaQuery('(max-width: 767px)')
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<ExpenseDialogOpenData>>()
  const formRef = ref<FormExpose>()
  const ocrPanelRef = ref<{ reset: () => void }>()
  const selection = reactive<{ waybills: DataSelectRecord[] }>({ waybills: [] })
  const state = reactive({ ocrEnabled: true })

  const createInitialForm = (): Expense => ({
    id: undefined,
    waybillId: '',
    expenseType: 'energy',
    amount: 0,
    occurredAt: dayjs().format('YYYY-MM-DD'),
    quantity: null,
    unitPrice: null,
    providerName: '',
    payeeName: '',
    paymentChannel: '',
    invoiceNo: '',
    meterNo: '',
    expenseLocation: '',
    description: '',
    attachments: [],
    latestOcrRunId: null,
    ocrArtifactId: null,
    ocrStatus: 'not_started',
    reportStatus: 'draft',
    reimbursementStatus: 'not_converted',
    paymentStatus: 'unpaid'
  })

  const form = reactive<ExpenseFormGroup>({
    data: createInitialForm(),
    rules: {
      waybillId: [{ required: true, message: '请选择关联运单', trigger: 'change' }],
      expenseType: [{ required: true, message: '请选择费用类型', trigger: 'change' }],
      amount: [
        {
          validator: (_rule, value, callback) =>
            Number(value) > 0 ? callback() : callback(new Error('费用金额必须大于 0')),
          trigger: 'change'
        }
      ],
      occurredAt: [{ required: true, message: '请选择费用发生日期', trigger: 'change' }]
    },
    items: computed<FormItem[]>(() => [
      { label: '业务关联', key: 'relationSection', type: 'divider', span: 24 },
      { label: '运单/车牌', key: 'waybillId', type: 'input', span: 24 },
      { label: '费用信息', key: 'expenseSection', type: 'divider', span: 24 },
      {
        label: '费用场景',
        key: 'expenseType',
        type: 'select',
        props: {
          options: getDictMap.value.tmsInTransitExpenseType ?? [],
          placeholder: '请选择费用场景'
        }
      },
      {
        label: '费用金额',
        key: 'amount',
        type: 'number',
        props: { min: 0.01, precision: 2, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '发生日期',
        key: 'occurredAt',
        type: 'date',
        props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
      },
      {
        label: '数量/用量',
        key: 'quantity',
        type: 'number',
        props: { min: 0, precision: 3, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '单价',
        key: 'unitPrice',
        type: 'number',
        props: { min: 0, precision: 4, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '服务商',
        key: 'providerName',
        type: 'input',
        props: { maxlength: 200, placeholder: '加油站、充电站或服务商' }
      },
      {
        label: '收款方',
        key: 'payeeName',
        type: 'input',
        props: { maxlength: 200, placeholder: '司机、服务商或实际收款人' }
      },
      {
        label: '支付渠道',
        key: 'paymentChannel',
        type: 'input',
        props: { maxlength: 80, placeholder: '现金、微信、油卡等' }
      },
      {
        label: '票据号码',
        key: 'invoiceNo',
        type: 'input',
        props: { maxlength: 120, placeholder: '发票号、订单号或交易号' }
      },
      {
        label: '表号/桩号',
        key: 'meterNo',
        type: 'input',
        props: { maxlength: 120, placeholder: '油枪号、充电桩号或设备号' }
      },
      {
        label: '发生地点',
        key: 'expenseLocation',
        type: 'input',
        span: 24,
        props: { maxlength: 300, placeholder: '填写或核对票据中的消费地点' }
      },
      {
        label: '费用说明',
        key: 'description',
        type: 'textarea',
        span: 24,
        props: {
          rows: 3,
          maxlength: 500,
          showWordLimit: true,
          placeholder: '说明费用产生原因、业务背景或票据异常'
        }
      }
    ])
  })

  const selectedWaybill = computed(() => selection.waybills[0] as Waybill | undefined)
  const waybillSummary = computed(() => {
    const waybill = selectedWaybill.value
    if (!waybill) return ''
    const driver = waybill.driver?.driverName || waybill.order?.dispatchDriverName || '司机待补充'
    const plate = waybill.order?.dispatchPlateNo || '车牌待补充'
    const route = [waybill.originCity, waybill.destinationCity].filter(Boolean).join(' → ')
    return `${waybill.waybillNo} · ${plate} · ${driver}${route ? ` · ${route}` : ''}`
  })
  const waybillColumns: DataSelectColumn[] = [
    { prop: 'waybillNo', label: '运单号', width: 180 },
    { prop: 'orderNo', label: '订单号', width: 170 },
    { prop: 'plateNo', label: '车牌号', width: 120 },
    { prop: 'driverName', label: '司机', width: 110 },
    { prop: 'route', label: '运输路线', minWidth: 220 }
  ]

  async function fetchWaybillSelectorData(params: DataSelectFetchParams) {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchInTransitWaybillOptions({
      keyword: params.keyword,
      from,
      to
    })
    return {
      data: (data ?? []).map(toSelectorWaybill),
      total: total ?? 0
    }
  }

  function toSelectorWaybill(item: Waybill): Waybill & DataSelectRecord {
    const plateNo = item.order?.dispatchPlateNo || ''
    const driverName = item.driver?.driverName || item.order?.dispatchDriverName || ''
    const route = [item.originCity, item.destinationCity].filter(Boolean).join(' → ')
    return {
      ...item,
      orderNo: item.order?.orderNo || '',
      plateNo,
      driverName,
      route,
      summary: [plateNo, driverName, route].filter(Boolean).join(' · ')
    }
  }

  function applyOcrResult(result: Api.Tms.Finance.InTransitExpenseOcrAnalyzeResponse): void {
    const value = result.expense
    Object.assign(form.data, {
      expenseType: value.expenseType,
      amount: value.amount ?? form.data.amount,
      occurredAt: value.occurredAt ?? form.data.occurredAt,
      quantity: value.quantity,
      unitPrice: value.unitPrice,
      providerName: value.providerName ?? form.data.providerName,
      payeeName: value.payeeName ?? form.data.payeeName,
      paymentChannel: value.paymentChannel ?? form.data.paymentChannel,
      invoiceNo: value.invoiceNo ?? form.data.invoiceNo,
      meterNo: value.meterNo ?? form.data.meterNo,
      expenseLocation: value.expenseLocation ?? form.data.expenseLocation,
      description: value.description ?? form.data.description,
      latestOcrRunId: result.runId,
      ocrArtifactId: result.artifactId,
      ocrStatus: 'succeeded'
    })
  }

  function buildOcrFinalPayload(): Record<string, unknown> {
    return {
      expenseType: form.data.expenseType,
      amount: Number(form.data.amount),
      occurredAt: form.data.occurredAt,
      quantity: form.data.quantity,
      unitPrice: form.data.unitPrice,
      providerName: form.data.providerName || null,
      payeeName: form.data.payeeName || null,
      paymentChannel: form.data.paymentChannel || null,
      invoiceNo: form.data.invoiceNo || null,
      meterNo: form.data.meterNo || null,
      expenseLocation: form.data.expenseLocation || null,
      description: form.data.description || null
    }
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    try {
      const type = form.data.id ? 'edit' : 'add'
      const response = form.data.id
        ? await editInTransitExpense(structuredClone(toRaw(form.data)))
        : await addInTransitExpense(structuredClone(toRaw(form.data)))
      const entityId = form.data.id || response.data?.id
      if (form.data.ocrArtifactId && entityId) {
        await reviewInTransitExpenseOcrArtifact({
          artifactId: form.data.ocrArtifactId,
          entityId,
          finalPayload: buildOcrFinalPayload()
        })
      }
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  async function resetForm(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    selection.waybills = []
    ocrPanelRef.value?.reset()
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function prefillByOrderId(orderId: string): Promise<void> {
    const { data } = await fetchInTransitWaybillOptions({ orderId, from: 0, to: 9 })
    const waybill = data?.[0]
    if (!waybill) return
    form.data.waybillId = waybill.id
    selection.waybills = [toSelectorWaybill(waybill)]
  }

  async function handleOpen(data: ExpenseDialogOpenData = {}): Promise<void> {
    await resetForm()
    if (data.row) Object.assign(form.data, createInitialForm(), structuredClone(toRaw(data.row)))
    await dialogRef.value?.handleOpen(data, {
      title: data.row ? `编辑在途费用 · ${data.row.expenseNo}` : '上报在途费用',
      subtitle: '按运单归集票据，审核通过后自动进入运单成本台账',
      confirmText: data.row ? '保存修改' : '保存草稿',
      contentMaxHeight: '78vh',
      loading: Boolean(data.orderId),
      onOpen: async (_openData, api) => {
        try {
          const [enabled] = await Promise.all([
            fetchInTransitExpenseOcrEnabled(),
            data.orderId ? prefillByOrderId(data.orderId) : Promise.resolve()
          ])
          state.ocrEnabled = enabled
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
  .expense-dialog {
    &__waybill-summary {
      margin-top: var(--art-space-4);
    }
  }
</style>
