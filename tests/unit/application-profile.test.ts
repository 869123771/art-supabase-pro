import assert from 'node:assert/strict'
import test from 'node:test'
import {
  APPLICATION_CODES,
  APPLICATION_PROFILES,
  resolveApplicationCode
} from '../../src/config/application'

test('resolves supported independent application codes', () => {
  for (const code of APPLICATION_CODES) {
    assert.equal(resolveApplicationCode(code.toUpperCase()), code)
    assert.equal(APPLICATION_PROFILES[code].code, code)
    assert.match(APPLICATION_PROFILES[code].defaultPath, /^\//)
  }
})

test('falls back to the platform for missing or invalid application codes', () => {
  assert.equal(resolveApplicationCode(undefined), 'platform')
  assert.equal(resolveApplicationCode(''), 'platform')
  assert.equal(resolveApplicationCode('unknown-module'), 'platform')
})
