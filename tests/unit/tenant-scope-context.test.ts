import assert from 'node:assert/strict'
import test from 'node:test'
import {
  readTenantScopeId,
  resolveTenantScopeId,
  shouldAttachTenantScopeHeader,
  TENANT_SCOPE_STORAGE_KEY,
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
