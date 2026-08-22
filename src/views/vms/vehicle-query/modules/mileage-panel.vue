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
  import { formatDateTime } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'
  import {
    canViewField,
    formatSensitiveNumber,
    mergeFieldAccessMaps
  } from '@/utils/field-permission'

  defineOptions({ name: 'VehicleQueryMileagePanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const { loading, records } = useVehiclePanelList<VehicleMileageRecord>(
    vehicle,
    async (current) => {
      const { data } = await fetchVehicleMileageList({
        vehicleId: current.id,
        from: 0,
        to: 9999
      })
      return data ?? []
    }
  )

  const effectiveFieldAccess = computed(() =>
    mergeFieldAccessMaps(...records.value.map((record) => record.fieldAccess))
  )

  const formatMileage = (value?: number | string | null): string =>
    formatSensitiveNumber(value, { maximumFractionDigits: 2 })

  const formatMileageTime = (value?: string | null): string =>
    value === '***' ? value : formatDateTime(value)

  const columns = computed<ColumnOption<VehicleMileageRecord>[]>(() => [
    { type: 'globalIndex', label: '序号', width: 80 },
    ...(canViewField(effectiveFieldAccess.value, 'mileageValues')
      ? [
          {
            prop: 'runningMileage',
            label: '运营行驶里程（公里）',
            minWidth: 180,
            formatter: (row: VehicleMileageRecord) => formatMileage(row.runningMileage)
          }
        ]
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'tripTimeline')
      ? [
          {
            prop: 'startTime',
            label: '开始时间',
            minWidth: 180,
            formatter: (row: VehicleMileageRecord) => formatMileageTime(row.startTime)
          }
        ]
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'mileageValues')
      ? [
          {
            prop: 'startMileage',
            label: '开始里程（公里）',
            minWidth: 170,
            formatter: (row: VehicleMileageRecord) => formatMileage(row.startMileage)
          }
        ]
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'tripTimeline')
      ? [
          {
            prop: 'endTime',
            label: '结束时间',
            minWidth: 180,
            formatter: (row: VehicleMileageRecord) => formatMileageTime(row.endTime)
          }
        ]
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'mileageValues')
      ? [
          {
            prop: 'endMileage',
            label: '结束里程（公里）',
            minWidth: 170,
            formatter: (row: VehicleMileageRecord) => formatMileage(row.endMileage)
          }
        ]
      : [])
  ])
</script>
