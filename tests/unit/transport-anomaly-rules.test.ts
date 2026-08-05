import assert from 'node:assert/strict'
import test from 'node:test'
import {
  assessTransportAnomaly,
  detectTransportAnomalies
} from '../../supabase/functions/_shared/transport-anomaly-rules'

const now = new Date('2026-08-04T08:00:00.000Z')

test('transport anomaly rules prioritize overdue arrival and ignore terminal orders', () => {
  const result = detectTransportAnomalies(
    [
      {
        id: 'active-order',
        order_no: 'DD001',
        order_status: 'transporting',
        dispatch_status: 'loaded',
        origin_station: '杭州',
        destination_station: '上海',
        planned_arrival_time: '2026-08-03T06:00:00.000Z',
        dispatch_vehicle_id: 'vehicle-1',
        dispatch_driver_id: 'driver-1',
        update_time: '2026-08-04T07:00:00.000Z'
      },
      {
        id: 'completed-order',
        order_no: 'DD002',
        order_status: 'completed',
        dispatch_status: 'completed',
        planned_arrival_time: '2026-08-01T06:00:00.000Z',
        update_time: '2026-08-01T07:00:00.000Z'
      }
    ],
    { now }
  )

  assert.equal(result.length, 1)
  assert.equal(result[0].type, 'arrival_overdue')
  assert.equal(result[0].severity, 'critical')
  assert.equal(result[0].overdueHours, 26)
})

test('transport anomaly rules distinguish missed departure and stale business data', () => {
  const result = detectTransportAnomalies(
    [
      {
        id: 'departure-order',
        order_no: 'DD003',
        order_status: 'pending_load',
        dispatch_status: 'pending',
        planned_departure_time: '2026-08-04T02:00:00.000Z',
        planned_arrival_time: '2026-08-05T02:00:00.000Z',
        update_time: '2026-08-04T07:00:00.000Z'
      },
      {
        id: 'stale-order',
        order_no: 'DD004',
        order_status: 'pending_pickup',
        dispatch_status: 'loaded',
        dispatch_vehicle_id: 'vehicle-1',
        dispatch_driver_id: 'driver-1',
        planned_departure_time: '2026-08-05T02:00:00.000Z',
        planned_arrival_time: '2026-08-06T02:00:00.000Z',
        update_time: '2026-08-02T07:00:00.000Z'
      }
    ],
    { now, staleHours: 24 }
  )

  assert.deepEqual(
    result.map((item) => [item.type, item.severity]),
    [
      ['departure_overdue', 'high'],
      ['data_stale', 'medium']
    ]
  )
})

test('assessment reports missing resources and schedule without inventing GPS deviation', () => {
  const result = assessTransportAnomaly(
    {
      id: 'missing-order',
      order_no: 'DD005',
      order_status: 'transporting',
      dispatch_status: 'loaded',
      update_time: '2026-08-04T07:00:00.000Z'
    },
    { now }
  )

  assert.equal(result.riskLevel, 'high')
  assert.deepEqual(
    result.signals.map((item) => item.type),
    ['missing_assignment', 'missing_schedule']
  )
  assert.ok(result.limitations.some((item) => item.includes('GPS')))
})

test('assessment detects order and waybill lifecycle mismatch', () => {
  const result = assessTransportAnomaly(
    {
      id: 'mismatch-order',
      order_no: 'DD006',
      order_status: 'transporting',
      waybill_status: 'accepted',
      dispatch_status: 'loaded',
      dispatch_vehicle_id: 'vehicle-1',
      dispatch_driver_id: 'driver-1',
      planned_departure_time: '2026-08-04T07:00:00.000Z',
      planned_arrival_time: '2026-08-05T07:00:00.000Z',
      update_time: '2026-08-04T07:30:00.000Z'
    },
    { now }
  )

  assert.ok(result.signals.some((item) => item.type === 'status_mismatch'))
  assert.equal(result.riskLevel, 'high')
})
