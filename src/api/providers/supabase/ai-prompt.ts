import { buildOrIlikeFilter } from '@/utils/supabase/search'
import { useSupabase } from '@/hooks'
import { omit } from 'lodash-es'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

export type AiPromptStatus = 'draft' | 'published' | 'archived'

export interface AiPromptTemplate {
  id: string
  tenantId: string
  feature: string
  version: string
  name: string
  description?: string | null
  systemPrompt: string
  status: AiPromptStatus
  changeNote?: string | null
  publishedAt?: string | null
  publishedBy?: string | null
  metadata: Record<string, unknown>
  createBy?: string | null
  createTime: string
  updateBy?: string | null
  updateTime: string
}

export interface AiPromptSearchParams {
  current: number
  size: number
  tenantId: string
  feature?: string
  status?: AiPromptStatus | ''
  keyword?: string
}

export interface AiPromptWritePayload {
  id?: string
  feature: string
  version: string
  name: string
  description?: string | null
  systemPrompt: string
  changeNote?: string | null
  status: 'draft'
  metadata?: Record<string, unknown>
}

export async function fetchAiPromptList(params: AiPromptSearchParams) {
  const current = Math.max(params.current || 1, 1)
  const size = Math.min(Math.max(params.size || 20, 1), 100)
  const from = (current - 1) * size
  const to = from + size - 1

  let query = supabase
    .from('ai_prompt_template')
    .select('*', { count: 'exact' })
    .eq('tenant_id', params.tenantId)
    .order('feature', { ascending: true })
    .order('update_time', { ascending: false })
    .range(from, to)

  if (params.feature) query = query.eq('feature', params.feature)
  if (params.status) query = query.eq('status', params.status)
  if (params.keyword?.trim()) {
    const keyword = params.keyword.trim()
    query = query.or(buildOrIlikeFilter(['name', 'version', 'description'], keyword))
  }

  return await responseHandle<AiPromptTemplate[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function createAiPromptDraft(params: AiPromptWritePayload): Promise<void> {
  const writeData = omit(params, ['id'])
  await responseHandle(
    () => supabase.from('ai_prompt_template').insert(keysToSnakeDeep(writeData)),
    { breakReturn: true, showMessage: true }
  )
}

export async function updateAiPromptDraft(params: AiPromptWritePayload): Promise<void> {
  const { id, ...writeData } = params
  if (!id) throw new Error('Prompt 草稿 ID 不能为空')
  await responseHandle(
    () =>
      supabase
        .from('ai_prompt_template')
        .update(keysToSnakeDeep(writeData))
        .eq('id', id)
        .eq('status', 'draft'),
    { breakReturn: true, showMessage: true }
  )
}

export async function publishAiPrompt(id: string): Promise<AiPromptTemplate | null> {
  const { data } = await responseHandle<AiPromptTemplate>(
    () => supabase.rpc('publish_ai_prompt_template', { p_prompt_id: id }),
    { breakReturn: true, showErrorMessage: true }
  )
  return data ?? null
}

export async function deleteAiPromptDraft(id: string): Promise<void> {
  await responseHandle(
    () => supabase.from('ai_prompt_template').delete().eq('id', id).eq('status', 'draft'),
    { breakReturn: true, showMessage: true }
  )
}
