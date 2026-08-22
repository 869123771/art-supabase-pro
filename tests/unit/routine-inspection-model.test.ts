import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EDITABLE_VEHICLE_ROUTINE_INSPECTION_ACCESS,
  sanitizeVehicleRoutineInspectionPayload
} from '../../src/views/vms/vehicle-manage/routine-inspection/modules/routine-inspection-model'

const createRecord = (): Api.Vms.VehicleManage.VehicleRoutineInspectionRecord => ({
  id: 'inspection-1',
  plateNo: 'QA-001',
  inspectionType: 'daily',
  inspectionTime: '2026-08-22 08:00:00',
  inspector: 'Inspector',
  driverName: 'Driver',
  checkResult: 'unqualified',
  checkCondition: 'Sensitive finding',
  handlingMethod: 'Sensitive remediation',
  remark: 'Sensitive remark',
  attachments: [{ name: 'evidence', url: 'https://example.invalid/evidence' }],
  attachmentsMasked: true,
  fieldAccess: {},
  isRecordOwner: false
})

test('routine inspection payload removes response-only metadata', () => {
  const payload = sanitizeVehicleRoutineInspectionPayload({
    ...createRecord(),
    fieldAccess: EDITABLE_VEHICLE_ROUTINE_INSPECTION_ACCESS
  })
  assert.equal('fieldAccess' in payload, false)
  assert.equal('isRecordOwner' in payload, false)
  assert.equal('attachmentsMasked' in payload, false)
})

test('routine inspection payload omits sensitive groups without edit permission', () => {
  const payload = sanitizeVehicleRoutineInspectionPayload(createRecord())
  assert.equal('inspector' in payload, false)
  assert.equal('driverName' in payload, false)
  assert.equal('checkResult' in payload, false)
  assert.equal('checkCondition' in payload, false)
  assert.equal('handlingMethod' in payload, false)
  assert.equal('remark' in payload, false)
  assert.equal('attachments' in payload, false)
})

test('routine inspection payload keeps editable sensitive groups', () => {
  const payload = sanitizeVehicleRoutineInspectionPayload({
    ...createRecord(),
    fieldAccess: EDITABLE_VEHICLE_ROUTINE_INSPECTION_ACCESS
  })
  assert.equal(payload.inspector, 'Inspector')
  assert.equal(payload.checkCondition, 'Sensitive finding')
  assert.equal(payload.attachments?.length, 1)
})
