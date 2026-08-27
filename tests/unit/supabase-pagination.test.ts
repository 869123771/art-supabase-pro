import assert from 'node:assert/strict'
import test from 'node:test'
import { fetchAllRangePages, type SupabaseRange } from '../../src/utils/supabase/pagination'

test('collects every range until the final partial page', async () => {
  const source = ['A', 'B', 'C', 'D', 'E']
  const ranges: SupabaseRange[] = []

  const result = await fetchAllRangePages(
    async (range) => {
      ranges.push(range)
      return {
        data: source.slice(range.from, range.to + 1),
        error: null
      }
    },
    { pageSize: 2 }
  )

  assert.deepEqual(ranges, [
    { from: 0, to: 1 },
    { from: 2, to: 3 },
    { from: 4, to: 5 }
  ])
  assert.deepEqual(result, { data: source, error: null, total: source.length })
})

test('returns the original page error without exposing partial data', async () => {
  const expectedError = new Error('request failed')
  let callCount = 0

  const result = await fetchAllRangePages(
    async () => {
      callCount += 1
      return callCount === 1
        ? { data: ['A', 'B'], error: null }
        : { data: null, error: expectedError }
    },
    { pageSize: 2 }
  )

  assert.equal(callCount, 2)
  assert.equal(result.data, null)
  assert.equal(result.error, expectedError)
  assert.equal(result.total, 2)
})

test('rejects invalid page sizes before querying', async () => {
  await assert.rejects(
    fetchAllRangePages(async () => ({ data: [], error: null }), { pageSize: 0 }),
    /分页大小必须是正整数/
  )
})
