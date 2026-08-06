<!-- 按钮组件 -->
<template>
  <button
    v-auth="permission"
    type="button"
    class="art-icon-button size-8.5 inline-flex flex-cc c-p border-0 bg-transparent text-g-600 dark:text-g-800 text-xl rounded tad-300 hover:bg-hover-color"
    :class="[`art-icon-button--${tone}`, { 'rounded-full': circle }]"
    :disabled="disabled"
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
    tone?: 'theme' | 'danger'
    permission?: string
  }

  const props = withDefaults(defineProps<Props>(), {
    tone: 'theme'
  })

  const emit = defineEmits<{
    (e: 'click', event: MouseEvent): void
  }>()

  const handleClick = (event: MouseEvent): void => {
    if (props.disabled) return
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

    &:disabled {
      cursor: not-allowed;
      opacity: 0.55;
    }
  }
</style>
