<template>
  <ArtPageSection :card="false" title="车辆年检">
    <VehicleQueryTable :data="records" :columns="columns" :loading="loading" />
  </ArtPageSection>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import { fetchVehicleInspectionList } from '@/api/vms'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehicleInspection } from './types'
  import { formatDate, formatMoney } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'

  defineOptions({ name: 'VehicleQueryInspectionPanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const { loading, records } = useVehiclePanelList<VehicleInspection>(vehicle, async (current) => {
    const { data } = await fetchVehicleInspectionList({
      plateNo: current.plateNo,
      from: 0,
      to: 9999
    })
    return data ?? []
  })

  const columns: ColumnOption<VehicleInspection>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    {
      prop: 'inspectionDate',
      label: '年检日期',
      minWidth: 150,
      formatter: (row) => formatDate(row.inspectionDate)
    },
    { prop: 'inspectionNo', label: '年检号', minWidth: 160 },
    {
      prop: 'inspectionAmount',
      label: '年检金额（元）',
      minWidth: 150,
      formatter: (row) => formatMoney(row.inspectionAmount)
    },
    { prop: 'vehicleOffice', label: '车管所', minWidth: 160 },
    {
      prop: 'expireDate',
      label: '到期日期',
      minWidth: 150,
      formatter: (row) => formatDate(row.expireDate)
    }
  ]
</script>
