<!-- 水印组件 -->
<template>
  <div
    v-if="resolvedVisible"
    class="fixed left-0 top-0 h-screen w-screen pointer-events-none"
    :style="{ zIndex: zIndex }"
  >
    <ElWatermark
      :content="watermarkContent"
      :font="{ fontSize: fontSize, color: fontColor }"
      :rotate="rotate"
      :gap="[gapX, gapY]"
      :offset="[offsetX, offsetY]"
    >
      <div style="height: 100vh"></div>
    </ElWatermark>
  </div>
</template>

<script setup lang="ts">
  import { useSettingStore } from '@/store/modules/setting'
  import { useUserStore } from '@/store/modules/user'
  import { useWebsiteConfig } from '@/hooks'

  defineOptions({ name: 'ArtWatermark' })

  const settingStore = useSettingStore()
  const userStore = useUserStore()
  const { watermarkVisible } = storeToRefs(settingStore)
  const { websiteConfig, websiteConfigLoaded, loadWebsiteConfig, resolveWatermarkContent } =
    useWebsiteConfig()

  interface WatermarkProps {
    /** 水印内容 */
    content?: string
    /** 水印是否可见 */
    visible?: boolean
    /** 水印字体大小 */
    fontSize?: number
    /** 水印字体颜色 */
    fontColor?: string
    /** 水印旋转角度 */
    rotate?: number
    /** 水印间距X */
    gapX?: number
    /** 水印间距Y */
    gapY?: number
    /** 水印偏移X */
    offsetX?: number
    /** 水印偏移Y */
    offsetY?: number
    /** 水印层级 */
    zIndex?: number
  }

  const props = withDefaults(defineProps<WatermarkProps>(), {
    content: '',
    visible: false,
    fontSize: 16,
    fontColor: 'rgba(128, 128, 128, 0.2)',
    rotate: -22,
    gapX: 100,
    gapY: 100,
    offsetX: 50,
    offsetY: 50,
    zIndex: 3100
  })

  const resolvedVisible = computed(() => {
    if (props.visible) return true
    if (websiteConfigLoaded.value) {
      return websiteConfig.value.watermarkEnabled
    }
    return watermarkVisible.value
  })

  const watermarkContent = computed(
    () => props.content || resolveWatermarkContent(userStore.getUserInfo)
  )

  onMounted(() => {
    void loadWebsiteConfig()
  })
</script>
