<template>
  <div class="tms-workspace-page art-full-height delivery-list">
    <MasterDeleteProcessingNotice
      action-hint="关联异常工单已自动打开并精确过滤；请完成处置后返回。"
    />
    <TmsWorkspaceHeader
      eyebrow="DELIVERY CONTROL"
      title="配送与签收"
      description="集中处理待签收、回单和异常工单，确保运输交付凭证完整并形成闭环。"
      icon="ri:package-check-line"
      :tags="[
        { label: '签收闭环', type: 'success' },
        { label: '异常可处置', type: 'warning' }
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
        emptyText: '暂无配送任务',
        emptyDescription: '当前状态下没有配送记录，可切换签收状态或调整查询条件。'
      }"
      focusable
    >
      <template #table-header-top>
        <div class="delivery-list__status-tabs">
          <ElSegmented
            :model-value="table.searchQuery.deliveryStatus"
            :options="table.statusTabs"
            @change="handleStatusTabChange"
          />
        </div>
      </template>
    </ArtTableQuery>

    <SignDialog ref="signDialogRef" @success="handleSignSuccess" />
    <ReceiptExceptionWorkOrderDrawer ref="exceptionDrawerRef" />
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
  import { fetchDeliveryStatusCounts } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import SignDialog from './modules/sign-dialog.vue'
  import ReceiptExceptionWorkOrderDrawer from './modules/receipt-exception-work-order-drawer.vue'
  import TmsWorkspaceHeader, {
    type TmsWorkspaceMetric
  } from '@/views/tms-transportation/modules/tms-workspace-header.vue'
  import MasterDeleteProcessingNotice from '@/components/business/master-delete-processing-notice/index.vue'
  import {
    DELIVERY_STATUS_ALL,
    createDeliveryColumns,
    createDeliveryHeaderActions,
    createDeliverySearchItems,
    createInitialDeliverySearch,
    fetchDeliveryTableData,
    deliveryOrderStatuses,
    type DeliveryRecord,
    type DeliverySearchParams,
    type DeliverySignDialogExpose,
    type TableParams
  } from './modules/delivery-shared'

  defineOptions({ name: 'TmsDeliveryManagement' })

  interface TableGroup {
    searchQuery: DeliverySearchParams
    statusCounts: Record<string, number>
    statusTotal: number
    statusTabs: ComputedRef<StatusTab[]>
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<DeliveryRecord>[]
  }

  interface StatusTab {
    label: string
    value: string
  }

  const router = useRouter()
  const route = useRoute()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const signDialogRef = ref<DeliverySignDialogExpose>()
  const exceptionDrawerRef = ref<{ handleOpen: (recordId?: string) => Promise<void> }>()
  const statusCountRequestId = ref(0)
  const paymentMethodOptions = computed(() => getDictMap.value.tmsOrderPaymentMethod ?? [])

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: createInitialDeliverySearch(),
    statusCounts: {},
    statusTotal: 0,
    statusTabs: computed<StatusTab[]>(() => {
      const statusDict = getDictMap.value.tmsOrderStatus ?? []
      return [
        { label: `全部 (${table.statusTotal})`, value: DELIVERY_STATUS_ALL },
        ...deliveryOrderStatuses.map((value) => {
          const item = statusDict.find((option) => option.value === value)
          return {
            label: `${item?.label || item?.name || value} (${table.statusCounts[value] ?? 0})`,
            value
          }
        })
      ]
    }),
    searchItems: createDeliverySearchItems(paymentMethodOptions, true),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() => [
      {
        label: '签收异常工单',
        icon: 'ri-file-warning-line',
        buttonProps: { type: 'primary', plain: true },
        onClick: () => void exceptionDrawerRef.value?.handleOpen()
      },
      ...createDeliveryHeaderActions({
        mode: 'delivery',
        router,
        tableQueryRef,
        signDialogRef
      }).value
    ]),
    columnsFactory: () =>
      createDeliveryColumns({
        mode: 'delivery',
        router,
        tableQueryRef,
        signDialogRef
      })
  })

  const workspaceMetrics = computed<TmsWorkspaceMetric[]>(() => [
    {
      label: '交付任务',
      value: table.statusTotal,
      description: '当前筛选范围内的配送记录',
      icon: 'ri:inbox-archive-line'
    },
    {
      label: '已签收',
      value: table.statusCounts.signed ?? 0,
      description: '已完成签收、待归档记录',
      icon: 'ri:signature-line',
      tone: 'warning'
    },
    {
      label: '已完成',
      value: table.statusCounts.completed ?? 0,
      description: '交付凭证已形成闭环',
      icon: 'ri:checkbox-circle-line',
      tone: 'success'
    }
  ])

  function fetchTableData(params: TableParams) {
    void loadStatusCounts(params)
    return fetchDeliveryTableData(params, 'delivery')
  }

  async function loadStatusCounts(params: TableParams): Promise<void> {
    const requestId = ++statusCountRequestId.value
    const result = await fetchDeliveryStatusCounts(params)
    if (requestId !== statusCountRequestId.value) return

    table.statusTotal = result.total
    table.statusCounts = result.counts
  }

  function handleStatusTabChange(status: string | number | boolean): void {
    table.searchQuery.deliveryStatus = String(status)
    void tableQueryRef.value?.getData()
  }

  function handleSignSuccess(): void {
    void tableQueryRef.value?.refreshUpdate()
  }

  const openMasterDeleteWorkOrder = (): void => {
    if (route.query.fromMasterDelete !== '1') return
    const recordId = typeof route.query.recordId === 'string' ? route.query.recordId : ''
    if (recordId) void nextTick().then(() => exceptionDrawerRef.value?.handleOpen(recordId))
  }

  watch(() => route.fullPath, openMasterDeleteWorkOrder, { immediate: true, flush: 'post' })
</script>

<style scoped lang="scss">
  .delivery-list {
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
