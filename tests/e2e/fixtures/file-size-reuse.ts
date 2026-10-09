import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { useUserStore } from '@/store/modules/user'
import { setupGlobDirectives } from '@/directives'
import ArtUploadFile from '@/components/core/forms/art-upload-file/index.vue'
import { formatSize } from '@/utils/file/format-size'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const app = createApp({
  render: () =>
    h('main', { class: 'grid min-w-0 gap-4 p-4' }, [
      h('h1', '附件大小与上传限制'),
      h('dl', { class: 'grid grid-cols-2 gap-2' }, [
        h('dt', '空文件'),
        h('dd', formatSize(0)),
        h('dt', '未知大小'),
        h('dd', formatSize(null, { emptyText: '大小未知' })),
        h('dt', '大文件'),
        h('dd', formatSize(1024 ** 3, { precision: 1 }))
      ]),
      h(ArtUploadFile, { modelValue: [], showResourcePicker: false, fileSize: 20 * 1024 ** 2 }),
      h(ArtUploadFile, { modelValue: [], showResourcePicker: false, fileSize: 1024 ** 3 })
    ])
})
app.use(store)
app.use(language)
const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/:pathMatch(.*)*', component: {} }]
})
app.use(router)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'file-size-test',
  tenantId: 'test-tenant',
  platformSuper: false
})
await router.isReady()
app.mount('#app')
