import { useSupabase } from '@/hooks/core/useSupabase'
import { applyFilters } from '@/utils/supabase'

type TenantListItem = Api.SystemManage.TenantListItem
type TenantSearchParams = Api.SystemManage.TenantSearchParams

const { supabase, keysToSnakeDeep, responseHandle } = useSupabase()

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
    showErrorMessage: true
  })
}

export async function fetchGetEnableTenantList() {
  const query = supabase
    .from('sys_tenant')
    .select('id, tenant_code, tenant_name, status, builtin_type')
    .eq('status', '1')
    .order('tenant_code', { ascending: true })

  return await responseHandle<TenantListItem[]>(() => query, {
    showErrorMessage: true
  })
}

export async function addTenant(params: TenantListItem) {
  return await responseHandle(() => supabase.from('sys_tenant').insert(keysToSnakeDeep(params)), {
    showMessage: true,
    breakReturn: true
  })
}

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

/** 保留组织、账号和业务历史，只停用租户。 */
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
