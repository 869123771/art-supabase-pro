import assert from 'node:assert/strict'
import test from 'node:test'
import {
  createCachedRouteLoader,
  mapApplicationViewModules,
  registerApplicationViewModules,
  resolveHostedApplicationCode
} from '../../src/router/core/ComponentLoader'

test('reuses an in-flight route component request and retries after a failure', async () => {
  let calls = 0
  let shouldFail = true
  const component = { name: 'CachedRouteComponent' }
  const loader = createCachedRouteLoader(async () => {
    calls += 1
    if (shouldFail) throw new Error('temporary route load failure')
    return { default: component }
  })

  const firstResults = await Promise.allSettled([loader(), loader()])
  assert.equal(calls, 1)
  assert.equal(
    firstResults.every((result) => result.status === 'rejected'),
    true
  )

  shouldFail = false
  const [firstRetry, secondRetry] = await Promise.all([loader(), loader()])
  assert.equal(calls, 2)
  assert.equal(firstRetry, component)
  assert.equal(secondRetry, component)
})

test('maps flattened child views behind the stable application route prefix', () => {
  const loader = async () => ({ default: {} })
  const mapped = mapApplicationViewModules('vms', '../../../modules/art-supabase-vms/src/views', {
    '../../../modules/art-supabase-vms/src/views/archive-manage/vehicle-archive-manage/index.vue':
      loader
  })

  assert.equal(mapped['../../views/vms/archive-manage/vehicle-archive-manage/index.vue'], loader)
})

test('accepts independently built application view registrations before bootstrap', () => {
  const loader = async () => ({ default: {} })
  const registered = registerApplicationViewModules('vms', './views', {
    './views/vehicle-query/index.vue': loader
  })

  assert.equal(registered['../../views/vms/vehicle-query/index.vue'], loader)
})

test('identifies missing business application pages for the host fallback', () => {
  assert.equal(resolveHostedApplicationCode('/vms/vehicle-query'), 'vms')
  assert.equal(resolveHostedApplicationCode('/fms/account-set'), 'fms')
  assert.equal(resolveHostedApplicationCode('/mdm/workbench'), 'mdm')
  assert.equal(resolveHostedApplicationCode('/mes/workbench'), 'mes')
  assert.equal(resolveHostedApplicationCode('/wms/workbench'), 'wms')
  assert.equal(resolveHostedApplicationCode('/system/user'), null)
  assert.equal(resolveHostedApplicationCode('/unknown/page'), null)
})
