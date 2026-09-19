import assert from 'node:assert/strict'
import test from 'node:test'
import { defineComponent } from 'vue'
import { useLazyComponent } from '../../src/hooks/core/useLazyComponent'

test('lazy component loads once and remains reusable', async () => {
  const expected = defineComponent({ name: 'LazyTestComponent' })
  let loadCount = 0
  const lazyComponent = useLazyComponent(async () => {
    loadCount += 1
    return { default: expected }
  })

  assert.equal(lazyComponent.component.value, undefined)
  await lazyComponent.load()
  await lazyComponent.load()

  assert.equal(lazyComponent.component.value, expected)
  assert.equal(loadCount, 1)
})
