import assert from 'node:assert/strict'
import test from 'node:test'
import {
  compareAiInvoiceOcrPayloads,
  normalizeAiInvoiceOcrResponse,
  validateAiInvoiceOcrProviderPayload
} from '../../supabase/functions/_shared/ai-invoice-ocr-contract'

function createValidPayload() {
  return {
    summary: '识别到一张增值税专用发票',
    confidence: 0.96,
    fieldConfidence: { invoiceNo: 0.99, totalAmount: 0.98 },
    missingFields: [],
    warnings: [],
    invoice: {
      invoiceType: 'vat_special',
      invoiceTitle: '杭州示例物流有限公司',
      taxNumber: '91330100TEST000001',
      invoiceCode: '033002300111',
      invoiceNo: '12345678',
      issueDate: '2026-08-05',
      taxRate: 9,
      amountExcludingTax: 100,
      taxAmount: 9,
      totalAmount: 109,
      buyerName: '杭州示例物流有限公司',
      buyerTaxNumber: '91330100TEST000001',
      sellerName: '上海示例供应链有限公司',
      sellerTaxNumber: '91310100TEST000002'
    }
  }
}

test('AI invoice OCR contract accepts a valid provider payload', () => {
  assert.deepEqual(validateAiInvoiceOcrProviderPayload(createValidPayload()), {
    valid: true,
    errors: []
  })
})

test('AI invoice OCR contract rejects unsafe values', () => {
  const payload = createValidPayload()
  payload.confidence = 1.2
  payload.invoice.taxAmount = -1

  const result = validateAiInvoiceOcrProviderPayload(payload)
  assert.equal(result.valid, false)
  assert.ok(result.errors.some((error) => error.includes('confidence')))
  assert.ok(result.errors.some((error) => error.includes('taxAmount')))
})

test('AI invoice OCR normalization standardizes dates and flags amount mismatch', () => {
  const payload = createValidPayload()
  payload.invoice.issueDate = '2026年8月5日'
  payload.invoice.totalAmount = 110

  const result = normalizeAiInvoiceOcrResponse(payload)
  assert.equal(result.invoice.issueDate, '2026-08-05')
  assert.ok(result.warnings.some((warning) => warning.includes('金额勾稽不一致')))
})

test('AI invoice OCR comparison records accepted and corrected fields', () => {
  const proposed = createValidPayload().invoice
  assert.deepEqual(compareAiInvoiceOcrPayloads(proposed, { ...proposed, invoiceNo: '87654321' }), {
    acceptedFields: [
      'invoiceType',
      'invoiceTitle',
      'taxNumber',
      'invoiceCode',
      'issueDate',
      'taxRate',
      'amountExcludingTax',
      'taxAmount',
      'totalAmount'
    ],
    correctedFields: ['invoiceNo']
  })
})
