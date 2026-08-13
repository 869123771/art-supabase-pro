import { useSupabase } from '@/hooks'
import { applyCreateTimeRange, type SupabaseQueryLike } from '@/api/providers/supabase/query'
import { compact, uniq } from 'lodash-es'

type OrderRecord = Api.Tms.Order.OrderRecord
type OrderSearchParams = Api.Tms.Order.OrderSearchParams
type InTransitMonitorRecord = Api.Tms.InTransit.MonitorRecord

const { supabase, responseHandle } = useSupabase()

export const ORDER_SELECT = `
  *,
  originStationRef:tms_station!tms_order_origin_station_id_fkey(
    id,
    station_code,
    station_name,
    station_type,
    region_code
  ),
  destinationStationRef:tms_station!tms_order_destination_station_id_fkey(
    id,
    station_code,
    station_name,
    station_type,
    region_code
  ),
  transferStationRef:tms_station!tms_order_transfer_station_id_fkey(
    id,
    station_code,
    station_name,
    station_type,
    region_code
  ),
  shippingCustomer:tms_customer!tms_order_shipping_customer_id_fkey(
    id,
    customer_code,
    customer_name,
    contact_name,
    contact_phone,
    region,
    address_detail
  ),
  receivingCustomer:tms_customer!tms_order_receiving_customer_id_fkey(
    id,
    customer_code,
    customer_name,
    contact_name,
    contact_phone,
    region,
    address_detail
  )
`

export const uniqueStringValues = (values: Array<string | null | undefined>): string[] =>
  uniq(compact(values.map((value) => String(value ?? '').trim())))

export const applyOrderFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: OrderSearchParams
): TQuery => {
  const {
    cargoKeyword,
    shippingKeyword,
    receivingKeyword,
    orderStatus,
    paymentMethod,
    originStationId,
    destinationStationId,
    transferStationId,
    createTimeRange,
    recordId
  } = params

  if (recordId) query = query.eq('id', recordId)
  if (orderStatus) {
    query = query.eq('order_status', orderStatus)
  }
  if (paymentMethod) query = query.eq('payment_method', paymentMethod)
  if (originStationId) query = query.eq('origin_station_id', originStationId)
  if (destinationStationId) query = query.eq('destination_station_id', destinationStationId)
  if (transferStationId) query = query.eq('transfer_station_id', transferStationId)
  if (cargoKeyword) {
    query = query.or(`order_no.ilike.%${cargoKeyword}%,cargo_no.ilike.%${cargoKeyword}%`)
  }
  if (shippingKeyword) {
    query = query.or(
      `shipping_contact_name.ilike.%${shippingKeyword}%,shipping_contact_phone.ilike.%${shippingKeyword}%,shipping_address_detail.ilike.%${shippingKeyword}%`
    )
  }
  if (receivingKeyword) {
    query = query.or(
      `receiving_contact_name.ilike.%${receivingKeyword}%,receiving_contact_phone.ilike.%${receivingKeyword}%,receiving_address_detail.ilike.%${receivingKeyword}%`
    )
  }

  return applyCreateTimeRange(query, createTimeRange)
}

export const applyOrderListFilters = <TQuery extends SupabaseQueryLike>(
  query: TQuery,
  params: OrderSearchParams
): TQuery => applyOrderFilters(query.neq('order_status', 'created'), params)

const DRIVER_WAYBILL_SELECT =
  'id, tenant_id, waybill_no, status, accepted_at, loaded_at, departed_at, unloaded_at, completed_at, cancelled_at, update_time'

interface CargoStatusRow {
  waybillId: string
  operationType: Api.Tms.Waybill.CargoOperationType
  operationStatus: Api.Tms.Waybill.CargoOperationStatus
}

interface ExecutionStatusRow {
  waybillId: string
  signedAt?: string | null
  signerName?: string | null
  signatureUrls?: string[] | null
  returnTime?: string | null
  returnOdometerKm?: number | null
  returnPhotoUrls?: string[] | null
}

const fetchDriverWaybillMap = async (
  orderNos: string[]
): Promise<Map<string, InTransitMonitorRecord>> => {
  if (!orderNos.length) return new Map()

  const { data } = await responseHandle<InTransitMonitorRecord[]>(
    () => supabase.from('tms_waybill').select(DRIVER_WAYBILL_SELECT).in('waybill_no', orderNos),
    { ignoreCheck: true }
  )

  return new Map((data ?? []).map((item) => [String(item.waybillNo), item]))
}

const mergeDriverWaybillStatus = (
  order: OrderRecord,
  driverWaybill?: InTransitMonitorRecord,
  unloadingStatus?: Api.Tms.Waybill.CargoOperationStatus,
  executionStatus?: ExecutionStatusRow
): OrderRecord => {
  if (!driverWaybill) return order

  return {
    ...order,
    waybillNo: driverWaybill.waybillNo ?? order.waybillNo ?? order.orderNo,
    driverWaybillId: driverWaybill.id ?? order.driverWaybillId,
    driverWaybillAcceptedAt: driverWaybill.acceptedAt ?? order.driverWaybillAcceptedAt,
    driverWaybillLoadedAt: driverWaybill.loadedAt ?? order.driverWaybillLoadedAt,
    driverWaybillDepartedAt: driverWaybill.departedAt ?? order.driverWaybillDepartedAt,
    driverWaybillUnloadedAt: driverWaybill.unloadedAt ?? order.driverWaybillUnloadedAt,
    driverWaybillCompletedAt: driverWaybill.completedAt ?? order.driverWaybillCompletedAt,
    driverWaybillUnloadingStatus: unloadingStatus ?? order.driverWaybillUnloadingStatus,
    driverWaybillSignedAt: executionStatus?.signedAt ?? order.driverWaybillSignedAt,
    driverWaybillSignedBy: executionStatus?.signerName ?? order.driverWaybillSignedBy,
    driverWaybillSignatureProofCount:
      executionStatus?.signatureUrls?.length ?? order.driverWaybillSignatureProofCount,
    driverWaybillReturnTime: executionStatus?.returnTime ?? order.driverWaybillReturnTime,
    driverWaybillReturnOdometerKm:
      executionStatus?.returnOdometerKm ?? order.driverWaybillReturnOdometerKm,
    driverWaybillReturnPhotoCount:
      executionStatus?.returnPhotoUrls?.length ?? order.driverWaybillReturnPhotoCount,
    waybillStatus: driverWaybill.status ?? null,
    updateTime: driverWaybill.updateTime || order.updateTime
  }
}

export const mergeOrdersWithDriverWaybills = async <T extends OrderRecord>(
  orders: T[] | null | undefined
): Promise<T[]> => {
  const rows = orders ?? []
  const waybillMap = await fetchDriverWaybillMap(uniqueStringValues(rows.map((row) => row.orderNo)))
  const waybillIds = [...waybillMap.values()]
    .map((item) => item.id)
    .filter((id): id is string => Boolean(id))
  const [cargoResult, executionResult] = waybillIds.length
    ? await Promise.all([
        responseHandle<CargoStatusRow[]>(
          () =>
            supabase
              .from('tms_waybill_cargo_operation')
              .select('waybill_id, operation_type, operation_status')
              .in('waybill_id', waybillIds)
              .eq('operation_type', 'unloading'),
          { ignoreCheck: true }
        ),
        responseHandle<ExecutionStatusRow[]>(
          () =>
            supabase
              .from('tms_waybill_execution_record')
              .select(
                'waybill_id, signed_at, signer_name, signature_urls, return_time, return_odometer_km, return_photo_urls'
              )
              .in('waybill_id', waybillIds),
          { ignoreCheck: true }
        )
      ])
    : [{ data: [] as CargoStatusRow[] }, { data: [] as ExecutionStatusRow[] }]
  const cargoRows = cargoResult.data
  const executionRows = executionResult.data
  const unloadingStatusMap = new Map(
    (cargoRows ?? []).map((item) => [String(item.waybillId), item.operationStatus])
  )
  const executionStatusMap = new Map(
    (executionRows ?? []).map((item) => [String(item.waybillId), item])
  )

  return rows.map((row) => {
    const driverWaybill = waybillMap.get(String(row.orderNo))
    return mergeDriverWaybillStatus(
      row,
      driverWaybill,
      unloadingStatusMap.get(String(driverWaybill?.id)),
      executionStatusMap.get(String(driverWaybill?.id))
    ) as T
  })
}
