<template>
  <ElDialog
    ref="dialogRef"
    :model-value="visible"
    v-bind="dialogBindings"
    :class="['art-dialog', dialogClass]"
    @update:model-value="handleModelValueChange"
    @open="handleOpenedStart"
    @opened="handleOpened"
    @close="handleClosedStart"
    @closed="handleClosed"
    @open-auto-focus="emit('open-auto-focus')"
    @close-auto-focus="emit('close-auto-focus')"
  >
    <template v-if="$slots.header || hasSubtitle" #header="{ titleId, titleClass }">
      <slot v-if="$slots.header" name="header" :data="openData" :api="exposedApi" />
      <span v-else :id="titleId" :class="titleClass">{{ dialogTitle }}</span>
      <div v-if="hasSubtitle" class="art-dialog__subtitle">
        <slot name="subtitle" :data="openData" :api="exposedApi">
          {{ dialogSubtitle }}
        </slot>
      </div>
    </template>

    <ElScrollbar
      v-if="shouldUseScrollbar"
      v-loading="contentLoading"
      ref="scrollbarRef"
      :height="normalizedContentHeight"
      :max-height="normalizedContentMaxHeight"
      :always="options.scrollbarAlways"
      :native="options.nativeScrollbar"
      :element-loading-text="options.loadingText"
      :element-loading-background="options.loadingBackground"
      :element-loading-custom-class="options.loadingCustomClass"
      class="art-dialog__scrollbar"
    >
      <div class="art-dialog__content">
        <component
          :is="options.content"
          v-if="options.content"
          v-bind="options.contentProps"
          :data="openData"
          :dialog-api="exposedApi"
        />
        <slot v-else :data="openData" :loading="contentLoading" :api="exposedApi" />
      </div>
    </ElScrollbar>

    <div
      v-else
      v-loading="contentLoading"
      :element-loading-text="options.loadingText"
      :element-loading-background="options.loadingBackground"
      :element-loading-custom-class="options.loadingCustomClass"
      class="art-dialog__content"
    >
      <component
        :is="options.content"
        v-if="options.content"
        v-bind="options.contentProps"
        :data="openData"
        :dialog-api="exposedApi"
      />
      <slot v-else :data="openData" :loading="contentLoading" :api="exposedApi" />
    </div>

    <template v-if="options.showFooter" #footer>
      <slot name="footer" :data="openData" :loading="confirmLoading" :api="exposedApi">
        <div class="art-dialog__footer" :class="{ 'has-left': $slots['footer-left'] }">
          <div v-if="$slots['footer-left']" class="art-dialog__footer-left">
            <slot name="footer-left" :data="openData" :loading="confirmLoading" :api="exposedApi" />
          </div>
          <div class="art-dialog__footer-actions">
            <ElButton
              v-if="options.showCancelButton"
              :disabled="contentLoading || confirmLoading"
              @click="() => handleClose()"
            >
              {{ options.cancelText }}
            </ElButton>
            <ElButton
              v-if="options.showConfirmButton"
              type="primary"
              :loading="confirmLoading"
              :disabled="contentLoading || options.confirmDisabled"
              @click="handleConfirm"
            >
              {{ options.confirmText }}
            </ElButton>
          </div>
        </div>
      </slot>
    </template>
  </ElDialog>
</template>

<script setup lang="ts" generic="T = Record<string, any>">
  import type { Component } from 'vue'
  import type { DialogInstance, DialogPropsPublic, ScrollbarInstance } from 'element-plus'
  import type { ArtDialogExpose, ArtDialogOptions, ArtScrollOptions } from './types'
  import { mergeOverlayRecords, useArtOverlay } from '@/hooks/core/useArtOverlay'

  defineOptions({
    name: 'ArtDialog',
    inheritAttrs: false
  })

  interface ArtDialogProps<TData = Record<string, any>> extends Partial<
    Omit<DialogPropsPublic, 'modelValue' | 'title' | 'width'>
  > {
    title?: string
    subtitle?: string
    width?: string | number
    fullscreen?: boolean
    loading?: boolean
    loadingText?: string
    loadingBackground?: string
    loadingCustomClass?: string
    contentHeight?: string | number
    contentMaxHeight?: string | number
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
    dialogProps?: ArtDialogOptions<TData>['dialogProps']
    onOpen?: ArtDialogOptions<TData>['onOpen']
    onConfirm?: ArtDialogOptions<TData>['onConfirm']
    onClose?: ArtDialogOptions<TData>['onClose']
    onReset?: ArtDialogOptions<TData>['onReset']
  }

  const props = withDefaults(defineProps<ArtDialogProps<T>>(), {
    title: '',
    subtitle: '',
    width: '50%',
    fullscreen: false,
    loading: false,
    loadingText: '',
    loadingBackground: '',
    loadingCustomClass: '',
    contentHeight: undefined,
    contentMaxHeight: undefined,
    showFooter: true,
    showCancelButton: true,
    showConfirmButton: true,
    cancelText: '取消',
    confirmText: '确定',
    confirmDisabled: false,
    autoClose: true,
    resetOnClose: true,
    closeOnConfirmError: false,
    scrollbarAlways: false,
    nativeScrollbar: false
  })

  const emit = defineEmits<{
    open: [data: T]
    opened: [data: T]
    close: [data: T]
    closed: []
    confirm: [data: T]
    reset: []
    error: [error: unknown]
    'open-auto-focus': []
    'close-auto-focus': []
  }>()

  const attrs = useAttrs()
  const slots = useSlots()
  const dialogRef = shallowRef<DialogInstance>()
  const scrollbarRef = shallowRef<ScrollbarInstance>()

  const getDefaultOptions = (): ArtDialogOptions<T> => ({
    title: props.title,
    subtitle: props.subtitle,
    width: props.width,
    fullscreen: props.fullscreen,
    loading: props.loading,
    loadingText: props.loadingText,
    loadingBackground: props.loadingBackground,
    loadingCustomClass: props.loadingCustomClass,
    contentHeight: props.contentHeight,
    contentMaxHeight: props.contentMaxHeight,
    showFooter: props.showFooter,
    showCancelButton: props.showCancelButton,
    showConfirmButton: props.showConfirmButton,
    cancelText: props.cancelText,
    confirmText: props.confirmText,
    confirmDisabled: props.confirmDisabled,
    autoClose: props.autoClose,
    resetOnClose: props.resetOnClose,
    closeOnConfirmError: props.closeOnConfirmError,
    scrollbarAlways: props.scrollbarAlways,
    nativeScrollbar: props.nativeScrollbar,
    content: props.content,
    contentProps: props.contentProps,
    dialogProps: props.dialogProps,
    onOpen: props.onOpen,
    onConfirm: props.onConfirm,
    onClose: props.onClose,
    onReset: props.onReset
  })

  const mergeOptions = (
    base: ArtDialogOptions<T>,
    override: Partial<ArtDialogOptions<T>> = {}
  ): ArtDialogOptions<T> => {
    return {
      ...base,
      ...override,
      contentProps: mergeOverlayRecords(base.contentProps, override.contentProps),
      dialogProps: mergeOverlayRecords(base.dialogProps, override.dialogProps)
    }
  }

  let exposedApi!: ArtDialogExpose<T>
  const overlay = useArtOverlay<T, ArtDialogExpose<T>, ArtDialogOptions<T>>({
    getDefaultOptions,
    mergeOptions,
    getApi: () => exposedApi,
    emitConfirm: (data) => {
      if (!props.onConfirm || options.value.onConfirm !== props.onConfirm) emit('confirm', data)
    },
    emitReset: () => {
      if (!props.onReset || options.value.onReset !== props.onReset) emit('reset')
    },
    emitError: (error) => emit('error', error)
  })

  const {
    visible,
    loading: contentLoading,
    confirmLoading,
    openData,
    options,
    handleOpen,
    handleClose,
    handleConfirm,
    handleReset,
    handleModelValueChange,
    setLoading,
    setConfirmLoading,
    setOptions,
    setData,
    updateData,
    getData
  } = overlay

  const normalizeSize = (value?: string | number) => {
    return typeof value === 'number' ? `${value}px` : value
  }

  const normalizedContentHeight = computed(() => {
    const height = options.value.contentHeight
    return normalizeSize(height)
  })

  const normalizedContentMaxHeight = computed(() => {
    return normalizeSize(options.value.contentMaxHeight ?? options.value.contentHeight)
  })

  const shouldUseScrollbar = computed(() => {
    return Boolean(normalizedContentHeight.value || normalizedContentMaxHeight.value)
  })

  const dialogClass = computed(() => [
    attrs.class,
    (options.value.dialogProps as Record<string, unknown> | undefined)?.class
  ])

  const dialogTitle = computed(() => String(options.value.title ?? attrs.title ?? ''))
  const dialogSubtitle = computed(() => String(options.value.subtitle ?? ''))
  const hasSubtitle = computed(() => Boolean(slots.subtitle || dialogSubtitle.value))

  watch(
    () => props.loading,
    (value) => setLoading(value)
  )

  const dialogBindings = computed<Record<string, unknown>>(() => {
    const runtimeProps = options.value.dialogProps ?? {}
    const inheritedAttrs = { ...attrs } as Record<string, unknown>
    delete inheritedAttrs.class
    const runtimeBindings = { ...runtimeProps }
    delete runtimeBindings.class
    delete inheritedAttrs.modelValue
    delete inheritedAttrs['onUpdate:modelValue']
    delete inheritedAttrs.onOpen
    delete inheritedAttrs.onOpened
    delete inheritedAttrs.onClose
    delete inheritedAttrs.onClosed
    delete inheritedAttrs.onOpenAutoFocus
    delete inheritedAttrs.onCloseAutoFocus

    return {
      alignCenter: true,
      destroyOnClose: true,
      draggable: true,
      ...inheritedAttrs,
      ...runtimeBindings,
      title: dialogTitle.value,
      width: options.value.width ?? inheritedAttrs.width ?? '50%',
      fullscreen: Boolean(options.value.fullscreen)
    }
  })

  const getDialogInstance = () => dialogRef.value

  const scrollTo = (scrollOptions: ArtScrollOptions) => {
    scrollbarRef.value?.scrollTo(scrollOptions as never)
  }

  const handleOpenedStart = () => {
    if (!props.onOpen || options.value.onOpen !== props.onOpen) emit('open', openData.value)
  }
  const handleOpened = () => emit('opened', openData.value)
  const handleClosedStart = () => {
    if (!props.onClose || options.value.onClose !== props.onClose) emit('close', openData.value)
  }

  const handleClosed = () => {
    overlay.handleClosed()
    emit('closed')
  }

  exposedApi = {
    visible: readonly(visible),
    loading: readonly(contentLoading),
    confirmLoading: readonly(confirmLoading),
    data: readonly(openData) as Readonly<Ref<T>>,
    options: readonly(options) as Readonly<Ref<ArtDialogOptions<T>>>,
    dialogRef: readonly(dialogRef),
    scrollbarRef: readonly(scrollbarRef),
    handleOpen,
    handleClose,
    handleConfirm,
    handleReset,
    setLoading,
    setConfirmLoading,
    setOptions,
    setData,
    updateData,
    getData,
    getDialogInstance,
    scrollTo
  } as unknown as ArtDialogExpose<T>

  defineExpose(exposedApi)
</script>

<style scoped lang="scss">
  :deep(.art-dialog) {
    max-width: calc(100vw - 32px);
  }

  .art-dialog {
    &__content {
      min-height: 1px;
    }

    &__subtitle {
      margin: 0 0 16px;
      font-size: 14px;
      line-height: 22px;
      color: var(--el-text-color-secondary);
    }

    &__scrollbar {
      width: 100%;

      :deep(.el-scrollbar__view) {
        padding-right: 4px;
      }
    }

    &__footer {
      display: flex;
      gap: 0;
      align-items: center;
      justify-content: flex-end;
      width: 100%;

      &.has-left {
        justify-content: space-between;
      }
    }

    &__footer-left {
      min-width: 0;
      overflow: hidden;
      font-size: 14px;
      color: var(--el-text-color-secondary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    &__footer-actions {
      display: flex;
      flex: none;
    }
  }
</style>
