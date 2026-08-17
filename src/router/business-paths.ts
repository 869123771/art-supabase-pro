export const FMS_ROOT_PATH = '/fms'
export const TMS_ROOT_PATH = '/tms'
export const VMS_ROOT_PATH = '/vms'

const LEGACY_FMS_ROOT_PATH = '/finance'
const LEGACY_TMS_ROOT_PATH = '/tms-transportation'
const LEGACY_VMS_ROOT_PATH = '/vehicle-manage-system'
const LEGACY_TMS_FINANCE_ROOT_PATH = `${LEGACY_TMS_ROOT_PATH}/finance-center`

export const financePaths = {
  workbench: `${FMS_ROOT_PATH}/workbench`,
  customerSettlement: `${FMS_ROOT_PATH}/customer-settlement`,
  carrierSettlement: `${FMS_ROOT_PATH}/carrier-settlement`,
  paymentApplication: `${FMS_ROOT_PATH}/payment-application`,
  cashTransaction: `${FMS_ROOT_PATH}/cash-transaction`,
  invoiceManagement: `${FMS_ROOT_PATH}/invoice-management`,
  waybillCost: `${FMS_ROOT_PATH}/waybill-cost`,
  expenseReimbursement: `${FMS_ROOT_PATH}/expense-reimbursement`,
  waybillProfit: `${FMS_ROOT_PATH}/waybill-profit`,
  expenseItem: `${FMS_ROOT_PATH}/expense-item`
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
 * Maps persisted bookmarks from the former business namespaces to their new
 * module roots. Non-business paths are intentionally ignored.
 */
export function resolveLegacyBusinessPath(path: string): string | undefined {
  const mappings = [
    { legacyRoot: LEGACY_TMS_FINANCE_ROOT_PATH, currentRoot: FMS_ROOT_PATH },
    { legacyRoot: LEGACY_FMS_ROOT_PATH, currentRoot: FMS_ROOT_PATH },
    { legacyRoot: LEGACY_TMS_ROOT_PATH, currentRoot: TMS_ROOT_PATH },
    { legacyRoot: LEGACY_VMS_ROOT_PATH, currentRoot: VMS_ROOT_PATH }
  ] as const

  for (const { legacyRoot, currentRoot } of mappings) {
    if (path === legacyRoot) {
      return currentRoot
    }

    if (path.startsWith(`${legacyRoot}/`)) {
      return `${currentRoot}${path.slice(legacyRoot.length)}`
    }
  }

  return undefined
}
