<!-- 系统logo -->
<template>
  <div class="flex-cc shrink-0 gap-2.5">
    <img
      v-if="variant !== 'wordmark'"
      :style="logoStyle"
      src="@imgs/common/logo.webp"
      width="36"
      height="36"
      :alt="variant === 'mark' ? '亿企工场 Logo' : ''"
      class="block object-contain"
    />
    <img
      v-if="variant !== 'mark'"
      :src="wordmarkSrc"
      :style="wordmarkStyle"
      width="420"
      height="100"
      alt="亿企工场"
      class="block object-contain"
    />
  </div>
</template>

<script setup lang="ts">
  import wordmarkLight from '@imgs/common/wordmark-light.png'
  import wordmarkDark from '@imgs/common/wordmark-dark.png'

  defineOptions({ name: 'ArtLogo' })

  interface Props {
    /** logo 大小 */
    size?: number | string
    /** 纯图标、独立字标，或图标与字标组合 */
    variant?: 'mark' | 'wordmark' | 'full'
    /** 所在表面的主题，侧栏可独立于页面设置深色 */
    dark?: boolean
  }

  const props = withDefaults(defineProps<Props>(), {
    size: 36,
    variant: 'mark',
    dark: false
  })

  const logoStyle = computed(() => ({ width: `${props.size}px`, height: `${props.size}px` }))
  const wordmarkSrc = computed(() => (props.dark ? wordmarkDark : wordmarkLight))
  const wordmarkStyle = computed(() => ({
    width: `${Number(props.size) * 2.52}px`,
    height: `${Number(props.size) * 0.6}px`
  }))
</script>
