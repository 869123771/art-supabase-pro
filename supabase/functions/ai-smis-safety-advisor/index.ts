import { createClient } from 'jsr:@supabase/supabase-js@2'
import { assessSmisSafety } from '../_shared/smis-safety-rules.ts'

interface AppUser {
  tenant_id: string
  user_email: string
  status: string | null
}

const FEATURE = 'smis_safety_advisor'
const RULE_VERSION = 'smis-safety-rules-v1'
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
  const { data: { user }, error: authError } = await authClient.auth.getUser(token)
  if (authError || !user) return json({ code: 'unauthorized', message: 'Invalid session' }, 401)

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
    return json({ code: 'forbidden', message: '当前用户不可使用 AI 安全研判' }, 403)
  }

  const startedAt = Date.now()
  let runId = ''
  try {
    const now = new Date()
    const nextMonth = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000)
    const [accidentCountsResult, ...requests] = await Promise.all([
      userClient.rpc('smis_get_accident_risk_counts_secure'),
      userClient.from('smis_risk_point').select('id', { count: 'exact', head: true }).eq('status', 'active').eq('current_risk_level', 'critical'),
      userClient.from('smis_risk_point').select('id', { count: 'exact', head: true }).eq('status', 'active').eq('current_risk_level', 'major'),
      userClient.from('smis_hidden_danger').select('id', { count: 'exact', head: true }).not('status', 'in', '(closed,cancelled)'),
      userClient.from('smis_hidden_danger').select('id', { count: 'exact', head: true }).not('status', 'in', '(closed,cancelled)').lt('rectification_deadline', now.toISOString()),
      userClient.from('smis_inspection_task').select('id', { count: 'exact', head: true }).in('status', ['pending', 'in_progress']).lt('scheduled_end_at', now.toISOString()),
      userClient.from('smis_emergency_plan').select('id', { count: 'exact', head: true }).eq('status', 'active'),
      userClient.from('smis_emergency_drill').select('id', { count: 'exact', head: true }).eq('status', 'planned').gte('scheduled_at', now.toISOString()).lte('scheduled_at', nextMonth.toISOString())
    ])
    const evidenceError = accidentCountsResult.error ?? requests.find((result) => result.error)?.error
    if (evidenceError) throw evidenceError
    const accidentCounts = (accidentCountsResult.data ?? {}) as {
      open_accidents?: number
      major_accidents?: number
    }
    const assessment = assessSmisSafety({
      criticalRiskPoints: requests[0].count ?? 0,
      majorRiskPoints: requests[1].count ?? 0,
      openDangers: requests[2].count ?? 0,
      overdueDangers: requests[3].count ?? 0,
      overdueInspections: requests[4].count ?? 0,
      openAccidents: Number(accidentCounts.open_accidents ?? 0),
      majorAccidents: Number(accidentCounts.major_accidents ?? 0),
      activeEmergencyPlans: requests[5].count ?? 0,
      upcomingDrills: requests[6].count ?? 0
    })
    const { data: run, error: runError } = await admin.from('ai_run').insert({
      auth_user_id: user.id,
      tenant_id: appUser.tenant_id,
      feature: FEATURE,
      model: RULE_VERSION,
      prompt_version: RULE_VERSION,
      metadata: {
        decisionMode: 'advisory_only',
        automaticBusinessWrite: false,
        riskLevel: assessment.riskLevel,
        riskScore: assessment.riskScore,
        signalCount: assessment.signals.length
      },
      create_by: appUser.user_email,
      update_by: appUser.user_email
    }).select('id').single()
    if (runError) throw runError
    runId = run.id
    await admin.from('ai_run').update({
      status: 'succeeded', latency_ms: Date.now() - startedAt,
      finished_at: new Date().toISOString(), update_by: appUser.user_email
    }).eq('id', runId)
    return json({ runId, ruleVersion: RULE_VERSION, generatedAt: new Date().toISOString(), assessment })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    console.error('ai-smis-safety-advisor failed', message)
    if (runId) {
      await admin.from('ai_run').update({
        status: 'failed', latency_ms: Date.now() - startedAt,
        error_code: 'smis_safety_advisor_failed', error_message: message.slice(0, 2000),
        finished_at: new Date().toISOString(), update_by: appUser.user_email
      }).eq('id', runId)
    }
    return json({ code: 'smis_safety_advisor_failed', message: 'AI 安全研判失败，请稍后重试' }, 500)
  }
})
