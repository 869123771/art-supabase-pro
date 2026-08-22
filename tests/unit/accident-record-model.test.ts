import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EDITABLE_VEHICLE_ACCIDENT_ACCESS,
  sanitizeVehicleAccidentPayload
} from '../../src/views/vms/vehicle-manage/accident-record/modules/accident-record-model'

const createAccident = (): Api.Vms.VehicleManage.VehicleAccidentRecord => ({
  id: 'accident-1',
  vehicleId: 'vehicle-1',
  plateNo: '沪A12345',
  driverName: '王五',
  driverPhone: '13800138000',
  accidentTime: '2026-08-22 09:00:00',
  accidentLocation: '上海市测试路 1 号',
  accidentLongitude: 121.4,
  accidentLatitude: 31.2,
  accidentSummary: '测试事故经过',
  companyBearAmount: 2000,
  economicLoss: 5000,
  reported: true,
  insuranceReported: true,
  processed: false,
  dataSource: 'self',
  remark: '仅测试',
  attachments: [{ name: 'photo.jpg', url: 'https://example.test/photo.jpg' }],
  fieldAccess: { ...EDITABLE_VEHICLE_ACCIDENT_ACCESS },
  tenantId: 'tenant-1',
  createBy: 'creator@example.test',
  createTime: '2026-08-22T00:00:00Z',
  isRecordOwner: true
})

test('accident payload removes response-only metadata', () => {
  const payload = sanitizeVehicleAccidentPayload(createAccident())

  assert.equal(payload.plateNo, '沪A12345')
  assert.equal('tenantId' in payload, false)
  assert.equal('createBy' in payload, false)
  assert.equal('createTime' in payload, false)
  assert.equal('fieldAccess' in payload, false)
  assert.equal('isRecordOwner' in payload, false)
})

test('accident payload omits sensitive groups without edit permission', () => {
  const payload = sanitizeVehicleAccidentPayload({
    ...createAccident(),
    fieldAccess: {
      driverContact: 'read',
      accidentLocation: 'masked',
      accidentNarrative: 'hidden',
      lossAmounts: 'read',
      documents: 'masked'
    }
  })

  assert.equal('driverName' in payload, false)
  assert.equal('driverPhone' in payload, false)
  assert.equal('accidentLocation' in payload, false)
  assert.equal('accidentLongitude' in payload, false)
  assert.equal('accidentLatitude' in payload, false)
  assert.equal('accidentSummary' in payload, false)
  assert.equal('remark' in payload, false)
  assert.equal('companyBearAmount' in payload, false)
  assert.equal('economicLoss' in payload, false)
  assert.equal('attachments' in payload, false)
})

test('accident payload keeps editable sensitive groups', () => {
  const payload = sanitizeVehicleAccidentPayload(createAccident())

  assert.equal(payload.driverPhone, '13800138000')
  assert.equal(payload.accidentSummary, '测试事故经过')
  assert.equal(payload.economicLoss, 5000)
  assert.equal(payload.attachments?.length, 1)
})
