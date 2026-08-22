import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EDITABLE_VEHICLE_INSURANCE_ACCESS,
  sanitizeVehicleInsurancePayload
} from '../../src/views/vms/vehicle-manage/vehicle-insurance/modules/vehicle-insurance-model'

const createInsurance = (): Api.Vms.VehicleManage.VehicleInsurance => ({
  id: 'insurance-1',
  plateNo: '沪A12345',
  commercialPolicyNo: 'COMMERCIAL-001',
  commercialPremium: 12000,
  compulsoryPolicyNo: 'COMPULSORY-001',
  compulsoryPremium: 1200,
  attachments: [{ name: 'policy.pdf', url: 'https://example.test/policy.pdf' }],
  fieldAccess: { ...EDITABLE_VEHICLE_INSURANCE_ACCESS },
  tenantId: 'tenant-1',
  createBy: 'creator@example.test',
  createTime: '2026-08-22T00:00:00Z',
  isRecordOwner: true
})

test('vehicle insurance payload removes response-only metadata', () => {
  const payload = sanitizeVehicleInsurancePayload(createInsurance())

  assert.equal(payload.plateNo, '沪A12345')
  assert.equal('tenantId' in payload, false)
  assert.equal('createBy' in payload, false)
  assert.equal('createTime' in payload, false)
  assert.equal('fieldAccess' in payload, false)
  assert.equal('isRecordOwner' in payload, false)
})

test('vehicle insurance payload omits sensitive groups without edit permission', () => {
  const payload = sanitizeVehicleInsurancePayload({
    ...createInsurance(),
    fieldAccess: {
      policyNumbers: 'read',
      premiumAmounts: 'masked',
      documents: 'hidden'
    }
  })

  assert.equal('commercialPolicyNo' in payload, false)
  assert.equal('compulsoryPolicyNo' in payload, false)
  assert.equal('commercialPremium' in payload, false)
  assert.equal('compulsoryPremium' in payload, false)
  assert.equal('attachments' in payload, false)
})

test('vehicle insurance payload keeps editable sensitive groups', () => {
  const payload = sanitizeVehicleInsurancePayload(createInsurance())

  assert.equal(payload.commercialPolicyNo, 'COMMERCIAL-001')
  assert.equal(payload.commercialPremium, 12000)
  assert.equal(payload.compulsoryPolicyNo, 'COMPULSORY-001')
  assert.equal(payload.compulsoryPremium, 1200)
  assert.equal(payload.attachments?.length, 1)
})
