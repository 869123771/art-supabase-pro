import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import type { SupabaseQueryLike } from '@/api/providers/supabase/query'
import {
  applyOrderFilters,
  mergeOrdersWithDriverWaybills,
  ORDER_SELECT,
  uniqueStringValues
} from '@/api/modules/tms/order-shared'
import { DISPATCH_VEHICLE_SELECT } from '@/api/modules/tms/waybill-shared'

type WaybillRecord = Api.Tms.Waybill.WaybillRecord
type WaybillSearchParams = Api.Tms.Waybill.WaybillSearchParams
type WaybillDispatchPayload = Api.Tms.Waybill.WaybillDispatchPayload
type DispatchVehicleOption = Api.Tms.Waybill.DispatchVehicleOption
type DispatchVehicleSearchParams = Api.Tms.Waybill.DispatchVehicleSearchParams

interface DriverWaybillStatusReference {
  orderId?: string | null
}

interface WaybillStatusCountResult {
  total: number
  counts: Record<string, number>
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const applyPlannedTimeRange = (
  query: SupabaseQueryLike,
  plannedTimeRange?: string[]
): SupabaseQueryLike => {
  if (plannedTimeRange?.[0]) {
    query = query.gte('planned_departure_time', `${plannedTimeRange[0]}T00:00:00`)
  }
  if (plannedTimeRange?.[1]) {
    query = query.lte('planned_departure_time', `${plannedTimeRange[1]}T23:59:59.999`)
  }
  return query
}

const applyWaybillFilters = (
  query: SupabaseQueryLike,
  params: WaybillSearchParams
): SupabaseQueryLike => {
  const { dispatchStatus, dispatchStatuses, dispatchVehicleId, vehicleKeyword, plannedTimeRange } =
    params

  query = applyOrderFilters(query, params)
  if (dispatchStatuses?.length) query = query.in('dispatch_status', dispatchStatuses)
  if (!dispatchStatuses?.length && dispatchStatus)
    query =
      dispatchStatus === 'loaded'
        ? query.in('dispatch_status', ['loaded', 'transporting', 'completed'])
        : query.eq('dispatch_status', dispatchStatus)
  if (dispatchVehicleId) query = query.eq('dispatch_vehicle_id', dispatchVehicleId)
  if (vehicleKeyword) {
    query = query.or(
      `dispatch_plate_no.ilike.%${vehicleKeyword}%,dispatch_vehicle_type.ilike.%${vehicleKeyword}%,dispatch_driver_name.ilike.%${vehicleKeyword}%,dispatch_driver_phone.ilike.%${vehicleKeyword}%`
    )
  }

  return applyPlannedTimeRange(query, plannedTimeRange)
}

const WAYBILL_STATUS_VALUES = [
  'pending',
  'loading',
  'transporting',
  'unloading',
  'completed',
  'cancelled'
] as const

const countWaybillOrders = async (
  params: WaybillSearchParams,
  orderIds?: string[] | null
): Promise<number> => {
  if (orderIds !== null && orderIds !== undefined && !orderIds.length) return 0

  let query = supabase
    .from('tms_order')
    .select('id', { count: 'exact', head: true }) as unknown as SupabaseQueryLike
  query = applyWaybillFilters(query, params)
  if (orderIds?.length) query = query.in('id', orderIds)

  const { total } = await responseHandle<null>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return total ?? 0
}

const fetchWaybillOrderIdsByStatus = async (status?: string): Promise<string[] | null> => {
  if (!status) return null

  const { data } = await responseHandle<DriverWaybillStatusReference[]>(
    () =>
      supabase
        .from('tms_waybill')
        .select('order_id')
        .eq('status', status)
        .not('order_id', 'is', null),
    { ignoreCheck: true, showErrorMessage: true }
  )

  return uniqueStringValues((data ?? []).map((item) => item.orderId))
}

export async function fetchWaybillStatusCounts(
  params: WaybillSearchParams
): Promise<WaybillStatusCountResult> {
  const sharedFilters = { ...params, waybillStatus: undefined }
  const [total, countEntries] = await Promise.all([
    countWaybillOrders(sharedFilters),
    Promise.all(
      WAYBILL_STATUS_VALUES.map(async (waybillStatus) => {
        const orderIds = await fetchWaybillOrderIdsByStatus(waybillStatus)
        const count = await countWaybillOrders(sharedFilters, orderIds)
        return [waybillStatus, count] as const
      })
    )
  ])

  return { total, counts: Object.fromEntries(countEntries) }
}

const createDispatchRpcPayload = (params: WaybillDispatchPayload) => ({
  dispatchVehicleId: params.dispatchVehicleId,
  dispatchDriverId: params.dispatchDriverId || null,
  dispatchPlateNo: params.dispatchPlateNo,
  dispatchVehicleType: params.dispatchVehicleType || null,
  dispatchVehicleLength: params.dispatchVehicleLength || null,
  dispatchDriverName: params.dispatchDriverName || null,
  dispatchDriverPhone: params.dispatchDriverPhone || null,
  plannedDepartureTime: params.plannedDepartureTime,
  plannedArrivalTime: params.plannedArrivalTime,
  dispatchRemark: params.dispatchRemark || null
})

export async function fetchWaybillList(
  params: WaybillSearchParams & Api.Common.CommonSearchParams
) {
  const { from = 0, to = 9 } = params
  const orderIds = await fetchWaybillOrderIdsByStatus(params.waybillStatus)
  if (orderIds !== null && !orderIds.length) return { data: [], total: 0 }

  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike

  query = applyWaybillFilters(query, params)
  if (orderIds) query = query.in('id', orderIds)
  const result = await responseHandle<WaybillRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await mergeOrdersWithDriverWaybills(result.data) }
}

export async function exportWaybillList(
  params: WaybillSearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  const orderIds = ids?.length ? null : await fetchWaybillOrderIdsByStatus(params.waybillStatus)
  if (orderIds !== null && !orderIds.length) return { data: [], total: 0 }

  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike
  query = ids?.length ? query.in('id', ids) : applyWaybillFilters(query, params)
  if (orderIds) query = query.in('id', orderIds)
  const result = await responseHandle<WaybillRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return { ...result, data: await mergeOrdersWithDriverWaybills(result.data) }
}

export async function dispatchWaybill(params: WaybillDispatchPayload) {
  const id = params.id
  if (!id) throw new Error('缺少运单ID')

  const result = await responseHandle<WaybillRecord[]>(
    () =>
      supabase.rpc('tms_dispatch_orders', {
        p_order_ids: [id],
        p_dispatch: keysToSnakeDeep(createDispatchRpcPayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data?.[0] ?? null }
}

export async function dispatchWaybillBatch(params: WaybillDispatchPayload) {
  const ids = params.ids?.filter(Boolean) ?? []
  if (!ids.length) throw new Error('请选择需要配载的运单')

  const result = await responseHandle<WaybillRecord[]>(
    () =>
      supabase.rpc('tms_dispatch_orders', {
        p_order_ids: ids,
        p_dispatch: keysToSnakeDeep(createDispatchRpcPayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
  return result
}

export async function cancelWaybillDispatch(id: string) {
  const result = await responseHandle<WaybillRecord[]>(
    () => supabase.rpc('tms_revoke_order_dispatch', { p_order_ids: [id] }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data?.[0] ?? null }
}

export async function cancelWaybillDispatchBatch(ids: string[]) {
  return await responseHandle<WaybillRecord[]>(
    () => supabase.rpc('tms_revoke_order_dispatch', { p_order_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelWaybillOrder(id: string) {
  return await responseHandle(
    () => supabase.rpc('tms_cancel_order_with_waybill', { p_order_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelWaybillOrderBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.rpc('tms_cancel_orders_with_waybills', { p_order_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}

export async function confirmWaybillAcceptance(orderId: string) {
  return await responseHandle(() => supabase.rpc('tms_accept_waybill', { p_order_id: orderId }), {
    showMessage: true,
    breakReturn: true
  })
}

export async function confirmWaybillDeparture(orderId: string) {
  return await responseHandle(
    () => supabase.rpc('tms_confirm_waybill_departure', { p_order_id: orderId }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchDispatchVehicleOptions(params: DispatchVehicleSearchParams = {}) {
  const { from = 0, to = 9, keyword } = params
  let query = supabase
    .from('vehicle_archive')
    .select(DISPATCH_VEHICLE_SELECT, { count: 'exact' })
    .order('plate_no', { ascending: true })
    .range(from, to) as unknown as SupabaseQueryLike

  if (keyword) {
    const { data: driverRows } = await responseHandle<Array<{ id?: string }>>(
      () =>
        supabase
          .from('tms_driver')
          .select('id')
          .or(`driver_name.ilike.%${keyword}%,phone.ilike.%${keyword}%`)
          .limit(200),
      { ignoreCheck: true }
    )
    const driverIds = (driverRows ?? []).map((item) => item.id).filter((id): id is string => !!id)
    const conditions = [
      `plate_no.ilike.%${keyword}%`,
      `company_name.ilike.%${keyword}%`,
      `self_no.ilike.%${keyword}%`,
      `vehicle_type.ilike.%${keyword}%`
    ]
    if (driverIds.length) {
      const ids = driverIds.join(',')
      conditions.push(`primary_driver_id.in.(${ids})`)
    }
    query = query.or(conditions.join(','))
  }

  return await responseHandle<DispatchVehicleOption[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function recommendDispatchResourcesByAi(
  orderId: string,
  limit = 5
): Promise<QueryResult<Api.Tms.Waybill.DispatchRecommendationResponse>> {
  const { data, error } =
    await supabase.functions.invoke<Api.Tms.Waybill.DispatchRecommendationResponse>(
      'ai-dispatch-advisor',
      { body: { orderId, limit } }
    )

  return {
    data: data ?? null,
    error: await normalizeDispatchAdvisorError(error)
  }
}

async function normalizeDispatchAdvisorError(error: unknown): Promise<unknown | null> {
  if (!error || typeof error !== 'object' || !('context' in error)) return error

  const context = (error as { context?: unknown }).context
  if (!(context instanceof Response)) return error

  try {
    const payload = (await context.clone().json()) as { code?: unknown; message?: unknown }
    if (typeof payload.message !== 'string' || !payload.message) return error
    return {
      code: typeof payload.code === 'string' ? payload.code : undefined,
      message: payload.message
    }
  } catch {
    return error
  }
}
