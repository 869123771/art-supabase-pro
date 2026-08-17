import assert from 'node:assert/strict'
import test from 'node:test'
import {
  FMS_ROOT_PATH,
  TMS_ROOT_PATH,
  VMS_ROOT_PATH,
  financePaths,
  getExpenseReimbursementDetailPath,
  getWaybillCostDetailPath,
  resolveLegacyBusinessPath
} from '../../src/router/business-paths'

test('exposes finance routes from the standalone root', () => {
  assert.equal(FMS_ROOT_PATH, '/fms')
  assert.equal(financePaths.invoiceManagement, '/fms/invoice-management')
  assert.equal(getWaybillCostDetailPath('waybill-1'), '/fms/waybill-cost/detail/waybill-1')
  assert.equal(
    getExpenseReimbursementDetailPath('claim-1'),
    '/fms/expense-reimbursement/detail/claim-1'
  )
})

test('redirects legacy finance bookmarks without changing their suffix', () => {
  assert.equal(resolveLegacyBusinessPath('/tms-transportation/finance-center'), '/fms')
  assert.equal(
    resolveLegacyBusinessPath(
      '/tms-transportation/finance-center/expense-reimbursement/detail/claim-1'
    ),
    '/fms/expense-reimbursement/detail/claim-1'
  )
})

test('redirects legacy business roots to their renamed modules', () => {
  assert.equal(resolveLegacyBusinessPath('/finance/workbench'), '/fms/workbench')
  assert.equal(resolveLegacyBusinessPath('/tms-transportation/order-list'), '/tms/order-list')
  assert.equal(
    resolveLegacyBusinessPath('/vehicle-manage-system/vehicle-query'),
    '/vms/vehicle-query'
  )
  assert.equal(TMS_ROOT_PATH, '/tms')
  assert.equal(VMS_ROOT_PATH, '/vms')
})

test('ignores paths outside the legacy business namespaces', () => {
  assert.equal(resolveLegacyBusinessPath('/tms/order-list'), undefined)
  assert.equal(resolveLegacyBusinessPath('/dashboard'), undefined)
})
