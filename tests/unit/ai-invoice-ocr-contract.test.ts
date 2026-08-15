import assert from 'node:assert/strict'
import test from 'node:test'
import {
  coerceAiInvoiceOcrProviderPayload,
  compareAiInvoiceOcrPayloads,
  normalizeAiInvoiceOcrResponse,
  validateAiInvoiceOcrProviderPayload
} from '../../supabase/functions/_shared/ai-invoice-ocr-contract'

function createValidPayload() {
  return {
    rawText: '增值税专用发票\n发票号码：12345678',
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

test('AI invoice OCR contract adapts flat provider fields for manual review', () => {
  const payload = coerceAiInvoiceOcrProviderPayload({
    invoiceNo: '12345678',
    issueDate: '2026-08-05',
    totalAmount: '109.00'
  })

  assert.ok(payload)
  assert.deepEqual(validateAiInvoiceOcrProviderPayload(payload), { valid: true, errors: [] })
  const normalized = normalizeAiInvoiceOcrResponse(payload)
  assert.equal(normalized.invoice.invoiceNo, '12345678')
  assert.equal(normalized.invoice.totalAmount, 109)
  assert.equal(normalized.rawText, '')
  assert.equal(normalized.confidence, 0)
  assert.ok(normalized.warnings.some((warning) => warning.includes('人工复核')))
})

test('AI invoice OCR contract unwraps provider result envelopes', () => {
  const payload = coerceAiInvoiceOcrProviderPayload({
    result: {
      confidence: '0.95',
      fieldConfidence: { invoiceNo: '0.98' },
      invoice: { invoiceNo: '87654321', totalAmount: '88.50' }
    }
  })

  assert.ok(payload)
  assert.deepEqual(validateAiInvoiceOcrProviderPayload(payload), { valid: true, errors: [] })
  assert.equal(normalizeAiInvoiceOcrResponse(payload).invoice.totalAmount, 88.5)
})

test('AI invoice OCR contract unwraps a filled expectedShape echo', () => {
  const payload = coerceAiInvoiceOcrProviderPayload({
    direction: 'output',
    expectedShape: {
      confidence: 0.88,
      fieldConfidence: { taxRate: 0.8 },
      warnings: [],
      invoice: { invoiceNo: '12345678', taxRate: '9%', totalAmount: '436.00' }
    },
    visionExtraction: 'untrusted OCR text'
  })

  assert.ok(payload)
  assert.deepEqual(validateAiInvoiceOcrProviderPayload(payload), { valid: true, errors: [] })
  const normalized = normalizeAiInvoiceOcrResponse(payload)
  assert.equal(normalized.invoice.invoiceNo, '12345678')
  assert.equal(normalized.invoice.taxRate, 9)
  assert.equal(normalized.invoice.totalAmount, 436)
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

test('AI invoice OCR normalization rejects an amount-like invoice number', () => {
  const payload = createValidPayload()
  payload.invoice.invoiceNo = '215.841584158416'

  const result = normalizeAiInvoiceOcrResponse(payload)
  assert.equal(result.invoice.invoiceNo, null)
  assert.ok(result.missingFields.includes('发票号码'))
  assert.ok(result.warnings.some((warning) => warning.includes('发票号码格式异常')))
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
