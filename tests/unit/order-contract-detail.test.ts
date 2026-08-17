import assert from 'node:assert/strict'
import test from 'node:test'
import {
  calculateContractCargoFreight,
  calculateContractTransportFee,
  createCargoItemFromContractDetail,
  mergeOrderContractDetails
} from '../../src/views/tms/order-open/modules/order-contract-detail'
import { createInitialCargoItem } from '../../src/views/tms/order-open/modules/order-open-model'

type ContractDetail = Api.Tms.BasicData.ContractDetailSelectorItem

const detail = (overrides: Partial<ContractDetail> = {}): ContractDetail => ({
  key: 'contract-1:cargo-1',
  contractId: 'contract-1',
  contractNo: 'HT-001',
  contractName: '年度运输合同',
  cargoId: 'cargo-1',
  cargoDescription: '矿石',
  cargoCode: 'HW001',
  contractQuantity: 100,
  unit: 'ton',
  transportUnitPrice: 12.5,
  freight: 1250,
  ...overrides
})

test('合同明细带入订单货物快照，本次数量默认 1', () => {
  assert.deepEqual(createCargoItemFromContractDetail(detail()), {
    cargoId: 'cargo-1',
    cargoName: '矿石',
    cargoCode: 'HW001',
    packageType: 'ton',
    quantity: 1,
    unit: 'ton',
    weightKg: null,
    volumeM3: null,
    unitPrice: 12.5,
    freight: 12.5,
    sourceContractId: 'contract-1',
    sourceContractNo: 'HT-001',
    sourceContractName: '年度运输合同',
    sourceContractDetailKey: 'contract-1:cargo-1'
  })
})

test('按合同明细来源去重并替换唯一空白行', () => {
  const result = mergeOrderContractDetails(
    [createInitialCargoItem()],
    [detail(), detail(), detail({ key: 'contract-2:cargo-1', contractId: 'contract-2' })]
  )

  assert.equal(result.addedCount, 2)
  assert.equal(result.items.length, 2)
})

test('行运费按本次数量乘合同单价计算并汇总', () => {
  const first = createCargoItemFromContractDetail(detail())
  first.quantity = 3
  const second = createCargoItemFromContractDetail(
    detail({ key: 'contract-2:cargo-2', contractId: 'contract-2', transportUnitPrice: 8 })
  )
  second.quantity = 2

  assert.equal(calculateContractCargoFreight(first), 37.5)
  assert.equal(calculateContractTransportFee([first, second]), 53.5)
})
