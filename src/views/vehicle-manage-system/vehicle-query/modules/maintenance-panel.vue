<template>
  <ArtPageSection :card="false" title="维修保养记录">
    <template #actions>
      <ElSelect
        v-model="panel.maintenanceType"
        clearable
        placeholder="维修类型"
        style="width: 180px"
      >
        <ElOption label="维修" value="repair" />
        <ElOption label="保养" value="maintenance" />
      </ElSelect>
    </template>
    <VehicleQueryTable :data="filteredRecords" :columns="columns" :loading="loading" />
  </ArtPageSection>
</template>

<script setup lang="tsx">
  import { ElOption, ElSelect } from 'element-plus'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleMaintenanceList } from '@/api/vehicle-manage-system'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehicleMaintenanceRecord } from './types'
  import { formatDateTime, formatMoney } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'

  defineOptions({ name: 'VehicleQueryMaintenancePanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const panel = reactive({
    maintenanceType: ''
  })

  const { loading, records } = useVehiclePanelList<VehicleMaintenanceRecord>(
    vehicle,
    async (current) => {
      const { data } = await fetchVehicleMaintenanceList({
        plateNo: current.plateNo,
        from: 0,
        to: 9999
      })
      return data ?? []
    }
  )

  const filteredRecords = computed(() =>
    panel.maintenanceType
      ? records.value.filter((item) => item.maintenanceType === panel.maintenanceType)
      : records.value
  )

  const columns: ColumnOption<VehicleMaintenanceRecord>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'maintenanceNo', label: '维修单号', minWidth: 160 },
    {
      prop: 'maintenanceType',
      label: '维修类别',
      minWidth: 130,
      dict: { code: 'vehicleMaintenanceType', display: 'auto' }
    },
    { prop: 'initiator', label: '发起人', minWidth: 130 },
    {
      prop: 'startTime',
      label: '维修保养时间',
      minWidth: 180,
      formatter: (row) => formatDateTime(row.startTime)
    },
    {
      prop: 'endTime',
      label: '结束时间',
      minWidth: 180,
      formatter: (row) => formatDateTime(row.endTime)
    },
    {
      prop: 'costAmount',
      label: '费用（元）',
      minWidth: 130,
      formatter: (row) => formatMoney(row.costAmount)
    }
  ]
</script>
