import assert from 'node:assert/strict'
import test from 'node:test'
import { resolveHostedApplicationCodes } from '../../src/config/application'

test('platform host aggregates every application granted to the current user', () => {
  assert.deepEqual(
    resolveHostedApplicationCodes('platform', [
      { code: 'vms' },
      { code: 'platform' },
      { code: 'hr' },
      { code: 'tms' }
    ]),
    ['platform', 'hr', 'tms', 'vms']
  )
})

test('standalone application only requests its own menu contract', () => {
  assert.deepEqual(resolveHostedApplicationCodes('vms', [{ code: 'platform' }, { code: 'hr' }]), [
    'vms'
  ])
})

test('standalone TMS is not mistaken for the platform host', () => {
  assert.deepEqual(resolveHostedApplicationCodes('tms', [{ code: 'platform' }]), ['tms'])
})
