<!-- 按钮组件 -->
<template>
  <div
    v-auth="permission"
    class="size-8.5 inline-flex flex-cc c-p text-g-600 dark:text-g-800 text-xl rounded tad-300 hover:bg-hover-color"
    :class="{ 'rounded-full': circle }"
    @click="handleClick"
  >
    <ArtSvgIcon :icon="icon"></ArtSvgIcon>
    <slot></slot>
  </div>
</template>

<script lang="ts" setup>
  defineOptions({ name: 'ArtIconButton' })

  interface Props {
    /** 图标名称 */
    icon: string
    /** 圆角按钮 */
    circle?: boolean
    permission?: string
  }

  withDefaults(defineProps<Props>(), {})

  const emit = defineEmits<{
    (e: 'click', event: MouseEvent): void
  }>()

  const handleClick = (event: MouseEvent): void => {
    emit('click', event)
  }
</script>
