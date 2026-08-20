import assert from 'node:assert/strict'
import test from 'node:test'
import {
  canEditField,
  canViewField,
  formatSensitiveNumber,
  getFieldAccess,
  isMaskedValue,
  mergeFieldAccessMaps,
  omitNonEditableFields
} from '../../src/utils/field-permission'

test('field access defaults to hidden and keeps explicit levels', () => {
  assert.equal(getFieldAccess(undefined, 'amount'), 'hidden')
  assert.equal(getFieldAccess(undefined, 'amount', 'edit'), 'edit')
  assert.equal(getFieldAccess({ amount: 'masked' }, 'amount'), 'masked')
})

test('view and edit checks distinguish hidden, masked, read and edit', () => {
  const access = {
    secret: 'hidden',
    phone: 'masked',
    amount: 'read',
    price: 'edit'
  } as const

  assert.equal(canViewField(access, 'secret'), false)
  assert.equal(canViewField(access, 'phone'), true)
  assert.equal(canViewField(access, 'amount'), true)
  assert.equal(canEditField(access, 'amount'), false)
  assert.equal(canEditField(access, 'price'), true)
})

test('sensitive number formatting preserves masks and formats numeric values', () => {
  assert.equal(isMaskedValue('***'), true)
  assert.equal(formatSensitiveNumber('***'), '***')
  assert.equal(formatSensitiveNumber(null), '--')
  assert.equal(formatSensitiveNumber(1234.5), '1,234.50')
  assert.equal(formatSensitiveNumber('12.3456', { maximumFractionDigits: 4 }), '12.3456')
})

test('write payload helper removes every field without edit permission', () => {
  const payload = { name: '合同 A', amount: 1200, phone: '13800001234' }
  const result = omitNonEditableFields(payload, { amount: 'read', phone: 'edit' }, [
    'amount',
    'phone'
  ])

  assert.deepEqual(result, { name: '合同 A', phone: '13800001234' })
  assert.deepEqual(payload, { name: '合同 A', amount: 1200, phone: '13800001234' })
})

test('field access maps merge by the highest effective permission', () => {
  const result = mergeFieldAccessMaps(
    { phone: 'masked', amount: 'read' },
    { phone: 'read', amount: 'hidden', address: 'edit' },
    undefined
  )

  assert.deepEqual(result, { phone: 'read', amount: 'read', address: 'edit' })
})
