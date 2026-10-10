import { useSupabase } from '@/hooks/core/useSupabase'

export type PurchasePayableKind = 'estimated' | 'financial'
export interface PurchasePayableLine {
  id: string
  sourceLineId: string
  lineNo: number
  materialCode: string
  materialDescription: string | null
  projectName: string | null
  constructionNo: string | null
  unitName: string | null
  quantity: number
  unitPrice: number
  amount: number
  taxAmount: number
  totalAmount: number
}
export interface PurchasePayableDocument {
  id: string
  tenantId: string
  kind: PurchasePayableKind
  documentNo: string
  sourceDocumentId: string
  sourceDocumentNo: string
  supplierName: string | null
  businessDate: string
  status: 'draft'
  amount: number
  taxAmount: number
  totalAmount: number
  lines: PurchasePayableLine[]
}
const { supabase, responseHandle } = useSupabase()
const options = {
  breakReturn: true,
  showErrorMessage: false,
  errorMessage: '应付单操作失败，请重试'
}
export async function pushPurchasePayables(
  kind: PurchasePayableKind,
  selections: Array<{ documentId: string; lineIds: string[] | null }>
): Promise<PurchasePayableDocument[]> {
  const { data } = await responseHandle<PurchasePayableDocument[]>(
    () =>
      supabase.rpc('wms_push_purchase_payables_secure', {
        p_kind: kind,
        p_selections: selections.map((row) => ({
          document_id: row.documentId,
          line_ids: row.lineIds
        }))
      }),
    options
  )
  if (!data?.length) throw new Error('没有可下推的采购入库明细，请重新选择')
  return data
}
export async function fetchPurchasePayables(
  kind: PurchasePayableKind,
  params: { current: number; size: number; keyword?: string; id?: string }
): Promise<{ data: PurchasePayableDocument[]; total: number }> {
  const { data } = await responseHandle<{ data: PurchasePayableDocument[]; total: number }>(
    () =>
      supabase.rpc('fms_purchase_payable_list_secure', {
        p_kind: kind,
        p_keyword: params.keyword || '',
        p_id: params.id || null,
        p_limit: params.size,
        p_offset: (params.current - 1) * params.size
      }),
    options
  )
  if (!data || !Array.isArray(data.data)) throw new Error('应付单数据不完整，请重试')
  return data
}

export async function fetchPurchasePayableDeleteDestination(
  id: string
): Promise<PurchasePayableKind | null> {
  const { data } = await responseHandle<{ kind: PurchasePayableKind }>(
    () => supabase.from('fms_purchase_payable_document').select('kind').eq('id', id).maybeSingle(),
    options
  )
  return data?.kind === 'estimated' || data?.kind === 'financial' ? data.kind : null
}
