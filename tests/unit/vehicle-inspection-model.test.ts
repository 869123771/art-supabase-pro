import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EDITABLE_VEHICLE_INSPECTION_ACCESS,
  sanitizeVehicleInspectionPayload
} from '../../src/views/vms/vehicle-manage/vehicle-inspection/modules/vehicle-inspection-model'

const createInspection = (): Api.Vms.VehicleManage.VehicleInspection => ({
  id: 'inspection-1',
  plateNo: '沪A12345',
  inspectionNo: 'INSPECTION-001',
  inspectionAmount: 860,
  compulsoryPolicyNo: 'COMPULSORY-001',
  compulsoryPremium: 1200,
  attachments: [{ name: 'inspection.pdf', url: 'https://example.test/inspection.pdf' }],
  fieldAccess: { ...EDITABLE_VEHICLE_INSPECTION_ACCESS },
  tenantId: 'tenant-1',
  createBy: 'creator@example.test',
  createTime: '2026-08-22T00:00:00Z',
  isRecordOwner: true
})

test('vehicle inspection payload removes response-only metadata', () => {
  const payload = sanitizeVehicleInspectionPayload(createInspection())

  assert.equal(payload.plateNo, '沪A12345')
  assert.equal('tenantId' in payload, false)
  assert.equal('createBy' in payload, false)
  assert.equal('createTime' in payload, false)
  assert.equal('fieldAccess' in payload, false)
  assert.equal('isRecordOwner' in payload, false)
})

test('vehicle inspection payload omits sensitive groups without edit permission', () => {
  const payload = sanitizeVehicleInspectionPayload({
    ...createInspection(),
    fieldAccess: {
      inspectionIdentifiers: 'read',
      monetaryAmounts: 'masked',
      documents: 'hidden'
    }
  })

  assert.equal('inspectionNo' in payload, false)
  assert.equal('compulsoryPolicyNo' in payload, false)
  assert.equal('inspectionAmount' in payload, false)
  assert.equal('compulsoryPremium' in payload, false)
  assert.equal('attachments' in payload, false)
})

test('vehicle inspection payload keeps editable sensitive groups', () => {
  const payload = sanitizeVehicleInspectionPayload(createInspection())

  assert.equal(payload.inspectionNo, 'INSPECTION-001')
  assert.equal(payload.inspectionAmount, 860)
  assert.equal(payload.compulsoryPolicyNo, 'COMPULSORY-001')
  assert.equal(payload.compulsoryPremium, 1200)
  assert.equal(payload.attachments?.length, 1)
})
