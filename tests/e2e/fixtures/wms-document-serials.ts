import { createApp, defineComponent, h, ref } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import { setupGlobDirectives } from '@/directives'
import language from '@/locales'
import { store } from '@/store'
import { useTenantScopeStore } from '@/store/modules/tenant-scope'
import { useUserStore } from '@/store/modules/user'
import type { WmsPurchaseDocument, WmsPurchaseLine } from '@/api/wms-purchase.types'
import PurchaseDocumentDrawer from '@/components/business/wms-purchase-document-workspace/modules/wms-purchase-document-drawer.vue'
import type { WmsInitialSalesDocument } from '../../../modules/art-supabase-wms/src/api/initial-sales.types'
import InitialSalesDrawer from '../../../modules/art-supabase-wms/src/views/initialization/initial-sales/modules/initial-sales-drawer.vue'
import '@styles/core/tailwind.css'
import '@styles/index.scss'

const tenantId = '11111111-1111-4111-8111-111111111111'
const document: WmsInitialSalesDocument = {
  id: '22222222-2222-4222-8222-222222222222',
  tenantId,
  organizationId: '33333333-3333-4333-8333-333333333333',
  organization: { organizationName: '测试库存组织', organizationCode: 'TEST-ORG' },
  kind: 'initial_outbound',
  documentNo: 'TEST-SALES-001',
  documentTypeId: '44444444-4444-4444-8444-444444444444',
  businessTypeId: '55555555-5555-4555-8555-555555555555',
  businessDate: '2026-10-01',
  accountingDate: '2026-10-02',
  customerId: '66666666-6666-4666-8666-666666666666',
  salespersonId: null,
  salesDepartmentId: null,
  keeperId: null,
  status: 'draft',
  isInitialization: true,
  remark: null,
  createdAt: '2026-10-01T08:00:00Z',
  updatedAt: '2026-10-01T08:00:00Z',
  approvedAt: null,
  lines: [
    {
      lineNo: 1,
      returnType: null,
      materialId: '77777777-7777-4777-8777-777777777777',
      material: {
        id: '77777777-7777-4777-8777-777777777777',
        tenantId,
        code: 'TEST-MATERIAL',
        name: '测试序列号物料',
        description: null,
        specificationModel: 'TEST-MODEL',
        inventoryUnitId: null,
        baseUnitId: null,
        auxiliaryUnitId: null,
        auxiliaryUnit2Id: null,
        unitConversions: [],
        serialManagementEnabled: true
      },
      projectId: null,
      constructionNo: null,
      gift: false,
      inventoryUnitId: '88888888-8888-4888-8888-888888888888',
      quantity: 2,
      baseUnitId: null,
      baseQuantity: 2,
      unitPrice: 10,
      taxInclusiveUnitPrice: 11.3,
      taxRate: 13,
      discountMethod: 'none',
      unitDiscountRate: 0,
      discountAmount: 0,
      amount: 20,
      taxAmount: 2.6,
      totalAmount: 22.6,
      batchNo: null,
      warehouseId: null,
      binId: null,
      stockType: 'normal',
      ownerType: 'self',
      ownerId: null,
      stockStatus: 'available',
      keeperId: null,
      auxiliaryUnitId: null,
      auxiliaryQuantity: null,
      auxiliaryUnit2Id: null,
      auxiliaryQuantity2: null,
      productionDate: null,
      expiryDate: null,
      trackingNo: null,
      sourceDocument: null,
      sourceLineNo: null,
      remark: null,
      serialNos: []
    }
  ]
}

const purchaseLine: WmsPurchaseLine = {
  ...document.lines[0],
  sourceBatchId: null,
  receivedQuantity: 0,
  unreceivedQuantity: 2,
  returnedQuantity: 0,
  unreturnedQuantity: 0
}
const purchaseDocument: WmsPurchaseDocument = {
  ...document,
  kind: 'initial_inbound',
  supplierId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  customerId: null,
  purchaserId: null,
  purchaseDepartmentId: null,
  warehouseId: null,
  createTime: document.createdAt,
  updateTime: document.updatedAt,
  lines: [purchaseLine]
}

const Preview = defineComponent({
  setup() {
    const drawer = ref<InstanceType<typeof InitialSalesDrawer> | null>(null)
    const purchaseDrawer = ref<InstanceType<typeof PurchaseDocumentDrawer> | null>(null)
    return () =>
      h('main', [
        h(
          'button',
          {
            type: 'button',
            onClick: () => void drawer.value?.handleOpen({ mode: 'edit', document })
          },
          '打开销售单据'
        ),
        h(
          'button',
          {
            type: 'button',
            onClick: () =>
              void purchaseDrawer.value?.handleOpen({ mode: 'edit', document: purchaseDocument })
          },
          '打开采购单据'
        ),
        h(InitialSalesDrawer, {
          ref: drawer,
          kind: 'initial_outbound',
          importPermission: 'WmsInitialSalesOutbound:Import'
        }),
        h(PurchaseDocumentDrawer, {
          ref: purchaseDrawer,
          kind: 'initial_inbound',
          permissionPrefix: 'WmsInitialPurchaseInbound',
          importPermission: 'WmsInitialPurchaseInbound:Import'
        })
      ])
  }
})

const app = createApp(Preview)
app.use(store)
app.use(
  createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: { template: '<div />' } }]
  })
)
app.use(language)
setupGlobDirectives(app)

const userStore = useUserStore(store)
userStore.setUserInfo({
  userId: '99999999-9999-4999-8999-999999999999',
  tenantId,
  tenant: { tenantCode: 'visual-test', tenantName: '视觉验收业务租户' },
  platformSuper: true
})
useTenantScopeStore(store).selectedTenantId = tenantId
app.mount('#wms-document-serials-preview')
