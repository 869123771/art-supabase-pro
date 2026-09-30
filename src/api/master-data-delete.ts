import { useSupabase } from '@/hooks'

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

export type VehicleReminderDeleteSourceType =
  'insurance' | 'inspection' | 'maintenance' | 'part' | 'vehicle'

export interface VehicleReminderDeleteDestination {
  sourceType: VehicleReminderDeleteSourceType
  sourceKey: string
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
