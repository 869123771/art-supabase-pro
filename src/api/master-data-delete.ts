import { useSupabase } from '@/hooks'
import { fetchAllRangePages } from '@/utils/supabase/pagination'
import type { DeleteReferenceContext } from '@/utils/supabase/delete-reference'

export interface RecordDeleteDependency extends Omit<
  MasterDataDeleteDependencyDetail,
  'dependencyCode' | 'cleanupAllowed' | 'createdAt'
> {
  sourceTable: string
  createdAt: string | null
}

export async function fetchRecordDeleteDependencies(
  context: DeleteReferenceContext
): Promise<RecordDeleteDependency[]> {
  const { data, error } = await fetchAllRangePages<RecordDeleteDependency>(({ from, to }) =>
    responseHandle<RecordDeleteDependency[]>(
      () =>
        supabase
          .rpc('get_record_delete_dependency_details', {
            p_table: context.table,
            p_ids: context.ids,
            p_constraint: context.constraint ?? null
          })
          .range(from, to),
      { breakReturn: true, showErrorMessage: false, errorMessage: '关联记录检查失败，请重试' }
    )
  )
  if (error || !data) throw new Error('关联记录检查失败，请重试', { cause: error })
  return data
}

export type MasterDataDeleteResourceType =
  | 'carrier'
  | 'driver'
  | 'cargo'
  | 'customer_address'
  | 'vehicle'
  | 'organization'
  | 'role'
  | 'menu'
  | 'dict_type'
  | 'dictionary'
  | 'attachment'
  | 'order'

export interface MasterDataDeleteDependencyDetail {
  resourceId: string
  dependencyCode: string
  recordId: string
  targetId: string
  recordNo: string
  recordSummary?: string | null
  recordStatus?: string | null
  recordAmount?: number | null
  createdAt: string
  cleanupAllowed: boolean
}

export interface CleanupMasterDataDeleteDependencyPayload {
  resourceType: MasterDataDeleteResourceType
  resourceIds: string[]
  dependencyCode: string
  recordIds: string[]
}

const { supabase, responseHandle } = useSupabase()

export async function deleteSupplierMasterRecords(ids: string[]) {
  return await responseHandle<number>(
    () => supabase.rpc('smis_delete_suppliers_secure', { p_ids: ids }),
    {
      breakReturn: true,
      showErrorMessage: false,
      requireAffected: true,
      noAffectedMessage: '所选供应商未删除，请刷新列表核对权限和数据状态后重试',
      errorMessage: '供应商删除失败，请检查业务引用后重试'
    }
  )
}

export type VehicleReminderDeleteSourceType =
  'insurance' | 'inspection' | 'maintenance' | 'part' | 'vehicle'

export interface VehicleReminderDeleteDestination {
  sourceType: VehicleReminderDeleteSourceType
  sourceKey: string
}

export async function fetchEquipmentInspectionDeleteDestination(
  inspectionId: string
): Promise<{ equipmentId: string } | null> {
  const { data } = await responseHandle<{ equipmentId: string }>(
    () =>
      supabase
        .from('smis_equipment_inspection')
        .select('equipmentId:equipment_id')
        .eq('id', inspectionId)
        .maybeSingle(),
    { breakReturn: true, showErrorMessage: false }
  )
  return data ?? null
}

export async function fetchWmsPurchaseDeleteDestination(
  documentId: string
): Promise<{ kind: string } | null> {
  const { data } = await responseHandle<{ kind: string }>(
    () => supabase.from('wms_purchase_document').select('kind').eq('id', documentId).maybeSingle(),
    { breakReturn: true, showErrorMessage: false }
  )
  return data && typeof data.kind === 'string' ? data : null
}

export async function fetchScmPurchaseDeleteDestination(
  documentId: string
): Promise<{ kind: string } | null> {
  const { data } = await responseHandle<{ kind: string }>(
    () => supabase.from('scm_purchase_document').select('kind').eq('id', documentId).maybeSingle(),
    { breakReturn: true, showErrorMessage: false }
  )
  return data && typeof data.kind === 'string' ? data : null
}

export async function fetchVehicleReminderDeleteDestination(
  workOrderId: string
): Promise<VehicleReminderDeleteDestination | null> {
  const { data } = await responseHandle<VehicleReminderDeleteDestination>(
    () =>
      supabase
        .from('vehicle_reminder_work_order')
        .select('sourceType:source_type,sourceKey:source_key')
        .eq('id', workOrderId)
        .maybeSingle(),
    { breakReturn: true, showErrorMessage: false }
  )
  return data ?? null
}

export async function fetchMasterDataDeleteDependencies(
  resourceType: MasterDataDeleteResourceType,
  resourceIds: string[]
): Promise<MasterDataDeleteDependencyDetail[]> {
  if (!resourceIds.length) return []
  const { data } = await responseHandle<MasterDataDeleteDependencyDetail[]>(
    () => {
      if (resourceType === 'attachment') {
        return supabase.rpc('get_attachment_delete_dependency_details', {
          p_resource_ids: resourceIds
        })
      }
      return supabase.rpc('get_governed_delete_dependency_details', {
        p_resource_type: resourceType,
        p_resource_ids: resourceIds
      })
    },
    { breakReturn: true, showErrorMessage: false }
  )
  return (data ?? []).map((item) => ({
    ...item,
    cleanupAllowed: Boolean(item.cleanupAllowed),
    recordAmount:
      item.recordAmount === null || item.recordAmount === undefined
        ? null
        : Number(item.recordAmount)
  }))
}

export async function cleanupMasterDataDeleteDependencies(
  payload: CleanupMasterDataDeleteDependencyPayload
): Promise<number> {
  if (!payload.resourceIds.length || !payload.recordIds.length) return 0
  const { data } = await responseHandle<number>(
    () =>
      supabase.rpc('cleanup_governed_delete_dependencies', {
        p_resource_type: payload.resourceType,
        p_resource_ids: payload.resourceIds,
        p_dependency_code: payload.dependencyCode,
        p_record_ids: payload.recordIds
      }),
    { breakReturn: true }
  )
  return Number(data) || 0
}
