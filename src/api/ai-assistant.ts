import { invokeSupabaseFunctionWithSessionRecovery } from '@/utils/supabase/functions'
import type {
  AiAssistantChatRequest,
  AiAssistantChatResponse,
  AiAssistantFeedbackRequest
} from '@/types/ai-assistant'

export async function chatWithAiAssistant(
  params: AiAssistantChatRequest
): Promise<AiAssistantChatResponse> {
  const { data, error } = await invokeSupabaseFunctionWithSessionRecovery<AiAssistantChatResponse>(
    'ai-assistant',
    { body: { ...params, action: 'chat' } }
  )
  if (error) throw await normalizeFunctionError(error)
  if (!data?.message || !data.conversationId || !data.runId) {
    throw new Error('AI 助手返回了无效结果')
  }
  return data
}

export async function submitAiAssistantFeedback(params: AiAssistantFeedbackRequest): Promise<void> {
  const { error } = await invokeSupabaseFunctionWithSessionRecovery('ai-assistant', {
    body: { ...params, action: 'feedback' }
  })
  if (error) throw await normalizeFunctionError(error)
}

export async function normalizeFunctionError(error: unknown): Promise<Error> {
  if (error && typeof error === 'object' && 'context' in error) {
    const context = (error as { context?: unknown }).context
    if (context instanceof Response) {
      try {
        const payload = (await context.clone().json()) as { message?: unknown }
        if (typeof payload.message === 'string' && payload.message) {
          return new Error(payload.message)
        }
      } catch {
        // Fall back to the original function error.
      }
    }
  }
  if (error instanceof Error) return error
  return new Error('AI 助手暂时不可用，请稍后重试')
}
