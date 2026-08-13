import assert from 'node:assert/strict'
import test from 'node:test'
import { usesCarrierParty } from '../../src/views/tms-transportation/basic-data/contract/modules/contract-business-type'

test('承运商合同以承运商为合同相对方', () => {
  assert.equal(usesCarrierParty('carrier'), true)
})

test('企业/货主端合同以客户或货主为合同相对方', () => {
  assert.equal(usesCarrierParty('customer'), false)
})
