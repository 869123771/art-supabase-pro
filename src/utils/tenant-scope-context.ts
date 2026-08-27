export const TENANT_SCOPE_HEADER = 'x-art-tenant-scope'
export const TENANT_SCOPE_STORAGE_KEY = 'art-platform-tenant-scope-id'

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

export const shouldAttachTenantScopeHeader = (requestUrl: string): boolean => {
  try {
    const { pathname } = new URL(requestUrl, 'http://localhost')
    return pathname === '/rest/v1' || pathname.startsWith('/rest/v1/')
  } catch {
    return false
  }
}

export const readTenantScopeId = (): string | null => {
  if (typeof sessionStorage === 'undefined') return null
  try {
    const value = sessionStorage.getItem(TENANT_SCOPE_STORAGE_KEY)?.trim()
    return value && UUID_PATTERN.test(value) ? value : null
  } catch {
    return null
  }
}

/**
 * Resolve an optional tenant query parameter against the platform scope selected in the shell.
 * Explicit feature parameters always win; ordinary tenant users have no stored platform scope
 * and continue to rely on the server-side tenant boundary.
 */
export const resolveTenantScopeId = (explicitTenantId?: string | null): string | undefined =>
  explicitTenantId?.trim() || readTenantScopeId() || undefined

export const writeTenantScopeId = (tenantId: string | null): void => {
  if (typeof sessionStorage === 'undefined') return
  try {
    if (tenantId) {
      sessionStorage.setItem(TENANT_SCOPE_STORAGE_KEY, tenantId)
      return
    }
    sessionStorage.removeItem(TENANT_SCOPE_STORAGE_KEY)
  } catch {
    // 浏览器禁用会话存储时退化为当前页面生命周期内的状态。
  }
}
