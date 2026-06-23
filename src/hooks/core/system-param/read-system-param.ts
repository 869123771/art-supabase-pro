import { fetchSystemParamByKey } from '@/api/system-manage'

type SystemParamItem = Api.SystemManage.SystemParamItem

interface ReadSystemParamOptions<TValue> {
  key: string
  fallback: TValue
  parse: (value: string, row: SystemParamItem) => TValue | undefined
}

const configuredValueCache = new Map<string, unknown>()
const pendingLoadCache = new Map<string, Promise<unknown>>()

export const readSystemParamValue = async <TValue>(
  options: ReadSystemParamOptions<TValue>
): Promise<TValue> => {
  const cachedValue = configuredValueCache.get(options.key)
  if (cachedValue !== undefined) {
    return cachedValue as TValue
  }

  const pendingLoad = pendingLoadCache.get(options.key) as Promise<TValue> | undefined
  if (pendingLoad) {
    return pendingLoad
  }

  const nextLoad = fetchSystemParamByKey(options.key)
    .then(({ data }) => {
      const parsedValue = data ? options.parse(data.paramValue, data) : undefined
      if (parsedValue !== undefined) {
        configuredValueCache.set(options.key, parsedValue)
      }
      return parsedValue ?? options.fallback
    })
    .catch(() => options.fallback)
    .finally(() => {
      pendingLoadCache.delete(options.key)
    })

  pendingLoadCache.set(options.key, nextLoad)
  return nextLoad
}
