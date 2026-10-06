import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { useUserStore } from '@/store/modules/user'
import { setupGlobDirectives } from '@/directives'
import WorkstationPage from '../../../modules/art-supabase-mdm/src/views/process-master/workstation/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/:pathMatch(.*)*', name: 'MdmWorkstation', component: {} }]
})
const app = createApp({ render: () => h(WorkstationPage) })
app.use(store)
app.use(router)
app.use(language)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'permission-test-user',
  tenantId: 'permission-test-tenant',
  platformSuper: true
})
await router.isReady()
app.mount('#workstation-delete')
