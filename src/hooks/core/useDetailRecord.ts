import { ref, shallowRef } from 'vue'

interface DetailResult<T> {
  data: T | null | undefined
  error?: unknown
}

/** Keep detail identity and retry available when a read fails or returns no record. */
export function useDetailRecord<T>(
  fetchDetail: (id: string) => Promise<DetailResult<T>>,
  failureMessage: string
) {
  const detail = shallowRef<T>()
  const activeId = ref('')
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)
  let requestVersion = 0

  async function loadDetail(id: string): Promise<void> {
    const version = ++requestVersion
    activeId.value = id
    loading.value = true
    loadError.value = null
    try {
      const result = await fetchDetail(id)
      if (result.error) throw result.error
      if (version === requestVersion) detail.value = result.data ?? undefined
    } catch (cause) {
      if (version !== requestVersion) return
      detail.value = undefined
      loadError.value = new Error(failureMessage, { cause })
    } finally {
      if (version === requestVersion) loading.value = false
    }
  }

  function openDetail(id: string, seed?: T): void {
    requestVersion += 1
    activeId.value = id
    detail.value = seed
    loading.value = false
    loadError.value = null
  }

  function retryLoad(): Promise<void> {
    return activeId.value ? loadDetail(activeId.value) : Promise.resolve()
  }

  return { detail, activeId, loading, loadError, loadDetail, openDetail, retryLoad }
}
