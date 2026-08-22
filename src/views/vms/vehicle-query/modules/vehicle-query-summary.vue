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

    <div class="vehicle-query-summary__main">
      <header class="vehicle-query-summary__header">
        <div>
          <span>车辆综合档案</span>
          <small>汇总车辆合规、运营和维保关键数据</small>
        </div>
        <ElButton v-auth="'VehicleQuery:AiAnalyze'" type="primary" plain @click="emit('analyze')">
          <ArtSvgIcon icon="ri:sparkling-2-line" />AI 车辆健康研判
        </ElButton>
      </header>
      <ArtDescriptions :data="descriptionData" :items="descriptionItems" />
    </div>
  </div>
</template>

<script setup lang="ts">
  import { ElButton, ElImage } from 'element-plus'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import type { InfoItem, VehicleArchive, VehicleQuerySummary } from './types'
  import { createDescriptionItems, formatDate, formatMileage, formatNumber } from './query-format'
  import { canViewField } from '@/utils/field-permission'

  defineOptions({ name: 'VehicleQuerySummary' })

  const props = defineProps<{
    vehicle: VehicleArchive
    summary: VehicleQuerySummary
  }>()
  const emit = defineEmits<{ analyze: [] }>()
  const descriptionData = Object.freeze({})

  const descriptionItems = computed(() =>
    createDescriptionItems([
      { label: '车牌号', value: props.vehicle.plateNo },
      { label: '所属机构', value: props.vehicle.companyName },
      { label: '车型', value: props.vehicle.vehicleType, dictCode: 'vehicleType' },
      { label: '车型厂商', value: props.vehicle.manufacturer },
      ...(canViewField(props.vehicle.fieldAccess, 'vehicleIdentifiers')
        ? [{ label: '车架号', value: props.vehicle.vin }]
        : []),
      { label: '购入开票日期', value: formatDate(props.vehicle.invoiceDate) },
      { label: '启用日期', value: formatDate(props.vehicle.startUseDate) },
      {
        label: '运营状态',
        value: props.vehicle.operationStatus,
        dictCode: 'vehicleOperationStatus'
      },
      { label: '运营时长', value: getOperationYears(), suffix: '年' },
      { label: '运营行驶里程', value: formatMileage(props.summary.runningMileage) },
      { label: '商业险到期', value: formatDate(props.summary.commercialExpireDate) },
      { label: '交强险到期', value: formatDate(props.summary.compulsoryExpireDate) },
      { label: '年检到期', value: formatDate(props.summary.inspectionExpireDate) },
      { label: '下次保养里程', value: formatMileage(props.summary.nextMaintenanceMileage) },
      { label: '下次保养时间', value: formatDate(props.summary.nextMaintenanceDate) }
    ] satisfies InfoItem[])
  )

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

    &__main {
      display: grid;
      gap: 14px;
      min-width: 0;
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 128px;
      font-weight: 600;
      color: var(--el-text-color-primary);
      background: var(--el-fill-color-lighter);
    }

    :deep(.art-descriptions .el-descriptions__content) {
      min-width: 180px;
      color: var(--el-text-color-secondary);
      overflow-wrap: anywhere;
    }

    &__header {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      min-width: 0;

      > div {
        display: grid;
        gap: 3px;
        min-width: 0;
      }

      span {
        font-size: 16px;
        font-weight: 700;
        color: var(--el-text-color-primary);
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
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

  @media (width <= 640px) {
    .vehicle-query-summary {
      &__header {
        flex-direction: column;
        align-items: stretch;

        :deep(.el-button) {
          width: 100%;
        }
      }
    }
  }
</style>
