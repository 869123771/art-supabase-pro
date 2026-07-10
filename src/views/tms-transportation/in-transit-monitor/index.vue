<template>
  <div class="transit-screen" v-loading="screen.loading">
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
        <div class="monitor-map__tools">
          <ElButton :icon="ZoomIn" circle @click="zoomChinaMap('in')" />
          <ElButton :icon="ZoomOut" circle @click="zoomChinaMap('out')" />
          <ElButton :icon="RefreshRight" circle @click="resetChinaMapView" />
          <span>{{ mapView.zoom }}级</span>
        </div>
        <div v-if="activeOrder" class="monitor-map__track-chip">
          {{ activeOrder.plateNo }} · {{ activeOrder.orderNo }}
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

        <section class="screen-panel map-float map-float--alerts">
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
            <ElEmpty v-if="alertItems.length === 0" description="暂无报警" :image-size="64" />
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
            <ElOption label="待提货" value="pending_pickup" />
            <ElOption label="运输中" value="transporting" />
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
                <span :class="`vehicle-card__status vehicle-card__status--${item.statusClass}`">
                  {{ item.statusLabel }}
                </span>
              </div>
              <p>{{ item.vehicleType }}</p>
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
                <em v-if="item.delayed">延误{{ item.delayText }}</em>
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

          <ElScrollbar class="detail-scroll">
            <template v-if="activeOrder">
              <div class="detail-vehicle">
                <div class="detail-vehicle__icon">
                  <ArtSvgIcon icon="ri:truck-fill" />
                </div>
                <div>
                  <strong>{{ activeOrder.plateNo }}</strong>
                  <p>{{ activeOrder.vehicleType }}</p>
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
                <div class="detail-driver__avatar">{{ activeOrder.driverName.slice(0, 1) }}</div>
                <div>
                  <strong>{{ activeOrder.driverName }}</strong>
                  <p>{{ activeOrder.driverPhone }}</p>
                </div>
              </div>

              <div class="detail-actions">
                <ElButton type="primary" :icon="Phone" @click="contactDriver">联系司机</ElButton>
                <ElButton type="warning" :icon="Warning" @click="sendReminder">发送提醒</ElButton>
              </div>
            </template>

            <ElEmpty v-else description="暂无车辆详情" :image-size="86" />
          </ElScrollbar>
        </section>
      </aside>
    </main>
  </div>
</template>

<script setup lang="ts">
  import type { UnwrapNestedRefs } from 'vue'
  import dayjs from 'dayjs'
  import { ElMessage } from 'element-plus'
  import {
    MoreFilled,
    Phone,
    RefreshRight,
    Search,
    Warning,
    ZoomIn,
    ZoomOut
  } from '@element-plus/icons-vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { fetchDeliveryList } from '@/api/tms'
  import { formatWithDayjs } from '@/utils/time'
  import { useIntervalFn } from '@vueuse/core'

  defineOptions({ name: 'TmsInTransitMonitor' })

  type DeliveryRecord = Api.Tms.Delivery.DeliveryRecord
  type TransitStatus = 'pending_pickup' | 'transporting'
  type GeoCoord = [number, number]

  const INITIAL_MAP_CENTER: GeoCoord = [105.5, 34.2]
  const INITIAL_MAP_ZOOM = 5
  const MAP_MIN_ZOOM = 4
  const MAP_MAX_ZOOM = 18
  const AMAP_PLUGINS = ['AMap.ToolBar', 'AMap.Scale']
  const AMAP_RASTER_TILE_URL =
    'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}'

  interface ScreenState {
    keyword: string
    lastRefreshTime?: string
    loading: boolean
    orders: DeliveryRecord[]
    region: string
    selectedOrderId?: string
    status: TransitStatus | ''
  }

  interface MonitorOrder {
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
    progress: number
    remainingKm: number
    routeName: string
    source: DeliveryRecord
    speed: number
    status: string
    statusClass: 'ready' | 'running' | 'warning'
    statusLabel: string
    vehicleType: string
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

  const router = useRouter()
  const chartRef = ref<HTMLDivElement>()
  const amapInstance = shallowRef<any>()
  const amapReady = ref(false)
  const liveTick = ref(0)
  const currentTime = ref(new Date().toISOString())
  const mapView: UnwrapNestedRefs<MapViewState> = reactive<MapViewState>({
    center: [...INITIAL_MAP_CENTER],
    zoom: INITIAL_MAP_ZOOM
  })
  let vehicleMarker: any
  let originMarker: any
  let destinationMarker: any
  let passedPolyline: any
  let remainingPolyline: any

  const screen: UnwrapNestedRefs<ScreenState> = reactive<ScreenState>({
    keyword: '',
    loading: false,
    orders: [],
    region: '',
    selectedOrderId: undefined,
    status: ''
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
    updateChinaMap()
  })

  onMounted(() => {
    void loadMonitorData()
    void initChinaMap()
    window.addEventListener('resize', resizeChinaMap)
  })

  onBeforeUnmount(() => {
    window.removeEventListener('resize', resizeChinaMap)
    destroyMonitorMap()
  })

  useIntervalFn(() => {
    void loadMonitorData(false)
  }, 60000)

  useIntervalFn(() => {
    liveTick.value += 1
    currentTime.value = new Date().toISOString()
  }, 1000)

  async function loadMonitorData(showLoading = true): Promise<void> {
    if (showLoading) screen.loading = true
    try {
      const { data } = await fetchDeliveryList({
        from: 0,
        orderStatuses: ['pending_pickup', 'transporting'],
        to: 199
      })

      screen.orders = createMockDeliveryRows(data ?? [])
      screen.lastRefreshTime = new Date().toISOString()
      if (!screen.selectedOrderId && screen.orders[0]?.id) {
        screen.selectedOrderId = screen.orders[0].id
      }
    } catch {
      screen.orders = createMockDeliveryRows([])
      screen.lastRefreshTime = new Date().toISOString()
      if (!screen.selectedOrderId && screen.orders[0]?.id) {
        screen.selectedOrderId = screen.orders[0].id
      }
    } finally {
      screen.loading = false
    }
  }

  function createMonitorOrder(row: DeliveryRecord): MonitorOrder {
    const id = String(row.id || row.orderNo)
    const origin = formatText(row.originStation)
    const destination = formatText(row.destinationStation)
    const originGeo = resolveStationGeo(origin)
    const destinationGeo = resolveStationGeo(destination)
    const progress = resolveProgress(row, id)
    const geoPoint = resolveGeoPoint(originGeo, destinationGeo, progress, id)
    const status = row.orderStatus || 'pending_pickup'
    const delayed = isDelayed(row)
    const distance = 260 + (hashText(`${origin}-${destination}`) % 720)

    return {
      cargoBoxes: Number(row.cargoQuantityTotal ?? row.cargoItems?.length ?? 0),
      cargoSummary: [
        {
          label: '货物类型',
          value: row.cargoItems?.map((item) => item.cargoName).find(Boolean) || '-'
        },
        { label: '总数量', value: `${formatNumber(row.cargoQuantityTotal, 0)} 件` },
        { label: '总重量', value: `${formatNumber(row.cargoWeightTotal)} kg` },
        { label: '总体积', value: `${formatNumber(row.cargoVolumeTotal, 3)} 方` }
      ],
      currentLabel: resolveCurrentLabel(row, progress),
      delayed,
      delayText: getDelayText(row.plannedArrivalTime),
      destination,
      destinationGeo,
      driverName: formatText(row.dispatchDriverName, '未派司机'),
      driverPhone: formatText(row.dispatchDriverPhone, '未登记电话'),
      id,
      latitude: geoPoint.latitude,
      longitude: geoPoint.longitude,
      orderNo: formatText(row.orderNo),
      origin,
      originGeo,
      plateNo: formatText(row.dispatchPlateNo, '未配车'),
      plannedArrivalTime: row.plannedArrivalTime,
      plannedDepartureTime: row.plannedDepartureTime,
      progress,
      remainingKm: Math.max(0, Math.round(distance * (1 - progress / 100))),
      routeName: [origin, row.transferStation, destination].filter(Boolean).join(' - '),
      source: row,
      speed: status === 'transporting' ? 62 + (hashText(id) % 24) : 0,
      status,
      statusClass: delayed ? 'warning' : status === 'transporting' ? 'running' : 'ready',
      statusLabel: getStatusLabel(status),
      vehicleType: formatText(row.dispatchVehicleType, '运输车辆')
    }
  }

  function createMockDeliveryRows(rows: DeliveryRecord[]): DeliveryRecord[] {
    const now = dayjs()
    const mockRows = [
      {
        id: 'mock-zj-gan-001',
        orderNo: 'SH20231115003',
        orderStatus: 'transporting',
        originStation: '浙江 · 义乌',
        destinationStation: '江西 · 赣州',
        transferStation: '太原',
        dispatchPlateNo: '浙A · 12345',
        dispatchVehicleType: '东风天龙重卡',
        dispatchDriverName: '李师傅',
        dispatchDriverPhone: '13800000001',
        plannedDepartureTime: now.subtract(4, 'hour').toISOString(),
        plannedArrivalTime: now.add(6, 'hour').toISOString(),
        dispatchedAt: now.subtract(4, 'hour').toISOString(),
        cargoQuantityTotal: 18,
        cargoWeightTotal: 12600,
        cargoVolumeTotal: 43.6,
        cargoItems: [{ cargoName: '电子产品' }]
      },
      {
        id: 'mock-su-cd-002',
        orderNo: 'SH205023932034',
        orderStatus: 'transporting',
        originStation: '江苏 · 苏州',
        destinationStation: '四川 · 成都',
        transferStation: '西安',
        dispatchPlateNo: '苏B · 67890',
        dispatchVehicleType: '福田欧曼重卡',
        dispatchDriverName: '张师傅',
        dispatchDriverPhone: '13800000002',
        plannedDepartureTime: now.subtract(8, 'hour').toISOString(),
        plannedArrivalTime: now.add(7, 'hour').toISOString(),
        dispatchedAt: now.subtract(8, 'hour').toISOString(),
        cargoQuantityTotal: 28,
        cargoWeightTotal: 18800,
        cargoVolumeTotal: 58.2,
        cargoItems: [{ cargoName: '机械设备' }]
      },
      {
        id: 'mock-zj-tai-003',
        orderNo: 'SH205023932035',
        orderStatus: 'transporting',
        originStation: '浙江 · 杭州',
        destinationStation: '山西 · 太原',
        dispatchPlateNo: '浙G · 12345',
        dispatchVehicleType: '解放J6重卡',
        dispatchDriverName: '赵师傅',
        dispatchDriverPhone: '13800000003',
        plannedDepartureTime: now.subtract(12, 'hour').toISOString(),
        plannedArrivalTime: now.subtract(1, 'hour').toISOString(),
        dispatchedAt: now.subtract(12, 'hour').toISOString(),
        cargoQuantityTotal: 15,
        cargoWeightTotal: 9200,
        cargoVolumeTotal: 31.4,
        cargoItems: [{ cargoName: '日用百货' }]
      },
      {
        id: 'mock-jing-yue-004',
        orderNo: 'SH205023932036',
        orderStatus: 'pending_pickup',
        originStation: '北京',
        destinationStation: '广东 · 广州',
        dispatchPlateNo: '京C · 29384',
        dispatchVehicleType: '厢式货车',
        dispatchDriverName: '王师傅',
        dispatchDriverPhone: '13800000004',
        plannedDepartureTime: now.add(2, 'hour').toISOString(),
        plannedArrivalTime: now.add(18, 'hour').toISOString(),
        dispatchedAt: now.toISOString(),
        cargoQuantityTotal: 12,
        cargoWeightTotal: 5200,
        cargoVolumeTotal: 22.1,
        cargoItems: [{ cargoName: '冷链食品' }]
      },
      {
        id: 'mock-hu-wu-005',
        orderNo: 'SH205023932037',
        orderStatus: 'transporting',
        originStation: '上海',
        destinationStation: '湖北 · 武汉',
        transferStation: '南京',
        dispatchPlateNo: '沪D · 56018',
        dispatchVehicleType: '新能源厢车',
        dispatchDriverName: '陈师傅',
        dispatchDriverPhone: '13800000005',
        plannedDepartureTime: now.subtract(5, 'hour').toISOString(),
        plannedArrivalTime: now.add(5, 'hour').toISOString(),
        dispatchedAt: now.subtract(5, 'hour').toISOString(),
        cargoQuantityTotal: 22,
        cargoWeightTotal: 10400,
        cargoVolumeTotal: 39.8,
        cargoItems: [{ cargoName: '服装箱包' }]
      },
      {
        id: 'mock-yue-qian-006',
        orderNo: 'SH205023932038',
        orderStatus: 'transporting',
        originStation: '广东 · 广州',
        destinationStation: '贵州 · 贵阳',
        transferStation: '长沙',
        dispatchPlateNo: '粤S · 80127',
        dispatchVehicleType: '冷藏车',
        dispatchDriverName: '刘师傅',
        dispatchDriverPhone: '13800000006',
        plannedDepartureTime: now.subtract(7, 'hour').toISOString(),
        plannedArrivalTime: now.add(3, 'hour').toISOString(),
        dispatchedAt: now.subtract(7, 'hour').toISOString(),
        cargoQuantityTotal: 16,
        cargoWeightTotal: 7600,
        cargoVolumeTotal: 28.3,
        cargoItems: [{ cargoName: '生鲜食品' }]
      },
      {
        id: 'mock-shan-xiang-007',
        orderNo: 'SH205023932039',
        orderStatus: 'transporting',
        originStation: '陕西 · 西安',
        destinationStation: '湖南 · 长沙',
        transferStation: '郑州',
        dispatchPlateNo: '陕A · 6T209',
        dispatchVehicleType: '栏板货车',
        dispatchDriverName: '周师傅',
        dispatchDriverPhone: '13800000007',
        plannedDepartureTime: now.subtract(9, 'hour').toISOString(),
        plannedArrivalTime: now.add(9, 'hour').toISOString(),
        dispatchedAt: now.subtract(9, 'hour').toISOString(),
        cargoQuantityTotal: 34,
        cargoWeightTotal: 21600,
        cargoVolumeTotal: 64.5,
        cargoItems: [{ cargoName: '建材辅料' }]
      },
      {
        id: 'mock-yu-dian-008',
        orderNo: 'SH205023932040',
        orderStatus: 'transporting',
        originStation: '重庆',
        destinationStation: '云南 · 昆明',
        transferStation: '贵阳',
        dispatchPlateNo: '渝B · 73K20',
        dispatchVehicleType: '高栏货车',
        dispatchDriverName: '孙师傅',
        dispatchDriverPhone: '13800000008',
        plannedDepartureTime: now.subtract(3, 'hour').toISOString(),
        plannedArrivalTime: now.add(10, 'hour').toISOString(),
        dispatchedAt: now.subtract(3, 'hour').toISOString(),
        cargoQuantityTotal: 20,
        cargoWeightTotal: 13500,
        cargoVolumeTotal: 41.2,
        cargoItems: [{ cargoName: '汽车零部件' }]
      }
    ] as DeliveryRecord[]

    const existingIds = new Set(mockRows.map((row) => row.id))
    const businessRows = rows.filter((row) => !row.id || !existingIds.has(row.id))
    return [...mockRows, ...businessRows].slice(0, 80)
  }

  async function initChinaMap(): Promise<void> {
    if (!chartRef.value) return

    try {
      const AMap = await loadAmap()
      const baseLayer = createAmapBaseLayer(AMap)
      amapInstance.value = new AMap.Map(chartRef.value, {
        center: INITIAL_MAP_CENTER,
        layers: [baseLayer],
        resizeEnable: true,
        viewMode: '2D',
        zoom: INITIAL_MAP_ZOOM,
        zooms: [MAP_MIN_ZOOM, MAP_MAX_ZOOM]
      })
      amapInstance.value.setLayers([baseLayer])
      amapInstance.value.addControl(new AMap.Scale())
      amapInstance.value.addControl(new AMap.ToolBar({ position: 'RT' }))
      amapInstance.value.on('zoomchange', syncMapViewState)
      amapInstance.value.on('mapmove', syncMapViewState)
      amapReady.value = true
    } catch (error) {
      amapReady.value = false
      ElMessage.warning(error instanceof Error ? error.message : '高德地图加载失败')
    }

    updateChinaMap()
  }

  function createAmapBaseLayer(AMap: any): any {
    return new AMap.TileLayer({
      detectRetina: true,
      getTileUrl: (x: number, y: number, z: number) =>
        AMAP_RASTER_TILE_URL.replace('{s}', String(Math.abs(x + y + z) % 4))
          .replace('{x}', String(x))
          .replace('{y}', String(y))
          .replace('{z}', String(z)),
      opacity: 1,
      visible: true,
      zIndex: 1,
      zooms: [MAP_MIN_ZOOM, MAP_MAX_ZOOM]
    })
  }

  function updateChinaMap(): void {
    const map = amapInstance.value
    const AMap = window.AMap
    const active = activeOrder.value
    if (!map || !AMap || !amapReady.value || !active) return

    const origin = active.originGeo
    const current: GeoCoord = [active.longitude, active.latitude]
    const destination = active.destinationGeo

    originMarker = upsertMarker(originMarker, origin, '发', active.origin, '#23d18b')
    vehicleMarker = upsertMarker(vehicleMarker, current, '车', active.plateNo, '#315cff')
    destinationMarker = upsertMarker(
      destinationMarker,
      destination,
      '收',
      active.destination,
      '#ff9f43'
    )

    passedPolyline = upsertPolyline(passedPolyline, [origin, current], '#23d18b', 7)
    remainingPolyline = upsertPolyline(
      remainingPolyline,
      [current, destination],
      '#6ba7ff',
      5,
      true
    )
    fitActiveTrack()
  }

  function zoomChinaMap(direction: 'in' | 'out'): void {
    const map = amapInstance.value
    if (!map) return
    const nextZoom =
      direction === 'in'
        ? Math.min(MAP_MAX_ZOOM, mapView.zoom + 1)
        : Math.max(MAP_MIN_ZOOM, mapView.zoom - 1)
    applyChinaMapView(nextZoom, mapView.center)
  }

  function resetChinaMapView(): void {
    fitActiveTrack(true)
  }

  function applyChinaMapView(zoom: number, center: GeoCoord): void {
    const map = amapInstance.value
    if (!map) return
    mapView.zoom = Math.round(zoom)
    mapView.center = center
    map.setZoomAndCenter(mapView.zoom, mapView.center)
  }

  function syncMapViewState(): void {
    const map = amapInstance.value
    if (!map) return
    const center = map.getCenter?.()
    if (center) mapView.center = [Number(center.lng), Number(center.lat)]
    const zoom = map.getZoom?.()
    if (typeof zoom === 'number') mapView.zoom = Math.round(zoom)
  }

  function resizeChinaMap(): void {
    amapInstance.value?.resize?.()
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

  function upsertMarker(
    marker: any,
    position: GeoCoord,
    label: string,
    title: string,
    color: string
  ): any {
    const map = amapInstance.value
    const AMap = window.AMap
    if (!map || !AMap) return marker

    const content = `<div class="transit-amap-marker" style="--marker-color:${color}"><b>${label}</b><span>${title}</span></div>`
    if (!marker) {
      const nextMarker = new AMap.Marker({
        anchor: 'center',
        content,
        offset: new AMap.Pixel(0, 0),
        position,
        zIndex: label === '车' ? 130 : 120
      })
      map.add(nextMarker)
      return nextMarker
    }

    marker.setPosition(position)
    marker.setContent(content)
    return marker
  }

  function upsertPolyline(
    polyline: any,
    path: GeoCoord[],
    color: string,
    weight: number,
    dashed = false
  ): any {
    const map = amapInstance.value
    const AMap = window.AMap
    if (!map || !AMap) return polyline

    if (!polyline) {
      const nextPolyline = new AMap.Polyline({
        borderWeight: 1,
        isOutline: true,
        lineJoin: 'round',
        outlineColor: 'rgba(0,0,0,.3)',
        path,
        showDir: !dashed,
        strokeColor: color,
        strokeOpacity: dashed ? 0.68 : 0.95,
        strokeStyle: dashed ? 'dashed' : 'solid',
        strokeWeight: weight,
        zIndex: dashed ? 90 : 100
      })
      map.add(nextPolyline)
      return nextPolyline
    }

    polyline.setPath(path)
    return polyline
  }

  function fitActiveTrack(force = false): void {
    const map = amapInstance.value
    const AMap = window.AMap
    const active = activeOrder.value
    if (!map || !AMap || !active) return
    if (!force && mapView.zoom >= 11) return

    const lngValues = [active.originGeo[0], active.destinationGeo[0], active.longitude]
    const latValues = [active.originGeo[1], active.destinationGeo[1], active.latitude]
    const southWest: GeoCoord = [Math.min(...lngValues), Math.min(...latValues)]
    const northEast: GeoCoord = [Math.max(...lngValues), Math.max(...latValues)]
    const bounds = new AMap.Bounds(southWest, northEast)
    bounds.extend([active.longitude, active.latitude])
    map.setBounds(bounds, false, [100, 380, 120, 360])
    syncMapViewState()
  }

  function destroyMonitorMap(): void {
    amapInstance.value?.destroy?.()
    amapInstance.value = undefined
    amapReady.value = false
    vehicleMarker = undefined
    originMarker = undefined
    destinationMarker = undefined
    passedPolyline = undefined
    remainingPolyline = undefined
  }

  function matchesSelectedRegion(item: MonitorOrder): boolean {
    if (!screen.region) return true
    const region = regionOptions.find((option) => option.value === screen.region)
    if (!region) return true

    const routeText = [item.origin, item.destination, item.routeName, item.currentLabel].join('')
    return region.keywords.some((keyword) => routeText.includes(keyword))
  }

  function resolveGeoPoint(
    origin: GeoCoord,
    destination: GeoCoord,
    progress: number,
    seed: string
  ): { latitude: number; longitude: number } {
    const longitudeBase = interpolate(origin[0], destination[0], progress)
    const latitudeBase = interpolate(origin[1], destination[1], progress)
    const offset = (hashText(seed) % 100) / 1000

    return {
      latitude: Number((latitudeBase + offset).toFixed(5)),
      longitude: Number((longitudeBase - offset).toFixed(5))
    }
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

  function resolveProgress(row: DeliveryRecord, seed: string): number {
    if (row.orderStatus === 'pending_pickup') return 18 + (hashText(row.orderNo) % 10)

    const departure = dayjs(row.plannedDepartureTime)
    const arrival = dayjs(row.plannedArrivalTime)
    if (departure.isValid() && arrival.isValid() && arrival.isAfter(departure)) {
      const total = arrival.diff(departure)
      const elapsed = dayjs().diff(departure)
      const liveOffset = ((liveTick.value + hashText(seed)) % 8) * 0.45
      return clamp(Math.round((elapsed / total) * 100 + liveOffset), 32, 94)
    }

    return clamp(48 + (hashText(row.orderNo) % 36) + (liveTick.value % 6), 32, 94)
  }

  function resolveCurrentLabel(row: DeliveryRecord, progress: number): string {
    if (row.orderStatus === 'pending_pickup') return row.originStation || '待提货'
    if (progress > 80) return row.destinationStation || '目的地附近'
    if (progress > 48 && row.transferStation) return row.transferStation
    return '在途'
  }

  function isDelayed(row: DeliveryRecord): boolean {
    if (!row.plannedArrivalTime || ['signed', 'completed'].includes(String(row.orderStatus))) {
      return false
    }
    const arrival = dayjs(row.plannedArrivalTime)
    return arrival.isValid() && dayjs().isAfter(arrival)
  }

  function getDelayText(value?: string | null): string {
    const arrival = dayjs(value)
    if (!arrival.isValid()) return ''
    const hours = Math.max(1, dayjs().diff(arrival, 'hour'))
    return `${hours}h`
  }

  function getStatusLabel(status?: string): string {
    const statusMap: Record<string, string> = {
      pending_pickup: '待提货',
      transporting: '运输中'
    }
    return statusMap[String(status)] || '在途'
  }

  function selectOrder(id: string): void {
    screen.selectedOrderId = id
    void nextTick(() => {
      updateChinaMap()
      fitActiveTrack(true)
    })
  }

  function openOrderDetail(): void {
    if (!activeOrder.value?.source.id) return
    void router.push({
      name: 'TmsOrderDetail',
      params: { id: activeOrder.value.source.id }
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

  function interpolate(start: number, end: number, progress: number): number {
    return Number((start + (end - start) * (progress / 100)).toFixed(2))
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
    display: grid;
    grid-template-rows: 72px minmax(0, 1fr);
    min-width: 1180px;
    min-height: 720px;
    overflow: hidden;
    color: #eef7ff;
    background:
      radial-gradient(circle at 18% 18%, rgb(40 190 167 / 16%), transparent 30%),
      radial-gradient(circle at 82% 30%, rgb(255 178 78 / 14%), transparent 28%),
      linear-gradient(135deg, #071019 0%, #0d1a20 48%, #130f1d 100%);

    &__header {
      position: relative;
      z-index: 20;
      display: flex;
      gap: 28px;
      align-items: center;
      padding: 10px 12px;
      margin: 6px 10px 0;
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
    &--detail,
    &--alerts {
      display: flex;
      flex-direction: column;
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

    &__geo {
      margin-top: 10px;
      font-size: 12px;
      color: #83a9bd;
    }

    &__status {
      padding: 3px 8px;
      font-size: 12px;
      border-radius: 999px;

      &--ready {
        color: #ffd36a;
        background: rgb(255 211 106 / 14%);
      }

      &--running {
        color: #97d7ff;
        background: rgb(76 125 255 / 24%);
      }

      &--warning {
        color: #ffbe9a;
        background: rgb(255 101 101 / 18%);
      }
    }
  }

  .monitor-map {
    position: absolute;
    inset: 0;
    overflow: hidden;
    background: #dfe7ee;

    &__chart {
      position: absolute;
      inset: 0;
      z-index: 1;
      cursor: grab;

      &:active {
        cursor: grabbing;
      }
    }

    :deep(.amap-container) {
      background: #dfe7ee !important;
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
      top: 86px;
      right: 356px;
      z-index: 10;
      display: flex;
      flex-direction: column;
      gap: 8px;
      align-items: center;
      padding: 8px;
      background: rgb(16 31 47 / 82%);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 12px 28px rgb(0 0 0 / 18%);
      backdrop-filter: blur(10px);

      :deep(.el-button) {
        width: 32px;
        height: 32px;
        margin: 0;
        color: #dcecf6;
        background: rgb(255 255 255 / 10%);
        border: 0;

        &:hover {
          color: #fff;
          background: #315cff;
        }
      }

      span {
        width: 42px;
        overflow: hidden;
        font-size: 12px;
        line-height: 18px;
        color: #8fb2c6;
        text-align: center;
        white-space: nowrap;
      }
    }
  }

  .map-float {
    position: absolute;
    left: 332px;
    z-index: 9;
    width: 300px;

    &--overview {
      top: 86px;
    }

    &--alerts {
      bottom: 28px;
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
    font-size: 12px;
    font-weight: 700;
    color: #f7fbff;
    text-overflow: ellipsis;
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
    gap: 12px;
    align-items: center;
    padding: 12px 0 18px;

    &__icon {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 54px;
      height: 54px;
      color: #071019;
      background: linear-gradient(135deg, #26e0a8, #ffd36a);
      border-radius: var(--el-border-radius-base);

      :deep(.svg-icon) {
        width: 30px;
        height: 30px;
      }
    }

    strong {
      font-size: 18px;
    }

    p {
      margin: 5px 0 0;
      color: #8fb2c6;
    }
  }

  .detail-speed {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;

    div {
      padding: 14px;
      background: rgb(7 16 25 / 50%);
      border: 0;
      border-radius: var(--el-border-radius-base);
    }

    span {
      display: block;
      margin-bottom: 8px;
      font-size: 12px;
      color: #8fb2c6;
    }

    strong {
      font-size: 24px;
    }
  }

  .detail-waybill,
  .detail-cargo,
  .detail-driver {
    padding-top: 20px;
    margin-top: 20px;
  }

  .detail-waybill {
    > span {
      display: block;
      color: #8fb2c6;
    }

    > strong {
      display: block;
      margin: 8px 0 14px;
      font-size: 17px;
    }
  }

  .detail-route {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 58px minmax(0, 1fr);
    gap: 10px;
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
      height: 58px;
      font-style: normal;
      color: #fff;
      border: 4px solid #315cff;
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
    strong {
      display: block;
      margin-bottom: 12px;
    }

    p {
      display: flex;
      justify-content: space-between;
      margin: 0 0 10px;
      font-size: 13px;
      color: #91adbe;

      b {
        color: #eef7ff;
      }
    }
  }

  .detail-driver {
    display: flex;
    gap: 12px;
    align-items: center;

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
      margin: 4px 0 0;
      color: #8fb2c6;
    }
  }

  .detail-actions {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
    margin: 20px 0 4px;
  }

  .detail-scroll {
    flex: 1;
    min-height: 0;
  }

  @media (width <= 1360px) {
    .transit-screen {
      &__left {
        width: 284px;
      }

      &__right {
        width: 304px;
      }
    }

    .map-float {
      left: 316px;
      width: 286px;
    }

    .monitor-map {
      &__tools {
        right: 342px;
      }
    }
  }
</style>
