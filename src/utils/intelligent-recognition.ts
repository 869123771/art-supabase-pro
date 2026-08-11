import type { RouteLocationRaw } from 'vue-router'

type Artifact = Api.IntelligentRecognition.RecognitionArtifact
type CashPaymentMethod = Api.Tms.Finance.CashPaymentMethod
type InvoiceType = Api.Tms.Finance.InvoiceType

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

function normalizeInvoiceDraft(payload: Record<string, unknown>): Api.Tms.Finance.InvoiceOcrDraft {
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

function normalizeCashVoucherDraft(
  payload: Record<string, unknown>
): Api.Tms.Finance.CashVoucherOcrDraft {
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
      path: '/tms-transportation/finance-center/invoice-management',
      query: { ...commonQuery, direction: metadataText(artifact, 'direction') || 'output' }
    }
  }

  if (artifact.feature === 'cash_voucher_ocr') {
    const direction = metadataText(artifact, 'direction') || 'receipt'
    return {
      path:
        direction === 'payment'
          ? '/tms-transportation/finance-center/payment-application'
          : '/tms-transportation/finance-center/cash-transaction',
      query: { ...commonQuery, direction }
    }
  }

  return {
    path: '/tms-transportation/delivery-management',
    query: {
      ...commonQuery,
      orderId: metadataText(artifact, 'orderId'),
      keyword: metadataText(artifact, 'orderNo')
    }
  }
}

export function toInvoiceOcrAnalyzeResponse(
  artifact: Artifact
): Api.Tms.Finance.InvoiceOcrAnalyzeResponse {
  const payload = normalizeInvoiceDraft(artifact.proposedPayload)
  return {
    artifactId: artifact.id,
    runId: artifact.aiRunId,
    generatedAt: artifact.createTime,
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
): Api.Tms.Finance.CashVoucherOcrAnalyzeResponse {
  const payload = normalizeCashVoucherDraft(artifact.proposedPayload)
  return {
    artifactId: artifact.id,
    runId: artifact.aiRunId,
    generatedAt: artifact.createTime,
    summary: metadataText(artifact, 'summary') || '已从识别中心恢复待复核收款凭证',
    confidence: Number(artifact.confidence ?? 0),
    fieldConfidence: artifact.fieldConfidence ?? {},
    missingFields: metadataTextList(artifact, 'missingFields'),
    warnings: artifact.warnings ?? [],
    voucher: payload,
    matches: [],
    evaluatedStatements: 0,
    reviewConfidenceThreshold: Number(artifact.metadata?.reviewConfidenceThreshold ?? 0.82)
  }
}
