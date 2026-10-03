import { createApp, h, ref } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { setupGlobDirectives } from '@/directives'
import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const model = ref({
  name: '初始名称',
  period: [new Date('2026-10-03T00:00:00Z'), new Date('2026-10-04T00:00:00Z')],
  attachment: new File(['测试附件内容'], 'test.txt', { type: 'text/plain' }),
  blank: '',
  count: 0,
  enabled: false
})
const output = ref('尚未提交')
const items: FormItem[] = [
  { key: 'name', label: '名称', type: 'input' },
  { key: 'period', label: '日期范围', type: 'daterange' }
]
const app = createApp({
  render: () =>
    h('main', { class: 'p-4' }, [
      h('h1', { class: 'text-xl' }, '表单控件值验收'),
      h(ArtForm, {
        modelValue: model.value,
        items,
        span: 24,
        submitText: '提交测试',
        resetText: '重置测试',
        sanitizeOutput: { removeEmptyString: true },
        onSubmit: async (value: Record<string, unknown>) => {
          output.value = JSON.stringify({
            name: value.name,
            period: Array.isArray(value.period)
              ? value.period.map((date: unknown) =>
                  date instanceof Date ? date.toISOString() : null
                )
              : null,
            attachment:
              value.attachment instanceof File
                ? { name: value.attachment.name, content: await value.attachment.text() }
                : null,
            hasBlank: Object.hasOwn(value, 'blank'),
            count: value.count,
            enabled: value.enabled
          })
        }
      }),
      h('output', { 'data-testid': 'form-output' }, output.value)
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
app.mount('#form-values-preview')
