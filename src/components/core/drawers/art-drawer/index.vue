<template>
  <ElDrawer
    ref="drawerRef"
    :model-value="visible"
    v-bind="drawerBindings"
    :class="['art-drawer', drawerClass]"
    @update:model-value="handleModelValueChange"
    @open="handleOpenedStart"
    @opened="handleOpened"
    @close="handleClosedStart"
    @closed="handleClosed"
    @open-auto-focus="emit('open-auto-focus')"
    @close-auto-focus="emit('close-auto-focus')"
    @resize-start="(...args) => emit('resize-start', ...args)"
    @resize="(...args) => emit('resize', ...args)"
    @resize-end="(...args) => emit('resize-end', ...args)"
  >
    <template v-if="$slots.header" #header>
      <slot name="header" :data="openData" :api="exposedApi" />
    </template>

    <ElScrollbar
      v-if="normalizedContentHeight"
      v-loading="contentLoading"
      ref="scrollbarRef"
      :height="normalizedContentHeight"
      :max-height="normalizedContentHeight"
      :always="options.scrollbarAlways"
      :native="options.nativeScrollbar"
      :element-loading-text="options.loadingText"
      :element-loading-background="options.loadingBackground"
      :element-loading-custom-class="options.loadingCustomClass"
      class="art-drawer__scrollbar"
    >
      <div class="art-drawer__content">
        <component
          :is="options.content"
          v-if="options.content"
          v-bind="options.contentProps"
          :data="openData"
          :drawer-api="exposedApi"
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
      class="art-drawer__content"
    >
      <component
        :is="options.content"
        v-if="options.content"
        v-bind="options.contentProps"
        :data="openData"
        :drawer-api="exposedApi"
      />
      <slot v-else :data="openData" :loading="contentLoading" :api="exposedApi" />
    </div>

    <template v-if="options.showFooter" #footer>
      <slot name="footer" :data="openData" :loading="confirmLoading" :api="exposedApi">
        <div class="art-drawer__footer">
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
      </slot>
    </template>
  </ElDrawer>
</template>

<script setup lang="ts" generic="T = Record<string, unknown>">
  import type { ScrollbarInstance } from 'element-plus'
  import type {
    ArtDrawerEmits,
    ArtDrawerExpose,
    ArtDrawerOptions,
    ArtDrawerProps,
    ArtDrawerSlots,
    ArtScrollOptions
  } from './types'
  import { mergeOverlayRecords, useArtOverlay } from '@/hooks/core/useArtOverlay'

  defineOptions({
    name: 'ArtDrawer',
    inheritAttrs: false
  })

  const props = withDefaults(defineProps<ArtDrawerProps<T>>(), {
    title: '',
    size: '40%',
    direction: 'rtl',
    loading: false,
    loadingText: '',
    loadingBackground: '',
    loadingCustomClass: '',
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

  const emit = defineEmits<ArtDrawerEmits<T>>()
  defineSlots<ArtDrawerSlots<T>>()

  const attrs = useAttrs()
  const drawerRef = shallowRef<unknown>()
  const scrollbarRef = shallowRef<ScrollbarInstance>()

  const getDefaultOptions = (): ArtDrawerOptions<T> => ({
    title: props.title,
    size: props.size,
    direction: props.direction,
    loading: props.loading,
    loadingText: props.loadingText,
    loadingBackground: props.loadingBackground,
    loadingCustomClass: props.loadingCustomClass,
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
    drawerProps: props.drawerProps,
    onOpen: props.onOpen,
    onConfirm: props.onConfirm,
    onClose: props.onClose,
    onReset: props.onReset
  })

  const mergeOptions = (
    base: ArtDrawerOptions<T>,
    override: Partial<ArtDrawerOptions<T>> = {}
  ): ArtDrawerOptions<T> => {
    return {
      ...base,
      ...override,
      contentProps: mergeOverlayRecords(base.contentProps, override.contentProps),
      drawerProps: mergeOverlayRecords(base.drawerProps, override.drawerProps)
    }
  }

  let exposedApi!: ArtDrawerExpose<T>
  const overlay = useArtOverlay<T, ArtDrawerExpose<T>, ArtDrawerOptions<T>>({
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

  const normalizedContentHeight = computed(() => {
    const height = options.value.contentHeight
    return typeof height === 'number' ? `${height}px` : height
  })

  const drawerClass = computed(() => [
    attrs.class,
    (options.value.drawerProps as Record<string, unknown> | undefined)?.class
  ])

  watch(
    () => props.loading,
    (value) => setLoading(value)
  )

  const drawerBindings = computed<Record<string, unknown>>(() => {
    const runtimeProps = options.value.drawerProps ?? {}
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
    delete inheritedAttrs.onResizeStart
    delete inheritedAttrs.onResize
    delete inheritedAttrs.onResizeEnd

    return {
      destroyOnClose: true,
      ...inheritedAttrs,
      ...runtimeBindings,
      title: String(options.value.title ?? inheritedAttrs.title ?? ''),
      size: options.value.size ?? inheritedAttrs.size ?? '40%',
      direction: options.value.direction ?? inheritedAttrs.direction ?? 'rtl'
    }
  })

  const getDrawerInstance = () => drawerRef.value

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
    options: readonly(options) as Readonly<Ref<ArtDrawerOptions<T>>>,
    drawerRef: readonly(drawerRef),
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
    getDrawerInstance,
    scrollTo
  } as unknown as ArtDrawerExpose<T>

  defineExpose(exposedApi)
</script>

<style scoped lang="scss">
  :deep(.art-drawer) {
    max-width: 100vw;
  }

  :deep(.art-drawer .el-drawer__body) {
    display: flex;
    flex-direction: column;
    min-height: 0;
  }

  .art-drawer__content {
    min-height: 1px;
    height: 100%;
  }

  .art-drawer__scrollbar {
    width: 100%;
    flex: 1;
    min-height: 0;

    :deep(.el-scrollbar__view) {
      padding-right: 4px;
    }
  }

  .art-drawer__footer {
    display: flex;
    gap: 12px;
    align-items: center;
    justify-content: flex-end;
  }
</style>
