import assert from 'node:assert/strict'
import test from 'node:test'
import { assessWaybillCost } from '../../supabase/functions/_shared/waybill-cost-audit-rules'

const now = new Date('2026-08-05T08:00:00.000Z')

function cost(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: 'cost-current',
    waybill_id: 'waybill-1',
    cost_type: 'toll',
    amount: 800,
    occurred_on: '2026-08-04',
    payee_name: '高速公路收费站',
    remark: '高速通行费',
    attachments: [{ url: 'receipt.jpg' }],
    audit_status: 'pending_review',
    waybill: {
      waybill_no: 'YDJ001',
      origin_city: '杭州',
      destination_city: '上海'
    },
    ...overrides
  }
}

test('cost audit blocks a suspected duplicate before financial approval', () => {
  const result = assessWaybillCost(
    {
      cost: cost(),
      siblingCosts: [
        cost({ id: 'cost-existing', audit_status: 'approved', occurred_on: '2026-08-03' })
      ],
      profit: {
        receivable_amount: 5_000,
        total_cost_amount: 2_000
      }
    },
    { now }
  )

  assert.equal(result.recommendation, 'block_for_verification')
  assert.equal(result.metrics.duplicateCount, 1)
  assert.ok(result.signals.some((item) => item.type === 'duplicate_cost'))
})

test('cost audit identifies negative projected margin as critical', () => {
  const result = assessWaybillCost(
    {
      cost: cost({ amount: 1_500, cost_type: 'carrier_freight' }),
      profit: {
        receivable_amount: 5_000,
        total_cost_amount: 4_200
      }
    },
    { now }
  )

  assert.equal(result.riskLevel, 'critical')
  assert.equal(result.metrics.projectedTotalCost, 5_700)
  assert.equal(result.metrics.projectedGrossMargin, -0.14)
  assert.ok(result.signals.some((item) => item.type === 'negative_margin'))
})

test('cost audit detects amount outliers only with enough historical samples', () => {
  const result = assessWaybillCost(
    {
      cost: cost({ amount: 3_600 }),
      referenceCosts: [700, 750, 800, 850, 900].map((amount, index) => ({
        id: `history-${index}`,
        amount
      }))
    },
    { now }
  )

  assert.equal(result.metrics.benchmarkMedian, 800)
  assert.ok(result.signals.some((item) => item.type === 'amount_outlier'))
})

test('cost audit reports missing evidence without inventing a margin result', () => {
  const result = assessWaybillCost(
    {
      cost: cost({ attachments: [], payee_name: '', remark: '' })
    },
    { now }
  )

  assert.equal(result.metrics.projectedGrossMargin, null)
  assert.deepEqual(
    result.signals.map((item) => item.type),
    ['missing_attachment', 'missing_payee']
  )
  assert.ok(result.limitations.some((item) => item.includes('利润数据')))
})

test('cost audit keeps a clean record in routine human review', () => {
  const result = assessWaybillCost(
    {
      cost: cost({ cost_type: 'carrier_freight', amount: 2_000 }),
      profit: {
        receivable_amount: 10_000,
        total_cost_amount: 4_000
      },
      referenceCosts: [1_800, 1_900, 2_000, 2_100, 2_200].map((amount, index) => ({
        id: `history-${index}`,
        amount
      }))
    },
    { now }
  )

  assert.equal(result.riskLevel, 'low')
  assert.equal(result.recommendation, 'routine_review')
  assert.equal(result.signals.length, 0)
})
