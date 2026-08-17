<template>
  <ArtPageSection :card="false" title="里程记录">
    <VehicleQueryTable :data="records" :columns="columns" :loading="loading" />
  </ArtPageSection>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import { fetchVehicleMileageList } from '@/api/vms'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehicleMileageRecord } from './types'
  import { formatDateTime, formatNumber } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'

  defineOptions({ name: 'VehicleQueryMileagePanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const { loading, records } = useVehiclePanelList<VehicleMileageRecord>(
    vehicle,
    async (current) => {
      const { data } = await fetchVehicleMileageList({
        plateNo: current.plateNo,
        from: 0,
        to: 9999
      })
      return data ?? []
    }
  )

  const columns: ColumnOption<VehicleMileageRecord>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    {
      prop: 'runningMileage',
      label: '运营行驶里程（公里）',
      minWidth: 180,
      formatter: (row) => formatNumber(row.runningMileage)
    },
    {
      prop: 'startTime',
      label: '开始时间',
      minWidth: 180,
      formatter: (row) => formatDateTime(row.startTime)
    },
    {
      prop: 'startMileage',
      label: '开始里程（公里）',
      minWidth: 170,
      formatter: (row) => formatNumber(row.startMileage)
    },
    {
      prop: 'endTime',
      label: '结束时间',
      minWidth: 180,
      formatter: (row) => formatDateTime(row.endTime)
    },
    {
      prop: 'endMileage',
      label: '结束里程（公里）',
      minWidth: 170,
      formatter: (row) => formatNumber(row.endMileage)
    }
  ]
</script>
