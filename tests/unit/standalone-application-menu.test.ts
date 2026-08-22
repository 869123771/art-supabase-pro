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
      },
      {
        name: 'BasicInfo',
        path: '/vms/basic-info',
        meta: { title: '基础信息管理' },
        children: [
          {
            name: 'Parts',
            path: '/vms/basic-info/parts',
            component: '/vms/basic-info/parts/index',
            meta: { title: '配件管理' }
          }
        ]
      }
    ]
  }
]

test('keeps application directories in the platform panoramic menu', () => {
  assert.deepEqual(flattenStandaloneApplicationMenu(vmsMenu, 'platform'), vmsMenu)
})

test('promotes application children without changing stable route paths in standalone mode', () => {
  const flattened = flattenStandaloneApplicationMenu(vmsMenu, 'vms')

  assert.equal(flattened.length, 2)
  assert.equal(flattened[0]?.meta.title, '车辆查询')
  assert.equal(flattened[0]?.path, '/vms/vehicle-query')
  assert.equal(flattened[1]?.meta.title, '基础信息管理')
  assert.equal(flattened[1]?.component, '/index/index')
})
