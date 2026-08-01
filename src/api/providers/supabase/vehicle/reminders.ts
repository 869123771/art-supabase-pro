import { useSupabase } from '@/hooks'
import {
  normalizeBooleanFilter,
  withRequestOptions,
  type SupabaseQueryLike
} from '@/api/providers/supabase/query'
import type { ApiRequestOptions } from '@/types/api/request'
import { applyFilters, type FilterSpec } from '@/utils/supabase-filters'
import type { VehicleReminderRow, VehicleReminderSearchParams } from './types'

const { supabase, responseHandle } = useSupabase()

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

  return await responseHandle<VehicleReminderRow[]>(
    () => withRequestOptions(query as unknown as SupabaseQueryLike, options),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}
