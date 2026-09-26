<template>
  <ArtDrawer ref="drawerRef" size="88%" :show-footer="mode !== 'view'">
    <div class="initialization-document-stack min-w-0">
      <ArtEntitySummary
        :icon="isReturn ? 'ri:inbox-unarchive-line' : 'ri:inbox-archive-line'"
        :eyebrow="isInitial ? 'OPENING PURCHASE DOCUMENT' : 'PURCHASE INVENTORY DOCUMENT'"
        :title="form.documentNo || `${mode === 'copy' ? '复制' : '新增'}${title}`"
        description="按单据表头、物料明细、税价和仓储信息依次填写。编号在保存时生成。"
      >
        <template #aside
          ><ElTag
            :type="
              form.status === 'approved'
                ? 'success'
                : form.status === 'submitted'
                  ? 'warning'
                  : 'info'
            "
            >{{ statusLabel }}</ElTag
          ></template
        >
      </ArtEntitySummary>
      <ElAlert v-if="optionError" type="warning" :closable="false" show-icon>
        基础资料加载失败，请重试后再保存。<ElButton link type="primary" @click="loadOptions"
          >重新加载</ElButton
        >
      </ElAlert>
      <ElAlert v-else type="info" :closable="false" show-icon>
        {{
          isInitial ? '业务日期不得晚于库存组织启用日期。' : ''
        }}物料价格、税额、折扣与辅助数量由系统核算；退货以负数入账。
      </ElAlert>
      <ElAlert v-if="importIntent" type="success" :closable="false" show-icon>
        先选择库存组织及供应商，再在“物料明细”中点击“导入明细”；导入后请核对仓储和价格信息。
      </ElAlert>
      <ArtSectionCard
        title="单据表头"
        subtitle="供应商、业务日期和库存组织是必填信息；记账日期由系统记录。"
      >
        <ArtDescriptions v-if="mode === 'view'" :data="viewData" :items="viewItems" :columns="3" />
        <ArtForm
          v-else
          ref="formRef"
          v-model="form"
          :items="headerItems"
          :rules="headerRules"
          :span="8"
          :gutter="18"
          label-position="top"
          :show-reset="false"
          :show-submit="false"
        >
          <template #supplierId>
            <ArtTableSingleSelect
              :model-value="form.supplierId || undefined"
              :selected-data="selectedSupplier"
              :data="suppliers"
              :columns="partyColumns"
              row-key="id"
              label-key="name"
              description-key="code"
              title="选择供应商"
              placeholder="从采购主数据选择"
              :disabled="!form.tenantId"
              @update:model-value="form.supplierId = String($event || '')"
              @update:selected-data="onSupplierSelected"
            />
          </template>
          <template #purchaserId>
            <ArtEmployeeSelect
              :model-value="form.purchaserId || undefined"
              :selected-data="selectedPurchaser"
              :tenant-id="form.tenantId || undefined"
              title="选择采购员"
              :disabled="!form.tenantId"
              @update:model-value="form.purchaserId = $event || null"
              @update:selected-data="onPurchaserSelected"
            />
          </template>
          <template #keeperId>
            <ArtEmployeeSelect
              :model-value="form.keeperId || undefined"
              :selected-data="selectedKeeper"
              :tenant-id="form.tenantId || undefined"
              title="选择仓管员"
              :disabled="!form.tenantId"
              @update:model-value="form.keeperId = $event || null"
              @update:selected-data="selectedKeeper = $event"
            />
          </template>
        </ArtForm>
      </ArtSectionCard>
      <ArtSectionCard
        title="物料明细"
        :subtitle="`共 ${lines.length} 行 · 数量 ${quantityTotal.toFixed(4)} · 价税合计 ${totalAmount.toFixed(2)} 元`"
        :empty="lines.length === 0"
        empty-title="尚未选择物料"
        empty-description="先选择库存组织，再从物料编码中添加明细。"
      >
        <template #actions>
          <div
            v-if="mode !== 'view' && form.tenantId"
            class="flex flex-nowrap items-center justify-end gap-2 whitespace-nowrap"
          >
            <ArtTableMultipleSelect
              v-model="materialPickerIds"
              v-model:selected-data="materialPickerRows"
              class="w-auto! shrink-0"
              title="选择采购物料"
              subtitle="可按物料编码、名称和描述检索并多选。"
              search-placeholder="搜索物料编码或描述"
              row-key="id"
              label-key="name"
              description-key="code"
              :columns="materialColumns"
              :api-fn="materialApi"
              @confirm="addMaterials"
            >
              <template #trigger="{ open }"
                ><ElButton type="primary" @click="open"
                  ><ArtSvgIcon icon="ri:add-line" />添加物料</ElButton
                ></template
              >
            </ArtTableMultipleSelect>
            <span
              v-auth="importPermission"
              class="shrink-0"
              :title="form.organizationId ? '' : '请先选择库存组织'"
            >
              <ArtExcelImport
                accept=".xlsx,.xls,.csv"
                :disabled="!form.organizationId"
                :button-props="{ type: 'success', plain: true }"
                icon="ri:upload-2-line"
                @import-success="importLines"
                @import-error="onImportError"
                >导入明细</ArtExcelImport
              >
            </span>
          </div>
        </template>
        <div v-if="lines.length" class="overflow-x-auto">
          <ArtTable
            :data="lines"
            :columns="lineColumns"
            :pagination="false"
            row-key="lineNo"
            table-layout="fixed"
          >
            <template #material="{ row }">
              <strong class="block truncate text-sm">{{ row.material?.name || '物料' }}</strong>
              <small class="text-[var(--el-text-color-secondary)]">{{
                row.material?.code || row.materialId
              }}</small>
            </template>
            <template #projectId="{ row }">{{ projectName(row.projectId) }}</template>
            <template #quantity="{ row }">
              <strong :class="isReturn ? 'purchase-return-quantity' : 'tabular-nums'">{{
                displayQuantity(Number(row.quantity)).toFixed(4)
              }}</strong>
            </template>
            <template #inventoryUnitId="{ row }">{{ unitName(row.inventoryUnitId) }}</template>
            <template #taxInclusiveUnitPrice="{ row }">{{
              Number(row.taxInclusiveUnitPrice).toFixed(4)
            }}</template>
            <template #taxRate="{ row }">{{ row.taxRate }}%</template>
            <template #totalAmount="{ row }">{{ lineFinancial(row).total.toFixed(2) }}</template>
            <template #gift="{ row }">{{ row.gift ? '✓' : '—' }}</template>
            <template #operation="{ row }">
              <ArtButtonTable
                :type="mode === 'view' ? 'view' : 'edit'"
                :icon="mode === 'view' ? 'ri:eye-line' : 'ri:edit-line'"
                :label="mode === 'view' ? '查看' : '编辑'"
                :permission="mode === 'view' ? viewPermission : lineEditPermission"
                @click="openLine(lineIndex(row))"
              />
              <ArtButtonMore
                v-if="mode !== 'view'"
                :list="lineMoreActions"
                trigger="click"
                @click="(item) => onLineMoreAction(item, row)"
              />
            </template>
          </ArtTable>
        </div>
      </ArtSectionCard>
    </div>
  </ArtDrawer>

  <ArtDialog ref="lineDialogRef" size="lg" :show-footer="mode !== 'view'">
    <div v-if="editLine" class="min-w-0 space-y-5">
      <ArtEntitySummary
        icon="ri:package-2-line"
        eyebrow="MATERIAL LINE"
        :title="`${editLine.material?.name || '物料'} · 第 ${editLine.lineNo} 行`"
        :description="`${editLine.material?.code || ''} · ${editLine.material?.specificationModel || '无规格型号'}`"
      />
      <template v-if="mode === 'view'">
        <ArtSectionCard title="物料与数量" subtitle="物料、项目与数量">
          <ArtDescriptions :data="editLine" :items="lineMaterialViewItems" :columns="3" />
        </ArtSectionCard>
        <ArtSectionCard title="价格与税额" subtitle="单价、折扣和税额由系统复算">
          <ArtDescriptions :data="editLine" :items="linePriceViewItems" :columns="3" />
        </ArtSectionCard>
        <ArtSectionCard title="仓储与货权" subtitle="仓库、库存状态和货主">
          <ArtDescriptions :data="editLine" :items="lineStorageViewItems" :columns="3" />
        </ArtSectionCard>
        <ArtSectionCard title="追溯与来源" subtitle="批次、来源和序列号">
          <ArtDescriptions :data="editLine" :items="lineTraceViewItems" :columns="3" />
        </ArtSectionCard>
      </template>
      <template v-else>
        <ArtSectionCard title="物料与数量" subtitle="数量为正数填写；退货列表与入账结果显示负数。">
          <ArtForm
            v-model="editLine"
            :items="lineMaterialFormItems"
            :rules="lineMaterialRules"
            :span="6"
            :gutter="16"
            label-position="top"
            :show-reset="false"
            :show-submit="false"
          >
            <template #projectId>
              <ArtTableSingleSelect
                :model-value="editLine.projectId || undefined"
                :selected-data="selectedProject"
                :data="projects"
                :columns="partyColumns"
                row-key="id"
                label-key="name"
                description-key="code"
                title="选择采购项目"
                placeholder="选择项目"
                @update:model-value="onLineProjectChange(String($event || '') || null)"
                @update:selected-data="selectedProject = $event"
              />
            </template>
          </ArtForm>
        </ArtSectionCard>
        <ArtSectionCard
          title="价格与税额"
          subtitle="填写单价或含税单价会联动另一项；金额与税额由系统复算。"
        >
          <ArtForm
            v-model="editLine"
            :items="linePriceFormItems"
            :rules="linePriceRules"
            :span="6"
            :gutter="16"
            label-position="top"
            :show-reset="false"
            :show-submit="false"
          />
        </ArtSectionCard>
        <ArtSectionCard
          title="仓储与货权"
          subtitle="仓位根据仓库过滤；辅助单位和数量从物料单位换算获得。"
        >
          <ArtForm
            v-model="editLine"
            :items="lineStorageFormItems"
            :rules="lineStorageRules"
            :span="6"
            :gutter="16"
            label-position="top"
            :show-reset="false"
            :show-submit="false"
          >
            <template #sourceBatchId>
              <ArtTableSingleSelect
                :model-value="editLine.sourceBatchId || undefined"
                :selected-data="selectedSourceBatch"
                :api-fn="sourceBatchApi"
                :columns="sourceBatchColumns"
                :disabled="!editLine.warehouseId || !editLine.materialId"
                :show-pagination="true"
                clearable
                row-key="id"
                label-key="batchNo"
                title="选择退料来源批次"
                subtitle="仅显示与当前组织、仓位、项目施工号及货权一致的可退库存。"
                search-placeholder="搜索批号"
                :placeholder="editLine.warehouseId ? '选择来源批次' : '请先选择仓库'"
                @update:model-value="editLine.sourceBatchId = String($event || '') || null"
                @update:selected-data="onSourceBatchSelected"
              />
            </template>
            <template #ownerId>
              <ArtTableSingleSelect
                v-if="editLine.ownerType !== 'self'"
                :model-value="editLine.ownerId || undefined"
                :selected-data="selectedOwner"
                :data="editLine.ownerType === 'supplier' ? suppliers : customers"
                :columns="partyColumns"
                row-key="id"
                label-key="name"
                description-key="code"
                title="选择货主"
                @update:model-value="onLineOwnerChange(String($event || '') || null)"
                @update:selected-data="selectedOwner = $event"
              />
              <span v-else>自有</span>
            </template>
            <template #keeperId>
              <ArtEmployeeSelect
                :model-value="editLine.keeperId || undefined"
                :selected-data="selectedLineKeeper"
                :tenant-id="form.tenantId || undefined"
                title="选择行仓管员"
                @update:model-value="editLine.keeperId = $event || null"
                @update:selected-data="selectedLineKeeper = $event"
              />
            </template>
          </ArtForm>
        </ArtSectionCard>
        <ArtSectionCard
          title="追溯与来源"
          subtitle="序列号物料须逐件录入。支持文本或 CSV 导入，一行一个序列号。"
        >
          <ArtForm
            v-model="editLine"
            :items="lineTraceFormItems"
            :span="6"
            :gutter="16"
            label-position="top"
            :show-reset="false"
            :show-submit="false"
          />
          <div
            v-if="editLine.material?.serialManagementEnabled"
            class="mt-2 rounded-xl border border-[var(--el-border-color-light)] p-4"
          >
            <div class="mb-3 flex flex-wrap items-center gap-3">
              <strong class="text-sm">序列号</strong>
              <ElButton link type="primary" @click="serialEntryVisible = true">录入序列号</ElButton>
              <ElButton link type="primary" @click="serialInputRef?.click()">导入序列号</ElButton>
              <ElButton link type="primary" @click="serialViewVisible = true">查看序列号</ElButton>
              <span class="text-xs text-[var(--el-text-color-secondary)]"
                >已录入 {{ serialList.length }} 个</span
              >
            </div>
            <input
              ref="serialInputRef"
              class="hidden"
              type="file"
              accept=".txt,.csv"
              @change="importSerials"
            />
          </div>
        </ArtSectionCard>
      </template>
    </div>
  </ArtDialog>

  <ArtDialog ref="serialEntryDialogRef" size="sm" :show-footer="mode !== 'view'">
    <ArtForm
      v-model="serialEntryForm"
      :items="serialEntryItems"
      :show-reset="false"
      :show-submit="false"
      label-position="top"
    />
  </ArtDialog>
  <ArtDialog ref="serialViewDialogRef" size="sm" :show-footer="false"
    ><div
      class="max-h-96 overflow-auto rounded-xl bg-[var(--el-fill-color-light)] p-4 font-mono text-sm whitespace-pre-wrap"
      >{{ serialList.join('\n') || '暂无序列号' }}</div
    ></ArtDialog
  >
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import { cloneDeep } from 'lodash-es'
  import { ElMessage } from 'element-plus'
  import { normalizeNullableText } from '@/utils/form/normalize'
  import { useUserStore } from '@/store/modules/user'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtEntitySummary from '@/components/core/surfaces/art-entity-summary/index.vue'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSectionCard from '@/components/core/surfaces/art-section-card/index.vue'
  import ArtEmployeeSelect from '@/components/business/art-employee-select/index.vue'
  import ArtTableMultipleSelect from '@/components/core/forms/art-data-select/table-multiple.vue'
  import ArtTableSingleSelect from '@/components/core/forms/art-data-select/table-single.vue'
  import type {
    DataSelectColumn,
    DataSelectRecord,
    DataSelectFetchParams
  } from '@/components/core/forms/art-data-select/types'
  import type { EmployeeIntegrationItem } from '@/api/integration/employees'
  import type { ColumnOption } from '@/types'
  import {
    fetchWmsPurchaseBins,
    fetchWmsPurchaseMaterials,
    fetchWmsPurchaseOptions,
    fetchWmsPurchaseSourceBatches,
    fetchWmsPurchaseDocument,
    fetchWmsPurchaseOrganizations,
    fetchWmsPurchaseUnits,
    fetchWmsPurchaseWarehouses,
    saveWmsPurchaseDocument,
    type WmsPurchaseBin,
    type WmsPurchaseMaterial,
    type WmsPurchaseDocument,
    type WmsPurchaseKind,
    type WmsPurchaseLine,
    type WmsPurchaseOption,
    type WmsPurchaseOrganization,
    type WmsPurchaseUnit,
    type WmsPurchaseWarehouse
  } from '@/api/wms-purchase'

  type OpenMode = 'create' | 'copy' | 'edit' | 'view'
  interface OpenData {
    mode: OpenMode
    document?: WmsPurchaseDocument
    documentId?: string
    importIntent?: boolean
  }
  const props = defineProps<{ kind: WmsPurchaseKind; importPermission: string }>()
  const emit = defineEmits<{ success: [] }>()
  const userStore = useUserStore()
  const drawerRef = ref<ArtDrawerExpose<OpenData>>()
  const lineDialogRef = ref<ArtDialogExpose>()
  const serialEntryDialogRef = ref<ArtDialogExpose>()
  const serialViewDialogRef = ref<ArtDialogExpose>()
  const formRef = ref<InstanceType<typeof ArtForm>>()
  const serialInputRef = ref<HTMLInputElement>()
  const mode = ref<OpenMode>('create')
  const importIntent = ref(false)
  const currentDocument = shallowRef<WmsPurchaseDocument | null>(null)
  const optionError = ref(false)
  const organizations = ref<WmsPurchaseOrganization[]>([])
  const warehouses = ref<WmsPurchaseWarehouse[]>([])
  const units = ref<WmsPurchaseUnit[]>([])
  const documentTypes = ref<WmsPurchaseOption[]>([])
  const businessTypes = ref<WmsPurchaseOption[]>([])
  const customers = ref<WmsPurchaseOption[]>([])
  const suppliers = ref<WmsPurchaseOption[]>([])
  const projects = ref<WmsPurchaseOption[]>([])
  const bins = ref<WmsPurchaseBin[]>([])
  const lines = ref<WmsPurchaseLine[]>([])
  const permissionPrefix = computed(
    () =>
      ({
        initial_inbound: 'WmsInitialPurchaseInbound',
        initial_return: 'WmsInitialPurchaseReturn',
        purchase_inbound: 'ScmPurchaseInbound',
        purchase_return: 'ScmPurchaseReturnRequest'
      })[props.kind]
  )
  const viewPermission = computed(() => `${permissionPrefix.value}:View`)
  const lineEditPermission = computed(
    () =>
      `${permissionPrefix.value}:${mode.value === 'create' ? 'Add' : mode.value === 'copy' ? 'Copy' : 'Edit'}`
  )
  const lineMoreActions = computed<ButtonMoreItem[]>(() => [
    {
      key: 'copy-line',
      label: '复制明细',
      icon: 'ri:file-copy-line',
      auth: lineEditPermission.value
    },
    {
      key: 'delete-line',
      label: '删除明细',
      icon: 'ri:delete-bin-line',
      color: 'var(--el-color-danger)',
      auth: lineEditPermission.value
    }
  ])
  const lineColumns = computed<ColumnOption<WmsPurchaseLine>[]>(() => [
    { prop: 'lineNo', label: '行号', width: 68 },
    { prop: 'material', label: '物料', minWidth: 230, useSlot: true },
    { prop: 'projectId', label: '项目名称', minWidth: 150, useSlot: true },
    { prop: 'quantity', label: '数量', width: 122, align: 'right', useSlot: true },
    { prop: 'inventoryUnitId', label: '库存单位', width: 110, useSlot: true },
    { prop: 'taxInclusiveUnitPrice', label: '含税单价', width: 118, align: 'right', useSlot: true },
    { prop: 'taxRate', label: '税率', width: 80, align: 'right', useSlot: true },
    { prop: 'totalAmount', label: '价税合计', width: 124, align: 'right', useSlot: true },
    { prop: 'gift', label: '赠品', width: 68, align: 'center', useSlot: true },
    { prop: 'operation', label: '操作', width: 112, fixed: 'right', useSlot: true }
  ])
  const materialPickerIds = ref<string[]>([])
  const materialPickerRows = ref<DataSelectRecord[]>([])
  const selectedSupplier = ref<DataSelectRecord[]>([])
  const selectedPurchaser = ref<EmployeeIntegrationItem[]>([])
  const selectedKeeper = ref<EmployeeIntegrationItem[]>([])
  const selectedLineKeeper = ref<EmployeeIntegrationItem[]>([])
  const selectedProject = ref<DataSelectRecord[]>([])
  const selectedOwner = ref<DataSelectRecord[]>([])
  const selectedSourceBatch = ref<DataSelectRecord[]>([])
  const editLine = ref<WmsPurchaseLine>()
  const editingIndex = ref(-1)
  const serialText = ref('')
  const serialEntryForm = reactive({ serialText: '' })
  const serialEntryItems: FormItem[] = [
    {
      key: 'serialText',
      label: '序列号',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 10, placeholder: '每行一个序列号' }
    }
  ]
  const form = reactive({
    id: '',
    tenantId: '',
    organizationId: '',
    documentNo: '',
    documentTypeId: '',
    businessTypeId: '',
    businessDate: '',
    accountingDate: dayjs().format('YYYY-MM-DD'),
    supplierId: '',
    supplierCode: '',
    purchaserId: null as string | null,
    purchaseDepartmentId: null as string | null,
    keeperId: null as string | null,
    warehouseId: null as string | null,
    status: 'draft' as WmsPurchaseDocument['status'],
    isInitialization: true,
    remark: ''
  })
  void userStore.ensureDictLoaded('wmsInitialStockType')
  void userStore.ensureDictLoaded('wmsInitialStockCondition')
  void userStore.ensureDictLoaded('mdmBusinessOwnerType')
  const stockTypes = computed(() => userStore.getDictMap['wmsInitialStockType'] ?? [])
  const stockStatuses = computed(() => userStore.getDictMap['wmsInitialStockCondition'] ?? [])
  const ownerTypes = computed(() => userStore.getDictMap['mdmBusinessOwnerType'] ?? [])
  const taxRates = [0, 1, 3, 6, 9, 13]
  const isReturn = computed(() => ['initial_return', 'purchase_return'].includes(props.kind))
  const isInitial = computed(() => props.kind.startsWith('initial_'))
  const title = computed(
    () =>
      ({
        initial_inbound: '期初采购入库单',
        initial_return: '期初采购退料单',
        purchase_inbound: '采购入库单',
        purchase_return: '采购退货单'
      })[props.kind]
  )
  const statusLabel = computed(
    () => ({ draft: '暂存', submitted: '已提交', approved: '已审核' })[form.status]
  )
  const typeCode = computed(
    () =>
      ({
        initial_inbound: 'WMS_INITIAL_PURCHASE_INBOUND',
        initial_return: 'WMS_INITIAL_PURCHASE_RETURN',
        purchase_inbound: 'WMS_PURCHASE_INBOUND',
        purchase_return: 'WMS_PURCHASE_RETURN'
      })[props.kind]
  )
  const selectedOrganization = computed(() =>
    organizations.value.find((item) => item.id === form.organizationId)
  )
  const viewData = computed(() => ({
    documentNo: form.documentNo,
    organization:
      currentDocument.value?.organization?.organizationName ||
      selectedOrganization.value?.organizationName ||
      '—',
    organizationCode:
      currentDocument.value?.organization?.organizationCode ||
      selectedOrganization.value?.organizationCode ||
      '—',
    documentType:
      documentTypes.value.find((item) => item.id === form.documentTypeId)?.name || title.value,
    businessType: businessTypes.value.find((item) => item.id === form.businessTypeId)?.name || '—',
    businessDate: form.businessDate,
    accountingDate: form.accountingDate,
    supplier:
      currentDocument.value?.supplier?.supplierName ||
      suppliers.value.find((item) => item.id === form.supplierId)?.name ||
      '—',
    supplierCode: suppliers.value.find((item) => item.id === form.supplierId)?.code || '—',
    purchaseDepartment:
      organizations.value.find((item) => item.id === form.purchaseDepartmentId)?.organizationName ||
      '—',
    purchaser:
      currentDocument.value?.purchaser?.employeeName || (form.purchaserId ? '已指定' : '未指定'),
    keeper: currentDocument.value?.keeper?.employeeName || (form.keeperId ? '已指定' : '未指定'),
    warehouse: warehouses.value.find((item) => item.id === form.warehouseId)?.warehouseName || '—',
    initialization: form.isInitialization ? '是' : '否',
    remark: form.remark || '—'
  }))
  const viewItems: ArtDescriptionItem<typeof viewData.value>[] = [
    { key: 'documentNo', label: '单据编号', field: 'documentNo', copyable: true },
    { key: 'organization', label: '库存组织', field: 'organization' },
    { key: 'organizationCode', label: '组织编码', field: 'organizationCode' },
    { key: 'documentType', label: '单据类型', field: 'documentType' },
    { key: 'businessType', label: '业务类型', field: 'businessType' },
    { key: 'businessDate', label: '业务日期', field: 'businessDate' },
    { key: 'accountingDate', label: '记账日期', field: 'accountingDate' },
    { key: 'supplier', label: '供应商', field: 'supplier' },
    { key: 'supplierCode', label: '供应商编码', field: 'supplierCode' },
    { key: 'purchaseDepartment', label: '采购部门', field: 'purchaseDepartment' },
    { key: 'purchaser', label: '采购员', field: 'purchaser' },
    { key: 'keeper', label: '仓管员', field: 'keeper' },
    { key: 'warehouse', label: '仓库', field: 'warehouse' },
    { key: 'initialization', label: '初始化单据', field: 'initialization' },
    { key: 'remark', label: '备注', field: 'remark', span: 3 }
  ]
  const currentWarehouses = computed(() =>
    warehouses.value.filter(
      (item) =>
        item.tenantId === form.tenantId &&
        item.organizationId === form.organizationId &&
        item.status === 'enabled'
    )
  )
  const availableOrganizations = computed(() =>
    organizations.value.filter(
      (item) => item.enabledOn && (!isInitial.value || !item.initializationClosedAt)
    )
  )
  const quantityTotal = computed(() =>
    lines.value.reduce((sum, item) => sum + displayQuantity(item.quantity), 0)
  )
  const totalAmount = computed(() =>
    lines.value.reduce((sum, item) => sum + lineFinancial(item).total, 0)
  )
  const purchaseUnitOptions = computed(() =>
    units.value.map((item) => ({ label: `${item.unitName} · ${item.unitCode}`, value: item.id }))
  )
  const lineMaterialFormItems = computed<FormItem[]>(() => [
    {
      key: 'materialName',
      label: '物料描述',
      type: 'text',
      props: { formatter: () => editLine.value?.material?.name || '—' }
    },
    {
      key: 'materialCode',
      label: '物料编码',
      type: 'text',
      props: { formatter: () => editLine.value?.material?.code || '—' }
    },
    {
      key: 'specificationModel',
      label: '规格型号',
      type: 'text',
      props: { formatter: () => editLine.value?.material?.specificationModel || '—' }
    },
    { key: 'projectId', label: '项目名称', type: 'input' },
    {
      key: 'projectCode',
      label: '项目编码',
      type: 'text',
      props: {
        formatter: () =>
          projects.value.find((item) => item.id === editLine.value?.projectId)?.code || '—'
      }
    },
    {
      key: 'constructionNo',
      label: '施工号',
      type: 'input',
      props: {
        disabled: !editLine.value?.projectId,
        placeholder: '选择项目后填写',
        onChange: clearSourceBatch
      }
    },
    { key: 'gift', label: '赠品', type: 'checkbox', props: { label: '赠品' } },
    {
      key: 'inventoryUnitId',
      label: '库存单位',
      type: 'select',
      options: purchaseUnitOptions.value,
      props: { filterable: true }
    },
    { key: 'quantity', label: '数量', type: 'number', props: { min: 0, precision: 4 } },
    {
      key: 'baseUnitId',
      label: '基本单位',
      type: 'select',
      options: purchaseUnitOptions.value,
      props: { filterable: true }
    },
    {
      key: 'baseQuantity',
      label: '基本数量',
      type: 'text',
      props: { formatter: () => (editLine.value ? baseQuantity(editLine.value) : '—') }
    }
  ])
  const lineMaterialRules = {
    inventoryUnitId: [{ required: true, message: '请选择库存单位', trigger: 'change' }],
    quantity: [{ required: true, message: '请填写数量', trigger: 'change' }]
  }
  const linePriceFormItems = computed<FormItem[]>(() => [
    {
      key: 'unitPrice',
      label: '单价(元)',
      type: 'number',
      props: { min: 0, precision: 4, onChange: () => updatePrice('untaxed') }
    },
    {
      key: 'taxInclusiveUnitPrice',
      label: '含税单价(元)',
      type: 'number',
      props: { min: 0, precision: 4, onChange: () => updatePrice('taxed') }
    },
    {
      key: 'taxRate',
      label: '税率(%)',
      type: 'select',
      options: taxRates.map((rate) => ({ label: `${rate}%`, value: rate })),
      props: { onChange: () => updatePrice(editLine.value?.priceBasis || 'untaxed') }
    },
    {
      key: 'discountMethod',
      label: '折扣方式',
      type: 'select',
      options: [
        { label: '无', value: 'none' },
        { label: '折扣率', value: 'rate' },
        { label: '单位折扣', value: 'amount' }
      ],
      props: {
        onChange: () => {
          if (editLine.value) editLine.value.unitDiscountRate = 0
        }
      }
    },
    {
      key: 'unitDiscountRate',
      label: '单位折扣（率）',
      type: 'number',
      props: {
        min: 0,
        max: 1,
        step: 0.01,
        precision: 4,
        disabled: editLine.value?.discountMethod === 'none'
      }
    },
    {
      key: 'discountAmount',
      label: '折扣额(元)',
      type: 'text',
      props: {
        formatter: () => (editLine.value ? lineFinancial(editLine.value).discount.toFixed(2) : '—')
      }
    },
    {
      key: 'amount',
      label: '金额(元)',
      type: 'text',
      props: {
        formatter: () => (editLine.value ? lineFinancial(editLine.value).amount.toFixed(2) : '—')
      }
    },
    {
      key: 'taxAmount',
      label: '税额(元)',
      type: 'text',
      props: {
        formatter: () => (editLine.value ? lineFinancial(editLine.value).tax.toFixed(2) : '—')
      }
    },
    {
      key: 'totalAmount',
      label: '价税合计(元)',
      type: 'text',
      props: {
        formatter: () => (editLine.value ? lineFinancial(editLine.value).total.toFixed(2) : '—')
      }
    }
  ])
  const linePriceRules = {
    taxRate: [{ required: true, message: '请选择税率', trigger: 'change' }]
  }
  const lineStorageFormItems = computed<FormItem[]>(() => [
    {
      key: 'batchNo',
      label: '批号',
      type: 'input',
      props: {
        onChange: () => {
          if (editLine.value?.batchNo !== selectedSourceBatch.value[0]?.batchNo) clearSourceBatch()
        }
      }
    },
    {
      key: 'warehouseId',
      label: '仓库',
      type: 'select',
      options: currentWarehouses.value.map((item) => ({
        label: `${item.warehouseName} · ${item.warehouseCode}`,
        value: item.id
      })),
      props: { filterable: true, clearable: true, onChange: onWarehouseChange }
    },
    {
      key: 'binId',
      label: '仓位',
      type: 'select',
      options: bins.value.map((item) => ({
        label: `${item.binName} · ${item.binCode}`,
        value: item.id
      })),
      props: {
        filterable: true,
        clearable: true,
        disabled: !editLine.value?.warehouseId,
        onChange: clearSourceBatch
      }
    },
    {
      key: 'stockType',
      label: '库存类型',
      type: 'select',
      options: stockTypes.value,
      props: { onChange: clearSourceBatch }
    },
    {
      key: 'ownerType',
      label: '货主类型',
      type: 'select',
      options: ownerTypes.value,
      props: {
        onChange: () => {
          if (editLine.value) editLine.value.ownerId = null
          clearSourceBatch()
        }
      }
    },
    { key: 'ownerId', label: '货主', type: 'input' },
    {
      key: 'stockStatus',
      label: '库存状态',
      type: 'select',
      options: stockStatuses.value,
      props: { onChange: clearSourceBatch }
    },
    ...(isReturn.value
      ? [{ key: 'sourceBatchId', label: '退料来源批次', type: 'input' as const, span: 12 }]
      : []),
    { key: 'keeperId', label: '仓管员', type: 'input' },
    {
      key: 'auxiliaryUnit',
      label: '辅助单位',
      type: 'text',
      props: { formatter: () => unitName(editLine.value?.auxiliaryUnitId || null) }
    },
    {
      key: 'auxiliaryQuantity',
      label: '辅助数量',
      type: 'text',
      props: {
        formatter: () =>
          editLine.value ? auxQuantity(editLine.value, editLine.value.auxiliaryUnitId) : '—'
      }
    },
    {
      key: 'auxiliaryUnit2',
      label: '辅助单位2',
      type: 'text',
      props: { formatter: () => unitName(editLine.value?.auxiliaryUnit2Id || null) }
    },
    {
      key: 'auxiliaryQuantity2',
      label: '辅助数量2',
      type: 'text',
      props: {
        formatter: () =>
          editLine.value ? auxQuantity(editLine.value, editLine.value.auxiliaryUnit2Id) : '—'
      }
    }
  ])
  const lineStorageRules = {
    warehouseId: [{ required: true, message: '请选择仓库', trigger: 'change' }],
    stockType: [{ required: true, message: '请选择库存类型', trigger: 'change' }]
  }
  const lineTraceFormItems = computed<FormItem[]>(() => [
    {
      key: 'productionDate',
      label: '生产日期',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: 'w-full!' }
    },
    {
      key: 'expiryDate',
      label: '有效期至',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: 'w-full!' }
    },
    { key: 'trackingNo', label: '跟踪号', type: 'input' },
    { key: 'sourceDocument', label: '来源单据', type: 'input' },
    { key: 'sourceLineNo', label: '源行号', type: 'input' },
    {
      key: 'remark',
      label: '备注',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 2, maxlength: 500 }
    }
  ])
  const lineMaterialViewItems: ArtDescriptionItem<WmsPurchaseLine>[] = [
    {
      key: 'materialName',
      label: '物料描述',
      value: (line: WmsPurchaseLine) => line.material?.name || '—'
    },
    {
      key: 'materialCode',
      label: '物料编码',
      value: (line: WmsPurchaseLine) => line.material?.code || '—'
    },
    {
      key: 'specificationModel',
      label: '规格型号',
      value: (line: WmsPurchaseLine) => line.material?.specificationModel || '—'
    },
    {
      key: 'project',
      label: '项目名称',
      value: (line: WmsPurchaseLine) =>
        projects.value.find((item) => item.id === line.projectId)?.name || '—'
    },
    { key: 'constructionNo', label: '施工号', field: 'constructionNo' },
    { key: 'gift', label: '赠品', value: (line: WmsPurchaseLine) => (line.gift ? '是' : '否') },
    {
      key: 'inventoryUnit',
      label: '库存单位',
      value: (line: WmsPurchaseLine) => unitName(line.inventoryUnitId)
    },
    {
      key: 'quantity',
      label: '数量',
      value: (line: WmsPurchaseLine) => String(displayQuantity(line.quantity))
    },
    {
      key: 'baseUnit',
      label: '基本单位',
      value: (line: WmsPurchaseLine) => unitName(line.baseUnitId)
    },
    {
      key: 'baseQuantity',
      label: '基本数量',
      value: (line: WmsPurchaseLine) => String(baseQuantity(line))
    }
  ]
  const linePriceViewItems: ArtDescriptionItem<WmsPurchaseLine>[] = [
    { key: 'unitPrice', label: '单价(元)', field: 'unitPrice' },
    { key: 'taxInclusiveUnitPrice', label: '含税单价(元)', field: 'taxInclusiveUnitPrice' },
    { key: 'taxRate', label: '税率(%)', value: (line: WmsPurchaseLine) => `${line.taxRate}%` },
    {
      key: 'discountMethod',
      label: '折扣方式',
      value: (line: WmsPurchaseLine) =>
        ({ none: '无', rate: '折扣率', amount: '单位折扣' })[line.discountMethod] || '—'
    },
    { key: 'unitDiscountRate', label: '单位折扣（率）', field: 'unitDiscountRate' },
    {
      key: 'discountAmount',
      label: '折扣额(元)',
      value: (line: WmsPurchaseLine) => lineFinancial(line).discount.toFixed(2)
    },
    {
      key: 'amount',
      label: '金额(元)',
      value: (line: WmsPurchaseLine) => lineFinancial(line).amount.toFixed(2)
    },
    {
      key: 'taxAmount',
      label: '税额(元)',
      value: (line: WmsPurchaseLine) => lineFinancial(line).tax.toFixed(2)
    },
    {
      key: 'totalAmount',
      label: '价税合计(元)',
      value: (line: WmsPurchaseLine) => lineFinancial(line).total.toFixed(2)
    }
  ]
  const lineStorageViewItems: ArtDescriptionItem<WmsPurchaseLine>[] = [
    {
      key: 'warehouse',
      label: '仓库',
      value: (line: WmsPurchaseLine) =>
        warehouses.value.find((item) => item.id === line.warehouseId)?.warehouseName || '—'
    },
    {
      key: 'bin',
      label: '仓位',
      value: (line: WmsPurchaseLine) =>
        bins.value.find((item) => item.id === line.binId)?.binName || '—'
    },
    {
      key: 'stockType',
      label: '库存类型',
      value: (line: WmsPurchaseLine) =>
        stockTypes.value.find((item) => item.value === line.stockType)?.label || '—'
    },
    {
      key: 'stockStatus',
      label: '库存状态',
      value: (line: WmsPurchaseLine) =>
        stockStatuses.value.find((item) => item.value === line.stockStatus)?.label || '—'
    },
    {
      key: 'ownerType',
      label: '货主类型',
      value: (line: WmsPurchaseLine) =>
        ownerTypes.value.find((item) => item.value === line.ownerType)?.label || '—'
    },
    {
      key: 'owner',
      label: '货主',
      value: (line: WmsPurchaseLine) =>
        line.ownerType === 'self'
          ? '自有'
          : [...suppliers.value, ...customers.value].find((item) => item.id === line.ownerId)
              ?.name || '—'
    },
    {
      key: 'keeper',
      label: '仓管员',
      value: (line: WmsPurchaseLine) => (line.keeperId ? '已指定' : '未指定')
    },
    {
      key: 'auxiliaryUnit',
      label: '辅助单位',
      value: (line: WmsPurchaseLine) => unitName(line.auxiliaryUnitId)
    },
    {
      key: 'auxiliaryQuantity',
      label: '辅助数量',
      value: (line: WmsPurchaseLine) => auxQuantity(line, line.auxiliaryUnitId)
    },
    {
      key: 'auxiliaryUnit2',
      label: '辅助单位2',
      value: (line: WmsPurchaseLine) => unitName(line.auxiliaryUnit2Id)
    },
    {
      key: 'auxiliaryQuantity2',
      label: '辅助数量2',
      value: (line: WmsPurchaseLine) => auxQuantity(line, line.auxiliaryUnit2Id)
    }
  ]
  const lineTraceViewItems = computed<ArtDescriptionItem<WmsPurchaseLine>[]>(() => [
    { key: 'batchNo', label: '批号', field: 'batchNo' },
    ...(isReturn.value
      ? [
          {
            key: 'sourceBatchId',
            label: '退料来源批次',
            value: (line: WmsPurchaseLine) => (line.sourceBatchId ? line.batchNo || '已指定' : '—')
          }
        ]
      : []),
    { key: 'productionDate', label: '生产日期', field: 'productionDate' },
    { key: 'expiryDate', label: '有效期至', field: 'expiryDate' },
    { key: 'trackingNo', label: '跟踪号', field: 'trackingNo' },
    { key: 'sourceDocument', label: '来源单据', field: 'sourceDocument' },
    { key: 'sourceLineNo', label: '源行号', field: 'sourceLineNo' },
    { key: 'remark', label: '备注', field: 'remark', span: 3 },
    {
      key: 'serialNos',
      label: '序列号',
      value: (line: WmsPurchaseLine) => line.serialNos.join('、') || '—',
      span: 3
    }
  ])
  const headerItems = computed<FormItem[]>(() => [
    {
      key: 'documentNo',
      label: '单据编号',
      type: 'input',
      props: { readonly: true, placeholder: '保存时按月度编号规则生成' }
    },
    {
      key: 'organizationId',
      label: '库存组织',
      type: 'select',
      options: availableOrganizations.value.map((item) => ({
        label: `${item.organizationName} · ${item.organizationCode}`,
        value: item.id
      })),
      props: { filterable: true, disabled: mode.value === 'view', onChange: onOrganizationChange }
    },
    {
      key: 'documentTypeId',
      label: '单据类型',
      type: 'select',
      options: documentTypes.value
        .filter((item) => item.code === typeCode.value)
        .map((item) => ({ label: item.name, value: item.id })),
      props: { disabled: mode.value === 'view' }
    },
    {
      key: 'businessTypeId',
      label: '业务类型',
      type: 'select',
      options: businessTypes.value
        .filter((item) => item.documentTypeId === form.documentTypeId)
        .map((item) => ({ label: item.name, value: item.id })),
      props: { disabled: mode.value === 'view' }
    },
    {
      key: 'businessDate',
      label: '业务日期',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', disabled: mode.value === 'view', class: 'w-full!' }
    },
    {
      key: 'accountingDate',
      label: '记账日期',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', disabled: true, class: 'w-full!' }
    },
    {
      key: 'supplierId',
      label: '供应商',
      type: 'input',
      props: { disabled: mode.value === 'view' }
    },
    {
      key: 'supplierCode',
      label: '供应商编码',
      type: 'input',
      props: { readonly: true, placeholder: '选择供应商后自动带入' }
    },
    {
      key: 'purchaserId',
      label: '采购员',
      type: 'input',
      props: { disabled: mode.value === 'view' }
    },
    {
      key: 'purchaseDepartmentId',
      label: '采购部门',
      type: 'select',
      options: organizations.value
        .filter((item) => item.tenantId === form.tenantId)
        .map((item) => ({ label: item.organizationName, value: item.id })),
      props: { filterable: true, clearable: true, disabled: mode.value === 'view' }
    },
    { key: 'keeperId', label: '仓管员', type: 'input', props: { disabled: mode.value === 'view' } },
    {
      key: 'warehouseId',
      label: '仓库',
      type: 'select',
      options: currentWarehouses.value.map((item) => ({
        label: `${item.warehouseName} · ${item.warehouseCode}`,
        value: item.id
      })),
      props: { filterable: true, clearable: true, disabled: mode.value === 'view' }
    },
    {
      key: 'status',
      label: '单据状态',
      type: 'select',
      options: [
        { label: '暂存', value: 'draft' },
        { label: '已提交', value: 'submitted' },
        { label: '已审核', value: 'approved' }
      ],
      props: { disabled: true }
    },
    { key: 'isInitialization', label: '初始化单据', type: 'switch', props: { disabled: true } },
    {
      key: 'remark',
      label: '备注',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 2,
        maxlength: 500,
        showWordLimit: true,
        disabled: mode.value === 'view'
      }
    }
  ])
  const headerRules = {
    organizationId: [{ required: true, message: '请选择已启用的库存组织', trigger: 'change' }],
    documentTypeId: [{ required: true, message: '请选择单据类型', trigger: 'change' }],
    businessTypeId: [{ required: true, message: '请选择业务类型', trigger: 'change' }],
    businessDate: [{ required: true, message: '请选择业务日期', trigger: 'change' }],
    supplierId: [{ required: true, message: '请选择供应商', trigger: 'change' }]
  }
  const materialColumns = [
    { prop: 'code', label: '物料编码', width: 165 },
    { prop: 'name', label: '物料描述', minWidth: 220 },
    { prop: 'specificationModel', label: '规格型号', minWidth: 140 }
  ]
  const partyColumns = [
    { prop: 'code', label: '编码', width: 150 },
    { prop: 'name', label: '名称', minWidth: 220 }
  ]
  const sourceBatchColumns: DataSelectColumn[] = [
    { prop: 'batchNo', label: '批号', minWidth: 200 },
    { prop: 'quantity', label: '现存数量', width: 120, align: 'right' },
    { prop: 'receivedAt', label: '入库时间', minWidth: 170 }
  ]
  function round(value: number, digits = 4): number {
    const factor = 10 ** digits
    return Math.round((value + Number.EPSILON) * factor) / factor
  }
  function displayQuantity(value: number): number {
    return isReturn.value ? -Math.abs(Number(value || 0)) : Math.abs(Number(value || 0))
  }
  function unitName(id: string | null): string {
    return units.value.find((item) => item.id === id)?.unitName || '—'
  }
  function projectName(id: string | null): string {
    return projects.value.find((item) => item.id === id)?.name || '—'
  }
  function conversionFactor(
    material: WmsPurchaseMaterial | null | undefined,
    unitId: string | null
  ): number | null {
    if (!material || !unitId) return null
    if (unitId === material.baseUnitId) return 1
    const entry = material.unitConversions?.find((item) => item.sourceUnitId === unitId)
    return entry && entry.sourceFactor > 0 ? entry.baseFactor / entry.sourceFactor : null
  }
  function baseQuantity(line: WmsPurchaseLine): number {
    const inventoryFactor = conversionFactor(line.material, line.inventoryUnitId)
    const baseFactor = conversionFactor(line.material, line.baseUnitId)
    return inventoryFactor && baseFactor
      ? round((Math.abs(Number(line.quantity || 0)) * inventoryFactor) / baseFactor)
      : 0
  }
  function auxQuantity(line: WmsPurchaseLine, unitId: string | null): string {
    const inventoryFactor = conversionFactor(line.material, line.inventoryUnitId)
    const auxFactor = conversionFactor(line.material, unitId)
    return inventoryFactor && auxFactor
      ? round((Math.abs(Number(line.quantity || 0)) * inventoryFactor) / auxFactor).toString()
      : '—'
  }
  function lineFinancial(line: WmsPurchaseLine): {
    discount: number
    amount: number
    tax: number
    total: number
  } {
    if (line.gift) return { discount: 0, amount: 0, tax: 0, total: 0 }
    const quantity = displayQuantity(line.quantity)
    const rate = line.discountMethod === 'none' ? 0 : Number(line.unitDiscountRate || 0)
    const discount = round(quantity * Number(line.taxInclusiveUnitPrice || 0) * rate, 2)
    const amount = round(quantity * Number(line.unitPrice || 0) - discount, 2)
    const tax = round((quantity * Number(line.unitPrice || 0) * Number(line.taxRate || 0)) / 100, 2)
    return { discount, amount, tax, total: round(amount + tax, 2) }
  }
  function updatePrice(basis: 'untaxed' | 'taxed'): void {
    if (!editLine.value) return
    editLine.value.priceBasis = basis
    const factor = 1 + Number(editLine.value.taxRate || 0) / 100
    if (basis === 'taxed')
      editLine.value.unitPrice = round(Number(editLine.value.taxInclusiveUnitPrice || 0) / factor)
    else
      editLine.value.taxInclusiveUnitPrice = round(Number(editLine.value.unitPrice || 0) * factor)
  }
  function materialFromRow(row: DataSelectRecord): WmsPurchaseMaterial | null {
    if (typeof row.id !== 'string' || typeof row.code !== 'string' || typeof row.name !== 'string')
      return null
    return {
      id: row.id,
      tenantId: form.tenantId,
      code: row.code,
      name: row.name,
      description: typeof row.description === 'string' ? row.description : null,
      specificationModel:
        typeof row.specificationModel === 'string' ? row.specificationModel : null,
      inventoryUnitId: typeof row.inventoryUnitId === 'string' ? row.inventoryUnitId : null,
      baseUnitId: typeof row.baseUnitId === 'string' ? row.baseUnitId : null,
      auxiliaryUnitId: typeof row.auxiliaryUnitId === 'string' ? row.auxiliaryUnitId : null,
      auxiliaryUnit2Id: typeof row.auxiliaryUnit2Id === 'string' ? row.auxiliaryUnit2Id : null,
      unitConversions: Array.isArray(row.unitConversions) ? row.unitConversions : [],
      serialManagementEnabled: row.serialManagementEnabled === true
    }
  }
  function makeLine(material: WmsPurchaseMaterial): WmsPurchaseLine {
    return {
      lineNo: (lines.value.length + 1) * 10,
      materialId: material.id,
      material,
      projectId: null,
      constructionNo: null,
      gift: false,
      inventoryUnitId: material.inventoryUnitId || '',
      quantity: 0,
      baseUnitId: material.baseUnitId,
      baseQuantity: 0,
      unitPrice: 0,
      taxInclusiveUnitPrice: 0,
      priceBasis: 'untaxed',
      taxRate: 13,
      discountMethod: 'none',
      unitDiscountRate: 0,
      discountAmount: 0,
      amount: 0,
      taxAmount: 0,
      totalAmount: 0,
      batchNo: null,
      sourceBatchId: null,
      warehouseId: form.warehouseId,
      binId: null,
      stockType: 'normal',
      ownerType: 'self',
      ownerId: null,
      stockStatus: 'available',
      keeperId: form.keeperId,
      auxiliaryUnitId: material.auxiliaryUnitId,
      auxiliaryQuantity: null,
      auxiliaryUnit2Id: material.auxiliaryUnit2Id,
      auxiliaryQuantity2: null,
      productionDate: null,
      expiryDate: null,
      trackingNo: null,
      sourceDocument: null,
      sourceLineNo: null,
      remark: null,
      serialNos: []
    }
  }
  function renumber(): void {
    lines.value.forEach((line, index) => {
      line.lineNo = (index + 1) * 10
    })
  }
  function addMaterials(_ids: unknown, rows: DataSelectRecord[]): void {
    lines.value.push(
      ...rows
        .map(materialFromRow)
        .filter((row): row is WmsPurchaseMaterial => row !== null)
        .map(makeLine)
    )
    renumber()
    materialPickerIds.value = []
    materialPickerRows.value = []
  }
  function copyLine(index: number): void {
    lines.value.splice(index + 1, 0, cloneDeep(lines.value[index]))
    renumber()
  }
  function removeLine(index: number): void {
    lines.value.splice(index, 1)
    renumber()
  }
  function lineIndex(line: WmsPurchaseLine): number {
    return lines.value.findIndex((item) => item.lineNo === line.lineNo)
  }
  function onLineMoreAction(item: ButtonMoreItem, line: WmsPurchaseLine): void {
    const index = lineIndex(line)
    if (index < 0) return
    if (item.key === 'copy-line') copyLine(index)
    else if (item.key === 'delete-line') removeLine(index)
  }
  function onPurchaserSelected(rows: EmployeeIntegrationItem[]): void {
    selectedPurchaser.value = rows
    if (rows[0]?.organizationId) form.purchaseDepartmentId = rows[0].organizationId
  }
  function onSupplierSelected(rows: DataSelectRecord[]): void {
    selectedSupplier.value = rows
    form.supplierCode = String(rows[0]?.code || '')
  }
  async function onWarehouseChange(): Promise<void> {
    if (!editLine.value) return
    editLine.value.binId = null
    clearSourceBatch()
    bins.value = editLine.value.warehouseId
      ? await fetchWmsPurchaseBins(editLine.value.warehouseId)
      : []
  }
  function clearSourceBatch(): void {
    if (editLine.value) editLine.value.sourceBatchId = null
    selectedSourceBatch.value = []
  }
  function onLineProjectChange(projectId: string | null): void {
    if (!editLine.value) return
    if (editLine.value.projectId === projectId) return
    editLine.value.projectId = projectId
    editLine.value.constructionNo = null
    clearSourceBatch()
  }
  function onLineOwnerChange(ownerId: string | null): void {
    if (!editLine.value) return
    if (editLine.value.ownerId === ownerId) return
    editLine.value.ownerId = ownerId
    clearSourceBatch()
  }
  function onSourceBatchSelected(rows: DataSelectRecord[]): void {
    const line = editLine.value
    if (!rows.length && line && line.batchNo === selectedSourceBatch.value[0]?.batchNo)
      line.batchNo = null
    selectedSourceBatch.value = rows
    if (line && typeof rows[0]?.batchNo === 'string') line.batchNo = rows[0].batchNo
  }
  function sourceBatchApi(params: DataSelectFetchParams) {
    const line = editLine.value
    if (!line?.materialId || !line.warehouseId || !form.tenantId || !form.organizationId)
      return { data: [], total: 0 }
    return fetchWmsPurchaseSourceBatches({
      tenantId: form.tenantId,
      organizationId: form.organizationId,
      materialId: line.materialId,
      warehouseId: line.warehouseId,
      binId: line.binId,
      projectId: line.projectId,
      constructionNo: line.constructionNo,
      ownerType: line.ownerType,
      ownerId: line.ownerId,
      stockType: line.stockType,
      stockStatus: line.stockStatus,
      keyword: params.keyword || '',
      current: params.page,
      size: params.pageSize
    })
  }
  const serialList = computed(() =>
    serialText.value
      .split(/\r?\n/)
      .map((value) => value.trim())
      .filter(Boolean)
  )
  const serialEntryVisible = computed({
    get: () => false,
    set: (value: boolean) => {
      if (value) {
        serialEntryForm.serialText = serialText.value
        void serialEntryDialogRef.value?.handleOpen(undefined, {
          title: '录入序列号',
          showFooter: mode.value !== 'view',
          confirmText: '保存序列号',
          onConfirm: () => {
            serialText.value = serialEntryForm.serialText
            return true
          }
        })
      }
    }
  })
  const serialViewVisible = computed({
    get: () => false,
    set: (value: boolean) => {
      if (value) void serialViewDialogRef.value?.handleOpen(undefined, { title: '查看序列号' })
    }
  })
  async function importSerials(event: Event): Promise<void> {
    const file = (event.target as HTMLInputElement).files?.[0]
    if (!file) return
    serialText.value = (await file.text()).replaceAll(',', '\n')
    ;(event.target as HTMLInputElement).value = ''
    ElMessage.success(`已导入 ${serialList.value.length} 个序列号`)
  }
  async function openLine(index: number): Promise<void> {
    editingIndex.value = index
    editLine.value = cloneDeep(lines.value[index])
    editLine.value.quantity = Math.abs(Number(editLine.value.quantity))
    serialText.value = editLine.value.serialNos.join('\n')
    selectedProject.value = editLine.value.project ? [editLine.value.project] : []
    selectedOwner.value = []
    selectedSourceBatch.value =
      editLine.value.sourceBatchId && editLine.value.batchNo
        ? [{ id: editLine.value.sourceBatchId, batchNo: editLine.value.batchNo }]
        : []
    selectedLineKeeper.value = []
    bins.value = []
    await lineDialogRef.value?.handleOpen(undefined, {
      title: mode.value === 'view' ? '物料明细' : '编辑物料明细',
      subtitle: `第 ${editLine.value.lineNo} 行`,
      showFooter: mode.value !== 'view',
      confirmText: '保存明细',
      onConfirm: () => {
        const line = editLine.value
        if (!line) return false
        if (!line.inventoryUnitId || Number(line.quantity) <= 0 || !line.stockType) {
          ElMessage.warning('请填写库存单位、数量和库存类型')
          return false
        }
        if (line.projectId && !line.constructionNo?.trim()) {
          ElMessage.warning('选择项目后请填写施工号')
          return false
        }
        if (line.ownerType !== 'self' && !line.ownerId) {
          ElMessage.warning('请选择货主')
          return false
        }
        const serials = serialList.value
        if (
          line.material?.serialManagementEnabled &&
          (Number(line.quantity) !== serials.length || new Set(serials).size !== serials.length)
        ) {
          ElMessage.warning('序列号数量须与物料数量一致且不能重复')
          return false
        }
        line.serialNos = serials
        line.baseQuantity = baseQuantity(line)
        const money = lineFinancial(line)
        line.discountAmount = money.discount
        line.amount = money.amount
        line.taxAmount = money.tax
        line.totalAmount = money.total
        lines.value[editingIndex.value] = cloneDeep(line)
        return true
      }
    })
    if (editLine.value.warehouseId) {
      bins.value = await fetchWmsPurchaseBins(editLine.value.warehouseId)
    }
  }
  function materialApi(params: DataSelectFetchParams) {
    return fetchWmsPurchaseMaterials({
      tenantId: form.tenantId,
      keyword: params.keyword || '',
      current: params.page,
      size: params.pageSize
    })
  }
  async function loadTenantOptions(tenantId: string): Promise<void> {
    const [unitRows, documentRows, businessRows, projectRows, supplierRows, customerRows] =
      await Promise.all([
        fetchWmsPurchaseUnits(tenantId),
        fetchWmsPurchaseOptions('mdm_document_type', tenantId),
        fetchWmsPurchaseOptions('mdm_business_type', tenantId),
        fetchWmsPurchaseOptions('mdm_project', tenantId),
        fetchWmsPurchaseOptions('mdm_supplier', tenantId),
        fetchWmsPurchaseOptions('mdm_customer', tenantId)
      ])
    units.value = unitRows
    documentTypes.value = documentRows
    businessTypes.value = businessRows
    projects.value = projectRows
    suppliers.value = supplierRows
    customers.value = customerRows
    if (!form.documentTypeId)
      form.documentTypeId = documentRows.find((item) => item.code === typeCode.value)?.id || ''
    if (!form.businessTypeId)
      form.businessTypeId =
        businessRows.find((item) => item.documentTypeId === form.documentTypeId)?.id || ''
  }
  async function onOrganizationChange(): Promise<void> {
    const org = selectedOrganization.value
    form.tenantId = org?.tenantId || ''
    form.businessDate = isInitial.value
      ? org?.enabledOn
        ? (dayjs().isAfter(org.enabledOn, 'day')
            ? dayjs(org.enabledOn).subtract(1, 'day')
            : dayjs()
          ).format('YYYY-MM-DD')
        : ''
      : dayjs().format('YYYY-MM-DD')
    form.documentTypeId = ''
    form.businessTypeId = ''
    form.supplierId = ''
    form.supplierCode = ''
    form.purchaserId = null
    form.purchaseDepartmentId = null
    form.warehouseId = null
    lines.value = []
    selectedSupplier.value = []
    selectedPurchaser.value = []
    if (form.tenantId) await loadTenantOptions(form.tenantId)
  }
  async function loadOptions(): Promise<void> {
    optionError.value = false
    try {
      const [orgPage, warehouseRows] = await Promise.all([
        fetchWmsPurchaseOrganizations(),
        fetchWmsPurchaseWarehouses()
      ])
      organizations.value = orgPage
      warehouses.value = warehouseRows
      if (form.tenantId) await loadTenantOptions(form.tenantId)
    } catch {
      optionError.value = true
    }
  }
  function onImportError(): void {
    ElMessage.error('导入失败，请检查 Excel 文件格式')
  }
  async function importLines(rows: Array<Record<string, unknown>>): Promise<void> {
    try {
      let imported = 0
      for (const row of rows.slice(0, 500)) {
        const code = String(row['物料编码'] || row.materialCode || '').trim()
        if (!code) continue
        const result = await fetchWmsPurchaseMaterials({
          tenantId: form.tenantId,
          keyword: code,
          current: 1,
          size: 20
        })
        const material = result.data.find((item) => item.code === code)
        if (!material) continue
        const line = makeLine(material)
        line.quantity = Math.abs(Number(row['数量'] || row.quantity || 0))
        line.unitPrice = Number(row['单价(元)'] || row.unitPrice || 0)
        line.taxRate = Number(row['税率(%)'] || row.taxRate || 13)
        line.taxInclusiveUnitPrice = round(line.unitPrice * (1 + line.taxRate / 100))
        line.batchNo = String(row['批号'] || row.batchNo || '') || null
        lines.value.push(line)
        imported++
      }
      renumber()
      if (imported) ElMessage.success(`已导入 ${imported} 行，请逐行核对仓储与价格信息`)
      else ElMessage.warning('未找到匹配的物料编码，请检查模板和当前租户物料')
    } catch {
      ElMessage.error('导入失败，请检查 Excel 文件格式')
    }
  }
  async function save(): Promise<boolean> {
    if (optionError.value) return false
    try {
      await formRef.value?.validate()
      if (
        isInitial.value &&
        (!selectedOrganization.value?.enabledOn ||
          form.businessDate > selectedOrganization.value.enabledOn)
      ) {
        ElMessage.warning('业务日期不得晚于库存组织启用日期')
        return false
      }
      if (!lines.value.length) {
        ElMessage.warning('请至少添加一行物料')
        return false
      }
      const incomplete = lines.value.find(
        (line) =>
          !line.inventoryUnitId ||
          Math.abs(Number(line.quantity)) <= 0 ||
          !line.stockType ||
          !line.warehouseId
      )
      if (incomplete) {
        ElMessage.warning(`第 ${incomplete.lineNo} 行尚未填写必填信息`)
        return false
      }
      await saveWmsPurchaseDocument({
        id: mode.value === 'edit' ? form.id : undefined,
        tenantId: form.tenantId,
        organizationId: form.organizationId,
        kind: props.kind,
        documentTypeId: form.documentTypeId,
        businessTypeId: form.businessTypeId,
        businessDate: form.businessDate,
        supplierId: form.supplierId,
        purchaserId: form.purchaserId,
        purchaseDepartmentId: form.purchaseDepartmentId,
        keeperId: form.keeperId,
        warehouseId: form.warehouseId,
        isInitialization: isInitial.value,
        remark: normalizeNullableText(form.remark),
        lines: lines.value
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen(data: OpenData): Promise<void> {
    mode.value = data.mode
    importIntent.value = Boolean(data.importIntent)
    await drawerRef.value?.handleOpen(data, {
      loading: true,
      loadingText: '正在加载单据资料…',
      showFooter: data.mode !== 'view',
      confirmText: data.mode === 'copy' ? '保存副本' : '保存',
      title:
        data.mode === 'create'
          ? `新增${title.value}`
          : data.mode === 'copy'
            ? `复制${title.value}`
            : data.mode === 'edit'
              ? `编辑${title.value}`
              : `${title.value}详情`,
      subtitle: data.document?.documentNo || '月度三位流水号自动生成',
      onConfirm: save
    })
    try {
      const source =
        data.document ??
        (data.documentId ? await fetchWmsPurchaseDocument(data.documentId) : undefined)
      currentDocument.value = source ?? null
      Object.assign(form, {
        id: data.mode === 'edit' ? source?.id || '' : '',
        tenantId: source?.tenantId || '',
        organizationId: source?.organizationId || '',
        documentNo: data.mode === 'copy' ? '' : source?.documentNo || '',
        documentTypeId: source?.documentTypeId || '',
        businessTypeId: source?.businessTypeId || '',
        businessDate: source?.businessDate || '',
        accountingDate: source?.accountingDate || dayjs().format('YYYY-MM-DD'),
        supplierId: source?.supplierId || '',
        supplierCode: source?.supplier?.supplierCode || '',
        purchaserId: source?.purchaserId || null,
        purchaseDepartmentId: source?.purchaseDepartmentId || null,
        keeperId: source?.keeperId || null,
        warehouseId: source?.warehouseId || null,
        status: data.mode === 'copy' ? 'draft' : source?.status || 'draft',
        isInitialization: isInitial.value,
        remark: source?.remark || ''
      })
      lines.value = source ? cloneDeep(source.lines) : []
      selectedSupplier.value = []
      selectedPurchaser.value = []
      selectedKeeper.value = []
      await loadOptions()
      drawerRef.value?.setOptions({ subtitle: source?.documentNo || '月度三位流水号自动生成' })
    } finally {
      drawerRef.value?.setLoading(false)
    }
  }
  defineExpose({ handleOpen })
</script>

<style scoped>
  .initialization-document-stack {
    display: grid;
    gap: 20px;
    align-content: start;
  }

  .purchase-return-quantity {
    padding: 4px 7px;
    font-weight: 800;
    font-variant-numeric: tabular-nums;
    color: var(--el-color-danger);
    background: var(--el-color-warning-light-9);
    border-radius: 5px;
  }
</style>
