import {
  authenticateAiEdgeRequest,
  authorizeAiEdgeAppUser
} from '../_shared/ai-edge-user-context.ts'
import { assessWaybillProfitPortfolio } from '../_shared/waybill-profit-analysis-rules.ts'

const FEATURE = 'waybill_profit_analysis'
const RULE_VERSION = 'waybill-profit-analysis-rules-v1'

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

  const authentication = await authenticateAiEdgeRequest(request, 'Invalid session')
  if (!authentication.ok) {
    return json(
      { code: authentication.code, message: authentication.message },
      authentication.status
    )
  }

  const context = await authorizeAiEdgeAppUser(authentication, '当前用户不可使用 AI 运单利润诊断')
  if (!context.ok) {
    return json({ code: context.code, message: context.message }, context.status)
  }
  const { admin, userClient, user, appUser } = context

  const startedAt = Date.now()
  let runId = ''
  try {
    const { data: profitRows, error: profitError } = await userClient.rpc(
      'tms_get_waybill_profit_ai_evidence_secure',
      { p_limit: 300 }
    )
    if (profitError) throw profitError

    const { data: run, error: runError } = await admin
      .from('ai_run')
      .insert({
        auth_user_id: user.id,
        tenant_id: appUser.tenant_id,
        feature: FEATURE,
        model: RULE_VERSION,
        prompt_version: RULE_VERSION,
        metadata: {
          scope: 'tenant_portfolio',
          rowLimit: 300,
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

    const assessment = assessWaybillProfitPortfolio(Array.isArray(profitRows) ? profitRows : [])
    const { error: finishError } = await admin
      .from('ai_run')
      .update({
        status: 'succeeded',
        latency_ms: Date.now() - startedAt,
        finished_at: new Date().toISOString(),
        metadata: {
          scope: 'tenant_portfolio',
          decisionMode: 'advisory_only',
          automaticFinancialWrite: false,
          riskLevel: assessment.riskLevel,
          riskScore: assessment.riskScore,
          recommendation: assessment.recommendation,
          signalCount: assessment.signals.length,
          analyzedWaybillCount: assessment.metrics.totalWaybills,
          costCoverage: assessment.metrics.costCoverage
        },
        update_by: appUser.user_email
      })
      .eq('id', runId)
    if (finishError) {
      console.error('ai-waybill-profit-analyst audit update failed', finishError.message)
    }

    return json({
      runId,
      ruleVersion: RULE_VERSION,
      generatedAt: new Date().toISOString(),
      assessment
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    console.error('ai-waybill-profit-analyst failed', message)
    if (runId) {
      const { error: finishError } = await admin
        .from('ai_run')
        .update({
          status: 'failed',
          latency_ms: Date.now() - startedAt,
          error_code: 'waybill_profit_analysis_failed',
          error_message: message.slice(0, 2_000),
          finished_at: new Date().toISOString(),
          update_by: appUser.user_email
        })
        .eq('id', runId)
      if (finishError) {
        console.error('ai-waybill-profit-analyst audit update failed', finishError.message)
      }
    }
    return json(
      { code: 'waybill_profit_analysis_failed', message: 'AI 运单利润诊断失败，请稍后重试' },
      500
    )
  }
})
