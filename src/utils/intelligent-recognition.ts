import type { RouteLocationRaw } from 'vue-router'

type Artifact = Api.IntelligentRecognition.RecognitionArtifact

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
  const payload = artifact.proposedPayload as Api.Tms.Finance.InvoiceOcrDraft
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
  const payload = artifact.proposedPayload as unknown as Api.Tms.Finance.CashVoucherOcrDraft
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
