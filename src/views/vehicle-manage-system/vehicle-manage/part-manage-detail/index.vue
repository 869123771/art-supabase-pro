<template>
  <ArtPageShell
    class="vehicle-part-usage-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无零部件详情"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.plateNo || '零部件详情'"
      :subtitle="detail.data?.partName || '--'"
      show-back
      @back="goBack"
    />

    <section class="vehicle-part-usage-detail__summary art-card-xs">
      <div class="vehicle-part-usage-detail__summary-item">
        <span>零部件状态</span>
        <strong>
          <ArtDictDisplay
            dict-code="vehiclePartUsageStatus"
            :value="detail.data?.status"
            display="auto"
          />
        </strong>
      </div>
      <div class="vehicle-part-usage-detail__summary-item">
        <span>RFID 标签</span>
        <strong>{{ detail.data?.rfidTag || '待绑定' }}</strong>
      </div>
      <div class="vehicle-part-usage-detail__summary-item">
        <span>启用日期</span>
        <strong>{{ detail.data?.enableDate || '--' }}</strong>
      </div>
      <div class="vehicle-part-usage-detail__summary-item">
        <span>已使用里程</span>
        <strong>{{ formatMileage(detail.data?.usedMileage) }}</strong>
      </div>
    </section>

    <div class="vehicle-part-usage-detail__content art-card-xs">
      <section>
        <ArtSectionTitle>零部件信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="partItems" :columns="3" />
      </section>

      <section>
        <ArtSectionTitle>零部件使用</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="usageItems" :columns="3" />
      </section>
    </div>
  </ArtPageShell>
</template>

<script setup lang="ts">
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import { fetchVehiclePartUsageDetail } from '@/api/vehicle-manage-system'

  defineOptions({ name: 'VehiclePartUsageDetail' })

  type Usage = Api.VehicleMgtSys.VehicleManage.VehiclePartUsage

  const route = useRoute()
  const router = useRouter()
  const page = reactive<{ loading: boolean; error: Error | null }>({ loading: false, error: null })
  const detail = reactive<{ data?: Usage }>({ data: undefined })
  const descriptionData = computed<Partial<Usage>>(() => detail.data ?? {})

  const formatMileage = (value?: number | null): string =>
    value === undefined || value === null ? '--' : `${Number(value).toLocaleString()} km`

  const partItems: ArtDescriptionItem<Partial<Usage>>[] = [
    { key: 'plateNo', label: '车牌号', field: 'plateNo' },
    { key: 'companyName', label: '所属公司', field: 'companyName' },
    { key: 'partType', label: '零部件类型', field: 'partType', dictCode: 'vehiclePartType' },
    { key: 'partName', label: '零部件名称', field: 'partName' },
    { key: 'partCode', label: '零部件编码', field: 'partCode', copyable: true },
    { key: 'categoryName', label: '零部件类别', field: 'categoryName' },
    { key: 'brand', label: '品牌', field: 'brand' },
    { key: 'model', label: '型号', field: 'model' },
    { key: 'unit', label: '单位', field: 'unit' },
    {
      key: 'isConsumable',
      label: '是否易损/耗件',
      value: (data: Partial<Usage>) => getBooleanDictValue(data.isConsumable),
      dictCode: 'commonBoolean',
      dictDisplay: 'text'
    },
    {
      key: 'qualityCategory',
      label: '品质分类',
      field: 'qualityCategory',
      dictCode: 'vehiclePartQualityCategory',
      dictDisplay: 'text'
    },
    { key: 'manufacturer', label: '生产厂商', field: 'manufacturer' },
    { key: 'supplierName', label: '供应厂商', field: 'supplierName' },
    { key: 'supplierContact', label: '供应厂商联系人', field: 'supplierContact', span: 2 }
  ]

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

  const usageItems = computed<ArtDescriptionItem<Partial<Usage>>[]>(() => [
    {
      key: 'rfidTag',
      label: 'RFID标签',
      value: (data: Partial<Usage>) => (data.rfidEnabled ? data.rfidTag : '否')
    },
    { key: 'enableDate', label: '启用日期', field: 'enableDate', format: 'date' },
    { key: 'warranty', label: '质保期', value: warrantyText.value },
    { key: 'serviceLife', label: '使用寿命', value: serviceLifeText.value, span: 2 },
    {
      key: 'usedMileage',
      label: '已使用里程',
      field: 'usedMileage',
      formatter: (value) => numberWithUnit(value as number | null | undefined, '公里')
    },
    {
      key: 'status',
      label: '状态',
      field: 'status',
      dictCode: 'vehiclePartUsageStatus'
    },
    ...(detail.data?.status === 'scrapped'
      ? [{ key: 'scrapReason', label: '报废原因', field: 'scrapReason', span: 2 }]
      : []),
    { key: 'remark', label: '备注', field: 'remark', span: 3 }
  ])

  onMounted(() => {
    void loadDetail()
  })

  const loadDetail = async (): Promise<void> => {
    const id = String(route.params.id || '')
    if (!id) {
      page.error = new Error('缺少零部件使用记录标识')
      return
    }
    page.loading = true
    page.error = null
    try {
      const { data } = await fetchVehiclePartUsageDetail(id)
      detail.data = data ?? undefined
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('零部件详情加载失败')
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vehicle-manage-system/vehicle-manage/part-manage')
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

    &__content {
      padding: 20px;
      margin-top: 12px;

      section + section {
        margin-top: 24px;
      }
    }

    &__summary {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      margin-top: 12px;
    }

    &__summary-item {
      display: grid;
      gap: 4px;
      min-width: 0;
      padding: 16px 20px;

      &:not(:last-child) {
        border-right: 1px solid var(--el-border-color-lighter);
      }

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 18px;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-primary);
        white-space: nowrap;
      }
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 138px;
      font-weight: 600;
    }

    @media (width <= 900px) {
      :deep(.art-descriptions .el-descriptions__body .el-descriptions__table) {
        table-layout: auto;
      }
    }

    @media (width <= 720px) {
      &__summary {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__summary-item:nth-child(2) {
        border-right: 0;
      }

      &__summary-item:nth-child(-n + 2) {
        border-bottom: 1px solid var(--el-border-color-lighter);
      }
    }
  }
</style>
