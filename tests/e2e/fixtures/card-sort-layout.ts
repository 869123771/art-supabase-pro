import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { store } from '@/store'
import language from '@/locales'
import { useUserStore } from '@/store/modules/user'
import { setupGlobDirectives } from '@/directives'
import ComponentType from '@mdm/views/engineering/component-type/index.vue'
import AccountingReadinessPanel from '@fms/views/workbench/modules/accounting-readiness-panel.vue'
import ArtSectionCard from '@/components/core/surfaces/art-section-card/index.vue'
import ArtEntitySummary from '@/components/core/surfaces/art-entity-summary/index.vue'
import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const params = new URLSearchParams(location.search)
document.documentElement.classList.toggle('dark', params.get('theme') === 'dark')
document.documentElement.dataset.boxMode = params.get('box') ?? 'border-mode'
const app = createApp({
  render: () =>
    h(
      'main',
      { class: 'p-4', style: { height: '100dvh' } },
      params.has('generic')
        ? [240, 320, 420]
            .map((width) =>
              h(
                ArtSectionCard,
                {
                  title: '公共卡片头部',
                  subtitle: '较长说明文字应适应容器宽度，保持操作按钮靠右。',
                  showScrollbar: false,
                  style: { width: `${width}px`, maxWidth: '100%', marginBottom: '16px' }
                },
                {
                  default: () => '内容区域',
                  actions: () =>
                    ['展开', '新增', '刷新'].map((label) =>
                      h(ArtIconButton, { label, icon: 'ri:refresh-line' })
                    )
                }
              )
            )
            .concat([
              h(
                ArtEntitySummary,
                {
                  title: '公共详情摘要',
                  description: '详情操作在窄屏保持靠右。',
                  icon: 'ri:folder-line',
                  style: { width: '320px', maxWidth: '100%', marginBottom: '16px' }
                },
                {
                  aside: () =>
                    ['查看', '编辑', '刷新'].map((label) =>
                      h(ArtIconButton, { label, icon: 'ri:refresh-line' })
                    )
                }
              ),
              h(AccountingReadinessPanel, {
                compact: true,
                style: { width: '320px', maxWidth: '100%' }
              })
            ])
        : h(ComponentType)
    )
})
app.use(store)
app.use(language)
app.use(
  createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/:pathMatch(.*)*', component: {} }]
  })
)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'card-sort-test',
  tenantId: 'test-tenant',
  platformSuper: true
})
app.mount('#card-sort-layout')
