import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createInitialVehicleArchiveForm,
  sanitizeVehicleArchivePayload
} from '../../src/views/vehicle-manage-system/archive-manage/vehicle-archive-edit/modules/vehicle-archive-model'

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
})
