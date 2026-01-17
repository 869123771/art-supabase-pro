import { useSupabase } from '@/hooks'
import { applyFilters, FilterSpec } from '@utils/supabase-filters'
const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

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
