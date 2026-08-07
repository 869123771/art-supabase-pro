import { AppRouteRecord } from '@/types/router'
import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import { buildSpecsFromMap, applyFilters, type Op } from '@utils/supabase-filters'
import { toNextDayStartUTC, toStartOfDayUTC } from '@/utils'
import { omit } from 'lodash-es'
const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

type TenantListItem = Api.SystemManage.TenantListItem
type TenantSearchParams = Api.SystemManage.TenantSearchParams
type SystemParamItem = Api.SystemManage.SystemParamItem
type SystemParamSearchParams = Api.SystemManage.SystemParamSearchParams
type WebsiteConfigItem = Api.SystemManage.WebsiteConfigItem
type WebsiteConfigParamMeta = Api.SystemManage.WebsiteConfigParamMeta
const WEBSITE_CONFIG_PARAM_KEY = 'website.config'

interface DeleteUserSyncPayload {
  action: 'delete'
  id: string
  auth_user_id?: string
}

// 获取用户列表
export async function fetchGetUserList(params: Api.SystemManage.UserSearchParams) {
  const { userName, userPhone, userGender, userEmail, status, from = 0, to = 9 } = params
  // 用户名和邮箱使用不区分大小写的包含匹配，其它字段保持精确匹配。
  // opsMap 使用 snake_case keys（buildSpecsFromMap 会内部 convertKeysToSnake，所以可以用 camelCase）
  const opsMap = {
    userName: 'ilike', // will be mapped to user_name internally
    userEmail: 'ilike'
    // userPhone 默认 eq
  } as Record<string, Op>

  // buildSpecsFromMap 会把 keys 转为 snake_case，并返回 FilterSpec[]
  // 它默认 op 为 'eq'，但会把 opsMap 中指定的替换为对应 op
  const specs = buildSpecsFromMap(
    {
      userName: userName ? `%${userName}%` : undefined, // 包裹 % 以用于 ilike
      userPhone,
      userEmail: userEmail?.trim() ? `%${userEmail.trim()}%` : undefined,
      userGender,
      status
    },
    opsMap
  )
  /* const specs = [
        { col: 'user_name', op: 'ilike', val: userName ? `%${userName}%` : undefined },
        { col: 'user_phone', op: 'eq', val: userPhone },
        { col: 'user_email', op: 'eq', val: userEmail }
      ]*/

  // 构建查询
  let query = supabase
    .from('sys_user')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false }) // 按创建时间倒序
    .range(from, to)

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })

  return await responseHandle(() => query, { ignoreCheck: true })
}

// 获取租户列表
export async function fetchGetTenantList(params: TenantSearchParams) {
  const { tenantCode, tenantName, status, from = 0, to = 9 } = params
  const specs = [
    { col: 'tenant_code', op: 'ilike', val: tenantCode ? `%${tenantCode}%` : undefined },
    { col: 'tenant_name', op: 'ilike', val: tenantName ? `%${tenantName}%` : undefined },
    { col: 'status', op: 'eq', val: status }
  ]

  let query = supabase
    .from('sys_tenant')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false })
    .range(from, to)

  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })
  return await responseHandle<TenantListItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

// 获取可用租户列表
export async function fetchGetEnableTenantList() {
  const query = supabase
    .from('sys_tenant')
    .select('id, tenant_code, tenant_name, status')
    .eq('status', '1')
    .order('tenant_code', { ascending: true })

  return await responseHandle<TenantListItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

// 新增租户
export async function addTenant(params: TenantListItem) {
  return await responseHandle(() => supabase.from('sys_tenant').insert(keysToSnakeDeep(params)), {
    showMessage: true,
    breakReturn: true
  })
}

// 编辑租户
export async function editTenant(params: TenantListItem) {
  const { id, ...data } = params
  return await responseHandle(
    () => supabase.from('sys_tenant').update(keysToSnakeDeep(data)).eq('id', id),
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

// 删除租户
export async function deleteTenant(id: string) {
  return await responseHandle(() => supabase.from('sys_tenant').delete().eq('id', id), {
    showMessage: true
  })
}

// 批量删除租户
export async function deleteTenantBatch(ids: string[]) {
  return await responseHandle(() => supabase.from('sys_tenant').delete().in('id', ids), {
    showMessage: true
  })
}

export async function fetchGetSystemParamList(params: SystemParamSearchParams) {
  const { keyword = '', groupCode, paramType, enabled, builtin, from = 0, to = 9 } = params
  const specs = [
    { col: 'group_code', op: 'eq', val: groupCode },
    { col: 'param_type', op: 'eq', val: paramType },
    { col: 'enabled', op: 'eq', val: enabled },
    { col: 'builtin', op: 'eq', val: builtin }
  ]

  let query = supabase
    .from('sys_param')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true })
    .order('create_time', { ascending: false })
    .range(from, to)

  const trimmedKeyword = keyword.trim()
  if (trimmedKeyword) {
    query = query.or(
      `param_name.ilike.%${trimmedKeyword}%,param_key.ilike.%${trimmedKeyword}%,remark.ilike.%${trimmedKeyword}%`
    )
  }

  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })
  return await responseHandle(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchSystemParamStats(): Promise<{
  data: Api.SystemManage.SystemParamStats
  error: unknown | null
}> {
  const query = supabase.from('sys_param').select('id, enabled, builtin, group_code, update_time')
  const { data, error } = await responseHandle<SystemParamItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })

  const rows = data ?? []
  const latestUpdateTime = rows
    .map((row) => row.updateTime || '')
    .filter(Boolean)
    .sort()
    .at(-1)
  const groupCounts = rows.reduce<Record<string, number>>((counts, row) => {
    if (row.groupCode) {
      counts[row.groupCode] = (counts[row.groupCode] ?? 0) + 1
    }
    return counts
  }, {})

  return {
    data: {
      total: rows.length,
      enabled: rows.filter((row) => row.enabled).length,
      builtin: rows.filter((row) => row.builtin).length,
      groups: Object.keys(groupCounts).length,
      groupCounts,
      lastRefreshTime: latestUpdateTime
    },
    error
  }
}

export async function fetchSystemParamByKey(paramKey: string): Promise<{
  data: SystemParamItem | null
  error: unknown | null
}> {
  return await responseHandle<SystemParamItem | null>(
    () =>
      supabase
        .from('sys_param')
        .select('*')
        .eq('param_key', paramKey)
        .eq('enabled', true)
        .maybeSingle(),
    {
      ignoreCheck: true,
      showErrorMessage: false
    }
  )
}

export async function addSystemParam(params: SystemParamItem) {
  return await responseHandle(() => supabase.from('sys_param').insert(keysToSnakeDeep(params)), {
    showMessage: true,
    breakReturn: true
  })
}

export async function editSystemParam(params: SystemParamItem) {
  const { id, ...payload } = params
  return await responseHandle(
    () =>
      supabase.from('sys_param').update(keysToSnakeDeep(payload), { count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function deleteSystemParam(id: string) {
  return await responseHandle(
    () => supabase.from('sys_param').delete({ count: 'exact' }).eq('id', id).eq('builtin', false),
    {
      showMessage: true,
      requireAffected: true,
      noAffectedMessage: '内置参数不允许删除，或当前账号没有删除权限'
    }
  )
}

export async function deleteSystemParamBatch(ids: string[]) {
  return await responseHandle(
    () => supabase.from('sys_param').delete({ count: 'exact' }).in('id', ids).eq('builtin', false),
    {
      showMessage: true,
      requireAffected: true,
      noAffectedMessage: '未删除任何数据，请确认未选择内置参数且当前账号有删除权限'
    }
  )
}

/*重置密码*/
const getWebsiteConfigParamMeta = (row: SystemParamItem): WebsiteConfigParamMeta => ({
  paramName: row.paramName,
  paramKey: row.paramKey,
  groupCode: row.groupCode,
  groupName: row.groupName,
  paramType: row.paramType,
  defaultValue: row.defaultValue ?? null,
  extendConfig: row.extendConfig ?? {},
  enabled: row.enabled,
  builtin: row.builtin,
  sort: row.sort,
  remark: row.remark ?? null
})

const parseWebsiteConfigParam = (row: SystemParamItem | null): WebsiteConfigItem | null => {
  if (!row?.paramValue) return null

  try {
    const parsed = JSON.parse(row.paramValue) as WebsiteConfigItem
    return {
      ...parsed,
      id: row.id,
      tenantId: row.tenantId,
      paramMeta: getWebsiteConfigParamMeta(row),
      createBy: row.createBy,
      createTime: row.createTime,
      updateBy: row.updateBy,
      updateTime: row.updateTime
    }
  } catch {
    return null
  }
}

export async function fetchWebsiteConfig(): Promise<{
  data: WebsiteConfigItem | null
  error: unknown | null
}> {
  const { data, error } = await responseHandle<SystemParamItem | null>(
    () =>
      supabase
        .from('sys_param')
        .select('*')
        .eq('param_key', WEBSITE_CONFIG_PARAM_KEY)
        .eq('enabled', true)
        .maybeSingle(),
    {
      ignoreCheck: true,
      showErrorMessage: false
    }
  )

  return {
    data: parseWebsiteConfigParam(data),
    error
  }
}

export async function saveWebsiteConfig(params: WebsiteConfigItem) {
  const { id, paramMeta } = params
  const payload = omit(params, [
    'id',
    'tenantId',
    'paramMeta',
    'createBy',
    'createTime',
    'updateBy',
    'updateTime'
  ])

  const paramValue = JSON.stringify(payload)

  if (!id) {
    const existing = await responseHandle<SystemParamItem | null>(
      () =>
        supabase
          .from('sys_param')
          .select('*')
          .eq('param_key', WEBSITE_CONFIG_PARAM_KEY)
          .maybeSingle(),
      {
        ignoreCheck: true,
        showErrorMessage: false
      }
    )
    if (existing.data?.id) {
      const existingId = existing.data.id
      const updatePayload = {
        ...omit(paramMeta ?? getWebsiteConfigParamMeta(existing.data), ['paramKey']),
        paramValue
      }
      return await responseHandle(
        () =>
          supabase
            .from('sys_param')
            .update(keysToSnakeDeep(updatePayload), { count: 'exact' })
            .eq('id', existingId),
        {
          showMessage: true,
          breakReturn: true,
          requireAffected: true,
          noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
        }
      )
    }

    if (!paramMeta) {
      throw new Error('未找到网站配置参数记录，无法保存网站配置')
    }

    return await responseHandle(
      () => supabase.from('sys_param').insert(keysToSnakeDeep({ ...paramMeta, paramValue })),
      {
        showMessage: true,
        breakReturn: true
      }
    )
  }

  return await responseHandle(
    () =>
      supabase
        .from('sys_param')
        .update(
          keysToSnakeDeep({
            ...(paramMeta ? omit(paramMeta, ['paramKey']) : {}),
            paramValue
          }),
          { count: 'exact' }
        )
        .eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

export async function resetUser(params: Api.SystemManage.UserListItem) {
  const { userEmail, password } = params
  const invokeResp = () =>
    supabase.functions.invoke('admin_reset_password', {
      body: {
        email: userEmail,
        password
      }
    })
  await responseHandle(invokeResp, {
    showMessage: true,
    message: '密码初始化成功，重新登录后生效'
  })
}

/*删除用户*/
export async function deleteUser(params: Api.SystemManage.UserListItem) {
  const { id, authUserId } = params
  if (!id) {
    throw new Error('未找到需要删除的用户')
  }
  //删除auth.usres 表对应记录
  const payload: DeleteUserSyncPayload = { action: 'delete', id: id }
  if (authUserId) {
    payload.auth_user_id = authUserId
  }
  const invokeResp = () =>
    supabase.functions.invoke('sync-user', {
      body: payload
    })
  await responseHandle(invokeResp, {
    showMessage: true,
    breakReturn: true
  })
}

/*新增用户*/
export async function addUser(params: Api.SystemManage.UserListItem) {
  const { userEmail, password } = params
  const payload = {
    action: 'create',
    email: userEmail,
    password,
    appUserData: params
  }
  const invokeResp = () =>
    supabase.functions.invoke('sync-user', {
      body: JSON.stringify(keysToSnakeDeep(payload))
    })
  await responseHandle(invokeResp, {
    showMessage: true,
    breakReturn: true
  })
}

/*编辑用户*/
export async function editUser(params: Api.SystemManage.UserListItem) {
  const { id, authUserId } = params
  //更新不更新 auth.users表
  const payload = {
    action: 'update',
    id,
    authUserId,
    appUserData: params
  }
  const invokeResp = () =>
    supabase.functions.invoke('sync-user', {
      body: JSON.stringify(keysToSnakeDeep(payload))
    })
  await responseHandle(invokeResp, {
    showMessage: true,
    breakReturn: true
  })
}

// 获取所有用户可分配的角色
export async function fetchGetEnableRoleList(params: { tenantId?: string } = {}) {
  const { tenantId } = params

  if (!tenantId) {
    return { data: [], error: null }
  }

  const query = supabase
    .from('sys_role')
    .select('id, role_name, role_code, enabled, tenant_id')
    .eq('tenant_id', tenantId)
    .eq('enabled', true)
    .order('role_code', { ascending: true })

  return await responseHandle(() => query, {
    ignoreCheck: true
  })
}

// 获取角色列表
export async function fetchGetRoleList(params: Api.SystemManage.RoleSearchParams) {
  const {
    roleName,
    roleCode,
    description,
    enabled,
    startTime = '',
    endTime = '',
    from = 0,
    to = 9
  } = params
  const specs = [
    { col: 'role_name', op: 'ilike', val: roleName ? `%${roleName}%` : undefined },
    { col: 'role_code', op: 'eq', val: roleCode },
    { col: 'description', op: 'ilike', val: description ? `%${description}%` : undefined },
    { col: 'enabled', op: 'eq', val: enabled },
    { col: 'create_time', op: 'gte', val: toStartOfDayUTC(startTime) },
    { col: 'create_time', op: 'lte', val: toNextDayStartUTC(endTime) }
  ]

  // 构建查询
  let query = supabase
    .from('sys_role')
    .select('*, tenant:sys_tenant!sys_role_tenant_id_fkey(tenant_code, tenant_name)', {
      count: 'exact'
    })
    .order('create_time', { ascending: false }) // 按创建时间倒序
    .range(from, to)

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })
  return await responseHandle(() => query, { ignoreCheck: true })
}

/*删除角色*/
export async function deleteRole(params: Api.SystemManage.RoleListItem) {
  const { id } = params
  return await responseHandle(() => supabase.from('sys_role').delete().eq('id', id), {
    showMessage: true
  })
}

/*新增角色*/
export async function addRole(params: Api.SystemManage.RoleListItem) {
  return await responseHandle(() => supabase.from('sys_role').insert(keysToSnakeDeep(params)), {
    showMessage: true,
    breakReturn: true
  })
}

/*编辑角色*/
export async function editRole(params: Api.SystemManage.RoleListItem) {
  const { id } = params
  return await responseHandle(
    () => supabase.from('sys_role').update(keysToSnakeDeep(params)).eq('id', id),
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

/*获取当前角色拥有的菜单*/
export async function getCurrentRoleMenus(params: AppRouteRecord) {
  const { id } = params
  return await responseHandle<Array<{ menuId: string }>>(
    () => supabase.from('sys_role_menu').select().eq('role_id', id),
    {
      ignoreCheck: true
    }
  )
}

// 获取有用的菜单列表
export async function fetchGetEnableMenuList() {
  // 构建查询
  const query = supabase
    .from('sys_menu')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true }) // 按sort倒序

  return await responseHandle<AppRouteRecord[]>(() => query, { ignoreCheck: true })
}

// 保存角色权限
export async function saveRoleMenuList(params: { p_role_id: string; p_menu_ids: string[] }) {
  return await responseHandle(() => supabase.rpc('set_role_menus', params), {
    showMessage: true,
    breakReturn: true
  })
}

// 获取菜单列表
export async function fetchGetMenuList(params: AppRouteRecord) {
  const { name, path } = params
  const specs = buildSpecsFromMap({
    path
  })

  // 构建查询
  let query = supabase.from('sys_menu').select('*', { count: 'exact' })

  if (name) {
    query = query.filter('meta->>title', 'ilike', `%${name}%`)
  }
  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })

  return await responseHandle<AppRouteRecord[]>(() => query, { ignoreCheck: true })
}

/*删除菜单*/
export async function deleteMenu(params: { ids: string[] }) {
  const { ids } = params
  if (!ids.length) throw new Error('未找到需要删除的菜单')

  try {
    return await deleteMenuRows(ids)
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error)
    if (message.includes('sys_role_menu_menu_id_fkey')) {
      await responseHandle(
        () => supabase.from('sys_role_menu').delete({ count: 'exact' }).in('menu_id', ids),
        {
          breakReturn: true,
          requireAffected: true,
          noAffectedMessage: '当前账号没有清理角色菜单关联权限'
        }
      )

      try {
        return await deleteMenuRows(ids)
      } catch (retryError) {
        throw new Error('角色菜单关联已清理，但菜单删除仍然失败', { cause: retryError })
      }
    }

    if (message.includes('foreign key')) {
      throw new Error('该菜单仍被其他业务数据引用，暂时不能删除。', { cause: error })
    }
    throw error
  }
}

async function deleteMenuRows(ids: string[]) {
  return await responseHandle(
    () => supabase.from('sys_menu').delete({ count: 'exact' }).in('id', ids),
    {
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

/*新增菜单*/
export async function addRMenu(params: AppRouteRecord) {
  return await responseHandle(() => supabase.from('sys_menu').insert(keysToSnakeDeep(params)), {
    showMessage: true
  })
}

/*编辑菜单*/
export async function editMenu(params: AppRouteRecord) {
  const { id } = params
  return await responseHandle(
    () =>
      supabase.from('sys_menu').update(keysToSnakeDeep(params), { count: 'exact' }).eq('id', id),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: WRITE_PERMISSION_DENIED_MESSAGE
    }
  )
}

/*拖拽保存菜单父级与排序*/
export async function saveMenuDragSort(
  params: Array<{ id: string; parentId: string | null; sort: number }>
) {
  const results = await Promise.all(
    params.map(({ id, ...data }) =>
      supabase.from('sys_menu').update(keysToSnakeDeep(data), { count: 'exact' }).eq('id', id)
    )
  )

  const error = results.find((result) => result.error)?.error
  if (error) throw error

  if (results.some((result) => result.count === 0)) {
    throw new Error(WRITE_PERMISSION_DENIED_MESSAGE)
  }

  return { data: null, error: null }
}

/*获取当前用户的菜单权限*/
export async function fetchCurrentUserMenu() {
  return await responseHandle<{ flat: AppRouteRecord[]; tree: AppRouteRecord[] }>(
    () => supabase.rpc('get_menus_for_current_user'),
    {
      showMessage: false,
      ignoreCheck: true
    }
  )
}
