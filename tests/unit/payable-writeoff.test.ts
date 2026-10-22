import assert from 'node:assert/strict'
import { describe, it } from 'node:test'
import { allocatePayableWriteoff } from '../../src/utils/finance/payable-writeoff'
import {
  newPayableSettlementLine,
  validateSettlementAmounts
} from '../../src/utils/finance/payable-settlement'

describe('payable writeoff allocation', () => {
  it('splits multiple sides exactly in cents without mutating inputs', () => {
    const primary = [
      { id: 'ap1', availableAmount: 0.1 },
      { id: 'ap2', availableAmount: 0.2 }
    ]
    const secondary = [
      { id: 'pay1', availableAmount: 0.15 },
      { id: 'pay2', availableAmount: 0.15 }
    ]
    assert.deepEqual(allocatePayableWriteoff(primary, secondary), [
      { payableId: 'ap1', paymentLineId: 'pay1', amount: 0.1 },
      { payableId: 'ap2', paymentLineId: 'pay1', amount: 0.05 },
      { payableId: 'ap2', paymentLineId: 'pay2', amount: 0.15 }
    ])
    assert.equal(primary[0].availableAmount, 0.1)
  })
  it('rejects missing sides, excess, invalid amounts and unequal totals', () => {
    assert.throws(() => allocatePayableWriteoff([], []), /分别选择/)
    assert.throws(
      () =>
        allocatePayableWriteoff(
          [{ id: 'ap', availableAmount: 100, writeoffAmount: 101 }],
          [{ id: 'pay', availableAmount: 101 }]
        ),
      /不能超过/
    )
    assert.throws(
      () =>
        allocatePayableWriteoff(
          [{ id: 'ap', availableAmount: 100, writeoffAmount: NaN }],
          [{ id: 'pay', availableAmount: 100 }]
        ),
      /本次核销金额/
    )
    assert.throws(
      () =>
        allocatePayableWriteoff(
          [{ id: 'ap', availableAmount: 100 }],
          [{ id: 'pay', availableAmount: 99.99 }]
        ),
      /合计须一致/
    )
  })
  it('validates multi-party settlement details and approval limits', () => {
    const line = {
      ...newPayableSettlementLine(10),
      purposeId: 'purpose',
      supplierId: 'supplier',
      payeeSupplierId: 'supplier',
      settlementMethodId: 'method',
      amount: 100,
      approvedAmount: 90,
      plannedAmount: 80
    }
    assert.equal(validateSettlementAmounts([line]), null)
    assert.match(validateSettlementAmounts([{ ...line, approvedAmount: 101 }]) || '', /金额不正确/)
    assert.match(validateSettlementAmounts([{ ...line, supplierId: null }]) || '', /往来单位/)
  })
})
