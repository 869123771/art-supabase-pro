<!-- 按钮组件 -->
<template>
  <button
    v-auth="permission"
    type="button"
    class="art-icon-button size-8.5 inline-flex flex-cc c-p border-0 bg-transparent text-g-600 dark:text-g-800 text-xl rounded tad-300 hover:bg-hover-color"
    :class="[
      `art-icon-button--${tone}`,
      { 'rounded-full': circle, 'art-icon-button--loading': loading }
    ]"
    :disabled="disabled || loading"
    :aria-busy="loading || undefined"
    :aria-label="accessibleLabel"
    :title="accessibleLabel"
    @click="handleClick"
  >
    <ArtSvgIcon :icon="icon"></ArtSvgIcon>
    <slot></slot>
  </button>
</template>

<script lang="ts" setup>
  defineOptions({ name: 'ArtIconButton' })

  interface Props {
    /** 图标名称 */
    icon: string
    /** 圆角按钮 */
    circle?: boolean
    /** 是否禁用 */
    disabled?: boolean
    /** 是否处于加载状态；加载时保留动作含义并旋转图标 */
    loading?: boolean
    tone?: 'theme' | 'danger'
    permission?: string
    /** 按钮动作名称，用于无障碍文本和悬停提示 */
    label?: string
  }

  const props = withDefaults(defineProps<Props>(), {
    tone: 'theme'
  })

  const emit = defineEmits<{
    (e: 'click', event: MouseEvent): void
  }>()

  const defaultIconLabels: Record<string, string> = {
    'ri:menu-2-fill': '展开或收起菜单',
    'ri:refresh-line': '刷新当前页面',
    'ri:function-line': '打开快捷入口',
    'dashicons:fullscreen-alt': '进入全屏',
    'dashicons:fullscreen-exit-alt': '退出全屏',
    'ri:translate-2': '切换语言',
    'ri:notification-2-line': '打开通知中心',
    'ri:message-3-line': '打开智能助手',
    'ri:settings-line': '打开界面设置',
    'ri:moon-line': '切换深色模式',
    'ri:sun-fill': '切换浅色模式',
    'ri:more-2-fill': '更多操作'
  }

  const accessibleLabel = computed(() => props.label || defaultIconLabels[props.icon] || '图标操作')

  const handleClick = (event: MouseEvent): void => {
    if (props.disabled || props.loading) return
    emit('click', event)
  }
</script>

<style scoped lang="scss">
  button {
    --art-action-color: var(--theme-color);

    touch-action: manipulation;
    transition:
      color var(--art-motion-duration-fast) ease,
      background-color var(--art-motion-duration-fast) ease,
      box-shadow var(--art-motion-duration-fast) ease;

    &.art-icon-button--danger {
      --art-action-color: var(--el-color-danger);
    }

    &:not(:disabled):hover {
      color: var(--art-action-color);
      background-color: color-mix(in srgb, var(--art-action-color) 10%, transparent);
      box-shadow: var(--art-themed-action-hover-shadow);
    }

    &:not(:disabled):active {
      background-color: color-mix(in srgb, var(--art-action-color) 16%, transparent);
      box-shadow: var(--art-themed-action-active-shadow);
    }

    &:focus-visible {
      color: var(--art-action-color);
      outline: none;
      background-color: color-mix(in srgb, var(--art-action-color) 9%, transparent);
      box-shadow: var(--art-themed-action-focus-shadow);
    }

    &:disabled:not(.art-icon-button--loading) {
      cursor: not-allowed;
      opacity: 0.55;
    }

    &.art-icon-button--loading {
      color: var(--art-action-color);
      cursor: progress;
      background-color: color-mix(in srgb, var(--art-action-color) 10%, transparent);
    }

    &.art-icon-button--loading :deep(svg) {
      animation: art-icon-button-spin 0.8s linear infinite;
    }

    @media (prefers-reduced-motion: reduce) {
      &.art-icon-button--loading :deep(svg) {
        animation: none;
      }
    }
  }

  @keyframes art-icon-button-spin {
    to {
      transform: rotate(360deg);
    }
  }
</style>
