import assert from 'node:assert/strict'
import test from 'node:test'
import {
  normalizeImportedEnabled,
  normalizeNonNullableText,
  normalizeNullableNumber,
  normalizeNullableText,
  normalizeSingleStringKey,
  normalizeStringList
} from '../../src/utils/form/normalize'
import { formatTenantLabel } from '../../src/utils/tenant-display'
import {
  createDateTimeFormatter,
  formatArtValue,
  formatCurrencyCodeValue,
  formatNumberValue,
  formatDurationMs,
  formatCnyCurrencyValue,
  formatCurrencyValue,
  formatSensitiveCurrencyValue,
  formatSensitiveCountValue,
  formatDateTimeValue,
  formatPercentValue
} from '../../src/utils/ui/format'

test('currency code amounts preserve protected text and operational currency precision', () => {
  assert.equal(formatCurrencyCodeValue(1234.5678), 'CNY 1,234.568')
  assert.equal(formatCurrencyCodeValue(0, 'USD'), 'USD 0.00')
  assert.equal(formatCurrencyCodeValue(-1234.5, 'EUR'), 'EUR -1,234.50')
  assert.equal(formatCurrencyCodeValue(null), '--')
  assert.equal(formatCurrencyCodeValue(undefined), '--')
  for (const text of ['***', '金额受控', '1234.500', '']) {
    assert.equal(formatCurrencyCodeValue(text), text)
  }
})

test('currency precision separates integer budgets from decimal amounts in the formatter cache', () => {
  assert.equal(formatSensitiveCurrencyValue(1234.5, 'CNY', 'zh-CN', 0), '¥1,235')
  assert.equal(formatSensitiveCurrencyValue(1234.5), '¥1,234.50')
  assert.equal(formatSensitiveCurrencyValue(0, 'USD', 'en-US', 0), '$0')
  assert.equal(formatSensitiveCurrencyValue(-1234.5, 'EUR', 'en-US', 0), '-€1,235')
  assert.equal(formatSensitiveCurrencyValue(null, 'CNY', 'zh-CN', 0), '--')
  assert.equal(formatSensitiveCurrencyValue('***', 'CNY', 'zh-CN', 0), '***')
  assert.equal(formatCurrencyValue(1234.5, 'CNY', 'zh-CN', 0), '¥1,235')
  assert.equal(formatCurrencyValue(1234.5), '¥1,234.50')
})

test('operational precision uses locale grouping without changing default number and percent policies', () => {
  const numberFormat = { maximumFractionDigits: 2 }
  assert.equal(formatNumberValue(1234.567, 'zh-CN', numberFormat), '1,234.57')
  assert.equal(formatNumberValue(1.2, 'zh-CN', numberFormat), '1.2')
  assert.equal(formatNumberValue(0, 'zh-CN', numberFormat), '0')
  assert.equal(formatNumberValue(1234.567), '1,234.567')
  assert.equal(formatArtValue(1234.567, 'number', { numberFormat }), '1,234.57')
  assert.equal(formatPercentValue(1234.567, { numberFormat }), '1,234.57%')
  assert.equal(formatPercentValue(1.2, { numberFormat }), '1.2%')
  assert.equal(formatPercentValue(0, { numberFormat }), '0%')
  assert.equal(formatPercentValue(null, { numberFormat }), '--')
  assert.equal(formatPercentValue('***', { numberFormat }), '***')
  assert.equal(formatPercentValue(1.2, { fractionDigits: 2 }), '1.20%')
})

test('imported status preserves explicit disabled values and defaults omitted status to enabled', () => {
  for (const value of [false, 'false', '停用', '否'])
    assert.equal(normalizeImportedEnabled(value), false)
  for (const value of [true, 'true', '启用', '是', undefined, null, '', 0])
    assert.equal(normalizeImportedEnabled(value), true)
})

test('millisecond telemetry uses one precision, unit and unavailable-value policy', () => {
  for (const value of [undefined, null, -1, Number.NaN, Number.POSITIVE_INFINITY]) {
    assert.equal(formatDurationMs(value), '--')
  }
  assert.equal(formatDurationMs(0), '0 ms')
  assert.equal(formatDurationMs(34.6), '35 ms')
  assert.equal(formatDurationMs(999), '999 ms')
  assert.equal(formatDurationMs(820), '820 ms')
  assert.equal(formatDurationMs(1000), '1.00 s')
  assert.equal(formatDurationMs(1234), '1.23 s')
  assert.equal(formatDurationMs(1250), '1.25 s')
  assert.equal(formatDurationMs(9999), '10.00 s')
  assert.equal(formatDurationMs(10_000), '10.0 s')
  assert.equal(formatDurationMs(12345), '12.3 s')
})

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

test('single-select string keys preserve zero and use only the first selected key', () => {
  for (const value of [null, undefined, []])
    assert.equal(normalizeSingleStringKey(value), undefined)
  assert.equal(normalizeSingleStringKey(0), '0')
  assert.equal(normalizeSingleStringKey(''), '')
  assert.equal(normalizeSingleStringKey('employee-id'), 'employee-id')
  assert.equal(normalizeSingleStringKey([0, 'second-id']), '0')
  assert.equal(normalizeSingleStringKey(['first-id', 'second-id']), 'first-id')
  const keys = ['first-id', 'second-id'] as const
  assert.equal(normalizeSingleStringKey(keys), 'first-id')
  assert.deepEqual(keys, ['first-id', 'second-id'])
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
  assert.equal(formatSensitiveCurrencyValue(0, 'USD', 'en-US'), '$0.00')
  assert.equal(formatSensitiveCurrencyValue(-1234.5, 'USD', 'en-US'), '-$1,234.50')
  assert.equal(formatSensitiveCurrencyValue('01234.50', 'USD', 'en-US'), '$1,234.50')
  assert.equal(formatSensitiveCurrencyValue('不可用', 'USD', 'en-US'), '不可用')
  assert.equal(formatSensitiveCurrencyValue(1234.5, 'EUR', 'en-US'), '€1,234.50')
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
  assert.equal(formatMinute(undefined), '—')
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
