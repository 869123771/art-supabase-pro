import assert from 'node:assert/strict'
import test from 'node:test'
import {
  calculateCargoSummary,
  formatNumber,
  joinRegionPath,
  mergeCargoSelections,
  normalizeMoney,
  normalizeNullableNumber,
  normalizeText,
  splitRegionPath
} from '../../src/views/tms/basic-data/modules/price-form-utils'

test('calculateCargoSummary handles mixed numeric values and domain precision', () => {
  const result = calculateCargoSummary([
    { quantity: 1, volumeM3: '1.2345', weightKg: 2.345 },
    { quantity: '2', volumeM3: 0.001, weightKg: null },
    { quantity: 'invalid', volumeM3: undefined, weightKg: '1.005' }
  ])

  assert.deepEqual(result, {
    quantity: 3,
    volume: 1.235,
    weight: 3.35
  })
})

test('mergeCargoSelections replaces an empty row and removes duplicate selections', () => {
  const result = mergeCargoSelections(
    [{ cargoName: '', quantity: null }],
    [
      { cargoName: '纸箱', unit: 'box' },
      { cargoName: '纸箱', unit: 'piece' },
      { cargoName: '托盘', unit: 'piece' }
    ],
    (cargo) => ({ ...cargo, quantity: 1 })
  )

  assert.equal(result.addedCount, 2)
  assert.deepEqual(
    result.items.map((item) => item.cargoName),
    ['纸箱', '托盘']
  )
})

test('mergeCargoSelections keeps current rows and ignores already selected cargo', () => {
  const currentItems = [{ cargoName: '纸箱', quantity: 3 }]
  const result = mergeCargoSelections(
    currentItems,
    [{ cargoName: '纸箱' }, { cargoName: '托盘' }],
    (cargo) => ({ ...cargo, quantity: 1 })
  )

  assert.equal(result.addedCount, 1)
  assert.deepEqual(result.items, [currentItems[0], { cargoName: '托盘', quantity: 1 }])
})

test('price field normalizers keep API payloads predictable', () => {
  assert.equal(normalizeText('  备注  '), '备注')
  assert.equal(normalizeText('  '), null)
  assert.equal(normalizeNullableNumber(''), null)
  assert.equal(normalizeNullableNumber('12.5'), 12.5)
  assert.equal(normalizeMoney('12.345'), 12.35)
  assert.equal(formatNumber('12.340', 3), '12.34')
})

test('region paths round-trip through the API representation', () => {
  assert.deepEqual(splitRegionPath(' 浙江省 / 杭州市 / 西湖区 '), ['浙江省', '杭州市', '西湖区'])
  assert.equal(joinRegionPath(['浙江省', '杭州市', '西湖区']), '浙江省/杭州市/西湖区')
})
