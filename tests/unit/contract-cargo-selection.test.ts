import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createContractDetailFromCargo,
  mergeContractCargoSelections
} from '../../src/views/tms/basic-data/contract/modules/contract-cargo-selection'

type Cargo = Api.Tms.BasicData.Cargo
type ContractTransportDetail = Api.Tms.BasicData.ContractTransportDetail

const cargo = (id: string, cargoName: string, cargoCode: string, unit: string): Cargo => ({
  id,
  cargoName,
  cargoCode,
  unit
})

test('从货物主档创建合同明细时带入可用字段并初始化合同字段', () => {
  assert.deepEqual(createContractDetailFromCargo(cargo('cargo-1', '矿石', 'HW001', 'ton')), {
    cargoId: 'cargo-1',
    cargoDescription: '矿石',
    cargoCode: 'HW001',
    contractQuantity: 1,
    unit: 'ton',
    transportUnitPrice: 0,
    freight: 0
  })
})

test('批量选择替换唯一空白行并去除重复货物', () => {
  const placeholder: ContractTransportDetail = {
    cargoId: null,
    cargoDescription: '',
    cargoCode: '',
    contractQuantity: 1,
    unit: '',
    transportUnitPrice: 0,
    freight: 0
  }
  const selected = cargo('cargo-1', '矿石', 'HW001', 'ton')

  const result = mergeContractCargoSelections([placeholder], [selected, selected])

  assert.equal(result.addedCount, 1)
  assert.deepEqual(result.items, [createContractDetailFromCargo(selected)])
})

test('批量选择不会覆盖已有合同数量和价格，也不会重复追加同一货物', () => {
  const existing: ContractTransportDetail = {
    cargoId: 'cargo-1',
    cargoDescription: '矿石',
    cargoCode: 'HW001',
    contractQuantity: 88,
    unit: 'ton',
    transportUnitPrice: 120,
    freight: 10560
  }
  const newCargo = cargo('cargo-2', '钢材', 'HW002', 'piece')

  const result = mergeContractCargoSelections(
    [existing],
    [cargo('cargo-1', '矿石新名称', 'NEW001', 'kg'), newCargo]
  )

  assert.equal(result.addedCount, 1)
  assert.deepEqual(result.items, [existing, createContractDetailFromCargo(newCargo)])
})
