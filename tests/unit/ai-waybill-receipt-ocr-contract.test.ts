import assert from 'node:assert/strict'
import test from 'node:test'
import {
  assessAiWaybillReceipt,
  normalizeAiWaybillReceiptResponse,
  validateAiWaybillReceiptProviderPayload
} from '../../supabase/functions/_shared/ai-waybill-receipt-ocr-contract'

function validPayload() {
  return {
    summary: '识别到正常签收回单',
    confidence: 0.94,
    fieldConfidence: { waybillNo: 0.99, signerName: 0.9, signedAt: 0.88 },
    missingFields: [],
    warnings: [],
    receipt: {
      waybillNo: 'YDHZ20260805001',
      signerName: '张三',
      signedAt: '2026-08-05 15:30:00+08:00',
      deliveryResult: 'normal',
      signedQuantity: 20,
      damagedQuantity: 0,
      shortageQuantity: 0,
      exceptionNote: null
    }
  }
}

test('waybill receipt contract accepts a valid provider payload', () => {
  assert.deepEqual(validateAiWaybillReceiptProviderPayload(validPayload()), {
    valid: true,
    errors: []
  })
})

test('waybill receipt normalization produces an ISO signing time', () => {
  const result = normalizeAiWaybillReceiptResponse(validPayload())
  assert.equal(result.receipt.signedAt, '2026-08-05T07:30:00.000Z')
  assert.equal(result.missingFields.length, 0)
})

test('waybill receipt assessment blocks a mismatched or refused receipt', () => {
  const payload = validPayload()
  payload.receipt.waybillNo = 'ANOTHER-WAYBILL'
  payload.receipt.deliveryResult = 'refused'
  const receipt = normalizeAiWaybillReceiptResponse(payload).receipt
  const result = assessAiWaybillReceipt(receipt, {
    orderNo: 'YDHZ20260805001',
    receiverName: '张三',
    cargoQuantityTotal: 20
  })

  assert.equal(result.riskLevel, 'critical')
  assert.equal(result.recommendedAction, 'block_completion')
  assert.ok(result.signals.some((item) => item.type === 'waybill_no_mismatch'))
  assert.ok(result.signals.some((item) => item.type === 'delivery_refused'))
})

test('waybill receipt assessment flags quantity shortage', () => {
  const payload = validPayload()
  payload.receipt.signedQuantity = 18
  const receipt = normalizeAiWaybillReceiptResponse(payload).receipt
  const result = assessAiWaybillReceipt(receipt, {
    orderNo: 'YDHZ20260805001',
    cargoQuantityTotal: 20
  })

  assert.equal(result.riskLevel, 'high')
  assert.ok(result.signals.some((item) => item.type === 'quantity_mismatch'))
})
