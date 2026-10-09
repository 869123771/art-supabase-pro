import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { store } from '@/store'
import language from '@/locales'
import { useUserStore } from '@/store/modules/user'
import Upload from '@/components/core/forms/art-upload-file/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const query = new URLSearchParams(location.search)
document.documentElement.classList.toggle('dark', query.get('theme') === 'dark')
document.documentElement.dataset.theme = query.get('theme') === 'dark' ? 'dark' : 'light'
document.documentElement.dataset.boxMode =
  query.get('box') === 'shadow-mode' ? 'shadow-mode' : 'border-mode'
const app = createApp({
  render: () =>
    h(
      'main',
      { class: 'p-4 grid gap-6' },
      ['normal', 'disabled', 'readonly'].map((mode) =>
        h('section', { 'data-mode': mode }, [
          h('h2', mode),
          h(Upload, {
            modelValue: [],
            style: 'width: 180px',
            resourceTenantId: 'test-tenant',
            disabled: mode === 'disabled',
            readonly: mode === 'readonly',
            showTip: false
          })
        ])
      )
    )
})
app.use(store)
app.use(language)
app.use(createRouter({ history: createMemoryHistory(), routes: [{ path: '/', component: {} }] }))
useUserStore(store).setUserInfo({
  userId: 'upload-source-test',
  tenantId: 'test-tenant',
  platformSuper: true
})
app.mount('#upload-source')
