import { createApp, defineComponent, h, ref } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { store } from '@/store'
import { setupGlobDirectives } from '@/directives'
import language from '@/locales'
import { useUserStore } from '@/store/modules/user'
import { useMenuStore } from '@/store/modules/menu'
import ArtButtonMore, {
  type ButtonMoreItem
} from '@/components/core/forms/art-button-more/index.vue'
import HazardLedgerDetailDrawer from '../../../modules/art-supabase-smis/src/views/dual-control-system/dual-control-checklist/hidden-hazard-governance-ledger/modules/hazard-ledger-detail-drawer.vue'
import type { SmisHiddenHazardLedgerRecord } from '@smis/api'
import VehicleAccident from '../../../modules/art-supabase-vms/src/views/vehicle-manage/accident-record-detail/index.vue'
import VehicleMaintenance from '../../../modules/art-supabase-vms/src/views/vehicle-manage/maintenance-record-detail/index.vue'
import VehicleInspection from '../../../modules/art-supabase-vms/src/views/vehicle-manage/routine-inspection-detail/index.vue'
import VehicleInsurance from '../../../modules/art-supabase-vms/src/views/vehicle-manage/vehicle-insurance-detail/index.vue'
import ProfitAnalysis from '../../../modules/art-supabase-fms/src/views/settlement/waybill-profit/modules/waybill-profit-analysis-drawer.vue'
import CollectionAdvisor from '../../../modules/art-supabase-fms/src/views/workbench/modules/receivables-collection-advisor-drawer.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const record: SmisHiddenHazardLedgerRecord = {
  id: 'date-hazard',
  hazardNo: 'DATE-001',
  sourceType: 'inspection',
  description: '测试日期显示',
  location: '测试检查区',
  hazardLevel: 'general',
  status: 'draft',
  reporterEmployeeNo: 'DATE-EMP',
  reporterEmployeeName: '测试上报人',
  reportedAt: '2026-10-08T00:30:00Z',
  approvedAt: 'invalid',
  rectificationDeadline: '',
  rectificationCompletedAt: null,
  acceptedAt: '2026-10-08T02:45:59Z',
  closedAt: null,
  imageUrls: [],
  rectificationImageUrls: [],
  acceptanceImageUrls: [],
  overdue: false,
  evidenceCount: 0,
  events: [{ id: 'event-date', title: '测试流转日期', eventAt: 'invalid', evidenceUrls: [] }]
}

const Preview = defineComponent({
  setup() {
    const drawer = ref<InstanceType<typeof HazardLedgerDetailDrawer> | null>(null)
    const profit = ref<InstanceType<typeof ProfitAnalysis> | null>(null)
    const collection = ref<InstanceType<typeof CollectionAdvisor> | null>(null)
    const selected = ref('尚未选择')
    const explicitClick = new URLSearchParams(location.search).has('click')
    return () =>
      h('main', [
        h(RouterView),
        h(
          'button',
          { type: 'button', onClick: () => void profit.value?.handleOpen() },
          '打开利润日期验收'
        ),
        h(
          'button',
          { type: 'button', onClick: () => void collection.value?.handleOpen() },
          '打开回款日期验收'
        ),
        h(ProfitAnalysis, { ref: profit }),
        h(CollectionAdvisor, { ref: collection }),
        h(ArtButtonMore, {
          trigger: explicitClick ? 'click' : undefined,
          list: [
            { key: 'preview', label: '查看说明', auth: 'Fixture:View' },
            { key: 'disabled', label: '禁用操作', disabled: true, auth: 'Fixture:View' },
            { key: 'denied', label: '未授权操作', auth: 'Fixture:Denied' }
          ],
          onClick: (item: ButtonMoreItem) => {
            selected.value = String(item.key)
          }
        }),
        h('p', { role: 'status' }, selected.value),
        h(
          'button',
          { type: 'button', onClick: () => void drawer.value?.handleOpen({ row: record }) },
          '打开日期验收'
        ),
        h(HazardLedgerDetailDrawer, { ref: drawer })
      ])
  }
})
const app = createApp(Preview)
app.use(store)
app.use(language)
setupGlobDirectives(app)
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    { path: '/', component: { render: () => null } },
    { path: '/accident/:id', component: VehicleAccident },
    { path: '/maintenance/:id', component: VehicleMaintenance },
    { path: '/inspection/:id', component: VehicleInspection },
    { path: '/insurance/:id', component: VehicleInsurance }
  ]
})
app.use(router)
useUserStore(store).setUserInfo({
  userId: 'date-test-user',
  tenantId: 'date-test-tenant',
  platformSuper: false
})
useMenuStore(store).setButtonList([
  { name: 'Fixture:View', path: '', type: 'button', meta: { title: '查看说明' } }
])
const vehicle = new URLSearchParams(location.search).get('vehicle')
await router.push(vehicle ? `/${vehicle}/display-test` : '/')
await router.isReady()
app.mount('#date-preview')
