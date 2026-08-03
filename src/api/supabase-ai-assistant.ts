import { useSupabase } from '@/hooks'
import { normalizeFunctionError } from './ai-assistant'
import type {
  ProjectAssistantChatRequest,
  ProjectAssistantChatResponse,
  ProjectAssistantCapabilities,
  ProjectAssistantFeedbackRequest,
  ProjectAssistantHistoryDetailResponse,
  ProjectAssistantHistoryListResponse,
  ProjectCatalogRequest,
  ProjectObjectDescriptionUpdateRequest,
  ProjectObjectDescriptionUpdateResponse
} from '@/types/supabase-ai-assistant'

const { supabase, keysToCamelDeep } = useSupabase()

export async function fetchProjectAssistantCapabilities(): Promise<ProjectAssistantCapabilities> {
  const { data, error } = await supabase.functions.invoke<ProjectAssistantCapabilities>(
    'ai-project-assistant',
    { body: { action: 'capabilities' } }
  )
  if (error) throw await normalizeFunctionError(error)
  if (!data?.version || !data.features) throw new Error('助手能力信息返回了无效结果')
  return keysToCamelDeep<ProjectAssistantCapabilities>(data)
}

export async function chatWithProjectAssistant(
  params: ProjectAssistantChatRequest,
  options: { signal?: AbortSignal } = {}
): Promise<ProjectAssistantChatResponse> {
  const { data, error } = await supabase.functions.invoke<ProjectAssistantChatResponse>(
    'ai-project-assistant',
    { body: { ...params, action: 'chat' }, signal: options.signal }
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

export async function updateProjectObjectDescription(
  params: ProjectObjectDescriptionUpdateRequest
): Promise<ProjectObjectDescriptionUpdateResponse> {
  const { data, error } = await supabase.functions.invoke<ProjectObjectDescriptionUpdateResponse>(
    'ai-project-assistant',
    { body: { ...params, action: 'catalog_update_description' } }
  )
  if (error) throw await normalizeFunctionError(error)
  if (!data?.ok || !data.object) throw new Error('对象说明更新返回了无效结果')
  return keysToCamelDeep<ProjectObjectDescriptionUpdateResponse>(data)
}

export async function fetchProjectAssistantHistory(
  query = '',
  limit = 30
): Promise<ProjectAssistantHistoryListResponse> {
  const { data, error } = await supabase.functions.invoke<ProjectAssistantHistoryListResponse>(
    'ai-project-assistant',
    { body: { action: 'history_list', query, limit } }
  )
  if (error) throw await normalizeFunctionError(error)
  if (!data?.conversations) throw new Error('会话历史返回了无效结果')
  return keysToCamelDeep<ProjectAssistantHistoryListResponse>(data)
}

export async function fetchProjectAssistantConversation(
  conversationId: string
): Promise<ProjectAssistantHistoryDetailResponse> {
  const { data, error } = await supabase.functions.invoke<ProjectAssistantHistoryDetailResponse>(
    'ai-project-assistant',
    { body: { action: 'history_detail', conversationId } }
  )
  if (error) throw await normalizeFunctionError(error)
  if (!data?.conversation || !data.messages) throw new Error('会话详情返回了无效结果')
  return keysToCamelDeep<ProjectAssistantHistoryDetailResponse>(data)
}

export async function renameProjectAssistantConversation(
  conversationId: string,
  title: string
): Promise<void> {
  const { data, error } = await supabase.functions.invoke<{ conversation?: { id: string } }>(
    'ai-project-assistant',
    { body: { action: 'history_rename', conversationId, title } }
  )
  if (error) throw await normalizeFunctionError(error)
  if (!data?.conversation?.id) throw new Error('会话重命名返回了无效结果')
}
