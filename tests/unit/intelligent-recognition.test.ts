import assert from 'node:assert/strict'
import test from 'node:test'
import {
  buildRecognitionBusinessRoute,
  toCashVoucherOcrAnalyzeResponse,
  toInvoiceOcrAnalyzeResponse,
  toWaybillExpenseOcrAnalyzeResponse
} from '../../src/utils/intelligent-recognition'
import { financePaths } from '../../src/router/business-paths'

function createArtifact(
  feature: Api.IntelligentRecognition.Feature,
  proposedPayload: Record<string, unknown>
): Api.IntelligentRecognition.RecognitionArtifact {
  return {
    id: 'artifact-id',
    aiRunId: 'run-id',
    authUserId: 'user-id',
    feature,
    artifactType: 'draft',
    status: 'pending',
    proposedPayload,
    rawOcrText: '原始识别内容',
    createTime: '2026-08-10T00:00:00Z'
  }
}

test('cash voucher artifact normalizes untrusted payload fields', () => {
  const response = toCashVoucherOcrAnalyzeResponse(
    createArtifact('cash_voucher_ocr', {
      payerName: ' 付款方 ',
      amount: Number.POSITIVE_INFINITY,
      paymentMethod: 'unsupported'
    })
  )

  assert.deepEqual(response.voucher, {
    payerName: ' 付款方 ',
    payeeName: null,
    transactionDate: null,
    amount: null,
    bankReference: null,
    paymentMethod: 'other'
  })
  assert.equal(response.rawText, '原始识别内容')
})

test('invoice artifact keeps valid values and rejects invalid enum values', () => {
  const response = toInvoiceOcrAnalyzeResponse(
    createArtifact('invoice_ocr', {
      invoiceType: 'unsupported',
      invoiceNo: 'INV-001',
      totalAmount: 128.5,
      taxRate: '6%'
    })
  )

  assert.equal(response.invoice.invoiceType, null)
  assert.equal(response.invoice.invoiceNo, 'INV-001')
  assert.equal(response.invoice.totalAmount, 128.5)
  assert.equal(response.invoice.taxRate, null)
})

test('waybill expense artifact restores a typed draft and rejects invalid numbers', () => {
  const artifact = createArtifact('waybill_expense_ocr', {
    amount: 286.5,
    occurredOn: '2026-08-20',
    quantity: Number.NaN,
    providerName: '能源服务商'
  })
  artifact.metadata = { reviewConfidenceThreshold: 'invalid' }

  const response = toWaybillExpenseOcrAnalyzeResponse(artifact)

  assert.equal(response.expense.amount, 286.5)
  assert.equal(response.expense.occurredOn, '2026-08-20')
  assert.equal(response.expense.quantity, null)
  assert.equal(response.expense.providerName, '能源服务商')
  assert.equal(response.reviewConfidenceThreshold, 0.82)
})

test('waybill expense review returns to the finance cost workflow', () => {
  const artifact = createArtifact('waybill_expense_ocr', {})

  assert.deepEqual(buildRecognitionBusinessRoute(artifact), {
    path: financePaths.waybillCost,
    query: { aiArtifactId: 'artifact-id' }
  })
})
