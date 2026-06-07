import type { Component, Ref, ShallowRef } from 'vue'

export type Awaitable<T> = T | Promise<T>
export type ArtScrollOptions =
  | number
  | {
      top?: number
      left?: number
      behavior?: 'auto' | 'smooth'
    }

export interface ArtOverlayOptions<TData, TApi> {
  contentHeight?: string | number
  showFooter?: boolean
  showCancelButton?: boolean
  showConfirmButton?: boolean
  cancelText?: string
  confirmText?: string
  confirmDisabled?: boolean
  autoClose?: boolean
  resetOnClose?: boolean
  closeOnConfirmError?: boolean
  scrollbarAlways?: boolean
  nativeScrollbar?: boolean
  content?: Component
  contentProps?: Record<string, unknown>
  onOpen?: (data: TData, api: TApi) => Awaitable<void>
  onConfirm?: (data: TData, api: TApi) => Awaitable<boolean | void>
  onClose?: (data: TData, api: TApi) => Awaitable<boolean | void>
  onReset?: (api: TApi) => void
}

export interface ArtOverlayExpose<TData, TOptions> {
  visible: Readonly<Ref<boolean>>
  loading: Readonly<Ref<boolean>>
  confirmLoading: Readonly<Ref<boolean>>
  data: Readonly<Ref<TData>>
  options: Readonly<Ref<TOptions>>
  handleClose: (force?: boolean) => Promise<boolean>
  handleConfirm: () => Promise<boolean>
  handleReset: () => void
  setLoading: (value: boolean) => void
  setConfirmLoading: (value: boolean) => void
  setOptions: (options: Partial<TOptions>) => void
  setData: (data: TData) => void
  updateData: (data: Partial<TData>) => void
  getData: () => TData
}

interface UseArtOverlayConfig<TData, TOptions, TApi> {
  getDefaultOptions: () => TOptions
  mergeOptions: (base: TOptions, override?: Partial<TOptions>) => TOptions
  getApi: () => TApi
  emitConfirm: (data: TData) => void
  emitReset: () => void
  emitError: (error: unknown) => void
}

export const cloneOverlayData = <TValue>(value: TValue): TValue => {
  if (value === undefined || value === null) return value
  if (typeof structuredClone === 'function') {
    try {
      return structuredClone(toRaw(value))
    } catch {
      // Component instances and functions intentionally remain by reference.
    }
  }
  if (Array.isArray(value)) return value.map((item) => cloneOverlayData(item)) as TValue
  if (typeof value === 'object') return { ...(toRaw(value) as object) } as TValue
  return value
}

export const mergeOverlayRecords = <T extends Record<string, unknown> | undefined>(
  base: T,
  override: T
): T => {
  if (!base && !override) return undefined as T
  return { ...(base ?? {}), ...(override ?? {}) } as T
}

export const useArtOverlay = <TData, TApi, TOptions extends ArtOverlayOptions<TData, TApi>>(
  config: UseArtOverlayConfig<TData, TOptions, TApi>
) => {
  const visible = ref(false)
  const loading = ref(false)
  const confirmLoading = ref(false)
  const openData = ref<TData>({} as TData) as Ref<TData>
  const initialData = shallowRef<TData>({} as TData) as ShallowRef<TData>
  const options = ref<TOptions>(config.getDefaultOptions()) as Ref<TOptions>
  const closePending = ref(false)
  let openSequence = 0

  const setLoading = (value: boolean) => {
    loading.value = value
  }

  const setConfirmLoading = (value: boolean) => {
    confirmLoading.value = value
  }

  const setOptions = (value: Partial<TOptions>) => {
    options.value = config.mergeOptions(options.value, value)
  }

  const setData = (data: TData) => {
    openData.value = data
  }

  const updateData = (data: Partial<TData>) => {
    if (openData.value && typeof openData.value === 'object') {
      openData.value = { ...openData.value, ...data }
    }
  }

  const getData = () => openData.value

  const handleReset = () => {
    openData.value = cloneOverlayData(initialData.value)
    loading.value = false
    confirmLoading.value = false
    options.value.onReset?.(config.getApi())
    config.emitReset()
  }

  const handleOpen = async (data = {} as TData, openOptions: Partial<TOptions> = {}) => {
    const sequence = ++openSequence
    options.value = config.mergeOptions(config.getDefaultOptions(), openOptions)
    initialData.value = cloneOverlayData(data)
    openData.value = cloneOverlayData(data)
    closePending.value = false
    visible.value = true

    await nextTick()
    if (sequence !== openSequence || !visible.value) return

    try {
      await options.value.onOpen?.(openData.value, config.getApi())
    } catch (error) {
      config.emitError(error)
    }
  }

  const handleClose = async (force = false): Promise<boolean> => {
    if (closePending.value || !visible.value) return false
    closePending.value = true

    try {
      if (!force && options.value.onClose) {
        const canClose = await options.value.onClose(openData.value, config.getApi())
        if (canClose === false) return false
      }

      visible.value = false
      return true
    } catch (error) {
      config.emitError(error)
      return false
    } finally {
      closePending.value = false
    }
  }

  const handleConfirm = async (): Promise<boolean> => {
    if (confirmLoading.value || loading.value || closePending.value) return false

    config.emitConfirm(openData.value)
    if (!options.value.onConfirm) {
      if (options.value.autoClose) await handleClose()
      return true
    }

    confirmLoading.value = true
    try {
      const result = await options.value.onConfirm(openData.value, config.getApi())
      if (result !== false && options.value.autoClose) await handleClose()
      return result !== false
    } catch (error) {
      config.emitError(error)
      if (options.value.closeOnConfirmError) await handleClose(true)
      return false
    } finally {
      confirmLoading.value = false
    }
  }

  const handleModelValueChange = (value: boolean) => {
    if (value) {
      visible.value = true
      return
    }
    void handleClose()
  }

  const handleClosed = () => {
    visible.value = false
    closePending.value = false
    if (options.value.resetOnClose) handleReset()
  }

  return {
    visible,
    loading,
    confirmLoading,
    openData,
    options,
    handleOpen,
    handleClose,
    handleConfirm,
    handleReset,
    handleModelValueChange,
    handleClosed,
    setLoading,
    setConfirmLoading,
    setOptions,
    setData,
    updateData,
    getData
  }
}
