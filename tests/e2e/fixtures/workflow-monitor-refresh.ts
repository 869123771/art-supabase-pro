import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { setupGlobDirectives } from '@/directives'
import language from '@/locales'
import { store } from '@/store'
import WorkflowMonitor from '@/views/workflow/monitor/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const app = createApp({ render: () => h(WorkflowMonitor) })
app.use(store)
app.use(language)
app.use(
  createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: { template: '<div />' } }]
  })
)
setupGlobDirectives(app)
app.mount('#monitor-preview')
