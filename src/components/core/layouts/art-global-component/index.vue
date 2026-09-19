<!-- 全局组件 -->
<template>
  <component
    v-for="componentConfig in renderedComponents"
    :key="componentConfig.key"
    :is="componentConfig.component"
  />
</template>

<script setup lang="ts">
  import {
    getEnabledGlobalComponents,
    type GlobalComponentConfig
  } from '@/config/modules/component'
  import { mittBus } from '@/utils/sys'
  import { ElMessage } from 'element-plus'
  import type { Component } from 'vue'

  defineOptions({ name: 'ArtGlobalComponent' })

  const enabledComponents = computed(() => getEnabledGlobalComponents())
  const loadedComponents = shallowReactive(new Map<string, Component>())
  const loadingComponents = new Map<string, Promise<Component>>()
  const renderedComponents = computed(() => {
    return enabledComponents.value.flatMap((config) => {
      const component = config.component ?? loadedComponents.get(config.key)
      return component ? [{ ...config, component }] : []
    })
  })

  const loadComponent = async (config: GlobalComponentConfig): Promise<Component | undefined> => {
    if (config.component) return config.component

    const loadedComponent = loadedComponents.get(config.key)
    if (loadedComponent) return loadedComponent
    if (!config.loader) return undefined

    const pendingLoad =
      loadingComponents.get(config.key) ?? config.loader().then((module) => module.default)
    loadingComponents.set(config.key, pendingLoad)

    try {
      const component = await pendingLoad
      loadedComponents.set(config.key, component)
      return component
    } finally {
      loadingComponents.delete(config.key)
    }
  }

  const activate = async (key: string, replay: () => void): Promise<void> => {
    if (loadedComponents.has(key)) return
    const config = enabledComponents.value.find((component) => component.key === key)
    if (!config) return

    try {
      const component = await loadComponent(config)
      if (!component) return
      await nextTick()
      replay()
    } catch (error) {
      console.error(`[global-component] 加载 ${config.name} 失败`, error)
      ElMessage.error(`${config.name}加载失败，请稍后重试`)
    }
  }

  const openSettings = (): void => {
    void activate('settings-panel', () => mittBus.emit('openSetting'))
  }
  const openSearch = (): void => {
    void activate('global-search', () => mittBus.emit('openSearchDialog'))
  }
  const openChat = (): void => {
    void activate('chat-window', () => mittBus.emit('openChat'))
  }
  const triggerFireworks = (imageUrl?: string): void => {
    void activate('fireworks-effect', () => mittBus.emit('triggerFireworks', imageUrl))
  }
  const handleGlobalShortcut = (event: KeyboardEvent): void => {
    if (loadedComponents.has('global-search')) return
    if (!(event.ctrlKey || event.metaKey) || event.key.toLowerCase() !== 'k') return

    event.preventDefault()
    openSearch()
  }

  onMounted(() => {
    mittBus.on('openSetting', openSettings)
    mittBus.on('openSearchDialog', openSearch)
    mittBus.on('openChat', openChat)
    mittBus.on('triggerFireworks', triggerFireworks)
    document.addEventListener('keydown', handleGlobalShortcut)
  })

  onUnmounted(() => {
    mittBus.off('openSetting', openSettings)
    mittBus.off('openSearchDialog', openSearch)
    mittBus.off('openChat', openChat)
    mittBus.off('triggerFireworks', triggerFireworks)
    document.removeEventListener('keydown', handleGlobalShortcut)
  })
</script>
