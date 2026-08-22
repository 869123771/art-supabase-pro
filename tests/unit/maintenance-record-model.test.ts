import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EDITABLE_VEHICLE_MAINTENANCE_ACCESS,
  sanitizeVehicleMaintenancePayload
} from '../../src/views/vms/vehicle-manage/maintenance-record/modules/maintenance-record-model'

const createMaintenance = (): Api.Vms.VehicleManage.VehicleMaintenanceRecord => ({
  id: 'maintenance-1',
  plateNo: '沪A12345',
  maintenanceNo: 'MAINTENANCE-001',
  maintenanceType: 'repair',
  startTime: '2026-08-22 09:00:00',
  costAmount: 2680,
  externalRepair: true,
  items: [{ itemName: '更换刹车片', partName: '刹车片', totalAmount: 1800 }],
  attachments: [{ name: 'invoice.pdf', url: 'https://example.test/invoice.pdf' }],
  fieldAccess: { ...EDITABLE_VEHICLE_MAINTENANCE_ACCESS },
  tenantId: 'tenant-1',
  createBy: 'creator@example.test',
  createTime: '2026-08-22T00:00:00Z',
  isRecordOwner: true
})

test('maintenance payload removes response-only metadata', () => {
  const payload = sanitizeVehicleMaintenancePayload(createMaintenance())

  assert.equal(payload.plateNo, '沪A12345')
  assert.equal('tenantId' in payload, false)
  assert.equal('createBy' in payload, false)
  assert.equal('createTime' in payload, false)
  assert.equal('fieldAccess' in payload, false)
  assert.equal('isRecordOwner' in payload, false)
})

test('maintenance payload omits sensitive groups without edit permission', () => {
  const payload = sanitizeVehicleMaintenancePayload({
    ...createMaintenance(),
    fieldAccess: {
      maintenanceIdentifiers: 'read',
      totalCost: 'masked',
      maintenanceItems: 'hidden',
      documents: 'read'
    }
  })

  assert.equal('maintenanceNo' in payload, false)
  assert.equal('costAmount' in payload, false)
  assert.equal('items' in payload, false)
  assert.equal('attachments' in payload, false)
})

test('maintenance payload keeps editable sensitive groups', () => {
  const payload = sanitizeVehicleMaintenancePayload(createMaintenance())

  assert.equal(payload.maintenanceNo, 'MAINTENANCE-001')
  assert.equal(payload.costAmount, 2680)
  assert.equal(payload.items?.length, 1)
  assert.equal(payload.attachments?.length, 1)
})
