import { createApp, h, ref } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { setupGlobDirectives } from '@/directives'
import GovernanceDialog from '../../../modules/art-supabase-mdm/src/views/governance-center/modules/governance-config-dialog.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const dialog = ref<InstanceType<typeof GovernanceDialog>>()
const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/:pathMatch(.*)*', component: {} }]
})
const app = createApp({
  render: () =>
    h('main', [
      h('button', { onClick: () => dialog.value?.handleOpen('steward') }, '配置责任人'),
      h(GovernanceDialog, { ref: dialog })
    ])
})
app.use(store)
app.use(router)
app.use(language)
setupGlobDirectives(app)
await router.isReady()
app.mount('#governance-user-state')
