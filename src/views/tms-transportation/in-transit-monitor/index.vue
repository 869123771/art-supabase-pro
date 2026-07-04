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
    />
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
  import {
    createDeliveryColumns,
    createDeliveryHeaderActions,
    createDeliverySearchItems,
    createInitialDeliverySearch,
    fetchDeliveryTableData,
    type DeliveryRecord,
    type DeliverySearchParams,
    type TableParams
  } from '../delivery-management/modules/delivery-shared'

  defineOptions({ name: 'TmsInTransitMonitor' })

  interface TableGroup {
    searchQuery: DeliverySearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<DeliveryRecord>[]
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const paymentMethodOptions = computed(() => getDictMap.value.tmsOrderPaymentMethod ?? [])

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: createInitialDeliverySearch(),
    searchItems: createDeliverySearchItems(paymentMethodOptions),
    headerActions: createDeliveryHeaderActions({
      mode: 'transit',
      router,
      tableQueryRef
    }),
    columnsFactory: () =>
      createDeliveryColumns({
        mode: 'transit',
        router,
        tableQueryRef
      })
  })

  function fetchTableData(params: TableParams) {
    return fetchDeliveryTableData(params, 'transit')
  }
</script>
