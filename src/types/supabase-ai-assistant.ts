import type {
  AiAssistantChatRequest,
  AiAssistantChatResponse,
  AiAssistantFeedbackRequest
} from './ai-assistant'

export type ProjectCatalogAction =
  'overview' | 'schemas' | 'list_objects' | 'object_detail' | 'relationships' | 'edge_functions'

export type ProjectObjectType =
  'all' | 'table' | 'view' | 'materialized_view' | 'function' | 'trigger' | 'policy' | 'index'

export interface ProjectOverview {
  projectRef: string
  databaseVersion: string
  schemas: number
  tables: number
  views: number
  functions: number
  triggers: number
  policies: number
  indexes: number
}

export interface ProjectDatabaseObject {
  schemaName: string
  objectName: string
  objectType: Exclude<ProjectObjectType, 'all'>
  description?: string | null
}

export interface ProjectObjectColumn {
  name: string
  dataType: string
  nullable: boolean
  defaultValue?: string | null
  description?: string | null
}

export interface ProjectObjectDetail extends ProjectDatabaseObject {
  ddl?: string
  tableName?: string
  identityArguments?: string
  resultType?: string
  columns?: ProjectObjectColumn[]
  constraints?: Array<{ name: string; type: string; definition: string }>
  notFound?: boolean
  [key: string]: unknown
}

export interface ProjectRelationship {
  constraintName: string
  sourceSchema: string
  sourceTable: string
  sourceColumns: string[]
  targetSchema: string
  targetTable: string
  targetColumns: string[]
  definition: string
}

export interface ProjectEdgeFunction {
  id?: string
  slug: string
  name?: string
  status?: string
  version?: number
  verifyJwt?: boolean
  verify_jwt?: boolean
  updatedAt?: number
  updated_at?: number
  source?: string
}

export interface ProjectEdgeFunctionResult {
  projectRef: string
  functions: ProjectEdgeFunction[]
  source: 'management_api' | 'bundled_manifest'
  warning?: string
}

export interface ProjectCatalogRequest {
  catalogAction: ProjectCatalogAction
  args?: Record<string, unknown>
}

export type ProjectAssistantChatRequest = AiAssistantChatRequest
export type ProjectAssistantChatResponse = AiAssistantChatResponse
export type ProjectAssistantFeedbackRequest = AiAssistantFeedbackRequest
