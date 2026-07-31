import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/hooks/core/useSupabase'
import { withRequestOptions, type SupabaseQueryLike } from '@/api/modules/tms/query'
import { applyOrderFilters, ORDER_SELECT } from '@/api/modules/tms/order-shared'
import type { ApiRequestOptions } from '@/types/api/request'

type DeliveryRecord = Api.Tms.Delivery.DeliveryRecord
type DeliverySearchParams = Api.Tms.Delivery.DeliverySearchParams
type DeliverySignPayload = Api.Tms.Delivery.DeliverySignPayload

const { supabase, responseHandle } = useSupabase()

// 配送签收 / 在途监控
const applySignedTimeRange = (
  query: SupabaseQueryLike,
  signedTimeRange?: string[]
): SupabaseQueryLike => {
  if (signedTimeRange?.[0]) query = query.gte('signed_at', `${signedTimeRange[0]}T00:00:00`)
  if (signedTimeRange?.[1]) query = query.lte('signed_at', `${signedTimeRange[1]}T23:59:59.999`)
  return query
}

const applyDeliveryFilters = (
  query: SupabaseQueryLike,
  params: DeliverySearchParams
): SupabaseQueryLike => {
  const { orderStatuses, signedTimeRange } = params

  query = applyOrderFilters(query, params)
  if (orderStatuses?.length) query = query.in('order_status', orderStatuses)

  return applySignedTimeRange(query, signedTimeRange)
}

interface DeliveryStatusCountResult {
  total: number
  counts: Record<string, number>
}

const DELIVERY_STATUS_COUNT_VALUES = ['signed', 'completed'] as const

const countDeliveryOrders = async (params: DeliverySearchParams): Promise<number> => {
  let query = supabase
    .from('tms_order')
    .select('id', { count: 'exact', head: true }) as unknown as SupabaseQueryLike

  query = applyDeliveryFilters(query, params)

  const { total } = await responseHandle<null>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
  return total ?? 0
}

export async function fetchDeliveryStatusCounts(
  params: DeliverySearchParams
): Promise<DeliveryStatusCountResult> {
  const sharedFilters = {
    ...params,
    deliveryStatus: undefined,
    orderStatus: undefined,
    orderStatuses: undefined
  }
  const [total, countEntries] = await Promise.all([
    countDeliveryOrders({ ...sharedFilters, orderStatuses: [...DELIVERY_STATUS_COUNT_VALUES] }),
    Promise.all(
      DELIVERY_STATUS_COUNT_VALUES.map(async (orderStatus) => {
        const count = await countDeliveryOrders({ ...sharedFilters, orderStatuses: [orderStatus] })
        return [orderStatus, count] as const
      })
    )
  ])

  return { total, counts: Object.fromEntries(countEntries) }
}

export async function fetchDeliveryList(
  params: DeliverySearchParams & Api.Common.CommonSearchParams,
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT, { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to) as unknown as SupabaseQueryLike

  query = applyDeliveryFilters(query, params)
  return await responseHandle<DeliveryRecord[]>(() => withRequestOptions(query, options), {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function exportDeliveryList(
  params: DeliverySearchParams & { ids?: string[]; maxRows?: number }
) {
  const { ids, maxRows = 10000 } = params
  let query = supabase
    .from('tms_order')
    .select(ORDER_SELECT)
    .order('create_time', { ascending: false })
    .limit(maxRows) as unknown as SupabaseQueryLike

  query = ids?.length ? query.in('id', ids) : applyDeliveryFilters(query, params)
  return await responseHandle<DeliveryRecord[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function signDeliveryOrder(params: DeliverySignPayload) {
  const { id, ...data } = params
  if (!id) throw new Error('缂哄皯杩愬崟ID')

  const query = supabase.rpc('tms_complete_order_with_waybill', {
    p_order_id: id,
    p_signed_cod_amount: data.signedCodAmount ?? 0,
    p_receipt_image_urls: data.receiptImageUrls ?? [],
    p_signed_at: data.signedAt ?? new Date().toISOString()
  }) as unknown as PromiseLike<QueryResult<unknown>>

  return await responseHandle(() => query, {
    showMessage: true,
    breakReturn: true
  })
}
