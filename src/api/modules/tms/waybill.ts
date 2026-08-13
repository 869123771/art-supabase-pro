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
import { isPlainObject } from 'lodash-es'

type WaybillRecord = Api.Tms.Waybill.WaybillRecord
type WaybillSearchParams = Api.Tms.Waybill.WaybillSearchParams
type WaybillDispatchPayload = Api.Tms.Waybill.WaybillDispatchPayload
type DispatchVehicleOption = Api.Tms.Waybill.DispatchVehicleOption
type DispatchVehicleSearchParams = Api.Tms.Waybill.DispatchVehicleSearchParams
type CargoOperationType = Api.Tms.Waybill.CargoOperationType
type CargoOperationContext = Api.Tms.Waybill.CargoOperationContext
type CargoOperationCheckinPayload = Api.Tms.Waybill.CargoOperationCheckinPayload
type CargoOperationCompletePayload = Api.Tms.Waybill.CargoOperationCompletePayload
type ExecutionContext = Api.Tms.Waybill.ExecutionContext
type ExecutionDeparturePayload = Api.Tms.Waybill.ExecutionDeparturePayload
type ExecutionSignaturePayload = Api.Tms.Waybill.ExecutionSignaturePayload
type ExecutionCompletionPayload = Api.Tms.Waybill.ExecutionCompletionPayload
type WaybillDetailRecord = Api.Tms.Waybill.WaybillDetailRecord
type WaybillEventRecord = Api.Tms.Waybill.WaybillEventRecord
type WaybillProofRecord = Api.Tms.Waybill.WaybillProofRecord
type CargoOperationRecord = Api.Tms.Waybill.CargoOperationRecord
type ExecutionRecord = Api.Tms.Waybill.ExecutionRecord

interface DriverWaybillStatusReference {
  orderId?: string | null
}

interface WaybillStatusCountResult {
  total: number
  counts: Record<string, number>
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const WAYBILL_DETAIL_SELECT = `
  *,
  order:tms_order!tms_waybill_order_id_fkey(${ORDER_SELECT}),
  driver:tms_driver!tms_waybill_driver_id_fkey(id, driver_name, phone, license_type),
  vehicle:vehicle_archive!tms_waybill_vehicle_id_fkey(
    id, plate_no, vehicle_type, brand_model, approved_load_mass, vehicle_photo_url
  ),
  carrier:tms_carrier!tms_waybill_carrier_id_fkey(
    id, company_name, contact_name, contact_phone
  ),
  cargo:tms_cargo!tms_waybill_cargo_id_fkey(id, cargo_code, cargo_name, unit)
`

export async function fetchWaybillDetail(waybillId: string) {
  const detailResult = await responseHandle<WaybillDetailRecord | null>(
    () =>
      supabase.from('tms_waybill').select(WAYBILL_DETAIL_SELECT).eq('id', waybillId).maybeSingle(),
    {
      breakReturn: true,
      errorMessage: '运单详情加载失败，请稍后重试'
    }
  )
  if (!detailResult.data) return detailResult

  const [eventResult, proofResult, cargoOperationResult, executionResult] = await Promise.all([
    responseHandle<WaybillEventRecord[]>(
      () =>
        supabase
          .from('tms_waybill_event')
          .select(
            'id, waybill_id, event_type, event_time, operator_name, location_text, longitude, latitude, payload, remark, create_by, create_time'
          )
          .eq('waybill_id', waybillId)
          .order('event_time', { ascending: false }),
      { breakReturn: true, errorMessage: '运单跟踪记录加载失败，请稍后重试' }
    ),
    responseHandle<WaybillProofRecord[]>(
      () =>
        supabase
          .from('tms_waybill_proof')
          .select(
            'id, waybill_id, proof_type, attachment_id, file_url, file_name, mime_type, file_size, uploaded_at, uploader_name, remark'
          )
          .eq('waybill_id', waybillId)
          .order('uploaded_at', { ascending: false }),
      { breakReturn: true, errorMessage: '运单凭证加载失败，请稍后重试' }
    ),
    responseHandle<CargoOperationRecord[]>(
      () =>
        supabase
          .from('tms_waybill_cargo_operation')
          .select('*')
          .eq('waybill_id', waybillId)
          .order('checkin_time', { ascending: false }),
      { breakReturn: true, errorMessage: '装卸作业记录加载失败，请稍后重试' }
    ),
    responseHandle<ExecutionRecord | null>(
      () =>
        supabase
          .from('tms_waybill_execution_record')
          .select('*')
          .eq('waybill_id', waybillId)
          .maybeSingle(),
      { breakReturn: true, errorMessage: '运单执行记录加载失败，请稍后重试' }
    )
  ])

  const data = detailResult.data
  return {
    ...detailResult,
    data: {
      ...data,
      routePoints: normalizeWaybillRoutePoints(data.routePoints),
      pickupPhotos: normalizeUrlList(data.pickupPhotos),
      deliveryPhotos: normalizeUrlList(data.deliveryPhotos),
      receiptAttachments: normalizeUrlList(data.receiptAttachments),
      events: (eventResult.data ?? []).map((event) => ({
        ...event,
        payload: isPlainObject(event.payload) ? event.payload : {}
      })),
      proofs: proofResult.data ?? [],
      cargoOperations: cargoOperationResult.data ?? [],
      execution: executionResult.data ?? null
    }
  }
}

function normalizeWaybillRoutePoints(value: unknown): Api.Tms.Waybill.WaybillRoutePoint[] {
  if (!Array.isArray(value)) return []
  return value.flatMap((item) => {
    if (!isPlainObject(item)) return []
    const longitude = Number(item.longitude ?? item.lng)
    const latitude = Number(item.latitude ?? item.lat)
    if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) return []
    return [
      {
        name: typeof item.name === 'string' ? item.name : null,
        address: typeof item.address === 'string' ? item.address : null,
        type: typeof item.type === 'string' ? item.type : null,
        longitude,
        latitude
      }
    ]
  })
}

function normalizeUrlList(value: unknown): string[] {
  if (!Array.isArray(value)) return []
  return value.flatMap((item) => {
    if (typeof item === 'string') return item.trim() ? [item.trim()] : []
    if (!isPlainObject(item) || typeof item.url !== 'string') return []
    const url = item.url.trim()
    return url ? [url] : []
  })
}

const applyPlannedTimeRange = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  plannedTimeRange?: string[]
): TQuery => {
  if (plannedTimeRange?.[0]) {
    query = query.gte('planned_departure_time', `${plannedTimeRange[0]}T00:00:00`)
  }
  if (plannedTimeRange?.[1]) {
    query = query.lte('planned_departure_time', `${plannedTimeRange[1]}T23:59:59.999`)
  }
  return query
}

const applyWaybillFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: WaybillSearchParams
): TQuery => {
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
  'accepted',
  'loading',
  'transporting',
  'unloading',
  'signed',
  'completed',
  'cancelled'
] as const

const countWaybillOrders = async (
  params: WaybillSearchParams,
  orderIds?: string[] | null
): Promise<number> => {
  if (orderIds !== null && orderIds !== undefined && !orderIds.length) return 0

  let query = supabase.from('tms_order').select('id', { count: 'exact', head: true })
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
    .range(from, to)

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
    .limit(maxRows)
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

export async function confirmWaybillAcceptance(waybillId: string) {
  return await responseHandle(
    () => supabase.rpc('tms_accept_assigned_waybill', { p_waybill_id: waybillId }),
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

export async function fetchWaybillCargoOperationContext(
  waybillId: string,
  operationType: CargoOperationType
) {
  return await responseHandle<CargoOperationContext>(
    () =>
      supabase.rpc('tms_get_waybill_cargo_operation_context', {
        p_waybill_id: waybillId,
        p_operation_type: operationType
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function checkInWaybillCargoOperation(params: CargoOperationCheckinPayload) {
  return await responseHandle<CargoOperationContext>(
    () =>
      supabase.rpc('tms_check_in_waybill_cargo_operation', {
        p_waybill_id: params.waybillId,
        p_operation_type: params.operationType,
        p_longitude: params.longitude,
        p_latitude: params.latitude,
        p_accuracy_m: params.accuracyM ?? null,
        p_location_text: params.locationText || null,
        p_outside_reason: params.outsideReason || null,
        p_automatic: params.automatic === true
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function completeWaybillCargoOperation(params: CargoOperationCompletePayload) {
  return await responseHandle<CargoOperationContext>(
    () =>
      supabase.rpc('tms_complete_waybill_cargo_operation', {
        p_waybill_id: params.waybillId,
        p_operation_type: params.operationType,
        p_weight_ton: params.weightTon,
        p_photo_urls: params.photoUrls,
        p_weighbridge_ticket_urls: params.weighbridgeTicketUrls,
        p_remark: params.remark || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchWaybillExecutionContext(waybillId: string) {
  return await responseHandle<ExecutionContext>(
    () =>
      supabase.rpc('tms_get_waybill_execution_context', {
        p_waybill_id: waybillId
      }),
    { ignoreCheck: true, showErrorMessage: true }
  )
}

export async function recordWaybillDeparture(params: ExecutionDeparturePayload) {
  return await responseHandle<ExecutionContext>(
    () =>
      supabase.rpc('tms_record_waybill_departure', {
        p_waybill_id: params.waybillId,
        p_departure_time: params.departureTime,
        p_odometer_km: params.odometerKm,
        p_photo_urls: params.photoUrls,
        p_remark: params.remark || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function signWaybill(params: ExecutionSignaturePayload) {
  return await responseHandle<ExecutionContext>(
    () =>
      supabase.rpc('tms_sign_waybill', {
        p_waybill_id: params.waybillId,
        p_signed_at: params.signedAt,
        p_signer_name: params.signerName,
        p_receipt_urls: params.receiptUrls,
        p_signature_urls: params.signatureUrls,
        p_remark: params.remark || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function completeWaybillExecution(params: ExecutionCompletionPayload) {
  return await responseHandle<ExecutionContext>(
    () =>
      supabase.rpc('tms_complete_waybill_execution', {
        p_waybill_id: params.waybillId,
        p_return_time: params.returnTime,
        p_return_odometer_km: params.returnOdometerKm,
        p_photo_urls: params.photoUrls,
        p_remark: params.remark || null
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelAssignedWaybill(waybillId: string, reason: string) {
  return await responseHandle<ExecutionContext>(
    () =>
      supabase.rpc('tms_cancel_assigned_waybill', {
        p_waybill_id: waybillId,
        p_reason: reason
      }),
    { showMessage: true, breakReturn: true }
  )
}

export async function fetchDispatchVehicleOptions(params: DispatchVehicleSearchParams = {}) {
  const { from = 0, to = 9, keyword } = params
  let query = supabase
    .from('vehicle_archive')
    .select(DISPATCH_VEHICLE_SELECT, { count: 'exact' })
    .order('plate_no', { ascending: true })
    .range(from, to)

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
