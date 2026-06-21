<template>
  <VehicleQuerySection title="事故记录">
    <VehicleQueryTable :data="records" :columns="columns" :loading="loading" />
  </VehicleQuerySection>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import { fetchVehicleAccidentList } from '@/api/vehicle-manage-system'
  import VehicleQuerySection from './vehicle-query-section.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleAccidentRecord, VehicleArchive } from './types'
  import { formatDate, formatValue } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'

  defineOptions({ name: 'VehicleQueryAccidentPanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const { loading, records } = useVehiclePanelList<VehicleAccidentRecord>(
    vehicle,
    async (current) => {
      const { data } = await fetchVehicleAccidentList({
        plateNo: current.plateNo,
        from: 0,
        to: 9999
      })
      return data ?? []
    }
  )

  const columns: ColumnOption<VehicleAccidentRecord>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'driverName', label: '驾驶员姓名', minWidth: 150 },
    {
      prop: 'accidentTime',
      label: '事故时间',
      minWidth: 150,
      formatter: (row) => formatDate(row.accidentTime)
    },
    { prop: 'accidentLocation', label: '事故地点', minWidth: 260 },
    { prop: 'accidentSummary', label: '事故概要', minWidth: 220 },
    { prop: 'damageLevel', label: '损坏程度', minWidth: 150 },
    {
      prop: 'processed',
      label: '是否处理',
      width: 120,
      dict: {
        code: 'vehicleRecordProcessed',
        display: 'text',
        value: (row) => String(row.processed)
      }
    },
    {
      prop: 'dataSource',
      label: '数据来源',
      width: 120,
      dict: { code: 'vehicleAccidentDataSource', display: 'text' },
      formatter: (row) => formatValue(row.dataSource)
    }
  ]
</script>
