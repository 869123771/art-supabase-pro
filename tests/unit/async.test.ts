import assert from 'node:assert/strict'
import test from 'node:test'
import { mapWithConcurrency } from '../../src/utils/async'

test('concurrent mapper rejects invalid limits instead of returning sparse results', async () => {
  for (const limit of [NaN, Infinity, 0, -1, 1.5]) {
    await assert.rejects(
      mapWithConcurrency([1], limit, async (item) => item),
      RangeError
    )
  }
})

test('concurrent mapper bounds active work and retains input order', async () => {
  let active = 0
  let maximum = 0
  const result = await mapWithConcurrency([3, 2, 1], 2, async (item, index) => {
    active++
    maximum = Math.max(maximum, active)
    await new Promise((resolve) => setTimeout(resolve, item))
    active--
    return `${index}:${item}`
  })
  assert.equal(maximum, 2)
  assert.deepEqual(result, ['0:3', '1:2', '2:1'])
  assert.deepEqual(await mapWithConcurrency([], 2, async (item) => item), [])
})

test('concurrent mapper stops scheduling after failure, retaining the original error', async () => {
  const failure = new Error('failed')
  const started: number[] = []
  let complete!: () => void
  const result = mapWithConcurrency([0, 1, 2, 3], 2, async (item) => {
    started.push(item)
    if (item === 0) throw failure
    await new Promise<void>((resolve) => {
      complete = resolve
    })
    return item
  })
  let settled = false
  const rejection = assert
    .rejects(result, (error) => error === failure)
    .then(() => {
      settled = true
    })
  await new Promise<void>((resolve) => setImmediate(resolve))
  assert.equal(settled, false, 'must wait for an active request before reporting failure')
  complete()
  await rejection
  assert.deepEqual(started, [0, 1])
})

test('concurrent mapper preserves the first failure after other active requests fail', async () => {
  const failure = new Error('first failure')
  let rejectSecond!: (error: Error) => void
  const result = mapWithConcurrency([0, 1, 2], 2, async (item) => {
    if (item === 0) throw failure
    return new Promise<number>((_resolve, reject) => {
      rejectSecond = reject
    })
  })
  const rejection = assert.rejects(result, (error) => error === failure)
  rejectSecond(new Error('later failure'))
  await rejection
})
