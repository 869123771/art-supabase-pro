import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter, RouterView } from 'vue-router'
import { setupGlobDirectives } from '@/directives'
import language from '@/locales'
import { store } from '@/store'
import { useTenantScopeStore } from '@/store/modules/tenant-scope'
import { useUserStore } from '@/store/modules/user'
import { useSettingStore } from '@/store/modules/setting'
import { initializeTheme } from '@/hooks/core/useTheme'
import { SystemThemeEnum } from '@/enums/app-enum'
import { ElConfigProvider } from 'element-plus'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import EstimatedPayablePage from '@fms/views/accounts-payable/estimated-payable/index.vue'
import FinancialPayablePage from '@fms/views/accounts-payable/purchase-payable/index.vue'
import PayablePaymentTerms from '@mdm/views/financial-master/payment-term/index.vue'
import { financePaths } from '@/router/business-paths'
import '@styles/core/tailwind.css'
import '@styles/index.scss'
const parameters = new URLSearchParams(location.search)
const pages = [
  {
    kind: 'purchase_contract',
    component: () => import('@scm/views/purchase-management/purchase-contract/index.vue')
  },
  {
    kind: 'purchase_order',
    component: () => import('@scm/views/purchase-management/purchase-order/index.vue')
  },
  { kind: 'estimated', component: EstimatedPayablePage },
  { kind: 'financial', component: FinancialPayablePage },
  { kind: 'payment-term', component: PayablePaymentTerms },
  {
    kind: 'application',
    component: () => import('@fms/views/accounts-payable/payment-application/index.vue')
  },
  { kind: 'payment', component: () => import('@fms/views/accounts-payable/payment/index.vue') },
  {
    kind: 'purpose',
    component: () => import('@mdm/views/financial-master/payment-purpose/index.vue')
  },
  {
    kind: 'method',
    component: () => import('@mdm/views/financial-master/settlement-method/index.vue')
  },
  { kind: 'writeoff', component: () => import('@fms/views/accounts-payable/writeoff/index.vue') }
]
const app = createApp({
  render: () =>
    h('main', { class: 'art-page-view p-4', style: { height: '100vh' } }, [
      h(
        ElConfigProvider,
        { locale: zhCn },
        {
          default: () => h(RouterView)
        }
      )
    ])
})
const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    {
      path: '/',
      component:
        pages.find((page) => page.kind === parameters.get('kind'))?.component ||
        EstimatedPayablePage
    },
    {
      path: financePaths.payableApplication,
      component: () => import('@fms/views/accounts-payable/payment-application/index.vue')
    },
    {
      path: financePaths.payablePayment,
      component: () => import('@fms/views/accounts-payable/payment/index.vue')
    }
  ]
})
app.use(store)
app.use(language)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'purchase-preview-user',
  tenantId: '11111111-1111-4111-8111-111111111111',
  platformSuper: true
})
useTenantScopeStore(store).selectedTenantId =
  parameters.get('scope') === 'all' ? null : '11111111-1111-4111-8111-111111111111'
const setting = useSettingStore(store)
const theme = parameters.get('theme') === 'dark' ? SystemThemeEnum.DARK : SystemThemeEnum.LIGHT
setting.setGlobalTheme(theme, theme)
setting.boxBorderMode = parameters.get('box') !== 'shadow-mode'
document.documentElement.dataset.boxMode = setting.boxBorderMode ? 'border-mode' : 'shadow-mode'
initializeTheme()
setting.setCustomRadius(setting.customRadius)
await router.push({
  path: '/',
  query: parameters.get('recordId') ? { recordId: parameters.get('recordId') } : {}
})
await router.isReady()
app.use(router)
app.mount('#purchase-payable-preview')
