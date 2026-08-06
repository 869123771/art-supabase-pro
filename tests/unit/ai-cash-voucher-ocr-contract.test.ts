import assert from 'node:assert/strict'
import test from 'node:test'
import {
  matchAiCashVoucherStatements,
  normalizeAiCashVoucherResponse,
  validateAiCashVoucherProviderPayload
} from '../../supabase/functions/_shared/ai-cash-voucher-ocr-contract'

function validPayload() {
  return {
    summary: '识别到银行转账回单',
    confidence: 0.96,
    fieldConfidence: { amount: 0.99, transactionDate: 0.97, payerName: 0.9 },
    missingFields: [],
    warnings: [],
    voucher: {
      payerName: '杭州示例科技有限公司',
      payeeName: '杭州物流有限公司',
      transactionDate: '2026年8月5日',
      amount: 1000,
      bankReference: '支付 CS202608-001',
      paymentMethod: 'bank_transfer'
    }
  }
}

test('cash voucher contract accepts and normalizes a valid payload', () => {
  const payload = validPayload()
  assert.deepEqual(validateAiCashVoucherProviderPayload(payload), { valid: true, errors: [] })
  assert.equal(normalizeAiCashVoucherResponse(payload).voucher.transactionDate, '2026-08-05')
})

test('cash voucher matching prioritizes amount and counterparty matches', () => {
  const voucher = normalizeAiCashVoucherResponse(validPayload()).voucher
  const result = matchAiCashVoucherStatements(voucher, 'receipt', [
    {
      statementId: 'statement-best',
      statementNo: 'CS202608-001',
      counterpartyId: 'customer-1',
      counterpartyName: '杭州示例科技有限公司',
      periodStart: '2026-08-01',
      periodEnd: '2026-08-31',
      statementAmount: 1000,
      settledAmount: 0,
      outstandingAmount: 1000
    },
    {
      statementId: 'statement-other',
      statementNo: 'CS202608-002',
      counterpartyId: 'customer-2',
      counterpartyName: '其他客户有限公司',
      periodStart: '2026-08-01',
      periodEnd: '2026-08-31',
      statementAmount: 3000,
      settledAmount: 0,
      outstandingAmount: 3000
    }
  ])

  assert.equal(result[0].statementId, 'statement-best')
  assert.equal(result[0].score, 100)
  assert.equal(result[0].recommendedAllocation, 1000)
})

test('cash voucher contract rejects negative amounts', () => {
  const payload = validPayload()
  payload.voucher.amount = -1
  const result = validateAiCashVoucherProviderPayload(payload)
  assert.equal(result.valid, false)
  assert.ok(result.errors.some((item) => item.includes('amount')))
})
