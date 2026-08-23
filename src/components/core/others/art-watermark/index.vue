<!-- 水印组件 -->
<template>
  <Teleport to="#app-content" :disabled="!teleportReady">
    <div
      v-if="resolvedVisible"
      class="art-watermark-layer"
      aria-hidden="true"
      :style="{ zIndex: zIndex }"
    >
      <ElWatermark
        class="h-full w-full"
        :content="watermarkContent"
        :font="{ fontSize: fontSize, color: fontColor }"
        :rotate="rotate"
        :gap="watermarkGap"
        :offset="watermarkOffset"
      >
        <div class="h-full"></div>
      </ElWatermark>
    </div>
  </Teleport>
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
  const teleportReady = ref(false)

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
    fontSize: 14,
    fontColor: 'rgba(71, 85, 105, 0.05)',
    rotate: -22,
    gapX: 340,
    gapY: 260,
    offsetX: 170,
    offsetY: 130,
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
  const watermarkGap = computed<[number, number]>(() => [props.gapX ?? 220, props.gapY ?? 190])
  const watermarkOffset = computed<[number, number]>(() => [
    props.offsetX ?? 110,
    props.offsetY ?? 95
  ])

  onMounted(async () => {
    await nextTick()
    teleportReady.value = true
    void loadWebsiteConfig()
  })
</script>

<style scoped>
  .art-watermark-layer {
    position: absolute;
    inset: 0;
    overflow: hidden;
    pointer-events: none;
  }
</style>
