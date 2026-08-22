import assert from 'node:assert/strict'
import test from 'node:test'
import { resolveHostedApplicationCodes } from '../../src/config/application'

test('platform host aggregates every application granted to the current user', () => {
  assert.deepEqual(
    resolveHostedApplicationCodes('platform', [
      { code: 'vms' },
      { code: 'platform' },
      { code: 'hr' }
    ]),
    ['platform', 'hr', 'vms']
  )
})

test('standalone application only requests its own menu contract', () => {
  assert.deepEqual(resolveHostedApplicationCodes('vms', [{ code: 'platform' }, { code: 'hr' }]), [
    'vms'
  ])
})
