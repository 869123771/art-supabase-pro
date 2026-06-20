<template>
  <div class="vehicle-part-usage-detail" v-loading="page.loading">
    <div class="vehicle-part-usage-detail__header">
      <div>
        <h2>{{ detail.data?.plateNo || '零部件详情' }}</h2>
        <p>{{ detail.data?.partName || '--' }}</p>
      </div>
      <ElButton @click="goBack">返回</ElButton>
    </div>

    <div class="vehicle-part-usage-detail__content">
      <section>
        <ArtSectionTitle>零部件信息</ArtSectionTitle>
        <ElDescriptions :column="3" border>
          <ElDescriptionsItem label="车牌号">{{ value(detail.data?.plateNo) }}</ElDescriptionsItem>
          <ElDescriptionsItem label="所属公司">
            {{ value(detail.data?.companyName) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="零部件类型">
            <ArtDictDisplay
              dict-code="vehiclePartType"
              :value="detail.data?.partType"
              display="auto"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="零部件名称">
            {{ value(detail.data?.partName) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="零部件编码">
            {{ value(detail.data?.partCode) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="零部件类别">
            {{ value(detail.data?.categoryName) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="品牌">{{ value(detail.data?.brand) }}</ElDescriptionsItem>
          <ElDescriptionsItem label="型号">{{ value(detail.data?.model) }}</ElDescriptionsItem>
          <ElDescriptionsItem label="单位">{{ value(detail.data?.unit) }}</ElDescriptionsItem>
          <ElDescriptionsItem label="是否易损/耗件">
            <ArtDictDisplay
              dict-code="commonBoolean"
              :value="getBooleanDictValue(detail.data?.isConsumable)"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="品质分类">
            <ArtDictDisplay
              dict-code="vehiclePartQualityCategory"
              :value="detail.data?.qualityCategory"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="生产厂商">
            {{ value(detail.data?.manufacturer) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="供应厂商">
            {{ value(detail.data?.supplierName) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="供应厂商联系人" :span="2">
            {{ value(detail.data?.supplierContact) }}
          </ElDescriptionsItem>
        </ElDescriptions>
      </section>

      <section>
        <ArtSectionTitle>零部件使用</ArtSectionTitle>
        <ElDescriptions :column="3" border>
          <ElDescriptionsItem label="RFID标签">
            {{ detail.data?.rfidEnabled ? value(detail.data?.rfidTag) : '否' }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="启用日期">
            {{ value(detail.data?.enableDate) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="质保期">{{ warrantyText }}</ElDescriptionsItem>
          <ElDescriptionsItem label="使用寿命" :span="2">
            {{ serviceLifeText }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="已使用里程">
            {{ numberWithUnit(detail.data?.usedMileage, '公里') }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="状态">
            <ArtDictDisplay
              dict-code="vehiclePartUsageStatus"
              :value="detail.data?.status"
              display="auto"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem v-if="detail.data?.status === 'scrapped'" label="报废原因" :span="2">
            {{ value(detail.data?.scrapReason) }}
          </ElDescriptionsItem>
          <ElDescriptionsItem label="备注" :span="3">
            {{ value(detail.data?.remark) }}
          </ElDescriptionsItem>
        </ElDescriptions>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { ElButton, ElDescriptions, ElDescriptionsItem } from 'element-plus'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { fetchVehiclePartUsageDetail } from '@/api/vehicle-manage-system'

  defineOptions({ name: 'VehiclePartUsageDetail' })

  type Usage = Api.VehicleMgtSys.VehicleManage.VehiclePartUsage

  const route = useRoute()
  const router = useRouter()
  const page = reactive({ loading: false })
  const detail = reactive<{ data?: Usage }>({ data: undefined })

  const warrantyText = computed(() => {
    if (detail.data?.warrantyMode === 'vehicle') return '随整车质保'
    return (
      [
        detail.data?.warrantyMileage ? `${detail.data.warrantyMileage}公里` : '',
        detail.data?.warrantyDuration ? `${detail.data.warrantyDuration}个月` : ''
      ]
        .filter(Boolean)
        .join(' / ') || '--'
    )
  })

  const serviceLifeText = computed(() => {
    return (
      [
        detail.data?.serviceMileageEnabled && detail.data.serviceMileage
          ? `使用里程 ${detail.data.serviceMileage} 公里`
          : '',
        detail.data?.serviceYearsEnabled && detail.data.serviceYears
          ? `使用年限 ${detail.data.serviceYears} 年`
          : ''
      ]
        .filter(Boolean)
        .join(' / ') || '--'
    )
  })

  onMounted(() => {
    void loadDetail()
  })

  const loadDetail = async (): Promise<void> => {
    const id = String(route.params.id || '')
    if (!id) return
    page.loading = true
    try {
      const { data } = await fetchVehiclePartUsageDetail(id)
      detail.data = data ?? undefined
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vehicle-manage-system/vehicle-manage/part-manage')
  }

  const value = (data?: string | number | null): string => {
    if (data === undefined || data === null || data === '') return '--'
    return String(data)
  }

  const numberWithUnit = (data: number | null | undefined, unit: string): string => {
    if (data === undefined || data === null) return '--'
    return `${data}${unit}`
  }

  const getBooleanDictValue = (value?: boolean | null): string | undefined =>
    value === undefined || value === null ? undefined : String(value)
</script>

<style scoped lang="scss">
  .vehicle-part-usage-detail {
    min-height: 100%;
    padding: 16px;
    background: var(--art-main-bg-color);

    &__header,
    &__content {
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-light);
      border-radius: 8px;
    }

    &__header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 18px 20px;

      h2 {
        margin: 0;
        font-size: 20px;
      }

      p {
        margin: 6px 0 0;
        color: var(--el-text-color-secondary);
      }
    }

    &__content {
      padding: 20px;
      margin-top: 12px;

      section + section {
        margin-top: 24px;
      }
    }

    :deep(.el-descriptions__label) {
      width: 138px;
      font-weight: 600;
    }

    @media (max-width: 900px) {
      :deep(.el-descriptions__body .el-descriptions__table) {
        table-layout: auto;
      }
    }
  }
</style>
