<template>
  <div class="enterprise-screen" :class="`is-${mode}`">
    <ArtAsyncState
      class="enterprise-screen__state"
      :loading="state.loading"
      :loading-mode="state.loaded ? 'mask' : 'skeleton'"
      :error="state.loaded ? null : state.error"
      :min-height="0"
      full-height
      @retry="loadData"
    >
      <ElScrollbar class="enterprise-screen__scrollbar">
        <div class="enterprise-screen__stage">
          <header class="command-header">
            <div class="command-header__identity">
              <button
                type="button"
                class="screen-icon-button"
                aria-label="返回工作台"
                title="返回工作台"
                @click="exitScreen"
              >
                <ArtSvgIcon icon="ri:arrow-left-line" />
              </button>
              <div>
                <span>ENTERPRISE OPERATIONS</span>
                <h1>{{ modeTitle }}</h1>
              </div>
            </div>

            <nav class="screen-nav" aria-label="大屏场景">
              <RouterLink
                v-for="item in screenNavItems"
                :key="item.path"
                :to="item.path"
                :aria-current="item.mode === mode ? 'page' : undefined"
                :class="{ 'is-active': item.mode === mode }"
              >
                <ArtSvgIcon :icon="item.icon" />
                {{ item.label }}
              </RouterLink>
              <RouterLink to="/tms/in-transit-monitor">
                <ArtSvgIcon icon="ri:route-line" />
                在途监控
              </RouterLink>
            </nav>

            <div class="command-header__status">
              <div>
                <time :datetime="currentTime">{{ timeText }}</time>
                <span>{{ dateText }}</span>
              </div>
              <span class="live-status"><i /> 数据已同步</span>
              <button
                type="button"
                class="screen-icon-button"
                :disabled="state.loading"
                aria-label="刷新大屏数据"
                title="刷新大屏数据"
                @click="loadData()"
              >
                <ArtSvgIcon icon="ri:refresh-line" :class="{ 'is-spinning': state.loading }" />
              </button>
            </div>
          </header>

          <main class="screen-content">
            <section class="metric-rail" aria-label="核心经营指标">
              <article v-for="metric in primaryMetrics" :key="metric.label" class="hero-metric">
                <div class="hero-metric__icon" :class="`is-${metric.tone}`">
                  <ArtSvgIcon :icon="metric.icon" />
                </div>
                <div class="hero-metric__content">
                  <span>{{ metric.label }}</span>
                  <strong
                    >{{ metric.value }}<em v-if="metric.unit">{{ metric.unit }}</em></strong
                  >
                  <small>{{ metric.hint }}</small>
                </div>
                <i class="hero-metric__signal" :class="`is-${metric.tone}`" />
              </article>
            </section>

            <template v-if="mode === 'business'">
              <section class="business-layout">
                <div class="screen-column screen-column--left">
                  <article class="screen-panel decision-panel">
                    <ScreenPanelHeading
                      eyebrow="DECISION SIGNAL"
                      title="今日经营决策"
                      icon="ri:focus-2-line"
                    />
                    <div class="decision-score">
                      <div class="score-ring" :style="scoreRingStyle">
                        <div>
                          <strong>{{ businessScore }}</strong>
                          <span>综合健康度</span>
                        </div>
                      </div>
                      <div class="decision-score__copy">
                        <strong>{{ decisionHeadline }}</strong>
                        <p>{{ decisionDescription }}</p>
                      </div>
                    </div>
                    <div class="decision-signals">
                      <div v-for="item in decisionSignals" :key="item.label">
                        <span>{{ item.label }}</span>
                        <strong :class="`is-${item.tone}`">{{ item.value }}</strong>
                      </div>
                    </div>
                  </article>

                  <article class="screen-panel finance-panel">
                    <ScreenPanelHeading
                      eyebrow="CASH & MARGIN"
                      title="资金与利润桥"
                      icon="ri:funds-box-line"
                    />
                    <div class="finance-balance">
                      <span>运输收入</span>
                      <strong>{{ formatCompactCurrency(transportRevenue) }}</strong>
                      <i />
                      <span>已审成本</span>
                      <strong>{{ formatCompactCurrency(data.finance.approvedWaybillCost) }}</strong>
                    </div>
                    <div class="margin-bar" aria-label="运输毛利率">
                      <div>
                        <span>估算毛利率</span>
                        <strong>{{ grossMarginRate }}%</strong>
                      </div>
                      <i><b :style="{ width: `${grossMarginRate}%` }" /></i>
                    </div>
                    <div class="finance-grid">
                      <div
                        ><span>应收口径</span
                        ><strong>{{ formatCompactCurrency(data.finance.receivable) }}</strong></div
                      >
                      <div
                        ><span>应付口径</span
                        ><strong>{{ formatCompactCurrency(data.finance.payable) }}</strong></div
                      >
                      <div
                        ><span>现金流入</span
                        ><strong>{{ formatCompactCurrency(data.finance.cashInflow) }}</strong></div
                      >
                      <div
                        ><span>现金流出</span
                        ><strong>{{ formatCompactCurrency(data.finance.cashOutflow) }}</strong></div
                      >
                    </div>
                  </article>
                </div>

                <div class="screen-column screen-column--center">
                  <article class="screen-panel trend-panel">
                    <ScreenPanelHeading
                      eyebrow="BUSINESS PULSE · 本月"
                      title="订单与收入脉搏"
                      icon="ri:pulse-line"
                    >
                      <template #aside>
                        <span class="panel-caption">共 {{ monthOrderCount }} 单</span>
                      </template>
                    </ScreenPanelHeading>
                    <div class="trend-summary">
                      <div>
                        <span>本月开单收入</span>
                        <strong>{{
                          formatCurrency(
                            data.transport.trend.reduce((sum, item) => sum + item.freightAmount, 0)
                          )
                        }}</strong>
                      </div>
                      <div>
                        <span>日均订单</span>
                        <strong>{{ averageDailyOrders }} <em>单</em></strong>
                      </div>
                      <div>
                        <span>履约完成</span>
                        <strong>{{ completionRate }}<em>%</em></strong>
                      </div>
                    </div>
                    <div class="pulse-chart" :class="{ 'is-empty': !monthOrderCount }">
                      <svg viewBox="0 0 760 230" role="img" aria-label="本月订单趋势折线图">
                        <defs>
                          <linearGradient id="pulse-area" x1="0" y1="0" x2="0" y2="1">
                            <stop
                              offset="0%"
                              stop-color="var(--screen-accent)"
                              stop-opacity=".35"
                            />
                            <stop
                              offset="100%"
                              stop-color="var(--screen-accent)"
                              stop-opacity="0"
                            />
                          </linearGradient>
                        </defs>
                        <g class="pulse-chart__grid">
                          <line
                            v-for="line in [35, 80, 125, 170, 215]"
                            :key="line"
                            x1="24"
                            :y1="line"
                            x2="744"
                            :y2="line"
                          />
                        </g>
                        <path v-if="monthOrderCount" :d="trendAreaPath" class="pulse-chart__area" />
                        <polyline
                          v-if="monthOrderCount"
                          :points="trendPoints"
                          class="pulse-chart__line"
                        />
                        <g v-if="monthOrderCount">
                          <circle
                            v-for="point in trendPointList"
                            :key="point.key"
                            :cx="point.x"
                            :cy="point.y"
                            r="3.5"
                          />
                        </g>
                      </svg>
                      <p v-if="!monthOrderCount">本月尚无订单，数据产生后将在此形成经营趋势</p>
                      <div class="trend-axis" aria-hidden="true">
                        <span v-for="label in trendAxisLabels" :key="label">{{ label }}</span>
                      </div>
                    </div>
                  </article>

                  <article class="screen-panel chain-panel">
                    <ScreenPanelHeading
                      eyebrow="FULFILLMENT CHAIN"
                      title="运输履约链路"
                      icon="ri:route-line"
                    />
                    <div class="fulfillment-chain">
                      <div
                        v-for="(item, index) in fulfillmentStages"
                        :key="item.label"
                        class="chain-node"
                      >
                        <span>{{ item.label }}</span>
                        <strong>{{ item.value }}</strong>
                        <small>{{ item.caption }}</small>
                        <i v-if="index < fulfillmentStages.length - 1"><b /></i>
                      </div>
                    </div>
                  </article>
                </div>

                <div class="screen-column screen-column--right">
                  <article class="screen-panel health-panel">
                    <ScreenPanelHeading
                      eyebrow="DOMAIN HEALTH"
                      title="跨域健康度"
                      icon="ri:heart-pulse-line"
                    />
                    <div class="health-list">
                      <div v-for="item in domainHealth" :key="item.label" class="health-item">
                        <div>
                          <span><ArtSvgIcon :icon="item.icon" />{{ item.label }}</span>
                          <strong>{{ item.score }}<em> / 100</em></strong>
                        </div>
                        <i><b :class="`is-${item.tone}`" :style="{ width: `${item.score}%` }" /></i>
                        <small>{{ item.caption }}</small>
                      </div>
                    </div>
                  </article>

                  <article class="screen-panel risk-panel">
                    <ScreenPanelHeading
                      eyebrow="RISK RADAR"
                      title="待关注事项"
                      icon="ri:alarm-warning-line"
                    >
                      <template #aside
                        ><span class="risk-count">{{ totalRiskCount }}</span></template
                      >
                    </ScreenPanelHeading>
                    <div class="risk-list">
                      <div v-for="item in riskItems" :key="item.label" class="risk-item">
                        <i :class="`is-${item.tone}`" />
                        <div
                          ><strong>{{ item.label }}</strong
                          ><span>{{ item.description }}</span></div
                        >
                        <b>{{ item.value }}</b>
                      </div>
                    </div>
                  </article>
                </div>
              </section>
            </template>

            <template v-else>
              <section class="operations-layout">
                <article class="screen-panel dispatch-panel">
                  <ScreenPanelHeading
                    eyebrow="LIVE QUEUE"
                    title="运输任务队列"
                    icon="ri:truck-line"
                  >
                    <template #aside
                      ><span class="panel-caption"
                        >实时 {{ data.transport.inTransitCount }} 单</span
                      ></template
                    >
                  </ScreenPanelHeading>
                  <div v-if="activeOrders.length" class="dispatch-list">
                    <div
                      v-for="(order, index) in activeOrders"
                      :key="order.orderNo"
                      class="dispatch-item"
                    >
                      <span class="dispatch-item__index">{{
                        String(index + 1).padStart(2, '0')
                      }}</span>
                      <div class="dispatch-item__route">
                        <strong>{{ order.originStation || '待补充起点' }}</strong>
                        <i><b /></i>
                        <strong>{{ order.destinationStation || '待补充终点' }}</strong>
                        <span
                          >{{ order.dispatchPlateNo || '待派车' }} ·
                          {{ order.dispatchDriverName || '待派司机' }}</span
                        >
                      </div>
                      <div class="dispatch-item__eta">
                        <strong>{{ formatEta(order.plannedArrivalTime) }}</strong>
                        <span>{{ order.orderNo }}</span>
                      </div>
                    </div>
                  </div>
                  <div v-else class="screen-empty">
                    <ArtSvgIcon icon="ri:route-line" />
                    <strong>暂无在途任务</strong>
                    <span>新任务进入运输状态后将自动出现在队列中</span>
                  </div>
                </article>

                <article class="screen-panel network-panel">
                  <ScreenPanelHeading
                    eyebrow="CONTROL TOWER"
                    title="全域运营态势"
                    icon="ri:radar-line"
                  />
                  <div class="network-core">
                    <div class="network-orbit network-orbit--outer" />
                    <div class="network-orbit network-orbit--inner" />
                    <div class="network-sweep" />
                    <div class="network-center">
                      <span>当前在途</span>
                      <strong>{{ data.transport.inTransitCount }}</strong>
                      <small>TRANSPORTING</small>
                    </div>
                    <div
                      v-for="node in networkNodes"
                      :key="node.label"
                      class="network-node"
                      :class="`at-${node.position}`"
                    >
                      <i :class="`is-${node.tone}`"><ArtSvgIcon :icon="node.icon" /></i>
                      <div
                        ><strong>{{ node.value }}</strong
                        ><span>{{ node.label }}</span></div
                      >
                    </div>
                  </div>
                  <div class="network-footnote">
                    <span><i class="is-success" />正常履约</span>
                    <span><i class="is-warning" />待处置</span>
                    <span>最近同步 {{ refreshText }}</span>
                  </div>
                </article>

                <article class="screen-panel alert-panel">
                  <ScreenPanelHeading
                    eyebrow="EXCEPTION BOARD"
                    title="异常与资源"
                    icon="ri:error-warning-line"
                  />
                  <div class="alert-summary">
                    <div
                      ><span>风险总量</span><strong>{{ totalRiskCount }}</strong></div
                    >
                    <div
                      ><span>逾期巡检</span
                      ><strong>{{ data.safety.overdueInspections }}</strong></div
                    >
                  </div>
                  <div class="risk-list risk-list--compact">
                    <div v-for="item in riskItems" :key="item.label" class="risk-item">
                      <i :class="`is-${item.tone}`" />
                      <div
                        ><strong>{{ item.label }}</strong
                        ><span>{{ item.description }}</span></div
                      >
                      <b>{{ item.value }}</b>
                    </div>
                  </div>
                  <div class="resource-strip">
                    <div
                      ><span>车辆在线</span
                      ><strong>{{ data.fleet.operating }}/{{ data.fleet.total }}</strong></div
                    >
                    <div
                      ><span>在岗员工</span><strong>{{ data.workforce.active }}</strong></div
                    >
                    <div
                      ><span>设备正常</span
                      ><strong
                        >{{ data.safety.equipmentNormal }}/{{ data.safety.equipmentTotal }}</strong
                      ></div
                    >
                  </div>
                </article>

                <article class="screen-panel flow-panel">
                  <ScreenPanelHeading
                    eyebrow="ORDER PIPELINE"
                    title="订单履约漏斗"
                    icon="ri:filter-3-line"
                  />
                  <div class="flow-track">
                    <div v-for="item in fulfillmentStages" :key="item.label">
                      <span>{{ item.label }}</span>
                      <i><b :style="{ width: `${Math.max(item.percent, 4)}%` }" /></i>
                      <strong>{{ item.value }}</strong>
                    </div>
                  </div>
                </article>
              </section>
            </template>
          </main>

          <footer class="screen-footer">
            <span>数据范围：当前租户可见业务数据</span>
            <span>{{
              mode === 'business' ? '管理驾驶舱 · 经营决策视角' : '运营控制塔 · 实时履约视角'
            }}</span>
            <span>亿企工场 · 企业数字运营平台</span>
          </footer>
        </div>
      </ElScrollbar>
    </ArtAsyncState>
  </div>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import ScreenPanelHeading from './screen-panel-heading.vue'
  import {
    fetchEnterpriseDashboardData,
    type EnterpriseDashboardData
  } from '@/api/enterprise-dashboard'

  type ScreenMode = 'business' | 'operations'
  type MetricTone = 'primary' | 'success' | 'warning' | 'danger' | 'info'

  interface Props {
    mode: ScreenMode
  }

  interface PrimaryMetric {
    label: string
    value: string
    unit?: string
    hint: string
    icon: string
    tone: MetricTone
  }

  interface ScreenState {
    loading: boolean
    loaded: boolean
    error: Error | null
    requestId: number
  }

  const props = defineProps<Props>()
  const router = useRouter()
  const currentTime = ref(new Date().toISOString())
  const state = reactive<ScreenState>({ loading: false, loaded: false, error: null, requestId: 0 })

  const createEmptyData = (): EnterpriseDashboardData => ({
    generatedAt: new Date().toISOString(),
    transport: {
      todayOrderCount: 0,
      todayFreightAmount: 0,
      pendingDispatchCount: 0,
      inTransitCount: 0,
      vehicleCount: 0,
      operatingVehicleCount: 0,
      pendingAuditVehicleCount: 0,
      completedTodayCount: 0,
      trend: [],
      statusCounts: {},
      transitOrders: [],
      recentOrders: [],
      reminders: []
    },
    fleet: { total: 0, operating: 0, pendingAudit: 0, dueDocuments: 0 },
    finance: {
      voucherCount: 0,
      postedAmount: 0,
      cashInflow: 0,
      cashOutflow: 0,
      receivable: 0,
      payable: 0,
      approvedWaybillCost: 0
    },
    workforce: { total: 0, active: 0, probation: 0, expiringContracts: 0 },
    safety: {
      openHazards: 0,
      overdueHazards: 0,
      overdueInspections: 0,
      recentAccidents: 0,
      equipmentTotal: 0,
      equipmentNormal: 0,
      criticalEquipment: 0
    }
  })
  const data = reactive<EnterpriseDashboardData>(createEmptyData())

  const mode = computed(() => props.mode)
  const modeTitle = computed(() =>
    mode.value === 'business' ? '企业经营驾驶舱' : '全域运营态势大屏'
  )
  const timeText = computed(() => dayjs(currentTime.value).format('HH:mm:ss'))
  const dateText = computed(() => dayjs(currentTime.value).format('YYYY年MM月DD日 · dddd'))
  const refreshText = computed(() => dayjs(data.generatedAt).format('HH:mm:ss'))
  const screenNavItems = [
    {
      mode: 'business',
      label: '经营驾驶舱',
      path: '/dashboard/business-cockpit',
      icon: 'ri:bar-chart-box-line'
    },
    {
      mode: 'operations',
      label: '运营态势',
      path: '/dashboard/operations-command',
      icon: 'ri:radar-line'
    }
  ] as const

  const transportRevenue = computed(() =>
    data.transport.trend.reduce((sum, item) => sum + item.freightAmount, 0)
  )
  const monthOrderCount = computed(() =>
    data.transport.trend.reduce((sum, item) => sum + item.orderCount, 0)
  )
  const averageDailyOrders = computed(() =>
    data.transport.trend.length
      ? Math.round(monthOrderCount.value / data.transport.trend.length)
      : 0
  )
  const completedCount = computed(() => data.transport.statusCounts.completed ?? 0)
  const statusTotal = computed(() =>
    Object.values(data.transport.statusCounts).reduce((sum, value) => sum + value, 0)
  )
  const completionRate = computed(() =>
    statusTotal.value ? Math.round((completedCount.value / statusTotal.value) * 100) : 100
  )
  const fleetRate = computed(() => percentage(data.fleet.operating, data.fleet.total))
  const equipmentRate = computed(() =>
    percentage(data.safety.equipmentNormal, data.safety.equipmentTotal)
  )
  const workforceRate = computed(() => percentage(data.workforce.active, data.workforce.total))
  const safetyScore = computed(() =>
    Math.max(
      0,
      100 -
        data.safety.overdueHazards * 8 -
        data.safety.overdueInspections * 3 -
        data.safety.recentAccidents * 12
    )
  )
  const businessScore = computed(() =>
    Math.round(
      (completionRate.value + fleetRate.value + workforceRate.value + safetyScore.value) / 4
    )
  )
  const scoreRingStyle = computed(() => ({
    '--score-angle': `${Math.max(0, Math.min(100, businessScore.value)) * 3.6}deg`
  }))
  const grossMarginRate = computed(() => {
    if (!transportRevenue.value) return 0
    return Math.max(
      0,
      Math.min(
        100,
        Math.round(
          ((transportRevenue.value - data.finance.approvedWaybillCost) / transportRevenue.value) *
            100
        )
      )
    )
  })
  const decisionHeadline = computed(() => {
    if (totalRiskCount.value > 10) return '风险事项需要优先收敛'
    if (data.transport.pendingDispatchCount > data.transport.inTransitCount)
      return '调度积压值得关注'
    return '整体运营保持稳定'
  })
  const decisionDescription = computed(() => {
    if (data.safety.overdueInspections)
      return `当前有 ${data.safety.overdueInspections} 项巡检已逾期，建议优先安排责任人闭环。`
    if (data.fleet.dueDocuments)
      return `未来 30 天有 ${data.fleet.dueDocuments} 项车辆证照到期，请提前安排续办。`
    return '运输、车辆、人员和安全关键指标处于可控区间。'
  })

  const primaryMetrics = computed<PrimaryMetric[]>(() =>
    mode.value === 'business'
      ? [
          {
            label: '今日开单',
            value: String(data.transport.todayOrderCount),
            unit: '单',
            hint: '今日新增运输订单',
            icon: 'ri:file-list-3-line',
            tone: 'primary'
          },
          {
            label: '今日运费',
            value: formatCompactNumber(data.transport.todayFreightAmount),
            unit: '元',
            hint: '开单收入实时口径',
            icon: 'ri:money-cny-circle-line',
            tone: 'info'
          },
          {
            label: '履约完成率',
            value: String(completionRate.value),
            unit: '%',
            hint: '全量订单完成占比',
            icon: 'ri:checkbox-circle-line',
            tone: 'success'
          },
          {
            label: '车辆运营率',
            value: String(fleetRate.value),
            unit: '%',
            hint: `${data.fleet.operating}/${data.fleet.total} 台运营中`,
            icon: 'ri:truck-line',
            tone: 'success'
          },
          {
            label: '在岗人数',
            value: String(data.workforce.active),
            unit: '人',
            hint: `人员总量 ${data.workforce.total} 人`,
            icon: 'ri:team-line',
            tone: 'primary'
          },
          {
            label: '风险待处理',
            value: String(totalRiskCount.value),
            unit: '项',
            hint: '跨域异常聚合',
            icon: 'ri:alarm-warning-line',
            tone: totalRiskCount.value ? 'warning' : 'success'
          }
        ]
      : [
          {
            label: '当前在途',
            value: String(data.transport.inTransitCount),
            unit: '单',
            hint: '正在执行运输任务',
            icon: 'ri:route-line',
            tone: 'primary'
          },
          {
            label: '待调度',
            value: String(data.transport.pendingDispatchCount),
            unit: '单',
            hint: '等待车辆与司机',
            icon: 'ri:time-line',
            tone: 'warning'
          },
          {
            label: '今日完成',
            value: String(data.transport.completedTodayCount),
            unit: '单',
            hint: '今日签收结案',
            icon: 'ri:checkbox-circle-line',
            tone: 'success'
          },
          {
            label: '运营车辆',
            value: String(data.fleet.operating),
            unit: '台',
            hint: `车队总量 ${data.fleet.total} 台`,
            icon: 'ri:truck-line',
            tone: 'success'
          },
          {
            label: '逾期巡检',
            value: String(data.safety.overdueInspections),
            unit: '项',
            hint: '安全巡检任务',
            icon: 'ri:shield-check-line',
            tone: data.safety.overdueInspections ? 'danger' : 'success'
          },
          {
            label: '证照临期',
            value: String(data.fleet.dueDocuments),
            unit: '项',
            hint: '未来 30 天到期',
            icon: 'ri:calendar-event-line',
            tone: data.fleet.dueDocuments ? 'warning' : 'success'
          }
        ]
  )

  const decisionSignals = computed(() => [
    {
      label: '待调度订单',
      value: `${data.transport.pendingDispatchCount} 单`,
      tone: data.transport.pendingDispatchCount ? 'warning' : 'success'
    },
    {
      label: '逾期隐患',
      value: `${data.safety.overdueHazards} 项`,
      tone: data.safety.overdueHazards ? 'danger' : 'success'
    },
    {
      label: '人员在岗率',
      value: `${workforceRate.value}%`,
      tone: workforceRate.value >= 90 ? 'success' : 'warning'
    }
  ])
  const domainHealth = computed(() => [
    {
      label: '运输履约',
      score: completionRate.value,
      caption: `${data.transport.inTransitCount} 单在途 · ${data.transport.pendingDispatchCount} 单待调度`,
      icon: 'ri:route-line',
      tone: scoreTone(completionRate.value)
    },
    {
      label: '车辆资产',
      score: fleetRate.value,
      caption: `${data.fleet.operating}/${data.fleet.total} 台运营中`,
      icon: 'ri:truck-line',
      tone: scoreTone(fleetRate.value)
    },
    {
      label: '组织人力',
      score: workforceRate.value,
      caption: `${data.workforce.active} 人在岗 · ${data.workforce.probation} 人试用期`,
      icon: 'ri:team-line',
      tone: scoreTone(workforceRate.value)
    },
    {
      label: '安全生产',
      score: safetyScore.value,
      caption: `${data.safety.openHazards} 项隐患 · ${data.safety.overdueInspections} 项逾期巡检`,
      icon: 'ri:shield-check-line',
      tone: scoreTone(safetyScore.value)
    },
    {
      label: '设备运行',
      score: equipmentRate.value,
      caption: `${data.safety.equipmentNormal}/${data.safety.equipmentTotal} 台设备正常`,
      icon: 'ri:settings-3-line',
      tone: scoreTone(equipmentRate.value)
    }
  ])
  const riskItems = computed(() => [
    {
      label: '待调度订单',
      value: data.transport.pendingDispatchCount,
      description: '等待车辆与司机资源匹配',
      tone: 'warning'
    },
    {
      label: '车辆证照临期',
      value: data.fleet.dueDocuments,
      description: '未来 30 天保险或年检到期',
      tone: 'warning'
    },
    {
      label: '逾期安全巡检',
      value: data.safety.overdueInspections,
      description: '超过计划完成时间仍未闭环',
      tone: 'danger'
    },
    {
      label: '未闭环隐患',
      value: data.safety.openHazards,
      description: '处于审批、整改或验收阶段',
      tone: 'danger'
    },
    {
      label: '员工合同临期',
      value: data.workforce.expiringContracts,
      description: '未来 30 天合同到期',
      tone: 'info'
    }
  ])
  const totalRiskCount = computed(() => riskItems.value.reduce((sum, item) => sum + item.value, 0))

  const fulfillmentStages = computed(() => {
    const definitions = [
      { key: 'pending_load', label: '待配载', caption: '资源匹配' },
      { key: 'pending_order', label: '待发车', caption: '装车准备' },
      { key: 'transporting', label: '运输中', caption: '在途执行' },
      { key: 'signed', label: '待结案', caption: '回单核验' },
      { key: 'completed', label: '已完成', caption: '履约闭环' }
    ]
    const max = Math.max(
      ...definitions.map((item) => data.transport.statusCounts[item.key] ?? 0),
      1
    )
    return definitions.map((item) => {
      const value = data.transport.statusCounts[item.key] ?? 0
      return { ...item, value, percent: Math.round((value / max) * 100) }
    })
  })
  const activeOrders = computed(() => data.transport.transitOrders.slice(0, 6))
  const networkNodes = computed(() => [
    {
      label: '待调度',
      value: data.transport.pendingDispatchCount,
      icon: 'ri:time-line',
      tone: 'warning',
      position: 'top'
    },
    {
      label: '今日完成',
      value: data.transport.completedTodayCount,
      icon: 'ri:checkbox-circle-line',
      tone: 'success',
      position: 'right'
    },
    {
      label: '运营车辆',
      value: data.fleet.operating,
      icon: 'ri:truck-line',
      tone: 'primary',
      position: 'bottom'
    },
    {
      label: '风险事项',
      value: totalRiskCount.value,
      icon: 'ri:alarm-warning-line',
      tone: totalRiskCount.value ? 'danger' : 'success',
      position: 'left'
    }
  ])

  const trendPointList = computed(() => {
    const values = data.transport.trend.map((item) => item.orderCount)
    const max = Math.max(...values, 1)
    const width = 720
    const height = 180
    return values.map((value, index) => ({
      key: `${index}-${value}`,
      x: 24 + (values.length <= 1 ? 0 : (index / (values.length - 1)) * width),
      y: 215 - (value / max) * height
    }))
  })
  const trendPoints = computed(() =>
    trendPointList.value.map((item) => `${item.x},${item.y}`).join(' ')
  )
  const trendAreaPath = computed(() => {
    const points = trendPointList.value
    if (!points.length) return ''
    return `M ${points[0].x} 215 L ${points.map((item) => `${item.x} ${item.y}`).join(' L ')} L ${points.at(-1)?.x ?? 24} 215 Z`
  })
  const trendAxisLabels = computed(() => {
    const labels = data.transport.trend.map((item) => item.label)
    if (!labels.length) return ['月初', '月中', '月末']
    return [labels[0], labels[Math.floor((labels.length - 1) / 2)], labels.at(-1)]
  })

  useIntervalFn(() => {
    currentTime.value = new Date().toISOString()
  }, 1000)
  useIntervalFn(() => {
    void loadData(false)
  }, 60000)

  onMounted(() => {
    void loadData()
  })

  async function loadData(showLoading = true): Promise<void> {
    const requestId = ++state.requestId
    if (showLoading) state.loading = true
    state.error = null
    try {
      const result = await fetchEnterpriseDashboardData()
      if (requestId !== state.requestId) return
      Object.assign(data, result)
      state.loaded = true
    } catch (error) {
      if (requestId !== state.requestId) return
      state.error = error instanceof Error ? error : new Error('企业经营大屏加载失败')
    } finally {
      if (requestId === state.requestId) state.loading = false
    }
  }

  function percentage(value: number, total: number): number {
    return total ? Math.max(0, Math.min(100, Math.round((value / total) * 100))) : 100
  }

  function scoreTone(score: number): MetricTone {
    if (score >= 90) return 'success'
    if (score >= 75) return 'primary'
    if (score >= 60) return 'warning'
    return 'danger'
  }

  function formatCompactNumber(value: number): string {
    return new Intl.NumberFormat('zh-CN', {
      notation: value >= 10000 ? 'compact' : 'standard',
      maximumFractionDigits: 1
    }).format(value)
  }

  function formatCurrency(value: number): string {
    return new Intl.NumberFormat('zh-CN', {
      style: 'currency',
      currency: 'CNY',
      maximumFractionDigits: 0
    }).format(value)
  }

  function formatCompactCurrency(value: number): string {
    return `${formatCompactNumber(value)} 元`
  }

  function formatEta(value?: string | null): string {
    if (!value) return '待确认 ETA'
    const target = dayjs(value)
    if (!target.isValid()) return '待确认 ETA'
    const diff = target.diff(dayjs(), 'minute')
    if (diff < 0) return `已超时 ${Math.abs(diff)} 分钟`
    if (diff < 60) return `${diff} 分钟后到达`
    return `${Math.floor(diff / 60)} 小时 ${diff % 60} 分后到达`
  }

  function exitScreen(): void {
    if (window.history.length > 1) {
      router.back()
      return
    }
    void router.push('/dashboard/console')
  }
</script>

<style scoped lang="scss" src="./enterprise-big-screen.scss"></style>
