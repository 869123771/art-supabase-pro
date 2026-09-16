<!-- 系统logo -->
<template>
  <div class="art-logo" :class="{ 'art-logo--dark': dark }">
    <img
      v-if="variant !== 'wordmark'"
      :style="logoStyle"
      src="@imgs/common/logo.webp"
      width="36"
      height="36"
      :alt="variant === 'mark' ? `${brandName} Logo` : ''"
      class="art-logo__mark"
    />
    <span
      v-if="variant !== 'mark'"
      :style="wordmarkStyle"
      class="art-logo__wordmark"
      :title="brandName"
      >{{ brandName }}</span
    >
  </div>
</template>

<script setup lang="ts">
  import type { CSSProperties } from 'vue'
  import { useWebsiteConfig } from '@/hooks'

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

  const { brandName } = useWebsiteConfig()

  const logoSize = computed(() => {
    if (typeof props.size === 'number') return `${props.size}px`
    return /^\d+(?:\.\d+)?$/.test(props.size) ? `${props.size}px` : props.size
  })

  const logoStyle = computed<CSSProperties>(() => ({
    width: logoSize.value,
    height: logoSize.value
  }))

  const wordmarkStyle = computed<CSSProperties>(() => ({
    fontSize: `calc(${logoSize.value} * 0.62)`,
    maxWidth: `calc(${logoSize.value} * 4.5)`
  }))
</script>

<style scoped lang="scss">
  .art-logo {
    display: inline-flex;
    flex-shrink: 0;
    gap: 10px;
    align-items: center;
    justify-content: center;
    min-width: 0;
    line-height: 1;

    &__mark {
      display: block;
      flex: none;
      object-fit: contain;
    }

    &__wordmark {
      display: block;
      min-width: 0;
      overflow: hidden;
      font-family: 'HarmonyOS Sans', 'PingFang SC', 'Microsoft YaHei', sans-serif;
      font-weight: 800;
      line-height: 1.08;
      color: #08275d;
      text-overflow: ellipsis;
      white-space: nowrap;
      letter-spacing: 0.025em;
      background: linear-gradient(180deg, #164c92 0%, #061c49 86%);
      background-clip: text;
      filter: drop-shadow(0 1px 0 rgb(255 255 255 / 42%));
      -webkit-text-fill-color: transparent;
      -webkit-text-stroke: 0.35px rgb(2 20 54 / 72%);
    }

    &--dark {
      .art-logo__wordmark {
        color: #f3f7ff;
        background: linear-gradient(180deg, #ffffff 0%, #d9e7fb 88%);
        background-clip: text;
        filter: drop-shadow(0 1px 2px rgb(0 0 0 / 35%));
        -webkit-text-fill-color: transparent;
        -webkit-text-stroke: 0.3px rgb(10 35 74 / 48%);
      }
    }
  }
</style>
