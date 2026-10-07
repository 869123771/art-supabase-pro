import { createApp, h, onMounted, onUnmounted, shallowRef } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import language from '@/locales'
import { store } from '@/store'
import { useUserStore } from '@/store/modules/user'
import { setupGlobDirectives } from '@/directives'
import BusinessTypePage from '../../../modules/art-supabase-mdm/src/views/business-type/index.vue'
import GlobalReferenceFeedback from '@/components/business/master-data-delete-guard/global-reference-feedback.vue'
import { mittBus } from '@/utils/sys'
import type { DeleteReferenceContext } from '@/utils/supabase/delete-reference'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const router = createRouter({
  history: createMemoryHistory(),
  routes: [
    { path: '/wms/outbound-business/outbound-request', name: 'WmsIssueRequest', component: {} },
    { path: '/scm/purchase/order', name: 'ScmPurchaseOrder', component: {} },
    { path: '/:pathMatch(.*)*', name: 'MdmBusinessType', component: {} }
  ]
})
const app = createApp({
  setup() {
    const referenceContext = shallowRef<DeleteReferenceContext>()
    const showReferences = (context: DeleteReferenceContext) => {
      referenceContext.value = context
    }
    onMounted(() => mittBus.on('deleteReferenceBlocked', showReferences))
    onUnmounted(() => mittBus.off('deleteReferenceBlocked', showReferences))
    return () =>
      h('main', { class: 'art-page-view', style: { height: '100vh', overflow: 'auto' } }, [
        h(BusinessTypePage),
        referenceContext.value
          ? h(GlobalReferenceFeedback, { context: referenceContext.value })
          : null,
        h(
          'output',
          { 'data-testid': 'navigation-path', hidden: true },
          router.currentRoute.value.path
        ),
        h(
          'output',
          { 'data-testid': 'navigation', hidden: true },
          JSON.stringify(router.currentRoute.value.query)
        )
      ])
  }
})
app.use(store)
app.use(router)
app.use(language)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'permission-test-user',
  tenantId: 'permission-test-tenant',
  platformSuper: true
})
await router.isReady()
app.mount('#business-type-delete')
