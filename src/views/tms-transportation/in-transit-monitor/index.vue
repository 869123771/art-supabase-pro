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
            <button type="button" class="is-active">实时监控</button>
            <button type="button">历史轨迹</button>
            <button type="button">统计分析</button>
          </nav>
          <div class="header-status">
            <strong>{{ headerTimeText }}</strong>
            <span><i />系统运行正常</span>
            <button type="button" @click="goHome">返回主页</button>
          </div>
        </header>

        <main class="transit-screen__body">
          <section class="monitor-map">
            <div ref="chartRef" class="monitor-map__chart" />
            <div class="monitor-map__heading">
              <strong>单车轨迹监控</strong>
              <span>{{ activeOrder?.routeName || '暂无线路' }}</span>
            </div>
            <div v-if="activeOrder" class="monitor-map__track-chip">
              {{ activeOrder.plateNo }} · {{ activeOrder.orderNo }}
            </div>
            <div class="monitor-map__tools">
              <ElButton circle :icon="ZoomIn" title="放大地图" @click="zoomMap('in')" />
              <ElButton circle :icon="ZoomOut" title="缩小地图" @click="zoomMap('out')" />
              <ElButton circle :icon="RefreshRight" title="定位当前车辆" @click="resetMapView" />
            </div>

            <section class="screen-panel map-float map-float--overview">
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

            <section v-if="alertItems.length > 0" class="screen-panel map-float map-float--alerts">
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

          <aside class="transit-screen__left">
            <section class="screen-panel screen-panel--filters">
              <ElInput
                v-model="screen.keyword"
                :prefix-icon="Search"
                clearable
                placeholder="请输入车辆运单号"
              />
              <ElSelect v-model="screen.status" clearable placeholder="所有状态">
                <ElOption
                  v-for="item in monitorStatusOptions"
                  :key="String(item.value)"
                  :label="item.label"
                  :value="String(item.value)"
                />
              </ElSelect>
              <ElSelect v-model="screen.region" clearable placeholder="所有区域">
                <ElOption
                  v-for="item in regionOptions"
                  :key="item.value"
                  :label="item.label"
                  :value="item.value"
                />
              </ElSelect>
              <div class="transit-metrics">
                <div class="transit-metric">
                  <span>今日运输量</span>
                  <strong>{{ overview.todayCount }}</strong>
                  <em>较昨日 +{{ overview.growthRate }}%</em>
                </div>
                <div class="transit-metric">
                  <span>准时到达率</span>
                  <strong>{{ overview.onTimeRate }}%</strong>
                  <em :class="{ 'is-warning': overview.delayedCount > 0 }">
                    延误 {{ overview.delayedCount }} 单
                  </em>
                </div>
              </div>
            </section>

            <section class="screen-panel screen-panel--list">
              <div class="screen-panel__title">
                <strong>在线车辆({{ filteredOrders.length }}/{{ monitorOrders.length }})</strong>
              </div>
              <ElScrollbar class="vehicle-list">
                <button
                  v-for="item in filteredOrders"
                  :key="item.id"
                  type="button"
                  class="vehicle-card"
                  :class="{ 'is-active': item.id === screen.selectedOrderId }"
                  @click="selectOrder(item.id)"
                >
                  <div class="vehicle-card__top">
                    <strong>{{ item.plateNo }}</strong>
                    <span
                      class="vehicle-card__status"
                      :style="{
                        color: item.statusColor,
                        backgroundColor: withAlpha(item.statusColor, 0.18)
                      }"
                    >
                      {{ item.statusLabel }}
                    </span>
                  </div>
                  <p>
                    <ArtDictDisplay
                      dict-code="vehicleType"
                      :value="getDictDisplayValue('vehicleType', item.vehicleTypeCode)"
                      display="text"
                      :empty-text="item.vehicleTypeLabel"
                    />
                  </p>
                  <div class="vehicle-card__line">
                    <span>{{ item.driverName }}</span>
                    <span>{{ item.progress }}%</span>
                  </div>
                  <div class="vehicle-card__geo">
                    经纬度：{{ formatCoordinate(item.longitude) }},
                    {{ formatCoordinate(item.latitude) }}
                  </div>
                  <div class="vehicle-card__order">
                    运单：{{ item.orderNo }}
                    <span
                      v-if="item.status === 'arrived'"
                      class="vehicle-card__arrival"
                      :class="{ 'is-delayed': item.arrivalDelayed }"
                    >
                      <ElIcon>
                        <Clock v-if="item.arrivalDelayed" />
                        <CircleCheckFilled v-else />
                      </ElIcon>
                      {{ item.arrivalText }}
                    </span>
                    <em v-else-if="item.delayed">延误{{ item.delayText }}</em>
                  </div>
                </button>
                <ElEmpty
                  v-if="filteredOrders.length === 0"
                  description="暂无在途车辆"
                  :image-size="72"
                />
              </ElScrollbar>
            </section>
          </aside>

          <aside class="transit-screen__right">
            <section class="screen-panel screen-panel--detail">
              <div class="screen-panel__title">
                <strong>车辆详情</strong>
                <ElButton link :icon="MoreFilled" @click="openOrderDetail" />
              </div>

              <div class="detail-scroll">
                <template v-if="activeOrder">
                  <div class="detail-vehicle">
                    <div class="detail-vehicle__icon">
                      <img :src="activeOrder.vehicleImage" :alt="activeOrder.vehicleTypeLabel" />
                    </div>
                    <div>
                      <strong>{{ activeOrder.plateNo }}</strong>
                      <p>
                        <ArtDictDisplay
                          dict-code="vehicleType"
                          :value="getDictDisplayValue('vehicleType', activeOrder.vehicleTypeCode)"
                          display="text"
                          :empty-text="activeOrder.vehicleTypeLabel"
                        />
                      </p>
                    </div>
                  </div>

                  <div class="detail-speed">
                    <div>
                      <span>当前速度</span>
                      <strong>{{ activeOrder.speed }}km/h</strong>
                    </div>
                    <div>
                      <span>剩余里程</span>
                      <strong>{{ activeOrder.remainingKm }}km</strong>
                    </div>
                  </div>

                  <div class="detail-waybill">
                    <span>当前运单</span>
                    <strong>{{ activeOrder.orderNo }}</strong>
                    <div class="detail-route">
                      <div>
                        <b>{{ activeOrder.origin }}</b>
                        <em>{{ formatDateTime(activeOrder.plannedDepartureTime) }}</em>
                      </div>
                      <i>{{ activeOrder.progress }}%</i>
                      <div>
                        <b>{{ activeOrder.destination }}</b>
                        <em>{{ formatDateTime(activeOrder.plannedArrivalTime) }}</em>
                      </div>
                    </div>
                    <div class="detail-progress">
                      <b :style="{ width: `${activeOrder.progress}%` }" />
                    </div>
                  </div>

                  <div class="detail-cargo">
                    <strong>货物信息</strong>
                    <p v-for="item in activeOrder.cargoSummary" :key="item.label">
                      <span>{{ item.label }}</span>
                      <b>{{ item.value }}</b>
                    </p>
                  </div>

                  <div class="detail-driver">
                    <div class="detail-driver__avatar">{{
                      activeOrder.driverName.slice(0, 1)
                    }}</div>
                    <div>
                      <strong>{{ activeOrder.driverName }}</strong>
                      <p>{{ activeOrder.driverPhone }}</p>
                    </div>
                  </div>

                  <div class="detail-actions">
                    <ElButton type="primary" :icon="Phone" @click="contactDriver"
                      >联系司机</ElButton
                    >
                    <ElButton type="warning" :icon="Warning" @click="sendReminder"
                      >发送提醒</ElButton
                    >
                  </div>
                </template>

                <ElEmpty v-else description="暂无车辆详情" :image-size="86" />
              </div>
            </section>
          </aside>
        </main>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import type { UnwrapNestedRefs } from 'vue'
  import dayjs from 'dayjs'
  import { storeToRefs } from 'pinia'
  import { ElMessage } from 'element-plus'
  import {
    CircleCheckFilled,
    Clock,
    MoreFilled,
    Phone,
    RefreshRight,
    Search,
    Warning,
    ZoomIn,
    ZoomOut
  } from '@element-plus/icons-vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import { fetchInTransitMonitorList, subscribeInTransitMonitorChanges } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { formatWithDayjs } from '@/utils/time'
  import { useDebounceFn, useIntervalFn, useResizeObserver } from '@vueuse/core'
  import defaultVehicleImage from '@/assets/images/tms/vehicles/default.svg?url'
  import largeCityBusImage from '@/assets/images/tms/vehicles/large-city-bus.svg?url'
  import mediumBusImage from '@/assets/images/tms/vehicles/medium-bus.svg?url'
  import smallBusImage from '@/assets/images/tms/vehicles/small-bus.svg?url'
  import specialVehicleImage from '@/assets/images/tms/vehicles/special-vehicle.svg?url'
  import truckImage from '@/assets/images/tms/vehicles/truck.svg?url'

  defineOptions({ name: 'TmsInTransitMonitor' })

  type InTransitRecord = Api.Tms.InTransit.MonitorRecord
  type TransitStatus = 'pending' | 'transporting' | 'arrived' | 'delayed'
  type GeoCoord = [number, number]

  const INITIAL_MAP_CENTER: GeoCoord = [105.5, 34.2]
  const INITIAL_MAP_ZOOM = 5
  const MAP_MIN_ZOOM = 4
  const MAP_MAX_ZOOM = 18
  const DEFAULT_SCREEN_DESIGN_WIDTH = 1920
  const DEFAULT_SCREEN_DESIGN_HEIGHT = 1080
  const AMAP_PLUGINS = ['AMap.Scale', 'AMap.Driving']
  const VEHICLE_TYPE_DICT_CODE = 'vehicleType'
  const MONITOR_STATUS_DICT_CODE = 'tmsInTransitMonitorStatus'
  const VEHICLE_IMAGE_MAP: Record<string, string> = {
    'large-city-bus': largeCityBusImage,
    'medium-bus': mediumBusImage,
    'small-bus': smallBusImage,
    'special-vehicle': specialVehicleImage,
    truck: truckImage
  }
  const OUT_OF_TRANSIT_MONITOR_STATUSES = new Set([
    'cancelled',
    'canceled',
    'closed',
    '已取消',
    '已关闭'
  ])
  const ACTIVE_TRANSIT_MONITOR_STATUSES = new Set([
    'transporting',
    'in_transit',
    'running',
    'processing',
    'in_progress',
    'ongoing'
  ])
  interface ScreenState {
    keyword: string
    lastRefreshTime?: string
    loading: boolean
    orders: InTransitRecord[]
    region: string
    selectedOrderId?: string
    status: TransitStatus | ''
  }

  interface MonitorOrder {
    arrivalDelayed: boolean
    arrivalText: string
    cargoBoxes: number
    cargoSummary: Array<{ label: string; value: string }>
    currentLabel: string
    delayed: boolean
    delayText: string
    destination: string
    destinationGeo: GeoCoord
    driverName: string
    driverPhone: string
    id: string
    latitude: number
    longitude: number
    orderNo: string
    origin: string
    originGeo: GeoCoord
    plateNo: string
    plannedArrivalTime?: string | null
    plannedDepartureTime?: string | null
    passedPath: GeoCoord[]
    progress: number
    remainingKm: number
    remainingPath: GeoCoord[]
    routePath: GeoCoord[]
    routeName: string
    source: InTransitRecord
    speed: number
    status: TransitStatus
    statusColor: string
    statusLabel: string
    vehicleType: string
    vehicleTypeCode: string
    vehicleTypeLabel: string
    vehicleImage: string
  }

  interface AlertItem {
    content: string
    key: string
    level: 'danger' | 'warning' | 'info'
    time: string
    title: string
  }

  interface MapViewState {
    center: GeoCoord
    zoom: number
  }

  interface ScreenScaleState {
    viewportHeight: number
    viewportWidth: number
  }

  interface RouteOverlayState {
    basePath: string
    height: number
    passedPath: string
    remainingPath: string
    visible: boolean
    width: number
  }

  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const viewportRef = ref<HTMLDivElement>()
  const chartRef = ref<HTMLDivElement>()
  const amapInstance = shallowRef<any>()
  const amapReady = ref(false)
  const liveTick = ref(0)
  const currentTime = ref(new Date().toISOString())
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
  const vehicleMarkers = new Map<string, any>()
  const drivingRoutePaths = reactive(new Map<string, GeoCoord[]>())
  const drivingRouteRequests = new Set<string>()
  let originMarker: any
  let destinationMarker: any
  let routeBasePolyline: any
  let passedPolyline: any
  let remainingPolyline: any
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

  const stationGeoPositions: Array<{ keywords: string[]; coord: GeoCoord }> = [
    { keywords: ['北京', '京'], coord: [116.4074, 39.9042] },
    { keywords: ['天津'], coord: [117.2009, 39.0842] },
    { keywords: ['太原', '晋'], coord: [112.5492, 37.8706] },
    { keywords: ['郑州', '豫'], coord: [113.6254, 34.7466] },
    { keywords: ['西安', '陕'], coord: [108.9402, 34.3416] },
    { keywords: ['上海', '沪'], coord: [121.4737, 31.2304] },
    { keywords: ['南京', '宁'], coord: [118.7969, 32.0603] },
    { keywords: ['苏州', '苏'], coord: [120.5853, 31.2989] },
    { keywords: ['杭州', '杭'], coord: [120.1551, 30.2741] },
    { keywords: ['义乌', '金华'], coord: [120.0751, 29.3068] },
    { keywords: ['武汉', '鄂'], coord: [114.3054, 30.5931] },
    { keywords: ['长沙', '湘'], coord: [112.9388, 28.2282] },
    { keywords: ['南昌', '赣'], coord: [115.8582, 28.682] },
    { keywords: ['赣州'], coord: [114.935, 25.8311] },
    { keywords: ['广州', '粤'], coord: [113.2644, 23.1291] },
    { keywords: ['成都', '川'], coord: [104.0665, 30.5723] },
    { keywords: ['重庆', '渝'], coord: [106.5516, 29.563] },
    { keywords: ['贵阳', '黔'], coord: [106.6302, 26.647] },
    { keywords: ['昆明', '滇'], coord: [102.8329, 24.8801] }
  ]

  const regionOptions = [
    {
      label: '华东区域',
      value: 'east',
      keywords: ['上海', '杭州', '南京', '苏州', '义乌', '金华']
    },
    { label: '华北区域', value: 'north', keywords: ['北京', '天津', '太原', '石家庄'] },
    { label: '华中区域', value: 'central', keywords: ['郑州', '武汉', '长沙', '南昌'] },
    { label: '华南区域', value: 'south', keywords: ['广州', '深圳', '佛山', '赣州'] },
    { label: '西南区域', value: 'southwest', keywords: ['成都', '重庆', '贵阳', '昆明'] },
    { label: '西北区域', value: 'northwest', keywords: ['西安', '兰州', '银川', '乌鲁木齐'] }
  ]

  const monitorStatusOptions = computed<Api.DataCenter.DictListItem[]>(
    () => getDictMap.value[MONITOR_STATUS_DICT_CODE] ?? []
  )

  const monitorOrders = computed<MonitorOrder[]>(() => screen.orders.map(createMonitorOrder))

  const filteredOrders = computed<MonitorOrder[]>(() => {
    const keyword = screen.keyword.trim().toLowerCase()

    return monitorOrders.value.filter((item) => {
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
      monitorOrders.value.find((item) => item.id === screen.selectedOrderId) ??
      filteredOrders.value[0] ??
      monitorOrders.value[0]
    )
  })

  const mapRouteOrder = computed<MonitorOrder | undefined>(() => {
    const active = activeOrder.value
    return active && isRouteVisibleStatus(active.status) ? active : undefined
  })

  const overview = computed(() => {
    const transporting = monitorOrders.value.filter((item) => item.status === 'transporting').length
    const delayed = monitorOrders.value.filter((item) => item.delayed).length
    const routeCount = new Set(monitorOrders.value.map((item) => item.routeName)).size
    const vehicleCount = new Set(monitorOrders.value.map((item) => item.plateNo)).size
    const cargoCount = monitorOrders.value.reduce((sum, item) => sum + item.cargoBoxes, 0)
    const total = monitorOrders.value.length
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
    if (monitorOrders.value.length === 0) return 0
    return Math.round(
      monitorOrders.value.reduce((sum, item) => sum + item.progress, 0) / monitorOrders.value.length
    )
  })

  const alertItems = computed<AlertItem[]>(() => {
    const delayedAlerts = monitorOrders.value
      .filter((item) => item.delayed)
      .map((item) => ({
        content: `${item.orderNo} 预计到达 ${formatDateTime(item.plannedArrivalTime)}`,
        key: `delay-${item.id}`,
        level: 'danger' as const,
        time: formatRefreshTime(screen.lastRefreshTime),
        title: `${item.plateNo} 路线偏离或延误`
      }))

    const missingVehicleAlerts = monitorOrders.value
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
    if (!items.length) return
    if (!items.some((item) => item.id === screen.selectedOrderId)) {
      screen.selectedOrderId = items[0].id
    }
  })

  watch([activeOrder, () => liveTick.value], () => {
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

      screen.orders = (data ?? []).filter(isActiveMonitorRecord)
      screen.lastRefreshTime = new Date().toISOString()
      if (!screen.orders.some((row) => getMonitorRecordId(row) === screen.selectedOrderId)) {
        screen.selectedOrderId = getPreferredMonitorRecordId(screen.orders)
      }
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
    const progress = resolveProgress(row, id, status)
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
      vehicleImage: getVehicleImage(vehicleTypeCode),
      vehicleType: vehicleTypeCode,
      vehicleTypeCode,
      vehicleTypeLabel
    }
  }

  function isActiveMonitorRecord(row: InTransitRecord): boolean {
    const waybillStatus = String(row.status ?? '')
      .trim()
      .toLowerCase()
    const orderStatus = String(row.order?.orderStatus ?? '')
      .trim()
      .toLowerCase()
    return (
      ACTIVE_TRANSIT_MONITOR_STATUSES.has(waybillStatus) &&
      !OUT_OF_TRANSIT_MONITOR_STATUSES.has(waybillStatus) &&
      !OUT_OF_TRANSIT_MONITOR_STATUSES.has(orderStatus)
    )
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
    const AMap = window.AMap
    if (!map || !AMap || !amapReady.value) return

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

    monitorOrders.value.forEach((item) => {
      activeIds.add(item.id)
      const position: GeoCoord =
        item.status === 'pending' ? item.originGeo : [item.longitude, item.latitude]
      vehicleMarkers.set(
        item.id,
        upsertMarker(
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
      )
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

  function removeMapObject(object: any): undefined {
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

  async function loadAmap(): Promise<any> {
    if (window.AMap) return window.AMap

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
      return window.AMap
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

    return window.AMap
  }

  async function ensureDrivingRoute(order: MonitorOrder): Promise<void> {
    if (drivingRoutePaths.has(order.id) || drivingRouteRequests.has(order.id)) return

    const AMap = window.AMap
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

  function loadAmapPlugin(AMap: any, pluginName: string): Promise<void> {
    if (AMap.Driving) return Promise.resolve()

    return new Promise((resolve, reject) => {
      const timeout = window.setTimeout(() => reject(new Error('驾车路线服务加载超时')), 8000)
      AMap.plugin(pluginName, () => {
        window.clearTimeout(timeout)
        if (AMap.Driving) resolve()
        else reject(new Error('驾车路线服务加载失败'))
      })
    })
  }

  function searchDrivingRoute(
    AMap: any,
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
        (status: string, result: any) => {
          if (status !== 'complete') {
            reject(new Error('驾车路线规划失败'))
            return
          }

          const path = (result.routes?.[0]?.steps ?? [])
            .flatMap((step: any) => step.path ?? [])
            .map((point: any) =>
              toGeoCoord(point.lng ?? point.getLng?.(), point.lat ?? point.getLat?.())
            )
            .filter((point: GeoCoord | undefined): point is GeoCoord => Boolean(point))
          resolve(dedupeGeoPath([origin, ...path, destination]))
        }
      )
    })
  }

  function upsertMarker(
    marker: any,
    position: GeoCoord,
    label: string,
    title: string,
    color: string,
    options: { image?: string; subtitle?: string } = {}
  ): any {
    const map = amapInstance.value
    const AMap = window.AMap
    if (!map || !AMap) return marker

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
    polyline: any,
    path: GeoCoord[],
    color: string,
    weight: number,
    dashed = false,
    zIndex = dashed ? 155 : 165,
    opacity = dashed ? 0.78 : 0.96
  ): any {
    const map = amapInstance.value
    const AMap = window.AMap
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
    const AMap = window.AMap
    if (!map || !AMap || path.length < 2) return ''

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

  function getMonitorRecordId(row: InTransitRecord): string {
    return String(row.id || row.waybillNo)
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

  function getRoutePosition(path: GeoCoord[], progress: number): { coord: GeoCoord } {
    if (path.length === 0) return { coord: INITIAL_MAP_CENTER }
    if (path.length === 1) return { coord: path[0] }

    const targetIndex = clamp(Math.round((progress / 100) * (path.length - 1)), 0, path.length - 1)

    return {
      coord: path[targetIndex]
    }
  }

  function splitRoutePath(
    routePath: GeoCoord[],
    current: GeoCoord,
    progress: number
  ): { passedPath: GeoCoord[]; remainingPath: GeoCoord[] } {
    if (routePath.length <= 1) {
      return {
        passedPath: [current],
        remainingPath: [current]
      }
    }

    const segmentIndex = clamp(
      Math.floor((progress / 100) * (routePath.length - 1)),
      0,
      routePath.length - 2
    )

    return {
      passedPath: dedupeGeoPath([...routePath.slice(0, segmentIndex + 1), current]),
      remainingPath: dedupeGeoPath([current, ...routePath.slice(segmentIndex + 1)])
    }
  }

  function resolveEndpointGeo(
    row: InTransitRecord,
    endpoint: 'origin' | 'destination',
    longitude: number | string | null | undefined,
    latitude: number | string | null | undefined,
    fallbackText: string
  ): GeoCoord {
    const directGeo = toGeoCoord(longitude, latitude)
    if (directGeo) return directGeo

    const routePointGeo = getRoutePointGeo(row, endpoint)
    if (routePointGeo) return routePointGeo

    return resolveStationGeo(fallbackText)
  }

  function getRoutePointGeo(
    row: InTransitRecord,
    endpoint: 'origin' | 'destination'
  ): GeoCoord | undefined {
    const point = row.routePoints?.find((item) => {
      const type = String(item.type ?? '').toLowerCase()
      if (endpoint === 'origin') return ['shipper', 'origin', 'start', 'load'].includes(type)
      return ['receiver', 'destination', 'end', 'unload'].includes(type)
    })
    if (!point) return undefined
    return toGeoCoord(point.longitude ?? point.lng, point.latitude ?? point.lat)
  }

  function toGeoCoord(
    longitude: number | string | null | undefined,
    latitude: number | string | null | undefined
  ): GeoCoord | undefined {
    const lng = Number(longitude)
    const lat = Number(latitude)
    if (!Number.isFinite(lng) || !Number.isFinite(lat)) return undefined
    if (Math.abs(lng) > 180 || Math.abs(lat) > 90) return undefined
    return [Number(lng.toFixed(6)), Number(lat.toFixed(6))]
  }

  function resolveStationGeo(text: string): GeoCoord {
    const normalized = text.trim()
    const matched = stationGeoPositions.find((item) =>
      item.keywords.some((keyword) => normalized.includes(keyword))
    )
    if (matched) return matched.coord

    const hash = hashText(normalized)
    return [86 + (hash % 36), 22 + ((hash >> 3) % 20)]
  }

  function resolveProgress(row: InTransitRecord, seed: string, status: TransitStatus): number {
    if (status === 'pending') return 0
    if (status === 'arrived') return 100

    const departure = dayjs(row.loadedAt || row.plannedLoadTime || row.order?.plannedDepartureTime)
    const arrival = dayjs(row.plannedUnloadTime || row.order?.plannedArrivalTime)
    if (departure.isValid() && arrival.isValid() && arrival.isAfter(departure)) {
      const total = arrival.diff(departure)
      const elapsed = dayjs().diff(departure)
      const liveOffset = ((liveTick.value + hashText(seed)) % 8) * 0.45
      return clamp(Math.round((elapsed / total) * 100 + liveOffset), 32, 94)
    }

    return clamp(48 + (hashText(row.waybillNo) % 36) + (liveTick.value % 6), 32, 94)
  }

  function resolveCurrentLabel(row: InTransitRecord, progress: number): string {
    const status = resolveTransitStatus(row, isDelayed(row))
    if (status === 'pending') return row.originCity || '待处理'
    if (status === 'arrived') return row.destinationCity || '已到达'
    if (progress > 80) return row.destinationCity || '目的地附近'
    if (progress > 48 && row.order?.transferStation) return row.order.transferStation
    return '在途'
  }

  function isDelayed(row: InTransitRecord): boolean {
    const plannedUnloadTime = row.plannedUnloadTime || row.order?.plannedArrivalTime
    const waybillStatus = String(row.status ?? '').toLowerCase()
    const orderStatus = String(row.order?.orderStatus ?? '').toLowerCase()
    if (
      !plannedUnloadTime ||
      row.unloadedAt ||
      waybillStatus === 'completed' ||
      ['signed', 'completed'].includes(orderStatus)
    ) {
      return false
    }
    const arrival = dayjs(plannedUnloadTime)
    return arrival.isValid() && dayjs().isAfter(arrival)
  }

  function getDelayText(value?: string | null): string {
    const arrival = dayjs(value)
    if (!arrival.isValid()) return ''
    const hours = Math.max(1, dayjs().diff(arrival, 'hour'))
    return `${hours}h`
  }

  function resolveArrivalPerformance(row: InTransitRecord): { delayed: boolean; text: string } {
    const planned = dayjs(row.plannedUnloadTime || row.order?.plannedArrivalTime)
    const actual = dayjs(row.unloadedAt || row.order?.signedAt || row.updateTime)
    if (!planned.isValid() || !actual.isValid()) return { delayed: false, text: '准时' }

    const delayedMinutes = actual.diff(planned, 'minute')
    if (delayedMinutes <= 0) return { delayed: false, text: '准时' }

    const delayText =
      delayedMinutes < 60 ? `${delayedMinutes}m` : `${Number((delayedMinutes / 60).toFixed(1))}h`
    return { delayed: true, text: `延误${delayText}` }
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

  function resolveTransitStatus(row: InTransitRecord, delayed: boolean): TransitStatus {
    if (delayed) return 'delayed'

    const rawStatus = String(row.status || row.order?.orderStatus || '')
      .trim()
      .toLowerCase()
    if (['completed', 'signed'].includes(rawStatus) || row.unloadedAt) return 'arrived'

    const runningStatuses = [
      'accepted',
      'loading',
      'transporting',
      'unloading',
      'in_transit',
      'running',
      'processing',
      'in_progress',
      'ongoing'
    ]
    return runningStatuses.includes(rawStatus) ? 'transporting' : 'pending'
  }

  function isRouteVisibleStatus(status: TransitStatus): boolean {
    return ['transporting', 'delayed'].includes(status)
  }

  function resolveSpeed(row: InTransitRecord, status: TransitStatus, seed: string): number {
    const speed = Number(row.speedKmh)
    if (Number.isFinite(speed) && speed >= 0) return Math.round(speed)
    return ['transporting', 'delayed'].includes(status) ? 58 + (hashText(seed) % 28) : 0
  }

  function withAlpha(color: string, alpha: number): string {
    const hex = color.trim().replace('#', '')
    if (!/^[\da-f]{6}$/i.test(hex)) return color
    const value = Number.parseInt(hex, 16)
    return `rgb(${(value >> 16) & 255} ${(value >> 8) & 255} ${value & 255} / ${alpha})`
  }

  function estimateDistanceKm(origin: GeoCoord, destination: GeoCoord): number {
    const radius = 6371
    const toRad = (value: number) => (value * Math.PI) / 180
    const lngDiff = toRad(destination[0] - origin[0])
    const latDiff = toRad(destination[1] - origin[1])
    const startLat = toRad(origin[1])
    const endLat = toRad(destination[1])
    const factor =
      Math.sin(latDiff / 2) ** 2 +
      Math.cos(startLat) * Math.cos(endLat) * Math.sin(lngDiff / 2) ** 2

    return Math.max(
      30,
      Math.round(radius * 2 * Math.atan2(Math.sqrt(factor), Math.sqrt(1 - factor)))
    )
  }

  function selectOrder(id: string): void {
    screen.selectedOrderId = id
    void nextTick(() => {
      updateChinaMap()
      fitSelectedMapView(true)
    })
  }

  function openOrderDetail(): void {
    const orderId = activeOrder.value?.source.order?.id
    if (!orderId) return
    void router.push({
      name: 'TmsOrderDetail',
      params: { id: orderId }
    })
  }

  function goHome(): void {
    void router.push('/')
  }

  function contactDriver(): void {
    if (!activeOrder.value) return
    ElMessage.success(`已打开 ${activeOrder.value.driverName} 的联系流程`)
  }

  function sendReminder(): void {
    if (!activeOrder.value) return
    ElMessage.success(`已向 ${activeOrder.value.plateNo} 发送在途提醒`)
  }

  function formatDateTime(value?: string | null): string {
    return formatWithDayjs(value, 'HH:mm') || '--'
  }

  function formatRefreshTime(value?: string): string {
    return formatWithDayjs(value, 'HH:mm:ss') || '--'
  }

  function formatNumber(value?: number | string | null, precision = 2): string {
    const numeric = Number(value ?? 0)
    if (!Number.isFinite(numeric)) return '0'
    return numeric
      .toFixed(precision)
      .replace(/(\.\d*?)0+$/, '$1')
      .replace(/\.$/, '')
  }

  function formatCoordinate(value: number): string {
    return value.toFixed(5)
  }

  function formatText(value?: string | number | null, fallback = '-'): string {
    const text = String(value ?? '').trim()
    return text || fallback
  }

  function normalizeVehicleTypeCode(value?: string | number | null): string {
    return String(value ?? '').trim()
  }

  function getVehicleImage(vehicleTypeCode: string): string {
    return VEHICLE_IMAGE_MAP[vehicleTypeCode] ?? defaultVehicleImage
  }

  function getDictDisplayValue(
    dictCode: string,
    value?: string | number | null
  ): string | undefined {
    const normalizedValue = String(value ?? '').trim()
    if (!normalizedValue) return undefined

    const exists = getDictMap.value[dictCode]?.some(
      (item) => String(item.value) === normalizedValue || String(item.code) === normalizedValue
    )
    return exists ? normalizedValue : undefined
  }

  function getDictLabel(dictCode: string, value?: string | number | null, fallback = '-'): string {
    const normalizedValue = String(value ?? '').trim()
    if (!normalizedValue) return fallback

    const dictItem = getDictMap.value[dictCode]?.find(
      (item) => String(item.value) === normalizedValue || String(item.code) === normalizedValue
    )
    return dictItem?.label || dictItem?.name || fallback
  }

  function dedupeGeoPath(path: GeoCoord[]): GeoCoord[] {
    return path.reduce<GeoCoord[]>((result, point) => {
      const previous = result[result.length - 1]
      if (!previous || previous[0] !== point[0] || previous[1] !== point[1]) {
        result.push(point)
      }
      return result
    }, [])
  }

  function escapeHtml(value: string): string {
    return value.replace(
      /[&<>"']/g,
      (char) =>
        ({
          '&': '&amp;',
          '<': '&lt;',
          '>': '&gt;',
          '"': '&quot;',
          "'": '&#39;'
        })[char] ?? char
    )
  }

  function clamp(value: number, min: number, max: number): number {
    return Math.min(Math.max(value, min), max)
  }

  function percentOf(value: number, total: number): number {
    return total > 0 ? clamp(Math.round((value / total) * 100), 0, 100) : 0
  }

  function hashText(value?: string | number | null): number {
    const text = String(value ?? '')
    return Array.from(text).reduce((hash, char) => hash + char.charCodeAt(0), 0)
  }
</script>

<style scoped lang="scss">
  .transit-screen {
    position: fixed;
    inset: 0;
    z-index: 2600;
    overflow: hidden;
    color: #eef7ff;
    background:
      radial-gradient(circle at 18% 18%, rgb(40 190 167 / 16%), transparent 30%),
      radial-gradient(circle at 82% 30%, rgb(255 178 78 / 14%), transparent 28%),
      linear-gradient(135deg, #071019 0%, #0d1a20 48%, #130f1d 100%);

    &__viewport {
      position: absolute;
      inset: 0;
      overflow: hidden;
    }

    &__stage {
      position: absolute;
      top: 0;
      left: 0;
      display: grid;
      grid-template-rows: 72px minmax(0, 1fr);
      overflow: hidden;
      transform-origin: 0 0;
      will-change: transform;
    }

    &__header {
      position: relative;
      z-index: 20;
      display: flex;
      gap: 28px;
      align-items: center;
      padding: 10px 12px;
      background: rgb(29 43 62 / 96%);
      border-radius: var(--el-border-radius-base);

      h1 {
        margin: 0;
        font-size: 24px;
        font-weight: 800;
        line-height: 1;
        color: #f7fbff;
        letter-spacing: 0;
      }
    }

    &__body {
      position: relative;
      min-height: 0;
      overflow: hidden;
    }

    &__left,
    &__right {
      position: absolute;
      top: 14px;
      bottom: 16px;
      z-index: 12;
      display: grid;
      gap: 12px;
      width: 296px;
      min-height: 0;
    }

    &__left {
      left: 16px;
      grid-template-rows: auto minmax(0, 1fr);
    }

    &__right {
      right: 16px;
      grid-template-rows: minmax(0, 1fr);
      width: 318px;
    }
  }

  .screen-tabs {
    display: flex;
    gap: 10px;
    align-items: center;

    button {
      min-width: 84px;
      height: 32px;
      padding: 0 16px;
      font-size: 14px;
      font-weight: 700;
      color: #dce9f6;
      cursor: pointer;
      background: rgb(255 255 255 / 10%);
      border: 0;
      border-radius: var(--el-border-radius-small);

      &.is-active {
        color: #fff;
        background: #2f66ff;
      }
    }
  }

  .header-status {
    display: flex;
    gap: 30px;
    align-items: center;
    margin-left: auto;
    font-size: 14px;

    strong {
      font-size: 15px;
      color: #fff;
    }

    span {
      display: inline-flex;
      gap: 8px;
      align-items: center;
      color: #eef7ff;

      i {
        width: 7px;
        height: 7px;
        background: #23d18b;
        border-radius: 50%;
      }
    }

    button {
      height: 34px;
      padding: 0 16px;
      font-weight: 700;
      color: #f4f8ff;
      cursor: pointer;
      background: rgb(255 255 255 / 12%);
      border: 0;
      border-radius: var(--el-border-radius-small);
    }
  }

  .screen-panel {
    min-width: 0;
    min-height: 0;
    padding: 14px;
    background: rgb(16 31 47 / 86%);
    border: 0;
    border-radius: var(--el-border-radius-base);
    box-shadow: 0 16px 38px rgb(0 0 0 / 20%);
    backdrop-filter: blur(10px);

    &__title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;

      strong {
        font-size: 15px;
        color: #f7fbff;
      }

      span {
        font-size: 12px;
        color: #8fb2c6;
      }
    }

    &--filters {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px 8px;
      padding: 12px;

      :deep(.el-input) {
        grid-column: 1 / -1;
      }

      :deep(.el-input__wrapper),
      :deep(.el-select__wrapper) {
        min-height: 34px;
        background: rgb(255 255 255 / 8%);
        border: 0;
        box-shadow: none;
      }

      .transit-metrics {
        grid-column: 1 / -1;
        margin-bottom: 0;
      }
    }

    &--list,
    &--alerts {
      display: flex;
      flex-direction: column;
    }

    &--detail {
      display: flex;
      flex-direction: column;
      padding: 12px;
    }
  }

  .transit-metrics {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
    margin-bottom: 14px;
  }

  .transit-metric {
    min-width: 0;
    padding: 14px;
    background: rgb(7 16 25 / 60%);
    border: 0;
    border-radius: var(--el-border-radius-base);

    span,
    em {
      display: block;
      font-size: 12px;
      font-style: normal;
      color: #8fb2c6;
    }

    strong {
      display: block;
      margin: 8px 0 4px;
      font-size: 28px;
      line-height: 1;
    }

    em {
      color: #23d18b;

      &.is-warning {
        color: #ffb04f;
      }
    }
  }

  .progress-lines {
    display: grid;
    gap: 12px;
  }

  .progress-line {
    div {
      display: flex;
      justify-content: space-between;
      margin-bottom: 6px;
      font-size: 12px;
      color: #b9d8e7;
    }

    i {
      display: block;
      height: 6px;
      overflow: hidden;
      background: rgb(255 255 255 / 10%);
      border-radius: 999px;

      b {
        display: block;
        height: 100%;
        border-radius: inherit;
      }
    }
  }

  .vehicle-list,
  .alert-list {
    flex: 1;
    min-height: 0;
  }

  .vehicle-card {
    display: block;
    width: 100%;
    padding: 14px;
    margin-bottom: 10px;
    color: #dcecf6;
    text-align: left;
    cursor: pointer;
    background: rgb(7 16 25 / 44%);
    border: 0;
    border-radius: var(--el-border-radius-base);
    transition: 0.18s ease;

    &:hover,
    &.is-active {
      background: rgb(29 49 78 / 86%);
      box-shadow: inset 0 0 0 1px rgb(76 125 255 / 68%);
    }

    p {
      margin: 5px 0 12px;
      font-size: 12px;
      color: #8fb2c6;
    }

    &__top,
    &__line,
    &__order {
      display: flex;
      gap: 8px;
      align-items: center;
      justify-content: space-between;
    }

    &__top strong {
      font-size: 15px;
      color: #fff;
    }

    &__line,
    &__order {
      font-size: 12px;
      color: #cfe6f6;
    }

    &__order {
      margin-top: 10px;

      em {
        font-style: normal;
        color: #ffb04f;
      }
    }

    &__arrival {
      display: inline-flex;
      flex: 0 0 auto;
      gap: 4px;
      align-items: center;
      font-weight: 700;
      color: #2ecc71;

      .el-icon {
        font-size: 15px;
      }

      &.is-delayed {
        color: #ff9f43;
      }
    }

    &__geo {
      margin-top: 10px;
      font-size: 12px;
      color: #83a9bd;
    }

    &__status {
      padding: 3px 8px;
      font-size: 12px;
      border-radius: 999px;
    }
  }

  .monitor-map {
    position: absolute;
    inset: 0;
    overflow: hidden;
    background: #020611;

    &__chart {
      position: absolute;
      inset: 0;
      z-index: 1;
      cursor: grab;
      pointer-events: auto;
      touch-action: none;

      &:active {
        cursor: grabbing;
      }
    }

    &__route-overlay {
      position: absolute;
      inset: 0;
      z-index: 4;
      width: 100%;
      height: 100%;
      pointer-events: none;
    }

    :deep(.amap-container) {
      width: 100% !important;
      height: 100% !important;
      pointer-events: auto !important;
      touch-action: none !important;
      background: #020611 !important;
    }

    :deep(.amap-maps),
    :deep(.amap-layers),
    :deep(.amap-layer),
    :deep(.amap-tile),
    :deep(.amap-vector-layer) {
      width: 100% !important;
      height: 100% !important;
    }

    :deep(.amap-container img) {
      max-width: none !important;
    }

    :deep(.amap-layer) {
      opacity: 1 !important;
    }

    &__heading {
      position: absolute;
      top: 16px;
      left: 50%;
      z-index: 8;
      display: grid;
      gap: 4px;
      text-align: center;
      transform: translateX(-50%);

      strong {
        font-size: 16px;
      }

      span {
        font-size: 12px;
        color: #8fb2c6;
      }
    }

    &__tools {
      position: absolute;
      top: 14px;
      right: 350px;
      z-index: 10;
      display: flex;
      gap: 6px;

      :deep(.el-button) {
        width: 32px;
        height: 32px;
        margin: 0;
        color: #dcecf6;
        background: rgb(16 31 47 / 88%);
        border: 1px solid rgb(143 178 198 / 22%);

        &:hover {
          color: #fff;
          background: #315cff;
        }
      }
    }
  }

  .route-line {
    fill: none;
    stroke-linecap: round;
    stroke-linejoin: round;

    &--base {
      filter: drop-shadow(0 0 9px rgb(76 125 255 / 54%));
      stroke: rgb(110 200 255 / 44%);
      stroke-width: 14;
    }

    &--remaining {
      stroke: rgb(142 211 255 / 88%);
      stroke-width: 7;
    }

    &--passed {
      filter: drop-shadow(0 0 8px rgb(49 92 255 / 66%));
      stroke: #315cff;
      stroke-width: 8;
    }
  }

  .map-float {
    position: absolute;
    left: 332px;
    z-index: 9;
    width: 300px;

    &--overview {
      top: 14px;
    }

    &--alerts {
      bottom: 16px;
      display: flex;
      flex-direction: column;
      max-height: 238px;
    }
  }

  :global(.transit-amap-marker) {
    display: inline-flex;
    gap: 6px;
    align-items: center;
    min-width: 0;
    padding: 5px 8px 5px 5px;
    white-space: nowrap;
    background: rgb(9 21 34 / 92%);
    border: 1px solid rgb(255 255 255 / 34%);
    border-radius: 999px;
    box-shadow: 0 8px 18px rgb(0 0 0 / 24%);
  }

  :global(.transit-amap-marker b) {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 24px;
    height: 24px;
    font-size: 12px;
    color: #fff;
    background: var(--marker-color);
    border-radius: 50%;
  }

  :global(.transit-amap-marker span) {
    max-width: 160px;
    overflow: hidden;
    text-overflow: ellipsis;
    font-size: 12px;
    font-weight: 700;
    color: #f7fbff;
  }

  :global(.transit-amap-marker em) {
    max-width: 104px;
    overflow: hidden;
    text-overflow: ellipsis;
    font-size: 11px;
    font-style: normal;
    color: #96d8ff;
  }

  :global(.transit-vehicle-marker) {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 44px;
    height: 34px;
    transform: translateZ(0);
  }

  :global(.transit-vehicle-marker i) {
    position: absolute;
    inset: -12px -16px;
    background: radial-gradient(
      circle,
      rgb(35 209 139 / 38%) 0%,
      rgb(76 125 255 / 16%) 44%,
      transparent 68%
    );
    border-radius: 999px;
    animation: transitVehiclePulse 1.35s ease-in-out infinite;
  }

  :global(.transit-vehicle-marker img) {
    position: relative;
    z-index: 1;
    width: 42px;
    height: 28px;
    object-fit: contain;
    filter: drop-shadow(0 8px 12px rgb(0 0 0 / 42%));
    animation: transitVehicleFloat 1.8s ease-in-out infinite;
  }

  :global(.transit-vehicle-marker span) {
    position: absolute;
    bottom: 34px;
    left: 50%;
    z-index: 2;
    max-width: 120px;
    padding: 5px 9px;
    overflow: visible;
    font-size: 12px;
    font-weight: 700;
    line-height: 18px;
    color: #263243;
    white-space: nowrap;
    background: #fff;
    border: 0;
    border-radius: var(--el-border-radius-small);
    box-shadow: 0 5px 16px rgb(0 0 0 / 30%);
    transform: translateX(-50%);
  }

  :global(.transit-vehicle-marker span::after) {
    position: absolute;
    bottom: -5px;
    left: 50%;
    width: 10px;
    height: 10px;
    content: '';
    background: #fff;
    transform: translateX(-50%) rotate(45deg);
  }

  .alert-item {
    display: grid;
    grid-template-columns: 8px minmax(0, 1fr) auto;
    gap: 10px;
    align-items: start;
    padding: 10px 0;
    border-bottom: 1px solid rgb(255 255 255 / 7%);

    strong {
      font-size: 13px;
      color: #fff;
    }

    p {
      margin: 4px 0 0;
      font-size: 12px;
      color: #91adbe;
    }

    span {
      font-size: 12px;
      color: #8fb2c6;
    }

    &__level {
      width: 4px;
      height: 34px;
      border-radius: 999px;

      &--danger {
        background: #ff5c6c;
      }

      &--warning {
        background: #ffb04f;
      }

      &--info {
        background: #4c7dff;
      }
    }
  }

  .detail-vehicle {
    display: flex;
    gap: 10px;
    align-items: center;
    min-height: 68px;
    padding: 2px 0 10px;

    &__icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 72px;
      height: 52px;
      color: #071019;
      background: rgb(7 16 25 / 58%);
      border-radius: var(--el-border-radius-base);

      img {
        width: 64px;
        height: 42px;
        object-fit: contain;
      }
    }

    strong {
      font-size: 17px;
    }

    p {
      margin: 4px 0 0;
      font-size: 13px;
      color: #8fb2c6;
    }
  }

  .detail-speed {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
    margin-top: 10px;

    div {
      min-width: 0;
      padding: 12px;
      background: rgb(7 16 25 / 50%);
      border: 0;
      border-radius: var(--el-border-radius-base);
    }

    span {
      display: block;
      margin-bottom: 6px;
      font-size: 12px;
      color: #8fb2c6;
    }

    strong {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 21px;
      line-height: 1.15;
      white-space: nowrap;
    }
  }

  .detail-waybill,
  .detail-cargo,
  .detail-driver {
    padding-top: 0;
    margin-top: 0;
  }

  .detail-waybill {
    padding-top: 18px;
    margin-top: 18px;
    border-top: 1px solid rgb(255 255 255 / 7%);

    > span {
      display: block;
      color: #8fb2c6;
    }

    > strong {
      display: block;
      margin: 8px 0 16px;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: 16px;
      white-space: nowrap;
    }
  }

  .detail-route {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 50px minmax(0, 1fr);
    gap: 8px;
    align-items: center;
    text-align: center;

    b,
    em {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    em {
      margin-top: 4px;
      font-size: 12px;
      font-style: normal;
      color: #8fb2c6;
    }

    i {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      height: 50px;
      font-size: 12px;
      font-style: normal;
      color: #fff;
      border: 3px solid #315cff;
      border-radius: 50%;
    }
  }

  .detail-progress {
    height: 6px;
    margin-top: 16px;
    overflow: hidden;
    background: rgb(255 255 255 / 10%);
    border-radius: 999px;

    b {
      display: block;
      height: 100%;
      background: linear-gradient(90deg, #315cff, #26e0a8);
    }
  }

  .detail-cargo {
    flex: 1;
    min-height: 138px;
    padding-top: 18px;
    margin-top: 18px;
    border-top: 1px solid rgb(255 255 255 / 7%);

    strong {
      display: block;
      margin-bottom: 12px;
    }

    p {
      display: flex;
      gap: 10px;
      justify-content: space-between;
      margin: 0 0 8px;
      font-size: 13px;
      color: #91adbe;

      span {
        flex: 0 0 auto;
      }

      b {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        color: #eef7ff;
        white-space: nowrap;
      }
    }
  }

  .detail-driver {
    display: flex;
    gap: 10px;
    align-items: center;
    padding-top: 22px;
    margin-top: 18px;
    border-top: 1px solid rgb(255 255 255 / 7%);

    &__avatar {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 44px;
      height: 44px;
      font-weight: 700;
      background: #315cff;
      border-radius: 50%;
    }

    p {
      margin: 3px 0 0;
      color: #8fb2c6;
    }
  }

  .detail-actions {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
    margin-top: 16px;
  }

  .detail-scroll {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 0;
    min-height: 0;
    overflow: hidden;
  }

  @keyframes transitVehiclePulse {
    0%,
    100% {
      opacity: 0.35;
      transform: scale(0.86);
    }

    50% {
      opacity: 1;
      transform: scale(1.12);
    }
  }

  @keyframes transitVehicleFloat {
    0%,
    100% {
      transform: translateX(-1px);
    }

    50% {
      transform: translateX(2px);
    }
  }
</style>
