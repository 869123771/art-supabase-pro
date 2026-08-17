// FMS consumes transport counterparties through its public facade so feature views do not
// depend on the TMS API entry point. Future source adapters can be added behind this boundary.
export { fetchCarrierOptions } from '@/api/modules/tms/carrier'
export { fetchCustomerOptions, fetchCustomerSelectorList } from '@/api/modules/tms/customer'

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
