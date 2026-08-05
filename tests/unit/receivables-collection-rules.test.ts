import assert from 'node:assert/strict'
import test from 'node:test'
import { assessReceivablesCollection } from '../../supabase/functions/_shared/receivables-collection-rules'

const now = new Date('2026-08-05T08:00:00.000Z')

function statement(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'statement-1',
    statement_no: 'KHZD20260001',
    customer_id: 'customer-1',
    customer_name: '测试客户',
    period_start: '2026-06-01',
    period_end: '2026-06-30',
    status: 'confirmed',
    statement_amount: 10_000,
    settled_amount: 2_000,
    outstanding_amount: 8_000,
    ...overrides
  }
}

test('prioritizes long-aging receivables as critical', () => {
  const result = assessReceivablesCollection(
    {
      statements: [
        statement({
          period_end: '2026-04-30',
          statement_amount: 12_000,
          outstanding_amount: 10_000
        })
      ]
    },
    { now }
  )

  assert.equal(result.riskLevel, 'critical')
  assert.equal(result.metrics.aging90Amount, 10_000)
  assert.equal(result.priorityStatements[0]?.riskScore, 99)
  assert.ok(result.signals.some((item) => item.type === 'aging_over_90_days'))
})

test('identifies settlement review as the first blocker', () => {
  const result = assessReceivablesCollection(
    {
      statements: [statement({ status: 'pending_review', period_end: '2026-07-31' })]
    },
    { now }
  )

  assert.equal(result.recommendation, 'unblock_settlement')
  assert.equal(result.metrics.reviewBlockedAmount, 8_000)
  assert.ok(result.signals.some((item) => item.type === 'settlement_review_blocked'))
})

test('detects invoicing as a collection prerequisite', () => {
  const result = assessReceivablesCollection(
    {
      statements: [statement()],
      invoiceableStatements: [
        {
          statement_id: 'statement-1',
          direction: 'receivable',
          statement_amount: 10_000,
          invoiced_amount: 3_000,
          uninvoiced_amount: 7_000
        }
      ]
    },
    { now }
  )

  assert.equal(result.recommendation, 'complete_invoicing')
  assert.equal(result.metrics.uninvoicedAmount, 7_000)
  assert.ok(result.priorityStatements[0]?.reasons.includes('仍有未开票金额'))
})

test('aggregates customer concentration without double counting closed statements', () => {
  const result = assessReceivablesCollection(
    {
      statements: [
        statement(),
        statement({
          id: 'statement-2',
          statement_no: 'KHZD20260002',
          outstanding_amount: 2_000
        }),
        statement({
          id: 'statement-3',
          statement_no: 'KHZD20260003',
          customer_id: 'customer-2',
          customer_name: '已结客户',
          status: 'settled',
          outstanding_amount: 0
        })
      ]
    },
    { now }
  )

  assert.equal(result.metrics.openStatementCount, 2)
  assert.equal(result.riskCustomers[0]?.statementCount, 2)
  assert.equal(result.riskCustomers[0]?.outstandingAmount, 10_000)
  assert.ok(!result.signals.some((item) => item.type === 'customer_concentration'))
})

test('flags customer concentration only when the portfolio has enough samples and value', () => {
  const result = assessReceivablesCollection(
    {
      statements: [
        statement({
          id: 'statement-large',
          customer_id: 'customer-a',
          customer_name: '客户 A',
          statement_amount: 12_000,
          outstanding_amount: 12_000
        }),
        statement({
          id: 'statement-medium',
          customer_id: 'customer-b',
          customer_name: '客户 B',
          statement_amount: 5_000,
          outstanding_amount: 5_000
        }),
        statement({
          id: 'statement-small',
          customer_id: 'customer-c',
          customer_name: '客户 C',
          statement_amount: 3_000,
          outstanding_amount: 3_000
        })
      ]
    },
    { now }
  )

  assert.ok(result.signals.some((item) => item.type === 'customer_concentration'))
  assert.ok(result.priorityStatements[0]?.reasons.includes('单笔未结金额占当前应收 30% 以上'))
})

test('returns a calm empty assessment when there is no open receivable', () => {
  const result = assessReceivablesCollection(
    { statements: [statement({ status: 'settled', outstanding_amount: 0 })] },
    { now }
  )

  assert.equal(result.riskLevel, 'low')
  assert.equal(result.recommendation, 'routine_monitoring')
  assert.equal(result.priorityStatements.length, 0)
  assert.equal(result.metrics.outstandingAmount, 0)
})
