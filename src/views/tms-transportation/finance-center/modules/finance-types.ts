export type SettlementKind = 'customer_receivable' | 'carrier_payable'

export interface FinanceMetric {
  label: string
  value: string
  trend: string
  icon: string
  tone: 'primary' | 'success' | 'warning' | 'danger'
}

export interface SettlementStatementRecord {
  id: string
  statementNo: string
  settlementType: SettlementKind
  counterpartyName: string
  period: string
  waybillCount: number
  statementAmount: number
  settledAmount: number
  outstandingAmount: number
  status: string
  ownerName: string
  createTime: string
}

export interface CashTransactionRecord {
  id: string
  transactionNo: string
  direction: 'receipt' | 'payment'
  counterpartyName: string
  transactionDate: string
  amount: number
  allocatedAmount: number
  paymentMethod: string
  status: string
  bankReference: string
}

export interface InvoiceRecord {
  id: string
  invoiceNo: string
  direction: 'output' | 'input'
  invoiceType: string
  counterpartyName: string
  issueDate: string
  amount: number
  taxAmount: number
  status: string
}

export interface WaybillCostRecord {
  id: string
  waybillNo: string
  costType: string
  vendorName: string
  occurredAt: string
  amount: number
  auditStatus: string
  remark: string
}

export interface WaybillProfitRecord {
  id: string
  waybillNo: string
  customerName: string
  carrierName: string
  receivableAmount: number
  payableAmount: number
  otherCostAmount: number
  grossProfit: number
  grossMargin: number
  completedAt: string
}

export interface WorkbenchTask {
  id: string
  taskType: string
  title: string
  count: number
  amount: number
  urgency: '普通' | '关注' | '紧急'
}

export interface ScaffoldListParams {
  current?: number
  size?: number
  keyword?: string
  status?: string
  direction?: string
  dateRange?: string[]
}
