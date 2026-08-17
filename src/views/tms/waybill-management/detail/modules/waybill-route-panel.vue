<template>
  <section class="waybill-route art-card-xs">
    <div class="waybill-route__heading">
      <div>
        <ArtSectionTitle title="节点轨迹与定位" />
        <p>业务节点、费用定位与自动停车点统一落在车辆轨迹上，并明确标记坐标来源。</p>
      </div>
      <div class="waybill-route__heading-tags" aria-label="轨迹概览">
        <ElTag :type="locationPoints.length ? 'success' : 'info'" effect="plain">
          {{ locationPoints.length }} 个定位节点
        </ElTag>
        <ElTag v-if="derivedPointCount" type="warning" effect="plain">
          {{ derivedPointCount }} 个推导坐标
        </ElTag>
        <ElTag v-if="energyPointCount" type="primary" effect="plain">
          {{ energyPointCount }} 个能源节点
        </ElTag>
        <ElTag v-if="stopPointCount" type="danger" effect="plain">
          {{ stopPointCount }} 个停车点
        </ElTag>
      </div>
    </div>

    <div v-if="locationPoints.length" class="waybill-route__layout">
      <div class="waybill-route__map-card">
        <ArtAsyncState
          class="waybill-route__map-state"
          :loading="map.loading"
          :error="map.error"
          :empty="!locationPoints.length"
          @retry="initializeMap"
        >
          <div ref="mapRef" class="waybill-route__map" aria-label="运单节点道路轨迹地图" />
        </ArtAsyncState>
        <div class="waybill-route__map-note" :class="`is-${map.routeStatus}`">
          <ArtSvgIcon :icon="routeNote.icon" aria-hidden="true" />
          <span>{{ routeNote.text }}</span>
        </div>
      </div>

      <ElScrollbar max-height="560px" always class="waybill-route__list-scrollbar">
        <ol class="waybill-route__list">
          <li v-for="point in locationPoints" :key="point.id" :class="`is-${point.kind}`">
            <span class="waybill-route__index">{{ point.markerLabel }}</span>
            <div>
              <div class="waybill-route__point-title">
                <strong>{{ point.label }}</strong>
                <div class="waybill-route__point-tags">
                  <ElTag :type="point.isDerived ? 'warning' : 'info'" size="small" effect="plain">
                    {{ point.sourceLabel }}
                  </ElTag>
                  <ElTag
                    v-if="point.insideGeofence != null"
                    :type="point.insideGeofence ? 'success' : 'warning'"
                    size="small"
                  >
                    {{ point.insideGeofence ? '围栏内' : '围栏外' }}
                  </ElTag>
                </div>
              </div>
              <p>{{ point.address || '未记录地点说明' }}</p>
              <small>
                {{ formatDateTime(point.time) }}
                <template v-if="point.endTime"> 至 {{ formatDateTime(point.endTime) }}</template>
              </small>
              <dl>
                <div
                  ><dt>经度</dt><dd>{{ point.longitude.toFixed(6) }}</dd></div
                >
                <div
                  ><dt>纬度</dt><dd>{{ point.latitude.toFixed(6) }}</dd></div
                >
                <div v-if="point.accuracyM != null">
                  <dt>定位精度</dt><dd>{{ point.accuracyM }} m</dd>
                </div>
                <div v-if="point.distanceM != null">
                  <dt>距围栏中心</dt><dd>{{ Math.round(point.distanceM) }} m</dd>
                </div>
                <div v-if="point.durationMinutes != null">
                  <dt>停留时长</dt><dd>{{ formatDuration(point.durationMinutes) }}</dd>
                </div>
              </dl>
              <p v-if="point.isDerived" class="waybill-route__derived-note">
                该节点未单独上报 GPS，坐标来自{{ point.sourceLabel }}。
              </p>
            </div>
          </li>
        </ol>
      </ElScrollbar>
    </div>

    <ArtEmptyState
      v-else
      title="暂无定位节点"
      description="请维护地址坐标，或由司机完成带定位的业务签到、费用上报与连续 GPS 采集。"
      size="compact"
      :visual-size="92"
    />
  </section>
</template>

<script setup lang="ts">
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtEmptyState from '@/components/core/layouts/art-empty-state/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { useAmapSdk } from '@/hooks/core/useAmapSdk'
  import { formatWithDayjs } from '@/utils/time'
  import {
    buildDrivingRoutePoints,
    buildWaybillGpsTrackPoints,
    buildWaybillLocationPoints,
    type WaybillLocationPoint
  } from './waybill-route-model'

  defineOptions({ name: 'TmsWaybillRoutePanel' })

  type RouteStatus = 'idle' | 'planning' | 'actual' | 'ready' | 'unavailable'

  type DetailAmapOverlay = object
  type DetailAmapMarker = object
  type DetailAmapPolyline = object
  interface DetailAmapMap {
    add: (overlays: DetailAmapOverlay[] | DetailAmapOverlay) => void
    destroy: () => void
    setFitView: (overlays?: DetailAmapOverlay[], immediately?: boolean, avoid?: number[]) => void
  }
  interface DetailAmapDriving {
    search: (
      origin: [number, number],
      destination: [number, number],
      options: { waypoints: Array<[number, number]> },
      callback: (status: string, result: unknown) => void
    ) => void
  }
  interface DetailAmapNamespace {
    Map: new (container: HTMLElement, options: Record<string, unknown>) => DetailAmapMap
    Marker: new (options: Record<string, unknown>) => DetailAmapMarker
    Polyline: new (options: Record<string, unknown>) => DetailAmapPolyline
    Driving: new (options: Record<string, unknown>) => DetailAmapDriving
    Pixel: new (x: number, y: number) => unknown
    DrivingPolicy?: { LEAST_TIME?: number }
    [key: string]: unknown
  }

  const props = defineProps<{ waybill: Api.Tms.Waybill.WaybillDetailRecord }>()
  const mapRef = ref<HTMLDivElement>()
  const map = reactive<{ loading: boolean; error: Error | null; routeStatus: RouteStatus }>({
    loading: false,
    error: null,
    routeStatus: 'idle'
  })
  const { loadAmap } = useAmapSdk<DetailAmapNamespace>({
    key: import.meta.env.VITE_AMAP_KEY,
    securityJsCode: import.meta.env.VITE_AMAP_SECURITY_JS_CODE,
    plugins: ['AMap.Driving']
  })
  let mapInstance: DetailAmapMap | undefined

  const locationPoints = computed<WaybillLocationPoint[]>(() =>
    buildWaybillLocationPoints(props.waybill)
  )
  const drivingRoutePoints = computed(() => buildDrivingRoutePoints(locationPoints.value))
  const gpsTrackPoints = computed(() => buildWaybillGpsTrackPoints(props.waybill))
  const derivedPointCount = computed(
    () => locationPoints.value.filter((point) => point.isDerived).length
  )
  const energyPointCount = computed(
    () => locationPoints.value.filter((point) => point.kind === 'energy').length
  )
  const stopPointCount = computed(
    () => locationPoints.value.filter((point) => point.kind === 'stop').length
  )
  const routeNote = computed(() => {
    const notes: Record<RouteStatus, { icon: string; text: string }> = {
      idle: { icon: 'ri:road-map-line', text: '正在准备道路轨迹。' },
      planning: { icon: 'ri:loader-4-line', text: '高德地图正在根据有效定位节点规划驾车路线。' },
      actual: {
        icon: 'ri:route-line',
        text: '蓝色线路为车辆连续 GPS 实际轨迹；P 点由低速定位簇自动识别并计算停留时长。'
      },
      ready: {
        icon: 'ri:route-line',
        text: '蓝色线路为高德驾车规划结果，用于连接有效节点；并非车辆连续 GPS 实际轨迹。'
      },
      unavailable: {
        icon: 'ri:information-line',
        text: '当前无法生成道路路线，仅显示有效定位点；请稍后重试或检查高德路线服务配置。'
      }
    }
    return notes[map.routeStatus]
  })

  watch(
    () => props.waybill.id,
    () => void initializeMap()
  )
  onMounted(() => void initializeMap())
  onBeforeUnmount(() => mapInstance?.destroy())

  async function initializeMap(): Promise<void> {
    if (!mapRef.value || !locationPoints.value.length) return
    map.loading = true
    map.error = null
    map.routeStatus = 'planning'
    try {
      const amap = await loadAmap()
      mapInstance?.destroy()
      mapInstance = new amap.Map(mapRef.value, {
        zoom: 10,
        resizeEnable: true,
        mapStyle: 'amap://styles/normal'
      })
      const markers = createMarkers(amap)
      mapInstance.add(markers)
      const actualTrack = createActualTrack(amap)
      if (actualTrack) {
        mapInstance.add(actualTrack)
        mapInstance.setFitView([...markers, actualTrack], false, [56, 56, 56, 56])
        map.routeStatus = 'actual'
      } else {
        mapInstance.setFitView(markers, false, [56, 56, 56, 56])
        map.routeStatus = await planDrivingRoute(amap)
      }
    } catch (error) {
      map.error = error instanceof Error ? error : new Error('地图加载失败，请稍后重试')
      map.routeStatus = 'unavailable'
    } finally {
      map.loading = false
    }
  }

  function createMarkers(amap: DetailAmapNamespace): DetailAmapMarker[] {
    return locationPoints.value.map((point) => {
      const marker = new amap.Marker({
        anchor: 'bottom-center',
        content: `<div class="waybill-route-marker is-${point.kind}"><b>${escapeLabel(point.markerLabel)}</b><span>${escapeLabel(point.label)}</span></div>`,
        offset: new amap.Pixel(0, 0),
        position: [point.longitude, point.latitude],
        title: point.label,
        zIndex: point.kind === 'stop' ? 130 : 120
      })
      return marker
    })
  }

  function createActualTrack(amap: DetailAmapNamespace): DetailAmapPolyline | undefined {
    if (gpsTrackPoints.value.length < 2) return undefined
    return new amap.Polyline({
      borderWeight: 2,
      isOutline: true,
      lineCap: 'round',
      lineJoin: 'round',
      outlineColor: '#ffffff',
      path: gpsTrackPoints.value.map((point) => [point.longitude, point.latitude]),
      showDir: true,
      strokeColor: '#2878ff',
      strokeOpacity: 0.95,
      strokeWeight: 7,
      zIndex: 80
    })
  }

  async function planDrivingRoute(amap: DetailAmapNamespace): Promise<RouteStatus> {
    const points = drivingRoutePoints.value
    if (!mapInstance || points.length < 2) return 'unavailable'

    const driving = new amap.Driving({
      map: mapInstance,
      policy: amap.DrivingPolicy?.LEAST_TIME ?? 0,
      hideMarkers: true,
      showTraffic: false,
      isOutline: true,
      outlineColor: '#ffffff',
      autoFitView: true
    })
    const origin: [number, number] = [points[0].longitude, points[0].latitude]
    const destinationPoint = points.at(-1)
    if (!destinationPoint) return 'unavailable'
    const destination: [number, number] = [destinationPoint.longitude, destinationPoint.latitude]
    const waypoints = points
      .slice(1, -1)
      .map((point): [number, number] => [point.longitude, point.latitude])

    return await new Promise((resolve) => {
      let settled = false
      let timeoutId = 0
      const finish = (status: RouteStatus) => {
        if (settled) return
        settled = true
        window.clearTimeout(timeoutId)
        resolve(status)
      }
      timeoutId = window.setTimeout(() => finish('unavailable'), 10_000)
      driving.search(origin, destination, { waypoints }, (status) => {
        finish(status === 'complete' ? 'ready' : 'unavailable')
      })
    })
  }

  function escapeLabel(value: string): string {
    return value.replace(
      /[&<>'"]/g,
      (char) =>
        ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[char] || char
    )
  }

  function formatDateTime(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') || '-'
  }

  function formatDuration(minutes: number): string {
    if (minutes < 60) return `${minutes} 分钟`
    const hours = Math.floor(minutes / 60)
    const remainder = minutes % 60
    return remainder ? `${hours} 小时 ${remainder} 分钟` : `${hours} 小时`
  }
</script>

<style scoped lang="scss">
  .waybill-route {
    min-width: 0;
    padding: var(--art-section-padding);

    &__heading {
      display: flex;
      gap: var(--art-space-4);
      align-items: flex-start;
      justify-content: space-between;

      p {
        margin: var(--art-space-1) 0 0;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__heading-tags,
    &__point-tags {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-2);
    }

    &__heading-tags {
      justify-content: flex-end;
    }

    &__layout {
      display: grid;
      grid-template-columns: minmax(0, 1.45fr) minmax(300px, 0.55fr);
      gap: var(--art-space-4);
      margin-top: var(--art-space-4);
    }

    &__map-card {
      min-width: 0;
      overflow: hidden;
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__map-state {
      min-height: 520px;
    }

    &__map {
      width: 100%;
      height: 520px;
    }

    &__map-note {
      display: flex;
      gap: var(--art-space-2);
      align-items: flex-start;
      padding: var(--art-space-3);
      font-size: 12px;
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-lighter);
      border-top: 1px solid var(--el-border-color-lighter);

      &.is-ready {
        color: var(--el-color-success-dark-2);
        background: var(--el-color-success-light-9);
      }

      &.is-unavailable {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
      }
    }

    &__list-scrollbar {
      min-width: 0;
    }

    &__list {
      display: grid;
      gap: var(--art-space-3);
      padding: 0 var(--art-space-2) 0 0;
      margin: 0;
      list-style: none;

      li {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        gap: var(--art-space-3);
        min-width: 0;
        padding: var(--art-space-3);
        background: var(--el-fill-color-lighter);
        border: 1px solid transparent;
        border-radius: var(--el-border-radius-base);

        &.is-energy {
          background: var(--el-color-warning-light-9);
          border-color: var(--el-color-warning-light-7);
        }

        &.is-stop {
          background: var(--el-color-danger-light-9);
          border-color: var(--el-color-danger-light-7);
        }
      }

      p {
        margin: var(--art-space-1) 0;
        color: var(--el-text-color-regular);
        overflow-wrap: anywhere;
      }

      small {
        color: var(--el-text-color-secondary);
      }

      dl {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--art-space-2);
        margin: var(--art-space-3) 0 0;

        > div {
          min-width: 0;
        }
      }

      dt {
        font-size: 10px;
        color: var(--el-text-color-secondary);
      }

      dd {
        margin: 2px 0 0;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-regular);
      }
    }

    &__index {
      display: grid;
      place-items: center;
      width: 28px;
      height: 28px;
      font-weight: 700;
      color: white;
      background: var(--theme-color);
      border-radius: 50%;
    }

    .is-energy &__index {
      background: var(--el-color-warning);
    }

    .is-stop &__index {
      background: var(--el-color-danger);
    }

    &__point-title {
      display: flex;
      gap: var(--art-space-2);
      align-items: flex-start;
      justify-content: space-between;
    }

    &__point-tags {
      flex: none;
      justify-content: flex-end;
    }

    &__derived-note {
      padding: var(--art-space-2);
      margin-top: var(--art-space-3) !important;
      font-size: 11px;
      color: var(--el-color-warning-dark-2) !important;
      background: var(--el-color-warning-light-9);
      border-radius: var(--el-border-radius-small);
    }
  }

  :global(.waybill-route-marker) {
    display: inline-flex;
    gap: 6px;
    align-items: center;
    padding: 4px 8px 4px 4px;
    font-size: 12px;
    font-weight: 600;
    color: var(--el-text-color-primary);
    white-space: nowrap;
    background: var(--el-bg-color);
    border: 1px solid var(--el-border-color-light);
    border-radius: var(--el-border-radius-small);
    box-shadow: 0 4px 12px rgb(31 45 61 / 12%);
  }

  :global(.waybill-route-marker b) {
    display: grid;
    place-items: center;
    width: 25px;
    height: 25px;
    color: #fff;
    background: var(--theme-color);
    border-radius: 50%;
  }

  :global(.waybill-route-marker.is-energy b) {
    background: var(--el-color-warning);
  }

  :global(.waybill-route-marker.is-stop b) {
    background: var(--el-color-danger);
  }

  @media (width <= 992px) {
    .waybill-route {
      &__layout {
        grid-template-columns: 1fr;
      }

      &__map-state,
      &__map {
        height: 420px;
        min-height: 420px;
      }
    }
  }

  @media (width <= 640px) {
    .waybill-route {
      &__heading,
      &__point-title {
        flex-direction: column;
      }

      &__heading-tags,
      &__point-tags {
        justify-content: flex-start;
      }

      &__map-state,
      &__map {
        height: 340px;
        min-height: 340px;
      }
    }
  }
</style>
