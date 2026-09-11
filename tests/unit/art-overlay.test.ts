import assert from 'node:assert/strict'
import test from 'node:test'
import { useArtOverlay, type ArtOverlayOptions } from '../../src/hooks/core/useArtOverlay'

interface TestData {
  id?: string
}

type TestOptions = ArtOverlayOptions<TestData, { setLoading: (value: boolean) => void }>

const createOverlay = (emitError: (error: unknown) => void = () => undefined) => {
  let setLoading: (value: boolean) => void = () => undefined
  const overlay = useArtOverlay<TestData, { setLoading: (value: boolean) => void }, TestOptions>({
    getDefaultOptions: () => ({ autoClose: true, resetOnClose: true }),
    mergeOptions: (base, override) => ({ ...base, ...override }),
    getApi: () => ({ setLoading }),
    emitConfirm: () => undefined,
    emitReset: () => undefined,
    emitError
  })
  setLoading = overlay.setLoading
  return overlay
}

test('closing an overlay invalidates a pending open callback and suppresses its stale error', async () => {
  const errors: unknown[] = []
  const overlay = createOverlay((error) => errors.push(error))
  let rejectOpen: ((error: Error) => void) | undefined

  const opening = overlay.handleOpen(
    { id: 'first' },
    {
      onOpen: () =>
        new Promise<void>((_resolve, reject) => {
          rejectOpen = reject
        })
    }
  )
  await Promise.resolve()
  await overlay.handleClose(true)
  rejectOpen?.(new Error('stale load failed'))
  await opening

  assert.equal(overlay.visible.value, false)
  assert.deepEqual(errors, [])
})

test('confirm locking prevents duplicate side effects while a submit is pending', async () => {
  const overlay = createOverlay()
  let submitCount = 0
  let finishSubmit: (() => void) | undefined

  await overlay.handleOpen(
    { id: 'submit' },
    {
      onConfirm: () =>
        new Promise<void>((resolve) => {
          submitCount += 1
          finishSubmit = resolve
        })
    }
  )
  const first = overlay.handleConfirm()
  const second = await overlay.handleConfirm()
  finishSubmit?.()

  assert.equal(second, false)
  assert.equal(await first, true)
  assert.equal(submitCount, 1)
})
