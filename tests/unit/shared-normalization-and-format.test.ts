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
  formatCurrencyValue,
  formatSensitiveCurrencyValue,
  formatSensitiveCountValue,
  formatDateTimeValue,
  formatPercentValue
} from '../../src/utils/ui/format'

test('shared form normalizers preserve database nullability semantics', () => {
  assert.equal(normalizeNonNullableText(null), '')
  assert.equal(normalizeNonNullableText(undefined), '')
  assert.equal(normalizeNonNullableText('  '), '')
  assert.equal(normalizeNonNullableText('  说明  '), '说明')
  assert.equal(normalizeNullableText('  '), null)
  assert.equal(normalizeNullableText(null), null)
  assert.equal(normalizeNullableText('  备注  '), '备注')
  assert.equal(normalizeNullableNumber(''), null)
  assert.equal(normalizeNullableNumber(null), null)
  assert.equal(normalizeNullableNumber('invalid'), null)
  assert.equal(normalizeNullableNumber('12.5'), 12.5)
  assert.equal(normalizeNullableNumber(' \t\n '), null)
  assert.equal(normalizeNullableNumber(0), 0)
  assert.equal(normalizeNullableNumber(' 0 '), 0)
  for (const value of [true, false, [], [12], {}, Number.NaN, Number.POSITIVE_INFINITY])
    assert.equal(normalizeNullableNumber(value), null)
  assert.deepEqual(normalizeStringList(undefined), [])
  assert.deepEqual(normalizeStringList(42), ['42'])
  assert.deepEqual(normalizeStringList([1, 'two']), ['1', 'two'])
})

test('shared UI formatters keep repeated display policies consistent', () => {
  assert.equal(formatCnyCurrencyValue(null), '¥0.00')
  assert.equal(formatCurrencyValue(1234.5, 'USD', 'en-US'), '$1,234.50')
  assert.equal(formatCurrencyValue('invalid'), 'invalid')
  assert.equal(formatSensitiveCurrencyValue(null), '--')
  assert.equal(formatSensitiveCurrencyValue(''), '--')
  assert.equal(formatSensitiveCurrencyValue('***'), '***')
  assert.equal(formatSensitiveCurrencyValue(1234.5), '¥1,234.50')
  assert.equal(formatSensitiveCurrencyValue(1234.5, 'USD', 'en-US'), '$1,234.50')
  assert.equal(formatSensitiveCurrencyValue('***', 'USD'), '***')
  assert.equal(formatSensitiveCurrencyValue(undefined, 'USD'), '--')
  assert.equal(formatPercentValue(null), '--')
  assert.equal(formatPercentValue(12.34), '12.3%')
  assert.equal(formatDateTimeValue(null), '--')
  assert.equal(formatDateTimeValue(''), '--')
  assert.equal(formatDateTimeValue('2026-09-13 08:30:00'), '2026-09-13 08:30:00')

  const formatMinute = createDateTimeFormatter({
    format: 'YYYY-MM-DD HH:mm',
    emptyText: '—',
    invalidText: '—'
  })
  assert.equal(formatMinute(null), '—')
  assert.equal(formatMinute('invalid'), '—')
  assert.equal(formatMinute('2026-09-13T08:30:00Z').length, 16)
  assert.equal(createDateTimeFormatter({ format: 'YYYY-MM-DD' })('2026-09-13'), '2026-09-13')
})

test('sensitive counts preserve masks, numeric strings and unavailable values', () => {
  assert.equal(formatSensitiveCountValue(undefined), '--')
  assert.equal(formatSensitiveCountValue(null), '--')
  assert.equal(formatSensitiveCountValue(''), '--')
  assert.equal(formatSensitiveCountValue('***'), '***')
  assert.equal(formatSensitiveCountValue('01234'), '01234')
  assert.equal(formatSensitiveCountValue('不可用'), '不可用')
  assert.equal(formatSensitiveCountValue(1234), '1,234')
  assert.equal(formatSensitiveCountValue(0), '0')
})

test('tenant labels share one fallback and composition rule', () => {
  assert.equal(
    formatTenantLabel({ tenant: { tenantName: ' 亿企 ', tenantCode: ' YQ ' } }),
    '亿企（YQ）'
  )
  assert.equal(formatTenantLabel({ tenantId: 'tenant-id' }), 'tenant-id')
  assert.equal(formatTenantLabel({}), '未识别租户')
})
