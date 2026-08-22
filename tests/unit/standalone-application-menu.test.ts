import assert from 'node:assert/strict'
import test from 'node:test'
import type { AppRouteRecord } from '../../src/types/router'
import { flattenStandaloneApplicationMenu } from '../../src/router/core/applicationMenu'

const vmsMenu: AppRouteRecord[] = [
  {
    name: 'VmsRoot',
    path: '/vms',
    component: '/index/index',
    meta: { title: 'VMS车辆管理' },
    children: [
      {
        name: 'VehicleQuery',
        path: '/vms/vehicle-query',
        component: '/vms/vehicle-query/index',
        meta: { title: '车辆查询' }
      }
    ]
  }
]

test('keeps application directories in the platform panoramic menu', () => {
  assert.deepEqual(flattenStandaloneApplicationMenu(vmsMenu, 'platform'), vmsMenu)
})

test('promotes application children without changing stable route paths in standalone mode', () => {
  const flattened = flattenStandaloneApplicationMenu(vmsMenu, 'vms')

  assert.equal(flattened.length, 1)
  assert.equal(flattened[0]?.meta.title, '车辆查询')
  assert.equal(flattened[0]?.path, '/vms/vehicle-query')
})
