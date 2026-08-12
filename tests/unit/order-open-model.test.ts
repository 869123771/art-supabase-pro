import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createInitialForm,
  normalizeOrderPayload
} from '../../src/views/tms-transportation/order-open/modules/order-open-model'

test('order payload normalizes monetary totals, stations and cargo summary', () => {
  const form = createInitialForm()
  Object.assign(form, {
    orderNo: ' ORD-1 ',
    originStationId: 'origin-1',
    destinationStationId: 'destination-1',
    transportFee: '10.105',
    deliveryFee: 2,
    cashAmount: 5,
    monthlyAmount: '7.50',
    cargoItems: [
      {
        cargoName: ' 配件 ',
        cargoId: ' cargo-1 ',
        cargoCode: ' HW001 ',
        packageType: ' 箱装 ',
        quantity: '2',
        unit: '箱',
        weightKg: '3.25',
        volumeM3: '1.125',
        unitPrice: '10.50',
        freight: '21',
        sourceContractId: ' contract-1 ',
        sourceContractNo: ' HT-001 ',
        sourceContractName: ' 年度合同 ',
        sourceContractDetailKey: ' contract-1:cargo-1 '
      }
    ]
  })

  const payload = normalizeOrderPayload({
    form,
    stationNames: { origin: '上海站', destination: '苏州站' }
  })

  assert.equal(payload.orderNo, 'ORD-1')
  assert.equal(payload.originStation, '上海站')
  assert.equal(payload.destinationStation, '苏州站')
  assert.equal(payload.totalFee, 12.11)
  assert.equal(payload.paymentTotal, 12.5)
  assert.equal(payload.cargoQuantityTotal, 2)
  assert.equal(payload.cargoWeightTotal, 3.25)
  assert.equal(payload.cargoVolumeTotal, 1.125)
  assert.equal(payload.cargoItems?.[0].sourceContractNo, 'HT-001')
  assert.equal(payload.cargoItems?.[0].unitPrice, 10.5)
  assert.equal('shippingCustomerName' in payload, false)
})
