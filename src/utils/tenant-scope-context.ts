export const TENANT_SCOPE_HEADER = 'x-art-tenant-scope'
export const TENANT_SCOPE_STORAGE_KEY = 'art-platform-tenant-scope-id'
export const TENANT_SCOPE_MODE_STORAGE_KEY = 'art-platform-tenant-scope-active'

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

const tenantIdFromRecord = (value: unknown): string | null => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const record = value as Record<string, unknown>
  const candidates = [
    record.tenant_id,
    (record.p_header as Record<string, unknown> | undefined)?.tenant_id,
    (record.p_payload as Record<string, unknown> | undefined)?.tenant_id,
    (record.p_document as Record<string, unknown> | undefined)?.tenant_id
  ]
  const tenantId = candidates.find(
    (candidate): candidate is string =>
      typeof candidate === 'string' && UUID_PATTERN.test(candidate)
  )
  return tenantId ?? null
}

/** Resolve an explicit write target from a PostgREST table or RPC JSON body. */
export const readMutationTenantScopeId = (body: BodyInit | null | undefined): string | null => {
  if (typeof body !== 'string' || !body.trim()) return null
  try {
    const payload: unknown = JSON.parse(body)
    if (Array.isArray(payload)) {
      const tenantIds = [...new Set(payload.map(tenantIdFromRecord).filter(Boolean))]
      return tenantIds.length === 1 ? (tenantIds[0] ?? null) : null
    }
    return tenantIdFromRecord(payload)
  } catch {
    return null
  }
}

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

/** Whether the current browser session belongs to the platform-wide tenant console. */
export const readPlatformTenantScopeActive = (): boolean => {
  if (typeof sessionStorage === 'undefined') return false
  try {
    return sessionStorage.getItem(TENANT_SCOPE_MODE_STORAGE_KEY) === '1'
  } catch {
    return false
  }
}

/**
 * Legacy pages sometimes hard-code the authenticated platform tenant into read queries. The
 * platform shell is the canonical read scope, so remove only top-level/nested tenant_id filters
 * from table reads and let the database scope policy apply "all" or the selected tenant.
 */
export const normalizePlatformTenantReadUrl = (requestUrl: string): string => {
  try {
    const url = new URL(requestUrl)
    if (!url.pathname.startsWith('/rest/v1/') || url.pathname.startsWith('/rest/v1/rpc/')) {
      return requestUrl
    }

    const tenantFilterKeys = [...url.searchParams.keys()].filter((key) =>
      /(^|\.)tenant_id$/i.test(key)
    )
    tenantFilterKeys.forEach((key) => url.searchParams.delete(key))
    return url.toString()
  } catch {
    return requestUrl
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

export const writePlatformTenantScopeActive = (active: boolean): void => {
  if (typeof sessionStorage === 'undefined') return
  try {
    if (active) {
      sessionStorage.setItem(TENANT_SCOPE_MODE_STORAGE_KEY, '1')
      return
    }
    sessionStorage.removeItem(TENANT_SCOPE_MODE_STORAGE_KEY)
  } catch {
    // 浏览器禁用会话存储时退化为当前页面生命周期内的状态。
  }
}
