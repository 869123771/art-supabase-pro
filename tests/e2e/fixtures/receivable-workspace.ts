import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { ElConfigProvider } from 'element-plus'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import { setupGlobDirectives } from '@/directives'
import language from '@/locales'
import { store } from '@/store'
import { useTenantScopeStore } from '@/store/modules/tenant-scope'
import { useUserStore } from '@/store/modules/user'
import { useSettingStore } from '@/store/modules/setting'
import { initializeTheme } from '@/hooks/core/useTheme'
import { SystemThemeEnum } from '@/enums/app-enum'
import ReceivableWorkspace from '@fms/views/accounts-receivable/modules/receivable-workspace.vue'
import ArSecondaryWorkspace from '@fms/views/accounts-receivable/modules/ar-secondary-workspace.vue'
import ArWriteoffWorkspace from '@fms/views/accounts-receivable/modules/ar-writeoff-workspace.vue'
import ReceivableReceiptConditions from '@mdm/views/financial-master/receipt-condition/index.vue'
import ArReport from '@fms/views/accounts-receivable/receivable-report/index.vue'
import ArPaymentRequest from '@fms/views/accounts-receivable/payment-request/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'
const params = new URLSearchParams(location.search)
const kind = params.get('kind') || 'estimate'
const app = createApp({
  render: () =>
    h(
      'main',
      { class: 'art-page-view p-4', style: { height: '100vh' } },
      h(
        ElConfigProvider,
        { locale: zhCn },
        {
          default: () =>
            kind === 'receipt' || kind === 'refund' || kind === 'revenue'
              ? h(ArSecondaryWorkspace, { kind })
              : kind === 'writeoff'
                ? h(ArWriteoffWorkspace)
                : kind === 'condition'
                  ? h(ReceivableReceiptConditions)
                  : kind === 'payment_request'
                    ? h(ArPaymentRequest)
                    : kind === 'report'
                      ? h(ArReport)
                      : h(ReceivableWorkspace, {
                          kind: kind === 'financial' ? 'financial' : 'estimate'
                        })
        }
      )
    )
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
  userId: 'ar-preview-user',
  tenantId: '11111111-1111-4111-8111-111111111111',
  platformSuper: true
})
useTenantScopeStore(store).selectedTenantId = '11111111-1111-4111-8111-111111111111'
const settings = useSettingStore(store)
const theme = params.get('theme') === 'dark' ? SystemThemeEnum.DARK : SystemThemeEnum.LIGHT
settings.setGlobalTheme(theme, theme)
settings.boxBorderMode = params.get('box') !== 'shadow-mode'
document.documentElement.dataset.boxMode = settings.boxBorderMode ? 'border-mode' : 'shadow-mode'
initializeTheme()
settings.setCustomRadius(settings.customRadius)
await router.push('/')
await router.isReady()
app.mount('#ar-preview')
