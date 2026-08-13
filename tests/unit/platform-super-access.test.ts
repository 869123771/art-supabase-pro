import assert from 'node:assert/strict'
import test from 'node:test'
import { hasPlatformSuperAccess } from '../../src/utils/platform-super-access'

const protectedProfile = {
  status: '1',
  userRoles: ['R_SUPER', 'R_ADMIN'],
  tenant: { builtinType: 'platform' as const }
}

test('explicit server capability takes precedence over the profile fallback', () => {
  assert.equal(hasPlatformSuperAccess({ ...protectedProfile, platformSuper: true }), true)
  assert.equal(hasPlatformSuperAccess({ ...protectedProfile, platformSuper: false }), false)
})

test('legacy sessions recover platform-super access from protected profile fields', () => {
  assert.equal(hasPlatformSuperAccess(protectedProfile), true)
})

test('fallback rejects incomplete, inactive, or tenant-local administrator profiles', () => {
  assert.equal(hasPlatformSuperAccess({ ...protectedProfile, status: '2' }), false)
  assert.equal(hasPlatformSuperAccess({ ...protectedProfile, userRoles: ['R_ADMIN'] }), false)
  assert.equal(
    hasPlatformSuperAccess({
      ...protectedProfile,
      tenant: { builtinType: 'public_register' }
    }),
    false
  )
})
