<template>
  <ArtPageSection :card="false" title="车辆保险">
    <VehicleQueryTable :data="records" :columns="columns" :loading="loading" />
  </ArtPageSection>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import { fetchVehicleInsuranceList } from '@/api/vms'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehicleInsurance } from './types'
  import { formatDate } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'
  import {
    canViewField,
    formatSensitiveNumber,
    mergeFieldAccessMaps
  } from '@/utils/field-permission'

  defineOptions({ name: 'VehicleQueryInsurancePanel' })

  const props = defineProps<{
    vehicle: VehicleArchive
  }>()

  const vehicle = toRef(props, 'vehicle')
  const { loading, records } = useVehiclePanelList<VehicleInsurance>(vehicle, async (current) => {
    const { data } = await fetchVehicleInsuranceList({
      plateNo: current.plateNo,
      from: 0,
      to: 9999
    })
    return data ?? []
  })

  const effectiveFieldAccess = computed(() =>
    mergeFieldAccessMaps(...records.value.map((row) => row.fieldAccess))
  )
  const formatPremium = (value?: number | string | null): string =>
    formatSensitiveNumber(value, { minimumFractionDigits: 1, maximumFractionDigits: 1 })

  const columns = computed<ColumnOption<VehicleInsurance>[]>(() => [
    { type: 'globalIndex', label: '序号', width: 70 },
    {
      label: '商业险',
      children: [
        ...(canViewField(effectiveFieldAccess.value, 'policyNumbers')
          ? [{ prop: 'commercialPolicyNo', label: '保单号', minWidth: 150 }]
          : []),
        { prop: 'commercialCompanyName', label: '保险公司', minWidth: 150 },
        {
          prop: 'commercialInsureDate',
          label: '投保日期',
          width: 120,
          formatter: (row) => formatDate(row.commercialInsureDate)
        },
        ...(canViewField(effectiveFieldAccess.value, 'premiumAmounts')
          ? [
              {
                prop: 'commercialPremium',
                label: '投保金额（元）',
                width: 140,
                formatter: (row: VehicleInsurance) => formatPremium(row.commercialPremium)
              }
            ]
          : []),
        {
          prop: 'commercialExpireDate',
          label: '到期日期',
          width: 120,
          formatter: (row) => formatDate(row.commercialExpireDate)
        }
      ]
    },
    {
      label: '交强险',
      children: [
        ...(canViewField(effectiveFieldAccess.value, 'policyNumbers')
          ? [{ prop: 'compulsoryPolicyNo', label: '保单号', minWidth: 150 }]
          : []),
        { prop: 'compulsoryCompanyName', label: '保险公司', minWidth: 150 },
        {
          prop: 'compulsoryInsureDate',
          label: '投保日期',
          width: 120,
          formatter: (row) => formatDate(row.compulsoryInsureDate)
        },
        ...(canViewField(effectiveFieldAccess.value, 'premiumAmounts')
          ? [
              {
                prop: 'compulsoryPremium',
                label: '投保金额（元）',
                width: 140,
                formatter: (row: VehicleInsurance) => formatPremium(row.compulsoryPremium)
              }
            ]
          : []),
        {
          prop: 'compulsoryExpireDate',
          label: '到期日期',
          width: 120,
          formatter: (row) => formatDate(row.compulsoryExpireDate)
        }
      ]
    }
  ])
</script>
