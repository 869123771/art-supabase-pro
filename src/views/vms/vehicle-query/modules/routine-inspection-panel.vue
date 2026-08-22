<template>
  <ArtPageSection :card="false" title="例检记录">
    <VehicleQueryTable :data="records" :columns="columns" :loading="loading" />
  </ArtPageSection>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import { fetchVehicleRoutineInspectionList } from '@/api/vms'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehicleRoutineInspectionRecord } from './types'
  import { formatDateTime } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'
  import { canViewField, mergeFieldAccessMaps } from '@/utils/field-permission'

  defineOptions({ name: 'VehicleQueryRoutineInspectionPanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const { loading, records } = useVehiclePanelList<VehicleRoutineInspectionRecord>(
    vehicle,
    async (current) => {
      const { data } = await fetchVehicleRoutineInspectionList({
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

  const columns = computed<ColumnOption<VehicleRoutineInspectionRecord>[]>(() => [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'routineInspectionNo', label: '例检单号', minWidth: 160 },
    {
      prop: 'inspectionType',
      label: '例检类型',
      minWidth: 130,
      dict: { code: 'vehicleRoutineInspectionType', display: 'auto' }
    },
    {
      prop: 'inspectionTime',
      label: '例检时间',
      minWidth: 180,
      formatter: (row) => formatDateTime(row.inspectionTime)
    },
    ...(canViewField(effectiveFieldAccess.value, 'responsiblePeople')
      ? ([
          { prop: 'inspector', label: '例检员', minWidth: 130 },
          { prop: 'driverName', label: '驾驶员姓名', minWidth: 140 }
        ] as ColumnOption<VehicleRoutineInspectionRecord>[])
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'inspectionFindings')
      ? ([
          { prop: 'checkCondition', label: '检查情况', minWidth: 160 },
          {
            prop: 'checkResult',
            label: '检查结果',
            minWidth: 130,
            dict: { code: 'vehicleRoutineInspectionResult', display: 'auto' }
          }
        ] as ColumnOption<VehicleRoutineInspectionRecord>[])
      : []),
    ...(canViewField(effectiveFieldAccess.value, 'remediationDetails')
      ? ([
          { prop: 'handlingMethod', label: '处理方式', minWidth: 160 }
        ] as ColumnOption<VehicleRoutineInspectionRecord>[])
      : [])
  ])
</script>
