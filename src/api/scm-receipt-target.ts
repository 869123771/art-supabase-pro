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
  constructionNo: string | null
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
    materialId?: string
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
  serialNos: string[]
  serialManagementEnabled?: boolean
  amount: number
}

export interface ScmReceiptTargetQuery {
  id?: string
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
  if (query.id) request = request.eq('id', query.id)
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
  const result = await responseHandle<ScmReceiptTargetLine[]>(
    () =>
      supabase
        .from('scm_receipt_target_line')
        .select('id,source_line_id,line_snapshot,serial_nos,amount')
        .eq('target_document_id', targetId)
        .order('created_at'),
    { breakReturn: true, showErrorMessage: true, errorMessage: '目标单据明细加载失败' }
  )
  const lines = result.data ?? []
  const materialIds = [
    ...new Set(
      lines.map((line) => line.lineSnapshot.materialId).filter((id): id is string => Boolean(id))
    )
  ]
  if (!materialIds.length) return result
  const controls = await responseHandle<Array<{ id: string; serialManagementEnabled: boolean }>>(
    () =>
      supabase.from('mdm_material').select('id,serial_management_enabled').in('id', materialIds),
    { breakReturn: true, showErrorMessage: true, errorMessage: '物料 SN 管控信息加载失败' }
  )
  const enabledById = new Map(
    (controls.data ?? []).map((row) => [row.id, row.serialManagementEnabled])
  )
  return {
    ...result,
    data: lines.map((line) => ({
      ...line,
      serialManagementEnabled: enabledById.get(line.lineSnapshot.materialId || '') ?? false
    }))
  }
}

export async function setScmReceiptLineSerials(lineId: string, serialNos: string[]) {
  await responseHandle(
    () =>
      supabase.rpc('wms_set_receipt_line_serials_secure', {
        p_line_id: lineId,
        p_serial_nos: serialNos
      }),
    {
      breakReturn: true,
      showMessage: true,
      message: '收料 SN 已保存',
      errorMessage: 'SN 保存失败，请核对件数、重复编码与权限'
    }
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

export async function fetchScmReceiptProjectSections(projectId: string) {
  const { data } = await responseHandle<
    Array<{ constructionNo: string; sectionName: string; status: 'active' | 'closed' }>
  >(
    () =>
      supabase
        .from('mdm_project_construction')
        .select('construction_no,section_name,status')
        .eq('project_id', projectId)
        .order('construction_no'),
    { breakReturn: true, showErrorMessage: true, errorMessage: '施工号加载失败，请重试' }
  )
  return data ?? []
}

export async function setScmReceiptScope(targetId: string, constructionNo: string) {
  await responseHandle(
    () =>
      supabase.rpc('wms_set_receipt_scope_secure', {
        p_target_id: targetId,
        p_construction_no: constructionNo
      }),
    {
      breakReturn: true,
      showMessage: true,
      message: '入库施工号已保存',
      errorMessage: '施工号保存失败，请核对项目状态与权限'
    }
  )
}
