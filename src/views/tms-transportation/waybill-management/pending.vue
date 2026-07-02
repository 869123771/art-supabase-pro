<template>
  <div class="art-full-height waybill-list">
    <ArtTableQuery
      ref="tableQueryRef"
      v-model="table.searchQuery"
      :search-items="table.searchItems"
      :api-fn="fetchTableData"
      :columns-factory="table.columnsFactory"
      :header-actions="table.headerActions"
      :search-bar-props="{ span: 6, labelWidth: 86 }"
      :table-props="{ rowKey: 'id', tableLayout: 'fixed' }"
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
  import { ColumnOption } from '@/types'
  import { useUserStore } from '@/store/modules/user'
  import DispatchDialog from './modules/dispatch-dialog.vue'
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
    void tableQueryRef.value?.refreshUpdate()
  }
</script>
