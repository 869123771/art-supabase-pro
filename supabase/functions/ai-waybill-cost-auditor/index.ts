import { createClient } from 'jsr:@supabase/supabase-js@2'
import { assessWaybillCost } from '../_shared/waybill-cost-audit-rules.ts'

interface WaybillCostAuditRequest {
  costId?: string
}

interface AppUser {
  tenant_id: string
  user_email: string
  status: string | null
}

const FEATURE = 'waybill_cost_audit'
const RULE_VERSION = 'waybill-cost-audit-rules-v1'

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

  const body = (await request.json().catch(() => ({}))) as WaybillCostAuditRequest
  const costId = text(body.costId)
  if (!isUuid(costId)) {
    return json({ code: 'invalid_cost_id', message: '缺少有效的运单费用 ID' }, 400)
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
    return json({ code: 'forbidden', message: '当前用户不可使用 AI 运单费用审核' }, 403)
  }

  const startedAt = Date.now()
  let runId = ''
  try {
    const { data: cost, error: costError } = await userClient
      .from('tms_waybill_cost')
      .select(
        `
          *,
          waybill:tms_waybill!tms_waybill_cost_waybill_id_fkey(
            id,
            waybill_no,
            origin_city,
            destination_city,
            order:tms_order!tms_waybill_order_id_fkey(
              id,
              origin_station,
              destination_station
            )
          )
        `
      )
      .eq('id', costId)
      .maybeSingle()
    if (costError) throw costError
    if (!cost) return json({ code: 'cost_not_found', message: '未找到可查看的运单费用' }, 404)

    const waybillId = text(cost.waybill_id)
    const costType = text(cost.cost_type)
    const [siblingResult, referenceResult, profitResult] = await Promise.all([
      userClient
        .from('tms_waybill_cost')
        .select('id,waybill_id,cost_type,amount,occurred_on,payee_name,audit_status')
        .eq('waybill_id', waybillId),
      userClient
        .from('tms_waybill_cost')
        .select('id,amount')
        .eq('cost_type', costType)
        .eq('audit_status', 'approved')
        .order('occurred_on', { ascending: false })
        .limit(100),
      userClient.from('tms_waybill_profit').select('*').eq('waybill_id', waybillId).maybeSingle()
    ])
    if (siblingResult.error) throw siblingResult.error
    if (referenceResult.error) throw referenceResult.error
    if (profitResult.error) throw profitResult.error

    const { data: run, error: runError } = await admin
      .from('ai_run')
      .insert({
        auth_user_id: user.id,
        tenant_id: appUser.tenant_id,
        feature: FEATURE,
        model: RULE_VERSION,
        prompt_version: RULE_VERSION,
        metadata: {
          costId,
          waybillId,
          decisionMode: 'advisory_only',
          automaticFinancialWrite: false
        },
        create_by: appUser.user_email,
        update_by: appUser.user_email
      })
      .select('id')
      .single()
    if (runError) throw runError
    runId = run.id

    const assessment = assessWaybillCost({
      cost,
      siblingCosts: siblingResult.data ?? [],
      referenceCosts: referenceResult.data ?? [],
      profit: profitResult.data
    })

    const { error: finishError } = await admin
      .from('ai_run')
      .update({
        status: 'succeeded',
        latency_ms: Date.now() - startedAt,
        finished_at: new Date().toISOString(),
        metadata: {
          costId,
          waybillId,
          decisionMode: 'advisory_only',
          automaticFinancialWrite: false,
          riskLevel: assessment.riskLevel,
          riskScore: assessment.riskScore,
          recommendation: assessment.recommendation,
          signalCount: assessment.signals.length,
          signalTypes: assessment.signals.map((item) => item.type)
        },
        update_by: appUser.user_email
      })
      .eq('id', runId)
    if (finishError) {
      console.error('ai-waybill-cost-auditor audit update failed', finishError.message)
    }

    return json({
      runId,
      ruleVersion: RULE_VERSION,
      generatedAt: new Date().toISOString(),
      assessment
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    console.error('ai-waybill-cost-auditor failed', message)
    if (runId) {
      const { error: finishError } = await admin
        .from('ai_run')
        .update({
          status: 'failed',
          latency_ms: Date.now() - startedAt,
          error_code: 'waybill_cost_audit_failed',
          error_message: message.slice(0, 2_000),
          finished_at: new Date().toISOString(),
          update_by: appUser.user_email
        })
        .eq('id', runId)
      if (finishError) {
        console.error('ai-waybill-cost-auditor audit update failed', finishError.message)
      }
    }
    return json(
      { code: 'waybill_cost_audit_failed', message: 'AI 运单费用审核失败，请稍后重试' },
      500
    )
  }
})
