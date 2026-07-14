<!-- 表格按钮 -->
<template>
  <div
    v-auth="permission"
    :class="[
      'inline-flex items-center justify-center min-w-8 h-8 px-2.5 mr-2.5 text-sm c-p rounded-md align-middle',
      buttonClass,
      { 'cursor-not-allowed opacity-60': isDisabled }
    ]"
    :style="{ backgroundColor: buttonBgColor, color: iconColor }"
    :aria-busy="loading"
    :aria-disabled="isDisabled"
    @click="handleClick"
  >
    <ArtSvgIcon :icon="iconContent" :class="{ 'animate-spin': loading }" />
  </div>
</template>

<script setup lang="ts">
  defineOptions({ name: 'ArtButtonTable' })

  interface Props {
    /** 按钮类型 */
    type?: 'add' | 'edit' | 'delete' | 'more' | 'sign' | 'view'
    /** 按钮图标 */
    icon?: string
    /** 按钮样式类 */
    iconClass?: string
    /** icon 颜色 */
    iconColor?: string
    /** 按钮背景色 */
    buttonBgColor?: string
    /*按钮权限*/
    permission?: string
    /** 是否显示加载状态 */
    loading?: boolean
    /** 是否禁用点击 */
    disabled?: boolean
  }

  const props = withDefaults(defineProps<Props>(), {})

  const emit = defineEmits<{
    (e: 'click'): void
  }>()

  // 默认按钮配置
  const defaultButtons = {
    add: { icon: 'ri:add-fill', class: 'bg-theme/12 text-theme' },
    edit: { icon: 'ri:pencil-line', class: 'bg-secondary/12 text-secondary' },
    delete: { icon: 'ri:delete-bin-5-line', class: 'bg-error/12 text-error' },
    sign: { icon: 'ri:checkbox-circle-line', class: 'bg-success/12 text-success' },
    view: { icon: 'ri:eye-line', class: 'bg-info/12 text-info' },
    more: { icon: 'ri:more-2-fill', class: '' }
  } as const

  const isDisabled = computed(() => props.disabled || props.loading)

  // 获取图标内容
  const iconContent = computed(() => {
    if (props.loading) return 'ri:loader-4-line'
    return props.icon || (props.type ? defaultButtons[props.type]?.icon : '') || ''
  })

  // 获取按钮样式类
  const buttonClass = computed(() => {
    return props.iconClass || (props.type ? defaultButtons[props.type]?.class : '') || ''
  })

  const handleClick = () => {
    if (isDisabled.value) return
    emit('click')
  }
</script>
