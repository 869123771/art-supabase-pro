<template>
  <ArtTable
    :data="data"
    :columns="columns"
    :loading="loading"
    :pagination="undefined"
    :show-table-header="false"
    :table-layout="tableLayout"
    :empty-height="emptyHeight"
  />
</template>

<script setup lang="ts">
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'

  defineOptions({ name: 'CarrierRelationTable' })

  withDefaults(
    defineProps<{
      data: unknown[]
      columns: ColumnOption[]
      loading?: boolean
      emptyHeight?: string
      tableLayout?: 'auto' | 'fixed'
    }>(),
    {
      loading: false,
      emptyHeight: '180px',
      tableLayout: 'fixed'
    }
  )
</script>
