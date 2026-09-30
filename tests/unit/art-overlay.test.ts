import assert from 'node:assert/strict'
import test from 'node:test'
import { useArtOverlay, type ArtOverlayOptions } from '../../src/hooks/core/useArtOverlay'

interface TestData {
  id?: string
}

type TestOptions = ArtOverlayOptions<TestData, { setLoading: (value: boolean) => void }>

const createOverlay = (
  emitError: (error: unknown) => void = () => undefined,
  onConfirmRejected?: () => void
) => {
  let setLoading: (value: boolean) => void = () => undefined
  const overlay = useArtOverlay<TestData, { setLoading: (value: boolean) => void }, TestOptions>({
    getDefaultOptions: () => ({ autoClose: true, resetOnClose: true }),
    mergeOptions: (base, override) => ({ ...base, ...override }),
    getApi: () => ({ setLoading }),
    emitConfirm: () => undefined,
    emitReset: () => undefined,
    emitError,
    onConfirmRejected
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

test('invalid confirmation requests field focus and leaves the overlay available for correction', async () => {
  let focusRequests = 0
  const overlay = createOverlay(undefined, () => {
    focusRequests += 1
  })
  await overlay.handleOpen({}, { onConfirm: () => false })

  assert.equal(await overlay.handleConfirm(), false)
  assert.equal(focusRequests, 1)
  assert.equal(overlay.visible.value, true)
  assert.equal(overlay.confirmLoading.value, false)
})

test('rejected validation requests focus unless the overlay closes on error', async () => {
  let focusRequests = 0
  const errors: unknown[] = []
  const overlay = createOverlay(
    (error) => errors.push(error),
    () => {
      focusRequests += 1
    }
  )
  const failure = new Error('invalid form')
  const onConfirm = () => {
    throw failure
  }
  await overlay.handleOpen({}, { onConfirm })
  assert.equal(await overlay.handleConfirm(), false)
  assert.equal(focusRequests, 1)
  assert.equal(overlay.visible.value, true)

  overlay.setOptions({ closeOnConfirmError: true })
  assert.equal(await overlay.handleConfirm(), false)
  assert.equal(focusRequests, 1)
  assert.equal(overlay.visible.value, false)
  assert.equal(overlay.confirmLoading.value, false)
  assert.deepEqual(errors, [failure, failure])
})
