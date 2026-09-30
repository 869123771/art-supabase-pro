import { createApp, h, nextTick } from 'vue'
import { createRouter, createWebHashHistory } from 'vue-router'
import '@/assets/styles/core/tailwind.css'
import '@/assets/styles/index.scss'
import { createPinia } from 'pinia'
import type { DomainCommandKind } from '@/api/domain-command'

const screen = new URLSearchParams(location.search).get('screen') || 'business'
const nativeFetch = globalThis.fetch.bind(globalThis)
globalThis.fetch = (input, init) => {
  const url = input instanceof Request ? input.url : String(input)
  if (/^https?:\/\//.test(url) && !url.startsWith(location.origin)) {
    return new Promise<Response>(() => {})
  }
  return nativeFetch(input, init)
}
const app = createApp({ render: () => h(component, componentProps) })
app.use(createPinia())
const [EnterpriseBigScreen, DomainCommandScreen, AssetMaintenanceBigScreen] = await Promise.all([
  import('@/views/dashboard/modules/enterprise-big-screen.vue').then((module) => module.default),
  import('@/views/dashboard/modules/domain-command-screen.vue').then((module) => module.default),
  import('@/views/dashboard/modules/asset-maintenance-big-screen.vue').then(
    (module) => module.default
  )
])
const domainKinds = new Set([
  'ai-safety',
  'safety-production',
  'financial-risk',
  'workflow-efficiency',
  'fleet-compliance',
  'data-governance',
  'workforce-insight'
])
const component =
  screen === 'asset'
    ? AssetMaintenanceBigScreen
    : domainKinds.has(screen)
      ? DomainCommandScreen
      : EnterpriseBigScreen
const componentProps = domainKinds.has(screen)
  ? { kind: screen as DomainCommandKind }
  : { mode: screen === 'operations' ? 'operations' : 'business' }
const router = createRouter({ history: createWebHashHistory(), routes: [] })
app.use(router).mount('#app')

await nextTick()
const instance = document.querySelector(
  '.enterprise-screen, .domain-command-screen'
)?.__vueParentComponent
if (instance) {
  const { state, data } = instance.setupState
  state.requestId += 1
  state.loading = false
  state.loaded = true
  state.error = null

  if (screen === 'business' || screen === 'operations') {
    Object.assign(data.transport, {
      todayOrderCount: 0,
      todayFreightAmount: 0,
      pendingDispatchCount: 2,
      inTransitCount: 0,
      vehicleCount: 5,
      operatingVehicleCount: 5,
      completedTodayCount: 0,
      trend: [{ freightAmount: 188948.7, orderCount: 5 }],
      statusCounts: { pending_load: 0, pending_order: 0, transporting: 0, signed: 0, completed: 1 },
      transitOrders: []
    })
    Object.assign(data.fleet, { total: 5, operating: 5, dueDocuments: 0 })
    Object.assign(data.finance, { approvedWaybillCost: 5390.83, cashInflow: 0, cashOutflow: 0 })
    Object.assign(data.workforce, { total: 8, active: 8 })
    Object.assign(data.safety, {
      openHazards: 3,
      overdueHazards: 1,
      overdueInspections: 170,
      equipmentTotal: 9,
      equipmentNormal: 9
    })
  } else {
    const isSafety = screen === 'safety-production'
    const isFlow = screen === 'workflow-efficiency'
    Object.assign(data, {
      score: isSafety ? 63 : isFlow ? 78 : 82,
      headline: isSafety
        ? '重大风险与逾期任务需要优先处置'
        : isFlow
          ? '审批瓶颈正在影响业务时效'
          : '关键运行指标总体平稳',
      description: isSafety
        ? '1 项重大风险与 170 项逾期巡检待闭环。'
        : isFlow
          ? '2 次 SLA 违约，3 项流程仍在运行。'
          : '持续关注异常节点与待办事项。',
      activeCount: isSafety ? 2 : isFlow ? 3 : 12,
      riskCount: isSafety ? 173 : isFlow ? 6 : 8,
      metrics: isSafety
        ? [
            {
              label: '风险点',
              value: '2',
              unit: '处',
              hint: '四色风险地图',
              icon: 'ri:map-pin-line',
              tone: 'warning'
            },
            {
              label: '重大风险',
              value: '0',
              unit: '项',
              hint: '0 项未受控',
              icon: 'ri:alarm-warning-line',
              tone: 'success'
            },
            {
              label: '开放隐患',
              value: '3',
              unit: '项',
              hint: '1 项逾期',
              icon: 'ri:error-warning-line',
              tone: 'danger'
            },
            {
              label: '巡检任务',
              value: '182',
              unit: '项',
              hint: '0 项完成',
              icon: 'ri:checkbox-line',
              tone: 'info'
            },
            {
              label: '巡检逾期',
              value: '170',
              unit: '项',
              hint: '需要立即处理',
              icon: 'ri:timer-line',
              tone: 'danger'
            }
          ]
        : isFlow
          ? [
              {
                label: '运行流程',
                value: '3',
                unit: '条',
                hint: '当前审批中',
                icon: 'ri:flow-chart',
                tone: 'info'
              },
              {
                label: 'SLA 达标率',
                value: '77.8',
                unit: '%',
                hint: '2 次违约',
                icon: 'ri:timer-line',
                tone: 'warning'
              },
              {
                label: '平均审批时长',
                value: '0.3',
                unit: 'h',
                hint: 'P90 0.3h',
                icon: 'ri:time-line',
                tone: 'info'
              },
              {
                label: '逾期待办',
                value: '2',
                unit: '项',
                hint: '3 项待处理',
                icon: 'ri:alarm-warning-line',
                tone: 'danger'
              }
            ]
          : [
              {
                label: '运行规模',
                value: '12',
                unit: '项',
                hint: '实时统计',
                icon: 'ri:dashboard-line',
                tone: 'primary'
              },
              {
                label: '待关注',
                value: '8',
                unit: '项',
                hint: '待处理',
                icon: 'ri:alarm-warning-line',
                tone: 'warning'
              },
              {
                label: '健康指数',
                value: '82',
                unit: '分',
                hint: '综合评估',
                icon: 'ri:heart-pulse-line',
                tone: 'success'
              },
              {
                label: '完成任务',
                value: '24',
                unit: '项',
                hint: '本期累计',
                icon: 'ri:checkbox-line',
                tone: 'info'
              }
            ],
      nodes: ['治理监控', '资源运行', '业务流程', '风险处置', '人员保障', '数据节点'].map(
        (label, index) => ({
          label,
          score: index === 4 ? 67 : 90 + index,
          caption: label,
          icon: 'ri:dashboard-line',
          tone: index === 4 ? 'danger' : 'success'
        })
      ),
      distribution: isSafety
        ? [
            { label: '重大风险', value: 0, tone: 'danger' },
            { label: '较大风险', value: 1, tone: 'warning' },
            { label: '一般风险', value: 0, tone: 'info' },
            { label: '低风险', value: 0, tone: 'success' },
            { label: '未分级', value: 1, tone: 'info' }
          ]
        : isFlow
          ? [{ label: '运单费用', value: 6, tone: 'info' }]
          : [
              { label: '业务运行', value: 12, tone: 'info' },
              { label: '风险处置', value: 4, tone: 'warning' },
              { label: '数据质量', value: 8, tone: 'success' }
            ],
      stages: isSafety
        ? [
            { label: '待辨识', value: 2 },
            { label: '待管控', value: 1 },
            { label: '巡检中', value: 12 },
            { label: '待整改', value: 3 },
            { label: '已闭环', value: 170 }
          ]
        : isFlow
          ? [
              { label: '已通过', value: 6 },
              { label: '已驳回', value: 0 },
              { label: '审批中', value: 3 }
            ]
          : [
              { label: '待处理', value: 3 },
              { label: '处理中', value: 5 },
              { label: '已完成', value: 12 }
            ],
      trend: Array.from({ length: 14 }, (_, index) => ({
        label: `09/${String(index + 17).padStart(2, '0')}`,
        primary: isSafety
          ? index >= 11
            ? 182
            : 0
          : isFlow
            ? index >= 11
              ? index - 9
              : 0
            : index + 7,
        secondary: isSafety ? (index >= 11 ? 170 : 0) : isFlow ? 0 : Math.max(0, 5 - index / 4)
      })),
      alerts: isSafety
        ? [
            { id: '1', title: '人员拥堵', detail: '13张 · 宏访', value: '待评价', tone: 'warning' },
            {
              id: '2',
              title: '人员拥堵',
              detail: '13张 · 路离',
              value: '较大风险',
              tone: 'warning'
            },
            { id: '3', title: '人员拥堵', detail: '巡检任务逾期', value: '逾期', tone: 'danger' },
            { id: '4', title: '人员拥堵', detail: '巡检任务逾期', value: '逾期', tone: 'danger' }
          ]
        : isFlow
          ? [
              {
                id: '1',
                title: '运单费用审批',
                detail: '3 项待办 · P90 0.3h',
                value: '严重',
                tone: 'danger'
              },
              {
                id: '2',
                title: '司机费用上报',
                detail: '下游系统回执异常',
                value: '死信',
                tone: 'danger'
              },
              { id: '3', title: '司机费用上报', detail: '回调异常', value: '死信', tone: 'danger' },
              { id: '4', title: '运单费用审批', detail: '回调异常', value: '死信', tone: 'danger' }
            ]
          : [{ id: '1', title: '运行异常', detail: '待处理', value: '高优先级', tone: 'warning' }]
    })
  }
}
