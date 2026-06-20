<template>
  <div class="vehicle-insurance-detail" v-loading="page.loading">
    <div class="vehicle-insurance-detail__header">
      <div>
        <h2>{{ detail.data?.plateNo || '车辆保险详情' }}</h2>
        <p>{{ detail.data?.companyName || '--' }}</p>
      </div>
      <div class="vehicle-insurance-detail__actions">
        <ElButton @click="goBack">返回</ElButton>
      </div>
    </div>

    <section class="vehicle-insurance-detail__summary">
      <div class="vehicle-insurance-detail__summary-item">
        <span>商业险到期</span>
        <strong>{{ formatValue(detail.data?.commercialExpireDate) }}</strong>
      </div>
      <div class="vehicle-insurance-detail__summary-item">
        <span>交强险到期</span>
        <strong>{{ formatValue(detail.data?.compulsoryExpireDate) }}</strong>
      </div>
      <div class="vehicle-insurance-detail__summary-item">
        <span>附件数量</span>
        <strong>{{ detail.data?.attachments?.length ?? 0 }}</strong>
      </div>
    </section>

    <div class="vehicle-insurance-detail__content">
      <section class="vehicle-insurance-detail__section">
        <ArtSectionTitle>保险信息</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="车牌号">{{
            formatValue(detail.data?.plateNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="所属公司">{{
            formatValue(detail.data?.companyName)
          }}</ElDescriptionsItem>
        </ElDescriptions>
      </section>

      <div class="vehicle-insurance-detail__insurance-grid">
        <section class="vehicle-insurance-detail__section">
          <ArtSectionTitle>商业险</ArtSectionTitle>
          <ElDescriptions :column="1" border>
            <ElDescriptionsItem label="保单号">
              {{ formatValue(detail.data?.commercialPolicyNo) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="保险公司">
              {{ formatValue(detail.data?.commercialCompanyName) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="投保日期">
              {{ formatValue(detail.data?.commercialInsureDate) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="投保金额">
              {{ formatMoney(detail.data?.commercialPremium) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="到期日期">
              {{ formatValue(detail.data?.commercialExpireDate) }}
            </ElDescriptionsItem>
          </ElDescriptions>
        </section>

        <section class="vehicle-insurance-detail__section">
          <ArtSectionTitle>交强险</ArtSectionTitle>
          <ElDescriptions :column="1" border>
            <ElDescriptionsItem label="保单号">
              {{ formatValue(detail.data?.compulsoryPolicyNo) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="保险公司">
              {{ formatValue(detail.data?.compulsoryCompanyName) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="投保日期">
              {{ formatValue(detail.data?.compulsoryInsureDate) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="投保金额">
              {{ formatMoney(detail.data?.compulsoryPremium) }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="到期日期">
              {{ formatValue(detail.data?.compulsoryExpireDate) }}
            </ElDescriptionsItem>
          </ElDescriptions>
        </section>
      </div>

      <section class="vehicle-insurance-detail__section">
        <ArtSectionTitle>备注</ArtSectionTitle>
        <div class="vehicle-insurance-detail__remark">{{ formatValue(detail.data?.remark) }}</div>
      </section>

      <section class="vehicle-insurance-detail__section">
        <ArtSectionTitle>保险附件</ArtSectionTitle>
        <ArtTable
          :data="detail.data?.attachments ?? []"
          :columns="attachmentColumns"
          :pagination="undefined"
          :show-table-header="false"
          empty-height="180px"
        />
      </section>
    </div>
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElDescriptions, ElDescriptionsItem } from 'element-plus'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleInsuranceDetail } from '@/api/vehicle-manage-system'
  import { downloadAttachment } from '@/utils/file'

  defineOptions({ name: 'VehicleInsuranceDetail' })

  type VehicleInsurance = Api.VehicleMgtSys.VehicleManage.VehicleInsurance
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive({ loading: false })
  const detail = reactive<{ data?: VehicleInsurance }>({ data: undefined })

  const attachmentColumns: ColumnOption<Attachment>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'name', label: '附件名称', minWidth: 240 },
    {
      prop: 'fileType',
      label: '格式类型',
      width: 120,
      dict: { code: 'FILE_EXTENSION_LABEL_MAP', display: 'text' }
    },
    { prop: 'fileSize', label: '附件大小', width: 120 },
    {
      prop: 'operation',
      label: '操作',
      width: 64,
      formatter: (row) => (
        <div class="flex items-center">
          <ArtIconButton icon="ri:download-2-line" onClick={() => downloadAttachment(row)} />
        </div>
      )
    }
  ]

  onMounted(() => {
    void loadDetail()
  })

  const loadDetail = async (): Promise<void> => {
    const id = String(route.params.id || '')
    if (!id) return
    page.loading = true
    try {
      const { data } = await fetchVehicleInsuranceDetail(id)
      detail.data = data ? { ...data, attachments: data.attachments ?? [] } : undefined
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vehicle-manage-system/vehicle-manage/vehicle-insurance')
  }

  const formatValue = (value?: string | number | null): string => {
    if (value === undefined || value === null || value === '') return '--'
    return String(value)
  }

  const formatMoney = (value?: number | null): string => {
    if (value === undefined || value === null) return '--'
    return `${Number(value).toFixed(2)} 元`
  }
</script>

<style scoped lang="scss">
  .vehicle-insurance-detail {
    min-height: 100%;
    padding: 16px;
    background: var(--art-main-bg-color);

    &__header,
    &__summary,
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
        font-weight: 600;
      }

      p {
        margin: 6px 0 0;
        color: var(--el-text-color-secondary);
      }
    }

    &__summary {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 1px;
      padding: 16px;
      margin-top: 12px;
    }

    &__summary-item {
      display: flex;
      flex-direction: column;
      gap: 8px;
      min-width: 0;

      span {
        color: var(--el-text-color-secondary);
      }

      strong {
        font-size: 18px;
        font-weight: 600;
        overflow-wrap: anywhere;
      }
    }

    &__content {
      padding: 20px;
      margin-top: 12px;
    }

    &__content > &__section + &__section,
    &__content > &__insurance-grid + &__section {
      margin-top: 22px;
    }

    &__insurance-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 16px;
      margin-top: 22px;
    }

    &__remark {
      min-height: 48px;
      padding: 12px 14px;
      line-height: 1.7;
      color: var(--el-text-color-regular);
      background: var(--el-fill-color-lighter);
      border-radius: 6px;
      overflow-wrap: anywhere;
    }

    :deep(.el-descriptions__label) {
      width: 128px;
      font-weight: 600;
    }

    @media (max-width: 900px) {
      &__summary,
      &__insurance-grid {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
