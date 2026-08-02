<template>
  <ArtDialog ref="dialogRef" width="1120px">
    <ArtForm
      ref="formRef"
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
        <ArtTableSingleSelect
          v-model="form.data.counterpartyId"
          v-model:selected-data="selection.parties"
          :api-fn="fetchPartySelectorData"
          :columns="partyColumns"
          :title="form.data.direction === 'output' ? '选择开票客户' : '选择来票承运商'"
          :subtitle="
            form.data.direction === 'output' ? '销项发票关联客户对账单' : '进项发票关联承运商对账单'
          "
          row-key="id"
          label-key="partyName"
          description-key="partyCode"
          placeholder="请选择往来单位"
          search-placeholder="名称、编码、联系人或电话"
          dialog-width="920px"
          show-pagination
          :page-size="10"
          @change="handlePartyChange"
        />
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
          dialog-width="1040px"
          show-pagination
          show-selected-panel
          :page-size="10"
          :disabled="!form.data.counterpartyId"
        />
      </template>
    </ArtForm>

    <ElAlert
      class="mt-4"
      :type="selection.statements.length ? 'success' : 'info'"
      :closable="false"
      show-icon
      :title="selectionSummary"
    />

    <section v-if="selection.statements.length" class="invoice-dialog__links art-card-xs">
      <ArtSectionTitle>对账单关联金额</ArtSectionTitle>
      <ElTable :data="selection.statements" table-layout="fixed">
        <ElTableColumn prop="statementNo" label="对账单号" min-width="180" />
        <ElTableColumn label="账期" width="205">
          <template #default="{ row }">{{ row.periodStart }} 至 {{ row.periodEnd }}</template>
        </ElTableColumn>
        <ElTableColumn label="对账金额" width="135" align="right">
          <template #default="{ row }">{{ formatMoney(row.statementAmount) }}</template>
        </ElTableColumn>
        <ElTableColumn label="可开票金额" width="135" align="right">
          <template #default="{ row }">{{ formatMoney(getAvailableAmount(row)) }}</template>
        </ElTableColumn>
        <ElTableColumn label="本次关联" width="190" align="right">
          <template #default="{ row }">
            <ElInputNumber
              v-model="selection.linkAmounts[row.statementId]"
              :min="0.01"
              :max="getAvailableAmount(row)"
              :precision="2"
              :step="100"
              controls-position="right"
            />
          </template>
        </ElTableColumn>
      </ElTable>
    </section>
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { FormRules } from 'element-plus'
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
  import {
    fetchCarrierOptions,
    fetchCustomerSelectorList,
    fetchInvoiceDetail,
    fetchInvoiceableStatementList,
    saveInvoice
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { pageInfoHandler } from '@/utils/table/tableUtils'

  defineOptions({ name: 'TmsInvoiceDialog' })

  type Invoice = Api.Tms.Finance.InvoiceRecord
  type InvoiceableStatement = Api.Tms.Finance.InvoiceableStatement

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface InvoiceFormModel {
    id?: string
    direction: Api.Tms.Finance.InvoiceDirection
    counterpartyId: string
    invoiceType: Api.Tms.Finance.InvoiceType
    invoiceTitle: string
    taxNumber: string
    invoiceCode: string
    invoiceNo: string
    issueDate: string
    taxRate: number
    amountExcludingTax: number
    taxAmount: number
    totalAmount: number
    statementIds: string[]
    attachments: Array<Record<string, unknown>>
    remark: string
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

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Invoice | undefined>>()
  const formRef = ref<FormExpose>()
  const statementSelectRef = ref<ArtDataSelectExpose>()

  const createInitialForm = (): InvoiceFormModel => ({
    id: undefined,
    direction: 'output',
    counterpartyId: '',
    invoiceType: 'vat_special',
    invoiceTitle: '',
    taxNumber: '',
    invoiceCode: '',
    invoiceNo: '',
    issueDate: dayjs().format('YYYY-MM-DD'),
    taxRate: 9,
    amountExcludingTax: 0,
    taxAmount: 0,
    totalAmount: 0,
    statementIds: [],
    attachments: [],
    remark: ''
  })

  const selection = reactive<SelectionGroup>({
    parties: [],
    statements: [],
    linkAmounts: {},
    originalLinkAmounts: {}
  })

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: reactive<InvoiceFormModel>(createInitialForm()),
    items: computed(() => [
      { label: '基本信息', key: 'baseSection', type: 'divider', span: 24 },
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
          onChange: recalculateTax
        }
      },
      { label: '发票抬头', key: 'invoiceTitle', type: 'input', span: 16 },
      { label: '纳税人识别号', key: 'taxNumber', type: 'input', span: 8 },
      { label: '发票代码', key: 'invoiceCode', type: 'input', span: 8 },
      { label: '发票号码', key: 'invoiceNo', type: 'input', span: 16 },
      { label: '金额信息', key: 'amountSection', type: 'divider', span: 24 },
      {
        label: '不含税金额',
        key: 'amountExcludingTax',
        type: 'number',
        span: 8,
        props: { min: 0, precision: 2, controlsPosition: 'right', onChange: recalculateTax }
      },
      {
        label: '税额',
        key: 'taxAmount',
        type: 'number',
        span: 8,
        props: { min: 0, precision: 2, controlsPosition: 'right', onChange: recalculateTotal }
      },
      {
        label: '价税合计',
        key: 'totalAmount',
        type: 'number',
        span: 8,
        props: { min: 0.01, precision: 2, controlsPosition: 'right', disabled: true }
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
      direction: [{ required: true, message: '请选择发票方向', trigger: 'change' }],
      counterpartyId: [{ required: true, message: '请选择往来单位', trigger: 'change' }],
      invoiceType: [{ required: true, message: '请选择发票类型', trigger: 'change' }],
      issueDate: [{ required: true, message: '请选择开票日期', trigger: 'change' }],
      invoiceNo: [{ required: true, message: '请输入发票号码', trigger: 'blur' }],
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

  const selectedLinkedAmount = computed(() =>
    selection.statements.reduce(
      (total, row) => total + Number(selection.linkAmounts[String(row.statementId)] ?? 0),
      0
    )
  )

  const selectionSummary = computed(() =>
    selection.statements.length
      ? `已选择 ${selection.statements.length} 份对账单，本次关联 ${formatMoney(selectedLinkedAmount.value)}，发票价税合计 ${formatMoney(form.data.totalAmount)}`
      : form.data.counterpartyId
        ? '可以关联已确认的对账单；暂不关联时，发票将进入待匹配状态'
        : '请先选择发票方向和往来单位，再关联对账单'
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
    return Math.round((Number(value) + Number.EPSILON) * 100) / 100
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

  function handleDirectionChange(): void {
    form.data.counterpartyId = ''
    selection.parties = []
    clearStatements()
  }

  function handlePartyChange(): void {
    clearStatements()
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
    await nextTick()
    formRef.value?.clearValidate()
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
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    const statementLinks = selection.statements.map((row) => ({
      statementId: String(row.statementId),
      linkedAmount: Number(selection.linkAmounts[String(row.statementId)] ?? 0)
    }))
    if (statementLinks.some((item) => item.linkedAmount <= 0)) return false
    if (selectedLinkedAmount.value > form.data.totalAmount + 0.01) return false

    const payload: Api.Tms.Finance.SaveInvoicePayload = {
      id: form.data.id,
      direction: form.data.direction,
      invoiceType: form.data.invoiceType,
      customerId: form.data.direction === 'output' ? form.data.counterpartyId : null,
      carrierId: form.data.direction === 'input' ? form.data.counterpartyId : null,
      invoiceTitle: form.data.invoiceTitle.trim() || null,
      taxNumber: form.data.taxNumber.trim() || null,
      invoiceCode: form.data.invoiceCode.trim() || null,
      invoiceNo: form.data.invoiceNo.trim() || null,
      issueDate: form.data.issueDate,
      taxRate: Number(form.data.taxRate),
      amountExcludingTax: Number(form.data.amountExcludingTax),
      taxAmount: Number(form.data.taxAmount),
      totalAmount: Number(form.data.totalAmount),
      attachments: form.data.attachments,
      remark: form.data.remark.trim() || null,
      statementLinks
    }

    try {
      await saveInvoice(payload)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(row?: Invoice): Promise<void> {
    await resetForm()
    await dialogRef.value?.handleOpen(row, {
      title: row ? '编辑发票' : '登记发票',
      subtitle: '发票可以关联一个或多个已确认对账单，未关联金额会进入财务工作台待办',
      confirmText: row ? '保存修改' : '保存草稿',
      contentMaxHeight: '76vh',
      loading: Boolean(row),
      onOpen: async (_data, api) => {
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

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .invoice-dialog {
    &__links {
      margin-top: 16px;
      padding: 16px;
    }
  }
</style>
