import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2'

export interface AiRuntimeConfig {
  enabled: boolean
  provider: string
  model: string
  visionModel: string | null
  fallbackModel: string | null
  timeoutMs: number
  maxRetries: number
  temperature: number
  maxTokens: number
  rateLimitPerMinute: number
  rateLimitPerDay: number
  promptVersion: string
}

interface AiFeatureConfigRow {
  enabled: boolean
  provider: string
  model: string
  vision_model: string | null
  fallback_model: string | null
  timeout_ms: number
  max_retries: number
  temperature: number | string
  max_tokens: number
  rate_limit_per_minute: number
  rate_limit_per_day: number
  prompt_version: string
}

function clampInteger(value: unknown, fallback: number, min: number, max: number): number {
  const parsed = Number(value)
  if (!Number.isFinite(parsed)) return fallback
  return Math.min(max, Math.max(min, Math.trunc(parsed)))
}

function clampNumber(value: unknown, fallback: number, min: number, max: number): number {
  const parsed = Number(value)
  if (!Number.isFinite(parsed)) return fallback
  return Math.min(max, Math.max(min, parsed))
}

function optionalText(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

export async function loadAiRuntimeConfig(
  admin: SupabaseClient,
  tenantId: string,
  feature: string,
  defaults: AiRuntimeConfig
): Promise<AiRuntimeConfig> {
  const { data, error } = await admin
    .from('ai_feature_config')
    .select(
      'enabled,provider,model,vision_model,fallback_model,timeout_ms,max_retries,temperature,max_tokens,rate_limit_per_minute,rate_limit_per_day,prompt_version'
    )
    .eq('tenant_id', tenantId)
    .eq('feature', feature)
    .maybeSingle()

  if (error) {
    console.warn('AI runtime config lookup failed; using environment defaults', feature, error.message)
    return defaults
  }

  const row = data as AiFeatureConfigRow | null
  if (!row) return defaults

  return {
    enabled: row.enabled,
    provider: optionalText(row.provider) ?? defaults.provider,
    model: optionalText(row.model) ?? defaults.model,
    visionModel: optionalText(row.vision_model),
    fallbackModel: optionalText(row.fallback_model),
    timeoutMs: clampInteger(row.timeout_ms, defaults.timeoutMs, 5000, 120000),
    maxRetries: clampInteger(row.max_retries, defaults.maxRetries, 0, 2),
    temperature: clampNumber(row.temperature, defaults.temperature, 0, 2),
    maxTokens: clampInteger(row.max_tokens, defaults.maxTokens, 100, 4096),
    rateLimitPerMinute: clampInteger(
      row.rate_limit_per_minute,
      defaults.rateLimitPerMinute,
      1,
      60
    ),
    rateLimitPerDay: clampInteger(row.rate_limit_per_day, defaults.rateLimitPerDay, 1, 5000),
    promptVersion: optionalText(row.prompt_version) ?? defaults.promptVersion
  }
}
