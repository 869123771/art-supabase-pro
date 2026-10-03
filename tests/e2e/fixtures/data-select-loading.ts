import { createApp, h, nextTick, ref } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { setupGlobDirectives } from '@/directives'
import ArtTableMultipleSelect from '@/components/core/forms/art-data-select/table-multiple.vue'
import type { ArtDataSelectExpose } from '@/components/core/forms/art-data-select/types'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const selector = ref<ArtDataSelectExpose>()
const loading = ref(true)
const rows = ref<{ id: string; label: string }[]>([])
const result = ref('未确认')
const empty = new URLSearchParams(location.search).has('empty')
const app = createApp({
  render: () =>
    h('main', { class: 'p-4' }, [
      h('button', { onClick: () => selector.value?.open() }, '打开选择器'),
      h(
        'button',
        {
          onClick: async () => {
            rows.value = empty ? [] : [{ id: 'fixture-line', label: '测试可选明细' }]
            await nextTick()
            await selector.value?.reload()
            loading.value = false
          }
        },
        '完成数据加载'
      ),
      h(
        ArtTableMultipleSelect,
        {
          ref: selector,
          data: rows.value,
          loading: loading.value,
          columns: [{ prop: 'label', label: '明细名称' }],
          title: '选择测试明细',
          showPagination: false,
          emptyText: '暂无可选明细',
          emptyDescription: '当前业务没有可选择的明细。',
          onConfirm: (value: unknown) => {
            result.value = JSON.stringify(value)
          }
        },
        {
          empty: () =>
            h(
              'button',
              {
                onClick: () => {
                  result.value = 'maintenance-requested'
                }
              },
              '维护测试明细'
            )
        }
      ),
      h('output', { 'data-testid': 'selector-result' }, result.value)
    ])
})
app.use(store)
app.use(language)
app.use(
  createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: { template: '<div />' } }]
  })
)
setupGlobDirectives(app)
app.mount('#selector-loading-preview')
