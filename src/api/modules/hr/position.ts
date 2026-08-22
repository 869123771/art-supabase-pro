import { useSupabase } from '@/hooks'
import { withRequestOptions } from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'

type Position = Api.Hr.Position
type PositionSearchParams = Api.Hr.PositionSearchParams
type PositionOption = Api.Hr.PositionOption
type CarrierOption = Api.Tms.BasicData.CarrierOption

interface PositionListPayload {
  records: Position[]
  total: number
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const pickPositionPayload = (position: Position): Record<string, unknown> => {
  const payload: Record<string, unknown> = {
    positionCode: position.positionCode,
    positionName: position.positionName,
    enabled: position.enabled,
    sort: position.sort,
    description: position.description ?? null
  }
  if (position.tenantId) payload.tenantId = position.tenantId
  return keysToSnakeDeep(payload)
}

export async function fetchPositionList(params: PositionSearchParams, options?: ApiRequestOptions) {
  const from = Math.max(params.from ?? 0, 0)
  const result = await responseHandle<PositionListPayload>(
    () =>
      withRequestOptions(
        supabase.rpc('hr_list_positions_secure', {
          p_from: from,
          p_to: Math.max(params.to ?? from + 19, from),
          p_keyword: String(params.keyword ?? '').trim() || null,
          p_enabled: params.enabled ?? null,
          p_tenant_id: params.tenantId || null
        }),
        options
      ),
    { showErrorMessage: true }
  )

  return {
    data: result.data?.records ?? [],
    total: result.data?.total ?? 0,
    error: result.error
  }
}

export async function fetchPositionOptions(
  params: { tenantId?: string; includeDisabled?: boolean },
  options?: ApiRequestOptions
) {
  return await responseHandle<PositionOption[]>(
    () =>
      withRequestOptions(
        supabase.rpc('hr_list_position_options_secure', {
          p_tenant_id: params.tenantId || null,
          p_include_disabled: params.includeDisabled ?? false
        }),
        options
      ),
    { showErrorMessage: true }
  )
}

export async function fetchEmployeeDriverCarrierOptions(
  tenantId?: string,
  options?: ApiRequestOptions
) {
  return await responseHandle<CarrierOption[]>(
    () =>
      withRequestOptions(
        supabase.rpc('hr_list_driver_carrier_options_secure', {
          p_tenant_id: tenantId || null
        }),
        options
      ),
    { showErrorMessage: true }
  )
}

export async function addPosition(position: Position) {
  return await responseHandle<string>(
    () => supabase.rpc('hr_create_position_secure', { p_payload: pickPositionPayload(position) }),
    { showMessage: true, message: '岗位已创建', breakReturn: true }
  )
}

export async function editPosition(position: Position) {
  if (!position.id) throw new Error('未找到需要编辑的岗位')
  return await responseHandle<boolean>(
    () =>
      supabase.rpc('hr_update_position_secure', {
        p_id: position.id,
        p_payload: pickPositionPayload(position)
      }),
    { showMessage: true, message: '岗位已更新', breakReturn: true }
  )
}

export async function deletePosition(id: string) {
  return await responseHandle<boolean>(
    () => supabase.rpc('hr_delete_position_secure', { p_id: id }),
    { showMessage: true, message: '岗位已删除', breakReturn: true }
  )
}
