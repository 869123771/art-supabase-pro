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

  defineOptions({ name: 'VehicleQueryTable' })

  withDefaults(
    defineProps<{
      /** 车辆查询详情页的轻量表格包装，行结构由各业务面板决定。 */
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
