import { useSupabase } from '@/hooks'

export type ScmReceiptTargetKind = 'inbound' | 'asset_payable'
export type ScmReceiptTargetStatus = 'draft' | 'confirmed' | 'approved'

export interface ScmReceiptTargetDocument {
  id: string
  tenantId: string
  targetKind: ScmReceiptTargetKind
  documentNo: string
  sourceReceiptId: string
  projectId: string | null
  supplierId: string | null
  status: ScmReceiptTargetStatus
  totalAmount: number
  createdAt: string
  completedAt: string | null
  source?: { documentNo: string } | null
  project?: { projectCode: string; projectName: string } | null
  supplier?: { supplierCode: string; supplierName: string } | null
}

export interface ScmReceiptTargetLine {
  id: string
  sourceLineId: string
  lineSnapshot: {
    lineNo?: number
    materialCode?: string
    materialDescription?: string
    quantity?: number
    stockQuantity?: number
    stockUnit?: string
    warehouse?: string
    location?: string
    batchNo?: string
    gift?: boolean
  }
  amount: number
}

export interface ScmReceiptTargetQuery {
  keyword?: string
  status?: string
  tenantId?: string
  from?: number
  to?: number
}

const { supabase, responseHandle } = useSupabase()

export async function fetchScmReceiptTargets(
  kind: ScmReceiptTargetKind,
  query: ScmReceiptTargetQuery = {}
) {
  let request = supabase
    .from('scm_receipt_target_document')
    .select(
      '*,source:scm_purchase_document!scm_receipt_target_document_source_receipt_id_fkey(document_no),project:mdm_project!scm_receipt_target_document_project_id_fkey(project_code,project_name),supplier:mdm_supplier!scm_receipt_target_document_supplier_id_fkey(supplier_code,supplier_name)',
      { count: 'exact' }
    )
    .eq('target_kind', kind)
    .order('created_at', { ascending: false })
    .range(query.from ?? 0, query.to ?? 999)
  if (query.status) request = request.eq('status', query.status)
  if (query.tenantId) request = request.eq('tenant_id', query.tenantId)
  if (query.keyword?.trim()) {
    request = request.ilike('document_no', `%${query.keyword.trim()}%`)
  }
  return responseHandle<ScmReceiptTargetDocument[]>(() => request, {
    showErrorMessage: true,
    errorMessage: '目标单据加载失败，请稍后重试'
  })
}

export async function fetchScmReceiptTargetLines(targetId: string) {
  return responseHandle<ScmReceiptTargetLine[]>(
    () =>
      supabase
        .from('scm_receipt_target_line')
        .select('id,source_line_id,line_snapshot,amount')
        .eq('target_document_id', targetId)
        .order('created_at'),
    { breakReturn: true, showErrorMessage: true, errorMessage: '目标单据明细加载失败' }
  )
}

export async function fetchPushedReceiptLineIds(
  receiptId: string,
  targetKind: ScmReceiptTargetKind
) {
  const { data } = await responseHandle<Array<{ sourceLineId: string }>>(
    () =>
      supabase
        .from('scm_receipt_target_line')
        .select('source_line_id')
        .eq('source_receipt_id', receiptId)
        .eq('target_kind', targetKind),
    { breakReturn: true, showErrorMessage: true, errorMessage: '已下推明细加载失败' }
  )
  return new Set((data ?? []).map((row) => row.sourceLineId))
}

export async function pushScmReceiptLines(
  receiptId: string,
  lineIds: string[],
  targetKind: ScmReceiptTargetKind
) {
  const { data } = await responseHandle<string>(
    () =>
      supabase.rpc('scm_push_receipt_lines_secure', {
        p_receipt_id: receiptId,
        p_line_ids: lineIds,
        p_target_kind: targetKind
      }),
    {
      breakReturn: true,
      showMessage: true,
      message: targetKind === 'inbound' ? '已生成收料入库草稿' : '已生成资产应付草稿',
      errorMessage: '下推失败，请检查单据状态、已下推明细及权限'
    }
  )
  return data
}

export async function transitionScmReceiptTarget(id: string, kind: ScmReceiptTargetKind) {
  return responseHandle<void>(
    () =>
      supabase.rpc('scm_transition_receipt_target_secure', {
        p_target_id: id,
        p_action: kind === 'inbound' ? 'confirm' : 'approve'
      }),
    {
      breakReturn: true,
      showMessage: true,
      message: kind === 'inbound' ? '已确认入库并写入库存流水' : '资产应付已审核',
      errorMessage: kind === 'inbound' ? '入库确认失败，请检查仓库与库存数量' : '应付审核失败'
    }
  )
}
