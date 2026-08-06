import 'jsr:@supabase/functions-js/edge-runtime.d.ts'
import { createClient } from 'jsr:@supabase/supabase-js@2'
import { getAiConfigTenantScope } from '../_shared/ai-config-tenancy.ts'

interface CatalogRequest {
  forceRefresh?: boolean
}

interface AppUser {
  tenant_id: string
  status: string | null
}

interface ConfiguredModelRow {
  model: string | null
  vision_model: string | null
  fallback_model: string | null
}

interface ProviderModel {
  id: string
  label: string
  ownedBy: string | null
  kind: 'text' | 'vision' | 'unknown'
  description: string
}

interface RemoteCatalogCache {
  expiresAt: number
  fetchedAt: string
  models: ProviderModel[]
}

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS'
}

const CATALOG_CACHE_TTL_MS = 5 * 60_000
const CATALOG_TIMEOUT_MS = 10_000
let remoteCatalogCache: RemoteCatalogCache | null = null

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
}

function stringValue(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const normalized = value.trim()
  return normalized || null
}

const ownerLabels: Record<string, string> = {
  '01-ai': '零一万物',
  adept: 'Adept',
  ai21labs: 'AI21 Labs',
  aisingapore: 'AI Singapore',
  baai: '智源研究院',
  bigcode: 'BigCode',
  databricks: 'Databricks',
  'deepseek-ai': 'DeepSeek',
  google: 'Google',
  ibm: 'IBM',
  meta: 'Meta',
  microsoft: 'Microsoft',
  minimaxai: 'MiniMax',
  mistralai: 'Mistral AI',
  moonshotai: '月之暗面',
  nvidia: 'NVIDIA',
  'nv-mistralai': 'NVIDIA / Mistral AI',
  openai: 'OpenAI',
  poolside: 'Poolside',
  snowflake: 'Snowflake',
  'stepfun-ai': '阶跃星辰',
  thinkingmachines: 'Thinking Machines',
  writer: 'Writer',
  'z-ai': '智谱 AI',
  zyphra: 'Zyphra'
}

function resolveOwnerLabel(id: string, ownedBy: string | null): string {
  const prefix = id.split('/')[0]?.toLowerCase() ?? ''
  if (ownerLabels[prefix]) return ownerLabels[prefix]
  const normalizedOwner = ownedBy?.trim()
  if (normalizedOwner && !/^(system|unknown)$/i.test(normalizedOwner)) return normalizedOwner
  return prefix || '远端服务'
}

function resolveModelCapability(id: string): {
  kind: ProviderModel['kind']
  label: string
} {
  if (/(embed|embedding|bge|retriever|e5)/i.test(id)) {
    return { kind: 'unknown', label: '向量嵌入' }
  }
  if (/rerank/i.test(id)) return { kind: 'unknown', label: '文本重排' }
  if (/(guard|safety|moderation)/i.test(id)) return { kind: 'unknown', label: '内容安全' }
  if (/(speech|audio|whisper|tts)/i.test(id)) return { kind: 'unknown', label: '语音音频' }
  if (/(translate)/i.test(id)) return { kind: 'text', label: '机器翻译' }
  if (/(parse|deplot)/i.test(id)) return { kind: 'vision', label: '文档解析' }
  if (/(reward)/i.test(id)) return { kind: 'unknown', label: '奖励模型' }
  if (/(detector|detect)/i.test(id)) return { kind: 'unknown', label: '内容检测' }
  if (/(code|coder|starcoder|codestral)/i.test(id)) return { kind: 'text', label: '代码生成' }
  if (/(^|[-_.\/])(vision|vl|vlm|image|omni)([-_.\/]|$)|fuyu|kosmos|neva|vila/i.test(id)) {
    return { kind: 'vision', label: '视觉理解' }
  }
  return { kind: 'text', label: '文本生成' }
}

function createProviderModel(id: string, ownedBy: string | null): ProviderModel {
  const capability = resolveModelCapability(id)
  const description = `${resolveOwnerLabel(id, ownedBy)} · ${capability.label}`
  return {
    id,
    label: `${id}  ·  ${description}`,
    ownedBy,
    kind: capability.kind,
    description
  }
}

function normalizeRemoteModels(payload: unknown): ProviderModel[] {
  if (!payload || typeof payload !== 'object') return []
  const record = payload as Record<string, unknown>
  const source = Array.isArray(record.data)
    ? record.data
    : Array.isArray(record.models)
      ? record.models
      : []
  const modelMap = new Map<string, ProviderModel>()

  for (const item of source) {
    const row = item && typeof item === 'object' ? (item as Record<string, unknown>) : {}
    const id = stringValue(row.id) ?? stringValue(row.name) ?? stringValue(row.model)
    if (!id) continue
    const ownedBy =
      stringValue(row.owned_by) ?? stringValue(row.ownedBy) ?? stringValue(row.provider)
    modelMap.set(id, createProviderModel(id, ownedBy))
  }

  return [...modelMap.values()].sort((left, right) => left.id.localeCompare(right.id, 'en'))
}

function mergeConfiguredModels(
  remoteModels: ProviderModel[],
  configuredRows: ConfiguredModelRow[],
  environmentModels: Array<string | null>
): ProviderModel[] {
  const modelMap = new Map(remoteModels.map((item) => [item.id, item]))
  const configuredModels = [
    ...environmentModels,
    ...configuredRows.flatMap((row) => [row.model, row.vision_model, row.fallback_model])
  ]

  for (const value of configuredModels) {
    const id = stringValue(value)
    if (!id || modelMap.has(id)) continue
    modelMap.set(id, createProviderModel(id, null))
  }

  return [...modelMap.values()].sort((left, right) => left.id.localeCompare(right.id, 'en'))
}

async function fetchRemoteCatalog(
  baseUrl: string,
  apiKey: string,
  forceRefresh: boolean
): Promise<{ fetchedAt: string; models: ProviderModel[]; cached: boolean }> {
  if (!forceRefresh && remoteCatalogCache && remoteCatalogCache.expiresAt > Date.now()) {
    return {
      fetchedAt: remoteCatalogCache.fetchedAt,
      models: remoteCatalogCache.models,
      cached: true
    }
  }

  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), CATALOG_TIMEOUT_MS)
  try {
    const response = await fetch(`${baseUrl}/models`, {
      headers: { Authorization: `Bearer ${apiKey}`, Accept: 'application/json' },
      signal: controller.signal
    })
    if (!response.ok) throw new Error(`Model catalog request failed with HTTP ${response.status}`)

    const models = normalizeRemoteModels(await response.json())
    if (!models.length) throw new Error('Model catalog returned no models')
    const fetchedAt = new Date().toISOString()
    remoteCatalogCache = {
      models,
      fetchedAt,
      expiresAt: Date.now() + CATALOG_CACHE_TTL_MS
    }
    return { fetchedAt, models, cached: false }
  } finally {
    clearTimeout(timeoutId)
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ code: 'method_not_allowed', message: 'Method not allowed' }, 405)

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  const authHeader = req.headers.get('Authorization') ?? ''
  if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey || !authHeader) {
    return json({ code: 'unauthorized', message: 'Authentication required' }, 401)
  }

  const token = authHeader.replace(/^Bearer\s+/i, '')
  const authClient = createClient(supabaseUrl, supabaseAnonKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  })
  const {
    data: { user },
    error: authError
  } = await authClient.auth.getUser(token)
  if (authError || !user) {
    return json({ code: 'unauthorized', message: 'Invalid or expired session' }, 401)
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  })
  const { data: appUserData, error: appUserError } = await admin
    .from('sys_user')
    .select('tenant_id,status')
    .eq('auth_user_id', user.id)
    .maybeSingle()
  const appUser = appUserData as AppUser | null
  if (appUserError || !appUser?.tenant_id || appUser.status === '0') {
    return json({ code: 'forbidden', message: 'Active application user is required' }, 403)
  }

  const apiKey = Deno.env.get('OPENAI_API_KEY') || Deno.env.get('AI_API_KEY')
  const baseUrl = (
    Deno.env.get('OPENAI_BASE_URL') ||
    Deno.env.get('AI_BASE_URL') ||
    'https://api.openai.com/v1'
  ).replace(/\/$/, '')
  const sharedModel = Deno.env.get('OPENAI_MODEL') || Deno.env.get('AI_MODEL')
  const body = (await req.json().catch(() => ({}))) as CatalogRequest

  const configTenantScope = await getAiConfigTenantScope(admin, appUser.tenant_id)
  const { data: configuredData } = await admin
    .from('ai_feature_config')
    .select('model,vision_model,fallback_model')
    .in('tenant_id', configTenantScope)
  const configuredRows = (configuredData ?? []) as ConfiguredModelRow[]
  const environmentModels = [
    sharedModel,
    Deno.env.get('AI_ASSISTANT_MODEL'),
    Deno.env.get('AI_ASSISTANT_FAST_MODEL'),
    Deno.env.get('AI_ASSISTANT_FALLBACK_MODEL'),
    Deno.env.get('AI_ORDER_MODEL'),
    Deno.env.get('AI_ORDER_VISION_MODEL'),
    Deno.env.get('AI_ORDER_FALLBACK_MODEL')
  ]

  let remoteModels: ProviderModel[] = []
  let source: 'remote' | 'configured' = 'configured'
  let cached = false
  let fetchedAt = new Date().toISOString()
  let warning: string | null = null

  if (apiKey) {
    try {
      const remote = await fetchRemoteCatalog(baseUrl, apiKey, body.forceRefresh === true)
      remoteModels = remote.models
      fetchedAt = remote.fetchedAt
      cached = remote.cached
      source = 'remote'
    } catch (error) {
      console.error(
        'ai-provider-catalog remote fetch failed',
        error instanceof Error ? error.message : error
      )
      warning = '远端服务暂时无法返回模型目录，当前展示已配置模型，可手动输入其他模型 ID。'
    }
  } else {
    warning = 'AI 服务密钥尚未配置，当前展示已配置模型，可手动输入其他模型 ID。'
  }

  const models = mergeConfiguredModels(remoteModels, configuredRows, environmentModels)
  return json({
    protocols: [
      {
        value: 'openai_compatible',
        label: 'OpenAI 兼容协议',
        description: '兼容 /models 与 /chat/completions 接口的服务'
      }
    ],
    models,
    source,
    cached,
    fetchedAt,
    warning
  })
})
