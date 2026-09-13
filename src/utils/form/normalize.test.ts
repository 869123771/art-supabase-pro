import assert from 'node:assert/strict'
import test from 'node:test'
import {
  normalizeNonNullableText,
  normalizeNullableNumber,
  normalizeNullableText,
  normalizeStringList
} from './normalize'

test('non-nullable database text keeps blank input as an empty string', () => {
  assert.equal(normalizeNonNullableText(null), '')
  assert.equal(normalizeNonNullableText(undefined), '')
  assert.equal(normalizeNonNullableText('   '), '')
  assert.equal(normalizeNonNullableText('  公式说明  '), '公式说明')
})

test('nullable database text converts blank input to null', () => {
  assert.equal(normalizeNullableText(null), null)
  assert.equal(normalizeNullableText('   '), null)
  assert.equal(normalizeNullableText('  备注  '), '备注')
})

test('nullable number converts blank and invalid input to null', () => {
  assert.equal(normalizeNullableNumber(null), null)
  assert.equal(normalizeNullableNumber(''), null)
  assert.equal(normalizeNullableNumber('not-a-number'), null)
  assert.equal(normalizeNullableNumber('12.5'), 12.5)
})

test('string list normalizes empty, scalar and array select values', () => {
  assert.deepEqual(normalizeStringList(undefined), [])
  assert.deepEqual(normalizeStringList(42), ['42'])
  assert.deepEqual(normalizeStringList(['a', 2]), ['a', '2'])
})
