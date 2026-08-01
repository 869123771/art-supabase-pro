<template>
  <div class="art-full-height">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="searchQuery"
      :search-items="searchItems"
      :api-fn="fetchTableData"
      :columns-factory="columnsFactory"
      :header-actions="headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
    />
    <FinanceRecordDialog ref="dialogRef" @success="handleScaffoldSuccess" />
  </div>
</template>

<script setup lang="tsx">
  import { ElMessage } from 'element-plus'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { useUserStore } from '@/store/modules/user'
  import {
    cashRows,
    costRows,
    createScaffoldListApi,
    formatMoney,
    invoiceRows
  } from './finance-scaffold-data'
  import type {
    CashTransactionRecord,
    InvoiceRecord,
    ScaffoldListParams,
    WaybillCostRecord
  } from './finance-types'
  import FinanceRecordDialog, { type FinanceRecordModule } from './finance-record-dialog.vue'

  defineOptions({ name: 'TmsFinanceLedgerList' })
  const props = defineProps<{ module: FinanceRecordModule }>()
  interface DialogExpose {
    handleOpen: (module: FinanceRecordModule) => Promise<void>
  }
  type LedgerRecord = CashTransactionRecord | InvoiceRecord | WaybillCostRecord

  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dialogRef = ref<DialogExpose>()
  const searchQuery = reactive<ScaffoldListParams>({ keyword: '', status: '', direction: '' })

  const statusOptions = computed(() => {
    if (props.module === 'cash') return getDictMap.value.tmsCashTransactionStatus ?? []
    if (props.module === 'invoice') return getDictMap.value.tmsInvoiceStatus ?? []
    return getDictMap.value.tmsCostAuditStatus ?? []
  })
  const directionOptions = computed(() =>
    props.module === 'cash'
      ? (getDictMap.value.tmsCashDirection ?? [])
      : (getDictMap.value.tmsInvoiceDirection ?? [])
  )

  const searchItems = computed<SearchFormItem[]>(() => [
    ...(props.module === 'cost'
      ? []
      : [
          {
            label: '业务方向',
            key: 'direction',
            type: 'select' as const,
            props: { options: directionOptions.value, clearable: true }
          }
        ]),
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: { options: statusOptions.value, clearable: true }
    },
    {
      label: '关键词',
      key: 'keyword',
      type: 'input',
      props: {
        clearable: true,
        placeholder: props.module === 'cost' ? '运单号 / 收款方' : '单号 / 往来单位'
      }
    }
  ])

  const sourceRows = computed(() =>
    props.module === 'cash' ? cashRows : props.module === 'invoice' ? invoiceRows : costRows
  )
  const fetchTableData = (params: ScaffoldListParams) =>
    createScaffoldListApi(
      sourceRows.value as Array<LedgerRecord & Record<string, unknown>>,
      (row) =>
        props.module === 'cash'
          ? `${(row as CashTransactionRecord).transactionNo} ${(row as CashTransactionRecord).counterpartyName}`
          : props.module === 'invoice'
            ? `${(row as InvoiceRecord).invoiceNo} ${(row as InvoiceRecord).counterpartyName}`
            : `${(row as WaybillCostRecord).waybillNo} ${(row as WaybillCostRecord).vendorName}`
    )(params)

  const operationColumn = (): ColumnOption<LedgerRecord> => ({
    prop: 'operation',
    label: '操作',
    width: 90,
    fixed: 'right',
    formatter: () => (
      <ArtButtonTable type="edit" onClick={() => ElMessage.info('下一阶段接入编辑与审核逻辑')} />
    )
  })

  const columnsFactory = (): ColumnOption<LedgerRecord>[] => {
    if (props.module === 'cash')
      return [
        { type: 'globalIndex', label: '序号', width: 72 },
        { prop: 'transactionNo', label: '收付单号', width: 180 },
        {
          prop: 'direction',
          label: '方向',
          width: 90,
          dict: { code: 'tmsCashDirection', display: 'tag' }
        },
        { prop: 'counterpartyName', label: '往来单位', minWidth: 200, showOverflowTooltip: true },
        { prop: 'transactionDate', label: '收付日期', width: 110 },
        {
          prop: 'amount',
          label: '金额',
          width: 135,
          align: 'right',
          formatter: (row) => formatMoney((row as CashTransactionRecord).amount)
        },
        {
          prop: 'allocatedAmount',
          label: '已核销',
          width: 135,
          align: 'right',
          formatter: (row) => formatMoney((row as CashTransactionRecord).allocatedAmount)
        },
        {
          prop: 'paymentMethod',
          label: '支付方式',
          width: 110,
          dict: { code: 'tmsCashPaymentMethod', display: 'text' }
        },
        {
          prop: 'status',
          label: '状态',
          width: 110,
          dict: { code: 'tmsCashTransactionStatus', display: 'tag' }
        },
        operationColumn()
      ]
    if (props.module === 'invoice')
      return [
        { type: 'globalIndex', label: '序号', width: 72 },
        { prop: 'invoiceNo', label: '发票号码', width: 190 },
        {
          prop: 'direction',
          label: '方向',
          width: 90,
          dict: { code: 'tmsInvoiceDirection', display: 'tag' }
        },
        {
          prop: 'invoiceType',
          label: '发票类型',
          width: 150,
          dict: { code: 'tmsInvoiceType', display: 'text' }
        },
        { prop: 'counterpartyName', label: '往来单位', minWidth: 210, showOverflowTooltip: true },
        { prop: 'issueDate', label: '开票日期', width: 110 },
        {
          prop: 'amount',
          label: '不含税金额',
          width: 140,
          align: 'right',
          formatter: (row) => formatMoney((row as InvoiceRecord).amount)
        },
        {
          prop: 'taxAmount',
          label: '税额',
          width: 120,
          align: 'right',
          formatter: (row) => formatMoney((row as InvoiceRecord).taxAmount)
        },
        {
          prop: 'status',
          label: '状态',
          width: 100,
          dict: { code: 'tmsInvoiceStatus', display: 'tag' }
        },
        operationColumn()
      ]
    return [
      { type: 'globalIndex', label: '序号', width: 72 },
      { prop: 'waybillNo', label: '运单号', width: 170 },
      {
        prop: 'costType',
        label: '费用类型',
        width: 120,
        dict: { code: 'tmsWaybillCostType', display: 'tag' }
      },
      { prop: 'vendorName', label: '收款方', minWidth: 190, showOverflowTooltip: true },
      { prop: 'occurredAt', label: '发生日期', width: 110 },
      {
        prop: 'amount',
        label: '费用金额',
        width: 140,
        align: 'right',
        formatter: (row) => formatMoney((row as WaybillCostRecord).amount)
      },
      {
        prop: 'auditStatus',
        label: '审核状态',
        width: 110,
        dict: { code: 'tmsCostAuditStatus', display: 'tag' }
      },
      { prop: 'remark', label: '费用说明', minWidth: 180, showOverflowTooltip: true },
      operationColumn()
    ]
  }

  const headerActions = computed<ArtTableQueryHeaderAction[]>(() => [
    {
      type: 'add',
      label:
        props.module === 'cash'
          ? '登记收付款'
          : props.module === 'invoice'
            ? '登记发票'
            : '登记费用',
      onClick: () => void dialogRef.value?.handleOpen(props.module)
    }
  ])

  function handleScaffoldSuccess(): void {
    ElMessage.success('表单交互已完成，真实保存将在下一阶段接入')
    void tableQueryRef.value?.refreshCreate()
  }
</script>
