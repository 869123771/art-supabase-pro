<template>
  <ArtPageSection :card="false" title="零部件管理">
    <template #actions>
      <ElInput v-model="panel.keyword" clearable placeholder="零部件名称" style="width: 220px" />
    </template>
    <VehicleQueryTable :data="filteredRecords" :columns="columns" :loading="loading" />
  </ArtPageSection>
</template>

<script setup lang="tsx">
  import { ElInput } from 'element-plus'
  import type { ColumnOption } from '@/types'
  import { fetchVehiclePartUsageList } from '@/api/vehicle-manage-system'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehiclePartUsage } from './types'
  import { formatDate, formatValue } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'
  import { isNil } from 'lodash-es'

  defineOptions({ name: 'VehicleQueryPartsPanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const panel = reactive({
    keyword: ''
  })

  const { loading, records } = useVehiclePanelList<VehiclePartUsage>(vehicle, async (current) => {
    const { data } = await fetchVehiclePartUsageList({
      plateNo: current.plateNo,
      from: 0,
      to: 9999
    })
    return data ?? []
  })

  const filteredRecords = computed(() => {
    const keyword = panel.keyword.trim()
    if (!keyword) return records.value
    return records.value.filter((item) => item.partName?.includes(keyword))
  })

  const columns: ColumnOption<VehiclePartUsage>[] = [
    { type: 'globalIndex', label: '序号', width: 70 },
    {
      prop: 'partType',
      label: '零部件类型',
      width: 120,
      dict: { code: 'vehiclePartType', display: 'auto' }
    },
    { prop: 'partName', label: '零部件名称', minWidth: 160 },
    { prop: 'categoryName', label: '类别', width: 120 },
    { prop: 'brand', label: '品牌', width: 100 },
    { prop: 'model', label: '型号', width: 120 },
    { prop: 'rfidTag', label: 'RFID标签', minWidth: 140 },
    {
      prop: 'enableDate',
      label: '启用日期',
      width: 120,
      formatter: (row) => formatDate(row.enableDate)
    },
    {
      prop: 'warrantySummary',
      label: '质保期',
      width: 150,
      formatter: (row) => formatWarranty(row)
    },
    { prop: 'serviceYears', label: '使用年限（年）', width: 130 },
    {
      prop: 'usedYears',
      label: '已使用时长（年）',
      width: 150,
      formatter: (row) => formatUsedYears(row.enableDate)
    },
    { prop: 'serviceMileage', label: '可使用里程（公里）', width: 160 },
    { prop: 'usedMileage', label: '已使用里程（公里）', width: 160 },
    {
      prop: 'status',
      label: '状态',
      width: 100,
      dict: { code: 'vehiclePartUsageStatus', display: 'auto' }
    }
  ]

  const formatWarranty = (row: VehiclePartUsage): string => {
    if (row.warrantyMode === 'vehicle') return '随整车质保'
    const values = [
      row.warrantyDuration ? `${row.warrantyDuration}个月` : '',
      row.warrantyMileage ? `${row.warrantyMileage}公里` : ''
    ].filter(Boolean)
    return values.join(' / ') || '--'
  }

  const formatUsedYears = (enableDate?: string | null): string => {
    if (isNil(enableDate) || enableDate === '') return '--'
    const start = new Date(enableDate)
    if (Number.isNaN(start.getTime())) return '--'
    const years = Math.max(0, (Date.now() - start.getTime()) / (365.25 * 24 * 60 * 60 * 1000))
    return formatValue(years.toFixed(1))
  }
</script>
