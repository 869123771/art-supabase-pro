<template>
  <ArtDialog ref="dialogRef" size="xl">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #customerId>
        <ArtTableSingleSelect
          v-model="form.customerId"
          v-model:selected-data="selectedCustomers"
          :api-fn="fetchCustomerSelectorData"
          :columns="customerColumns"
          title="选择对账客户"
          subtitle="客户对账单按发货客户归集应收运费"
          row-key="id"
          label-key="customerName"
          description-key="customerCode"
          placeholder="请选择客户"
          search-placeholder="客户名称、编码、联系人或电话"
          dialog-width="lg"
          show-pagination
          :page-size="10"
          @change="handleCriteriaChange"
        />
      </template>

      <template #waybillIds>
        <ArtTableMultipleSelect
          ref="waybillSelectRef"
          v-model="form.waybillIds"
          v-model:selected-data="selectedWaybills"
          :api-fn="fetchWaybillSelectorData"
          :columns="waybillColumns"
          title="选择待对账运单"
          subtitle="仅显示该客户在所选账期内已签收或已完成、且尚未进入有效对账单的运单"
          row-key="id"
          label-key="waybillNo"
          description-key="routeLabel"
          placeholder="请选择待对账运单"
          search-placeholder="运单号、订单号或运输线路"
          dialog-width="xl"
          show-pagination
          show-selected-panel
          :page-size="10"
          :disabled="!canSelectWaybill"
        />
      </template>
    </ArtForm>

    <ElAlert
      class="mt-4"
      :type="selectedWaybills.length ? 'success' : 'info'"
      :closable="false"
      show-icon
      :title="selectionSummary"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { FormRules } from 'element-plus'
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
  import {
    createCustomerStatement,
    fetchCustomerSelectorList,
    fetchCustomerStatementEligibleWaybills
  } from '@/api/finance'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatWithDayjs } from '@/utils/time'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'

  defineOptions({ name: 'FinanceCustomerStatementDialog' })

  type CreatePayload = Api.Finance.CreateCustomerStatementPayload
  type EligibleWaybill = Api.Finance.CustomerStatementEligibleWaybill

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface StatementForm {
    statementNo: string
    customerId: string
    periodRange: string[]
    waybillIds: string[]
    remark: string
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<FormExpose>()
  const waybillSelectRef = ref<ArtDataSelectExpose>()
  const selectedCustomers = ref<DataSelectRecord[]>([])
  const selectedWaybills = ref<DataSelectRecord[]>([])
  const statementNumber = useDocumentNumberRule('tms.customer_statement')

  const createInitialForm = (): StatementForm => ({
    statementNo: '',
    customerId: '',
    periodRange: [dayjs().startOf('month').format('YYYY-MM-DD'), dayjs().format('YYYY-MM-DD')],
    waybillIds: [],
    remark: ''
  })

  const form = reactive<StatementForm>(createInitialForm())

  const canSelectWaybill = computed(() =>
    Boolean(form.customerId && form.periodRange?.[0] && form.periodRange?.[1])
  )

  const selectedAmount = computed(() =>
    selectedWaybills.value.reduce(
      (total, row) => total + Number((row as EligibleWaybill).receivableAmount ?? 0),
      0
    )
  )

  const formatMoney = (value?: number | null): string =>
    `¥${Number(value ?? 0).toLocaleString('zh-CN', {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2
    })}`

  const selectionSummary = computed(() =>
    selectedWaybills.value.length
      ? `已选择 ${selectedWaybills.value.length} 条运单，对账金额 ${formatMoney(selectedAmount.value)}`
      : canSelectWaybill.value
        ? '请选择本次需要纳入对账的运单'
        : '请先选择客户和账期，再选择待对账运单'
  )

  const customerColumns: DataSelectColumn[] = [
    { prop: 'customerCode', label: '客户编码', width: 145 },
    { prop: 'customerName', label: '客户名称', minWidth: 210 },
    { prop: 'contactName', label: '联系人', width: 120 },
    { prop: 'contactPhone', label: '联系电话', width: 145 },
    { prop: 'region', label: '所在区域', minWidth: 150 }
  ]

  const waybillColumns: DataSelectColumn[] = [
    { prop: 'waybillNo', label: '运单号', width: 170 },
    { prop: 'orderNo', label: '订单号', width: 170 },
    {
      prop: 'routeLabel',
      label: '运输线路',
      minWidth: 200,
      formatter: (row) =>
        [(row as EligibleWaybill).originStation, (row as EligibleWaybill).destinationStation]
          .filter(Boolean)
          .join(' → ') || '-'
    },
    {
      prop: 'completedAt',
      label: '完成时间',
      width: 170,
      formatter: (row) =>
        formatWithDayjs((row as EligibleWaybill).completedAt, 'YYYY-MM-DD HH:mm') ?? '-'
    },
    {
      prop: 'receivableAmount',
      label: '应收金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney((row as EligibleWaybill).receivableAmount)
    }
  ]

  const formRules: FormRules<StatementForm> = {
    statementNo: [
      {
        validator: (_rule, value, callback) =>
          statementNumber.manualRequired(false) && !String(value || '').trim()
            ? callback(new Error('请输入客户对账单号'))
            : callback(),
        trigger: 'blur'
      }
    ],
    customerId: [{ required: true, message: '请选择对账客户', trigger: 'change' }],
    periodRange: [{ required: true, message: '请选择对账账期', trigger: 'change' }],
    waybillIds: [
      {
        validator: (_rule, value, callback) =>
          Array.isArray(value) && value.length
            ? callback()
            : callback(new Error('请至少选择一条待对账运单')),
        trigger: 'change'
      }
    ],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '对账范围', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '对账单号',
      key: 'statementNo',
      type: 'input',
      span: 12,
      props: { maxlength: 50, ...statementNumber.inputProps(false, '请输入客户对账单号') },
      description: statementNumber.description.value
    },
    { label: '对账客户', key: 'customerId', type: 'input', span: 12 },
    {
      label: '对账账期',
      key: 'periodRange',
      type: 'date',
      span: 12,
      props: {
        type: 'daterange',
        valueFormat: 'YYYY-MM-DD',
        startPlaceholder: '开始日期',
        endPlaceholder: '结束日期',
        rangeSeparator: '至',
        class: '!w-full',
        onChange: handleCriteriaChange
      }
    },
    { label: '待对账运单', key: 'waybillIds', type: 'input', span: 24 },
    {
      label: '对账备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 3,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '可填写账期说明、客户约定或内部备注'
      }
    }
  ])

  async function fetchCustomerSelectorData(params: DataSelectFetchParams) {
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCustomerSelectorList({
      keyword: params.keyword,
      from,
      to
    })
    return { data: data ?? [], total: total ?? 0 }
  }

  async function fetchWaybillSelectorData(params: DataSelectFetchParams) {
    if (!canSelectWaybill.value) return { data: [], total: 0 }
    const { from, to } = pageInfoHandler({ current: params.page, size: params.pageSize })
    const { data, total } = await fetchCustomerStatementEligibleWaybills({
      customerId: form.customerId,
      periodStart: form.periodRange[0],
      periodEnd: form.periodRange[1],
      keyword: params.keyword,
      from,
      to
    })
    const records = (data ?? []).map((item) => ({
      ...item,
      routeLabel: [item.originStation, item.destinationStation].filter(Boolean).join(' → ')
    }))
    return { data: records, total: total ?? 0 }
  }

  function handleCriteriaChange(): void {
    form.waybillIds = []
    selectedWaybills.value = []
    void waybillSelectRef.value?.reload()
  }

  function replaceForm(nextForm: StatementForm): void {
    Object.keys(form).forEach((key) => delete form[key as keyof StatementForm])
    Object.assign(form, nextForm)
  }

  async function resetForm(): Promise<void> {
    replaceForm(createInitialForm())
    selectedCustomers.value = []
    selectedWaybills.value = []
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    const payload: CreatePayload = {
      statementNo: form.statementNo.trim() || null,
      customerId: form.customerId,
      periodStart: form.periodRange[0],
      periodEnd: form.periodRange[1],
      waybillIds: [...form.waybillIds],
      remark: form.remark.trim() || null
    }

    try {
      await createCustomerStatement(payload)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(): Promise<void> {
    await Promise.all([resetForm(), statementNumber.loadRule()])
    await dialogRef.value?.handleOpen(undefined, {
      title: '生成客户对账单',
      subtitle: '按客户和账期归集已完成运单，生成后可提交财务审核',
      confirmText: '生成对账单',
      contentMaxHeight: '72vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
