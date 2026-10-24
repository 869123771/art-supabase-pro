import { createApp, h, ref } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { ElConfigProvider } from 'element-plus'
import zhCn from 'element-plus/es/locale/lang/zh-cn'
import { setupGlobDirectives } from '@/directives'
import language from '@/locales'
import { store } from '@/store'
import { useTenantScopeStore } from '@/store/modules/tenant-scope'
import { useUserStore } from '@/store/modules/user'
import { useMenuStore } from '@/store/modules/menu'
import { useSettingStore } from '@/store/modules/setting'
import { initializeTheme } from '@/hooks/core/useTheme'
import { SystemThemeEnum } from '@/enums/app-enum'
import ReceivableWorkspace from '@fms/views/accounts-receivable/modules/receivable-workspace.vue'
import ArSecondaryWorkspace from '@fms/views/accounts-receivable/modules/ar-secondary-workspace.vue'
import ArWriteoffWorkspace from '@fms/views/accounts-receivable/modules/ar-writeoff-workspace.vue'
import ReceivableReceiptConditions from '@mdm/views/financial-master/receipt-condition/index.vue'
import ArReport from '@fms/views/accounts-receivable/receivable-report/index.vue'
import ArPaymentRequest from '@fms/views/accounts-receivable/payment-request/index.vue'
import PayeeInformationDialog from '@fms/views/everyone-expense/payee-information/modules/payee-information-dialog.vue'
import TravelApplicationPage from '@fms/views/everyone-expense/travel-application/index.vue'
import LoanApplicationPage from '@fms/views/everyone-expense/loan-application/index.vue'
import RepaymentPage from '@fms/views/everyone-expense/repayment/index.vue'
import PayeePage from '@fms/views/everyone-expense/payee-information/index.vue'
import ReimbursementPage from '@fms/views/everyone-expense/expense-reimbursement/index.vue'
import ReimbursementDetail from '@fms/views/everyone-expense/expense-reimbursement/detail/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'
const params = new URLSearchParams(location.search)
const kind = params.get('kind') || 'estimate'
const payeeDialog = ref<InstanceType<typeof PayeeInformationDialog>>()
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
            kind === 'expense_reimbursement_detail'
              ? h(ReimbursementDetail)
              : kind === 'expense_payee'
                ? h(PayeePage)
                : kind === 'expense_reimbursement'
                  ? h(ReimbursementPage)
                  : kind === 'expense_travel'
                    ? h(TravelApplicationPage)
                    : kind === 'expense_loan'
                      ? h(LoanApplicationPage)
                      : kind === 'expense_repayment'
                        ? h(RepaymentPage)
                        : kind === 'payee'
                          ? h('div', [
                              h(
                                'button',
                                { onClick: () => payeeDialog.value?.handleOpen() },
                                '新增收款信息'
                              ),
                              h(PayeeInformationDialog, { ref: payeeDialog })
                            ])
                          : kind === 'receipt' || kind === 'refund' || kind === 'revenue'
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
  routes: [
    { path: '/', component: {} },
    { path: '/reimbursement/:id', component: {} }
  ]
})
app.use(store)
app.use(router)
app.use(language)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'ar-preview-user',
  tenantId: '11111111-1111-4111-8111-111111111111',
  platformSuper: !params.has('permissions')
})
if (params.has('permissions'))
  useMenuStore(store).setButtonList(
    (params.get('permissions') || '')
      .split(',')
      .filter(Boolean)
      .map((name) => ({
        name,
        path: '',
        type: 'button',
        meta: { title: '财务验收权限' }
      }))
  )
useTenantScopeStore(store).selectedTenantId = '11111111-1111-4111-8111-111111111111'
const settings = useSettingStore(store)
const theme = params.get('theme') === 'dark' ? SystemThemeEnum.DARK : SystemThemeEnum.LIGHT
settings.setGlobalTheme(theme, theme)
settings.boxBorderMode = params.get('box') !== 'shadow-mode'
document.documentElement.dataset.boxMode = settings.boxBorderMode ? 'border-mode' : 'shadow-mode'
initializeTheme()
settings.setCustomRadius(settings.customRadius)
await router.push(
  kind === 'expense_reimbursement_detail'
    ? `/reimbursement/${params.get('recordId') || 'detail-1'}`
    : { path: '/', query: params.has('recordId') ? { recordId: params.get('recordId') } : {} }
)
await router.isReady()
app.mount('#ar-preview')
