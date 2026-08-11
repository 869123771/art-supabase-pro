<template>
  <div class="transit-screen" aria-label="TMS 运输在途监控工作台">
    <ArtAsyncState
      class="transit-screen__state"
      :loading="screen.loading"
      :error="pageError"
      :min-height="0"
      full-height
      @retry="loadMonitorData"
    >
      <div
        ref="viewportRef"
        class="transit-screen__viewport"
        :class="{ 'is-compact': isCompactScreen }"
        @wheel.capture="handleScreenWheelCapture"
      >
        <ElScrollbar class="transit-screen__scrollbar">
          <div
            class="transit-screen__stage"
            :class="{ 'is-compact': isCompactScreen }"
            :style="screenStageStyle"
          >
            <header class="transit-screen__header">
              <div class="transit-screen__title">
                <button
                  type="button"
                  aria-label="返回运营工作台"
                  title="返回运营工作台"
                  @click="exitMonitor"
                >
                  <ArtSvgIcon icon="ri:arrow-left-line" />
                </button>
                <h1>TMS 运输在途监控</h1>
              </div>
              <ElScrollbar class="screen-tabs-scrollbar">
                <nav class="screen-tabs" aria-label="监控模式">
                  <button
                    v-for="item in monitorTabs"
                    :key="item.value"
                    type="button"
                    :class="{ 'is-active': activeMode === item.value }"
                    :aria-current="activeMode === item.value ? 'page' : undefined"
                    @click="activeMode = item.value"
                  >
                    {{ item.label }}
                  </button>
                </nav>
              </ElScrollbar>
              <div class="header-status">
                <time :datetime="currentTime">{{ headerTimeText }}</time>
                <span><i />系统运行正常</span>
              </div>
            </header>

            <main class="transit-screen__body">
              <section class="monitor-map" :class="`monitor-map--${activeMode}`">
                <div ref="chartRef" class="monitor-map__chart" />
                <div class="monitor-map__heading">
                  <strong>{{ monitorHeadingTitle }}</strong>
                  <span>{{ activeOrder?.routeName || '暂无线路' }}</span>
                </div>
                <div v-if="activeOrder" class="monitor-map__track-chip">
                  {{ activeOrder.plateNo }} · {{ activeOrder.orderNo }}
                </div>
                <div class="monitor-map__tools" :class="{ 'is-wide': activeMode !== 'realtime' }">
                  <ElButton
                    circle
                    :icon="ZoomIn"
                    title="放大地图"
                    aria-label="放大地图"
                    @click="zoomMap('in')"
                  />
                  <ElButton
                    circle
                    :icon="ZoomOut"
                    title="缩小地图"
                    aria-label="缩小地图"
                    @click="zoomMap('out')"
                  />
                  <ElButton
                    circle
                    :icon="RefreshRight"
                    title="定位当前车辆"
                    aria-label="定位当前车辆"
                    @click="resetMapView"
                  />
                </div>

                <section
                  v-if="activeMode === 'realtime'"
                  class="screen-panel map-float map-float--overview"
                >
                  <div class="screen-panel__title">
                    <strong>运输概况</strong>
                    <span>{{ formatRefreshTime(screen.lastRefreshTime) }}</span>
                  </div>
                  <div class="progress-lines">
                    <div v-for="item in overviewBars" :key="item.label" class="progress-line">
                      <div>
                        <span>{{ item.label }}</span>
                        <strong>{{ item.value }}</strong>
                      </div>
                      <i>
                        <b :style="{ width: `${item.percent}%`, background: item.color }" />
                      </i>
                    </div>
                  </div>
                </section>

                <section
                  v-if="activeMode === 'realtime' && alertItems.length > 0"
                  class="screen-panel map-float map-float--alerts"
                >
                  <div class="screen-panel__title">
                    <strong>实时报警</strong>
                    <span>{{ alertItems.length }} 条</span>
                  </div>
                  <ElScrollbar class="alert-list">
                    <div v-for="item in alertItems" :key="item.key" class="alert-item">
                      <i :class="`alert-item__level alert-item__level--${item.level}`" />
                      <div>
                        <strong>{{ item.title }}</strong>
                        <p>{{ item.content }}</p>
                      </div>
                      <span>{{ item.time }}</span>
                    </div>
                  </ElScrollbar>
                </section>
              </section>

              <RealtimeMonitorPanel
                v-if="activeMode === 'realtime'"
                v-model:keyword="screen.keyword"
                v-model:region="screen.region"
                v-model:status="screen.status"
                class="transit-screen__left"
                :get-poi-text="getVehiclePoiText"
                :is-poi-loading="isVehiclePoiLoading"
                :orders="filteredOrders"
                :overview="overview"
                :region-options="regionOptions"
                :selected-id="screen.selectedOrderId"
                :status-options="monitorStatusOptions"
                :total-count="realtimeOrders.length"
                @refresh-poi="handleVehiclePoiRefresh"
                @select="selectOrder"
              />
              <WaybillMonitorPanel
                v-else-if="activeMode === 'waybill'"
                v-model:keyword="monitorKeywords.waybill"
                class="transit-screen__left"
                :orders="monitorOrders"
                :overview="overview"
                :selected-id="screen.selectedOrderId"
                @select="selectOrder"
              />
              <VehicleMonitorPanel
                v-else
                v-model:keyword="monitorKeywords.vehicle"
                class="transit-screen__left"
                :orders="monitorOrders"
                :overview="overview"
                :selected-id="screen.selectedOrderId"
                @select="selectOrder"
              />

              <MonitorDetailPanel
                v-if="activeMode === 'realtime'"
                class="transit-screen__right"
                :order="activeOrder"
                @analyze-anomaly="openTransportAnomalyAdvisor"
                @contact-driver="contactDriver"
                @open-detail="openOrderDetail"
                @send-reminder="sendReminder"
              />
            </main>
          </div>
        </ElScrollbar>
      </div>
    </ArtAsyncState>

    <TransportAnomalyAdvisorDrawer ref="transportAnomalyAdvisorRef" />
  </div>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import type { UnwrapNestedRefs } from 'vue'
  import { storeToRefs } from 'pinia'
  import { ElMessage } from 'element-plus'
  import { RefreshRight, ZoomIn, ZoomOut } from '@element-plus/icons-vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import { fetchInTransitMonitorList, subscribeInTransitMonitorChanges } from '@/api/tms'
  import { useAmapSdk } from '@/hooks/core/useAmapSdk'
  import { useUserStore } from '@/store/modules/user'
  import { formatWithDayjs } from '@/utils/time'
  import { useDebounceFn, useEventListener, useIntervalFn, useResizeObserver } from '@vueuse/core'
  import MonitorDetailPanel from './modules/monitor-detail-panel.vue'
  import RealtimeMonitorPanel from './modules/realtime-monitor-panel.vue'
  import TransportAnomalyAdvisorDrawer from './modules/transport-anomaly-advisor-drawer.vue'
  import VehicleMonitorPanel from './modules/vehicle-monitor-panel.vue'
  import WaybillMonitorPanel from './modules/waybill-monitor-panel.vue'
  import {
    AMAP_PLUGINS,
    DEFAULT_SCREEN_DESIGN_HEIGHT,
    DEFAULT_SCREEN_DESIGN_WIDTH,
    INITIAL_MAP_ZOOM,
    INITIAL_POI_CONCURRENCY,
    MAP_MAX_ZOOM,
    MAP_MIN_ZOOM,
    MONITOR_STATUS_DICT_CODE,
    monitorTabs,
    regionOptions,
    VEHICLE_TYPE_DICT_CODE
  } from './modules/monitor-config'
  import { INITIAL_MAP_CENTER } from './modules/monitor-geo-config'
  import type {
    GeoCoord,
    MonitorMode,
    MonitorKeywordState,
    MonitorOrder,
    ReverseGeocodeResult,
    ScreenScaleState,
    ScreenState,
    VehiclePoiState
  } from './modules/monitor-types'
  import {
    dedupeGeoPath,
    escapeHtml,
    formatRefreshTime,
    getMonitorRecordId,
    isRouteVisibleStatus,
    toGeoCoord
  } from './modules/monitor-utils'
  import { useMonitorOrders } from './modules/use-monitor-orders'

  defineOptions({ name: 'TmsInTransitMonitor' })

  interface MonitorAmapLngLatLike {
    lng?: number
    lat?: number
    getLng?: () => number
    getLat?: () => number
  }

  interface TransportAnomalyAdvisorExpose {
    handleOpen: (data: { orderId: string; orderNo: string }) => Promise<void>
  }

  interface MonitorAmapMarkerInstance {
    setContent: (content: string) => void
    setPosition: (position: GeoCoord) => void
    setzIndex?: (zIndex: number) => void
  }

  interface MonitorAmapPolylineInstance {
    setOptions?: (options: Record<string, unknown>) => void
    setPath: (path: MonitorAmapLngLatLike[]) => void
  }

  type MonitorAmapOverlay = MonitorAmapMarkerInstance | MonitorAmapPolylineInstance

  interface MonitorAmapMapInstance {
    add: (overlay: MonitorAmapOverlay | unknown) => void
    addControl: (control: unknown) => void
    destroy?: () => void
    getZoom?: () => number
    on: (event: string, handler: () => void) => void
    remove?: (overlay: MonitorAmapOverlay) => void
    resize?: () => void
    setCenter?: (center: GeoCoord) => void
    setStatus?: (status: Record<string, boolean>) => void
    setZoom?: (zoom: number) => void
    setZoomAndCenter?: (zoom: number, center: GeoCoord) => void
    zoomIn?: () => void
    zoomOut?: () => void
  }

  interface MonitorAmapGeocoderInstance {
    getAddress: (
      position: GeoCoord,
      callback: (status: string, result: ReverseGeocodeResult) => void
    ) => void
  }

  interface MonitorAmapDrivingResult {
    routes?: Array<{
      steps?: Array<{
        path?: MonitorAmapLngLatLike[]
      }>
    }>
  }

  interface MonitorAmapDrivingInstance {
    search: (
      origin: MonitorAmapLngLatLike,
      destination: MonitorAmapLngLatLike,
      callback: (status: string, result: MonitorAmapDrivingResult) => void
    ) => void
  }

  interface MonitorAmapNamespace {
    Driving: new (options: Record<string, unknown>) => MonitorAmapDrivingInstance
    DrivingPolicy?: {
      LEAST_TIME?: unknown
    }
    Geocoder: new (options: Record<string, unknown>) => MonitorAmapGeocoderInstance
    LngLat: new (lng: number, lat: number) => MonitorAmapLngLatLike
    Map: new (container: HTMLElement, options: Record<string, unknown>) => MonitorAmapMapInstance
    Marker: new (options: Record<string, unknown>) => MonitorAmapMarkerInstance
    Pixel: new (x: number, y: number) => unknown
    Polyline: new (options: Record<string, unknown>) => MonitorAmapPolylineInstance
    Scale: new () => unknown
    [key: string]: unknown
  }

  const router = useRouter()
  const userStore = useUserStore()
  const { loadAmap } = useAmapSdk<MonitorAmapNamespace>({
    key: import.meta.env.VITE_AMAP_KEY,
    plugins: AMAP_PLUGINS,
    securityJsCode: import.meta.env.VITE_AMAP_SECURITY_JS_CODE
  })
  const { getDictMap } = storeToRefs(userStore)
  const viewportRef = ref<HTMLDivElement>()
  const chartRef = ref<HTMLDivElement>()
  const transportAnomalyAdvisorRef = ref<TransportAnomalyAdvisorExpose>()
  const amapSdk = shallowRef<MonitorAmapNamespace>()
  const amapInstance = shallowRef<MonitorAmapMapInstance>()
  const amapReady = ref(false)
  const liveTick = ref(0)
  const currentTime = ref(new Date().toISOString())
  const activeMode = ref<MonitorMode>('realtime')
  const monitorKeywords = reactive<MonitorKeywordState>({
    vehicle: '',
    waybill: ''
  })
  const mapZoom = ref(INITIAL_MAP_ZOOM)
  const screenScale: UnwrapNestedRefs<ScreenScaleState> = reactive<ScreenScaleState>({
    viewportHeight: DEFAULT_SCREEN_DESIGN_HEIGHT,
    viewportWidth: DEFAULT_SCREEN_DESIGN_WIDTH
  })
  const vehicleMarkers = new Map<string, MonitorAmapMarkerInstance>()
  const vehiclePois = reactive(new Map<string, VehiclePoiState>())
  const drivingRoutePaths = reactive(new Map<string, GeoCoord[]>())
  const drivingRouteRequests = new Set<string>()
  let originMarker: MonitorAmapMarkerInstance | undefined
  let destinationMarker: MonitorAmapMarkerInstance | undefined
  let routeBasePolyline: MonitorAmapPolylineInstance | undefined
  let passedPolyline: MonitorAmapPolylineInstance | undefined
  let remainingPolyline: MonitorAmapPolylineInstance | undefined
  let unsubscribeMonitorChanges: (() => void) | undefined

  const screen: UnwrapNestedRefs<ScreenState> = reactive<ScreenState>({
    keyword: '',
    loading: false,
    loaded: false,
    error: null,
    orders: [],
    region: '',
    selectedOrderId: undefined,
    status: ''
  })

  const screenBaseScale = computed(() => {
    const scale = Math.min(
      screenScale.viewportWidth / DEFAULT_SCREEN_DESIGN_WIDTH,
      screenScale.viewportHeight / DEFAULT_SCREEN_DESIGN_HEIGHT
    )

    return Number.isFinite(scale) && scale > 0 ? scale : 1
  })

  const isCompactScreen = computed(() => screenScale.viewportWidth <= 1100)

  const screenStageStyle = computed(() => {
    if (isCompactScreen.value) {
      return {
        width: '100%',
        height: 'auto',
        minHeight: `${screenScale.viewportHeight}px`,
        transform: 'none'
      }
    }

    const scale = screenBaseScale.value
    const width = DEFAULT_SCREEN_DESIGN_WIDTH * scale
    const height = DEFAULT_SCREEN_DESIGN_HEIGHT * scale
    const offsetX = (screenScale.viewportWidth - width) / 2
    const offsetY = (screenScale.viewportHeight - height) / 2

    return {
      width: `${DEFAULT_SCREEN_DESIGN_WIDTH}px`,
      height: `${DEFAULT_SCREEN_DESIGN_HEIGHT}px`,
      transform: `translate(${offsetX}px, ${offsetY}px) scale(${scale})`
    }
  })

  const headerTimeText = computed(() =>
    formatWithDayjs(currentTime.value, 'YYYY年MM月DD日 HH:mm:ss')
  )
  const pageError = computed(() => (screen.loaded ? null : screen.error))
  const monitorHeadingTitle = computed(
    () =>
      ({
        realtime: '单车轨迹监控',
        vehicle: '车辆实时位置',
        waybill: '运单运输轨迹'
      })[activeMode.value]
  )

  const {
    activeOrder,
    alertItems,
    filteredOrders,
    getPreferredMonitorRecordId,
    mapRouteOrder,
    modeOrders,
    monitorOrders,
    monitorStatusOptions,
    overview,
    overviewBars,
    realtimeOrders
  } = useMonitorOrders({
    activeMode,
    drivingRoutePaths,
    getDictOptions: (dictCode) => getDictMap.value[dictCode] ?? [],
    liveTick,
    screen
  })

  watch([activeMode, activeOrder, () => liveTick.value], () => {
    const routeOrder = mapRouteOrder.value
    if (routeOrder) void ensureDrivingRoute(routeOrder)
    updateChinaMap()
  })

  onMounted(() => {
    updateScreenViewportSize()
    void Promise.all([
      userStore.ensureDictLoaded(VEHICLE_TYPE_DICT_CODE),
      userStore.ensureDictLoaded(MONITOR_STATUS_DICT_CODE)
    ])
    void loadMonitorData()
    unsubscribeMonitorChanges = subscribeInTransitMonitorChanges(refreshMonitorFromRealtime)
    void initChinaMap()
  })

  onBeforeUnmount(() => {
    unsubscribeMonitorChanges?.()
    destroyMonitorMap()
  })

  useEventListener(window, 'resize', resizeScaledScreen)
  if (window.visualViewport) {
    useEventListener(window.visualViewport, 'resize', resizeScaledScreen)
  }

  useResizeObserver(viewportRef, () => {
    resizeScaledScreen()
  })

  useResizeObserver(chartRef, () => {
    resizeChinaMap()
  })

  useIntervalFn(() => {
    void loadMonitorData(false)
  }, 60000)

  useIntervalFn(() => {
    liveTick.value += 1
    currentTime.value = new Date().toISOString()
  }, 1000)

  const refreshMonitorFromRealtime = useDebounceFn(() => {
    void loadMonitorData(false)
  }, 250)

  async function loadMonitorData(showLoading = true): Promise<void> {
    if (showLoading) screen.loading = true
    screen.error = null
    try {
      const { data } = await fetchInTransitMonitorList({
        from: 0,
        to: 199
      })

      screen.orders = data ?? []
      screen.loaded = true
      screen.lastRefreshTime = new Date().toISOString()
      if (!screen.orders.some((row) => getMonitorRecordId(row) === screen.selectedOrderId)) {
        screen.selectedOrderId = getPreferredMonitorRecordId(screen.orders)
      }
      void loadVehiclePois()
      if (amapReady.value) {
        void nextTick(() => {
          updateChinaMap()
          fitSelectedMapView(true)
        })
      }
    } catch (error) {
      screen.error = error instanceof Error ? error : new Error('在途监控数据加载失败')
    } finally {
      screen.loading = false
    }
  }

  async function initChinaMap(): Promise<void> {
    if (!chartRef.value) return

    try {
      const AMap = await loadAmap()
      amapSdk.value = AMap
      amapInstance.value = new AMap.Map(chartRef.value, {
        center: INITIAL_MAP_CENTER,
        doubleClickZoom: true,
        dragEnable: true,
        features: ['bg', 'road', 'point'],
        mapStyle: 'amap://styles/darkblue',
        resizeEnable: true,
        scrollWheel: true,
        viewMode: '2D',
        zoom: INITIAL_MAP_ZOOM,
        zoomEnable: true,
        zooms: [MAP_MIN_ZOOM, MAP_MAX_ZOOM]
      })
      amapInstance.value.setStatus?.({
        doubleClickZoom: true,
        dragEnable: true,
        scrollWheel: true,
        zoomEnable: true
      })
      amapInstance.value.addControl(new AMap.Scale())
      amapInstance.value.on('zoomchange', syncMapViewState)
      amapInstance.value.on('mapmove', syncMapViewState)
      amapReady.value = true
      const routeOrder = mapRouteOrder.value
      if (routeOrder) void ensureDrivingRoute(routeOrder)
    } catch (error) {
      amapReady.value = false
      ElMessage.warning(getFriendlySupabaseErrorMessage(error, '地图加载失败，请稍后重试'))
    }

    updateChinaMap()
    fitSelectedMapView(true)
  }

  function updateChinaMap(): void {
    const map = amapInstance.value
    if (!map || !amapSdk.value || !amapReady.value) return

    syncOnlineVehicleMarkers()

    const active = mapRouteOrder.value
    if (!active) {
      clearRouteObjects()
      return
    }

    const origin = active.originGeo
    const destination = active.destinationGeo

    originMarker = upsertMarker(originMarker, origin, '发', active.origin, '#23d18b')
    destinationMarker = upsertMarker(
      destinationMarker,
      destination,
      '收',
      active.destination,
      '#ff9f43'
    )

    if (active.routePath.length < 2) {
      clearRouteLines()
      return
    }

    routeBasePolyline = upsertPolyline(
      routeBasePolyline,
      buildVisibleRoutePath(active),
      '#6ec8ff',
      12,
      false,
      150,
      0.34
    )
    passedPolyline = upsertPolyline(passedPolyline, active.passedPath, '#315cff', 8, false, 180)
    remainingPolyline = upsertPolyline(
      remainingPolyline,
      active.remainingPath,
      '#8ed3ff',
      7,
      false,
      170,
      0.82
    )
  }

  function syncOnlineVehicleMarkers(): void {
    const activeIds = new Set<string>()

    modeOrders.value.forEach((item) => {
      activeIds.add(item.id)
      const position: GeoCoord =
        item.status === 'pending' ? item.originGeo : [item.longitude, item.latitude]
      const marker = upsertMarker(
        vehicleMarkers.get(item.id),
        position,
        '车',
        item.plateNo,
        isRouteVisibleStatus(item.status) ? '#315cff' : '#d69b12',
        {
          image: item.vehicleImage,
          subtitle: item.statusLabel
        }
      )
      if (marker) vehicleMarkers.set(item.id, marker)
    })

    vehicleMarkers.forEach((marker, id) => {
      if (activeIds.has(id)) return
      removeMapObject(marker)
      vehicleMarkers.delete(id)
    })
  }

  function clearRouteObjects(): void {
    originMarker = removeMapObject(originMarker)
    destinationMarker = removeMapObject(destinationMarker)
    clearRouteLines()
  }

  function clearRouteLines(): void {
    routeBasePolyline = removeMapObject(routeBasePolyline)
    passedPolyline = removeMapObject(passedPolyline)
    remainingPolyline = removeMapObject(remainingPolyline)
  }

  function removeMapObject(object: MonitorAmapOverlay | undefined): undefined {
    if (object) amapInstance.value?.remove?.(object)
    return undefined
  }

  function updateScreenViewportSize(): void {
    const viewport = viewportRef.value
    screenScale.viewportWidth =
      viewport?.clientWidth || window.innerWidth || DEFAULT_SCREEN_DESIGN_WIDTH
    screenScale.viewportHeight =
      viewport?.clientHeight || window.innerHeight || DEFAULT_SCREEN_DESIGN_HEIGHT
  }

  function resizeScaledScreen(): void {
    updateScreenViewportSize()
    resizeChinaMap()
  }

  function handleScreenWheelCapture(event: WheelEvent): void {
    if (!event.ctrlKey) return

    event.stopPropagation()
  }

  function syncMapViewState(): void {
    const map = amapInstance.value
    if (!map) return
    const zoom = map.getZoom?.()
    if (typeof zoom === 'number') mapZoom.value = Math.round(zoom)
  }

  function resizeChinaMap(): void {
    const applyResize = () => {
      amapInstance.value?.resize?.()
    }

    window.requestAnimationFrame(() => {
      applyResize()
      window.setTimeout(applyResize, 120)
    })
  }

  async function loadVehiclePois(): Promise<void> {
    const orders = [...realtimeOrders.value]
    const activeIds = new Set(orders.map((item) => item.id))
    vehiclePois.forEach((_, id) => {
      if (!activeIds.has(id)) vehiclePois.delete(id)
    })

    const queue = [...orders]
    const workerCount = Math.min(INITIAL_POI_CONCURRENCY, queue.length)
    await Promise.all(
      Array.from({ length: workerCount }, async () => {
        let order = queue.shift()
        while (order) {
          await refreshVehiclePoi(order)
          order = queue.shift()
        }
      })
    )
  }

  function getVehiclePoiText(order: MonitorOrder): string {
    const poi = vehiclePois.get(order.id)
    return poi?.coordinateKey === getVehicleCoordinateKey(order) ? poi.label : '正在获取位置...'
  }

  function isVehiclePoiLoading(order: MonitorOrder): boolean {
    const poi = vehiclePois.get(order.id)
    return poi?.coordinateKey === getVehicleCoordinateKey(order) && poi.loading
  }

  async function handleVehiclePoiRefresh(order: MonitorOrder): Promise<void> {
    const success = await refreshVehiclePoi(order, true)
    if (!success) ElMessage.warning('当前坐标暂无 POI 信息，请稍后重试')
  }

  async function refreshVehiclePoi(order: MonitorOrder, force = false): Promise<boolean> {
    const coordinateKey = getVehicleCoordinateKey(order)
    const current = vehiclePois.get(order.id)
    if (!force && current?.coordinateKey === coordinateKey)
      return current.label !== '暂未获取到 POI'

    const state: VehiclePoiState = {
      coordinateKey,
      label: current?.coordinateKey === coordinateKey ? current.label : '正在获取位置...',
      loading: true
    }
    vehiclePois.set(order.id, state)

    try {
      const label = await reverseGeocode(order.longitude, order.latitude)
      const nextState = vehiclePois.get(order.id)
      if (nextState?.coordinateKey === coordinateKey) nextState.label = label
      return true
    } catch {
      const nextState = vehiclePois.get(order.id)
      if (nextState?.coordinateKey === coordinateKey) nextState.label = '暂未获取到 POI'
      return false
    } finally {
      const nextState = vehiclePois.get(order.id)
      if (nextState?.coordinateKey === coordinateKey) nextState.loading = false
    }
  }

  async function reverseGeocode(longitude: number, latitude: number): Promise<string> {
    const AMap = await loadAmap()

    return new Promise((resolve, reject) => {
      const geocoder = new AMap.Geocoder({ extensions: 'all', radius: 1000 })
      geocoder.getAddress([longitude, latitude], (status: string, result: ReverseGeocodeResult) => {
        if (status !== 'complete') {
          reject(new Error('高德逆地理编码失败'))
          return
        }

        const regeocode = result?.regeocode
        const poiName = regeocode?.pois?.[0]?.name
        const address = String(
          regeocode?.formattedAddress || regeocode?.formatted_address || poiName || ''
        ).trim()
        if (!address) {
          reject(new Error('未查询到 POI'))
          return
        }
        resolve(address)
      })
    })
  }

  function getVehicleCoordinateKey(order: MonitorOrder): string {
    return `${order.longitude.toFixed(6)},${order.latitude.toFixed(6)}`
  }

  async function ensureDrivingRoute(order: MonitorOrder): Promise<void> {
    if (drivingRoutePaths.has(order.id) || drivingRouteRequests.has(order.id)) return
    if (!amapReady.value) return
    drivingRouteRequests.add(order.id)

    try {
      const AMap = await loadAmap()
      const path = await searchDrivingRoute(AMap, order.originGeo, order.destinationGeo)
      if (path.length > 1) {
        drivingRoutePaths.set(order.id, path)
        await nextTick()
        updateChinaMap()
        if (activeOrder.value?.id === order.id) fitSelectedMapView(true)
      }
    } catch {
      // 高德路线不可用时保持无线状态。
    } finally {
      drivingRouteRequests.delete(order.id)
    }
  }

  function searchDrivingRoute(
    AMap: MonitorAmapNamespace,
    origin: GeoCoord,
    destination: GeoCoord
  ): Promise<GeoCoord[]> {
    return new Promise((resolve, reject) => {
      const driving = new AMap.Driving({
        hideMarkers: true,
        policy: AMap.DrivingPolicy?.LEAST_TIME,
        showTraffic: false
      })
      driving.search(
        new AMap.LngLat(origin[0], origin[1]),
        new AMap.LngLat(destination[0], destination[1]),
        (status: string, result) => {
          if (status !== 'complete') {
            reject(new Error('驾车路线规划失败'))
            return
          }

          const path = (result.routes?.[0]?.steps ?? [])
            .flatMap((step) => step.path ?? [])
            .map((point) =>
              toGeoCoord(point.lng ?? point.getLng?.(), point.lat ?? point.getLat?.())
            )
            .filter((point: GeoCoord | undefined): point is GeoCoord => Boolean(point))
          resolve(dedupeGeoPath([origin, ...path, destination]))
        }
      )
    })
  }

  function upsertMarker(
    marker: MonitorAmapMarkerInstance | undefined,
    position: GeoCoord,
    label: string,
    title: string,
    color: string,
    options: { image?: string; subtitle?: string } = {}
  ): MonitorAmapMarkerInstance | undefined {
    const map = amapInstance.value
    const AMap = amapSdk.value
    if (!map || !AMap) return marker

    const content = options.image
      ? `<div class="transit-vehicle-marker" style="--marker-color:${color}"><i></i><img src="${options.image}" alt="${escapeHtml(options.subtitle || title)}" width="42" height="28" /><span>${escapeHtml(title)}</span></div>`
      : `<div class="transit-amap-marker" style="--marker-color:${color}"><b>${escapeHtml(label)}</b><span>${escapeHtml(title)}</span>${options.subtitle ? `<em>${escapeHtml(options.subtitle)}</em>` : ''}</div>`
    if (!marker) {
      const nextMarker = new AMap.Marker({
        anchor: 'center',
        content,
        offset: new AMap.Pixel(0, 0),
        position,
        zIndex: label === '车' ? 1200 : 1100
      })
      map.add(nextMarker)
      return nextMarker
    }

    marker.setPosition(position)
    marker.setContent(content)
    marker.setzIndex?.(label === '车' ? 1200 : 1100)
    return marker
  }

  function upsertPolyline(
    polyline: MonitorAmapPolylineInstance | undefined,
    path: GeoCoord[],
    color: string,
    weight: number,
    dashed = false,
    zIndex = dashed ? 155 : 165,
    opacity = dashed ? 0.78 : 0.96
  ): MonitorAmapPolylineInstance | undefined {
    const map = amapInstance.value
    const AMap = amapSdk.value
    if (!map || !AMap) return polyline
    const visiblePath: GeoCoord[] = path.length > 1 ? path : path[0] ? [path[0], path[0]] : []
    const amapPath = visiblePath.map((point) => new AMap.LngLat(point[0], point[1]))

    if (!polyline) {
      const nextPolyline = new AMap.Polyline({
        borderWeight: 1,
        bubble: false,
        isOutline: true,
        lineCap: 'round',
        lineJoin: 'round',
        outlineColor: 'rgba(0,0,0,.55)',
        path: amapPath,
        showDir: !dashed,
        strokeColor: color,
        strokeOpacity: opacity,
        strokeStyle: dashed ? 'dashed' : 'solid',
        strokeWeight: weight,
        zIndex
      })
      map.add(nextPolyline)
      return nextPolyline
    }

    polyline.setOptions?.({
      showDir: !dashed,
      strokeColor: color,
      strokeOpacity: opacity,
      strokeStyle: dashed ? 'dashed' : 'solid',
      strokeWeight: weight,
      zIndex
    })
    polyline.setPath(amapPath)
    return polyline
  }

  function fitActiveTrack(force = false): void {
    const map = amapInstance.value
    const active = mapRouteOrder.value
    if (!map) return
    if (!active) {
      const selected = activeOrder.value
      if (selected) fitPendingVehicle(selected.originGeo)
      return
    }
    if (!force && mapZoom.value >= 11) return

    const current: GeoCoord = [active.longitude, active.latitude]
    if (map.setZoomAndCenter) map.setZoomAndCenter(INITIAL_MAP_ZOOM, current)
    else {
      map.setZoom?.(INITIAL_MAP_ZOOM)
      map.setCenter?.(current)
    }
    syncMapViewState()
  }

  function fitPendingVehicle(origin: GeoCoord): void {
    const map = amapInstance.value
    if (!map) return
    map.setCenter?.(origin)
    if (mapZoom.value !== INITIAL_MAP_ZOOM) map.setZoom?.(INITIAL_MAP_ZOOM)
    syncMapViewState()
  }

  function fitSelectedMapView(force = false): void {
    const selected = activeOrder.value
    if (selected?.status === 'pending') {
      fitPendingVehicle(selected.originGeo)
      return
    }
    fitActiveTrack(force)
  }

  function zoomMap(direction: 'in' | 'out'): void {
    const map = amapInstance.value
    if (!map) return
    if (direction === 'in') map.zoomIn?.()
    else map.zoomOut?.()
    syncMapViewState()
  }

  function resetMapView(): void {
    fitSelectedMapView(true)
  }

  function buildVisibleRoutePath(active: MonitorOrder): GeoCoord[] {
    return dedupeGeoPath([...active.passedPath, ...active.remainingPath.slice(1)])
  }

  function destroyMonitorMap(): void {
    amapInstance.value?.destroy?.()
    amapInstance.value = undefined
    amapSdk.value = undefined
    amapReady.value = false
    vehicleMarkers.clear()
    originMarker = undefined
    destinationMarker = undefined
    routeBasePolyline = undefined
    passedPolyline = undefined
    remainingPolyline = undefined
  }

  function selectOrder(id: string): void {
    screen.selectedOrderId = id
    void nextTick(() => {
      updateChinaMap()
      fitSelectedMapView(true)
    })
  }

  function openOrderDetail(): void {}

  function openTransportAnomalyAdvisor(): void {
    const order = activeOrder.value
    const orderId = String(order?.source.order?.id || '')
    if (!order || !orderId) {
      ElMessage.warning('当前运输记录缺少订单 ID，暂时无法进行异常研判')
      return
    }

    void transportAnomalyAdvisorRef.value?.handleOpen({
      orderId,
      orderNo: order.orderNo
    })
  }

  function contactDriver(): void {
    if (!activeOrder.value) return
    ElMessage.success(`已打开 ${activeOrder.value.driverName} 的联系流程`)
  }

  function exitMonitor(): void {
    if (window.history.length > 1) {
      router.back()
      return
    }
    void router.push('/dashboard/console')
  }

  function sendReminder(): void {
    if (!activeOrder.value) return
    ElMessage.success(`已向 ${activeOrder.value.plateNo} 发送在途提醒`)
  }
</script>

<style scoped lang="scss" src="./modules/in-transit-monitor.scss"></style>
