import assert from 'node:assert/strict'
import test from 'node:test'
import { resolveTenantScopeReadOnly } from '../../src/utils/tenant-scope-access-policy'

test('platform super retains mutation access in the all-tenant scope', () => {
  assert.equal(
    resolveTenantScopeReadOnly({
      isAllTenants: true,
      isPlatformSuper: true,
      routePath: '/smis/basic-data/position-safety-responsibility'
    }),
    false
  )
})

test('aggregate tenant viewers without platform-super capability remain read-only', () => {
  assert.equal(
    resolveTenantScopeReadOnly({
      isAllTenants: true,
      isPlatformSuper: false,
      routePath: '/smis/basic-data/position-safety-responsibility'
    }),
    true
  )
})

test('tenant administration and singular tenant scopes are not blocked by the aggregate guard', () => {
  assert.equal(
    resolveTenantScopeReadOnly({
      isAllTenants: true,
      isPlatformSuper: false,
      routePath: '/system/tenant'
    }),
    false
  )
  assert.equal(
    resolveTenantScopeReadOnly({
      isAllTenants: false,
      isPlatformSuper: false,
      routePath: '/smis/basic-data/position-safety-responsibility'
    }),
    false
  )
})
