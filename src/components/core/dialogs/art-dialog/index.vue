<template>
  <ElDialog
    ref="dialogRef"
    :model-value="visible"
    v-bind="dialogBindings"
    :class="[
      'art-dialog',
      options.size ? `art-dialog--${options.size}` : '',
      dialogClass,
      { 'is-fullscreen-toggle-enabled': options.showFullscreenButton }
    ]"
    @update:model-value="handleModelValueChange"
    @open="handleOpenedStart"
    @opened="handleOpened"
    @close="handleClosedStart"
    @closed="handleClosed"
    @open-auto-focus="emit('open-auto-focus')"
    @close-auto-focus="emit('close-auto-focus')"
  >
    <template
      v-if="$slots.header || hasSubtitle || options.showFullscreenButton"
      #header="{ titleId, titleClass }"
    >
      <div class="art-dialog__header">
        <div class="art-dialog__header-main">
          <slot v-if="$slots.header" name="header" :data="openData" :api="exposedApi" />
          <span v-else :id="titleId" :class="titleClass">{{ dialogTitle }}</span>
          <div v-if="hasSubtitle" class="art-dialog__subtitle">
            <slot name="subtitle" :data="openData" :api="exposedApi">
              {{ dialogSubtitle }}
            </slot>
          </div>
        </div>
        <button
          v-if="options.showFullscreenButton"
          type="button"
          class="el-dialog__headerbtn art-dialog__fullscreen-button"
          :aria-label="fullscreenLabel"
          :title="fullscreenLabel"
          @click.stop="toggleFullscreen"
        >
          <ArtSvgIcon :icon="fullscreenIcon" class="art-dialog__action-icon" />
        </button>
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

<script setup lang="ts" generic="T = Record<string, unknown>">
  import type { DialogInstance, ScrollbarInstance } from 'element-plus'
  import type {
    ArtDialogEmits,
    ArtDialogExpose,
    ArtDialogOptions,
    ArtDialogProps,
    ArtDialogSlots,
    ArtScrollOptions
  } from './types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { mergeOverlayRecords, useArtOverlay } from '@/hooks/core/useArtOverlay'

  defineOptions({
    name: 'ArtDialog',
    inheritAttrs: false
  })

  const props = withDefaults(defineProps<ArtDialogProps<T>>(), {
    title: '',
    subtitle: '',
    width: undefined,
    size: undefined,
    fullscreen: false,
    showFullscreenButton: false,
    fullscreenText: '全屏',
    exitFullscreenText: '退出全屏',
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

  const emit = defineEmits<ArtDialogEmits<T>>()

  const DEFAULT_CONTENT_MAX_HEIGHT = 'min(70vh, calc(100vh - 200px))'

  const attrs = useAttrs()
  const slots = defineSlots<ArtDialogSlots<T>>()
  const dialogRef = shallowRef<DialogInstance>()
  const scrollbarRef = shallowRef<ScrollbarInstance>()

  const getDefaultOptions = (): ArtDialogOptions<T> => ({
    title: props.title,
    subtitle: props.subtitle,
    width: props.width,
    size: props.size,
    fullscreen: props.fullscreen,
    showFullscreenButton: props.showFullscreenButton,
    fullscreenText: props.fullscreenText,
    exitFullscreenText: props.exitFullscreenText,
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

  const dialogSizeMap = {
    sm: 'var(--art-dialog-width-sm)',
    md: 'var(--art-dialog-width-md)',
    lg: 'var(--art-dialog-width-lg)',
    xl: 'var(--art-dialog-width-xl)',
    full: 'calc(100vw - 24px)'
  } as const

  const isFullscreen = computed(() => Boolean(options.value.fullscreen))

  const normalizedDialogWidth = computed(() => {
    const inheritedWidth = attrs.width as string | number | undefined
    const presetWidth = options.value.size ? dialogSizeMap[options.value.size] : undefined
    const configuredWidth = options.value.width ?? inheritedWidth
    const width = normalizeSize(configuredWidth ?? presetWidth ?? '50%')
    if (!width) return undefined
    return `min(${width}, calc(100vw - 32px))`
  })

  const normalizedContentHeight = computed(() => {
    if (isFullscreen.value) return undefined
    const height = options.value.contentHeight
    return normalizeSize(height)
  })

  const normalizedContentMaxHeight = computed(() => {
    if (isFullscreen.value) return undefined
    return normalizeSize(
      options.value.contentMaxHeight ?? options.value.contentHeight ?? DEFAULT_CONTENT_MAX_HEIGHT
    )
  })

  const shouldUseScrollbar = computed(() => {
    return Boolean(
      normalizedContentHeight.value || normalizedContentMaxHeight.value || isFullscreen.value
    )
  })

  const dialogClass = computed(() => [
    attrs.class,
    (options.value.dialogProps as Record<string, unknown> | undefined)?.class
  ])

  const dialogTitle = computed(() => String(options.value.title ?? attrs.title ?? ''))
  const dialogSubtitle = computed(() => String(options.value.subtitle ?? ''))
  const hasSubtitle = computed(() => Boolean(slots.subtitle || dialogSubtitle.value))
  const fullscreenIcon = computed(() =>
    isFullscreen.value ? 'dashicons:fullscreen-exit-alt' : 'dashicons:fullscreen-alt'
  )
  const fullscreenLabel = computed(() =>
    isFullscreen.value
      ? String(options.value.exitFullscreenText ?? '退出全屏')
      : String(options.value.fullscreenText ?? '全屏')
  )

  const setFullscreen = (value: boolean) => {
    setOptions({ fullscreen: value } as Partial<ArtDialogOptions<T>>)
  }

  const toggleFullscreen = () => {
    setFullscreen(!isFullscreen.value)
  }

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
      appendToBody: true,
      destroyOnClose: true,
      draggable: true,
      ...inheritedAttrs,
      ...runtimeBindings,
      title: dialogTitle.value,
      width: normalizedDialogWidth.value,
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
    fullscreen: readonly(isFullscreen),
    options: readonly(options) as Readonly<Ref<ArtDialogOptions<T>>>,
    dialogRef: readonly(dialogRef),
    scrollbarRef: readonly(scrollbarRef),
    handleOpen,
    handleClose,
    handleConfirm,
    handleReset,
    setLoading,
    setConfirmLoading,
    setFullscreen,
    toggleFullscreen,
    setOptions,
    setData,
    updateData,
    getData,
    getDialogInstance,
    scrollTo
  }

  defineExpose(exposedApi)
</script>

<style scoped lang="scss">
  :global(.art-dialog) {
    max-width: calc(100vw - 32px);
  }

  :global(.art-dialog > .el-dialog__body) {
    overscroll-behavior: contain;
  }

  :global(.art-dialog.is-fullscreen) {
    display: flex;
    flex-direction: column;
    max-width: none;
    overflow: hidden;
  }

  :global(.art-dialog.is-fullscreen > .el-dialog__header),
  :global(.art-dialog.is-fullscreen > .el-dialog__footer) {
    flex: none;
  }

  :global(.art-dialog.is-fullscreen > .el-dialog__body) {
    flex: 1;
    min-height: 0;
    overflow: auto;
  }

  .art-dialog {
    &__header {
      display: flex;
      align-items: center;
      min-width: 0;
      min-height: 24px;
    }

    &__header-main {
      flex: 1;
      min-width: 0;
    }

    &__fullscreen-button {
      right: 52px !important;
    }

    &__action-icon {
      width: 18px;
      height: 18px;
    }

    &__content {
      box-sizing: border-box;
      min-height: 1px;
      padding: var(
        --art-dialog-content-padding,
        var(--art-space-4) var(--art-space-5) var(--art-space-5)
      );
    }

    &__subtitle {
      margin-top: 3px;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 13px;
      line-height: 20px;
      color: var(--el-text-color-secondary);
      overflow-wrap: anywhere;
    }

    &__scrollbar {
      width: 100%;

      :deep(.el-scrollbar__wrap) {
        overscroll-behavior: contain;
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
      text-overflow: ellipsis;
      font-size: 14px;
      color: var(--el-text-color-secondary);
      white-space: nowrap;
    }

    &__footer-actions {
      display: flex;
      flex: none;
      gap: var(--art-space-2);

      > .el-button {
        min-width: 72px;
        margin-left: 0;
      }
    }
  }

  :global(.art-dialog > .el-dialog__header .el-dialog__headerbtn) {
    top: 12px;
    right: 16px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 32px;
    height: 32px;
    padding: 0;
    color: var(--el-text-color-secondary);
    background: transparent;
    border: 1px solid transparent;
    border-radius: var(--art-control-radius);
    transition:
      color var(--art-motion-duration-fast) ease,
      background-color var(--art-motion-duration-fast) ease,
      border-color var(--art-motion-duration-fast) ease,
      box-shadow var(--art-motion-duration-fast) ease;
  }

  :global(.art-dialog > .el-dialog__header .el-dialog__headerbtn:hover) {
    color: var(--theme-color);
    background: color-mix(in srgb, var(--theme-color) 9%, transparent);
    border-color: transparent;
    box-shadow: var(--art-themed-action-hover-shadow);
  }

  :global(.art-dialog > .el-dialog__header .el-dialog__headerbtn:focus-visible) {
    color: var(--theme-color);
    outline: none;
    box-shadow: var(--art-themed-action-focus-shadow);
  }

  :global(.art-dialog > .el-dialog__header .el-dialog__headerbtn .el-dialog__close) {
    position: static;
    width: 18px;
    height: 18px;
    color: currentcolor;
    background: transparent !important;
    border-radius: 0;
  }

  :global(.art-dialog > .el-dialog__body > .art-dialog__content > .art-form),
  :global(
    .art-dialog > .el-dialog__body > .art-dialog__scrollbar .art-dialog__content > .art-form
  ) {
    padding: 0 !important;
  }
</style>
