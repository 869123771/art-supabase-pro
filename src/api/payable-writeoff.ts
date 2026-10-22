import { useSupabase } from '@/hooks/core/useSupabase'
import type { PayableReference, PayableMatchRule } from '@/api/payable-reference'
import type { PayableSettlementOption } from '@/api/payable-settlement.types'
import type { PayableVoucherPreview } from '@/api/purchase-payable'
export interface PayableWriteoffCandidate {
  id: string
  tenantId: string
  documentId?: string
  documentNo: string
  businessDate: string
  documentTypeName?: string
  supplierId: string
  supplierName: string
  purposeName?: string
  currencyCode: string
  projectName?: string
  sourceDocumentNo?: string
  amount: number
  availableAmount: number
  writeoffAmount?: number
}
export interface PayableWriteoffRecord {
  id: string
  tenantId: string
  supplierId: string
  recordNo: string
  documentNo?: string | null
  payableId: string
  paymentLineId: string
  payableNo: string
  paymentNo: string
  supplierName: string
  writeoffDate: string
  amount: number
  paymentAmount?: number
  cashDiscountAmount?: number
  matchSnapshot?: { schemeCode: string; schemeName: string; rules: PayableMatchRule[] }
  needsVoucher: boolean
  voucherId?: string | null
  voucherNo?: string | null
  status: string
  remark: string
}
export interface PayableWriteoffWorkspace {
  primary: PayableWriteoffCandidate[]
  secondary: PayableWriteoffCandidate[]
  history: PayableWriteoffRecord[]
  schemes: PayableReference[]
  organizations?: PayableSettlementOption[]
}
export interface PayableVoucherResult {
  status?: string
  message: string
  voucherIds?: string[]
  lines?: PayableVoucherPreview['lines']
}
export interface PayableAutomaticWriteoffItem {
  payableId: string
  paymentLineId: string
  payableNo: string
  paymentNo: string
  supplierName: string
  paymentSupplierName: string
  amount: number
  needsVoucher: boolean
}
export interface PayableAutomaticWriteoffPlan {
  items: PayableAutomaticWriteoffItem[]
  totalAmount: number
  recordCount: number
  planToken: string
  recordIds: string[]
  executed: boolean
  schemeName: string
  message: string
}
export interface PayableAutomaticWriteoffRequest {
  schemeId: string
  date: string
  query: { organizationId?: string; supplierId?: string; keyword?: string }
}
const { supabase, responseHandle, keysToSnakeDeep } = useSupabase()
const options = {
  breakReturn: true,
  showErrorMessage: false,
  errorMessage: '应付核销操作失败，请重试'
}
export async function fetchPayableWriteoffWorkspace(query: {
  organizationId?: string
  supplierId?: string
  keyword?: string
}): Promise<PayableWriteoffWorkspace> {
  const { data } = await responseHandle<PayableWriteoffWorkspace>(
    () =>
      supabase.rpc('fms_payable_writeoff_workspace_secure', { p_query: keysToSnakeDeep(query) }),
    options
  )
  if (
    !data ||
    !Array.isArray(data.primary) ||
    !Array.isArray(data.secondary) ||
    !Array.isArray(data.history)
  )
    throw new Error('核销资料加载失败，请重试')
  return data
}
export async function executePayableWriteoff(
  items: Array<{ payableId: string; paymentLineId: string; amount: number }>,
  schemeId: string,
  date: string,
  remark: string
): Promise<void> {
  await responseHandle(
    () =>
      supabase.rpc('fms_payable_writeoff_secure', {
        p_items: keysToSnakeDeep(items),
        p_scheme_id: schemeId,
        p_date: date,
        p_remark: remark
      }),
    options
  )
}
export async function automaticPayableWriteoff(
  request: PayableAutomaticWriteoffRequest,
  planToken?: string
): Promise<PayableAutomaticWriteoffPlan> {
  const { data } = await responseHandle<PayableAutomaticWriteoffPlan>(
    () =>
      supabase.rpc('fms_auto_payable_writeoff_secure', {
        p_scheme_id: request.schemeId,
        p_date: request.date,
        p_query: keysToSnakeDeep(request.query),
        p_execute: planToken !== undefined,
        p_plan_token: planToken ?? null
      }),
    options
  )
  if (!data || !Array.isArray(data.items) || typeof data.planToken !== 'string')
    throw new Error('自动核销预览未加载，请重新预览后再试')
  return data
}
export async function reversePayableWriteoff(id: string, reason: string): Promise<void> {
  await responseHandle(
    () => supabase.rpc('fms_reverse_payable_writeoff_secure', { p_id: id, p_reason: reason }),
    options
  )
}
export async function payableSettlementVoucher(
  id: string,
  kind: 'payment' | 'writeoff',
  preview = false
): Promise<PayableVoucherResult> {
  const { data } = await responseHandle<PayableVoucherResult>(
    () =>
      supabase.rpc('fms_payable_settlement_voucher_secure', {
        p_id: id,
        p_kind: kind,
        p_preview: preview
      }),
    options
  )
  if (!data || (!Array.isArray(data.lines) && !Array.isArray(data.voucherIds)))
    throw new Error('凭证处理未完成，请重试')
  return data
}
