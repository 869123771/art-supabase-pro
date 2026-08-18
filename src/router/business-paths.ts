export const FMS_ROOT_PATH = '/fms'
export const TMS_ROOT_PATH = '/tms'
export const VMS_ROOT_PATH = '/vms'

const LEGACY_FMS_ROOT_PATH = '/finance'
const LEGACY_TMS_ROOT_PATH = '/tms-transportation'
const LEGACY_VMS_ROOT_PATH = '/vehicle-manage-system'
const LEGACY_TMS_FINANCE_ROOT_PATH = `${LEGACY_TMS_ROOT_PATH}/finance-center`

export const financePaths = {
  workbench: `${FMS_ROOT_PATH}/workbench`,
  settlement: `${FMS_ROOT_PATH}/settlement`,
  customerSettlement: `${FMS_ROOT_PATH}/settlement/customer-settlement`,
  carrierSettlement: `${FMS_ROOT_PATH}/settlement/carrier-settlement`,
  paymentApplication: `${FMS_ROOT_PATH}/settlement/payment-application`,
  cashTransaction: `${FMS_ROOT_PATH}/settlement/cash-transaction`,
  invoiceManagement: `${FMS_ROOT_PATH}/settlement/invoice-management`,
  waybillCost: `${FMS_ROOT_PATH}/settlement/waybill-cost`,
  expenseReimbursement: `${FMS_ROOT_PATH}/settlement/expense-reimbursement`,
  waybillProfit: `${FMS_ROOT_PATH}/settlement/waybill-profit`,
  expenseItem: `${FMS_ROOT_PATH}/settlement/expense-item`,
  accounting: `${FMS_ROOT_PATH}/accounting`,
  accountSet: `${FMS_ROOT_PATH}/accounting/account-set`,
  accountingSubject: `${FMS_ROOT_PATH}/accounting/accounting-subject`,
  accountingAuxiliary: `${FMS_ROOT_PATH}/accounting/accounting-auxiliary`,
  accountingCurrency: `${FMS_ROOT_PATH}/accounting/accounting-currency`,
  openingBalance: `${FMS_ROOT_PATH}/accounting/opening-balance`,
  voucherCenter: `${FMS_ROOT_PATH}/accounting/voucher-center`,
  voucherTemplate: `${FMS_ROOT_PATH}/accounting/voucher-template`,
  autoPosting: `${FMS_ROOT_PATH}/accounting/auto-posting`,
  treasury: `${FMS_ROOT_PATH}/treasury`,
  fundAccount: `${FMS_ROOT_PATH}/treasury/fund-account`,
  fundTransfer: `${FMS_ROOT_PATH}/treasury/fund-transfer`,
  bankReconciliation: `${FMS_ROOT_PATH}/treasury/bank-reconciliation`,
  fundJournal: `${FMS_ROOT_PATH}/treasury/fund-journal`
} as const

export const financeRouteNames = {
  root: 'FinanceCenter',
  workbench: 'FinanceWorkbench',
  accountSet: 'FinanceAccountSet',
  accountingSubject: 'FinanceAccountingSubject',
  accountingAuxiliary: 'FinanceAccountingAuxiliary',
  accountingCurrency: 'FinanceAccountingCurrency',
  openingBalance: 'FinanceOpeningBalance',
  voucherCenter: 'FinanceVoucherCenter',
  voucherTemplate: 'FinanceVoucherTemplate',
  autoPosting: 'FinanceAutoPosting',
  fundAccount: 'FinanceFundAccount',
  fundTransfer: 'FinanceFundTransfer',
  bankReconciliation: 'FinanceBankReconciliation',
  fundJournal: 'FinanceFundJournal',
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
  const financeLeafMappings = [
    ['customer-settlement', financePaths.customerSettlement],
    ['carrier-settlement', financePaths.carrierSettlement],
    ['payment-application', financePaths.paymentApplication],
    ['cash-transaction', financePaths.cashTransaction],
    ['invoice-management', financePaths.invoiceManagement],
    ['waybill-cost', financePaths.waybillCost],
    ['expense-reimbursement', financePaths.expenseReimbursement],
    ['waybill-profit', financePaths.waybillProfit],
    ['expense-item', financePaths.expenseItem],
    ['account-set', financePaths.accountSet],
    ['accounting-subject', financePaths.accountingSubject],
    ['accounting-auxiliary', financePaths.accountingAuxiliary],
    ['accounting-currency', financePaths.accountingCurrency],
    ['opening-balance', financePaths.openingBalance],
    ['voucher-center', financePaths.voucherCenter],
    ['voucher-template', financePaths.voucherTemplate],
    ['auto-posting', financePaths.autoPosting],
    ['fund-account', financePaths.fundAccount],
    ['fund-transfer', financePaths.fundTransfer],
    ['bank-reconciliation', financePaths.bankReconciliation],
    ['fund-journal', financePaths.fundJournal]
  ] as const

  const financeRoots = [FMS_ROOT_PATH, LEGACY_FMS_ROOT_PATH, LEGACY_TMS_FINANCE_ROOT_PATH]
  const mappings = [
    ...financeRoots.flatMap((root) =>
      financeLeafMappings.map(([suffix, currentRoot]) => ({
        legacyRoot: `${root}/${suffix}`,
        currentRoot
      }))
    ),
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
