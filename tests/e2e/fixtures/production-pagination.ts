import { createApp, h, ref } from 'vue'
import { store } from '@/store'
import {
  fetchWmsPurchaseDocumentIdPage,
  fetchWmsPurchasePage,
  fetchWmsPurchaseMaterials,
  fetchWmsPurchaseSourceBatches
} from '@/api/wms-purchase'
import { fetchDocumentTypeList } from '../../../modules/art-supabase-mdm/src/api/modules/document-type'
import { fetchBusinessTypeList } from '../../../modules/art-supabase-mdm/src/api/modules/business-type'
import { fetchStorageMaterialsPage } from '../../../modules/art-supabase-mdm/src/api/modules/inventory-storage'
import { fetchProductionPeople } from '../../../modules/art-supabase-mdm/src/api/modules/production'
import {
  fetchWmsMaterialOptions,
  fetchWmsProjectSectionPage,
  fetchWmsStockPage,
  fetchWmsSalesReturnAllocationPage,
  fetchWmsMovementPage,
  fetchWmsDirectTransferPage,
  fetchWmsSerialPage,
  fetchWmsTransferPage,
  fetchWmsTransferRequestPage,
  fetchWmsCountAdjustmentPage,
  fetchWmsIssueRequestPage,
  fetchWmsCountPlanPage,
  fetchWmsAdjustmentPage,
  fetchWmsAssemblyPage,
  fetchWmsProjectWorkOrderPage,
  fetchWmsProjectPackPage,
  fetchWmsProjectMaterialPage,
  fetchWmsProjectMovementPage
} from '../../../modules/art-supabase-wms/src/api/warehouse'
import {
  fetchOperationTemplates,
  fetchWorkCenters,
  fetchWorkCenterReferenceOptions,
  fetchAvailableMainCenters,
  fetchWorkstations,
  fetchPersonnelWorkCenterConfigs,
  fetchProductionReferences,
  fetchProcessRouteMaterialOptions,
  fetchProcessRoutes,
  fetchProcessSteps
} from '../../../modules/art-supabase-mdm/src/api/modules/workspaces'

const result = ref('未检查')
const valid = new URLSearchParams(location.search).get('valid') === 'true'
const app = createApp({
  render: () =>
    h('main', [
      h(
        'button',
        {
          onClick: async () => {
            let rejected = 0
            let accepted = 0
            for (const current of valid ? [2] : [0, -1, 1.5, Infinity, Number.MAX_SAFE_INTEGER]) {
              const query = { tenantId: 'tenant-a', keyword: '', current, size: 20 }
              const calls = [
                () => fetchOperationTemplates(query),
                () => fetchWorkCenters(query),
                () => fetchWorkCenterReferenceOptions('equipment', 'tenant-a', '', current, 20),
                () => fetchAvailableMainCenters('', current, 20),
                () => fetchWorkstations({ ...query, workCenterId: 'center' }),
                () => fetchPersonnelWorkCenterConfigs(query),
                () => fetchProductionReferences('material', 'tenant-a', '', current, 20),
                () => fetchProcessRouteMaterialOptions(query),
                () => fetchProcessRoutes(query),
                () => fetchProcessSteps(query),
                () => fetchDocumentTypeList(query),
                () => fetchBusinessTypeList(query),
                () => fetchStorageMaterialsPage('tenant-a', '', current, 20),
                () => fetchProductionPeople(query),
                () => fetchWmsMaterialOptions('tenant-a', '', current, 20),
                () => fetchWmsProjectSectionPage(query),
                () => fetchWmsStockPage(query),
                () => fetchWmsSalesReturnAllocationPage(query),
                () => fetchWmsMovementPage(query),
                () => fetchWmsDirectTransferPage(query),
                () => fetchWmsSerialPage(query),
                () => fetchWmsSerialPage({ ...query, projectId: 'project-a' }),
                () => fetchWmsTransferPage(query),
                () => fetchWmsTransferRequestPage(query),
                () => fetchWmsCountAdjustmentPage('gain', query),
                () => fetchWmsIssueRequestPage(query),
                () => fetchWmsCountPlanPage(query),
                () => fetchWmsAdjustmentPage(query),
                () => fetchWmsAssemblyPage(query),
                () => fetchWmsProjectWorkOrderPage({ ...query, projectId: 'project-a' }),
                () => fetchWmsProjectPackPage({ ...query, projectId: 'project-a' }),
                () => fetchWmsProjectMaterialPage({ ...query, projectId: 'project-a' }),
                () => fetchWmsProjectMovementPage({ ...query, projectId: 'project-a' }),
                () => fetchWmsPurchaseDocumentIdPage({ ...query, kind: 'purchase_inbound' }),
                () => fetchWmsPurchasePage({ ...query, kind: 'purchase_inbound' }),
                () => fetchWmsPurchaseMaterials(query),
                () =>
                  fetchWmsPurchaseSourceBatches({
                    ...query,
                    organizationId: 'organization-a',
                    materialId: 'material-a',
                    warehouseId: 'warehouse-a',
                    binId: null,
                    projectId: null,
                    constructionNo: null,
                    ownerType: 'company',
                    ownerId: null,
                    stockType: 'owned',
                    stockStatus: 'normal'
                  })
              ]
              for (const call of calls) {
                try {
                  await call()
                  accepted++
                } catch (error) {
                  if (error instanceof RangeError) rejected++
                }
              }
            }
            result.value = valid ? `${accepted} 个请求完成` : `${rejected} 个参数拒绝`
          }
        },
        '校验非法分页'
      ),
      h('output', { 'data-testid': 'result' }, result.value)
    ])
})
app.use(store)
app.mount('#production-pagination')
