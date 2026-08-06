import { useSupabase } from '@/hooks'
import {
  normalizeBooleanFilter,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { applyFilters, type FilterSpec } from '@/utils/supabase-filters'
import type { VehicleReminderRow, VehicleReminderSearchParams } from './types'

type ReminderKind = Api.VehicleMgtSys.ReminderManage.ReminderKind
type ReminderWorkOrder = Api.VehicleMgtSys.ReminderManage.VehicleReminderWorkOrder
type ReminderCreatePayload = Api.VehicleMgtSys.ReminderManage.VehicleReminderWorkOrderCreatePayload
type ReminderTransitionPayload =
  Api.VehicleMgtSys.ReminderManage.VehicleReminderWorkOrderTransitionPayload

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

export const VEHICLE_REMINDER_VIEWS = [
  'vehicle_reminder_insurance_expiry',
  'vehicle_reminder_inspection_expiry',
  'vehicle_reminder_maintenance_expiry',
  'vehicle_reminder_part_service_life',
  'vehicle_reminder_vehicle_service_life'
] as const

export type VehicleReminderViewName = (typeof VEHICLE_REMINDER_VIEWS)[number]

const getVehicleReminderSearchFilters = (
  params: VehicleReminderSearchParams,
  mode: 'days' | 'expired'
): FilterSpec[] => [
  {
    col: 'companyName',
    op: 'ilike',
    val: params.companyName ? `%${params.companyName}%` : undefined
  },
  { col: 'plateNo', op: 'ilike', val: params.plateNo ? `%${params.plateNo}%` : undefined },
  {
    col: 'expired',
    op: 'eq',
    val: mode === 'expired' ? normalizeBooleanFilter(params.expired) : undefined
  }
]

export async function fetchVehicleReminderViewList(
  viewName: VehicleReminderViewName,
  sourceType: ReminderKind,
  params: VehicleReminderSearchParams,
  mode: 'days' | 'expired',
  options?: ApiRequestOptions
) {
  const { from = 0, to = 9 } = params
  let query = supabase
    .from(viewName)
    .select('*', { count: 'exact' })
    .order('remaining_days', { ascending: true })
    .range(from, to)

  if (mode === 'days' && params.reminderDays !== null && params.reminderDays !== undefined) {
    query = query.lte('remaining_days', Number(params.reminderDays))
  }

  query = applyFilters(query, getVehicleReminderSearchFilters(params, mode), {
    skipEmpty: true,
    camelToSnake: true
  })

  const result = await responseHandle<VehicleReminderRow[]>(
    () => withRequestOptions(query as unknown as SupabaseQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )

  const rows = (result.data ?? []).map((row) => ({
    ...row,
    sourceVersion: getReminderSourceVersion(row)
  }))
  if (!rows.length) return { ...result, data: rows }

  const { data: workOrders } = await responseHandle<ReminderWorkOrder[]>(
    () =>
      supabase
        .from('vehicle_reminder_work_order')
        .select('*')
        .eq('source_type', sourceType)
        .in(
          'source_key',
          rows.map((row) => row.id)
        )
        .order('update_time', { ascending: false }),
    { ignoreCheck: true, showErrorMessage: true }
  )
  const workOrderMap = new Map(
    (workOrders ?? []).map((workOrder) => [
      `${workOrder.sourceKey}:${workOrder.sourceVersion}`,
      workOrder
    ])
  )

  return {
    ...result,
    data: rows.map((row) => {
      const workOrder = workOrderMap.get(`${row.id}:${row.sourceVersion}`) ?? null
      return { ...row, workOrder, workOrderStatus: workOrder?.status ?? null }
    })
  }
}

export async function createVehicleReminderWorkOrder(params: ReminderCreatePayload) {
  return await responseHandle<ReminderWorkOrder>(
    () =>
      supabase.rpc('get_or_create_vehicle_reminder_work_order', {
        p_reminder: keysToSnakeDeep(params)
      }),
    { breakReturn: true }
  )
}

export async function transitionVehicleReminderWorkOrder(params: ReminderTransitionPayload) {
  return await responseHandle<ReminderWorkOrder>(
    () =>
      supabase.rpc('transition_vehicle_reminder_work_order', {
        p_work_order_id: params.workOrderId,
        p_next_status: params.nextStatus,
        p_resolution: params.resolution || null
      }),
    { breakReturn: true }
  )
}

function getReminderSourceVersion(row: VehicleReminderRow): string {
  return (
    row.expireDate ||
    row.nextMaintenanceDate ||
    [row.startUseDate, row.serviceYears].filter(Boolean).join(':') ||
    [row.currentMileage, row.nextMaintenanceMileage]
      .filter((value) => value !== undefined)
      .join(':') ||
    'current'
  )
}
