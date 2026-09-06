import assert from 'node:assert/strict'
import test from 'node:test'
import {
  readTenantScopeId,
  readPlatformTenantScopeActive,
  readMutationTenantScopeId,
  normalizePlatformTenantReadUrl,
  resolveTenantScopeId,
  shouldAttachTenantScopeHeader,
  TENANT_SCOPE_MODE_STORAGE_KEY,
  TENANT_SCOPE_STORAGE_KEY,
  writePlatformTenantScopeActive,
  writeTenantScopeId
} from '../../src/utils/tenant-scope-context'

class MemoryStorage implements Storage {
  private readonly values = new Map<string, string>()

  get length(): number {
    return this.values.size
  }

  clear(): void {
    this.values.clear()
  }

  getItem(key: string): string | null {
    return this.values.get(key) ?? null
  }

  key(index: number): string | null {
    return [...this.values.keys()][index] ?? null
  }

  removeItem(key: string): void {
    this.values.delete(key)
  }

  setItem(key: string, value: string): void {
    this.values.set(key, value)
  }
}

test('tenant scope context persists only valid concrete tenant UUIDs', () => {
  const originalDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'sessionStorage')
  const storage = new MemoryStorage()
  Object.defineProperty(globalThis, 'sessionStorage', { configurable: true, value: storage })

  try {
    const tenantId = '7529f951-938e-4e2c-ac0d-316c136ae1f9'
    writeTenantScopeId(tenantId)
    assert.equal(readTenantScopeId(), tenantId)
    assert.equal(resolveTenantScopeId(), tenantId)
    assert.equal(
      resolveTenantScopeId('a6f21b7d-bca8-4698-a72a-b6df251bf07c'),
      'a6f21b7d-bca8-4698-a72a-b6df251bf07c'
    )

    storage.setItem(TENANT_SCOPE_STORAGE_KEY, 'not-a-tenant-id')
    assert.equal(readTenantScopeId(), null)
    assert.equal(resolveTenantScopeId(), undefined)

    writeTenantScopeId(null)
    assert.equal(storage.getItem(TENANT_SCOPE_STORAGE_KEY), null)
  } finally {
    if (originalDescriptor) {
      Object.defineProperty(globalThis, 'sessionStorage', originalDescriptor)
    } else {
      Reflect.deleteProperty(globalThis, 'sessionStorage')
    }
  }
})

test('platform scope state is explicit even when all tenants is selected', () => {
  const originalDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'sessionStorage')
  const storage = new MemoryStorage()
  Object.defineProperty(globalThis, 'sessionStorage', { configurable: true, value: storage })

  try {
    writePlatformTenantScopeActive(true)
    assert.equal(readPlatformTenantScopeActive(), true)
    assert.equal(storage.getItem(TENANT_SCOPE_MODE_STORAGE_KEY), '1')

    writePlatformTenantScopeActive(false)
    assert.equal(readPlatformTenantScopeActive(), false)
  } finally {
    if (originalDescriptor) {
      Object.defineProperty(globalThis, 'sessionStorage', originalDescriptor)
    } else {
      Reflect.deleteProperty(globalThis, 'sessionStorage')
    }
  }
})

test('platform table reads discard legacy tenant filters but preserve business filters and RPCs', () => {
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/mdm_production_department?select=*&tenant_id=eq.platform&enabled=eq.true'
    ),
    'https://example.supabase.co/rest/v1/mdm_production_department?select=*&enabled=eq.true'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/mdm_employee?organization.tenant_id=eq.platform&name=ilike.%25A%25'
    ),
    'https://example.supabase.co/rest/v1/mdm_employee?name=ilike.%25A%25'
  )
  assert.equal(
    normalizePlatformTenantReadUrl(
      'https://example.supabase.co/rest/v1/rpc/list_people?tenant_id=platform'
    ),
    'https://example.supabase.co/rest/v1/rpc/list_people?tenant_id=platform'
  )
})

test('tenant scope header is attached only to Supabase Data API requests', () => {
  assert.equal(
    shouldAttachTenantScopeHeader('https://example.supabase.co/rest/v1/sys_user?select=*'),
    true
  )
  assert.equal(
    shouldAttachTenantScopeHeader(
      'https://example.supabase.co/rest/v1/rpc/get_platform_tenant_options'
    ),
    true
  )
  assert.equal(shouldAttachTenantScopeHeader('/rest/v1/sys_tenant'), true)

  assert.equal(
    shouldAttachTenantScopeHeader('https://example.supabase.co/functions/v1/check_user_status'),
    false
  )
  assert.equal(
    shouldAttachTenantScopeHeader('https://example.supabase.co/auth/v1/token?grant_type=password'),
    false
  )
  assert.equal(
    shouldAttachTenantScopeHeader(
      'https://example.supabase.co/storage/v1/object/public/avatar/demo.png'
    ),
    false
  )
  assert.equal(shouldAttachTenantScopeHeader('not a Supabase request'), false)
})

test('mutation tenant scope is read only from explicit table and supported RPC payloads', () => {
  const tenantId = '7529f951-938e-4e2c-ac0d-316c136ae1f9'
  assert.equal(readMutationTenantScopeId(JSON.stringify({ tenant_id: tenantId })), tenantId)
  assert.equal(
    readMutationTenantScopeId(JSON.stringify({ p_header: { tenant_id: tenantId } })),
    tenantId
  )
  assert.equal(
    readMutationTenantScopeId(JSON.stringify({ p_document: { tenant_id: tenantId } })),
    tenantId
  )
  assert.equal(readMutationTenantScopeId(JSON.stringify({ tenant_id: 'invalid' })), null)
  assert.equal(readMutationTenantScopeId('not-json'), null)
})
