import { normalizeFunctionError } from './ai-assistant'
import { useSupabase } from '@/hooks'
import { invokeSupabaseFunctionWithSessionRecovery } from '@/utils/supabase/functions'
import type {
  AiPlannerCapabilities,
  AiPlannerState,
  AiSuggestionStatus,
  GenerateAiSuggestionsRequest,
  RecordAiSuggestionEventRequest,
  RecordAiSuggestionEventResponse
} from '@/types/ai-project-planner'

const { keysToCamelDeep } = useSupabase()
const FUNCTION_NAME = 'ai-project-planner'

async function invokePlanner<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await invokeSupabaseFunctionWithSessionRecovery<T>(FUNCTION_NAME, {
    body
  })
  if (error) throw await normalizeFunctionError(error)
  if (!data) throw new Error('AI 项目规划台返回了无效结果')
  return keysToCamelDeep<T>(data)
}

export async function fetchAiPlannerCapabilities(): Promise<AiPlannerCapabilities> {
  return await invokePlanner<AiPlannerCapabilities>({ action: 'capabilities' })
}

export async function fetchAiPlannerState(
  status: AiSuggestionStatus | 'all' = 'all'
): Promise<AiPlannerState> {
  return await invokePlanner<AiPlannerState>({ action: 'list', status })
}

export async function generateAiSuggestions(
  params: GenerateAiSuggestionsRequest
): Promise<AiPlannerState> {
  return await invokePlanner<AiPlannerState>({ action: 'generate', ...params })
}

export async function recordAiSuggestionEvent(
  params: RecordAiSuggestionEventRequest
): Promise<RecordAiSuggestionEventResponse> {
  return await invokePlanner<RecordAiSuggestionEventResponse>({ action: 'event', ...params })
}
