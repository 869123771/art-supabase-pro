import { useSupabase } from '@/hooks'
import { applyFilters, FilterSpec } from '@utils/supabase-filters'
const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()
import { QueryResult } from '@supabase/supabase-js'

/*获取字典类型列表*/
export async function fetchGetDictTypeList(params: Api.DataCenter.DictListItem) {
  const { name } = params
  const specs = [{ col: 'name', op: 'ilike', val: name ? `%${name}%` : undefined }]

  // 构建查询
  let query: any = supabase
    .from('dict_type')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false }) // 按创建时间倒序

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })
  return await responseHandle(() => query as any, { ignoreCheck: true })
}

/*删除字典类型*/
export async function deleteDictType(params: Api.DataCenter.DictListItem) {
  const { id } = params
  return await responseHandle(() => supabase.from('dict_type').delete().eq('id', id) as any, {
    showMessage: true
  })
}

/*新增字典类型*/
export async function addDictType(params: Api.DataCenter.DictListItem) {
  return await responseHandle(
    () => supabase.from('dict_type').insert(keysToSnakeDeep(params)) as any,
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

/*编辑字典类型*/
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

/*获取字典列表通过类型Id*/
export async function fetchGetDictListByTypeId(params: Api.DataCenter.DictListItem) {
  const { typeId, label = '', code, i18nScope, status } = params
  const specs = [
    { col: 'typeId', op: 'eq', val: typeId },
    { col: 'label', op: 'ilike', val: `%${label}%` },
    { col: 'code', op: 'eq', val: code },
    { col: 'i18nScope', op: 'eq', val: i18nScope },
    { col: 'status', op: 'eq', val: status }
  ]

  // 构建查询
  let query: any = supabase
    .from('dict')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => query as any, { ignoreCheck: true })
}

/*获取字典列表*/
export async function fetchGetDictList() {
  // 构建查询
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
    // dict 表本身状态
    .eq('status', '1')
    // 关联 dict_type 表状态
    .eq('dict_type.status', '1')
    // 可选：排序
    .order('sort', { ascending: true })
  return await responseHandle(() => query as any, { ignoreCheck: true })
}

/*删除字典*/
export async function deleteDict(params: Api.DataCenter.DictListItem) {
  const { id } = params
  return await responseHandle(() => supabase.from('dict').delete().eq('id', id) as any, {
    showMessage: true
  })
}

/*删除字典批量*/
export async function deleteDictBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('dict').delete().in('id', ids) as any, {
    showMessage: true
  })
}

/*新增字典类型*/
export async function addDict(params: Api.DataCenter.DictListItem) {
  return await responseHandle(() => supabase.from('dict').insert(keysToSnakeDeep(params)) as any, {
    showMessage: true,
    breakReturn: true
  })
}

/*编辑字典类型*/
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

/*获取资源列表*/
export async function fetchGetResourceList(params: Api.DataCenter.Resources.ResourceSearchParams) {
  const { originName = '', suffix = '', from = 0, to = 9 } = params
  const specs: FilterSpec[] = [{ col: 'originName', op: 'ilike', val: `%${originName}%` }]

  // 处理 suffix：将逗号分隔的字符串转换为数组，并使用 in 操作符
  if (suffix) {
    const suffixArray = suffix
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0)

    if (suffixArray.length > 0) {
      specs.push({ col: 'suffix', op: 'in', val: suffixArray })
    }
  }
  // 构建查询
  let query: any = supabase
    .from('attachment')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: true })
  return await responseHandle(() => query as any, { ignoreCheck: true, showErrorMessage: true })
}

/*删除资源*/
export async function deleteResource(params: Api.DataCenter.Resources.ResourceListItem) {
  const { id } = params

  // 1) 获取要删除记录的 object_name
  const { data: resourceItem } = await responseHandle(
    () => supabase.from('attachment').select().eq('id', id).single() as any,
    {
      ignoreCheck: true
    }
  )
  const { storagePath, objectName } = resourceItem as Api.DataCenter.Resources.ResourceListItem
  const fullPath = `${storagePath}/${objectName}`
  // 2) 删除 DB 记录（原示例行为）

  await responseHandle(() => supabase.from('attachment').delete().eq('id', id).single() as any, {
    breakReturn: true
  })

  // 3) 如果 DB 删除成功，删除 Storage 对象（注意：remove 接受路径数组）
  return await responseHandle(
    () => supabase.storage.from('attachments').remove([fullPath]) as any,
    {
      showMessage: true
    }
  )
}

/*sql控制台*/
/**
 * 获取数据库元数据（Schema, Tables, Columns, Functions）
 * 注意：需要有访问 information_schema 的权限
 */
export async function fetchDatabaseMetadata(): Promise<Api.DataCenter.SqlConsole.DatabaseMetadata> {
  try {
    // 尝试使用 RPC 函数获取元数据
    const { data, error } = await responseHandle(
      () => supabase.rpc('get_database_metadata_all') as any,
      {
        showMessage: false,
        ignoreCheck: true
      }
    )

    if (error || !data) {
      // 如果 RPC 不存在，使用 information_schema 查询
      return await fetchMetadataFromInformationSchema()
    }

    // Supabase 返回的 data 可能直接是解析后的 JSON，
    // 也可能是 array/other shape, 所以要适配
    const payload = Array.isArray(data) && data.length > 0 ? data[0] : (data as any)

    const schemas: string[] = payload?.schemas ?? []

    const columns: Api.DataCenter.SqlConsole.ColumnMetadata[] = (payload?.columns ?? []).map(
      (c: any) => ({
        tableSchema: c.tableSchema,
        tableName: c.tableName,
        columnName: c.columnName,
        dataType: c.dataType,
        isNullable: c.isNullable,
        ordinalPosition: c.ordinalPosition
      })
    )

    const tablesMap = new Map<string, Api.DataCenter.SqlConsole.TableMetadata>()
    columns.forEach((col) => {
      const key = `${col.tableSchema}.${col.tableName}`
      if (!tablesMap.has(key)) {
        tablesMap.set(key, {
          schema: col.tableSchema,
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

    const functions = (payload?.functions ?? []).map((f: any) => ({
      routineSchema: f.routineSchema,
      routineName: f.routineName,
      returnType: f.returnType
    }))
    return {
      schemas,
      tables: Array.from(tablesMap.values()),
      functions
    }
  } catch (error) {
    console.error('Failed to fetch database metadata:', error)
    // 返回空数据
    return {
      schemas: ['public'],
      tables: [],
      functions: []
    }
  }
}

/**
 * 从 information_schema 获取元数据（备用方案）
 */
async function fetchMetadataFromInformationSchema(): Promise<Api.DataCenter.SqlConsole.DatabaseMetadata> {
  // 这里可以添加从 information_schema 查询的逻辑
  // 目前返回空数据，后续可以扩展
  return {
    schemas: ['public'],
    tables: [],
    functions: []
  }
}

/**
 * 执行 SQL 查询
 * @param params SQL 查询参数
 * @returns SQL 执行结果
 */
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
    showMessage: false
  })
}
