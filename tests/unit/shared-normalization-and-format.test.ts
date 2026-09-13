import assert from 'node:assert/strict'
import test from 'node:test'
import {
  normalizeNonNullableText,
  normalizeNullableNumber,
  normalizeNullableText,
  normalizeStringList
} from '../../src/utils/form/normalize'
import { formatTenantLabel } from '../../src/utils/tenant-display'
import {
  createDateTimeFormatter,
  formatCnyCurrencyValue,
  formatPercentValue
} from '../../src/utils/ui/format'

test('shared form normalizers preserve database nullability semantics', () => {
  assert.equal(normalizeNonNullableText('  '), '')
  assert.equal(normalizeNonNullableText('  说明  '), '说明')
  assert.equal(normalizeNullableText('  '), null)
  assert.equal(normalizeNullableText('  备注  '), '备注')
  assert.equal(normalizeNullableNumber(''), null)
  assert.equal(normalizeNullableNumber('invalid'), null)
  assert.equal(normalizeNullableNumber('12.5'), 12.5)
  assert.deepEqual(normalizeStringList(undefined), [])
  assert.deepEqual(normalizeStringList([1, 'two']), ['1', 'two'])
})

test('shared UI formatters keep repeated display policies consistent', () => {
  assert.equal(formatCnyCurrencyValue(null), '¥0.00')
  assert.equal(formatPercentValue(null), '--')
  assert.equal(formatPercentValue(12.34), '12.3%')

  const formatMinute = createDateTimeFormatter({
    format: 'YYYY-MM-DD HH:mm',
    emptyText: '—',
    invalidText: '—'
  })
  assert.equal(formatMinute(null), '—')
  assert.equal(formatMinute('invalid'), '—')
  assert.equal(formatMinute('2026-09-13T08:30:00Z').length, 16)
})

test('tenant labels share one fallback and composition rule', () => {
  assert.equal(
    formatTenantLabel({ tenant: { tenantName: ' 亿企 ', tenantCode: ' YQ ' } }),
    '亿企（YQ）'
  )
  assert.equal(formatTenantLabel({ tenantId: 'tenant-id' }), 'tenant-id')
  assert.equal(formatTenantLabel({}), '未识别租户')
})
