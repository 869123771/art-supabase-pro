import assert from 'node:assert/strict'
import test from 'node:test'
import { recommendDispatchResources } from '../../supabase/functions/_shared/dispatch-recommendation-rules.ts'

const NOW = new Date('2026-08-04T08:00:00.000Z')

function vehicle(id: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id,
    plate_no: `粤A${id}`,
    company_name: '测试车队',
    vehicle_type: 'box_truck',
    audit_status: 'approved',
    operation_status: 'operating',
    approved_load_mass: 8_000,
    operation_route: '广州-深圳',
    primary_driver_id: `driver-${id}`,
    primaryDriver: {
      id: `driver-${id}`,
      driver_name: `司机${id}`,
      phone: '13800138000',
      enabled: true,
      license_expire_date: '2027-08-04'
    },
    ...overrides
  }
}

test('dispatch recommendations exclude busy and overloaded vehicles', () => {
  const result = recommendDispatchResources({
    now: NOW,
    order: {
      id: 'order-current',
      origin_station: '广州',
      destination_station: '深圳',
      cargo_weight_total: 6_000
    },
    vehicles: [vehicle('10001'), vehicle('10002'), vehicle('10003', { approved_load_mass: 5_000 })],
    activeAssignments: [
      {
        id: 'order-busy',
        dispatch_status: 'transporting',
        dispatch_vehicle_id: '10002',
        dispatch_driver_id: 'driver-10002'
      }
    ]
  })

  assert.deepEqual(
    result.recommendations.map((item) => item.vehicle.id),
    ['10001']
  )
  assert.equal(result.rejectedByReason.active_assignment, 1)
  assert.equal(result.rejectedByReason.capacity_exceeded, 1)
})

test('dispatch recommendations reward route experience and punctual history', () => {
  const matchingHistory = Array.from({ length: 4 }, (_, index) => ({
    dispatch_vehicle_id: '10001',
    origin_station: '广州',
    destination_station: '深圳',
    planned_arrival_time: `2026-07-0${index + 1}T18:00:00.000Z`,
    signed_at: `2026-07-0${index + 1}T17:00:00.000Z`
  }))
  const result = recommendDispatchResources({
    now: NOW,
    order: {
      id: 'order-current',
      origin_station: '广州',
      destination_station: '深圳',
      cargo_weight_total: 5_000
    },
    vehicles: [vehicle('10001'), vehicle('10002', { operation_route: '佛山-东莞' })],
    history: matchingHistory
  })

  assert.equal(result.recommendations[0]?.vehicle.id, '10001')
  assert.equal(result.recommendations[0]?.metrics.routeTrips, 4)
  assert.equal(result.recommendations[0]?.metrics.onTimeRate, 1)
  assert.ok((result.recommendations[0]?.score ?? 0) > (result.recommendations[1]?.score ?? 0))
  assert.ok((result.recommendations[0]?.confidence ?? 0) >= 0.8)
})

test('dispatch recommendations keep incomplete capacity data visible with a warning', () => {
  const result = recommendDispatchResources({
    now: NOW,
    order: {
      id: 'order-current',
      origin_station: '广州',
      destination_station: '深圳',
      cargo_weight_total: 2_000
    },
    vehicles: [vehicle('10001', { approved_load_mass: null })]
  })

  assert.equal(result.recommendations.length, 1)
  assert.match(result.recommendations[0]?.warnings[0] ?? '', /核定载质量/)
})

test('dispatch recommendations diversify primary drivers before repeating one', () => {
  const sharedDriver = {
    id: 'driver-shared',
    driver_name: '共享司机',
    phone: '13800138000',
    enabled: true,
    license_expire_date: '2027-08-04'
  }
  const result = recommendDispatchResources({
    now: NOW,
    limit: 3,
    order: {
      id: 'order-current',
      origin_station: '广州',
      destination_station: '深圳',
      cargo_weight_total: 11.7
    },
    vehicles: [
      vehicle('10001', { primaryDriver: sharedDriver }),
      vehicle('10002', { primaryDriver: sharedDriver }),
      vehicle('10003')
    ]
  })

  assert.equal(result.recommendations[0]?.vehicle.primaryDriver.id, 'driver-shared')
  assert.equal(result.recommendations[1]?.vehicle.primaryDriver.id, 'driver-10003')
  assert.match(result.recommendations[0]?.reasons[0] ?? '', /<1%/)
})
