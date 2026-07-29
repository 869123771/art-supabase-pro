<template>
  <div class="transit-screen" v-loading="screen.loading">
    <div
      ref="viewportRef"
      class="transit-screen__viewport"
      @wheel.capture="handleScreenWheelCapture"
    >
      <div class="transit-screen__stage" :style="screenStageStyle">
        <header class="transit-screen__header">
          <h1>TMS 运输在途监控</h1>
          <nav class="screen-tabs">
            <button
              v-for="item in monitorTabs"
              :key="item.value"
              type="button"
              :class="{ 'is-active': activeMode === item.value }"
              @click="activeMode = item.value"
            >
              {{ item.label }}
            </button>
          </nav>
          <div class="header-status">
            <strong>{{ headerTimeText }}</strong>
            <span><i />系统运行正常</span>
          </div>
        </header>

        <main class="transit-screen__body">
          <section class="monitor-map">
            <div ref="chartRef" class="monitor-map__chart" />
            <div class="monitor-map__heading">
              <strong>{{ monitorHeadingTitle }}</strong>
              <span>{{ activeOrder?.routeName || '暂无线路' }}</span>
            </div>
            <div v-if="activeOrder" class="monitor-map__track-chip">
              {{ activeOrder.plateNo }} · {{ activeOrder.orderNo }}
            </div>
            <div class="monitor-map__tools" :class="{ 'is-wide': activeMode !== 'realtime' }">
              <ElButton circle :icon="ZoomIn" title="放大地图" @click="zoomMap('in')" />
              <ElButton circle :icon="ZoomOut" title="缩小地图" @click="zoomMap('out')" />
              <ElButton circle :icon="RefreshRight" title="定位当前车辆" @click="resetMapView" />
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
            @contact-driver="contactDriver"
            @open-detail="openOrderDetail"
            @send-reminder="sendReminder"
          />
        </main>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import type { UnwrapNestedRefs } from 'vue'
  import { storeToRefs } from 'pinia'
  import { ElMessage } from 'element-plus'
  import { RefreshRight, ZoomIn, ZoomOut } from '@element-plus/icons-vue'
  import { fetchInTransitMonitorList, subscribeInTransitMonitorChanges } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { formatWithDayjs } from '@/utils/time'
  import { useDebounceFn, useIntervalFn, useResizeObserver } from '@vueuse/core'
  import MonitorDetailPanel from './modules/monitor-detail-panel.vue'
  import RealtimeMonitorPanel from './modules/realtime-monitor-panel.vue'
  import VehicleMonitorPanel from './modules/vehicle-monitor-panel.vue'
  import WaybillMonitorPanel from './modules/waybill-monitor-panel.vue'
  import {
    AMAP_PLUGINS,
    DEFAULT_SCREEN_DESIGN_HEIGHT,
    DEFAULT_SCREEN_DESIGN_WIDTH,
    getVehicleImage,
    INITIAL_MAP_CENTER,
    INITIAL_MAP_ZOOM,
    INITIAL_POI_CONCURRENCY,
    MAP_MAX_ZOOM,
    MAP_MIN_ZOOM,
    MONITOR_STATUS_DICT_CODE,
    monitorTabs,
    REALTIME_WAYBILL_STATUSES,
    regionOptions,
    VEHICLE_TYPE_DICT_CODE
  } from './modules/monitor-config'
  import type {
    AlertItem,
    GeoCoord,
    InTransitRecord,
    MapViewState,
    MonitorMode,
    MonitorKeywordState,
    MonitorOrder,
    ReverseGeocodeResult,
    RouteOverlayState,
    ScreenScaleState,
    ScreenState,
    TransitStatus,
    VehiclePoiState
  } from './modules/monitor-types'
  import {
    dedupeGeoPath,
    escapeHtml,
    estimateDistanceKm,
    formatDateTime,
    formatNumber,
    formatRefreshTime,
    formatText,
    getDelayText,
    getMonitorRecordId,
    getRoutePosition,
    isDelayed,
    isRouteVisibleStatus,
    normalizeVehicleTypeCode,
    percentOf,
    resolveArrivalPerformance,
    resolveCurrentLabel,
    resolveEndpointGeo,
    resolveProgress,
    resolveSpeed,
    resolveTransitStatus,
    splitRoutePath,
    toGeoCoord
  } from './modules/monitor-utils'

  defineOptions({ name: 'TmsInTransitMonitor' })

  interface MonitorAmapLngLatLike {
    lng?: number
    lat?: number
    getLng?: () => number
    getLat?: () => number
  }

  interface MonitorAmapPixelLike {
    x?: number
    y?: number
    getX?: () => number
    getY?: () => number
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
    getCenter?: () => MonitorAmapLngLatLike
    getZoom?: () => number
    lngLatToContainer: (lngLat: MonitorAmapLngLatLike) => MonitorAmapPixelLike
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
    plugin: (pluginName: string, callback: () => void) => void
    [key: string]: unknown
  }

  const getLoadedAmap = (): MonitorAmapNamespace => {
    if (!window.AMap) throw new Error('AMap SDK is not loaded')
    return window.AMap as unknown as MonitorAmapNamespace
  }

  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const viewportRef = ref<HTMLDivElement>()
  const chartRef = ref<HTMLDivElement>()
  const amapInstance = shallowRef<MonitorAmapMapInstance>()
  const amapReady = ref(false)
  const liveTick = ref(0)
  const currentTime = ref(new Date().toISOString())
  const activeMode = ref<MonitorMode>('realtime')
  const monitorKeywords = reactive<MonitorKeywordState>({
    vehicle: '',
    waybill: ''
  })
  const mapView: UnwrapNestedRefs<MapViewState> = reactive<MapViewState>({
    center: [...INITIAL_MAP_CENTER],
    zoom: INITIAL_MAP_ZOOM
  })
  const screenScale: UnwrapNestedRefs<ScreenScaleState> = reactive<ScreenScaleState>({
    viewportHeight: DEFAULT_SCREEN_DESIGN_HEIGHT,
    viewportWidth: DEFAULT_SCREEN_DESIGN_WIDTH
  })
  const routeOverlay: UnwrapNestedRefs<RouteOverlayState> = reactive<RouteOverlayState>({
    basePath: '',
    height: 0,
    passedPath: '',
    remainingPath: '',
    visible: false,
    width: 0
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

  const screenStageStyle = computed(() => {
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
  const monitorHeadingTitle = computed(
    () =>
      ({
        realtime: '单车轨迹监控',
        vehicle: '车辆实时位置',
        waybill: '运单运输轨迹'
      })[activeMode.value]
  )

  const monitorStatusOptions = computed<Api.DataCenter.DictListItem[]>(
    () => getDictMap.value[MONITOR_STATUS_DICT_CODE] ?? []
  )

  const monitorOrders = computed<MonitorOrder[]>(() => screen.orders.map(createMonitorOrder))

  const realtimeOrders = computed<MonitorOrder[]>(() =>
    monitorOrders.value.filter(isRealtimeMonitorOrder)
  )

  const modeOrders = computed<MonitorOrder[]>(() =>
    activeMode.value === 'realtime' ? realtimeOrders.value : monitorOrders.value
  )

  const filteredOrders = computed<MonitorOrder[]>(() => {
    const keyword = screen.keyword.trim().toLowerCase()

    return realtimeOrders.value.filter((item) => {
      const matchesStatus = !screen.status || item.status === screen.status
      const matchesRegion = matchesSelectedRegion(item)
      const matchesKeyword =
        !keyword ||
        [item.plateNo, item.orderNo, item.driverName, item.driverPhone, item.routeName]
          .join(' ')
          .toLowerCase()
          .includes(keyword)

      return matchesStatus && matchesRegion && matchesKeyword
    })
  })

  const activeOrder = computed<MonitorOrder | undefined>(() => {
    return (
      modeOrders.value.find((item) => item.id === screen.selectedOrderId) ??
      (activeMode.value === 'realtime' ? filteredOrders.value[0] : modeOrders.value[0])
    )
  })

  const mapRouteOrder = computed<MonitorOrder | undefined>(() => {
    const active = activeOrder.value
    return active && isRouteVisibleStatus(active.status) ? active : undefined
  })

  const overview = computed(() => {
    const orders = modeOrders.value
    const transporting = orders.filter(isRealtimeMonitorOrder).length
    const delayed = orders.filter((item) => item.delayed).length
    const routeCount = new Set(orders.map((item) => item.routeName)).size
    const vehicleCount = new Set(orders.map((item) => item.plateNo)).size
    const cargoCount = orders.reduce((sum, item) => sum + item.cargoBoxes, 0)
    const total = orders.length
    const onTimeRate = total > 0 ? Math.round(((total - delayed) / total) * 100) : 100

    return {
      cargoCount,
      delayedCount: delayed,
      growthRate: Math.max(4, Math.min(18, routeCount + transporting)),
      onTimeRate,
      routeCount,
      todayCount: total,
      transporting,
      vehicleCount
    }
  })

  const overviewBars = computed(() => [
    {
      color: '#4c7dff',
      label: '在途车辆',
      percent: percentOf(overview.value.transporting, Math.max(overview.value.todayCount, 1)),
      value: `${overview.value.transporting}/${overview.value.todayCount}`
    },
    {
      color: '#23d18b',
      label: '准时运输',
      percent: overview.value.onTimeRate,
      value: `${overview.value.onTimeRate}%`
    },
    {
      color: '#ff9f43',
      label: '运输完成率',
      percent: averageProgress.value,
      value: `${averageProgress.value}%`
    }
  ])

  const averageProgress = computed(() => {
    const orders = modeOrders.value
    if (orders.length === 0) return 0
    return Math.round(orders.reduce((sum, item) => sum + item.progress, 0) / orders.length)
  })

  const alertItems = computed<AlertItem[]>(() => {
    const delayedAlerts = realtimeOrders.value
      .filter((item) => item.delayed)
      .map((item) => ({
        content: `${item.orderNo} 预计到达 ${formatDateTime(item.plannedArrivalTime)}`,
        key: `delay-${item.id}`,
        level: 'danger' as const,
        time: formatRefreshTime(screen.lastRefreshTime),
        title: `${item.plateNo} 路线偏离或延误`
      }))

    const missingVehicleAlerts = realtimeOrders.value
      .filter((item) => item.plateNo === '未配车')
      .map((item) => ({
        content: `${item.orderNo} 已进入在途池，请补充配载车辆信息`,
        key: `vehicle-${item.id}`,
        level: 'warning' as const,
        time: formatRefreshTime(screen.lastRefreshTime),
        title: '车辆信息缺失'
      }))

    return [...delayedAlerts, ...missingVehicleAlerts].slice(0, 6)
  })

  watch(filteredOrders, (items) => {
    if (activeMode.value !== 'realtime') return
    if (!items.length) return
    if (!items.some((item) => item.id === screen.selectedOrderId)) {
      screen.selectedOrderId = items[0].id
    }
  })

  watch(modeOrders, (items) => {
    if (!items.some((item) => item.id === screen.selectedOrderId)) {
      screen.selectedOrderId = items[0]?.id
    }
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
    window.addEventListener('resize', resizeScaledScreen)
    window.visualViewport?.addEventListener('resize', resizeScaledScreen)
  })

  onBeforeUnmount(() => {
    unsubscribeMonitorChanges?.()
    window.removeEventListener('resize', resizeScaledScreen)
    window.visualViewport?.removeEventListener('resize', resizeScaledScreen)
    destroyMonitorMap()
  })

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
    try {
      const { data } = await fetchInTransitMonitorList({
        from: 0,
        to: 199
      })

      screen.orders = data ?? []
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
    } catch {
      screen.orders = []
      screen.lastRefreshTime = new Date().toISOString()
      screen.selectedOrderId = undefined
    } finally {
      screen.loading = false
    }
  }

  function createMonitorOrder(row: InTransitRecord): MonitorOrder {
    const id = getMonitorRecordId(row)
    const order = row.order
    const origin = formatText(row.originCity || order?.originStation)
    const destination = formatText(row.destinationCity || order?.destinationStation)
    const originGeo = resolveEndpointGeo(
      row,
      'origin',
      row.shipperLongitude ?? order?.shippingLongitude,
      row.shipperLatitude ?? order?.shippingLatitude,
      origin
    )
    const destinationGeo = resolveEndpointGeo(
      row,
      'destination',
      row.receiverLongitude ?? order?.receivingLongitude,
      row.receiverLatitude ?? order?.receivingLatitude,
      destination
    )
    const delayed = isDelayed(row)
    const status = resolveTransitStatus(row, delayed)
    const arrivalPerformance = resolveArrivalPerformance(row)
    const progress = resolveProgress(row, id, status, liveTick.value)
    const routePath = getDrivingRoutePath(id)
    const currentGeo =
      routePath.length > 1
        ? getRoutePosition(routePath, progress).coord
        : status === 'arrived'
          ? destinationGeo
          : originGeo
    const routeSegments = splitRoutePath(routePath, currentGeo, progress)
    const distance = estimateDistanceKm(originGeo, destinationGeo)
    const vehicleTypeCode = normalizeVehicleTypeCode(
      row.vehicle?.vehicleType || order?.dispatchVehicleType
    )
    const vehicleTypeLabel = getDictLabel(
      VEHICLE_TYPE_DICT_CODE,
      vehicleTypeCode,
      vehicleTypeCode || '运输车辆'
    )
    const cargoWeightText =
      row.cargoWeightTon !== null && row.cargoWeightTon !== undefined
        ? `${formatNumber(row.cargoWeightTon)} 吨`
        : `${formatNumber(order?.cargoWeightTotal)} kg`

    return {
      arrivalDelayed: arrivalPerformance.delayed,
      arrivalText: arrivalPerformance.text,
      cargoBoxes: Number(row.cargoQuantity ?? order?.cargoQuantityTotal ?? 0),
      cargoSummary: [
        {
          label: '货物类型',
          value:
            row.cargoName || order?.cargoItems?.map((item) => item.cargoName).find(Boolean) || '-'
        },
        {
          label: '总数量',
          value: `${formatNumber(row.cargoQuantity ?? order?.cargoQuantityTotal, 0)} 件`
        },
        { label: '总重量', value: cargoWeightText },
        {
          label: '总体积',
          value: `${formatNumber(row.cargoVolumeM3 ?? order?.cargoVolumeTotal, 3)} 方`
        }
      ],
      currentLabel: resolveCurrentLabel(row, progress),
      completedKm: Math.round(distance * (progress / 100)),
      delayed,
      delayText: getDelayText(row.plannedUnloadTime ?? order?.plannedArrivalTime),
      destination,
      destinationGeo,
      driverName: formatText(row.driver?.driverName || order?.dispatchDriverName, '未派司机'),
      driverPhone: formatText(row.driver?.phone || order?.dispatchDriverPhone, '未登记电话'),
      id,
      latitude: currentGeo[1],
      longitude: currentGeo[0],
      orderNo: formatText(row.waybillNo || order?.orderNo),
      origin,
      originGeo,
      plateNo: formatText(row.vehicle?.plateNo || order?.dispatchPlateNo, '未配车'),
      plannedArrivalTime: row.plannedUnloadTime ?? order?.plannedArrivalTime,
      plannedDepartureTime: row.plannedLoadTime ?? order?.plannedDepartureTime,
      passedPath: routeSegments.passedPath,
      progress,
      remainingKm: Math.max(0, Math.round(distance * (1 - progress / 100))),
      remainingPath: routeSegments.remainingPath,
      routePath,
      routeName: [origin, order?.transferStation, destination].filter(Boolean).join(' - '),
      source: row,
      speed: resolveSpeed(row, status, id),
      status,
      statusColor: getMonitorStatusColor(status),
      statusLabel: getMonitorStatusLabel(status),
      totalKm: distance,
      vehicleImage: getVehicleImage(vehicleTypeCode),
      vehicleType: vehicleTypeCode,
      vehicleTypeCode,
      vehicleTypeLabel
    }
  }

  async function initChinaMap(): Promise<void> {
    if (!chartRef.value) return

    try {
      const AMap = await loadAmap()
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
      ElMessage.warning(error instanceof Error ? error.message : '高德地图加载失败')
    }

    updateChinaMap()
    fitSelectedMapView(true)
  }

  function updateChinaMap(): void {
    const map = amapInstance.value
    if (!map || !window.AMap || !amapReady.value) return

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
    scheduleRouteOverlayUpdate()
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
    resetRouteOverlay()
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
    const center = map.getCenter?.()
    if (center) mapView.center = [Number(center.lng), Number(center.lat)]
    const zoom = map.getZoom?.()
    if (typeof zoom === 'number') mapView.zoom = Math.round(zoom)
    scheduleRouteOverlayUpdate()
  }

  function resizeChinaMap(): void {
    const applyResize = () => {
      amapInstance.value?.resize?.()
      scheduleRouteOverlayUpdate()
    }

    window.requestAnimationFrame(() => {
      applyResize()
      window.setTimeout(applyResize, 120)
    })
  }

  async function loadAmap(): Promise<MonitorAmapNamespace> {
    if (window.AMap) return getLoadedAmap()

    const amapKey = import.meta.env.VITE_AMAP_KEY
    if (!amapKey) throw new Error('请先配置 VITE_AMAP_KEY')

    const securityJsCode = import.meta.env.VITE_AMAP_SECURITY_JS_CODE
    if (securityJsCode) {
      window._AMapSecurityConfig = { securityJsCode }
    }

    const existingScript = document.querySelector<HTMLScriptElement>('script[data-art-amap]')
    if (existingScript) {
      await new Promise<void>((resolve, reject) => {
        existingScript.addEventListener('load', () => resolve(), { once: true })
        existingScript.addEventListener('error', () => reject(new Error('高德地图加载失败')), {
          once: true
        })
      })
      return getLoadedAmap()
    }

    await new Promise<void>((resolve, reject) => {
      const script = document.createElement('script')
      script.dataset.artAmap = 'true'
      script.src = `https://webapi.amap.com/maps?v=2.0&key=${amapKey}&plugin=${AMAP_PLUGINS.join(',')}`
      script.async = true
      script.onload = () => resolve()
      script.onerror = () => reject(new Error('高德地图加载失败'))
      document.head.appendChild(script)
    })

    return getLoadedAmap()
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
    await loadAmapPlugin(AMap, 'AMap.Geocoder')

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

    const AMap = window.AMap ? getLoadedAmap() : undefined
    if (!AMap) return
    drivingRouteRequests.add(order.id)

    try {
      await loadAmapPlugin(AMap, 'AMap.Driving')
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

  function loadAmapPlugin(AMap: MonitorAmapNamespace, pluginName: string): Promise<void> {
    const pluginConstructorName = pluginName.replace('AMap.', '')
    if (AMap[pluginConstructorName]) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const timeout = window.setTimeout(() => reject(new Error(`${pluginName} 服务加载超时`)), 8000)
      AMap.plugin(pluginName, () => {
        window.clearTimeout(timeout)
        if (AMap[pluginConstructorName]) resolve()
        else reject(new Error(`${pluginName} 服务加载失败`))
      })
    })
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
    if (!map || !window.AMap) return marker
    const AMap = getLoadedAmap()

    const content = options.image
      ? `<div class="transit-vehicle-marker" style="--marker-color:${color}"><i></i><img src="${options.image}" alt="${escapeHtml(options.subtitle || title)}" /><span>${escapeHtml(title)}</span></div>`
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
    if (!map || !window.AMap) return polyline
    const AMap = getLoadedAmap()
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
    if (!force && mapView.zoom >= 11) return

    const current: GeoCoord = [active.longitude, active.latitude]
    if (map.setZoomAndCenter) map.setZoomAndCenter(INITIAL_MAP_ZOOM, current)
    else {
      map.setZoom?.(INITIAL_MAP_ZOOM)
      map.setCenter?.(current)
    }
    syncMapViewState()
    scheduleRouteOverlayUpdate()
  }

  function fitPendingVehicle(origin: GeoCoord): void {
    const map = amapInstance.value
    if (!map) return
    map.setCenter?.(origin)
    if (mapView.zoom !== INITIAL_MAP_ZOOM) map.setZoom?.(INITIAL_MAP_ZOOM)
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

  function scheduleRouteOverlayUpdate(): void {
    window.requestAnimationFrame(updateRouteOverlay)
  }

  function updateRouteOverlay(): void {
    const map = amapInstance.value
    const active = mapRouteOrder.value
    const chartElement = chartRef.value
    const chartWidth = chartElement?.clientWidth ?? 0
    const chartHeight = chartElement?.clientHeight ?? 0
    if (!map || !active || !chartWidth || !chartHeight) {
      resetRouteOverlay()
      return
    }

    const basePath = toSvgPath(buildVisibleRoutePath(active))
    const passedPath = toSvgPath(active.passedPath)
    const remainingPath = toSvgPath(active.remainingPath)
    Object.assign(routeOverlay, {
      basePath,
      height: chartHeight,
      passedPath,
      remainingPath,
      visible: Boolean(basePath),
      width: chartWidth
    })
  }

  function resetRouteOverlay(): void {
    Object.assign(routeOverlay, {
      basePath: '',
      height: 0,
      passedPath: '',
      remainingPath: '',
      visible: false,
      width: 0
    })
  }

  function toSvgPath(path: GeoCoord[]): string {
    const map = amapInstance.value
    if (!map || !window.AMap || path.length < 2) return ''
    const AMap = getLoadedAmap()

    return path
      .map((point, index) => {
        const pixel = map.lngLatToContainer(new AMap.LngLat(point[0], point[1]))
        const x = Number((pixel.x ?? pixel.getX?.() ?? 0).toFixed(2))
        const y = Number((pixel.y ?? pixel.getY?.() ?? 0).toFixed(2))
        return `${index === 0 ? 'M' : 'L'} ${x} ${y}`
      })
      .join(' ')
  }

  function destroyMonitorMap(): void {
    amapInstance.value?.destroy?.()
    amapInstance.value = undefined
    amapReady.value = false
    vehicleMarkers.clear()
    originMarker = undefined
    destinationMarker = undefined
    routeBasePolyline = undefined
    passedPolyline = undefined
    remainingPolyline = undefined
    resetRouteOverlay()
  }

  function matchesSelectedRegion(item: MonitorOrder): boolean {
    if (!screen.region) return true
    const region = regionOptions.find((option) => option.value === screen.region)
    if (!region) return true

    const routeText = [item.origin, item.destination, item.routeName, item.currentLabel].join('')
    return region.keywords.some((keyword) => routeText.includes(keyword))
  }

  function isRealtimeMonitorOrder(item: MonitorOrder): boolean {
    const waybillStatus = String(item.source.status ?? '')
      .trim()
      .toLowerCase()
    return REALTIME_WAYBILL_STATUSES.has(waybillStatus)
  }

  function getPreferredMonitorRecordId(rows: InTransitRecord[]): string | undefined {
    const preferred = rows.find((row) => {
      const status = resolveTransitStatus(row, isDelayed(row))
      return ['transporting', 'delayed'].includes(status)
    })
    const row = preferred ?? rows.find((item) => resolveTransitStatus(item, false) === 'arrived')
    return row ? getMonitorRecordId(row) : rows[0] ? getMonitorRecordId(rows[0]) : undefined
  }

  function getDrivingRoutePath(id: string): GeoCoord[] {
    return drivingRoutePaths.get(id) ?? []
  }

  function getMonitorStatusItem(status: TransitStatus): Api.DataCenter.DictListItem | undefined {
    return monitorStatusOptions.value.find((item) => String(item.value) === status)
  }

  function getMonitorStatusLabel(status: TransitStatus): string {
    return getMonitorStatusItem(status)?.label || status
  }

  function getMonitorStatusColor(status: TransitStatus): string {
    return getMonitorStatusItem(status)?.color || '#409EFF'
  }

  function selectOrder(id: string): void {
    screen.selectedOrderId = id
    void nextTick(() => {
      updateChinaMap()
      fitSelectedMapView(true)
    })
  }

  function openOrderDetail(): void {}

  function contactDriver(): void {
    if (!activeOrder.value) return
    ElMessage.success(`已打开 ${activeOrder.value.driverName} 的联系流程`)
  }

  function sendReminder(): void {
    if (!activeOrder.value) return
    ElMessage.success(`已向 ${activeOrder.value.plateNo} 发送在途提醒`)
  }

  function getDictLabel(dictCode: string, value?: string | number | null, fallback = '-'): string {
    const normalizedValue = String(value ?? '').trim()
    if (!normalizedValue) return fallback

    const dictItem = getDictMap.value[dictCode]?.find(
      (item) => String(item.value) === normalizedValue || String(item.code) === normalizedValue
    )
    return dictItem?.label || dictItem?.name || fallback
  }
</script>

<style scoped lang="scss" src="./modules/in-transit-monitor.scss"></style>
