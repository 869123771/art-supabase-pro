import { AppRouteRecord } from '@/types/router'
import type { ApplicationCode } from '@/config/application'
import { useSupabase } from '@/hooks'
import { WRITE_PERMISSION_DENIED_MESSAGE } from '@/hooks/core/useSupabase'
import { buildSpecsFromMap, applyFilters, type Op } from '@/utils/supabase'
import { toNextDayStartUTC, toStartOfDayUTC } from '@/utils'
import { omit } from 'lodash-es'
import TreeUtils from '@/utils/tree'
import { resolveTenantScopeId } from '@/utils/tenant-scope-context'
const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

const organizationTreeUtils = new TreeUtils({
  idKey: 'id',
  parentKey: 'parentId',
  childrenKey: 'children'
})

const ORGANIZATION_DETAIL_SELECT = `
  *,
  tenant:sys_tenant!sys_organization_tenant_id_fkey(tenant_code, tenant_name),
  leader:sys_user!sys_organization_leader_user_id_fkey(
    id, avatar, user_name, nick_name, user_email
  ),
  members:sys_user!sys_user_organization_id_fkey(
    id, avatar, user_name, nick_name, user_email, status, user_roles
  ),
  roles:sys_role!sys_role_organization_id_fkey(
    id, role_name, role_code, enabled,
    role_menus:sys_role_menu!sys_role_menu_role_id_fkey(
      menu_id,
      menu:sys_menu!sys_role_menu_menu_id_fkey(name, type, meta)
    )
  )
`

type TenantListItem = Api.SystemManage.TenantListItem
type TenantSearchParams = Api.SystemManage.TenantSearchParams
type SystemParamItem = Api.SystemManage.SystemParamItem
type SystemParamSearchParams = Api.SystemManage.SystemParamSearchParams
type WebsiteConfigItem = Api.SystemManage.WebsiteConfigItem
type WebsiteConfigParamMeta = Api.SystemManage.WebsiteConfigParamMeta
const WEBSITE_CONFIG_PARAM_KEY = 'website.config'
type GeofenceConfigItem = Api.SystemManage.GeofenceConfigItem
const GEOFENCE_CONFIG_PARAM_KEY = 'tms.geofence.config'

interface DeleteUserSyncPayload {
  action: 'deactivate'
  id: string
  auth_user_id?: string
}

// 获取用户列表
export async function fetchGetUserList(params: Api.SystemManage.UserSearchParams) {
  const {
    id,
    tenantId,
    organizationId,
    organizationIds,
    organizationUnassigned,
    userName,
    userPhone,
    userGender,
    userEmail,
    status,
    from = 0,
    to = 9
  } = params
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
      id,
      userName: userName ? `%${userName}%` : undefined, // 包裹 % 以用于 ilike
      userPhone,
      userEmail: userEmail?.trim() ? `%${userEmail.trim()}%` : undefined,
      userGender,
      status,
      tenantId,
      organizationId: organizationUnassigned ? undefined : organizationId
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
    .select(
      `
        *,
        tenant:sys_tenant!sys_user_tenant_id_fkey(tenant_code, tenant_name, builtin_type),
        organization:sys_organization!sys_user_organization_id_fkey(
          id,
          organization_code,
          organization_name
        )
      `,
      { count: 'exact' }
    )
    .is('deleted_at', null)
    .order('create_time', { ascending: false }) // 按创建时间倒序
    .range(from, to)

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })

  if (organizationUnassigned) {
    query = query.is('organization_id', null)
  } else if (organizationIds?.length) {
    query = query.in('organization_id', organizationIds)
  }

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
    .select('id, tenant_code, tenant_name, status, builtin_type')
    .eq('status', '1')
    .order('tenant_code', { ascending: true })

  return await responseHandle<TenantListItem[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function fetchGetOrganizationList(
  params: Api.SystemManage.OrganizationSearchParams = {}
) {
  const { keyword, tenantId, organizationType, status, recordId } = params
  const scopedTenantId = resolveTenantScopeId(tenantId)
  const response = await responseHandle<Api.SystemManage.OrganizationListItem[]>(
    () =>
      supabase.rpc('get_organization_list_secure', {
        p_keyword: keyword?.trim() || undefined,
        p_tenant_id: scopedTenantId,
        p_organization_type: organizationType || undefined,
        p_status: status || undefined,
        p_record_id: recordId || undefined
      }),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )

  return {
    ...response,
    total: response.data?.length ?? 0
  }
}

export async function fetchGetOrganizationDetail(id: string) {
  return await responseHandle<Api.SystemManage.OrganizationListItem | null>(
    () =>
      supabase
        .from('sys_organization')
        .select(ORGANIZATION_DETAIL_SELECT)
        .eq('id', id)
        .maybeSingle(),
    {
      ignoreCheck: true,
      showErrorMessage: true
    }
  )
}

export async function fetchGetOrganizationTree(
  params: Api.SystemManage.OrganizationSearchParams = {}
) {
  const response = await fetchGetOrganizationList(params)
  const records = response.data ?? []
  return {
    ...response,
    data: organizationTreeUtils.listToTree(records, (a, b) => {
      const sortDiff = (a.sort ?? 0) - (b.sort ?? 0)
      return sortDiff || a.organizationName.localeCompare(b.organizationName, 'zh-CN')
    })
  }
}

export async function fetchGetEnableOrganizationTree(
  params: {
    tenantId?: string
    excludeId?: string
  } = {}
) {
  if (!params?.tenantId) {
    return { data: [], error: null }
  }

  const response = await fetchGetOrganizationTree({
    tenantId: params.tenantId,
    status: '1'
  })
  const data = params.excludeId
    ? organizationTreeUtils.removeNodesByCondition(
        response.data ?? [],
        (node) => node.id === params.excludeId
      ).tree
    : response.data

  return { ...response, data }
}

export async function fetchGetUserOrganizationTree(params: { tenantId?: string } = {}) {
  let query = supabase
    .from('sys_organization')
    .select(
      `
        id, tenant_id, parent_id, organization_code, organization_name,
        organization_type, status, sort, is_system,
        tenant:sys_tenant!sys_organization_tenant_id_fkey(tenant_code, tenant_name),
        members:sys_user!sys_user_organization_id_fkey(id, status)
      `
    )
    .eq('status', '1')
    .order('sort', { ascending: true })
    .order('organization_name', { ascending: true })

  if (params.tenantId) query = query.eq('tenant_id', params.tenantId)

  const response = await responseHandle<
    Array<Api.SystemManage.OrganizationScopeFilterItem & { members?: Array<{ id: string }> }>
  >(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })

  return {
    ...response,
    data: organizationTreeUtils.listToTree(
      (response.data ?? []).map(({ members, ...organization }) => ({
        ...organization,
        scopeCount: members?.length ?? 0
      })),
      (a, b) => {
        const tenantDiff = (a.tenant?.tenantName ?? '').localeCompare(
          b.tenant?.tenantName ?? '',
          'zh-CN'
        )
        const sortDiff = (a.sort ?? 0) - (b.sort ?? 0)
        return (
          tenantDiff || sortDiff || a.organizationName.localeCompare(b.organizationName, 'zh-CN')
        )
      }
    )
  }
}

export async function fetchGetRoleOrganizationTree(params: { tenantId?: string } = {}) {
  let query = supabase
    .from('sys_organization')
    .select(
      `
        id, tenant_id, parent_id, organization_code, organization_name,
        organization_type, status, sort, is_system,
        tenant:sys_tenant!sys_organization_tenant_id_fkey(tenant_code, tenant_name),
        roles:sys_role!sys_role_organization_id_fkey(id, enabled)
      `
    )
    .eq('status', '1')
    .order('sort', { ascending: true })
    .order('organization_name', { ascending: true })

  if (params.tenantId) query = query.eq('tenant_id', params.tenantId)

  const response = await responseHandle<
    Array<Api.SystemManage.OrganizationScopeFilterItem & { roles?: Array<{ id: string }> }>
  >(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })

  return {
    ...response,
    data: organizationTreeUtils.listToTree(
      (response.data ?? []).map(({ roles, ...organization }) => ({
        ...organization,
        scopeCount: roles?.length ?? 0
      })),
      (a, b) => {
        const tenantDiff = (a.tenant?.tenantName ?? '').localeCompare(
          b.tenant?.tenantName ?? '',
          'zh-CN'
        )
        const sortDiff = (a.sort ?? 0) - (b.sort ?? 0)
        return (
          tenantDiff || sortDiff || a.organizationName.localeCompare(b.organizationName, 'zh-CN')
        )
      }
    )
  }
}

export async function fetchGetEnableOrganizationUserList(params: { tenantId?: string } = {}) {
  if (!params?.tenantId) {
    return { data: [], error: null }
  }

  const query = supabase
    .from('sys_user')
    .select(
      `
        id,
        tenant_id,
        organization_id,
        avatar,
        user_name,
        nick_name,
        user_email,
        status,
        organization:sys_organization!sys_user_organization_id_fkey(
          id,
          organization_code,
          organization_name
        )
      `
    )
    .eq('tenant_id', params.tenantId)
    .eq('status', '1')
    .is('deleted_at', null)
    .order('nick_name', { ascending: true })

  return await responseHandle<Api.SystemManage.OrganizationMember[]>(() => query, {
    ignoreCheck: true,
    showErrorMessage: true
  })
}

export async function addOrganization(params: Api.SystemManage.OrganizationSavePayload) {
  return await responseHandle(
    () => supabase.from('sys_organization').insert(keysToSnakeDeep(params)),
    {
      showMessage: true,
      breakReturn: true
    }
  )
}

export async function editOrganization(params: Api.SystemManage.OrganizationSavePayload) {
  const { id, ...payload } = params
  return await responseHandle(
    () =>
      supabase
        .from('sys_organization')
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

export async function deleteOrganization(id: string) {
  return await responseHandle(
    () =>
      supabase
        .from('sys_organization')
        .delete({ count: 'exact' })
        .eq('id', id)
        .eq('is_system', false),
    {
      showMessage: true,
      requireAffected: true,
      noAffectedMessage: '系统预置根组织不可删除，或当前账号没有删除权限'
    }
  )
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

// 停用租户：保留组织、账号和业务历史，阻止继续作为有效租户使用。
export async function deactivateTenant(id: string) {
  return await responseHandle(
    () =>
      supabase
        .from('sys_tenant')
        .update({ status: '0' })
        .eq('id', id)
        .is('builtin_type', null)
        .select('id'),
    {
      showMessage: true,
      message: '租户已停用，历史数据已保留',
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: '系统预置租户不可停用，或当前账号没有操作权限'
    }
  )
}

// 批量停用租户
export async function deactivateTenantBatch(ids: string[]) {
  return await responseHandle(
    () =>
      supabase
        .from('sys_tenant')
        .update({ status: '0' })
        .in('id', ids)
        .is('builtin_type', null)
        .select('id'),
    {
      showMessage: true,
      message: '所选租户已停用，历史数据已保留',
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: '所选记录均为系统预置租户，或当前账号没有操作权限'
    }
  )
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

export async function fetchRegistrationRoleOptions() {
  return await responseHandle<Api.SystemManage.RegistrationRoleOption[]>(
    () => supabase.rpc('get_registration_role_options'),
    {
      ignoreCheck: true,
      showErrorMessage: true
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

const parseGeofenceConfig = (row: SystemParamItem | null): GeofenceConfigItem | null => {
  if (!row?.paramValue) return null

  try {
    const parsed = JSON.parse(row.paramValue) as Partial<GeofenceConfigItem>
    return {
      id: row.id,
      tenantId: row.tenantId,
      enabled: parsed.enabled !== false,
      loadingRadiusM: Number(parsed.loadingRadiusM) || 1000,
      unloadingRadiusM: Number(parsed.unloadingRadiusM) || 1000,
      loadingAllowOutsideCheckIn: parsed.loadingAllowOutsideCheckIn === true,
      unloadingAllowOutsideCheckIn: parsed.unloadingAllowOutsideCheckIn === true,
      autoConfirmLoading: parsed.autoConfirmLoading === true,
      autoConfirmUnloading: parsed.autoConfirmUnloading === true,
      createBy: row.createBy,
      createTime: row.createTime,
      updateBy: row.updateBy,
      updateTime: row.updateTime
    }
  } catch {
    return null
  }
}

export async function fetchGeofenceConfig(): Promise<{
  data: GeofenceConfigItem | null
  error: unknown | null
}> {
  const { data, error } = await responseHandle<SystemParamItem | null>(
    () =>
      supabase
        .from('sys_param')
        .select('*')
        .eq('param_key', GEOFENCE_CONFIG_PARAM_KEY)
        .eq('enabled', true)
        .maybeSingle(),
    { ignoreCheck: true, showErrorMessage: true }
  )
  return { data: parseGeofenceConfig(data), error }
}

export async function saveGeofenceConfig(params: GeofenceConfigItem) {
  const config = omit(params, [
    'id',
    'tenantId',
    'createBy',
    'createTime',
    'updateBy',
    'updateTime'
  ])
  return await responseHandle<GeofenceConfigItem>(
    () => supabase.rpc('tms_save_geofence_config', { p_config: config }),
    { showMessage: true, breakReturn: true }
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

/*注销用户：保留业务资料，只撤销登录与角色授权。*/
export async function deactivateUser(params: Api.SystemManage.UserListItem) {
  const { id, authUserId } = params
  if (!id) {
    throw new Error('未找到需要注销的用户')
  }
  const payload: DeleteUserSyncPayload = { action: 'deactivate', id: id }
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

/*分配用户角色*/
export async function assignUserRoles(params: Api.SystemManage.UserListItem) {
  const { id, tenantId, userRoles } = params
  const payload = {
    action: 'assign_roles',
    id,
    appUserData: { tenantId, userRoles }
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
    .select('id, role_name, role_code, enabled, tenant_id, builtin_type')
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
    tenantId,
    organizationId,
    organizationIds,
    organizationUnassigned,
    roleName,
    roleCode,
    description,
    enabled,
    startTime = '',
    endTime = '',
    recordId,
    from = 0,
    to = 9
  } = params
  const specs = [
    { col: 'id', op: 'eq', val: recordId },
    { col: 'role_name', op: 'ilike', val: roleName ? `%${roleName}%` : undefined },
    { col: 'role_code', op: 'eq', val: roleCode },
    { col: 'description', op: 'ilike', val: description ? `%${description}%` : undefined },
    { col: 'enabled', op: 'eq', val: enabled },
    { col: 'tenant_id', op: 'eq', val: tenantId },
    {
      col: 'organization_id',
      op: 'eq',
      val: organizationUnassigned ? undefined : organizationId
    },
    { col: 'create_time', op: 'gte', val: toStartOfDayUTC(startTime) },
    { col: 'create_time', op: 'lte', val: toNextDayStartUTC(endTime) }
  ]

  // 构建查询
  let query = supabase
    .from('sys_role')
    .select(
      `
        *,
        tenant:sys_tenant!sys_role_tenant_id_fkey(tenant_code, tenant_name, builtin_type),
        organization:sys_organization!sys_role_organization_id_fkey(
          id, organization_code, organization_name
        )
      `,
      { count: 'exact' }
    )
    .order('create_time', { ascending: false }) // 按创建时间倒序
    .range(from, to)

  // applyFilters 支持传入 FilterSpec[]（这里 specs 已为 snake_case）
  query = applyFilters(query, specs, { skipEmpty: true, camelToSnake: false })

  if (organizationUnassigned) {
    query = query.is('organization_id', null)
  } else if (organizationIds?.length) {
    query = query.in('organization_id', organizationIds)
  }

  return await responseHandle(() => query, { ignoreCheck: true })
}

/*删除角色*/
export async function deleteRole(params: Api.SystemManage.RoleListItem) {
  const { id } = params
  return await responseHandle(
    () =>
      supabase.from('sys_role').delete({ count: 'exact' }).eq('id', id).is('builtin_type', null),
    {
      showMessage: true,
      breakReturn: true,
      requireAffected: true,
      noAffectedMessage: '系统预置角色不可删除，或当前账号没有删除权限'
    }
  )
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
  const { id, ...payload } = params
  return await responseHandle(
    () => supabase.from('sys_role').update(keysToSnakeDeep(payload)).eq('id', id),
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
export async function fetchGetMenuList(params: AppRouteRecord & { recordId?: string }) {
  const { name, path, recordId } = params
  const specs = buildSpecsFromMap({
    path,
    id: recordId
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

  return await deleteMenuRows(ids)
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

export async function saveMenuSort(params: Array<{ id: string; sort: number }>) {
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

/*原子保存完整菜单树的父级关系和同级顺序*/
export async function saveMenuTreeOrder(
  updates: Array<{ id: string; parentId: string | null; sort: number }>
) {
  return await responseHandle(
    () =>
      supabase.rpc('save_menu_tree_order', {
        p_updates: updates
      }),
    {
      breakReturn: true,
      showMessage: false
    }
  )
}

/*获取当前用户的菜单权限*/
export async function fetchCurrentUserMenu(applicationCode: ApplicationCode, signal?: AbortSignal) {
  const query = supabase.rpc('get_menus_for_current_application', {
    p_app_code: applicationCode
  })
  return await responseHandle<{ flat: AppRouteRecord[]; tree: AppRouteRecord[] }>(
    () => (signal ? query.abortSignal(signal) : query),
    {
      showMessage: false,
      ignoreCheck: true
    }
  )
}

export interface AccessibleApplication {
  code: ApplicationCode
  name: string
  description: string | null
  baseUrl: string
  sort: number
}

/** 获取当前用户可进入的独立应用。 */
export async function fetchAccessibleApplications(signal?: AbortSignal) {
  const query = supabase.rpc('get_accessible_applications')
  return await responseHandle<AccessibleApplication[]>(
    () => (signal ? query.abortSignal(signal) : query),
    {
      showMessage: false,
      ignoreCheck: true
    }
  )
}
