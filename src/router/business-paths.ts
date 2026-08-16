export const FINANCE_ROOT_PATH = '/finance'

const LEGACY_FINANCE_ROOT_PATH = '/tms-transportation/finance-center'

export const financePaths = {
  workbench: `${FINANCE_ROOT_PATH}/workbench`,
  customerSettlement: `${FINANCE_ROOT_PATH}/customer-settlement`,
  carrierSettlement: `${FINANCE_ROOT_PATH}/carrier-settlement`,
  paymentApplication: `${FINANCE_ROOT_PATH}/payment-application`,
  cashTransaction: `${FINANCE_ROOT_PATH}/cash-transaction`,
  invoiceManagement: `${FINANCE_ROOT_PATH}/invoice-management`,
  waybillCost: `${FINANCE_ROOT_PATH}/waybill-cost`,
  expenseReimbursement: `${FINANCE_ROOT_PATH}/expense-reimbursement`,
  waybillProfit: `${FINANCE_ROOT_PATH}/waybill-profit`,
  expenseItem: `${FINANCE_ROOT_PATH}/expense-item`
} as const

export const financeRouteNames = {
  root: 'FinanceCenter',
  workbench: 'FinanceWorkbench',
  customerSettlement: 'FinanceCustomerSettlement',
  carrierSettlement: 'FinanceCarrierSettlement',
  paymentApplication: 'FinanceCarrierPaymentApplication',
  cashTransaction: 'FinanceCashTransaction',
  invoiceManagement: 'FinanceInvoiceManagement',
  waybillCost: 'FinanceWaybillCost',
  expenseReimbursement: 'FinanceExpenseReimbursement',
  waybillProfit: 'FinanceWaybillProfit',
  expenseItem: 'FinanceExpenseItem',
  waybillCostDetail: 'FinanceWaybillCostDetail',
  expenseReimbursementDetail: 'FinanceExpenseReimbursementDetail'
} as const

export function getWaybillCostDetailPath(id: string): string {
  return `${financePaths.waybillCost}/detail/${id}`
}

export function getExpenseReimbursementDetailPath(id: string): string {
  return `${financePaths.expenseReimbursement}/detail/${id}`
}

/**
 * Maps persisted finance bookmarks from the former TMS namespace to the
 * standalone finance module. Non-finance paths are intentionally ignored.
 */
export function resolveLegacyBusinessPath(path: string): string | undefined {
  if (path === LEGACY_FINANCE_ROOT_PATH) {
    return FINANCE_ROOT_PATH
  }

  if (!path.startsWith(`${LEGACY_FINANCE_ROOT_PATH}/`)) {
    return undefined
  }

  return `${FINANCE_ROOT_PATH}${path.slice(LEGACY_FINANCE_ROOT_PATH.length)}`
}
