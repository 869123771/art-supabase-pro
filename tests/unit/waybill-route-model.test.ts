import assert from 'node:assert/strict'
import test from 'node:test'
import {
  buildDrivingRoutePoints,
  buildWaybillLocationPoints,
  isValidMapCoordinate
} from '../../src/views/tms-transportation/waybill-management/detail/modules/waybill-route-model'

function createWaybill(): Api.Tms.Waybill.WaybillDetailRecord {
  return {
    id: 'waybill-1',
    tenantId: 'tenant-1',
    waybillNo: 'YD-001',
    status: 'completed',
    shipperLongitude: 113.466042,
    shipperLatitude: 34.087698,
    receiverLongitude: 116.458443,
    receiverLatitude: 39.912666,
    shipperAddress: '发货地址',
    receiverAddress: '收货地址',
    routePoints: [],
    pickupPhotos: [],
    deliveryPhotos: [],
    receiptAttachments: [],
    createTime: '2026-08-13T04:00:00Z',
    updateTime: '2026-08-13T12:00:00Z',
    events: [
      {
        id: 'accepted',
        waybillId: 'waybill-1',
        eventType: 'accepted',
        eventTime: '2026-08-13T04:40:00Z',
        longitude: null,
        latitude: null,
        payload: {},
        createTime: '2026-08-13T04:40:00Z'
      },
      {
        id: 'departed',
        waybillId: 'waybill-1',
        eventType: 'departed',
        eventTime: '2026-08-13T09:22:00Z',
        longitude: null,
        latitude: null,
        payload: {},
        createTime: '2026-08-13T09:22:00Z'
      },
      {
        id: 'signed',
        waybillId: 'waybill-1',
        eventType: 'signed',
        eventTime: '2026-08-13T09:29:00Z',
        longitude: null,
        latitude: null,
        payload: {},
        createTime: '2026-08-13T09:29:00Z'
      }
    ],
    proofs: [],
    cargoOperations: [
      {
        id: 'loading',
        tenantId: 'tenant-1',
        waybillId: 'waybill-1',
        operationType: 'loading',
        operationStatus: 'completed',
        checkinTime: '2026-08-13T08:45:00Z',
        checkinMode: 'manual',
        longitude: 114.1828629,
        latitude: 30.4974522,
        geofenceCenterLongitude: 113.466042,
        geofenceCenterLatitude: 34.087698,
        geofenceRadiusM: 1000,
        distanceM: 404859,
        insideGeofence: true,
        photoUrls: [],
        weighbridgeTicketUrls: [],
        createTime: '2026-08-13T08:45:00Z',
        updateTime: '2026-08-13T08:45:00Z'
      },
      {
        id: 'unloading',
        tenantId: 'tenant-1',
        waybillId: 'waybill-1',
        operationType: 'unloading',
        operationStatus: 'completed',
        checkinTime: '2026-08-13T09:25:00Z',
        checkinMode: 'manual',
        longitude: 114.1828664,
        latitude: 30.4974507,
        geofenceCenterLongitude: 116.458443,
        geofenceCenterLatitude: 39.912666,
        geofenceRadiusM: 1000,
        distanceM: 1067030,
        insideGeofence: true,
        photoUrls: [],
        weighbridgeTicketUrls: [],
        createTime: '2026-08-13T09:25:00Z',
        updateTime: '2026-08-13T09:25:00Z'
      }
    ]
  }
}

test('rejects missing and zero placeholder coordinates', () => {
  assert.equal(isValidMapCoordinate(null, null), false)
  assert.equal(isValidMapCoordinate(0, 0), false)
  assert.equal(isValidMapCoordinate(113.466042, 34.087698), true)
})

test('derives missing lifecycle event coordinates without converting null to zero', () => {
  const points = buildWaybillLocationPoints(createWaybill())
  const accepted = points.find((point) => point.id === 'event-accepted')
  const departed = points.find((point) => point.id === 'event-departed')
  const signed = points.find((point) => point.id === 'event-signed')

  assert.deepEqual(
    { longitude: accepted?.longitude, latitude: accepted?.latitude, source: accepted?.sourceLabel },
    { longitude: 113.466042, latitude: 34.087698, source: '关联地址' }
  )
  assert.equal(departed?.sourceLabel, '关联打卡')
  assert.equal(signed?.sourceLabel, '关联打卡')
  assert.equal(
    points.some((point) => point.longitude === 0 && point.latitude === 0),
    false
  )
})

test('uses only endpoints and measured positions for driving route planning', () => {
  const waybill = createWaybill()
  const points = buildWaybillLocationPoints(waybill)
  const route = buildDrivingRoutePoints(points)

  assert.equal(route[0]?.id, 'shipper')
  assert.equal(route.at(-1)?.id, 'receiver')
  assert.equal(
    route.some((point) => point.id.startsWith('event-') && point.isDerived),
    false
  )
  assert.ok(route.some((point) => point.id === 'operation-loading'))
})

test('keeps persisted derived coordinates distinguishable from measured GPS', () => {
  const detail = createWaybill()
  detail.events[0]!.longitude = 113.466042
  detail.events[0]!.latitude = 34.087698
  detail.events[0]!.payload = {
    coordinateDerived: true,
    coordinateSource: 'shipper_address'
  }

  const accepted = buildWaybillLocationPoints(detail).find((point) => point.label === '接单')

  assert.deepEqual(
    {
      source: accepted?.source,
      sourceLabel: accepted?.sourceLabel,
      isDerived: accepted?.isDerived
    },
    { source: 'address', sourceLabel: '关联地址', isDerived: true }
  )
})

test('keeps the destination when limiting AMap waypoints', () => {
  const points = Array.from({ length: 22 }, (_, index) => ({
    id: index === 0 ? 'shipper' : index === 21 ? 'receiver' : `gps-${index}`,
    label: `节点 ${index}`,
    longitude: 110 + index * 0.1,
    latitude: 30 + index * 0.1,
    source: index === 0 || index === 21 ? ('address' as const) : ('gps' as const),
    sourceLabel: '测试定位',
    isDerived: false
  }))

  const route = buildDrivingRoutePoints(points)

  assert.equal(route.length, 18)
  assert.equal(route.at(-1)?.id, 'receiver')
})
