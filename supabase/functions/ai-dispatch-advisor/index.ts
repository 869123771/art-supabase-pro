import { createClient } from 'jsr:@supabase/supabase-js@2'
import { recommendDispatchResources } from '../_shared/dispatch-recommendation-rules.ts'

interface DispatchAdvisorRequest {
  orderId?: string
  limit?: number
}

interface AppUser {
  tenant_id: string
  user_email: string
  status: string | null
}

const FEATURE = 'dispatch_recommendation'
const RULE_VERSION = 'dispatch-rules-v1'
const HISTORY_DAYS = 180
const MAX_VEHICLES = 500
const MAX_HISTORY_ROWS = 2_000

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' }
  })
}

function text(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function integer(value: unknown, fallback: number, min: number, max: number): number {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? Math.min(max, Math.max(min, Math.trunc(parsed))) : fallback
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value
  )
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') {
    return json({ code: 'method_not_allowed', message: 'Method not allowed' }, 405)
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const authHeader = request.headers.get('Authorization') ?? ''
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authHeader) {
    return json({ code: 'unauthorized', message: 'Authentication required' }, 401)
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  })
  const token = authHeader.replace(/^Bearer\s+/i, '')
  const {
    data: { user },
    error: authError
  } = await authClient.auth.getUser(token)
  if (authError || !user) return json({ code: 'unauthorized', message: 'Invalid session' }, 401)

  const body = (await request.json().catch(() => ({}))) as DispatchAdvisorRequest
  const orderId = text(body.orderId)
  if (!isUuid(orderId)) {
    return json({ code: 'invalid_order_id', message: '缺少有效的待调度订单 ID' }, 400)
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  })
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false }
  })
  const { data: appUserData, error: appUserError } = await admin
    .from('sys_user')
    .select('tenant_id,user_email,status')
    .eq('auth_user_id', user.id)
    .maybeSingle()
  const appUser = appUserData as AppUser | null
  if (appUserError || !appUser?.tenant_id || appUser.status === '0') {
    return json({ code: 'forbidden', message: '当前用户不可使用 AI 调度推荐' }, 403)
  }

  const startedAt = Date.now()
  let runId = ''
  try {
    const { data: order, error: orderError } = await userClient
      .from('tms_order')
      .select(
        'id,order_no,order_status,dispatch_status,origin_station,destination_station,cargo_weight_total,cargo_volume_total,transport_mode,planned_departure_time,planned_arrival_time'
      )
      .eq('id', orderId)
      .maybeSingle()
    if (orderError) throw orderError
    if (!order) return json({ code: 'order_not_found', message: '未找到可查看的订单' }, 404)
    if (order.dispatch_status !== 'pending') {
      return json({ code: 'already_dispatched', message: '该订单已配载，请刷新列表后重试' }, 409)
    }

    const { data: run, error: runError } = await admin
      .from('ai_run')
      .insert({
        auth_user_id: user.id,
        tenant_id: appUser.tenant_id,
        feature: FEATURE,
        model: RULE_VERSION,
        prompt_version: RULE_VERSION,
        metadata: {
          orderId,
          historyDays: HISTORY_DAYS,
          decisionMode: 'advisory_only'
        },
        create_by: appUser.user_email,
        update_by: appUser.user_email
      })
      .select('id')
      .single()
    if (runError) throw runError
    runId = run.id

    const historyStart = new Date(Date.now() - HISTORY_DAYS * 86_400_000).toISOString()
    const [vehiclesResult, assignmentsResult, historyResult] = await Promise.all([
      userClient
        .from('vehicle_archive')
        .select(
          `id,carrier_id,plate_no,company_name,vehicle_type,tonnage_or_seat,overall_length,approved_load_mass,operation_route,operation_status,audit_status,service_end_time,primary_driver_id,primaryDriver:tms_driver!vehicle_archive_primary_driver_id_fkey(id,driver_name,license_type,license_expire_date,enabled)`,
          { count: 'exact' }
        )
        .eq('audit_status', 'approved')
        .eq('operation_status', 'operating')
        .order('plate_no', { ascending: true })
        .limit(MAX_VEHICLES),
      userClient
        .from('tms_order')
        .select('id,dispatch_status,dispatch_vehicle_id,dispatch_driver_id')
        .in('dispatch_status', ['loaded', 'dispatched', 'loading', 'transporting', 'unloading'])
        .limit(2_000),
      userClient
        .from('tms_order')
        .select(
          'dispatch_vehicle_id,origin_station,destination_station,planned_arrival_time,signed_at,create_time'
        )
        .in('order_status', ['signed', 'completed'])
        .not('dispatch_vehicle_id', 'is', null)
        .gte('create_time', historyStart)
        .order('create_time', { ascending: false })
        .limit(MAX_HISTORY_ROWS)
    ])
    if (vehiclesResult.error) throw vehiclesResult.error
    if (assignmentsResult.error) throw assignmentsResult.error
    if (historyResult.error) throw historyResult.error

    const vehicleRows = (vehiclesResult.data ?? []) as Array<Record<string, unknown>>
    const driverIds = Array.from(
      new Set(
        vehicleRows
          .map((vehicle) => String(vehicle.primary_driver_id ?? '').trim())
          .filter(Boolean)
      )
    )
    let secureDrivers: Array<Record<string, unknown>> = []
    if (driverIds.length) {
      const secureDriversResult = await userClient.rpc('tms_list_driver_options_secure', {
        p_carrier_id: null,
        p_driver_name: null,
        p_driver_type: null,
        p_ids: driverIds,
        p_include_disabled: true,
        p_max_rows: driverIds.length
      })
      if (secureDriversResult.error) throw secureDriversResult.error
      secureDrivers = Array.isArray(secureDriversResult.data)
        ? (secureDriversResult.data as Array<Record<string, unknown>>)
        : []
    }
    const secureDriversById = new Map(
      secureDrivers.map((driver) => [String(driver.id ?? ''), driver])
    )
    const securedVehicleRows = vehicleRows.map((vehicle) => {
      const driverId = String(vehicle.primary_driver_id ?? '')
      const secureDriver = secureDriversById.get(driverId)
      if (!secureDriver) return vehicle
      return {
        ...vehicle,
        primaryDriver: {
          ...((vehicle.primaryDriver as Record<string, unknown> | null) ?? {}),
          ...secureDriver
        }
      }
    })

    const result = recommendDispatchResources({
      order: order as Record<string, unknown>,
      vehicles: securedVehicleRows,
      activeAssignments: (assignmentsResult.data ?? []) as Array<Record<string, unknown>>,
      history: (historyResult.data ?? []) as Array<Record<string, unknown>>,
      limit: integer(body.limit, 5, 1, 10)
    })

    const { error: finishError } = await admin
      .from('ai_run')
      .update({
        status: 'succeeded',
        latency_ms: Date.now() - startedAt,
        finished_at: new Date().toISOString(),
        metadata: {
          orderId,
          historyDays: HISTORY_DAYS,
          decisionMode: 'advisory_only',
          evaluatedVehicles: result.evaluatedVehicles,
          eligibleVehicles: result.eligibleVehicles,
          recommendationCount: result.recommendations.length,
          sourceVehicleCount: vehiclesResult.count ?? result.evaluatedVehicles,
          sourceTruncated: (vehiclesResult.count ?? 0) > MAX_VEHICLES
        },
        update_by: appUser.user_email
      })
      .eq('id', runId)
    if (finishError) console.error('ai-dispatch-advisor audit update failed', finishError.message)

    return json({
      runId,
      ruleVersion: RULE_VERSION,
      generatedAt: new Date().toISOString(),
      order: {
        id: order.id,
        orderNo: order.order_no,
        originStation: order.origin_station,
        destinationStation: order.destination_station
      },
      summary: result.recommendations.length
        ? `已从 ${result.evaluatedVehicles} 辆候选车辆中生成 ${result.recommendations.length} 条推荐`
        : '当前没有同时满足车辆、司机、载重和占用条件的候选资源',
      ...result
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    console.error('ai-dispatch-advisor failed', message)
    if (runId) {
      const { error: finishError } = await admin
        .from('ai_run')
        .update({
          status: 'failed',
          latency_ms: Date.now() - startedAt,
          error_code: 'dispatch_advisor_failed',
          error_message: message.slice(0, 2_000),
          finished_at: new Date().toISOString(),
          update_by: appUser.user_email
        })
        .eq('id', runId)
      if (finishError) console.error('ai-dispatch-advisor audit update failed', finishError.message)
    }
    return json({ code: 'dispatch_advisor_failed', message: 'AI 调度推荐生成失败，请稍后重试' }, 500)
  }
})
