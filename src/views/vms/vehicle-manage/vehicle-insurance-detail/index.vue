<template>
  <ArtPageShell
    class="vehicle-insurance-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无车辆保险详情"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.plateNo || '车辆保险详情'"
      :subtitle="detail.data?.companyName || '--'"
      show-back
      @back="goBack"
    />

    <section class="vehicle-insurance-detail__summary art-card-xs">
      <div v-if="canViewInsuranceField('documents')" class="vehicle-insurance-detail__summary-item">
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

    <div class="vehicle-insurance-detail__content art-card-xs">
      <section v-if="canViewInsuranceField('documents')" class="vehicle-insurance-detail__section">
        <ArtSectionTitle>保险信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="vehicleItems" :columns="2" />
      </section>

      <div class="vehicle-insurance-detail__insurance-grid">
        <section class="vehicle-insurance-detail__section">
          <ArtSectionTitle>商业险</ArtSectionTitle>
          <ArtDescriptions :data="descriptionData" :items="commercialItems" :columns="1" />
        </section>

        <section class="vehicle-insurance-detail__section">
          <ArtSectionTitle>交强险</ArtSectionTitle>
          <ArtDescriptions :data="descriptionData" :items="compulsoryItems" :columns="1" />
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
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleInsuranceDetail } from '@/api/vms'
  import { downloadAttachment } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import { canViewField, formatSensitiveNumber } from '@/utils/field-permission'

  defineOptions({ name: 'VehicleInsuranceDetail' })

  type VehicleInsurance = Api.Vms.VehicleManage.VehicleInsurance
  type Attachment = Api.Vms.VehicleManage.VehicleAttachment
  type InsuranceFieldKey = Api.Vms.VehicleManage.VehicleInsuranceFieldKey

  const route = useRoute()
  const router = useRouter()
  const page = reactive<{ loading: boolean; error: Error | null }>({ loading: false, error: null })
  const detail = reactive<{ data?: VehicleInsurance }>({ data: undefined })
  const descriptionData = computed<Partial<VehicleInsurance>>(() => detail.data ?? {})
  const canViewInsuranceField = (field: InsuranceFieldKey): boolean =>
    canViewField(detail.data?.fieldAccess, field)
  const vehicleItems: ArtDescriptionItem<Partial<VehicleInsurance>>[] = [
    { key: 'plateNo', label: '车牌号', field: 'plateNo' },
    { key: 'companyName', label: '所属公司', field: 'companyName' }
  ]
  const commercialItems = computed<ArtDescriptionItem<Partial<VehicleInsurance>>[]>(() => [
    ...(canViewInsuranceField('policyNumbers')
      ? [
          {
            key: 'commercialPolicyNo',
            label: '保单号',
            field: 'commercialPolicyNo',
            copyable: true
          } as ArtDescriptionItem<Partial<VehicleInsurance>>
        ]
      : []),
    { key: 'commercialCompanyName', label: '保险公司', field: 'commercialCompanyName' },
    {
      key: 'commercialInsureDate',
      label: '投保日期',
      field: 'commercialInsureDate',
      format: 'date'
    },
    ...(canViewInsuranceField('premiumAmounts')
      ? [
          {
            key: 'commercialPremium',
            label: '投保金额',
            field: 'commercialPremium',
            formatter: (value) => formatMoney(value as number | string | null | undefined)
          } as ArtDescriptionItem<Partial<VehicleInsurance>>
        ]
      : []),
    {
      key: 'commercialExpireDate',
      label: '到期日期',
      field: 'commercialExpireDate',
      format: 'date'
    }
  ])
  const compulsoryItems = computed<ArtDescriptionItem<Partial<VehicleInsurance>>[]>(() => [
    ...(canViewInsuranceField('policyNumbers')
      ? [
          {
            key: 'compulsoryPolicyNo',
            label: '保单号',
            field: 'compulsoryPolicyNo',
            copyable: true
          } as ArtDescriptionItem<Partial<VehicleInsurance>>
        ]
      : []),
    { key: 'compulsoryCompanyName', label: '保险公司', field: 'compulsoryCompanyName' },
    {
      key: 'compulsoryInsureDate',
      label: '投保日期',
      field: 'compulsoryInsureDate',
      format: 'date'
    },
    ...(canViewInsuranceField('premiumAmounts')
      ? [
          {
            key: 'compulsoryPremium',
            label: '投保金额',
            field: 'compulsoryPremium',
            formatter: (value) => formatMoney(value as number | string | null | undefined)
          } as ArtDescriptionItem<Partial<VehicleInsurance>>
        ]
      : []),
    {
      key: 'compulsoryExpireDate',
      label: '到期日期',
      field: 'compulsoryExpireDate',
      format: 'date'
    }
  ])

  const attachmentColumns: ColumnOption<Attachment>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'name', label: '附件名称', minWidth: 240, formatter: renderAttachmentLink },
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
    if (!id) {
      page.error = new Error('缺少保险记录标识')
      return
    }
    page.loading = true
    page.error = null
    try {
      const { data } = await fetchVehicleInsuranceDetail(id)
      detail.data = data ? { ...data, attachments: data.attachments ?? [] } : undefined
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('车辆保险详情加载失败')
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vms/vehicle-manage/vehicle-insurance')
  }

  const formatValue = (value?: string | number | null): string => {
    if (value === undefined || value === null || value === '') return '--'
    return String(value)
  }

  const formatMoney = (value?: number | string | null): string => {
    const formatted = formatSensitiveNumber(value)
    return formatted === '--' || formatted === '***' ? formatted : `${formatted} 元`
  }
</script>

<style scoped lang="scss">
  .vehicle-insurance-detail {
    min-height: 100%;
    padding: 16px;
    background: var(--art-main-bg-color);

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
      overflow-wrap: anywhere;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 128px;
      font-weight: 600;
    }

    @media (width <= 900px) {
      &__summary,
      &__insurance-grid {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
