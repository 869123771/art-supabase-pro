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

/**
 * AI capabilities fail closed when tenant-level governance is unavailable.
 * Provider defaults remain available for administrators to seed a reviewed config later.
 */
export function disableAiRuntimeConfig(defaults: AiRuntimeConfig): AiRuntimeConfig {
  return { ...defaults, enabled: false }
}
