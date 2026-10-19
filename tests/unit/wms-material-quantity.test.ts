import assert from 'node:assert/strict'
import { test } from 'node:test'
import { convertWmsMaterialQuantity } from '../../src/utils/wms/material-quantity'

const material = {
  baseUnitId: 'piece',
  unitConversions: [
    { sourceUnitId: 'box', sourceFactor: 1, baseFactor: 12 },
    { sourceUnitId: 'case', sourceFactor: 1, baseFactor: 60 }
  ]
}

test('库存单位、基本单位与辅助单位按同一物料换算关系计算', () => {
  assert.equal(convertWmsMaterialQuantity(material, 2, 'box', 'piece'), 24)
  assert.equal(convertWmsMaterialQuantity(material, 24, 'piece', 'case'), 0.4)
  assert.equal(convertWmsMaterialQuantity(material, 2, 'box', 'case'), 0.4)
})

test('缺失或无效的换算关系阻止错误数量', () => {
  assert.equal(convertWmsMaterialQuantity(material, 2, 'unknown', 'piece'), null)
  assert.equal(convertWmsMaterialQuantity(material, -1, 'box', 'piece'), null)
  assert.equal(convertWmsMaterialQuantity({ baseUnitId: 'piece' }, 1, 'box', 'piece'), null)
})
