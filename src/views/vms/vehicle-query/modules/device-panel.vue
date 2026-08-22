<template>
  <ArtPageSection :card="false" title="绑定设备">
    <VehicleQueryTable :data="records" :columns="columns" />
  </ArtPageSection>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive } from './types'
  import { formatValue } from './query-format'
  import { isNil } from 'lodash-es'
  import { canViewField } from '@/utils/field-permission'

  defineOptions({ name: 'VehicleQueryDevicePanel' })

  interface BoundDevice {
    id: string
    deviceId?: string
    deviceType?: string
    simNo?: string
    manufacturer?: string
    model?: string
    softwareVersion?: string
    hardwareVersion?: string
    hardwareNo?: string
  }

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const records = computed<BoundDevice[]>(() => {
    if (!canViewField(props.vehicle.fieldAccess, 'deviceIdentity')) return []
    if (isNil(props.vehicle.terminalPhone) || props.vehicle.terminalPhone === '') return []

    return [
      {
        id: props.vehicle.id ?? props.vehicle.plateNo,
        deviceId: props.vehicle.terminalPhone,
        deviceType: '车载终端',
        simNo: props.vehicle.terminalPhone
      }
    ]
  })

  const columns: ColumnOption<BoundDevice>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'deviceId', label: '设备ID', minWidth: 220 },
    { prop: 'deviceType', label: '设备类型', minWidth: 160 },
    { prop: 'simNo', label: 'SIM卡号', minWidth: 220 },
    {
      prop: 'manufacturer',
      label: '设备厂商',
      minWidth: 160,
      formatter: (row) => formatValue(row.manufacturer)
    },
    { prop: 'model', label: '设备型号', minWidth: 160, formatter: (row) => formatValue(row.model) },
    {
      prop: 'softwareVersion',
      label: '软件版本',
      minWidth: 140,
      formatter: (row) => formatValue(row.softwareVersion)
    },
    {
      prop: 'hardwareVersion',
      label: '硬件版本',
      minWidth: 140,
      formatter: (row) => formatValue(row.hardwareVersion)
    },
    {
      prop: 'hardwareNo',
      label: '硬件编号',
      minWidth: 160,
      formatter: (row) => formatValue(row.hardwareNo)
    }
  ]
</script>
