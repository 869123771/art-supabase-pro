/** Preserve input order; stop scheduling on failure and drain active work before rejecting. */
export async function mapWithConcurrency<TInput, TOutput>(
  items: readonly TInput[],
  concurrency: number,
  mapper: (item: TInput, index: number) => Promise<TOutput>
): Promise<TOutput[]> {
  if (!Number.isSafeInteger(concurrency) || concurrency < 1) {
    throw new RangeError('并发数必须是正安全整数')
  }
  if (items.length === 0) return []

  const workerCount = Math.min(concurrency, items.length)
  const results = new Array<TOutput>(items.length)
  let nextIndex = 0
  let failed = false
  let firstError: unknown

  const worker = async (): Promise<void> => {
    while (!failed && nextIndex < items.length) {
      const index = nextIndex
      nextIndex += 1
      try {
        results[index] = await mapper(items[index], index)
      } catch (error) {
        if (!failed) firstError = error
        failed = true
      }
    }
  }

  await Promise.all(Array.from({ length: workerCount }, () => worker()))
  if (failed) throw firstError
  return results
}
