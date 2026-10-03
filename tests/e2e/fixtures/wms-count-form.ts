import { createApp, defineComponent, h, ref } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { setupGlobDirectives } from '@/directives'
import language from '@/locales'
import { store } from '@/store'
import { useUserStore } from '@/store/modules/user'
import type { WmsCountLine } from '../../../modules/art-supabase-wms/src/api/warehouse.types'
import CountLineDialog from '../../../modules/art-supabase-wms/src/views/count-business/count/modules/count-line-dialog.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const line: WmsCountLine = {
  id: '11111111-1111-4111-8111-111111111111',
  tenantId: '22222222-2222-4222-8222-222222222222',
  planId: '33333333-3333-4333-8333-333333333333',
  batchId: '44444444-4444-4444-8444-444444444444',
  materialId: '55555555-5555-4555-8555-555555555555',
  projectId: null,
  constructionNo: null,
  expectedQuantity: 2,
  expectedAreaSqm: null,
  expectedSerialIds: [],
  countedQuantity: null,
  countedSerialIds: [],
  newSerialNos: [],
  lossMovementId: null,
  gainMovementId: null,
  countedAt: null,
  material: {
    materialCode: 'TEST-COUNT',
    materialName: '测试盘点物料',
    serialManagementEnabled: false
  }
}
useUserStore(store).setUserInfo({
  userId: '66666666-6666-4666-8666-666666666666',
  tenantId: line.tenantId,
  platformSuper: true
} as Api.Auth.UserInfo)
const app = createApp(
  defineComponent({
    setup() {
      const dialog = ref<InstanceType<typeof CountLineDialog>>()
      const saved = ref(0)
      return () =>
        h('div', [
          h('button', { onClick: () => dialog.value?.handleOpen(line) }, '打开测试盘点'),
          h('output', { 'data-testid': 'saved-count' }, saved.value),
          h(CountLineDialog, { ref: dialog, onSuccess: () => (saved.value += 1) })
        ])
    }
  })
)
app.use(store)
app.use(language)
app.use(
  createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: { template: '<div />' } }]
  })
)
setupGlobDirectives(app)
app.mount('#count-preview')
