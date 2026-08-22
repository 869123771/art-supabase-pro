<template>
  <ArtPageSection :card="false" title="司机管理">
    <VehicleQueryTable :data="drivers" :columns="columns" />
  </ArtPageSection>
</template>

<script setup lang="ts">
  import type { ColumnOption } from '@/types'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehicleDriver } from './types'
  import { canViewField } from '@/utils/field-permission'

  defineOptions({ name: 'VehicleQueryDriverPanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const drivers = computed<VehicleDriver[]>(() =>
    [props.vehicle.primaryDriver, props.vehicle.secondaryDriver].filter(
      (driver): driver is VehicleDriver => Boolean(driver?.id)
    )
  )

  const columns = computed<ColumnOption<VehicleDriver>[]>(() => [
    { type: 'globalIndex', label: '序号', width: 70 },
    { prop: 'driverName', label: '司机姓名', minWidth: 140 },
    {
      prop: 'driverType',
      label: '司机类型',
      width: 110,
      dict: { code: 'tmsDriverType', display: 'tag' }
    },
    ...(drivers.value.some((driver) => canViewField(driver.fieldAccess, 'contactPhone'))
      ? [
          {
            prop: 'phone',
            label: '联系电话',
            width: 160,
            formatter: (row: VehicleDriver) =>
              canViewField(row.fieldAccess, 'contactPhone') ? row.phone || '--' : '--'
          } satisfies ColumnOption<VehicleDriver>
        ]
      : []),
    {
      prop: 'licenseType',
      label: '驾照类型',
      width: 120,
      dict: { code: 'tmsDriverLicenseType', display: 'auto' }
    },
    {
      prop: 'enabled',
      label: '状态',
      width: 100,
      dict: { code: 'commonBoolean', display: 'tag', value: (row) => String(row.enabled) }
    }
  ])
</script>
