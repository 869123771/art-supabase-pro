<template>
  <div class="business-workspace-page art-full-height waybill-list">
    <BusinessWorkspaceHeader
      eyebrow="DISPATCH QUEUE"
      title="待调度运单"
      description="聚合尚未完成派车的运输需求，统一核对线路、货物、付款方式与调度条件。"
      icon="ri:route-line"
      :tags="[
        { label: '待调度队列', type: 'warning' },
        { label: '运力匹配', type: 'primary' }
      ]"
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
        emptyText: '暂无待调度运单',
        emptyDescription: '当前没有待派车任务，可调整客户、线路、付款方式和时间条件后重新查询。'
      }"
      focusable
    />

    <DispatchDialog ref="dispatchDialogRef" @success="handleDispatchSuccess" />
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
  import { useUserStore } from '@/store/modules/user'
  import DispatchDialog from './modules/dispatch-dialog.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import {
    createInitialWaybillSearch,
    createWaybillColumns,
    createWaybillHeaderActions,
    createWaybillSearchItems,
    fetchWaybillTableData,
    type TableParams,
    type WaybillDialogExpose,
    type WaybillRecord,
    type WaybillSearchParams
  } from './modules/waybill-shared'

  defineOptions({ name: 'TmsPendingWaybillList' })

  interface TableGroup {
    searchQuery: WaybillSearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<WaybillRecord>[]
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const dispatchDialogRef = ref<WaybillDialogExpose>()
  const paymentMethodOptions = computed(() => getDictMap.value.tmsOrderPaymentMethod ?? [])

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: createInitialWaybillSearch(),
    searchItems: createWaybillSearchItems(paymentMethodOptions, false),
    headerActions: createWaybillHeaderActions({
      mode: 'pending',
      router,
      tableQueryRef,
      dispatchDialogRef
    }),
    columnsFactory: () =>
      createWaybillColumns({
        mode: 'pending',
        router,
        tableQueryRef,
        dispatchDialogRef
      })
  })

  function fetchTableData(params: TableParams) {
    return fetchWaybillTableData(params, 'pending')
  }

  function handleDispatchSuccess(): void {
    void router.push({ name: 'TmsLoadedWaybillList' })
  }

  onActivated(() => {
    void tableQueryRef.value?.getData()
  })
</script>
