import { createClient } from '@supabase/supabase-js'
import { isSupabaseApi } from '@/config/api-provider'
import {
  normalizePlatformTenantReadUrl,
  readPlatformTenantScopeActive,
  readMutationTenantScopeId,
  readTenantScopeId,
  shouldAttachTenantScopeHeader,
  TENANT_SCOPE_HEADER
} from '@/utils/tenant-scope-context'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'http://localhost'
const supabaseKey = import.meta.env.VITE_SUPABASE_KEY || 'java-api-provider'

if (isSupabaseApi && (!import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_KEY)) {
  throw new Error('Missing VITE_SUPABASE_URL or VITE_SUPABASE_KEY')
}

const tenantScopeFetch: typeof fetch = async (input, init) => {
  const selectedTenantScopeId = readTenantScopeId()
  const requestUrl = input instanceof Request ? input.url : String(input)
  const requestMethod = (
    init?.method ?? (input instanceof Request ? input.method : 'GET')
  ).toUpperCase()
  const isDataApiRequest = shouldAttachTenantScopeHeader(requestUrl)
  const shouldNormalizeRead =
    readPlatformTenantScopeActive() && ['GET', 'HEAD'].includes(requestMethod) && isDataApiRequest
  const requestBody = init?.body ?? (input instanceof Request ? await input.clone().text() : null)
  const mutationTenantScopeId =
    readPlatformTenantScopeActive() && !['GET', 'HEAD'].includes(requestMethod)
      ? readMutationTenantScopeId(requestBody)
      : null
  const tenantScopeId = selectedTenantScopeId ?? mutationTenantScopeId
  const normalizedUrl = shouldNormalizeRead
    ? normalizePlatformTenantReadUrl(requestUrl)
    : requestUrl

  if (!tenantScopeId || !isDataApiRequest) {
    if (normalizedUrl === requestUrl) return fetch(input, init)
    const normalizedInput =
      input instanceof Request ? new Request(normalizedUrl, input) : normalizedUrl
    return fetch(normalizedInput, init)
  }

  const headers = new Headers(input instanceof Request ? input.headers : undefined)
  new Headers(init?.headers).forEach((value, key) => headers.set(key, value))
  headers.set(TENANT_SCOPE_HEADER, tenantScopeId)

  const normalizedInput =
    input instanceof Request ? new Request(normalizedUrl, input) : normalizedUrl
  return fetch(normalizedInput, { ...init, headers })
}

export const supabase = createClient(supabaseUrl, supabaseKey, {
  global: { fetch: tenantScopeFetch }
})
