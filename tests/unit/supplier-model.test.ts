import assert from 'node:assert/strict'
import test from 'node:test'
import {
  EDITABLE_SUPPLIER_ACCESS,
  sanitizeSupplierPayload
} from '../../src/views/vms/basic-info/supplier/modules/supplier-model'

const createSupplier = (): Api.Vms.BasicInfo.Supplier => ({
  id: 'supplier-1',
  supplierName: 'QA Supplier',
  contactPerson: 'Sensitive Contact',
  contactPhone: '13800138000',
  region: 'Sensitive Region',
  addressDetail: 'Sensitive Address',
  remark: 'Sensitive Note',
  fieldAccess: {},
  isRecordOwner: false
})

test('supplier payload removes response-only metadata', () => {
  const payload = sanitizeSupplierPayload({
    ...createSupplier(),
    fieldAccess: EDITABLE_SUPPLIER_ACCESS
  })
  assert.equal('fieldAccess' in payload, false)
  assert.equal('isRecordOwner' in payload, false)
})

test('supplier payload omits protected groups without edit permission', () => {
  const payload = sanitizeSupplierPayload(createSupplier())
  assert.equal('contactPerson' in payload, false)
  assert.equal('contactPhone' in payload, false)
  assert.equal('region' in payload, false)
  assert.equal('addressDetail' in payload, false)
  assert.equal('remark' in payload, false)
})

test('supplier payload keeps editable protected groups', () => {
  const payload = sanitizeSupplierPayload({
    ...createSupplier(),
    fieldAccess: EDITABLE_SUPPLIER_ACCESS
  })
  assert.equal(payload.contactPhone, '13800138000')
  assert.equal(payload.addressDetail, 'Sensitive Address')
  assert.equal(payload.remark, 'Sensitive Note')
})
