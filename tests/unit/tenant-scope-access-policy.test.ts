import assert from 'node:assert/strict'
import test from 'node:test'
import {
  resolveTenantReadTargetId,
  resolveTenantScopeReadOnly
} from '../../src/utils/tenant-scope-access-policy'

test('tenant read targets respect all, selected, ordinary and forged scopes', () => {
  const ownTenantId = '028e6a68-a9db-4055-974c-1e05bfe94b0f'
  const otherTenantId = '7529f951-938e-4e2c-ac0d-316c136ae1f9'

  assert.equal(resolveTenantReadTargetId({ effectiveTenantId: null, isPlatformSuper: true }), null)
  assert.equal(
    resolveTenantReadTargetId({
      effectiveTenantId: null,
      requestedTenantId: otherTenantId,
      isPlatformSuper: true
    }),
    otherTenantId
  )
  assert.equal(
    resolveTenantReadTargetId({ effectiveTenantId: otherTenantId, isPlatformSuper: true }),
    otherTenantId
  )
  assert.equal(
    resolveTenantReadTargetId({
      effectiveTenantId: otherTenantId,
      requestedTenantId: ownTenantId,
      isPlatformSuper: true
    }),
    undefined
  )
  assert.equal(
    resolveTenantReadTargetId({ effectiveTenantId: ownTenantId, isPlatformSuper: false }),
    ownTenantId
  )
  assert.equal(
    resolveTenantReadTargetId({
      effectiveTenantId: ownTenantId,
      requestedTenantId: otherTenantId,
      isPlatformSuper: false
    }),
    undefined
  )
})

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
