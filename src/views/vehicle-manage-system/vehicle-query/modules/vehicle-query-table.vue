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
      // ArtTable 是业务记录无关的包装组件；这里保留局部 any，避免 Vue 模板泛型推断把各业务行类型退成 Record<string, unknown>。
      data: any[]
      columns: ColumnOption<any>[]
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
