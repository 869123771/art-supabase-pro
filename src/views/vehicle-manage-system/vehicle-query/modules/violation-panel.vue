<template>
  <ArtPageSection :card="false" title="车辆违章">
    <VehicleQueryTable :data="records" :columns="columns" :loading="loading" />
  </ArtPageSection>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import { fetchVehicleViolationList } from '@/api/vehicle-manage-system'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehicleViolationRecord } from './types'
  import { formatDateTime, formatMoney } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'

  defineOptions({ name: 'VehicleQueryViolationPanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const { loading, records } = useVehiclePanelList<VehicleViolationRecord>(
    vehicle,
    async (current) => {
      const { data } = await fetchVehicleViolationList({
        plateNo: current.plateNo,
        from: 0,
        to: 9999
      })
      return data ?? []
    }
  )

  const columns: ColumnOption<VehicleViolationRecord>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'driverName', label: '驾驶员姓名', minWidth: 140 },
    { prop: 'violationBehavior', label: '违章行为', minWidth: 220 },
    {
      prop: 'violationTime',
      label: '违章时间',
      minWidth: 180,
      formatter: (row) => formatDateTime(row.violationTime)
    },
    { prop: 'violationLocation', label: '违章地点', minWidth: 260 },
    { prop: 'penaltyPoints', label: '违章扣分（分）', width: 150 },
    {
      prop: 'fineAmount',
      label: '违章罚款（元）',
      width: 150,
      formatter: (row) => formatMoney(row.fineAmount)
    },
    {
      prop: 'processed',
      label: '是否处理',
      width: 120,
      dict: {
        code: 'vehicleRecordProcessed',
        display: 'auto',
        value: (row) => String(row.processed)
      }
    }
  ]
</script>
