import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2'
import {
  loadAiRuntimeConfig,
  type AiRuntimeConfig
} from '../_shared/ai-runtime-config.ts'
import { loadPublishedAiPrompt } from '../_shared/ai-prompt-template.ts'

const FEATURE = 'project_assistant'
const PROJECT_REF = 'ckbftoopuyophiebamwy'
const DEFAULT_PROMPT = [
  '你是 Art Supabase Pro 的 Supabase 项目管理助手。',
  '你只服务于平台超级管理员，并且当前处于严格只读模式。',
  '项目事实必须通过白名单工具查询；不得猜测数据库对象或 Edge Function。',
  '你可以解释或生成 DDL、DQL、DML 草稿，但绝不能执行任何数据库变更或任意 SQL。',
  '回答使用清晰的中文，写明 schema、对象名称、影响范围和人工复核步骤。'
].join('\n')

type MessageRole = 'user' | 'assistant'
type CatalogAction =
  | 'overview'
  | 'schemas'
  | 'list_objects'
  | 'object_detail'
  | 'relationships'
  | 'edge_functions'
type ToolName =
  | 'get_project_overview'
  | 'list_database_objects'
  | 'get_database_object_detail'
  | 'get_table_relationships'
  | 'list_edge_functions'

interface AssistantMessage {
  role: MessageRole
  content: string
}

interface AssistantContext {
  routeName?: string
  routePath?: string
  pageTitle?: string
  selectedObject?: Record<string, unknown>
  query?: Record<string, unknown>
}

interface AssistantRequest {
  action?: 'chat' | 'feedback' | 'catalog'
  conversationId?: string
  runId?: string
  rating?: -1 | 1
  comment?: string
  messages?: AssistantMessage[]
  context?: AssistantContext
  catalogAction?: CatalogAction
  args?: Record<string, unknown>
}

interface AppUser {
  tenant_id: string
  user_email: string
  status: string | null
}

interface ProviderToolCall {
  id: string
  type: 'function'
  function: { name: string; arguments: string }
}

interface ProviderMessage {
  role: 'system' | 'user' | 'assistant' | 'tool'
  content: string | null
  tool_call_id?: string
  tool_calls?: ProviderToolCall[]
}

interface ProviderResult {
  message: ProviderMessage
  usage: { prompt_tokens?: number; completion_tokens?: number }
  model: string
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
}

const MAX_HISTORY_MESSAGES = 12
const MAX_MESSAGE_LENGTH = 4000
const MAX_TOOL_CALLS = 4
const toolNames = new Set<ToolName>([
  'get_project_overview',
  'list_database_objects',
  'get_database_object_detail',
  'get_table_relationships',
  'list_edge_functions'
])
const catalogActions = new Set<CatalogAction>([
  'overview',
  'schemas',
  'list_objects',
  'object_detail',
  'relationships',
  'edge_functions'
])

const edgeFunctionManifest = [
  ['sync-user', true],
  ['register-and-sync-user', false],
  ['check_user_status', false],
  ['admin_reset_password', true],
  ['execute-sql-with-columns', true],
  ['proxy-logs', true],
  ['ai-sql-assistant', true],
  ['driver-auth', false],
  ['sync-driver-waybills', true],
  ['ai-order-assistant', true],
  ['ai-assistant', true],
  ['ai-provider-catalog', true],
  ['ai-run-diagnosis', true],
  ['ai-project-assistant', true]
].map(([slug, verifyJwt]) => ({ slug, name: slug, status: 'ACTIVE', verifyJwt, source: 'manifest' }))

const tools = [
  {
    type: 'function',
    function: {
      name: 'get_project_overview',
      description: '查询当前 Supabase 项目的数据库版本以及 schema、表、视图、函数、触发器、RLS 策略和索引数量。',
      parameters: { type: 'object', properties: {}, additionalProperties: false }
    }
  },
  {
    type: 'function',
    function: {
      name: 'list_database_objects',
      description: '按对象类型、schema 和关键词查询数据库对象目录。',
      parameters: {
        type: 'object',
        properties: {
          objectType: {
            type: 'string',
            enum: ['all', 'table', 'view', 'function', 'trigger', 'policy', 'index']
          },
          schema: { type: 'string' },
          keyword: { type: 'string' },
          limit: { type: 'integer', minimum: 1, maximum: 100 }
        },
        additionalProperties: false
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'get_database_object_detail',
      description: '查看一个数据库对象的字段、约束和只读 DDL 定义。',
      parameters: {
        type: 'object',
        properties: {
          objectType: {
            type: 'string',
            enum: ['table', 'view', 'materialized_view', 'function', 'trigger', 'policy', 'index']
          },
          schema: { type: 'string' },
          name: { type: 'string' }
        },
        required: ['objectType', 'schema', 'name'],
        additionalProperties: false
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'get_table_relationships',
      description: '查询数据库外键关系，可限定 schema 或表名。',
      parameters: {
        type: 'object',
        properties: { schema: { type: 'string' }, name: { type: 'string' } },
        additionalProperties: false
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'list_edge_functions',
      description: '列出当前项目已知的 Supabase Edge Functions、状态和 JWT 校验配置。',
      parameters: { type: 'object', properties: {}, additionalProperties: false }
    }
  }
]

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function textValue(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function integerValue(value: unknown, fallback: number, min: number, max: number): number {
  const parsed = Number(value)
  if (!Number.isFinite(parsed)) return fallback
  return Math.min(max, Math.max(min, Math.trunc(parsed)))
}

function safeJsonParse(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value)
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : {}
  } catch {
    return {}
  }
}

function isToolName(value: string): value is ToolName {
  return toolNames.has(value as ToolName)
}

async function fetchWithTimeout(url: string, init: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs)
  try {
    return await fetch(url, { ...init, signal: controller.signal })
  } finally {
    clearTimeout(timeoutId)
  }
}

async function requestProvider(
  baseUrl: string,
  apiKey: string,
  messages: ProviderMessage[],
  allowTools: boolean,
  config: AiRuntimeConfig
): Promise<ProviderResult> {
  const models = [...new Set([config.model, config.fallbackModel].filter(Boolean))] as string[]
  let lastError = new Error('AI provider request failed')
  for (const model of models) {
    for (let attempt = 0; attempt <= config.maxRetries; attempt += 1) {
      const body: Record<string, unknown> = {
        model,
        temperature: config.temperature,
        max_tokens: config.maxTokens,
        stream: false,
        messages
      }
      if (allowTools) Object.assign(body, { tools, tool_choice: 'auto', parallel_tool_calls: false })
      try {
        const response = await fetchWithTimeout(`${baseUrl}/chat/completions`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(body)
        }, config.timeoutMs)
        if (!response.ok) {
          lastError = new Error(`AI provider request failed with HTTP ${response.status}`)
          if (response.status < 500 && response.status !== 429) break
          continue
        }
        const payload = await response.json()
        const message = payload?.choices?.[0]?.message as ProviderMessage | undefined
        if (!message) throw new Error('AI provider returned an empty response')
        return { message, usage: payload?.usage ?? {}, model }
      } catch (error) {
        lastError = error instanceof Error ? error : lastError
      }
    }
  }
  throw lastError
}

async function listEdgeFunctions(): Promise<Record<string, unknown>> {
  const accessToken = Deno.env.get('SUPABASE_ACCESS_TOKEN')
  if (!accessToken) {
    return {
      projectRef: PROJECT_REF,
      functions: edgeFunctionManifest,
      source: 'bundled_manifest',
      warning: '未配置 SUPABASE_ACCESS_TOKEN，当前展示随应用发布的函数清单；源码读取将在后续安全配置完成后开放。'
    }
  }
  try {
    const response = await fetchWithTimeout(
      `https://api.supabase.com/v1/projects/${PROJECT_REF}/functions`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
      15_000
    )
    if (!response.ok) throw new Error(`Management API HTTP ${response.status}`)
    const functions = await response.json()
    return { projectRef: PROJECT_REF, functions, source: 'management_api' }
  } catch (error) {
    return {
      projectRef: PROJECT_REF,
      functions: edgeFunctionManifest,
      source: 'bundled_manifest',
      warning: error instanceof Error ? error.message : 'Management API unavailable'
    }
  }
}

async function executeCatalog(
  action: CatalogAction,
  args: Record<string, unknown>,
  userClient: SupabaseClient
): Promise<unknown> {
  if (action === 'edge_functions') return await listEdgeFunctions()
  const { data, error } = await userClient.rpc('get_ai_project_catalog', {
    p_action: action,
    p_args: args
  })
  if (error) throw error
  return data
}

async function executeTool(
  name: ToolName,
  args: Record<string, unknown>,
  userClient: SupabaseClient
): Promise<unknown> {
  const actionMap: Record<ToolName, CatalogAction> = {
    get_project_overview: 'overview',
    list_database_objects: 'list_objects',
    get_database_object_detail: 'object_detail',
    get_table_relationships: 'relationships',
    list_edge_functions: 'edge_functions'
  }
  return await executeCatalog(actionMap[name], args, userClient)
}

async function writeToolAudit(
  admin: SupabaseClient,
  payload: {
    runId: string
    userId: string
    tenantId: string
    email: string
    name: ToolName
    args: Record<string, unknown>
    status: 'succeeded' | 'failed'
    latencyMs: number
    error?: string
  }
): Promise<void> {
  const { error } = await admin.from('ai_tool_call').insert({
    run_id: payload.runId,
    auth_user_id: payload.userId,
    tenant_id: payload.tenantId,
    tool_name: payload.name,
    arguments: payload.args,
    status: payload.status,
    result_summary: { safetyMode: 'read_only' },
    latency_ms: payload.latencyMs,
    error_message: payload.error ?? null,
    create_by: payload.email,
    update_by: payload.email
  })
  if (error) console.error('ai-project-assistant tool audit failed', error.message)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ code: 'method_not_allowed', message: 'Method not allowed' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authHeader) {
    return json({ code: 'unauthorized', message: 'Authentication required' }, 401)
  }

  const authClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  })
  const token = authHeader.replace(/^Bearer\s+/i, '')
  const { data: { user }, error: authError } = await authClient.auth.getUser(token)
  if (authError || !user) return json({ code: 'unauthorized', message: 'Invalid or expired session' }, 401)

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  })
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false }
  })
  const [{ data: isSuper, error: superError }, { data: appUserData, error: appUserError }] = await Promise.all([
    userClient.rpc('current_is_super'),
    admin.from('sys_user').select('tenant_id,user_email,status').eq('auth_user_id', user.id).maybeSingle()
  ])
  const appUser = appUserData as AppUser | null
  if (superError || isSuper !== true || appUserError || !appUser?.tenant_id || appUser.status === '0') {
    return json({ code: 'forbidden', message: '仅平台超级管理员可使用 Supabase 管理助手' }, 403)
  }

  let runId = ''
  const startedAt = Date.now()
  try {
    const body = await req.json() as AssistantRequest
    if (body.action === 'catalog') {
      const action = body.catalogAction
      if (!action || !catalogActions.has(action)) {
        return json({ code: 'invalid_action', message: '不支持的目录操作' }, 400)
      }
      const data = await executeCatalog(action, body.args ?? {}, userClient)
      return json({ data })
    }

    if (body.action === 'feedback') {
      if (!body.runId || (body.rating !== -1 && body.rating !== 1)) {
        return json({ code: 'invalid_feedback', message: 'Run ID and rating are required' }, 400)
      }
      const { data: ownedRun } = await admin.from('ai_run').select('id')
        .eq('id', body.runId).eq('auth_user_id', user.id).eq('feature', FEATURE).maybeSingle()
      if (!ownedRun) return json({ code: 'not_found', message: 'AI run was not found' }, 404)
      const { error } = await admin.from('ai_feedback').upsert({
        run_id: body.runId,
        auth_user_id: user.id,
        tenant_id: appUser.tenant_id,
        rating: body.rating,
        comment: textValue(body.comment).slice(0, 1000) || null,
        create_by: appUser.user_email,
        update_by: appUser.user_email
      }, { onConflict: 'run_id,auth_user_id' })
      if (error) throw error
      return json({ ok: true })
    }

    const messages = (body.messages ?? [])
      .filter((item): item is AssistantMessage => Boolean(item)
        && (item.role === 'user' || item.role === 'assistant')
        && Boolean(textValue(item.content)))
      .slice(-MAX_HISTORY_MESSAGES)
      .map((item) => ({ role: item.role, content: textValue(item.content).slice(0, MAX_MESSAGE_LENGTH) }))
    const latestUserMessage = [...messages].reverse().find((item) => item.role === 'user')
    if (!latestUserMessage) return json({ code: 'invalid_input', message: '请输入问题' }, 400)

    const apiKey = Deno.env.get('OPENAI_API_KEY') || Deno.env.get('AI_API_KEY')
    if (!apiKey) return json({ code: 'missing_secret', message: 'AI provider is not configured' }, 500)
    const baseUrl = (Deno.env.get('OPENAI_BASE_URL') || Deno.env.get('AI_BASE_URL') || 'https://api.openai.com/v1').replace(/\/$/, '')
    const sharedModel = Deno.env.get('OPENAI_MODEL') || Deno.env.get('AI_MODEL') || 'gpt-4.1-mini'
    const runtimeConfig = await loadAiRuntimeConfig(admin, appUser.tenant_id, FEATURE, {
      enabled: true,
      provider: 'openai_compatible',
      model: Deno.env.get('AI_PROJECT_ASSISTANT_MODEL') || sharedModel,
      visionModel: null,
      fallbackModel: Deno.env.get('AI_PROJECT_ASSISTANT_FALLBACK_MODEL') || null,
      timeoutMs: integerValue(Deno.env.get('AI_PROJECT_ASSISTANT_TIMEOUT_MS'), 30_000, 5_000, 120_000),
      maxRetries: integerValue(Deno.env.get('AI_PROJECT_ASSISTANT_MAX_RETRIES'), 0, 0, 2),
      temperature: 0.1,
      maxTokens: 1200,
      rateLimitPerMinute: 8,
      rateLimitPerDay: 100,
      promptVersion: 'v1'
    })
    if (!runtimeConfig.enabled) return json({ code: 'feature_disabled', message: 'Supabase 管理助手当前已停用' }, 503)
    const publishedPrompt = await loadPublishedAiPrompt(admin, appUser.tenant_id, FEATURE, {
      content: DEFAULT_PROMPT,
      version: runtimeConfig.promptVersion
    })

    const minuteAgo = new Date(Date.now() - 60_000).toISOString()
    const dayAgo = new Date(Date.now() - 86_400_000).toISOString()
    const [minuteResult, dayResult] = await Promise.all([
      admin.from('ai_run').select('id', { count: 'exact', head: true }).eq('auth_user_id', user.id).gte('started_at', minuteAgo),
      admin.from('ai_run').select('id', { count: 'exact', head: true }).eq('auth_user_id', user.id).gte('started_at', dayAgo)
    ])
    if ((minuteResult.count ?? 0) >= runtimeConfig.rateLimitPerMinute
      || (dayResult.count ?? 0) >= runtimeConfig.rateLimitPerDay) {
      return json({ code: 'rate_limited', message: 'AI 调用次数已达到限额，请稍后再试' }, 429)
    }

    const context: AssistantContext = body.context && typeof body.context === 'object' ? body.context : {}
    const conversationContext = { ...context, assistantMode: 'project', safetyMode: 'read_only' }
    let conversationId = textValue(body.conversationId)
    if (conversationId) {
      const { data: ownedConversation } = await admin.from('ai_conversation').select('id')
        .eq('id', conversationId).eq('auth_user_id', user.id).eq('tenant_id', appUser.tenant_id).maybeSingle()
      if (!ownedConversation) return json({ code: 'not_found', message: 'Conversation was not found' }, 404)
      await admin.from('ai_conversation').update({ context: conversationContext, update_by: appUser.user_email }).eq('id', conversationId)
    } else {
      const { data, error } = await admin.from('ai_conversation').insert({
        auth_user_id: user.id,
        tenant_id: appUser.tenant_id,
        title: latestUserMessage.content.replace(/\s+/g, ' ').slice(0, 40),
        context: conversationContext,
        create_by: appUser.user_email,
        update_by: appUser.user_email
      }).select('id').single()
      if (error) throw error
      conversationId = data.id
    }

    let resolvedModel = runtimeConfig.model
    const { data: run, error: runError } = await admin.from('ai_run').insert({
      conversation_id: conversationId,
      auth_user_id: user.id,
      tenant_id: appUser.tenant_id,
      feature: FEATURE,
      model: resolvedModel,
      prompt_version: publishedPrompt.version,
      metadata: { context: conversationContext, safetyMode: 'read_only', promptSource: publishedPrompt.source },
      create_by: appUser.user_email,
      update_by: appUser.user_email
    }).select('id').single()
    if (runError) throw runError
    runId = run.id

    const { error: userMessageError } = await admin.from('ai_message').insert({
      conversation_id: conversationId,
      auth_user_id: user.id,
      tenant_id: appUser.tenant_id,
      role: 'user',
      content: latestUserMessage.content,
      create_by: appUser.user_email,
      update_by: appUser.user_email
    })
    if (userMessageError) throw userMessageError

    const providerMessages: ProviderMessage[] = [
      { role: 'system', content: `${publishedPrompt.content}\n当前页面上下文：${JSON.stringify(conversationContext)}` },
      ...messages.map((item) => ({ role: item.role, content: item.content }))
    ]
    let inputTokens = 0
    let outputTokens = 0
    let response = await requestProvider(baseUrl, apiKey, providerMessages, true, runtimeConfig)
    resolvedModel = response.model
    inputTokens += response.usage.prompt_tokens ?? 0
    outputTokens += response.usage.completion_tokens ?? 0
    const executedTools: Array<{ name: string; status: string }> = []
    const requestedCalls = (response.message.tool_calls ?? []).slice(0, MAX_TOOL_CALLS)
    if (requestedCalls.length) {
      providerMessages.push(response.message)
      for (const call of requestedCalls) {
        const started = Date.now()
        const args = safeJsonParse(call.function.arguments)
        if (!isToolName(call.function.name)) {
          providerMessages.push({ role: 'tool', tool_call_id: call.id, content: JSON.stringify({ error: 'Unsupported tool' }) })
          continue
        }
        try {
          const result = await executeTool(call.function.name, args, userClient)
          executedTools.push({ name: call.function.name, status: 'succeeded' })
          await writeToolAudit(admin, {
            runId, userId: user.id, tenantId: appUser.tenant_id, email: appUser.user_email,
            name: call.function.name, args, status: 'succeeded', latencyMs: Date.now() - started
          })
          providerMessages.push({ role: 'tool', tool_call_id: call.id, content: JSON.stringify(result).slice(0, 24_000) })
        } catch (error) {
          const message = error instanceof Error ? error.message : 'Tool execution failed'
          executedTools.push({ name: call.function.name, status: 'failed' })
          await writeToolAudit(admin, {
            runId, userId: user.id, tenantId: appUser.tenant_id, email: appUser.user_email,
            name: call.function.name, args, status: 'failed', error: message, latencyMs: Date.now() - started
          })
          providerMessages.push({ role: 'tool', tool_call_id: call.id, content: JSON.stringify({ error: message }) })
        }
      }
      response = await requestProvider(baseUrl, apiKey, providerMessages, false, runtimeConfig)
      resolvedModel = response.model
      inputTokens += response.usage.prompt_tokens ?? 0
      outputTokens += response.usage.completion_tokens ?? 0
    }
    const content = textValue(response.message.content)
    if (!content) throw new Error('AI provider returned an empty message')
    const latencyMs = Date.now() - startedAt
    const { error: assistantMessageError } = await admin.from('ai_message').insert({
      conversation_id: conversationId,
      auth_user_id: user.id,
      tenant_id: appUser.tenant_id,
      role: 'assistant',
      content,
      usage: { inputTokens, outputTokens },
      create_by: appUser.user_email,
      update_by: appUser.user_email
    })
    if (assistantMessageError) throw assistantMessageError
    await admin.from('ai_run').update({
      status: 'succeeded',
      model: resolvedModel,
      input_tokens: inputTokens,
      output_tokens: outputTokens,
      latency_ms: latencyMs,
      tool_calls: executedTools,
      finished_at: new Date().toISOString(),
      update_by: appUser.user_email
    }).eq('id', runId)
    return json({
      conversationId,
      runId,
      message: content,
      tools: executedTools,
      usage: { inputTokens, outputTokens },
      safetyMode: 'read_only'
    })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    console.error('ai-project-assistant error', message)
    if (runId) {
      await admin.from('ai_run').update({
        status: 'failed',
        latency_ms: Date.now() - startedAt,
        error_code: error instanceof DOMException && error.name === 'AbortError' ? 'provider_timeout' : 'server_error',
        error_message: message.slice(0, 2000),
        finished_at: new Date().toISOString(),
        update_by: appUser.user_email
      }).eq('id', runId)
    }
    return json({ code: 'server_error', message }, 500)
  }
})
