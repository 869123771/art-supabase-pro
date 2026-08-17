import assert from 'node:assert/strict'
import test from 'node:test'
import { reactive } from 'vue'
import {
  cloneReimbursementExpenses,
  validateReimbursementSelection,
  type ReimbursementExpenseCandidate
} from '../../src/views/fms/waybill-cost/modules/reimbursement-selection'

const approvedExpense = (
  overrides: Partial<ReimbursementExpenseCandidate> = {}
): ReimbursementExpenseCandidate => ({
  id: 'cost-1',
  waybillId: 'waybill-1',
  auditStatus: 'approved',
  settlementStatus: 'unsettled',
  reimbursementId: null,
  expensePaymentId: null,
  expenseItem: { reimbursementAllowed: true },
  ...overrides
})

test('allows one eligible expense', () => {
  assert.equal(validateReimbursementSelection([approvedExpense()]).valid, true)
})

test('allows multiple eligible expenses from the same waybill', () => {
  const result = validateReimbursementSelection([
    approvedExpense(),
    approvedExpense({ id: 'cost-2' })
  ])

  assert.equal(result.valid, true)
})

test('safely clones reactive expenses for the reimbursement dialog', () => {
  const expenses = reactive([approvedExpense()])
  const cloned = cloneReimbursementExpenses(expenses)

  assert.deepEqual(cloned, expenses)
  assert.notEqual(cloned, expenses)
  assert.notEqual(cloned[0], expenses[0])
})

test('rejects expenses from different waybills', () => {
  const result = validateReimbursementSelection([
    approvedExpense(),
    approvedExpense({ id: 'cost-2', waybillId: 'waybill-2' })
  ])

  assert.equal(result.valid, false)
  assert.match(result.message, /同一个运单/)
})

test('rejects unapproved or already occupied expenses', () => {
  const unapproved = validateReimbursementSelection([
    approvedExpense({ auditStatus: 'pending_review' })
  ])
  const occupied = validateReimbursementSelection([
    approvedExpense({ settlementStatus: 'pending_payment', reimbursementId: 'reimbursement-1' })
  ])

  assert.match(unapproved.message, /尚未审核通过/)
  assert.match(occupied.message, /已进入报销或支付流程/)
})
