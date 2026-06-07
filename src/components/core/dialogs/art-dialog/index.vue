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
    <template v-if="$slots.header" #header>
      <slot name="header" :data="openData" :api="exposedApi" />
    </template>

    <ElScrollbar
      v-if="normalizedContentHeight"
      ref="scrollbarRef"
      :height="normalizedContentHeight"
      :max-height="normalizedContentHeight"
      :always="options.scrollbarAlways"
      :native="options.nativeScrollbar"
      class="art-dialog__scrollbar"
    >
      <div v-loading="loading" class="art-dialog__content">
        <component
          :is="options.content"
          v-if="options.content"
          v-bind="options.contentProps"
          :data="openData"
          :dialog-api="exposedApi"
        />
        <slot v-else :data="openData" :api="exposedApi" />
      </div>
    </ElScrollbar>

    <div v-else v-loading="loading" class="art-dialog__content">
      <component
        :is="options.content"
        v-if="options.content"
        v-bind="options.contentProps"
        :data="openData"
        :dialog-api="exposedApi"
      />
      <slot v-else :data="openData" :api="exposedApi" />
    </div>

    <template v-if="options.showFooter" #footer>
      <slot name="footer" :data="openData" :loading="confirmLoading" :api="exposedApi">
        <div class="art-dialog__footer">
          <ElButton
            v-if="options.showCancelButton"
            :disabled="loading || confirmLoading"
            @click="() => handleClose()"
          >
            {{ options.cancelText }}
          </ElButton>
          <ElButton
            v-if="options.showConfirmButton"
            type="primary"
            :loading="confirmLoading"
            :disabled="loading || options.confirmDisabled"
            @click="handleConfirm"
          >
            {{ options.confirmText }}
          </ElButton>
        </div>
      </slot>
    </template>
  </ElDialog>
</template>

<script setup lang="ts" generic="T = Record<string, any>">
  import type { Component } from 'vue'
  import type { DialogInstance, ScrollbarInstance } from 'element-plus'
  import type { ArtDialogExpose, ArtDialogOptions, ArtScrollOptions } from './types'
  import { mergeOverlayRecords, useArtOverlay } from '@/hooks/core/useArtOverlay'

  defineOptions({
    name: 'ArtDialog',
    inheritAttrs: false
  })

  interface Props {
    title?: string
    width?: string | number
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
    dialogProps?: ArtDialogOptions<T>['dialogProps']
    onOpen?: ArtDialogOptions<T>['onOpen']
    onConfirm?: ArtDialogOptions<T>['onConfirm']
    onClose?: ArtDialogOptions<T>['onClose']
    onReset?: ArtDialogOptions<T>['onReset']
  }

  const props = withDefaults(defineProps<Props>(), {
    title: '',
    width: '50%',
    contentHeight: undefined,
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
  const dialogRef = shallowRef<DialogInstance>()
  const scrollbarRef = shallowRef<ScrollbarInstance>()

  const getDefaultOptions = (): ArtDialogOptions<T> => ({
    title: props.title,
    width: props.width,
    contentHeight: props.contentHeight,
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
    loading,
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

  const normalizedContentHeight = computed(() => {
    const height = options.value.contentHeight
    return typeof height === 'number' ? `${height}px` : height
  })

  const dialogClass = computed(() => [
    attrs.class,
    (options.value.dialogProps as Record<string, unknown> | undefined)?.class
  ])

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
      title: String(options.value.title ?? inheritedAttrs.title ?? ''),
      width: options.value.width ?? inheritedAttrs.width ?? '50%'
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
    loading: readonly(loading),
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

  .art-dialog__content {
    min-height: 1px;
  }

  .art-dialog__scrollbar {
    width: 100%;

    :deep(.el-scrollbar__view) {
      padding-right: 4px;
    }
  }

  .art-dialog__footer {
    display: flex;
    align-items: center;
    justify-content: flex-end;
  }
</style>
