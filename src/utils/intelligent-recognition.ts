import type { RouteLocationRaw } from 'vue-router'
import { financePaths } from '@/router/business-paths'

type Artifact = Api.IntelligentRecognition.RecognitionArtifact
type CashPaymentMethod = Api.Fms.CashPaymentMethod
type InvoiceType = Api.Fms.InvoiceType

const CASH_PAYMENT_METHODS = new Set<string>(['bank_transfer', 'cash', 'wechat', 'alipay', 'other'])
const INVOICE_TYPES = new Set<string>(['vat_special', 'vat_ordinary', 'electronic'])

function isCashPaymentMethod(value: string): value is CashPaymentMethod {
  return CASH_PAYMENT_METHODS.has(value)
}

function isInvoiceType(value: string): value is InvoiceType {
  return INVOICE_TYPES.has(value)
}

function nullableText(record: Record<string, unknown>, key: string): string | null {
  const value = record[key]
  return typeof value === 'string' && value.trim() ? value : null
}

function nullableNumber(record: Record<string, unknown>, key: string): number | null {
  const value = record[key]
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

function normalizeInvoiceDraft(payload: Record<string, unknown>): Api.Fms.InvoiceOcrDraft {
  const invoiceType = nullableText(payload, 'invoiceType')
  return {
    invoiceType: invoiceType && isInvoiceType(invoiceType) ? invoiceType : null,
    invoiceTitle: nullableText(payload, 'invoiceTitle'),
    taxNumber: nullableText(payload, 'taxNumber'),
    invoiceCode: nullableText(payload, 'invoiceCode'),
    invoiceNo: nullableText(payload, 'invoiceNo'),
    issueDate: nullableText(payload, 'issueDate'),
    taxRate: nullableNumber(payload, 'taxRate'),
    amountExcludingTax: nullableNumber(payload, 'amountExcludingTax'),
    taxAmount: nullableNumber(payload, 'taxAmount'),
    totalAmount: nullableNumber(payload, 'totalAmount'),
    buyerName: nullableText(payload, 'buyerName'),
    buyerTaxNumber: nullableText(payload, 'buyerTaxNumber'),
    sellerName: nullableText(payload, 'sellerName'),
    sellerTaxNumber: nullableText(payload, 'sellerTaxNumber')
  }
}

function normalizeCashVoucherDraft(payload: Record<string, unknown>): Api.Fms.CashVoucherOcrDraft {
  const paymentMethod = nullableText(payload, 'paymentMethod')
  return {
    payerName: nullableText(payload, 'payerName'),
    payeeName: nullableText(payload, 'payeeName'),
    transactionDate: nullableText(payload, 'transactionDate'),
    amount: nullableNumber(payload, 'amount'),
    bankReference: nullableText(payload, 'bankReference'),
    paymentMethod: paymentMethod && isCashPaymentMethod(paymentMethod) ? paymentMethod : 'other'
  }
}

function normalizeWaybillExpenseDraft(
  payload: Record<string, unknown>
): Api.Fms.WaybillExpenseOcrDraft {
  return {
    amount: nullableNumber(payload, 'amount'),
    occurredOn: nullableText(payload, 'occurredOn'),
    quantity: nullableNumber(payload, 'quantity'),
    unitPrice: nullableNumber(payload, 'unitPrice'),
    providerName: nullableText(payload, 'providerName'),
    payeeName: nullableText(payload, 'payeeName'),
    paymentChannel: nullableText(payload, 'paymentChannel'),
    invoiceNo: nullableText(payload, 'invoiceNo'),
    meterNo: nullableText(payload, 'meterNo'),
    expenseLocation: nullableText(payload, 'expenseLocation'),
    remark: nullableText(payload, 'remark')
  }
}

function metadataNumber(artifact: Artifact, key: string, fallback: number): number {
  const value = Number(artifact.metadata?.[key])
  return Number.isFinite(value) ? value : fallback
}

function metadataText(artifact: Artifact, key: string): string {
  const value = artifact.metadata?.[key]
  return typeof value === 'string' ? value : ''
}

function metadataTextList(artifact: Artifact, key: string): string[] {
  const value = artifact.metadata?.[key]
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === 'string')
    : []
}

export function buildRecognitionBusinessRoute(artifact: Artifact): RouteLocationRaw {
  const commonQuery = { aiArtifactId: artifact.id }

  if (artifact.feature === 'invoice_ocr') {
    return {
      path: financePaths.invoiceManagement,
      query: { ...commonQuery, direction: metadataText(artifact, 'direction') || 'output' }
    }
  }

  if (artifact.feature === 'cash_voucher_ocr') {
    const direction = metadataText(artifact, 'direction') || 'receipt'
    return {
      path:
        direction === 'payment' ? financePaths.paymentApplication : financePaths.cashTransaction,
      query: { ...commonQuery, direction }
    }
  }

  if (artifact.feature === 'waybill_expense_ocr') {
    return {
      path: financePaths.waybillCost,
      query: commonQuery
    }
  }

  return {
    path: '/tms/delivery-management',
    query: {
      ...commonQuery,
      orderId: metadataText(artifact, 'orderId'),
      keyword: metadataText(artifact, 'orderNo')
    }
  }
}

export function toInvoiceOcrAnalyzeResponse(artifact: Artifact): Api.Fms.InvoiceOcrAnalyzeResponse {
  const payload = normalizeInvoiceDraft(artifact.proposedPayload)
  return {
    artifactId: artifact.id,
    runId: artifact.aiRunId,
    generatedAt: artifact.createTime,
    rawText: artifact.rawOcrText,
    summary: metadataText(artifact, 'summary') || '已从识别中心恢复待复核发票',
    confidence: Number(artifact.confidence ?? 0),
    fieldConfidence: artifact.fieldConfidence ?? {},
    missingFields: metadataTextList(artifact, 'missingFields'),
    warnings: artifact.warnings ?? [],
    invoice: payload
  }
}

export function toCashVoucherOcrAnalyzeResponse(
  artifact: Artifact
): Api.Fms.CashVoucherOcrAnalyzeResponse {
  const payload = normalizeCashVoucherDraft(artifact.proposedPayload)
  return {
    artifactId: artifact.id,
    runId: artifact.aiRunId,
    generatedAt: artifact.createTime,
    rawText: artifact.rawOcrText,
    summary: metadataText(artifact, 'summary') || '已从识别中心恢复待复核收款凭证',
    confidence: Number(artifact.confidence ?? 0),
    fieldConfidence: artifact.fieldConfidence ?? {},
    missingFields: metadataTextList(artifact, 'missingFields'),
    warnings: artifact.warnings ?? [],
    voucher: payload,
    matches: [],
    evaluatedStatements: 0,
    reviewConfidenceThreshold: metadataNumber(artifact, 'reviewConfidenceThreshold', 0.82)
  }
}

export function toWaybillExpenseOcrAnalyzeResponse(
  artifact: Artifact
): Api.Fms.WaybillExpenseOcrAnalyzeResponse {
  const payload = normalizeWaybillExpenseDraft(artifact.proposedPayload)
  return {
    artifactId: artifact.id,
    runId: artifact.aiRunId,
    generatedAt: artifact.createTime,
    rawText: artifact.rawOcrText,
    summary: metadataText(artifact, 'summary') || '已从识别中心恢复待复核运单费用票据',
    confidence: Number(artifact.confidence ?? 0),
    fieldConfidence: artifact.fieldConfidence ?? {},
    missingFields: metadataTextList(artifact, 'missingFields'),
    warnings: artifact.warnings ?? [],
    expense: payload,
    reviewConfidenceThreshold: metadataNumber(artifact, 'reviewConfidenceThreshold', 0.82)
  }
}
