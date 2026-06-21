<template>
  <VehicleQuerySection title="车辆保险">
    <VehicleQueryTable :data="records" :columns="columns" :loading="loading" />
  </VehicleQuerySection>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import { fetchVehicleInsuranceList } from '@/api/vehicle-manage-system'
  import VehicleQuerySection from './vehicle-query-section.vue'
  import VehicleQueryTable from './vehicle-query-table.vue'
  import type { VehicleArchive, VehicleInsurance } from './types'
  import { formatDate, formatMoney } from './query-format'
  import { useVehiclePanelList } from './use-vehicle-panel-list'

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

  const columns: ColumnOption<VehicleInsurance>[] = [
    { type: 'globalIndex', label: '序号', width: 70 },
    {
      label: '商业险',
      children: [
        { prop: 'commercialPolicyNo', label: '保单号', minWidth: 150 },
        { prop: 'commercialCompanyName', label: '保险公司', minWidth: 150 },
        {
          prop: 'commercialInsureDate',
          label: '投保日期',
          width: 120,
          formatter: (row) => formatDate(row.commercialInsureDate)
        },
        {
          prop: 'commercialPremium',
          label: '投保金额（元）',
          width: 140,
          formatter: (row) => formatMoney(row.commercialPremium)
        },
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
        { prop: 'compulsoryPolicyNo', label: '保单号', minWidth: 150 },
        { prop: 'compulsoryCompanyName', label: '保险公司', minWidth: 150 },
        {
          prop: 'compulsoryInsureDate',
          label: '投保日期',
          width: 120,
          formatter: (row) => formatDate(row.compulsoryInsureDate)
        },
        {
          prop: 'compulsoryPremium',
          label: '投保金额（元）',
          width: 140,
          formatter: (row) => formatMoney(row.compulsoryPremium)
        },
        {
          prop: 'compulsoryExpireDate',
          label: '到期日期',
          width: 120,
          formatter: (row) => formatDate(row.compulsoryExpireDate)
        }
      ]
    }
  ]
</script>
