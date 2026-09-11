import assert from 'node:assert/strict'
import test from 'node:test'
import {
  isLazyCapabilityAsset,
  isLazyCapabilityStyle,
  shouldPreloadHtmlDependency
} from '../../scripts/bundle-boundaries'

test('heavy capabilities remain outside ordinary application chunk budgets', () => {
  for (const asset of [
    'assets/3d-runtime.123.js',
    'assets/exceljs.123.js',
    'assets/file-viewer.123.js',
    'assets/monaco.123.js'
  ]) {
    assert.equal(isLazyCapabilityAsset(asset), true, asset)
    assert.equal(shouldPreloadHtmlDependency(asset), false, asset)
  }

  assert.equal(isLazyCapabilityAsset('assets/dashboard.123.js'), false)
  assert.equal(shouldPreloadHtmlDependency('assets/framework.123.js'), true)
})

test('only known lazy renderer styles are excluded from application CSS totals', () => {
  assert.equal(isLazyCapabilityStyle('assets/art-file-viewer.123.css'), true)
  assert.equal(isLazyCapabilityStyle('vendor/pdf/viewer.css'), true)
  assert.equal(isLazyCapabilityStyle('assets/dashboard.123.css'), false)
})
