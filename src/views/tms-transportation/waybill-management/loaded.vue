<template>
  <div class="tms-workspace-page art-full-height waybill-list">
    <CustomerDeleteProcessingNotice
      v-if="deleteContext.active"
      :customer-id="deleteContext.customerId"
      :customer-name="deleteContext.customerName"
      action-hint="已按运单号精确定位；运单属于履约历史，请保留记录并返回停用主数据。"
    />
    <TmsWorkspaceHeader
      eyebrow="WAYBILL EXECUTION"
      title="运输运单"
      description="跟踪装货、运输、卸货与完成状态，统一掌握车辆、司机、线路和执行进度。"
      icon="ri:truck-line"
      :tags="[
        { label: '运输执行', type: 'primary' },
        { label: '节点可追踪', type: 'success' }
      ]"
      :metrics="workspaceMetrics"
    />

    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86 }"
      :table-props="{
        rowKey: 'id',
        tableLayout: 'fixed',
        emptyText: '暂无运输运单',
        emptyDescription: '当前状态下没有运单，可切换执行状态或调整查询条件。'
      }"
      focusable
    >
      <template #table-header-top>
        <div class="waybill-list__status-tabs">
          <ElSegmented
            :model-value="table.searchQuery.waybillStatus"
            :options="table.statusTabs"
            @change="handleStatusTabChange"
          />
        </div>
      </template>
    </ArtTableQuery>
  </div>
</template>

<script setup lang="ts">
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchWaybillStatusCounts } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import TmsWorkspaceHeader, {
    type TmsWorkspaceMetric
  } from '@/views/tms-transportation/modules/tms-workspace-header.vue'
  import {
    WAYBILL_STATUS_ALL,
    createInitialWaybillSearch,
    createWaybillModeParams,
    createWaybillColumns,
    createWaybillHeaderActions,
    createWaybillSearchItems,
    fetchWaybillTableData,
    loadedWaybillStatusTabValues,
    type TableParams,
    type WaybillDialogExpose,
    type WaybillRecord,
    type WaybillSearchParams
  } from './modules/waybill-shared'
  import CustomerDeleteProcessingNotice from '@/views/tms-transportation/modules/customer-delete-processing-notice.vue'
  import { useCustomerDeleteProcessingContext } from '@/views/tms-transportation/modules/use-customer-delete-processing'

  defineOptions({ name: 'TmsLoadedWaybillList' })

  interface TableGroup {
    searchQuery: WaybillSearchParams
    statusCounts: Record<string, number>
    statusTotal: number
    statusTabs: ComputedRef<StatusTab[]>
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<WaybillRecord>[]
  }

  interface StatusTab {
    label: string
    value: string
  }

  const router = useRouter()
  const route = useRoute()
  const deleteContext = useCustomerDeleteProcessingContext()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dispatchDialogRef = ref<WaybillDialogExpose>()
  const statusCountRequestId = ref(0)
  const paymentMethodOptions = computed(() => getDictMap.value.tmsOrderPaymentMethod ?? [])
  const loadedStatusFallbackLabels: Record<string, string> = {
    pending: '待装货',
    loading: '装货中',
    transporting: '运输中',
    unloading: '卸货中',
    completed: '已完成',
    cancelled: '已取消'
  }

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: {
      ...createInitialWaybillSearch(),
      recordId:
        route.query.fromMasterDelete === '1' && typeof route.query.recordId === 'string'
          ? route.query.recordId
          : '',
      cargoKeyword: typeof route.query.recordNo === 'string' ? route.query.recordNo : ''
    },
    statusCounts: {},
    statusTotal: 0,
    statusTabs: computed<StatusTab[]>(() => {
      const statusDict = getDictMap.value.tmsWaybillStatus ?? []
      return [
        { label: `全部 (${table.statusTotal})`, value: WAYBILL_STATUS_ALL },
        ...loadedWaybillStatusTabValues.map((value) => {
          const item = statusDict.find((option) => option.value === value)
          return {
            label: `${item?.label || item?.name || loadedStatusFallbackLabels[value] || value} (${table.statusCounts[value] ?? 0})`,
            value
          }
        })
      ]
    }),
    searchItems: createWaybillSearchItems(paymentMethodOptions, true),
    headerActions: createWaybillHeaderActions({
      mode: 'loaded',
      router,
      tableQueryRef,
      dispatchDialogRef
    }),
    columnsFactory: () =>
      createWaybillColumns({
        mode: 'loaded',
        router,
        tableQueryRef,
        dispatchDialogRef
      })
  })

  const workspaceMetrics = computed<TmsWorkspaceMetric[]>(() => [
    {
      label: '执行运单',
      value: table.statusTotal,
      description: '当前筛选范围内的运输运单',
      icon: 'ri:file-list-2-line'
    },
    {
      label: '作业中',
      value: ['loading', 'transporting', 'unloading'].reduce(
        (sum, status) => sum + (table.statusCounts[status] ?? 0),
        0
      ),
      description: '装货、运输或卸货中的运单',
      icon: 'ri:route-line',
      tone: 'warning'
    },
    {
      label: '已完成',
      value: table.statusCounts.completed ?? 0,
      description: '已结束运输执行',
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    }
  ])

  function fetchTableData(params: TableParams) {
    void loadStatusCounts(params)
    return fetchWaybillTableData(params, 'loaded')
  }

  async function loadStatusCounts(params: TableParams): Promise<void> {
    const requestId = ++statusCountRequestId.value
    const searchParams = { ...params, ...createWaybillModeParams(params, 'loaded') }
    const result = await fetchWaybillStatusCounts(searchParams)
    if (requestId !== statusCountRequestId.value) return

    table.statusTotal = result.total
    table.statusCounts = result.counts
  }

  function handleStatusTabChange(status: string | number | boolean): void {
    table.searchQuery.waybillStatus = String(status)
    void tableQueryRef.value?.getData()
  }

  function syncMasterDeleteRoute(forceRefresh = false): void {
    if (route.query.fromMasterDelete !== '1') {
      if (forceRefresh) void tableQueryRef.value?.getData()
      return
    }
    const recordId = typeof route.query.recordId === 'string' ? route.query.recordId : ''
    const changed = table.searchQuery.recordId !== recordId
    Object.assign(table.searchQuery, {
      recordId,
      cargoKeyword: '',
      waybillStatus: WAYBILL_STATUS_ALL
    })
    if (changed || forceRefresh) void nextTick().then(() => tableQueryRef.value?.getData())
  }

  watch(
    () => route.fullPath,
    () => syncMasterDeleteRoute(),
    { flush: 'post' }
  )
  onActivated(() => syncMasterDeleteRoute(true))
</script>

<style scoped lang="scss">
  .waybill-list {
    &__status-tabs {
      display: flex;
      flex-wrap: wrap;
      align-items: center;

      :deep(.el-segmented) {
        --el-segmented-item-selected-color: var(--el-color-white);
        --el-segmented-item-selected-bg-color: var(--el-color-primary);

        max-width: 100%;

        .el-segmented__group {
          flex-wrap: wrap;
        }

        .el-segmented__item {
          color: var(--el-color-primary);

          &.is-selected {
            color: var(--el-color-white);
          }
        }
      }
    }
  }
</style>
