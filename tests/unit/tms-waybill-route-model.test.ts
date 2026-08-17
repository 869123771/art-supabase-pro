import assert from 'node:assert/strict'
import test from 'node:test'
import {
  buildWaybillGpsTrackPoints,
  buildWaybillLocationPoints
} from '../../src/views/tms/waybill-management/detail/modules/waybill-route-model'

const createWaybill = (
  routePoints: Api.Tms.Waybill.WaybillRoutePoint[],
  expenseLocations: Api.Tms.Waybill.WaybillExpenseLocationRecord[] = []
): Api.Tms.Waybill.WaybillDetailRecord =>
  ({
    id: 'waybill-1',
    tenantId: 'tenant-1',
    waybillNo: 'YD-001',
    status: 'transporting',
    routePoints,
    expenseLocations,
    events: [],
    proofs: [],
    cargoOperations: [],
    pickupPhotos: [],
    deliveryPhotos: [],
    receiptAttachments: [],
    createTime: '2026-08-15T00:00:00+08:00',
    updateTime: '2026-08-15T00:20:00+08:00'
  }) as Api.Tms.Waybill.WaybillDetailRecord

test('waybill route keeps chronological GPS samples and detects a parking point', () => {
  const waybill = createWaybill([
    {
      longitude: 113.00001,
      latitude: 34.00001,
      capturedAt: '2026-08-15T00:00:00+08:00',
      speedKmh: 0
    },
    {
      longitude: 113.00002,
      latitude: 34.00002,
      capturedAt: '2026-08-15T00:06:00+08:00',
      speedKmh: 1
    },
    {
      longitude: 113.00003,
      latitude: 34.00001,
      capturedAt: '2026-08-15T00:12:00+08:00',
      speedKmh: 0
    },
    {
      longitude: 113.05,
      latitude: 34.05,
      capturedAt: '2026-08-15T00:20:00+08:00',
      speedKmh: 60
    }
  ])

  assert.equal(buildWaybillGpsTrackPoints(waybill).length, 4)
  const stop = buildWaybillLocationPoints(waybill).find((point) => point.kind === 'stop')
  assert.equal(stop?.markerLabel, 'P')
  assert.equal(stop?.durationMinutes, 12)
  assert.equal(stop?.label, '停车 P1')
})

test('waybill route uses expense report coordinates for fuel and charging nodes', () => {
  const waybill = createWaybill(
    [],
    [
      {
        id: 'fuel-1',
        occurredOn: '2026-08-15',
        expenseLongitude: 114.1,
        expenseLatitude: 34.1,
        expenseLocation: '示例加油站',
        expenseItem: {
          id: 'item-fuel',
          itemCode: 'fuel',
          itemName: '在途加油',
          businessCategory: 'fuel'
        }
      },
      {
        id: 'charging-1',
        occurredOn: '2026-08-15',
        expenseLongitude: 115.1,
        expenseLatitude: 35.1,
        expenseLocation: '示例充电站',
        expenseItem: {
          id: 'item-charging',
          itemCode: 'charging',
          itemName: '在途充电',
          businessCategory: 'in_transit_charging'
        }
      }
    ]
  )

  const energyPoints = buildWaybillLocationPoints(waybill).filter(
    (point) => point.kind === 'energy'
  )
  assert.deepEqual(
    energyPoints.map((point) => [point.label, point.sourceLabel]),
    [
      ['加油', '费用上报定位'],
      ['充电', '费用上报定位']
    ]
  )
})

test('automatic parking detection does not duplicate a nearby business node', () => {
  const waybill = createWaybill([
    {
      longitude: 116.10001,
      latitude: 39.10001,
      capturedAt: '2026-08-15T00:00:00+08:00',
      speedKmh: 0
    },
    {
      longitude: 116.10002,
      latitude: 39.10002,
      capturedAt: '2026-08-15T00:10:00+08:00',
      speedKmh: 0
    }
  ])
  waybill.shipperLongitude = 116.1
  waybill.shipperLatitude = 39.1
  waybill.shipperAddress = '装货点'

  assert.equal(
    buildWaybillLocationPoints(waybill).filter((point) => point.kind === 'stop').length,
    0
  )
})
