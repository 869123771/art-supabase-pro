import { useSupabase } from '@/hooks/core/useSupabase'
export type PayableReferenceKind = 'purpose' | 'method' | 'scheme'
export type PayableMatchField =
  | 'supplier_id'
  | 'currency_code'
  | 'project_id'
  | 'source_id'
  | 'organization_id'
  | 'document_no'
  | 'source_document_no'
  | 'business_date'
  | 'amount'
export type PayableMatchOperator =
  'eq' | 'ne' | 'lt' | 'lte' | 'gt' | 'gte' | 'contains' | 'starts_with'
export interface PayableMatchRule {
  primaryField: PayableMatchField
  secondaryField: PayableMatchField
  operator: PayableMatchOperator
  emptyMatches: boolean
}
export interface PayableReference {
  id?: string
  tenantId?: string
  tenant?: { tenantName?: string; tenantCode?: string }
  code: string
  name: string
  enabled: boolean
  businessType?: string
  payableWriteoff?: boolean
  receivableWriteoff?: boolean
  defaultFundPurpose?: string
  description?: string
  category?: string
  cashMethod?: string
  automatic?: boolean
  rules?: PayableMatchRule[]
  remark?: string
}
const { supabase, responseHandle, keysToSnakeDeep } = useSupabase()
const options = {
  breakReturn: true,
  showErrorMessage: false,
  errorMessage: '付款配置操作失败，请重试'
}
export async function fetchPayableReferences(
  kind: PayableReferenceKind
): Promise<PayableReference[]> {
  const { data } = await responseHandle<PayableReference[]>(
    () => supabase.rpc('fms_payable_reference_list_secure', { p_kind: kind }),
    options
  )
  if (!Array.isArray(data)) throw new Error('付款配置加载失败，请重试')
  return data
}
export async function savePayableReference(
  kind: PayableReferenceKind,
  record: PayableReference
): Promise<string> {
  const { data } = await responseHandle<string>(
    () =>
      supabase.rpc('fms_save_payable_reference_secure', {
        p_kind: kind,
        p_record: keysToSnakeDeep(record)
      }),
    options
  )
  if (typeof data !== 'string' || !data) throw new Error('付款配置未保存，请重试')
  return data
}
