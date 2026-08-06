import assert from 'node:assert/strict'
import test from 'node:test'
import {
  disableAiRuntimeConfig,
  type AiRuntimeConfig
} from '../../supabase/functions/_shared/ai-runtime-config-policy'

const defaults: AiRuntimeConfig = {
  enabled: true,
  provider: 'openai_compatible',
  model: 'model-a',
  visionModel: 'vision-a',
  fallbackModel: null,
  timeoutMs: 60000,
  maxRetries: 0,
  temperature: 0,
  maxTokens: 1400,
  rateLimitPerMinute: 6,
  rateLimitPerDay: 100,
  promptVersion: 'v1'
}

test('missing AI governance disables the feature without mutating provider defaults', () => {
  const result = disableAiRuntimeConfig(defaults)

  assert.equal(result.enabled, false)
  assert.equal(result.model, defaults.model)
  assert.equal(result.visionModel, defaults.visionModel)
  assert.equal(defaults.enabled, true)
  assert.notEqual(result, defaults)
})
