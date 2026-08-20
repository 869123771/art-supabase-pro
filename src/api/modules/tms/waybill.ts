import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/types/api/response'
import { fetchSecureOrders } from '@/api/modules/tms/transport-secure'
import { DISPATCH_VEHICLE_SELECT } from '@/api/modules/tms/waybill-shared'
import { fetchDriverOptions } from '@/api/modules/tms/driver'
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
type WaybillExpenseLocationRecord = Api.Tms.Waybill.WaybillExpenseLocationRecord

interface WaybillExpenseLocationQueryRecord extends WaybillExpenseLocationRecord {
  costType?: string | null
}

interface WaybillStatusCountResult {
  total: number
  counts: Record<string, number>
}

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const ENERGY_COST_TYPES = new Set([
  'fuel',
  'in_transit_energy',
  'in_transit_charging',
  'in_transit_gas'
])

export async function fetchWaybillDetail(waybillId: string) {
  const detailResult = await responseHandle<WaybillDetailRecord | null>(
    () => supabase.rpc('tms_get_waybill_detail_secure', { p_waybill_id: waybillId }),
    {
      breakReturn: true,
      errorMessage: '运单详情加载失败，请稍后重试'
    }
  )
  if (!detailResult.data) return detailResult

  const data = detailResult.data
  return {
    ...detailResult,
    data: {
      ...data,
      routePoints: normalizeWaybillRoutePoints(data.routePoints),
      pickupPhotos: normalizeUrlList(data.pickupPhotos),
      deliveryPhotos: normalizeUrlList(data.deliveryPhotos),
      receiptAttachments: normalizeUrlList(data.receiptAttachments),
      events: (data.events ?? []).map((event) => ({
        ...event,
        payload: isPlainObject(event.payload) ? event.payload : {}
      })),
      proofs: data.proofs ?? [],
      cargoOperations: data.cargoOperations ?? [],
      expenseLocations: normalizeExpenseLocations(data.expenseLocations ?? []),
      execution: data.execution ?? null
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
    const speedKmh = Number(item.speedKmh ?? item.speed ?? item.velocity)
    return [
      {
        name: typeof item.name === 'string' ? item.name : null,
        address: typeof item.address === 'string' ? item.address : null,
        type: typeof item.type === 'string' ? item.type : null,
        capturedAt: getFirstString(item, [
          'capturedAt',
          'timestamp',
          'recordedAt',
          'eventTime',
          'gpsTime',
          'time'
        ]),
        speedKmh: Number.isFinite(speedKmh) && speedKmh >= 0 ? speedKmh : null,
        source: typeof item.source === 'string' ? item.source : null,
        longitude,
        latitude
      }
    ]
  })
}

function normalizeExpenseLocations(
  records: WaybillExpenseLocationQueryRecord[]
): WaybillExpenseLocationRecord[] {
  return records.flatMap((record) => {
    const longitude = Number(record.expenseLongitude)
    const latitude = Number(record.expenseLatitude)
    const category = String(
      record.expenseItem?.businessCategory || record.costType || ''
    ).toLowerCase()
    const label =
      `${record.expenseItem?.itemCode || ''} ${record.expenseItem?.itemName || ''}`.toLowerCase()
    const isEnergyExpense =
      ENERGY_COST_TYPES.has(category) ||
      /(fuel|gas|charging|energy|加油|燃油|充电|能源)/i.test(label)

    if (!isEnergyExpense || !isValidCoordinate(longitude, latitude)) return []
    return [
      {
        id: record.id,
        occurredOn: record.occurredOn,
        expenseLocation: record.expenseLocation,
        expenseLongitude: longitude,
        expenseLatitude: latitude,
        expenseCoordinateSource: record.expenseCoordinateSource,
        expenseItem: record.expenseItem
      }
    ]
  })
}

function getFirstString(record: Record<string, unknown>, keys: string[]): string | null {
  for (const key of keys) {
    const value = record[key]
    if (typeof value === 'string' && value.trim()) return value.trim()
  }
  return null
}

function isValidCoordinate(longitude: number, latitude: number): boolean {
  return (
    Number.isFinite(longitude) &&
    Number.isFinite(latitude) &&
    longitude >= -180 &&
    longitude <= 180 &&
    latitude >= -90 &&
    latitude <= 90 &&
    !(longitude === 0 && latitude === 0)
  )
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

const normalizeWaybillSearchParams = (params: WaybillSearchParams): WaybillSearchParams =>
  params.dispatchStatus === 'loaded' && !params.dispatchStatuses?.length
    ? {
        ...params,
        dispatchStatus: undefined,
        dispatchStatuses: ['loaded', 'transporting', 'completed']
      }
    : params

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

export async function fetchWaybillStatusCounts(
  params: WaybillSearchParams
): Promise<WaybillStatusCountResult> {
  const sharedFilters = { ...params, waybillStatus: undefined }
  const [total, countEntries] = await Promise.all([
    fetchSecureOrders<WaybillRecord>(
      { ...normalizeWaybillSearchParams(sharedFilters), countOnly: true },
      'waybill_list'
    ).then((result) => result.total),
    Promise.all(
      WAYBILL_STATUS_VALUES.map(async (waybillStatus) => {
        const result = await fetchSecureOrders<WaybillRecord>(
          {
            ...normalizeWaybillSearchParams(sharedFilters),
            waybillStatus,
            countOnly: true
          },
          'waybill_list'
        )
        return [waybillStatus, result.total] as const
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
  return await fetchSecureOrders<WaybillRecord>(
    normalizeWaybillSearchParams(params),
    'waybill_list'
  )
}

export async function exportWaybillList(
  params: WaybillSearchParams & { ids?: string[]; maxRows?: number }
) {
  return await fetchSecureOrders<WaybillRecord>(
    normalizeWaybillSearchParams(params),
    'waybill_export'
  )
}

export async function dispatchWaybill(params: WaybillDispatchPayload) {
  const id = params.id
  if (!id) throw new Error('缺少运单ID')

  const result = await responseHandle<WaybillRecord[]>(
    () =>
      supabase.rpc('tms_dispatch_orders_secure', {
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
      supabase.rpc('tms_dispatch_orders_secure', {
        p_order_ids: ids,
        p_dispatch: keysToSnakeDeep(createDispatchRpcPayload(params))
      }),
    { showMessage: true, breakReturn: true }
  )
  return result
}

export async function cancelWaybillDispatch(id: string) {
  const result = await responseHandle<WaybillRecord[]>(
    () => supabase.rpc('tms_revoke_order_dispatch_secure', { p_order_ids: [id] }),
    { showMessage: true, breakReturn: true }
  )
  return { ...result, data: result.data?.[0] ?? null }
}

export async function cancelWaybillDispatchBatch(ids: string[]) {
  return await responseHandle<WaybillRecord[]>(
    () => supabase.rpc('tms_revoke_order_dispatch_secure', { p_order_ids: ids }),
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelWaybillOrder(id: string) {
  return await responseHandle(
    () => supabase.rpc('tms_cancel_waybill_order_secure', { p_order_id: id }),
    { showMessage: true, breakReturn: true }
  )
}

export async function cancelWaybillOrderBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.rpc('tms_cancel_waybill_orders_secure', { p_order_ids: ids }),
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
    .eq('audit_status', 'approved')
    .order('plate_no', { ascending: true })
    .range(from, to)

  if (keyword) {
    const { data: driverRows } = await fetchDriverOptions({
      driverName: keyword,
      includeDisabled: true,
      maxRows: 200
    })
    const driverIds = (driverRows ?? []).map((item) => item.id).filter(Boolean)
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

  const result = await responseHandle<DispatchVehicleOption[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  const driverIds = Array.from(
    new Set(
      (result.data ?? [])
        .map((vehicle) => vehicle.primaryDriverId)
        .filter((id): id is string => Boolean(id))
    )
  )
  if (!driverIds.length) return result

  const driverResult = await fetchDriverOptions({
    ids: driverIds,
    includeDisabled: true,
    maxRows: driverIds.length
  })
  const driversById = new Map((driverResult.data ?? []).map((driver) => [driver.id, driver]))
  return {
    ...result,
    data: (result.data ?? []).map((vehicle) => ({
      ...vehicle,
      primaryDriver: vehicle.primaryDriverId
        ? (driversById.get(vehicle.primaryDriverId) ?? vehicle.primaryDriver ?? null)
        : null
    }))
  }
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
