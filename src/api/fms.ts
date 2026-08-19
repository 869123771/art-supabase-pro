// FMS consumes transport counterparties through its public facade so feature views do not
// depend on the TMS API entry point. Future source adapters can be added behind this boundary.
export { fetchCarrierOptions } from '@/api/modules/tms/carrier'
export { fetchCustomerOptions, fetchCustomerSelectorList } from '@/api/modules/tms/customer'

export {
  fetchAccountingFoundationSummary,
  fetchAccountingReadiness,
  fetchAccountingPeriodList,
  fetchAccountSetDetail,
  fetchAccountSetList,
  fetchAccountSetOverview,
  fetchAccountSetOptions,
  initializeAccountingDefaults,
  saveAccountSet,
  setAccountingPeriodStatus,
  setAccountSetStatus
} from '@/api/modules/fms/accounting/foundation'

export {
  deleteAuxiliaryType,
  deleteOpeningBalance,
  fetchAuxiliaryItemList,
  fetchAuxiliaryTypeList,
  fetchCurrencyList,
  fetchExchangeRateList,
  fetchOpeningBalanceList,
  fetchOpeningBalanceSummary,
  fetchSubjectList,
  saveAuxiliaryItem,
  saveAuxiliaryType,
  saveCurrency,
  saveExchangeRate,
  saveOpeningBalance,
  saveSubject,
  setAuxiliaryItemEnabled,
  setAuxiliaryTypeEnabled,
  setCurrencyEnabled,
  setOpeningBalanceStatus,
  syncAuxiliaryItems,
  setSubjectEnabled
} from '@/api/modules/fms/accounting/base-data'

export {
  deleteVoucherTemplate,
  exportVoucherList,
  fetchVoucherDetail,
  fetchVoucherList,
  fetchVoucherSummary,
  fetchVoucherTemplateDetail,
  fetchVoucherTemplateList,
  saveVoucher,
  saveVoucherTemplate,
  transitionVoucher
} from '@/api/modules/fms/accounting/voucher'

export {
  fetchGeneralLedgerReport,
  fetchSubjectBalanceReport,
  fetchSubsidiaryLedgerReport
} from '@/api/modules/fms/accounting/ledger'

export {
  fetchCashFlowAllocations,
  fetchFinancialStatementFormulas,
  fetchFinancialStatementItems,
  fetchFinancialStatementReport,
  initializeFinancialStatementItems,
  saveCashFlowAllocations,
  saveFinancialStatementFormulas,
  saveFinancialStatementItem,
  saveFinancialStatementMappings
} from '@/api/modules/fms/accounting/financial-report'

export {
  deletePostingRule,
  fetchAccountingWorkloadSummary,
  fetchPostingEventDetail,
  fetchPostingEventList,
  fetchPostingRuleDetail,
  fetchPostingRuleList,
  processPendingPostingEvents,
  retryPostingEvent,
  savePostingRule
} from '@/api/modules/fms/accounting/posting'

export {
  autoMatchBankReconciliation,
  deleteFundAccount,
  deleteFundTransfer,
  fetchBankReconciliationDetail,
  fetchBankReconciliationList,
  fetchBankStatementLines,
  fetchBankStatementMatches,
  fetchFundAccountList,
  fetchFundAccountOptions,
  fetchFundAccountOverview,
  fetchFundLedgerList,
  fetchFundTransferActions,
  fetchFundTransferList,
  ignoreBankStatementLine,
  importBankReconciliation,
  matchBankStatementLine,
  saveFundAccount,
  saveFundTransfer,
  transitionBankReconciliation,
  transitionFundTransfer,
  unmatchBankStatementLine
} from '@/api/modules/fms/treasury/treasury'

export {
  actCommercialBill,
  deleteCommercialBill,
  fetchCommercialBillEvents,
  fetchCommercialBillList,
  fetchCommercialBillSummary,
  saveCommercialBill
} from '@/api/modules/fms/specialized/commercial-bill'

export {
  actAssetDepreciationRun,
  actFixedAsset,
  calculateAssetDepreciation,
  deleteAssetCategory,
  deleteFixedAsset,
  fetchAssetCategoryList,
  fetchAssetDepreciationLines,
  fetchAssetDepreciationRuns,
  fetchFixedAssetList,
  fetchFixedAssetSummary,
  saveAssetCategory,
  saveFixedAsset
} from '@/api/modules/fms/specialized/fixed-asset'

export {
  actPayrollRun,
  deletePayrollLine,
  fetchPayrollEmployeeOptions,
  fetchPayrollLines,
  fetchPayrollRunList,
  fetchPayrollSummary,
  savePayrollLine,
  savePayrollRun
} from '@/api/modules/fms/specialized/payroll'

export {
  actTaxPeriod,
  deleteTaxLedgerLine,
  fetchTaxLedgerLines,
  fetchTaxPeriodList,
  fetchTaxSummary,
  saveTaxLedgerLine,
  saveTaxPeriod
} from '@/api/modules/fms/specialized/tax-management'

export {
  actPeriodCloseRun,
  fetchPeriodCloseChecks,
  fetchPeriodCloseRuns,
  fetchPeriodCloseSummary,
  generateProfitLossCarryforward,
  runPeriodCloseChecks
} from '@/api/modules/fms/specialized/period-close'

export {
  addExpenseItem,
  addWaybillCost,
  analyzeReceivablesCollectionByAi,
  analyzeWaybillCostByAi,
  analyzeWaybillExpenseByAi,
  analyzeWaybillProfitByAi,
  createExpenseReimbursement,
  deleteExpenseItem,
  deleteExpenseReimbursement,
  deleteWaybillCost,
  editExpenseItem,
  editWaybillCost,
  executeExpenseReimbursement,
  exportWaybillCostList,
  exportWaybillProfitList,
  fetchExpenseItemList,
  fetchExpenseItemTree,
  fetchExpenseReimbursementDetail,
  fetchExpenseReimbursementList,
  fetchFinanceWaybillOptions,
  fetchFinanceWorkbench,
  fetchWaybillCostDetail,
  fetchWaybillCostList,
  fetchWaybillCostOverview,
  fetchWaybillExpenseOcrEnabled,
  fetchWaybillExpenseOcrRunList,
  fetchWaybillProfitList,
  reviewWaybillCost,
  reviewWaybillExpenseOcrArtifact,
  submitExpenseReimbursement,
  submitWaybillCost,
  voidWaybillCost
} from '@/api/modules/fms/transport/fms'

export {
  analyzeInvoiceAttachmentByAi,
  analyzeInvoiceComplianceByAi,
  createInvoiceCounterpartyFromOcr,
  deleteInvoice,
  exportInvoiceList,
  fetchActiveInvoiceByLegalNo,
  fetchInvoiceDetail,
  fetchInvoiceList,
  fetchInvoiceableStatementList,
  isInvoiceLegalNumberConflict,
  resolveInvoiceCounterparty,
  reviewInvoiceOcrArtifact,
  saveInvoice,
  updateInvoiceStatus
} from '@/api/modules/fms/transport/invoice'

export {
  createCustomerStatement,
  deleteCustomerStatement,
  exportCustomerStatementList,
  fetchCustomerStatementDetail,
  fetchCustomerStatementEligibleWaybills,
  fetchCustomerStatementList,
  updateCustomerStatementStatus
} from '@/api/modules/fms/transport/customer-settlement'

export {
  createCarrierStatement,
  deleteCarrierStatement,
  exportCarrierStatementList,
  fetchCarrierStatementDetail,
  fetchCarrierStatementEligibleCosts,
  fetchCarrierStatementList,
  updateCarrierStatementStatus
} from '@/api/modules/fms/transport/carrier-settlement'

export {
  allocateCarrierPayment,
  allocateCustomerReceipt,
  analyzeBankStatementBatchByAi,
  analyzeCashVoucherByAi,
  commitBankStatementBatchByAi,
  createCarrierPayment,
  createCustomerReceipt,
  exportCashTransactionList,
  fetchCarrierStatementAllocatableList,
  fetchCashTransactionDetail,
  fetchCashTransactionList,
  fetchCustomerStatementAllocatableList,
  reverseCarrierCashAllocation,
  reverseCashAllocation,
  reviewCashVoucherOcrArtifact,
  voidCashTransaction
} from '@/api/modules/fms/transport/cash-transaction'

export {
  cancelCarrierPaymentApplication,
  deleteCarrierPaymentApplication,
  executeCarrierPaymentApplication,
  exportCarrierPaymentApplicationList,
  fetchCarrierPaymentApplicationDetail,
  fetchCarrierPaymentApplicationList,
  saveCarrierPaymentApplication,
  submitCarrierPaymentApplication
} from '@/api/modules/fms/transport/payment-application'
