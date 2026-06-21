<template>
  <div class="vehicle-query-summary art-card-xs">
    <div class="vehicle-query-summary__photo">
      <ElImage
        v-if="vehicle.vehiclePhotoUrl"
        :src="vehicle.vehiclePhotoUrl"
        fit="cover"
        :preview-src-list="[vehicle.vehiclePhotoUrl]"
      />
      <div v-else class="vehicle-query-summary__photo-empty">
        <IconifyIconOnline icon="ri:bus-2-line" />
      </div>
    </div>

    <VehicleQueryInfoGrid :items="summaryItems" />
  </div>
</template>

<script setup lang="ts">
  import { ElImage } from 'element-plus'
  import VehicleQueryInfoGrid from './vehicle-query-info-grid.vue'
  import type { InfoItem, VehicleArchive, VehicleQuerySummary } from './types'
  import { formatDate, formatMileage, formatNumber } from './query-format'

  defineOptions({ name: 'VehicleQuerySummary' })

  const props = defineProps<{
    vehicle: VehicleArchive
    summary: VehicleQuerySummary
  }>()

  const summaryItems = computed<InfoItem[]>(() => [
    { label: '车牌号', value: props.vehicle.plateNo },
    { label: '所属机构', value: props.vehicle.companyName },
    { label: '车型', value: props.vehicle.vehicleType, dictCode: 'vehicleType' },
    { label: '车型厂商', value: props.vehicle.manufacturer },
    { label: '车架号', value: props.vehicle.vin },
    { label: '购入开票日期', value: formatDate(props.vehicle.invoiceDate) },
    { label: '启用日期', value: formatDate(props.vehicle.startUseDate) },
    { label: '运营状态', value: props.vehicle.operationStatus, dictCode: 'vehicleOperationStatus' },
    { label: '运营时长', value: getOperationYears(), suffix: '年' },
    { label: '运营行驶里程', value: formatMileage(props.summary.runningMileage) },
    { label: '商业险到期', value: formatDate(props.summary.commercialExpireDate) },
    { label: '交强险到期', value: formatDate(props.summary.compulsoryExpireDate) },
    { label: '年检到期', value: formatDate(props.summary.inspectionExpireDate) },
    { label: '下次保养里程', value: formatMileage(props.summary.nextMaintenanceMileage) },
    { label: '下次保养时间', value: formatDate(props.summary.nextMaintenanceDate) }
  ])

  const getOperationYears = (): string => {
    if (!props.vehicle.startUseDate) return '--'
    const startTime = new Date(props.vehicle.startUseDate).getTime()
    if (Number.isNaN(startTime)) return '--'
    const years = Math.max(0, (Date.now() - startTime) / (365.25 * 24 * 60 * 60 * 1000))
    return formatNumber(Number(years.toFixed(1)))
  }
</script>

<style scoped lang="scss">
  .vehicle-query-summary {
    display: grid;
    grid-template-columns: 220px minmax(0, 1fr);
    gap: 28px;
    padding: 24px;

    &__photo {
      width: 220px;
      height: 150px;

      :deep(.el-image) {
        width: 100%;
        height: 100%;
      }
    }

    &__photo-empty {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 100%;
      height: 100%;
      font-size: 56px;
      color: var(--el-text-color-placeholder);
      background: var(--el-fill-color-light);
    }
  }

  @media (width <= 900px) {
    .vehicle-query-summary {
      grid-template-columns: 1fr;

      &__photo {
        width: 100%;
        max-width: 260px;
      }
    }
  }
</style>
