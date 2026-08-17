import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createInitialCustomerPriceForm,
  normalizeCustomerPricePayload
} from '../../src/views/tms/basic-data/customer-price-edit/modules/customer-price-model'

test('customer price payload trims fields and owns calculated totals', () => {
  const form = createInitialCustomerPriceForm()
  Object.assign(form, {
    customerId: 'customer-1',
    originRegionPath: ['上海市', '浦东新区'],
    destinationRegionPath: ['江苏省', '苏州市'],
    vehicleCount: '',
    transportFee: '10.105',
    insuranceFee: 2,
    cashAmount: 5,
    periodicAmount: '7.50',
    remark: '  测试价格  ',
    cargoItems: [
      { cargoName: '  配件  ', quantity: '2', unit: ' 箱 ', volumeM3: '1.25', weightKg: '3' },
      { cargoName: '  ', quantity: null, unit: '', volumeM3: null, weightKg: null }
    ]
  })

  const payload = normalizeCustomerPricePayload(form)

  assert.equal(payload.originRegion, '上海市/浦东新区')
  assert.equal(payload.destinationRegion, '江苏省/苏州市')
  assert.equal(payload.totalFee, 12.11)
  assert.equal(payload.paymentTotal, 12.5)
  assert.equal(payload.vehicleCount, null)
  assert.equal(payload.remark, '测试价格')
  assert.deepEqual(payload.cargoItems, [
    { cargoName: '配件', quantity: 2, unit: '箱', volumeM3: 1.25, weightKg: 3 }
  ])
  assert.equal(payload.cargoQuantityTotal, 2)
  assert.equal(payload.cargoVolumeTotal, 1.25)
  assert.equal(payload.cargoWeightTotal, 3)
  assert.equal('customerCode' in payload, false)
})
