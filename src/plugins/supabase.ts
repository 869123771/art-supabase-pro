import { createClient } from '@supabase/supabase-js'
import { isSupabaseApi } from '@/config/api-provider'
import {
  readTenantScopeId,
  shouldAttachTenantScopeHeader,
  TENANT_SCOPE_HEADER
} from '@/utils/tenant-scope-context'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'http://localhost'
const supabaseKey = import.meta.env.VITE_SUPABASE_KEY || 'java-api-provider'

if (isSupabaseApi && (!import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_KEY)) {
  throw new Error('Missing VITE_SUPABASE_URL or VITE_SUPABASE_KEY')
}

const tenantScopeFetch: typeof fetch = (input, init) => {
  const tenantScopeId = readTenantScopeId()
  const requestUrl = input instanceof Request ? input.url : String(input)
  if (!tenantScopeId || !shouldAttachTenantScopeHeader(requestUrl)) return fetch(input, init)

  const headers = new Headers(input instanceof Request ? input.headers : undefined)
  new Headers(init?.headers).forEach((value, key) => headers.set(key, value))
  headers.set(TENANT_SCOPE_HEADER, tenantScopeId)

  return fetch(input, { ...init, headers })
}

export const supabase = createClient(supabaseUrl, supabaseKey, {
  global: { fetch: tenantScopeFetch }
})
