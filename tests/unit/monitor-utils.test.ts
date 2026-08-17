import assert from 'node:assert/strict'
import test from 'node:test'
import type { InTransitRecord } from '../../src/views/tms/in-transit-monitor/modules/monitor-types'
import {
  dedupeGeoPath,
  escapeHtml,
  estimateDistanceKm,
  getRoutePosition,
  resolveTransitStatus,
  splitRoutePath,
  toGeoCoord
} from '../../src/views/tms/in-transit-monitor/modules/monitor-utils'

test('toGeoCoord normalizes valid coordinates and rejects invalid ranges', () => {
  assert.deepEqual(toGeoCoord('120.1234567', '30.7654321'), [120.123457, 30.765432])
  assert.equal(toGeoCoord(181, 30), undefined)
  assert.equal(toGeoCoord(120, Number.NaN), undefined)
})

test('route helpers keep ordered unique points and split at current progress', () => {
  const path: Array<[number, number]> = [
    [100, 20],
    [101, 21],
    [101, 21],
    [102, 22],
    [103, 23]
  ]

  assert.deepEqual(dedupeGeoPath(path), [
    [100, 20],
    [101, 21],
    [102, 22],
    [103, 23]
  ])
  assert.deepEqual(getRoutePosition(path, 50), { coord: [101, 21] })
  assert.deepEqual(splitRoutePath(path, [101.5, 21.5], 50), {
    passedPath: [
      [100, 20],
      [101, 21],
      [101.5, 21.5]
    ],
    remainingPath: [
      [101.5, 21.5],
      [102, 22],
      [103, 23]
    ]
  })
})

test('resolveTransitStatus follows delayed, completed, and running precedence', () => {
  assert.equal(resolveTransitStatus({ status: 'transporting' } as InTransitRecord, true), 'delayed')
  assert.equal(resolveTransitStatus({ status: 'completed' } as InTransitRecord, false), 'arrived')
  assert.equal(
    resolveTransitStatus({ status: 'loading' } as InTransitRecord, false),
    'transporting'
  )
  assert.equal(resolveTransitStatus({ status: 'created' } as InTransitRecord, false), 'pending')
})

test('distance and marker escaping stay safe at external map boundaries', () => {
  assert.ok(estimateDistanceKm([120, 30], [121, 30]) > 90)
  assert.equal(escapeHtml('<img title="x">'), '&lt;img title=&quot;x&quot;&gt;')
})
