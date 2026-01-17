import { AppRouteRecord } from '@/types/router'
import { useSupabase } from '@/hooks'
import { buildSpecsFromMap, applyFilters } from '@utils/supabase-filters'
import { toNextDayStartUTC, toStartOfDayUTC } from '@/utils'
const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

// 获取用户列表
export async function fetchGetUserList(params: Api.SystemManage.UserSearchParams) {
  const { userName, userPhone, userGender, userEmail, status, from = 0, to = 9 } = params
  // 想要：userName 使用 ilike 模糊匹配，其它字段精确匹配
  // opsMap 使用 snake_case keys（buildSpecsFromMap 会内部 convertKeysToSnake，所以可以用 camelCase）
  const opsMap = {
    userName: 'ilike' // will be mapped to user_name internally
    // userPhone 默认 eq
  } as Record<string, any>

  // buildSpecsFromMap 会把 keys 转为 snake_case，并返回 FilterSpec[]
  // 它默认 op 为 'eq'，但会把 opsMap 中指定的替换为对应 op
  const specs = buildSpecsFromMap(
    {
      userName: userName ? `%${userName}%` : undefined, // 包裹 % 以用于 ilike
      userPhone,
      userEmail,
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
    .from('app_users')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false }) // 按创建时间倒序
    .range(from, to)

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })

  return await responseHandle(() => query as any, { ignoreCheck: true })
}

/*重置密码*/
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
  //删除auth.usres 表对应记录
  const payload: any = { action: 'delete', id: id }
  if (authUserId) {
    payload.auth_user_id = authUserId
  }
  const invokeResp = () =>
    supabase.functions.invoke('sync-user', {
      body: payload
    }) as any
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
export async function fetchGetEnableRoleList() {
  return await responseHandle(() => supabase.from('roles').select() as any, { ignoreCheck: true })
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
  let query: any = supabase
    .from('roles')
    .select('*', { count: 'exact' })
    .order('create_time', { ascending: false }) // 按创建时间倒序
    .range(from, to)

  console.log('specs:', JSON.stringify(specs, null, 2))

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })
  return await responseHandle(() => query as any, { ignoreCheck: true })
}

/*删除角色*/
export async function deleteRole(params: Api.SystemManage.RoleListItem) {
  const { id } = params
  return await responseHandle(() => supabase.from('roles').delete().eq('id', id) as any, {
    showMessage: true
  })
}

/*新增角色*/
export async function addRole(params: Api.SystemManage.RoleListItem) {
  return await responseHandle(() => supabase.from('roles').insert(keysToSnakeDeep(params)) as any, {
    showMessage: true,
    breakReturn: true
  })
}

/*编辑角色*/
export async function editRole(params: Api.SystemManage.RoleListItem) {
  const { id } = params
  return await responseHandle(
    () => supabase.from('roles').update(keysToSnakeDeep(params)).eq('id', id) as any,
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

/*获取当前角色拥有的菜单*/
export async function getCurrentRoleMenus(params: AppRouteRecord) {
  const { id } = params
  return await responseHandle(() => supabase.from('role_menus').select().eq('role_id', id) as any, {
    ignoreCheck: true
  })
}

// 获取有用的菜单列表
export async function fetchGetEnableMenuList() {
  // 构建查询
  const query = supabase
    .from('menus')
    .select('*', { count: 'exact' })
    .order('sort', { ascending: true }) // 按sort倒序

  return await responseHandle(() => query as any, { ignoreCheck: true })
}

// 保存角色权限
export async function saveRoleMenuList(params: any) {
  return await responseHandle(() => supabase.rpc('set_role_menus', params) as any, {
    showMessage: true
  })
}

// 获取菜单列表
export async function fetchGetMenuList(params: AppRouteRecord) {
  const { name, path } = params
  const specs = buildSpecsFromMap({
    path
  })

  // 构建查询
  let query: any = supabase.from('menus').select('*', { count: 'exact' })

  if (name) {
    query = query.filter('meta->>title', 'ilike', `%${name}%`)
  }
  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })

  return await responseHandle(() => query as any, { ignoreCheck: true })
}

/*删除菜单*/
export async function deleteMenu(params: Array<string>) {
  const { ids } = params as any
  return await responseHandle(() => supabase.from('menus').delete().in('id', ids) as any, {
    showMessage: true
  })
}

/*新增菜单*/
export async function addRMenu(params: AppRouteRecord) {
  return await responseHandle(() => supabase.from('menus').insert(keysToSnakeDeep(params)) as any, {
    showMessage: true
  })
}

/*编辑菜单*/
export async function editMenu(params: AppRouteRecord) {
  const { id } = params
  return await responseHandle(
    () => supabase.from('menus').update(keysToSnakeDeep(params)).eq('id', id) as any,
    {
      showMessage: true
    }
  )
}

/*获取当前用户的菜单权限*/
export async function fetchCurrentUserMenu() {
  return await responseHandle(() => supabase.rpc('get_menus_for_current_user') as any, {
    showMessage: false,
    ignoreCheck: true
  })
}
