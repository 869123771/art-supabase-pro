import { useSupabase } from '@/hooks'
import { normalizeFunctionError } from './ai-assistant'
import type {
  ProjectAssistantChatRequest,
  ProjectAssistantChatResponse,
  ProjectAssistantFeedbackRequest,
  ProjectCatalogRequest
} from '@/types/supabase-ai-assistant'

const { supabase, keysToCamelDeep } = useSupabase()

export async function chatWithProjectAssistant(
  params: ProjectAssistantChatRequest
): Promise<ProjectAssistantChatResponse> {
  const { data, error } = await supabase.functions.invoke<ProjectAssistantChatResponse>(
    'ai-project-assistant',
    { body: { ...params, action: 'chat' } }
  )
  if (error) throw await normalizeFunctionError(error)
  if (!data?.message || !data.conversationId || !data.runId) {
    throw new Error('Supabase 管理助手返回了无效结果')
  }
  return data
}

export async function submitProjectAssistantFeedback(
  params: ProjectAssistantFeedbackRequest
): Promise<void> {
  const { error } = await supabase.functions.invoke('ai-project-assistant', {
    body: { ...params, action: 'feedback' }
  })
  if (error) throw await normalizeFunctionError(error)
}

export async function fetchProjectCatalog<T>(params: ProjectCatalogRequest): Promise<T> {
  const { data, error } = await supabase.functions.invoke<{ data: T }>('ai-project-assistant', {
    body: { ...params, action: 'catalog' }
  })
  if (error) throw await normalizeFunctionError(error)
  if (!data || !('data' in data)) throw new Error('项目目录返回了无效结果')
  return keysToCamelDeep<T>(data.data)
}
