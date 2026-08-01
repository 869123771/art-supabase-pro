import dayjs from 'dayjs'
import { useSupabase } from '@/hooks'
import type { SupabaseQueryLike } from '@/api/providers/supabase/query'

const { supabase, responseHandle } = useSupabase()

export type DashboardReminderKey = 'insurance' | 'inspection' | 'maintenance' | 'part' | 'vehicle'

export interface DashboardOrder {
  id?: string
  orderNo: string
  orderStatus?: string | null
  dispatchStatus?: string | null
  originStation?: string | null
  destinationStation?: string | null
  shippingCustomerName?: string | null
  dispatchPlateNo?: string | null
  dispatchDriverName?: string | null
  plannedArrivalTime?: string | null
  totalFee?: number | string | null
  createTime?: string | null
}

export interface DashboardTrendPoint {
  date: string
  label: string
  orderCount: number
  freightAmount: number
}

export interface DashboardReminder {
  key: DashboardReminderKey
  label: string
  count: number
  severity: 'danger' | 'warning'
}

export interface DashboardData {
  todayOrderCount: number
  todayFreightAmount: number
  pendingDispatchCount: number
  inTransitCount: number
  vehicleCount: number
  operatingVehicleCount: number
  pendingAuditVehicleCount: number
  completedTodayCount: number
  trend: DashboardTrendPoint[]
  statusCounts: Record<string, number>
  transitOrders: DashboardOrder[]
  recentOrders: DashboardOrder[]
  reminders: DashboardReminder[]
}

interface DashboardOrderRow {
  id?: string
  orderNo: string
  orderStatus?: string | null
  dispatchStatus?: string | null
  originStation?: string | null
  destinationStation?: string | null
  shippingCustomerName?: string | null
  shippingCustomer?: {
    customerName?: string | null
  } | null
  dispatchPlateNo?: string | null
  dispatchDriverName?: string | null
  plannedArrivalTime?: string | null
  totalFee?: number | string | null
  createTime?: string | null
}

const orderSelect =
  'id, order_no, order_status, dispatch_status, origin_station, destination_station, dispatch_plate_no, dispatch_driver_name, planned_arrival_time, total_fee, create_time, shippingCustomer:tms_customer!tms_order_shipping_customer_id_fkey(customer_name)'

const statusKeys = ['pending_load', 'pending_order', 'transporting', 'signed', 'completed'] as const

const reminderConfigs: Array<{
  key: DashboardReminderKey
  label: string
  table: string
  severity: 'danger' | 'warning'
  field: 'remaining_days' | 'expired'
}> = [
  {
    key: 'insurance',
    label: '保险到期',
    table: 'vehicle_reminder_insurance_expiry',
    severity: 'danger',
    field: 'remaining_days'
  },
  {
    key: 'inspection',
    label: '年检到期',
    table: 'vehicle_reminder_inspection_expiry',
    severity: 'danger',
    field: 'remaining_days'
  },
  {
    key: 'maintenance',
    label: '保养逾期',
    table: 'vehicle_reminder_maintenance_expiry',
    severity: 'warning',
    field: 'expired'
  },
  {
    key: 'part',
    label: '配件寿命',
    table: 'vehicle_reminder_part_service_life',
    severity: 'warning',
    field: 'expired'
  },
  {
    key: 'vehicle',
    label: '车辆临期',
    table: 'vehicle_reminder_vehicle_service_life',
    severity: 'warning',
    field: 'remaining_days'
  }
]

function toDashboardOrder(row: DashboardOrderRow): DashboardOrder {
  return {
    id: row.id,
    orderNo: row.orderNo,
    orderStatus: row.orderStatus,
    dispatchStatus: row.dispatchStatus,
    originStation: row.originStation,
    destinationStation: row.destinationStation,
    shippingCustomerName: row.shippingCustomer?.customerName ?? row.shippingCustomerName ?? null,
    dispatchPlateNo: row.dispatchPlateNo,
    dispatchDriverName: row.dispatchDriverName,
    plannedArrivalTime: row.plannedArrivalTime,
    totalFee: row.totalFee,
    createTime: row.createTime
  }
}

function asDashboardQuery(query: unknown): SupabaseQueryLike {
  return query as SupabaseQueryLike
}

async function countRows(query: SupabaseQueryLike): Promise<number> {
  const { total } = await responseHandle<null>(() => query, { ignoreCheck: true })
  return total ?? 0
}

async function fetchRows<T>(query: SupabaseQueryLike): Promise<T[]> {
  const { data } = await responseHandle<T[]>(() => query, { ignoreCheck: true })
  return data ?? []
}

async function fetchReminderCounts(): Promise<DashboardReminder[]> {
  return await Promise.all(
    reminderConfigs.map(async (item) => {
      let query = supabase
        .from(item.table)
        .select('*', { count: 'exact', head: true }) as unknown as SupabaseQueryLike
      query =
        item.field === 'remaining_days'
          ? query.lte('remaining_days', 30)
          : query.eq('expired', true)

      return { ...item, count: await countRows(query) }
    })
  )
}

function createTrend(rows: DashboardOrderRow[], days: number): DashboardTrendPoint[] {
  const points = Array.from({ length: days }, (_, index) => {
    const date = dayjs()
      .subtract(days - index - 1, 'day')
      .format('YYYY-MM-DD')
    return { date, label: dayjs(date).format('MM/DD'), orderCount: 0, freightAmount: 0 }
  })
  const pointMap = new Map(points.map((item) => [item.date, item]))

  rows.forEach((row) => {
    const date = dayjs(row.createTime).format('YYYY-MM-DD')
    const point = pointMap.get(date)
    if (!point) return
    point.orderCount += 1
    const fee = Number(row.totalFee ?? 0)
    point.freightAmount += Number.isFinite(fee) ? fee : 0
  })

  return points
}

export async function fetchDashboardData(days = 14): Promise<DashboardData> {
  const safeDays = Math.min(Math.max(days, 7), 30)
  const todayStart = dayjs().startOf('day').toISOString()
  const trendStart = dayjs()
    .subtract(safeDays - 1, 'day')
    .startOf('day')
    .toISOString()

  const [
    todayOrders,
    pendingDispatchCount,
    inTransitCount,
    vehicleRows,
    completedTodayCount,
    trendRows,
    transitRows,
    recentRows,
    reminders
  ] = await Promise.all([
    fetchRows<DashboardOrderRow>(
      asDashboardQuery(
        supabase.from('tms_order').select(orderSelect).gte('create_time', todayStart)
      )
    ),
    countRows(
      asDashboardQuery(
        supabase
          .from('tms_order')
          .select('id', { count: 'exact', head: true })
          .eq('dispatch_status', 'pending')
      )
    ),
    countRows(
      asDashboardQuery(
        supabase
          .from('tms_order')
          .select('id', { count: 'exact', head: true })
          .eq('order_status', 'transporting')
      )
    ),
    fetchRows<{ operationStatus?: string | null; auditStatus?: string | null }>(
      asDashboardQuery(supabase.from('vehicle_archive').select('operation_status, audit_status'))
    ),
    countRows(
      asDashboardQuery(
        supabase
          .from('tms_order')
          .select('id', { count: 'exact', head: true })
          .eq('order_status', 'completed')
          .gte('signed_at', todayStart)
      )
    ),
    fetchRows<DashboardOrderRow>(
      asDashboardQuery(
        supabase
          .from('tms_order')
          .select('order_no, order_status, total_fee, create_time')
          .gte('create_time', trendStart)
          .order('create_time', { ascending: true })
          .limit(2000)
      )
    ),
    fetchRows<DashboardOrderRow>(
      asDashboardQuery(
        supabase
          .from('tms_order')
          .select(orderSelect)
          .eq('order_status', 'transporting')
          .order('update_time', { ascending: false })
          .limit(6)
      )
    ),
    fetchRows<DashboardOrderRow>(
      asDashboardQuery(
        supabase
          .from('tms_order')
          .select(orderSelect)
          .order('create_time', { ascending: false })
          .limit(6)
      )
    ),
    fetchReminderCounts()
  ])

  const statusCounts = statusKeys.reduce<Record<string, number>>((result, status) => {
    result[status] = 0
    return result
  }, {})
  trendRows.forEach((row) => {
    const status = String(row.orderStatus ?? '')
    if (status in statusCounts) statusCounts[status] += 1
  })

  return {
    todayOrderCount: todayOrders.length,
    todayFreightAmount: todayOrders.reduce((total, item) => total + Number(item.totalFee ?? 0), 0),
    pendingDispatchCount,
    inTransitCount,
    vehicleCount: vehicleRows.length,
    operatingVehicleCount: vehicleRows.filter((item) => item.operationStatus === 'operating')
      .length,
    pendingAuditVehicleCount: vehicleRows.filter((item) => item.auditStatus === 'pending').length,
    completedTodayCount,
    trend: createTrend(trendRows, safeDays),
    statusCounts,
    transitOrders: transitRows.map(toDashboardOrder),
    recentOrders: recentRows.map(toDashboardOrder),
    reminders
  }
}
