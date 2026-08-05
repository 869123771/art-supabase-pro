import assert from 'node:assert/strict'
import test from 'node:test'
import { assessCarrierPerformance } from '../../supabase/functions/_shared/carrier-performance-rules'

const now = new Date('2026-08-05T00:00:00.000Z')

test('marks incomplete qualification as requiring manual review', () => {
  const result = assessCarrierPerformance(
    {
      carrier: {
        id: 'carrier-1',
        carrier_code: 'C001',
        company_name: '测试承运商',
        signed_contract: false
      },
      waybills: [],
      driverCount: 0,
      vehicleCount: 0
    },
    { now }
  )

  assert.equal(result.riskLevel, 'critical')
  assert.equal(result.cooperationStrategy, 'manual_qualification_review')
  assert.equal(result.confidence, 0.55)
  assert.ok(result.signals.some((signal) => signal.type === 'qualification_incomplete'))
  assert.ok(result.signals.some((signal) => signal.type === 'history_insufficient'))
})

test('identifies cancellation and late-arrival performance risks', () => {
  const waybills = Array.from({ length: 5 }, (_, index) => ({
    id: `waybill-${index}`,
    waybill_no: `WB-${index}`,
    status: index === 0 ? 'cancelled' : 'completed',
    origin_city: '武汉',
    destination_city: '杭州',
    freight_amount: 1000,
    planned_unload_time: `2026-08-0${index + 1}T08:00:00.000Z`,
    arrived_at:
      index === 0 ? null : `2026-08-0${index + 1}T${index === 1 ? '12' : '07'}:00:00.000Z`,
    create_time: `2026-08-0${index + 1}T00:00:00.000Z`
  }))

  const result = assessCarrierPerformance(
    {
      carrier: {
        id: 'carrier-2',
        carrier_code: 'C002',
        company_name: '华东运输',
        business_license_no: 'LIC-002',
        signed_contract: true
      },
      waybills,
      costs: [{ amount: 800, audit_status: 'rejected' }],
      statements: [{ status: 'submitted' }],
      driverCount: 3,
      vehicleCount: 4
    },
    { now }
  )

  assert.equal(result.metrics.cancellationRate, 20)
  assert.equal(result.metrics.onTimeRate, 75)
  assert.equal(result.metrics.rejectedCostCount, 1)
  assert.equal(result.metrics.openStatementCount, 1)
  assert.equal(result.cooperationStrategy, 'conditional_cooperation')
  assert.ok(result.riskWaybills.some((row) => row.reasons.includes('运单已取消')))
  assert.ok(result.signals.some((signal) => signal.type === 'on_time_rate_low'))
})

test('keeps a complete and stable carrier in the preferred tier', () => {
  const waybills = Array.from({ length: 10 }, (_, index) => ({
    id: `stable-${index}`,
    waybill_no: `STABLE-${index}`,
    status: 'completed',
    origin_city: '广州',
    destination_city: '深圳',
    freight_amount: 1200,
    planned_unload_time: '2026-08-04T12:00:00.000Z',
    arrived_at: '2026-08-04T11:30:00.000Z',
    create_time: '2026-08-04T00:00:00.000Z'
  }))

  const result = assessCarrierPerformance(
    {
      carrier: {
        id: 'carrier-3',
        carrier_code: 'C003',
        company_name: '稳定运输',
        business_license_no: 'LIC-003',
        signed_contract: true
      },
      waybills,
      costs: [{ amount: 6500, audit_status: 'approved' }],
      statements: [{ status: 'settled' }],
      driverCount: 5,
      vehicleCount: 8
    },
    { now }
  )

  assert.equal(result.riskLevel, 'low')
  assert.equal(result.performanceScore, 82)
  assert.equal(result.cooperationStrategy, 'preferred_partner')
  assert.equal(result.metrics.onTimeRate, 100)
  assert.equal(result.signals.length, 0)
})
