import assert from 'node:assert/strict'
import test from 'node:test'
import { TableCache } from '../../src/utils/table/tableCache'
import { createSmartDebounce, defaultResponseAdapter } from '../../src/utils/table/tableUtils'

test('cache enforces capacity and evicts least recent rather than least frequent entries', () => {
  const cache = new TableCache<number>(1000, 2)
  cache.set('a', [1], {})
  for (let i = 0; i < 10; i++) cache.get('a')
  cache.set('b', [2], {})
  cache.set('c', [3], {})
  assert.equal(cache.getStats().total, 2)
  assert.equal(cache.get('a'), null)
  assert.deepEqual(cache.get('b')?.data, [2])
  cache.set('d', [4], {})
  assert.equal(cache.get('c'), null)
  cache.set('b', [20], {})
  assert.equal(cache.getStats().total, 2)
  assert.deepEqual(cache.get('b')?.data, [20])
})

test('cache expires at the TTL boundary and removes expired entries before live ones', (t) => {
  t.mock.timers.enable({ apis: ['Date'], now: 1000 })
  const cache = new TableCache<number>(100, 2)
  cache.set('a', [], {})
  t.mock.timers.tick(50)
  cache.set('b', [], {})
  cache.get('a')
  t.mock.timers.tick(50)
  cache.set('c', [], {})
  assert.equal(cache.get('a'), null)
  assert.ok(cache.get('b'))
  assert.ok(cache.get('c'))
  t.mock.timers.tick(100)
  assert.equal(cache.cleanupExpired(), 2)
})

test('cache validates bounds, supports disabled caching, and accepts unknown parameters', () => {
  for (const capacity of [-1, 1.5, NaN, Infinity]) {
    assert.throws(() => new TableCache(100, capacity), RangeError)
  }
  for (const ttl of [-1, NaN, Infinity]) assert.throws(() => new TableCache(ttl), RangeError)
  const disabled = new TableCache(100, 0)
  disabled.set(null, [], {})
  assert.equal(disabled.getStats().total, 0)
  const cache = new TableCache()
  cache.set(null, [], {})
  assert.ok(cache.get(null))
})

test('cache tags are stable for reordered and structured filters and match exactly', () => {
  const cache = new TableCache()
  cache.set({ size: 10, filter: { status: 'open' }, current: 1 }, [], {})
  cache.set({ current: 2, filter: { status: 'open' }, size: 10 }, [], {})
  cache.set({ size: 100, filter: { status: 'closed' } }, [], {})
  const first = cache.get({ size: 10, filter: { status: 'open' }, current: 1 })!
  const second = cache.get({ current: 2, filter: { status: 'open' }, size: 10 })!
  assert.deepEqual(first.tags, second.tags)
  assert.equal(cache.clearByTags(['pagination:10']), 2)
  assert.equal(cache.clearPagination(), 1)
})

test('cache keys isolate otherwise identical queries by tenant and permission scope', () => {
  const cache = new TableCache<number>()
  cache.set({ tenantId: 'tenant-a', permissionScope: 'tenant', current: 1 }, [1], {})
  cache.set({ tenantId: null, permissionScope: 'platform-all', current: 1 }, [2], {})

  assert.deepEqual(
    cache.get({ tenantId: 'tenant-a', permissionScope: 'tenant', current: 1 })?.data,
    [1]
  )
  assert.deepEqual(
    cache.get({ tenantId: null, permissionScope: 'platform-all', current: 1 })?.data,
    [2]
  )
  assert.equal(cache.get({ tenantId: 'tenant-b', permissionScope: 'tenant', current: 1 }), null)
})

test('response adapter handles null and preserves explicit empty lists and totals', () => {
  assert.deepEqual(defaultResponseAdapter({ data: null }), { records: [], total: 0 })
  assert.deepEqual(defaultResponseAdapter({ data: [], total: 12 }), { records: [], total: 12 })
  assert.deepEqual(defaultResponseAdapter({ records: [], total: 12, data: { list: [1] } }), {
    records: [],
    total: 12
  })
})

test('nested envelopes use the same field mapping and reject invalid pagination', () => {
  for (const field of ['list', 'data', 'records', 'items', 'result', 'rows']) {
    assert.deepEqual(
      defaultResponseAdapter({ page: 2, data: { [field]: [1], count: 8, page: 3, limit: 5 } }),
      {
        records: [1],
        total: 8,
        current: 2,
        size: 5
      }
    )
  }
  assert.deepEqual(defaultResponseAdapter({ data: { rows: [1] }, total: 9 }), {
    records: [1],
    total: 9
  })
  assert.deepEqual(defaultResponseAdapter({ rows: [1], total: NaN, current: -1, size: Infinity }), {
    records: [1],
    total: 1
  })
})

test('debounce coalesces callers and resolves every promise with the latest arguments', async () => {
  const calls: number[] = []
  const search = createSmartDebounce(async (value: number) => {
    calls.push(value)
    return value
  }, 1000)
  const first = search(1)
  const second = search(2)
  assert.equal(await search.flush(), 2)
  assert.deepEqual(await Promise.all([first, second]), [2, 2])
  assert.deepEqual(calls, [2])
  assert.equal(await search.flush(), undefined)
})

test('debounce cancellation settles callers without issuing work', async () => {
  const search = createSmartDebounce(async () => assert.fail('must not run'), 1000)
  const first = search()
  const second = search()
  search.cancel()
  assert.deepEqual(await Promise.all([first, second]), [undefined, undefined])
  assert.equal(await search.flush(), undefined)
})

test('older debounce completion cannot erase a queued batch', async () => {
  let complete!: (value: number) => void
  const search = createSmartDebounce(
    (value: number) =>
      value === 1
        ? new Promise<number>((resolve) => {
            complete = resolve
          })
        : Promise.resolve(value),
    1000
  )
  const first = search(1)
  const running = search.flush()
  const second = search(2)
  complete(1)
  assert.equal(await running, 1)
  assert.equal(await first, 1)
  assert.equal(await search.flush(), 2)
  assert.equal(await second, 2)
})

test('debounce rejects every waiter and flush with the original failure', async () => {
  const failure = new Error('failed')
  const search = createSmartDebounce(async () => {
    throw failure
  }, 1000)
  const first = assert.rejects(search(), (error) => error === failure)
  const second = assert.rejects(search(), (error) => error === failure)
  await assert.rejects(search.flush(), (error) => error === failure)
  await Promise.all([first, second])
})

test('debounce timer executes without needing flush', async () => {
  const search = createSmartDebounce(async (value: number) => value, 1)
  assert.deepEqual(await Promise.all([search(1), search(2)]), [2, 2])
})
