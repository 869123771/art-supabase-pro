import assert from 'node:assert/strict'
import test from 'node:test'
import {
  FINANCE_ROOT_PATH,
  financePaths,
  getExpenseReimbursementDetailPath,
  getWaybillCostDetailPath,
  resolveLegacyBusinessPath
} from '../../src/router/business-paths'

test('exposes finance routes from the standalone root', () => {
  assert.equal(FINANCE_ROOT_PATH, '/finance')
  assert.equal(financePaths.invoiceManagement, '/finance/invoice-management')
  assert.equal(getWaybillCostDetailPath('waybill-1'), '/finance/waybill-cost/detail/waybill-1')
  assert.equal(
    getExpenseReimbursementDetailPath('claim-1'),
    '/finance/expense-reimbursement/detail/claim-1'
  )
})

test('redirects legacy TMS finance bookmarks without changing their suffix', () => {
  assert.equal(resolveLegacyBusinessPath('/tms-transportation/finance-center'), '/finance')
  assert.equal(
    resolveLegacyBusinessPath(
      '/tms-transportation/finance-center/expense-reimbursement/detail/claim-1'
    ),
    '/finance/expense-reimbursement/detail/claim-1'
  )
})

test('ignores paths outside the former finance namespace', () => {
  assert.equal(resolveLegacyBusinessPath('/tms-transportation/order-list'), undefined)
  assert.equal(resolveLegacyBusinessPath('/finance/workbench'), undefined)
})
