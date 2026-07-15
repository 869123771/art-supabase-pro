<template>
  <div class="art-full-height delivery-list">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
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
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const signDialogRef = ref<DeliverySignDialogExpose>()
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
    headerActions: createDeliveryHeaderActions({
      mode: 'delivery',
      router,
      tableQueryRef,
      signDialogRef
    }),
    columnsFactory: () =>
      createDeliveryColumns({
        mode: 'delivery',
        router,
        tableQueryRef,
        signDialogRef
      })
  })

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
