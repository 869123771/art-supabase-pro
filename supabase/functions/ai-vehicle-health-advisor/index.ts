import {
  authenticateAiEdgeRequest,
  authorizeAiEdgeAppUser
} from '../_shared/ai-edge-user-context.ts'
import { assessVehicleHealth } from '../_shared/vehicle-health-rules.ts'

interface VehicleHealthRequest {
  vehicleId?: string
}

const FEATURE = 'vehicle_health_advisor'
const RULE_VERSION = 'vehicle-health-rules-v1'
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

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') {
    return json({ code: 'method_not_allowed', message: 'Method not allowed' }, 405)
  }

  const authentication = await authenticateAiEdgeRequest(request, 'Invalid session')
  if (!authentication.ok) {
    return json(
      { code: authentication.code, message: authentication.message },
      authentication.status
    )
  }

  const body = (await request.json().catch(() => ({}))) as VehicleHealthRequest
  const vehicleId = text(body.vehicleId)
  if (!isUuid(vehicleId)) {
    return json({ code: 'invalid_vehicle_id', message: '缺少有效的车辆 ID' }, 400)
  }

  const context = await authorizeAiEdgeAppUser(authentication, '当前用户不可使用 AI 车辆健康研判')
  if (!context.ok) {
    return json({ code: context.code, message: context.message }, context.status)
  }
  const { admin, userClient, user, appUser } = context

  const startedAt = Date.now()
  let runId = ''
  try {
    const { data: vehicle, error: vehicleError } = await userClient
      .from('mdm_vehicle')
      .select(
        'id,plate_no,vehicle_type,operation_status,manufacturer,brand_model,start_use_date,service_years'
      )
      .eq('id', vehicleId)
      .maybeSingle()
    if (vehicleError) throw vehicleError
    if (!vehicle) return json({ code: 'vehicle_not_found', message: '未找到可查看的车辆档案' }, 404)

    const evidenceResults = await Promise.all([
      userClient.rpc('vms_get_vehicle_insurance_expiry_context_secure', {
        p_vehicle_id: vehicleId,
        p_until: null,
        p_limit: 20
      }),
      userClient.rpc('vms_get_vehicle_inspection_expiry_context_secure', {
        p_vehicle_id: vehicleId,
        p_until: null,
        p_limit: 20
      }),
      userClient.rpc('vms_get_vehicle_maintenance_health_context_secure', {
        p_vehicle_id: vehicleId,
        p_limit: 100
      }),
      userClient.rpc('vms_get_vehicle_mileage_health_context_secure', {
        p_vehicle_id: vehicleId,
        p_limit: 60
      }),
      userClient.rpc('vms_get_vehicle_accident_health_context_secure', {
        p_vehicle_id: vehicleId,
        p_limit: 50
      }),
      userClient.rpc('vms_get_vehicle_routine_inspection_health_context_secure', {
        p_vehicle_id: vehicleId,
        p_limit: 100
      }),
      userClient.rpc('vms_get_vehicle_part_health_context_secure', {
        p_vehicle_id: vehicleId,
        p_limit: 200
      })
    ])
    const evidenceError = evidenceResults.find((result) => result.error)?.error
    if (evidenceError) throw evidenceError
    const [insurance, inspections, maintenance, mileage, accidents, routineInspections, parts] =
      evidenceResults.map((result) => result.data ?? [])

    const { data: run, error: runError } = await admin
      .from('ai_run')
      .insert({
        auth_user_id: user.id,
        tenant_id: appUser.tenant_id,
        feature: FEATURE,
        model: RULE_VERSION,
        prompt_version: RULE_VERSION,
        metadata: {
          vehicleId,
          plateNo: vehicle.plate_no,
          decisionMode: 'advisory_only',
          automaticVehicleWrite: false
        },
        create_by: appUser.user_email,
        update_by: appUser.user_email
      })
      .select('id')
      .single()
    if (runError) throw runError
    runId = run.id

    const assessment = assessVehicleHealth({
      vehicle,
      insurance,
      inspections,
      maintenance,
      mileage,
      accidents,
      routineInspections,
      parts
    })
    const { error: finishError } = await admin
      .from('ai_run')
      .update({
        status: 'succeeded',
        latency_ms: Date.now() - startedAt,
        finished_at: new Date().toISOString(),
        metadata: {
          vehicleId,
          plateNo: vehicle.plate_no,
          decisionMode: 'advisory_only',
          automaticVehicleWrite: false,
          riskLevel: assessment.riskLevel,
          riskScore: assessment.riskScore,
          healthScore: assessment.healthScore,
          signalCount: assessment.signals.length,
          signalTypes: assessment.signals.map((item) => item.type)
        },
        update_by: appUser.user_email
      })
      .eq('id', runId)
    if (finishError) {
      console.error('ai-vehicle-health-advisor audit update failed', finishError.message)
    }

    return json({
      runId,
      ruleVersion: RULE_VERSION,
      generatedAt: new Date().toISOString(),
      assessment
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    console.error('ai-vehicle-health-advisor failed', message)
    if (runId) {
      const { error: finishError } = await admin
        .from('ai_run')
        .update({
          status: 'failed',
          latency_ms: Date.now() - startedAt,
          error_code: 'vehicle_health_advisor_failed',
          error_message: message.slice(0, 2_000),
          finished_at: new Date().toISOString(),
          update_by: appUser.user_email
        })
        .eq('id', runId)
      if (finishError) {
        console.error('ai-vehicle-health-advisor audit update failed', finishError.message)
      }
    }
    return json(
      { code: 'vehicle_health_advisor_failed', message: 'AI 车辆健康研判失败，请稍后重试' },
      500
    )
  }
})
