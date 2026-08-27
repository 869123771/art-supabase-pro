import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import type { QueryResult } from '@/types/api/response'
import { applyFilters, fetchAllRangePages, FilterSpec } from '@/utils/supabase'
import { invokeSupabaseFunctionWithSessionRecovery } from '@/utils/supabase/functions'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

type DataCenterQueryResult<T> = QueryResult<T>
type DictionaryWithType = Api.DataCenter.DictListItem & {
  dictTypeTable: { code: string; name: string }
}

const DICTIONARY_BATCH_SIZE = 500

interface MetadataPayload {
  schemas?: string[]
  columns?: MetadataColumnRow[]
  functions?: MetadataFunctionRow[]
}

interface MetadataColumnRow {
  tableSchema?: string
  tableName?: string
  columnName?: string
  dataType?: string
  isNullable?: string
  ordinalPosition?: number
}

interface MetadataFunctionRow {
  routineSchema?: string
  routineName?: string
  returnType?: string
}

interface ForeignKeyRow {
  sourceSchema?: string
  source_schema?: string
  sourceTable?: string
  source_table?: string
  sourceColumn?: string
  source_column?: string
  targetSchema?: string
  target_schema?: string
  targetTable?: string
  target_table?: string
  targetColumn?: string
  target_column?: string
  constraintName?: string
  constraint_name?: string
}

function normalizeMetadataPayload(data: unknown): MetadataPayload | null {
  const payload = Array.isArray(data) ? data[0] : data
  return payload && typeof payload === 'object' ? (payload as MetadataPayload) : null
}

// 字典目录与类型列表
export async function fetchGetDictTypeList(params: Partial<Api.DataCenter.DictTypeItem> = {}) {
  const { name } = params
  const specs = [{ col: 'name', op: 'ilike', val: name ? `%${name}%` : undefined }]

  let query = supabase
    .from('sys_dict_type')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })
    .order('name', { ascending: true })

  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })
  return await responseHandle(() => query, { ignoreCheck: true })
}

// 删除字典类型
export async function deleteDictType(params: Api.DataCenter.DictTypeItem) {
  const { id } = params
  return await responseHandle(
    () => supabase.from('sys_dict_type').delete({ count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

// 新增字典类型
export async function addDictType(params: Api.DataCenter.DictTypeItem) {
  return await responseHandle(
    () => supabase.from('sys_dict_type').insert(keysToSnakeDeep(params)),
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

// 编辑字典类型
export async function editDictType(params: Api.DataCenter.DictTypeItem) {
  const { id, ...payload } = params
  return await responseHandle(
    () =>
      supabase
        .from('sys_dict_type')
        .update(keysToSnakeDeep(payload), { count: 'exact' })
        .eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function saveDictTypeTreeOrder(
  updates: Array<{ id: string; parentId: string | null; sort: number }>
) {
  return await responseHandle(
    () =>
      supabase.rpc('save_dict_type_tree_order', {
        p_updates: updates
      }),
    {
      breakReturn: true,
      showMessage: false
    }
  )
}

// 根据类型 ID 查询字典项
export async function fetchGetDictListByTypeId(
  params: Partial<Api.DataCenter.DictListItem> &
    Api.Common.CommonSearchParams & { recordId?: string }
) {
  const { typeId, label = '', code, i18nScope, status, recordId } = params
  const specs = [
    { col: 'id', op: 'eq', val: recordId },
    { col: 'typeId', op: 'eq', val: typeId },
    { col: 'label', op: 'ilike', val: `%${label}%` },
    { col: 'code', op: 'eq', val: code },
    { col: 'i18nScope', op: 'eq', val: i18nScope },
    { col: 'status', op: 'eq', val: status }
  ]

  let query = supabase
    .from('sys_dictionary')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })
    .order('label', { ascending: true })

  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => query, { ignoreCheck: true })
}

export async function fetchDictTypeIdByDictionaryId(id: string): Promise<string | undefined> {
  const { data } = await responseHandle<{ typeId?: string } | null>(
    () => supabase.from('sys_dictionary').select('type_id').eq('id', id).maybeSingle(),
    { ignoreCheck: true }
  )
  return data?.typeId
}

// 字典项列表
export async function fetchGetDictList(): Promise<QueryResult<DictionaryWithType[]>> {
  return await fetchAllRangePages<DictionaryWithType>(
    ({ from, to }) => {
      const query = supabase
        .from('sys_dictionary')
        .select(
          `
          id,
          type_id,
          code,
          label,
          value,
          sort,
          color,
          tag_type,
          remark,
          parent_id,
          cascade_parent_id,
          dict_type_table:sys_dict_type!inner(
            code,
            name
          )
        `
        )
        .eq('status', '1')
        .eq('dict_type_table.status', '1')
        .order('sort', { ascending: true })
        .order('id', { ascending: true })
        .range(from, to)

      return responseHandle<DictionaryWithType[]>(() => query, { ignoreCheck: true })
    },
    { pageSize: DICTIONARY_BATCH_SIZE }
  )
}

// 删除字典项
export async function deleteDict(params: Api.DataCenter.DictListItem) {
  const { id } = params
  return await responseHandle(
    () => supabase.from('sys_dictionary').delete({ count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

// 批量删除字典项
export async function deleteDictBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('sys_dictionary').delete({ count: 'exact' }).in('id', ids),
    {
      showMessage: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

// 新增字典项
export async function addDict(params: Api.DataCenter.DictListItem) {
  return await responseHandle(
    () => supabase.from('sys_dictionary').insert(keysToSnakeDeep(params)),
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

// 编辑字典项
export async function editDict(params: Api.DataCenter.DictListItem) {
  const { id, ...payload } = params
  return await responseHandle(
    () =>
      supabase
        .from('sys_dictionary')
        .update(keysToSnakeDeep(payload), { count: 'exact' })
        .eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

// 资源列表
export async function fetchGetResourceList(params: Api.DataCenter.Resources.ResourceSearchParams) {
  const { originName = '', suffix = '', from = 0, to = 9 } = params
  const specs: FilterSpec[] = [{ col: 'originName', op: 'ilike', val: `%${originName}%` }]

  if (suffix) {
    const suffixArray = suffix
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0)

    if (suffixArray.length > 0) {
      specs.push({ col: 'suffix', op: 'in', val: suffixArray })
    }
  }

  let query = supabase
    .from('sys_attachment')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: true })
  return await responseHandle<Api.DataCenter.Resources.ResourceListItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

// 删除资源，同时清理 Storage 对象
export async function deleteResource(params: Api.DataCenter.Resources.ResourceListItem) {
  const { id } = params

  const { data: resourceItem } = await responseHandle(
    () => supabase.from('sys_attachment').select().eq('id', id).single(),
    {
      ignoreCheck: true
    }
  )

  const { storagePath, objectName } = resourceItem as Api.DataCenter.Resources.ResourceListItem
  const fullPath = `${storagePath}/${objectName}`

  await responseHandle(() => supabase.from('sys_attachment').delete().eq('id', id).single(), {
    breakReturn: true
  })

  return await responseHandle(() => supabase.storage.from('attachments').remove([fullPath]), {
    showMessage: true
  })
}

/**
 * 读取 SQL 工作台需要的元数据。
 * 当前除了 schema / table / column / function，也会补上外键信息，
 * 这样前端才能做 JOIN 自动推断。
 */
export async function fetchDatabaseMetadata(): Promise<Api.DataCenter.SqlConsole.DatabaseMetadata> {
  try {
    const [{ data, error }, foreignKeys] = await Promise.all([
      invokeSupabaseFunctionWithSessionRecovery('execute-sql-with-columns', {
        body: { action: 'metadata' }
      }),
      fetchForeignKeysMetadata()
    ])

    if (error || !data) {
      const fallback = await fetchMetadataFromInformationSchema()
      return { ...fallback, foreignKeys }
    }

    const payload = normalizeMetadataPayload(data)
    const schemas: string[] = payload?.schemas ?? []

    const columns: Api.DataCenter.SqlConsole.ColumnMetadata[] = (payload?.columns ?? []).map(
      (c) => ({
        tableSchema: c.tableSchema || '',
        tableName: c.tableName || '',
        columnName: c.columnName || '',
        dataType: c.dataType || '',
        isNullable: c.isNullable || 'YES',
        ordinalPosition: c.ordinalPosition || 0
      })
    )

    // 以后端 columns 为准重建 table 结构，保证表和列始终同步。
    const tablesMap = new Map<string, Api.DataCenter.SqlConsole.TableMetadata>()
    columns.forEach((col) => {
      const key = `${col.tableSchema}.${col.tableName}`
      if (!tablesMap.has(key)) {
        tablesMap.set(key, {
          tableSchema: col.tableSchema,
          tableName: col.tableName,
          columns: []
        })
      }
      tablesMap.get(key)!.columns.push({
        name: col.columnName,
        dataType: col.dataType,
        isNullable: col.isNullable === 'YES'
      })
    })
    const tables: Api.DataCenter.SqlConsole.TableMetadata[] = Array.from(tablesMap.values())

    const functions: Api.DataCenter.SqlConsole.FunctionMetadata[] = (payload?.functions ?? []).map(
      (f) => ({
        routineSchema: f.routineSchema || '',
        routineName: f.routineName || '',
        returnType: f.returnType || ''
      })
    )

    return {
      schemas,
      columns,
      tables,
      functions,
      foreignKeys
    }
  } catch (error) {
    console.error('Failed to fetch database metadata:', error)
    return {
      schemas: ['public'],
      columns: [],
      tables: [],
      functions: [],
      foreignKeys: []
    }
  }
}

// RPC 不可用时的兜底返回，至少不让前端提示链路崩掉。
async function fetchMetadataFromInformationSchema(): Promise<Api.DataCenter.SqlConsole.DatabaseMetadata> {
  return {
    schemas: ['public'],
    columns: [],
    tables: [],
    functions: [],
    foreignKeys: []
  }
}

// 额外查询外键关系，给 JOIN 自动推断和 AI schema 摘要使用。
async function fetchForeignKeysMetadata(): Promise<Api.DataCenter.SqlConsole.ForeignKeyMetadata[]> {
  const relationQuery = `
    SELECT
      tc.table_schema AS source_schema,
      tc.table_name AS source_table,
      kcu.column_name AS source_column,
      ccu.table_schema AS target_schema,
      ccu.table_name AS target_table,
      ccu.column_name AS target_column,
      tc.constraint_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name
      AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name
      AND ccu.constraint_schema = tc.constraint_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    ORDER BY tc.table_schema, tc.table_name, tc.constraint_name
  `

  const { data, error } = await executeSql({ query: relationQuery })
  const rows = data?.rows as ForeignKeyRow[] | undefined
  if (error || !rows) {
    return []
  }

  return rows.map((item) => ({
    sourceSchema: item.sourceSchema || item.source_schema || '',
    sourceTable: item.sourceTable || item.source_table || '',
    sourceColumn: item.sourceColumn || item.source_column || '',
    targetSchema: item.targetSchema || item.target_schema || '',
    targetTable: item.targetTable || item.target_table || '',
    targetColumn: item.targetColumn || item.target_column || '',
    constraintName: item.constraintName || item.constraint_name || ''
  }))
}

// SQL 执行入口，调用现有 Edge Function 并保留原始错误给编辑器做定位。
export async function executeSql(
  params: Api.DataCenter.SqlConsole.SqlExecuteRequest
): Promise<DataCenterQueryResult<Api.DataCenter.SqlConsole.SqlExecuteResponse>> {
  const invokeResp = () =>
    invokeSupabaseFunctionWithSessionRecovery<Api.DataCenter.SqlConsole.SqlExecuteResponse>(
      'execute-sql-with-columns',
      {
        body: params
      }
    )

  return await responseHandle(invokeResp, {
    convertToCamelShadow: true,
    returnRawError: true
  })
}

// AI SQL 入口单独保留，方便后面替换模型提供方而不动工作台页面。
export async function generateSqlByAi(
  params: Api.DataCenter.SqlConsole.SqlAiGenerateRequest
): Promise<QueryResult<Api.DataCenter.SqlConsole.SqlAiGenerateResponse>> {
  const invokeResp = () =>
    invokeSupabaseFunctionWithSessionRecovery<Api.DataCenter.SqlConsole.SqlAiGenerateResponse>(
      'ai-sql-assistant',
      { body: params }
    )

  return await responseHandle(invokeResp, {
    convertToCamelShadow: true,
    returnRawError: true
  })
}
