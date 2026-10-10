import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { setupGlobDirectives } from '@/directives'
import language from '@/locales'
import { store } from '@/store'
import { useTenantScopeStore } from '@/store/modules/tenant-scope'
import { useUserStore } from '@/store/modules/user'
import { useSettingStore } from '@/store/modules/setting'
import { ElConfigProvider } from 'element-plus'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import PurchasePayableWorkspace from '@/components/business/purchase-payable-workspace/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'
const kind =
  new URLSearchParams(location.search).get('kind') === 'financial' ? 'financial' : 'estimated'
const app = createApp({
  render: () =>
    h('main', { class: 'art-page-view p-4', style: { height: '100vh' } }, [
      h(
        ElConfigProvider,
        { locale: zhCn },
        {
          default: () =>
            h(PurchasePayableWorkspace, {
              kind,
              viewPermission:
                kind === 'estimated'
                  ? 'FinanceEstimatedPayable:View'
                  : 'FinancePurchasePayable:View'
            })
        }
      )
    ])
})
const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/', component: {} }]
})
app.use(store)
app.use(router)
app.use(language)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'purchase-preview-user',
  tenantId: '11111111-1111-4111-8111-111111111111',
  platformSuper: true
})
useTenantScopeStore(store).selectedTenantId = '11111111-1111-4111-8111-111111111111'
const setting = useSettingStore(store)
setting.setCustomRadius(setting.customRadius)
await router.push('/')
await router.isReady()
app.mount('#purchase-payable-preview')
