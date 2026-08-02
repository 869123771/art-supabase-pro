import { useSupabase } from '@/hooks'
import type { SupabaseQueryLike } from '@/api/providers/supabase/query'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

export interface AiFeatureConfig {
  id: string
  tenantId: string
  feature: string
  enabled: boolean
  provider: string
  model: string
  visionModel?: string | null
  fallbackModel?: string | null
  timeoutMs: number
  maxRetries: number
  temperature: number
  maxTokens: number
  rateLimitPerMinute: number
  rateLimitPerDay: number
  promptVersion: string
  metadata: Record<string, unknown>
  createBy?: string | null
  createTime: string
  updateBy?: string | null
  updateTime: string
}

export interface AiFeatureConfigSearchParams {
  current: number
  size: number
  tenantId: string
  feature?: string
  enabled?: boolean | ''
  keyword?: string
}

export interface AiProviderProtocol {
  value: string
  label: string
  description: string
}

export interface AiProviderModel {
  id: string
  label: string
  ownedBy?: string | null
  kind: 'text' | 'vision' | 'unknown'
  description: string
}

export interface AiProviderCatalog {
  protocols: AiProviderProtocol[]
  models: AiProviderModel[]
  source: 'remote' | 'configured'
  cached: boolean
  fetchedAt: string
  warning?: string | null
}

export type AiFeatureConfigWritePayload = Pick<
  AiFeatureConfig,
  | 'id'
  | 'enabled'
  | 'provider'
  | 'model'
  | 'visionModel'
  | 'fallbackModel'
  | 'timeoutMs'
  | 'maxRetries'
  | 'temperature'
  | 'maxTokens'
  | 'rateLimitPerMinute'
  | 'rateLimitPerDay'
  | 'promptVersion'
>

let providerCatalogPromise: Promise<AiProviderCatalog> | null = null

async function normalizeFunctionError(error: unknown): Promise<Error> {
  if (error && typeof error === 'object' && 'context' in error) {
    const context = (error as { context?: unknown }).context
    if (context instanceof Response) {
      try {
        const payload = (await context.clone().json()) as { message?: unknown }
        if (typeof payload.message === 'string' && payload.message)
          return new Error(payload.message)
      } catch {
        // Fall back to the original function error.
      }
    }
  }
  if (error instanceof Error) return error
  return new Error('远端模型目录暂时不可用')
}

export async function fetchAiProviderCatalog(params?: {
  forceRefresh?: boolean
}): Promise<AiProviderCatalog> {
  if (!providerCatalogPromise || params?.forceRefresh) {
    providerCatalogPromise = (async () => {
      const { data, error } = await supabase.functions.invoke<AiProviderCatalog>(
        'ai-provider-catalog',
        { body: { forceRefresh: params?.forceRefresh === true } }
      )
      if (error) throw await normalizeFunctionError(error)
      if (!data || !Array.isArray(data.models)) throw new Error('远端模型目录返回格式无效')
      return data
    })()
    providerCatalogPromise.catch(() => {
      providerCatalogPromise = null
    })
  }
  return await providerCatalogPromise
}

export async function fetchAiFeatureConfigList(params: AiFeatureConfigSearchParams) {
  const current = Math.max(params.current || 1, 1)
  const size = Math.min(Math.max(params.size || 20, 1), 100)
  const from = (current - 1) * size
  const to = from + size - 1

  let query = supabase
    .from('ai_feature_config')
    .select('*', { count: 'exact' })
    .eq('tenant_id', params.tenantId)
    .order('feature', { ascending: true })
    .range(from, to)

  if (params.feature) query = query.eq('feature', params.feature)
  if (typeof params.enabled === 'boolean') query = query.eq('enabled', params.enabled)
  if (params.keyword?.trim()) {
    const keyword = params.keyword.trim().replace(/[,%()]/g, ' ')
    query = query.or(
      `model.ilike.%${keyword}%,vision_model.ilike.%${keyword}%,fallback_model.ilike.%${keyword}%`
    )
  }

  return await responseHandle<AiFeatureConfig[]>(() => query as unknown as SupabaseQueryLike, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function updateAiFeatureConfig(params: AiFeatureConfigWritePayload): Promise<void> {
  const { id, ...writeData } = params
  await responseHandle(
    () =>
      supabase
        .from('ai_feature_config')
        .update(keysToSnakeDeep(writeData))
        .eq('id', id) as unknown as SupabaseQueryLike,
    { breakReturn: true, showMessage: true }
  )
}
