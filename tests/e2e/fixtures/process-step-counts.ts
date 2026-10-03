import { createApp, h, ref } from 'vue'
import language from '@/locales'
import { store } from '@/store'
import { fetchProcessSteps } from '../../../modules/art-supabase-mdm/src/api/modules/workspaces'

const result = ref('尚未查询')
const app = createApp({
  render: () =>
    h('main', [
      h(
        'button',
        {
          onClick: async () => {
            try {
              result.value = JSON.stringify(await fetchProcessSteps({ current: 1, size: 20 }))
            } catch {
              result.value = '查询失败'
            }
          }
        },
        '查询工序'
      ),
      h('output', { 'data-testid': 'step-result' }, result.value)
    ])
})
app.use(store)
app.use(language)
app.mount('#step-counts-preview')
