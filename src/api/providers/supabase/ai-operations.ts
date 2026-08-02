import dayjs from 'dayjs'
import { useSupabase } from '@/hooks'
import type { SupabaseQueryLike } from '@/api/providers/supabase/query'

const { supabase, responseHandle } = useSupabase()

export type AiRunStatus = 'running' | 'succeeded' | 'failed'

export interface AiOperationsTrendPoint {
  date: string
  total: number
  succeeded: number
  failed: number
}

export interface AiOperationsFeatureStat {
  feature: string
  total: number
  succeeded: number
  failed: number
  averageLatencyMs: number
}

export interface AiOperationsErrorStat {
  code: string
  count: number
}

export interface AiOperationsOverview {
  days: number
  totalRuns: number
  succeededRuns: number
  failedRuns: number
  runningRuns: number
  successRate: number
  averageLatencyMs: number
  p95LatencyMs: number
  inputTokens: number
  outputTokens: number
  positiveFeedback: number
  negativeFeedback: number
  dailyTrend: AiOperationsTrendPoint[]
  featureBreakdown: AiOperationsFeatureStat[]
  topErrors: AiOperationsErrorStat[]
}

export interface AiRunFeedback {
  rating: -1 | 1
  comment?: string | null
  createTime?: string | null
}

export interface AiRunToolSummary {
  name: string
  status: 'succeeded' | 'failed'
}

export interface AiRunListItem {
  id: string
  conversationId?: string | null
  authUserId: string
  feature: string
  model: string
  promptVersion: string
  status: AiRunStatus
  inputTokens: number
  outputTokens: number
  latencyMs?: number | null
  toolCalls: AiRunToolSummary[]
  errorCode?: string | null
  errorMessage?: string | null
  metadata: Record<string, unknown>
  startedAt: string
  finishedAt?: string | null
  createBy?: string | null
  feedback?: AiRunFeedback[]
}

export interface AiRunSearchParams {
  current: number
  size: number
  feature?: string
  status?: AiRunStatus | ''
  model?: string
  timeRange?: string[]
}

export interface AiToolCallDetail {
  id: number
  toolName: string
  arguments: Record<string, unknown>
  status: 'succeeded' | 'failed'
  resultSummary: Record<string, unknown>
  latencyMs?: number | null
  errorMessage?: string | null
  createTime: string
}

export interface AiConversationMessage {
  id: number
  role: 'user' | 'assistant' | 'tool'
  content: string
  toolName?: string | null
  usage: Record<string, unknown>
  createTime: string
}

export interface AiRunConversation {
  title: string
  context: Record<string, unknown>
}

export interface AiRunDetail extends AiRunListItem {
  conversation?: AiRunConversation | null
  toolCallDetails: AiToolCallDetail[]
  messages: AiConversationMessage[]
}

export type AiDiagnosisSeverity = 'low' | 'medium' | 'high' | 'critical'
export type AiDiagnosisCategory =
  'provider' | 'configuration' | 'prompt' | 'tool' | 'data' | 'performance' | 'unknown'
export type AiDiagnosisPriority = 'P0' | 'P1' | 'P2'
export type AiDiagnosisOwner = 'platform' | 'tenant' | 'provider'

export interface AiDiagnosisRootCause {
  title: string
  evidence: string
  confidence: number
}

export interface AiDiagnosisAction {
  priority: AiDiagnosisPriority
  title: string
  steps: string[]
  owner: AiDiagnosisOwner
}

export interface AiRunDiagnosis {
  severity: AiDiagnosisSeverity
  category: AiDiagnosisCategory
  confidence: number
  summary: string
  rootCauses: AiDiagnosisRootCause[]
  actions: AiDiagnosisAction[]
  prevention: string[]
  observations: string[]
}

export interface AiRunDiagnosisResponse {
  diagnosis: AiRunDiagnosis
  runId: string
  targetRunId: string
  model: string
  promptVersion: string
  providerDurationMs: number
  durationMs: number
}

const runListSelect = `
  id,
  conversation_id,
  auth_user_id,
  feature,
  model,
  prompt_version,
  status,
  input_tokens,
  output_tokens,
  latency_ms,
  tool_calls,
  error_code,
  error_message,
  metadata,
  started_at,
  finished_at,
  create_by,
  feedback:ai_feedback(rating,comment,create_time)
`

export function createEmptyAiOperationsOverview(days = 30): AiOperationsOverview {
  return {
    days,
    totalRuns: 0,
    succeededRuns: 0,
    failedRuns: 0,
    runningRuns: 0,
    successRate: 0,
    averageLatencyMs: 0,
    p95LatencyMs: 0,
    inputTokens: 0,
    outputTokens: 0,
    positiveFeedback: 0,
    negativeFeedback: 0,
    dailyTrend: [],
    featureBreakdown: [],
    topErrors: []
  }
}

export async function fetchAiOperationsOverview(days = 30): Promise<AiOperationsOverview> {
  const safeDays = Math.min(Math.max(Math.trunc(days), 1), 90)
  const { data } = await responseHandle<AiOperationsOverview>(
    () => supabase.rpc('ai_operations_overview', { p_days: safeDays }),
    { breakReturn: true, showErrorMessage: true }
  )
  return data ?? createEmptyAiOperationsOverview(safeDays)
}

export async function fetchAiRunList(params: AiRunSearchParams) {
  const current = Math.max(params.current || 1, 1)
  const size = Math.min(Math.max(params.size || 20, 1), 100)
  const from = (current - 1) * size
  const to = from + size - 1

  let query = supabase
    .from('ai_run')
    .select(runListSelect, { count: 'exact' })
    .order('started_at', { ascending: false })
    .range(from, to)

  if (params.feature) query = query.eq('feature', params.feature)
  if (params.status) query = query.eq('status', params.status)
  if (params.model?.trim()) query = query.ilike('model', `%${params.model.trim()}%`)
  if (params.timeRange?.[0]) {
    query = query.gte('started_at', dayjs(params.timeRange[0]).startOf('day').toISOString())
  }
  if (params.timeRange?.[1]) {
    query = query.lte('started_at', dayjs(params.timeRange[1]).endOf('day').toISOString())
  }

  return await responseHandle<AiRunListItem[]>(() => query as unknown as SupabaseQueryLike, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchAiRunDetail(id: string): Promise<AiRunDetail> {
  const { data: run } = await responseHandle<AiRunListItem & { conversation?: AiRunConversation }>(
    () =>
      supabase
        .from('ai_run')
        .select(`${runListSelect},conversation:ai_conversation(title,context)`)
        .eq('id', id)
        .single(),
    { breakReturn: true, showErrorMessage: true }
  )
  if (!run) throw new Error('AI 运行记录不存在或无权查看')

  const toolPromise = responseHandle<AiToolCallDetail[]>(
    () =>
      supabase
        .from('ai_tool_call')
        .select('id,tool_name,arguments,status,result_summary,latency_ms,error_message,create_time')
        .eq('run_id', id)
        .order('create_time', { ascending: true }),
    { breakReturn: true }
  )
  const messagePromise = run.conversationId
    ? responseHandle<AiConversationMessage[]>(
        () =>
          supabase
            .from('ai_message')
            .select('id,role,content,tool_name,usage,create_time')
            .eq('conversation_id', run.conversationId)
            .order('create_time', { ascending: true }),
        { breakReturn: true }
      )
    : Promise.resolve({ data: [] as AiConversationMessage[], error: null })

  const [toolResult, messageResult] = await Promise.all([toolPromise, messagePromise])
  return {
    ...run,
    toolCallDetails: toolResult.data ?? [],
    messages: messageResult.data ?? []
  }
}

async function normalizeFunctionError(error: unknown): Promise<Error> {
  if (error && typeof error === 'object' && 'context' in error) {
    const context = (error as { context?: unknown }).context
    if (context instanceof Response) {
      try {
        const payload = (await context.clone().json()) as { message?: unknown }
        if (typeof payload.message === 'string' && payload.message)
          return new Error(payload.message)
      } catch {
        // Fall back to the original Edge Function error.
      }
    }
  }
  if (error instanceof Error) return error
  return new Error('AI 运行诊断暂时不可用')
}

export async function diagnoseAiRun(id: string): Promise<AiRunDiagnosisResponse> {
  const { data, error } = await supabase.functions.invoke<AiRunDiagnosisResponse>(
    'ai-run-diagnosis',
    { body: { runId: id } }
  )
  if (error) throw await normalizeFunctionError(error)
  if (!data?.runId || !data.diagnosis?.summary) throw new Error('AI 运行诊断返回格式无效')
  return data
}
