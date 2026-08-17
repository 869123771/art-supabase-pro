import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createInitialVehicleArchiveForm,
  requiresVehicleArchiveResubmission,
  sanitizeVehicleArchivePayload
} from '../../src/views/vms/archive-manage/vehicle-archive-edit/modules/vehicle-archive-model'

test('vehicle archive payload removes display and audit-only fields', () => {
  const form = createInitialVehicleArchiveForm()
  Object.assign(form, {
    id: 'vehicle-1',
    plateNo: '沪A12345',
    carrierId: 'carrier-1',
    companyName: '',
    primaryDriverName: '司机甲',
    primaryDriverPhone: '13800000000',
    createBy: 'auditor',
    auditStatus: 'rejected',
    auditRemark: '请补充资料',
    attachments: undefined
  })

  const payload = sanitizeVehicleArchivePayload(form)

  assert.equal(payload.id, 'vehicle-1')
  assert.equal(payload.plateNo, '沪A12345')
  assert.equal(payload.companyName, null)
  assert.deepEqual(payload.attachments, [])
  assert.equal(payload.isAirConditioned, false)
  assert.equal('primaryDriverName' in payload, false)
  assert.equal('createBy' in payload, false)
  assert.equal('auditStatus' in payload, false)
  assert.equal('auditRemark' in payload, false)
})

test('only rejected vehicle archives require resubmission after editing', () => {
  assert.equal(requiresVehicleArchiveResubmission('rejected'), true)
  assert.equal(requiresVehicleArchiveResubmission('pending'), false)
  assert.equal(requiresVehicleArchiveResubmission('approved'), false)
  assert.equal(requiresVehicleArchiveResubmission(undefined), false)
})
