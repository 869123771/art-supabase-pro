import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createCustomerPriceBusinessPatch,
  createFavoriteRouteContactPatch,
  createInitialForm,
  formatOrderAddress,
  normalizeOrderPayload
} from '../../src/views/tms/order-open/modules/order-open-model'

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

test('customer price patch updates commercial values without touching either contact side', () => {
  const price: Api.Tms.BasicData.CustomerPrice = {
    customerId: 'customer-1',
    originRegion: '发货区域',
    destinationRegion: '收货区域',
    transportType: 'road',
    billingMethod: 'fixed',
    shippingContactName: '模板发货人',
    shippingContactPhone: '13000000001',
    shippingAddressDetail: '模板发货地址',
    receivingContactName: '模板收货人',
    receivingContactPhone: '13000000002',
    receivingAddressDetail: '模板收货地址',
    transportFee: 100,
    loadingFee: 20,
    fuelFee: 3,
    serviceFee: 2,
    otherFee: 5,
    collectAmount: 130,
    remark: '价格备注'
  }

  const patch = createCustomerPriceBusinessPatch(price, '原备注')

  assert.deepEqual(patch, {
    transportFee: 100,
    unloadingFee: 20,
    transferFee: 0,
    insuranceFee: 0,
    packageFee: 0,
    otherFee: 10,
    cashAmount: 0,
    collectAmount: 130,
    monthlyAmount: 0,
    orderRemark: '价格备注'
  })
  assert.equal('shippingCustomerId' in patch, false)
  assert.equal('shippingContactName' in patch, false)
  assert.equal('shippingAddressDetail' in patch, false)
  assert.equal('receivingCustomerId' in patch, false)
  assert.equal('receivingContactName' in patch, false)
  assert.equal('receivingAddressDetail' in patch, false)
})

test('favorite route patch fills both endpoint customers, contacts and addresses independently', () => {
  const route: Api.Tms.BasicData.FavoriteRoute = {
    id: 'route-1',
    routeName: '矿区到仓库',
    customerId: 'route-owner',
    customer: { id: 'route-owner', customerName: '线路所属客户' },
    originAddressId: 'origin-address',
    destinationAddressId: 'destination-address',
    enabled: true,
    originAddress: {
      id: 'origin-address',
      customerId: 'shipper-1',
      customer: { id: 'shipper-1', customerName: '发货客户' },
      addressType: 'shipping',
      contactName: '发货联系人',
      contactPhone: '13000000001',
      region: '河南省/许昌市/禹州市',
      addressDetail: '矿区一号门',
      longitude: 113.4,
      latitude: 34.1
    },
    destinationAddress: {
      id: 'destination-address',
      customerId: 'receiver-1',
      customer: { id: 'receiver-1', customerName: '收货客户' },
      addressType: 'receiving',
      contactName: '收货联系人',
      contactPhone: '13000000002',
      region: '山西省/长治市/潞州区',
      addressDetail: '仓库二号门',
      longitude: 113.1,
      latitude: 36.2
    }
  }

  assert.deepEqual(createFavoriteRouteContactPatch(route), {
    shippingCustomerId: 'shipper-1',
    shippingCustomerName: '发货客户',
    shippingAddressId: 'origin-address',
    shippingContactName: '发货联系人',
    shippingContactPhone: '13000000001',
    shippingAddressDetail: '河南省/许昌市/禹州市 矿区一号门',
    shippingLongitude: 113.4,
    shippingLatitude: 34.1,
    receivingCustomerId: 'receiver-1',
    receivingCustomerName: '收货客户',
    receivingAddressId: 'destination-address',
    receivingContactName: '收货联系人',
    receivingContactPhone: '13000000002',
    receivingAddressDetail: '山西省/长治市/潞州区 仓库二号门',
    receivingLongitude: 113.1,
    receivingLatitude: 36.2
  })
  assert.equal(
    formatOrderAddress('河南省/许昌市/禹州市', '河南省许昌市禹州市矿区一号门'),
    '河南省许昌市禹州市矿区一号门'
  )
})
