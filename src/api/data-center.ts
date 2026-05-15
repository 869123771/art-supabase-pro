import { useSupabase } from '@/hooks'
import type { QueryResult } from '@/hooks/core/useSupabase'
import { applyFilters, FilterSpec } from '@utils/supabase-filters'

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

// 字典类型列表
export async function fetchGetDictTypeList(params: Api.DataCenter.DictListItem) {
  const { name } = params
  const specs = [{ col: 'name', op: 'ilike', val: name ? `%${name}%` : undefined }]

  let query: any = supabase
    .from('dict_type')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })

  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })
  return await responseHandle(() => query as any, { ignoreCheck: true })
}

// 删除字典类型
export async function deleteDictType(params: Api.DataCenter.DictListItem) {
  const { id } = params
  return await responseHandle(() => supabase.from('dict_type').delete().eq('id', id) as any, {
    showMessage: true
  })
}

// 新增字典类型
export async function addDictType(params: Api.DataCenter.DictListItem) {
  return await responseHandle(
    () => supabase.from('dict_type').insert(keysToSnakeDeep(params)) as any,
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

// 编辑字典类型
export async function editDictType(params: Api.DataCenter.DictListItem) {
  const { id } = params
  return await responseHandle(
    () => supabase.from('dict_type').update(keysToSnakeDeep(params)).eq('id', id) as any,
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

// 根据类型 ID 查询字典项
export async function fetchGetDictListByTypeId(params: Api.DataCenter.DictListItem) {
  const { typeId, label = '', code, i18nScope, status } = params
  const specs = [
    { col: 'typeId', op: 'eq', val: typeId },
    { col: 'label', op: 'ilike', val: `%${label}%` },
    { col: 'code', op: 'eq', val: code },
    { col: 'i18nScope', op: 'eq', val: i18nScope },
    { col: 'status', op: 'eq', val: status }
  ]

  let query: any = supabase
    .from('dict')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })

  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => query as any, { ignoreCheck: true })
}

// 字典项列表
export async function fetchGetDictList() {
  const query = supabase
    .from('dict')
    .select(
      `
      id,
      type_id,
      code,
      label,
      value,
      sort,
      color,
      dict_type_table:dict_type!inner(
        code,
        name
      )
    `
    )
    .eq('status', '1')
    .eq('dict_type.status', '1')
    .order('sort', { ascending: true })

  return await responseHandle(() => query as any, { ignoreCheck: true })
}

// 删除字典项
export async function deleteDict(params: Api.DataCenter.DictListItem) {
  const { id } = params
  return await responseHandle(() => supabase.from('dict').delete().eq('id', id) as any, {
    showMessage: true
  })
}

// 批量删除字典项
export async function deleteDictBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('dict').delete().in('id', ids) as any, {
    showMessage: true
  })
}

// 新增字典项
export async function addDict(params: Api.DataCenter.DictListItem) {
  return await responseHandle(() => supabase.from('dict').insert(keysToSnakeDeep(params)) as any, {
    showMessage: true,
    breakReturn: true
  })
}

// 编辑字典项
export async function editDict(params: Api.DataCenter.DictListItem) {
  const { id } = params
  return await responseHandle(
    () => supabase.from('dict').update(keysToSnakeDeep(params)).eq('id', id) as any,
    {
      showMessage: true,
      breakReturn: true
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

  let query: any = supabase
    .from('attachment')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => query as any, { ignoreCheck: true, showErrorMessage: true })
}

// 删除资源，同时清理 Storage 对象
export async function deleteResource(params: Api.DataCenter.Resources.ResourceListItem) {
  const { id } = params

  const { data: resourceItem } = await responseHandle(
    () => supabase.from('attachment').select().eq('id', id).single() as any,
    {
      ignoreCheck: true
    }
  )

  const { storagePath, objectName } = resourceItem as Api.DataCenter.Resources.ResourceListItem
  const fullPath = `${storagePath}/${objectName}`

  await responseHandle(() => supabase.from('attachment').delete().eq('id', id).single() as any, {
    breakReturn: true
  })

  return await responseHandle(
    () => supabase.storage.from('attachments').remove([fullPath]) as any,
    {
      showMessage: true
    }
  )
}

/**
 * 读取 SQL 工作台需要的元数据。
 * 当前除了 schema / table / column / function，也会补上外键信息，
 * 这样前端才能做 JOIN 自动推断。
 */
export async function fetchDatabaseMetadata(): Promise<Api.DataCenter.SqlConsole.DatabaseMetadata> {
  try {
    const { data, error } = await responseHandle(
      () => supabase.rpc('get_database_metadata_all') as any,
      {
        showMessage: false,
        ignoreCheck: true
      }
    )

    if (error || !data) {
      return await fetchMetadataFromInformationSchema()
    }

    const payload = Array.isArray(data) && data.length > 0 ? data[0] : (data as any)
    const schemas: string[] = payload?.schemas ?? []

    const columns: Api.DataCenter.SqlConsole.ColumnMetadata[] = (payload?.columns ?? []).map(
      (c: any) => ({
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
      (f: any) => ({
        routineSchema: f.routineSchema || '',
        routineName: f.routineName || '',
        returnType: f.returnType || ''
      })
    )

    const foreignKeys = await fetchForeignKeysMetadata()

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

  const { data, error } = (await executeSql({ query: relationQuery })) as any
  if (error || !data?.rows) {
    return []
  }

  return (data.rows || []).map((item: any) => ({
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
): Promise<QueryResult<any>> {
  const invokeResp = () =>
    supabase.functions.invoke<Api.DataCenter.SqlConsole.SqlExecuteResponse>(
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
  const { data, error } =
    await supabase.functions.invoke<Api.DataCenter.SqlConsole.SqlAiGenerateResponse>(
      'ai-sql-assistant',
      {
        body: params
      }
    )

  return {
    data: data ?? null,
    error
  }
}
