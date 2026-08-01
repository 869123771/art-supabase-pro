export type AiAssistantMessageRole = 'user' | 'assistant'

export interface AiAssistantMessage {
  role: AiAssistantMessageRole
  content: string
}

export interface AiAssistantPageContext {
  routeName?: string
  routePath?: string
  pageTitle?: string
  recordId?: string
  query?: Record<string, unknown>
}

export interface AiAssistantChatRequest {
  conversationId?: string
  messages: AiAssistantMessage[]
  context?: AiAssistantPageContext
}

export interface AiAssistantToolResult {
  name: string
  status: 'succeeded' | 'failed'
}

export interface AiAssistantChatResponse {
  conversationId: string
  runId: string
  message: string
  tools: AiAssistantToolResult[]
  usage?: {
    inputTokens?: number
    outputTokens?: number
  }
}

export interface AiAssistantFeedbackRequest {
  runId: string
  rating: -1 | 1
  comment?: string
}
