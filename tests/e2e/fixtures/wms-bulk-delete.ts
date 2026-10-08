import { createApp, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { store } from '@/store'
import language from '@/locales'
import { useUserStore } from '@/store/modules/user'
import { useMenuStore } from '@/store/modules/menu'
import { setupGlobDirectives } from '@/directives'
import type { AppRouteRecord } from '@/types/router'
import Stock from '../../../modules/art-supabase-wms/src/views/initialization/initial-stock/index.vue'
import Sales from '../../../modules/art-supabase-wms/src/views/initialization/initial-sales/workspace.vue'
import Purchase from '../../../modules/art-supabase-wms/src/views/initialization/initial-purchase-inbound/index.vue'
import PurchaseReturn from '../../../modules/art-supabase-wms/src/views/initialization/initial-purchase-return/index.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const params = new URLSearchParams(location.search)
const kind = params.get('kind') || 'stock'
const names: Record<string, string> = {
  stock: 'WmsInitialStock',
  sales: 'WmsInitialSalesOutbound',
  'sales-return': 'WmsInitialSalesReturn',
  purchase: 'WmsInitialPurchaseInbound',
  'purchase-return': 'WmsInitialPurchaseReturn'
}
const name = names[kind] || names.stock
document.documentElement.style.setProperty('--art-full-height', 'calc(100vh - 32px)')
const app = createApp({
  render: () =>
    h(
      'main',
      { class: 'art-page-view', style: { padding: '16px' } },
      kind === 'sales' || kind === 'sales-return'
        ? h(Sales, { kind: kind === 'sales' ? 'initial_outbound' : 'initial_return' })
        : h(kind === 'purchase' ? Purchase : kind === 'purchase-return' ? PurchaseReturn : Stock)
    )
})
app.use(store)
app.use(language)
app.use(
  createRouter({ history: createMemoryHistory(), routes: [{ path: '/', name, component: {} }] })
)
setupGlobDirectives(app)
useUserStore(store).setUserInfo({
  userId: 'bulk-delete-test',
  tenantId: '11111111-1111-4111-8111-111111111111',
  platformSuper: false
})
useMenuStore(store).setButtonList(
  ['View', ...(params.get('authority') === 'readonly' ? [] : ['Delete'])].map<AppRouteRecord>(
    (action) => ({
      name: `${name}:${action}`,
      path: '',
      component: '',
      type: 'button',
      meta: { title: action }
    })
  )
)
app.mount('#wms-bulk-delete')
