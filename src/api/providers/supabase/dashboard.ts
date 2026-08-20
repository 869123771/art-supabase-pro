import dayjs, { type Dayjs } from 'dayjs'
import { useSupabase } from '@/hooks'
import type { SupabaseQueryLike } from '@/api/providers/supabase/query'
import { fetchSecureOrders } from '@/api/modules/tms/transport-secure'

const { supabase, responseHandle } = useSupabase()

export type DashboardReminderKey = 'insurance' | 'inspection' | 'maintenance' | 'part' | 'vehicle'
export type DashboardTrendPeriod = 'today' | 'week' | 'month' | 'year'

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

interface DashboardTrendRange {
  start: Dayjs
  pointCount: number
  unit: 'hour' | 'day' | 'month'
  keyFormat: string
  labelFormat: string
}

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
      let query = supabase.from(item.table).select('*', { count: 'exact', head: true })
      query =
        item.field === 'remaining_days'
          ? query.lte('remaining_days', 30)
          : query.eq('expired', true)

      return { ...item, count: await countRows(query) }
    })
  )
}

function getMondayStart(reference: Dayjs): Dayjs {
  const daysFromMonday = (reference.day() + 6) % 7
  return reference.subtract(daysFromMonday, 'day').startOf('day')
}

function getTrendRange(period: DashboardTrendPeriod, reference = dayjs()): DashboardTrendRange {
  if (period === 'today') {
    return {
      start: reference.startOf('day'),
      pointCount: 24,
      unit: 'hour',
      keyFormat: 'YYYY-MM-DD HH',
      labelFormat: 'HH:mm'
    }
  }
  if (period === 'month') {
    return {
      start: reference.startOf('month'),
      pointCount: reference.daysInMonth(),
      unit: 'day',
      keyFormat: 'YYYY-MM-DD',
      labelFormat: 'MM/DD'
    }
  }
  if (period === 'year') {
    return {
      start: reference.startOf('year'),
      pointCount: 12,
      unit: 'month',
      keyFormat: 'YYYY-MM',
      labelFormat: 'M月'
    }
  }
  return {
    start: getMondayStart(reference),
    pointCount: 7,
    unit: 'day',
    keyFormat: 'YYYY-MM-DD',
    labelFormat: 'MM/DD'
  }
}

function createTrend(rows: DashboardOrderRow[], range: DashboardTrendRange): DashboardTrendPoint[] {
  const pointMap = new Map<string, DashboardTrendPoint>()
  const points = Array.from({ length: range.pointCount }, (_, index) => {
    const pointDate = range.start.add(index, range.unit)
    const point = {
      date: pointDate.format(range.keyFormat),
      label: pointDate.format(range.labelFormat),
      orderCount: 0,
      freightAmount: 0
    }
    pointMap.set(point.date, point)
    return point
  })

  rows.forEach((row) => {
    const date = dayjs(row.createTime).format(range.keyFormat)
    const point = pointMap.get(date)
    if (!point) return
    point.orderCount += 1
    const fee = Number(row.totalFee ?? 0)
    point.freightAmount += Number.isFinite(fee) ? fee : 0
  })

  return points
}

export async function fetchDashboardData(
  period: DashboardTrendPeriod = 'month'
): Promise<DashboardData> {
  const trendRange = getTrendRange(period)
  const todayDate = dayjs().format('YYYY-MM-DD')
  const trendStartDate = trendRange.start.format('YYYY-MM-DD')

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
    fetchSecureOrders<Api.Tms.Order.OrderRecord>(
      { createTimeRange: [todayDate, todayDate], maxRows: 10000 },
      'dashboard'
    ).then((result) => result.data as DashboardOrderRow[]),
    fetchSecureOrders<Api.Tms.Order.OrderRecord>(
      { dispatchStatus: 'pending', countOnly: true },
      'dashboard'
    ).then((result) => result.total),
    fetchSecureOrders<Api.Tms.Order.OrderRecord>(
      { orderStatus: 'transporting', countOnly: true },
      'dashboard'
    ).then((result) => result.total),
    fetchRows<{ operationStatus?: string | null; auditStatus?: string | null }>(
      asDashboardQuery(supabase.from('vehicle_archive').select('operation_status, audit_status'))
    ),
    fetchSecureOrders<Api.Tms.Order.OrderRecord>(
      {
        orderStatus: 'completed',
        signedTimeRange: [todayDate, todayDate],
        countOnly: true
      },
      'dashboard'
    ).then((result) => result.total),
    fetchSecureOrders<Api.Tms.Order.OrderRecord>(
      { createTimeRange: [trendStartDate], maxRows: 5000 },
      'dashboard'
    ).then((result) => result.data as DashboardOrderRow[]),
    fetchSecureOrders<Api.Tms.Order.OrderRecord>(
      { orderStatus: 'transporting', maxRows: 6 },
      'dashboard'
    ).then((result) => result.data as DashboardOrderRow[]),
    fetchSecureOrders<Api.Tms.Order.OrderRecord>({ maxRows: 6 }, 'dashboard').then(
      (result) => result.data as DashboardOrderRow[]
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
    trend: createTrend(trendRows, trendRange),
    statusCounts,
    transitOrders: transitRows.map(toDashboardOrder),
    recentOrders: recentRows.map(toDashboardOrder),
    reminders
  }
}
