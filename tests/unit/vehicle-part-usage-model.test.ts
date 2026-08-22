import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EDITABLE_VEHICLE_PART_USAGE_ACCESS,
  sanitizeVehiclePartUsagePayload
} from '../../src/views/vms/vehicle-manage/part-manage/modules/vehicle-part-usage-model'

const createRecord = (): Api.Vms.VehicleManage.VehiclePartUsage => ({
  id: 'usage-1',
  plateNo: 'QA-001',
  partType: 'original',
  partName: 'Brake pad',
  partCode: 'PART-001',
  supplierName: 'Sensitive supplier',
  supplierContact: '13800138000',
  isConsumable: true,
  rfidEnabled: true,
  rfidTag: 'RFID-SECRET',
  enableMode: 'date',
  enableDate: '2026-08-22',
  warrantyMode: 'self',
  warrantyMileage: 100000,
  serviceMileageEnabled: true,
  serviceMileage: 80000,
  serviceYearsEnabled: false,
  usedMileage: 12000,
  status: 'normal',
  remark: 'Sensitive note',
  lifecycleLimitsMasked: true,
  fieldAccess: {},
  isRecordOwner: false
})

test('vehicle part usage payload removes response-only metadata', () => {
  const payload = sanitizeVehiclePartUsagePayload({
    ...createRecord(),
    fieldAccess: EDITABLE_VEHICLE_PART_USAGE_ACCESS
  })
  assert.equal('fieldAccess' in payload, false)
  assert.equal('isRecordOwner' in payload, false)
  assert.equal('lifecycleLimitsMasked' in payload, false)
})

test('vehicle part usage payload omits protected groups without edit permission', () => {
  const payload = sanitizeVehiclePartUsagePayload(createRecord())
  assert.equal('supplierContact' in payload, false)
  assert.equal('rfidTag' in payload, false)
  assert.equal('enableDate' in payload, false)
  assert.equal('serviceMileage' in payload, false)
  assert.equal('usedMileage' in payload, false)
  assert.equal('remark' in payload, false)
})

test('vehicle part usage payload keeps editable protected groups', () => {
  const payload = sanitizeVehiclePartUsagePayload({
    ...createRecord(),
    fieldAccess: EDITABLE_VEHICLE_PART_USAGE_ACCESS
  })
  assert.equal(payload.supplierContact, '13800138000')
  assert.equal(payload.rfidTag, 'RFID-SECRET')
  assert.equal(payload.serviceMileage, 80000)
  assert.equal(payload.remark, 'Sensitive note')
})
