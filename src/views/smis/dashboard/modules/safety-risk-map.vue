<template>
  <section class="safety-risk-map art-card-xs">
    <header>
      <div><strong>风险空间分布</strong><p>风险点定位与未结事故坐标统一展示。</p></div>
      <ElTag effect="plain">{{ points.length }} 个定位对象</ElTag>
    </header>
    <ArtAsyncState
      :loading="state.loading"
      :error="state.error"
      loading-mode="skeleton"
      @retry="initializeMap"
    >
      <div
        v-show="points.length"
        ref="mapRef"
        class="safety-risk-map__canvas"
        aria-label="安全风险空间分布地图"
      />
    </ArtAsyncState>
    <ArtEmptyState
      v-if="!points.length && !state.loading"
      compact
      title="暂无可定位的风险对象"
      description="事故坐标或风险点 mapGeometry 完善后会自动显示在地图中。"
    />
  </section>
</template>

<script setup lang="ts">
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import { useAmapSdk } from '@/hooks/core/useAmapSdk'

  defineOptions({ name: 'SmisSafetyRiskMap' })
  type Point = Api.Smis.Dashboard.SafetyMapPoint
  type Overlay = object
  interface MapInstance {
    add: (overlays: Overlay[]) => void
    destroy: () => void
    setFitView: (overlays?: Overlay[], immediately?: boolean, avoid?: number[]) => void
  }
  interface AmapNamespace {
    Map: new (container: HTMLElement, options: Record<string, unknown>) => MapInstance
    Marker: new (options: Record<string, unknown>) => Overlay
    Pixel: new (x: number, y: number) => unknown
  }

  const props = defineProps<{ points: Point[] }>()
  const mapRef = ref<HTMLDivElement>()
  const state = reactive<{ loading: boolean; error: Error | null }>({ loading: false, error: null })
  const { loadAmap } = useAmapSdk<AmapNamespace>({
    key: import.meta.env.VITE_AMAP_KEY,
    securityJsCode: import.meta.env.VITE_AMAP_SECURITY_JS_CODE
  })
  let mapInstance: MapInstance | undefined

  const escapeHtml = (value: string): string =>
    value.replace(
      /[&<>'"]/g,
      (character) =>
        ({
          '&': '&amp;',
          '<': '&lt;',
          '>': '&gt;',
          "'": '&#39;',
          '"': '&quot;'
        })[character] || character
    )
  const initializeMap = async (): Promise<void> => {
    if (!mapRef.value || !props.points.length) return
    state.loading = true
    state.error = null
    try {
      const amap = await loadAmap()
      mapInstance?.destroy()
      mapInstance = new amap.Map(mapRef.value, {
        zoom: 10,
        resizeEnable: true,
        mapStyle: 'amap://styles/normal'
      })
      const markers = props.points.map(
        (point) =>
          new amap.Marker({
            anchor: 'bottom-center',
            position: [point.longitude, point.latitude],
            title: point.title,
            offset: new amap.Pixel(0, 0),
            content: `<div class="smis-risk-marker is-${point.level}"><b>${point.kind === 'accident' ? '故' : '险'}</b><span>${escapeHtml(point.title)}</span></div>`
          })
      )
      mapInstance.add(markers)
      mapInstance.setFitView(markers, false, [56, 56, 56, 56])
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('风险地图加载失败')
    } finally {
      state.loading = false
    }
  }
  watch(
    () => props.points,
    () => void nextTick(initializeMap),
    { deep: true }
  )
  onMounted(() => void initializeMap())
  onBeforeUnmount(() => mapInstance?.destroy())
</script>

<style scoped lang="scss">
  .safety-risk-map {
    display: grid;
    gap: 14px;
    min-width: 0;
    padding: 18px;
  }

  .safety-risk-map header {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;
  }

  .safety-risk-map header strong {
    font-size: 16px;
  }

  .safety-risk-map header p {
    margin: 4px 0 0;
    font-size: 13px;
    color: var(--art-text-gray-600);
  }

  .safety-risk-map__canvas {
    width: 100%;
    height: 390px;
    overflow: hidden;
    border-radius: 10px;
  }

  :global(.smis-risk-marker) {
    display: flex;
    gap: 6px;
    align-items: center;
    max-width: 180px;
    padding: 5px 9px 5px 5px;
    color: #fff;
    background: #6b7280;
    border: 2px solid #fff;
    border-radius: 999px;
    box-shadow: 0 5px 14px rgb(15 23 42 / 20%);
  }

  :global(.smis-risk-marker b) {
    display: grid;
    flex: 0 0 auto;
    place-items: center;
    width: 24px;
    height: 24px;
    background: rgb(255 255 255 / 18%);
    border-radius: 50%;
  }

  :global(.smis-risk-marker span) {
    overflow: hidden;
    text-overflow: ellipsis;
    font-size: 12px;
    white-space: nowrap;
  }

  :global(.smis-risk-marker.is-low) {
    background: #16a34a;
  }

  :global(.smis-risk-marker.is-general) {
    background: #d97706;
  }

  :global(.smis-risk-marker.is-major) {
    background: #ea580c;
  }

  :global(.smis-risk-marker.is-critical) {
    background: #dc2626;
  }

  @media (width <= 760px) {
    .safety-risk-map__canvas {
      height: 320px;
    }
  }
</style>
