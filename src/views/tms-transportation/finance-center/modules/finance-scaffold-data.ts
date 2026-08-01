import type {
  CashTransactionRecord,
  InvoiceRecord,
  ScaffoldListParams,
  SettlementKind,
  SettlementStatementRecord,
  WaybillCostRecord,
  WaybillProfitRecord,
  WorkbenchTask
} from './finance-types'

// 第一阶段只负责页面链路和交互骨架；第二阶段用 @/api/tms 的真实接口替换本文件。
export const statementRows: SettlementStatementRecord[] = [
  {
    id: 's1',
    statementNo: 'JS-KH-202608-001',
    settlementType: 'customer_receivable',
    counterpartyName: '上海云驰供应链有限公司',
    period: '2026-07',
    waybillCount: 38,
    statementAmount: 286500,
    settledAmount: 180000,
    outstandingAmount: 106500,
    status: 'partially_settled',
    ownerName: '王晓',
    createTime: '2026-08-01 09:18'
  },
  {
    id: 's2',
    statementNo: 'JS-KH-202608-002',
    settlementType: 'customer_receivable',
    counterpartyName: '杭州星河商贸有限公司',
    period: '2026-07',
    waybillCount: 21,
    statementAmount: 142800,
    settledAmount: 0,
    outstandingAmount: 142800,
    status: 'pending_review',
    ownerName: '李倩',
    createTime: '2026-08-01 10:05'
  },
  {
    id: 's3',
    statementNo: 'JS-CY-202608-001',
    settlementType: 'carrier_payable',
    counterpartyName: '华东捷运物流有限公司',
    period: '2026-07',
    waybillCount: 45,
    statementAmount: 198600,
    settledAmount: 198600,
    outstandingAmount: 0,
    status: 'settled',
    ownerName: '陈锋',
    createTime: '2026-07-31 17:42'
  },
  {
    id: 's4',
    statementNo: 'JS-CY-202608-002',
    settlementType: 'carrier_payable',
    counterpartyName: '苏州安达运输有限公司',
    period: '2026-07',
    waybillCount: 29,
    statementAmount: 116900,
    settledAmount: 50000,
    outstandingAmount: 66900,
    status: 'confirmed',
    ownerName: '陈锋',
    createTime: '2026-08-01 11:12'
  },
  {
    id: 's5',
    statementNo: 'JS-KH-202607-015',
    settlementType: 'customer_receivable',
    counterpartyName: '宁波海越科技有限公司',
    period: '2026-06',
    waybillCount: 18,
    statementAmount: 88500,
    settledAmount: 88500,
    outstandingAmount: 0,
    status: 'settled',
    ownerName: '王晓',
    createTime: '2026-07-02 08:36'
  }
]

export const cashRows: CashTransactionRecord[] = [
  {
    id: 'c1',
    transactionNo: 'SZ-20260801-001',
    direction: 'receipt',
    counterpartyName: '上海云驰供应链有限公司',
    transactionDate: '2026-08-01',
    amount: 100000,
    allocatedAmount: 80000,
    paymentMethod: 'bank_transfer',
    status: 'partially_allocated',
    bankReference: 'BOC202608010093'
  },
  {
    id: 'c2',
    transactionNo: 'FZ-20260801-001',
    direction: 'payment',
    counterpartyName: '苏州安达运输有限公司',
    transactionDate: '2026-08-01',
    amount: 50000,
    allocatedAmount: 50000,
    paymentMethod: 'bank_transfer',
    status: 'allocated',
    bankReference: 'ICBC202608010127'
  },
  {
    id: 'c3',
    transactionNo: 'SZ-20260731-004',
    direction: 'receipt',
    counterpartyName: '杭州星河商贸有限公司',
    transactionDate: '2026-07-31',
    amount: 60000,
    allocatedAmount: 0,
    paymentMethod: 'bank_transfer',
    status: 'pending_allocation',
    bankReference: 'CMB202607310614'
  }
]

export const invoiceRows: InvoiceRecord[] = [
  {
    id: 'i1',
    invoiceNo: '24312000000182645123',
    direction: 'output',
    invoiceType: 'vat_special',
    counterpartyName: '上海云驰供应链有限公司',
    issueDate: '2026-07-29',
    amount: 120000,
    taxAmount: 10800,
    status: 'issued'
  },
  {
    id: 'i2',
    invoiceNo: '24312000000182645124',
    direction: 'input',
    invoiceType: 'vat_special',
    counterpartyName: '华东捷运物流有限公司',
    issueDate: '2026-07-30',
    amount: 98600,
    taxAmount: 8874,
    status: 'certified'
  },
  {
    id: 'i3',
    invoiceNo: '待生成',
    direction: 'output',
    invoiceType: 'electronic',
    counterpartyName: '杭州星河商贸有限公司',
    issueDate: '2026-08-01',
    amount: 42800,
    taxAmount: 3852,
    status: 'draft'
  }
]

export const costRows: WaybillCostRecord[] = [
  {
    id: 'w1',
    waybillNo: 'YD202607310018',
    costType: 'toll',
    vendorName: '华东捷运物流有限公司',
    occurredAt: '2026-07-31',
    amount: 860,
    auditStatus: 'approved',
    remark: '沪宁高速路桥费'
  },
  {
    id: 'w2',
    waybillNo: 'YD202607310021',
    costType: 'loading',
    vendorName: '苏州装卸服务队',
    occurredAt: '2026-07-31',
    amount: 1200,
    auditStatus: 'pending_review',
    remark: '夜间装卸加班'
  },
  {
    id: 'w3',
    waybillNo: 'YD202608010003',
    costType: 'waiting',
    vendorName: '司机张师傅',
    occurredAt: '2026-08-01',
    amount: 500,
    auditStatus: 'draft',
    remark: '客户仓库等待 5 小时'
  }
]

export const profitRows: WaybillProfitRecord[] = [
  {
    id: 'p1',
    waybillNo: 'YD202607310018',
    customerName: '上海云驰供应链有限公司',
    carrierName: '华东捷运物流有限公司',
    receivableAmount: 12800,
    payableAmount: 8600,
    otherCostAmount: 860,
    grossProfit: 3340,
    grossMargin: 26.09,
    completedAt: '2026-07-31 18:20'
  },
  {
    id: 'p2',
    waybillNo: 'YD202607310021',
    customerName: '杭州星河商贸有限公司',
    carrierName: '苏州安达运输有限公司',
    receivableAmount: 9600,
    payableAmount: 7200,
    otherCostAmount: 1200,
    grossProfit: 1200,
    grossMargin: 12.5,
    completedAt: '2026-07-31 20:45'
  },
  {
    id: 'p3',
    waybillNo: 'YD202608010003',
    customerName: '宁波海越科技有限公司',
    carrierName: '自营车辆 沪A·8T521',
    receivableAmount: 6800,
    payableAmount: 3600,
    otherCostAmount: 500,
    grossProfit: 2700,
    grossMargin: 39.71,
    completedAt: '2026-08-01 10:12'
  }
]

export const workbenchTasks: WorkbenchTask[] = [
  {
    id: 't1',
    taskType: 'statement_review',
    title: '待审核对账单',
    count: 8,
    amount: 356800,
    urgency: '紧急'
  },
  {
    id: 't2',
    taskType: 'cash_allocation',
    title: '待核销收付款',
    count: 6,
    amount: 182000,
    urgency: '关注'
  },
  {
    id: 't3',
    taskType: 'invoice_review',
    title: '待复核发票',
    count: 4,
    amount: 96400,
    urgency: '普通'
  },
  {
    id: 't4',
    taskType: 'cost_review',
    title: '待审核运单费用',
    count: 11,
    amount: 18620,
    urgency: '关注'
  }
]

export function getStatementRows(kind: SettlementKind): SettlementStatementRecord[] {
  return statementRows.filter((row) => row.settlementType === kind)
}

export function createScaffoldListApi<T extends Record<string, unknown>>(
  source: T[],
  searchText: (row: T) => string
) {
  return async (params: ScaffoldListParams) => {
    const current = Number(params.current || 1)
    const size = Number(params.size || 20)
    const keyword = String(params.keyword || '')
      .trim()
      .toLowerCase()
    const filtered = source.filter((row) => {
      if (keyword && !searchText(row).toLowerCase().includes(keyword)) return false
      if (params.status && row.status !== params.status) return false
      if (params.direction && row.direction !== params.direction) return false
      return true
    })
    const start = (current - 1) * size
    return { records: filtered.slice(start, start + size), total: filtered.length, current, size }
  }
}

export function formatMoney(value: number): string {
  return `¥${value.toLocaleString('zh-CN', { minimumFractionDigits: 2 })}`
}
