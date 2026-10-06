import { createApp, h, ref, nextTick } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { useUserStore } from '@/store/modules/user'
import { setupGlobDirectives } from '@/directives'
import BomDialog from '../../../modules/art-supabase-mdm/src/views/engineering/bom-maintenance/modules/bom-dialog.vue'
import type { BomRecord } from '../../../modules/art-supabase-mdm/src/api'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const tenantId = '11111111-1111-4111-8111-111111111111'
const dialog = ref<InstanceType<typeof BomDialog>>()
const successes = ref(0)
const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/:pathMatch(.*)*', component: {} }]
})
const row: BomRecord = {
  id: 'bom-a',
  tenantId,
  materialId: 'material-a',
  bomCode: 'BOM-TEST',
  version: 'V1',
  purpose: 'production',
  status: 'design',
  baseQuantity: 1,
  baseUnitId: 'unit-a',
  sort: 0,
  processRouteId: 'route-a',
  items: [],
  description: '填写保留'
}
const app = createApp({
  render: () =>
    h('main', [
      h(
        'button',
        {
          onClick: async () => {
            useUserStore(store).setUserInfo({ userId: 'test-user', tenantId, platformSuper: true })
            await nextTick()
            void dialog.value?.handleOpen({
              row,
              tenantId,
              tenantOptions: [],
              units: [],
              groups: []
            })
          }
        },
        '打开 BOM'
      ),
      h(BomDialog, { ref: dialog, onSuccess: () => successes.value++ }),
      h(
        'button',
        {
          onClick: () =>
            dialog.value?.handleOpen({
              row: {
                ...row,
                id: 'bom-b',
                tenantId: '22222222-2222-4222-8222-222222222222',
                materialId: 'material-b',
                processRouteId: 'route-b',
                bomCode: 'BOM-OTHER',
                version: 'V2'
              },
              tenantId: '22222222-2222-4222-8222-222222222222',
              tenantOptions: [],
              units: [],
              groups: []
            })
        },
        '打开另一租户 BOM'
      ),
      h('button', { onClick: () => router.push('/away') }, '离开 BOM 页面'),
      h('output', { 'data-testid': 'success-count' }, String(successes.value))
    ])
})
app.use(store)
app.use(router)
app.use(language)
setupGlobDirectives(app)
app.mount('#bom-preview')
