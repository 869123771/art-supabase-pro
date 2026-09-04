import assert from 'node:assert/strict'
import test from 'node:test'
import {
  mapApplicationViewModules,
  registerApplicationViewModules,
  resolveHostedApplicationCode
} from '../../src/router/core/ComponentLoader'

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
