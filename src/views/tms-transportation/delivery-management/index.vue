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
  import { useUserStore } from '@/store/modules/user'
  import SignDialog from './modules/sign-dialog.vue'
  import {
    createDeliveryColumns,
    createDeliveryHeaderActions,
    createDeliverySearchItems,
    createInitialDeliverySearch,
    fetchDeliveryTableData,
    type DeliveryRecord,
    type DeliverySearchParams,
    type DeliverySignDialogExpose,
    type TableParams
  } from './modules/delivery-shared'

  defineOptions({ name: 'TmsDeliveryManagement' })

  interface TableGroup {
    searchQuery: DeliverySearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
    columnsFactory: () => ColumnOption<DeliveryRecord>[]
  }

  const router = useRouter()
  const { getDictMap } = storeToRefs(useUserStore())
  const tableQueryRef = ref<ArtTableQueryExpose>()
  const signDialogRef = ref<DeliverySignDialogExpose>()
  const paymentMethodOptions = computed(() => getDictMap.value.tmsOrderPaymentMethod ?? [])

  const table: UnwrapNestedRefs<TableGroup> = reactive<TableGroup>({
    searchQuery: createInitialDeliverySearch(),
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
    return fetchDeliveryTableData(params, 'delivery')
  }

  function handleSignSuccess(): void {
    void tableQueryRef.value?.refreshUpdate()
  }
</script>
