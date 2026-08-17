<template>
  <ArtPageShell
    class="vehicle-inspection-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无车辆年检详情"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.inspectionNo || '车辆年检详情'"
      :subtitle="
        [detail.data?.plateNo, detail.data?.companyName].filter(Boolean).join(' / ') || '--'
      "
      show-back
      @back="goBack"
    />

    <section class="vehicle-inspection-detail__summary art-card-xs">
      <div class="vehicle-inspection-detail__summary-item">
        <span>年检日期</span>
        <strong>{{ detail.data?.inspectionDate || '--' }}</strong>
      </div>
      <div class="vehicle-inspection-detail__summary-item">
        <span>到期日期</span>
        <strong>{{ detail.data?.expireDate || '--' }}</strong>
      </div>
      <div class="vehicle-inspection-detail__summary-item">
        <span>年检金额</span>
        <strong>{{ formatMoney(detail.data?.inspectionAmount) }}</strong>
      </div>
      <div class="vehicle-inspection-detail__summary-item">
        <span>附件数量</span>
        <strong>{{ detail.data?.attachments?.length ?? 0 }}</strong>
      </div>
    </section>

    <div class="vehicle-inspection-detail__content art-card-xs">
      <section class="vehicle-inspection-detail__section">
        <ArtSectionTitle>年检信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="descriptionItems" :columns="2" />
      </section>

      <section class="vehicle-inspection-detail__section">
        <ArtSectionTitle>年检附件</ArtSectionTitle>
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
  import { isNil } from 'lodash-es'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleInspectionDetail } from '@/api/vms'
  import { downloadAttachment } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'

  defineOptions({ name: 'VehicleInspectionDetail' })

  type VehicleInspection = Api.Vms.VehicleManage.VehicleInspection
  type Attachment = Api.Vms.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive<{ loading: boolean; error: Error | null }>({ loading: false, error: null })
  const detail = reactive<{ data?: VehicleInspection }>({ data: undefined })
  const descriptionData = computed<Partial<VehicleInspection>>(() => detail.data ?? {})
  const descriptionItems: ArtDescriptionItem<Partial<VehicleInspection>>[] = [
    { key: 'plateNo', label: '车牌号', field: 'plateNo' },
    { key: 'companyName', label: '所属公司', field: 'companyName' },
    { key: 'inspectionDate', label: '年检日期', field: 'inspectionDate', format: 'date' },
    { key: 'inspectionNo', label: '年检号', field: 'inspectionNo', copyable: true },
    {
      key: 'inspectionAmount',
      label: '年检金额',
      field: 'inspectionAmount',
      formatter: (value) => formatMoney(value as number | null | undefined)
    },
    { key: 'vehicleOffice', label: '车管所', field: 'vehicleOffice' },
    { key: 'expireDate', label: '到期日期', field: 'expireDate', format: 'date' },
    { key: 'remark', label: '备注', field: 'remark' }
  ]

  const attachmentColumns: ColumnOption<Attachment>[] = [
    { type: 'globalIndex', label: '序号', width: 56 },
    { prop: 'name', label: '附件名称', minWidth: 180, formatter: renderAttachmentLink },
    {
      prop: 'fileType',
      label: '格式类型',
      width: 110,
      dict: { code: 'FILE_EXTENSION_LABEL_MAP', display: 'text' }
    },
    { prop: 'fileSize', label: '附件大小', width: 110 },
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
      page.error = new Error('缺少年检记录标识')
      return
    }
    page.loading = true
    page.error = null
    try {
      const { data } = await fetchVehicleInspectionDetail(id)
      detail.data = data ? { ...data, attachments: data.attachments ?? [] } : undefined
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('车辆年检详情加载失败')
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vms/vehicle-manage/vehicle-inspection')
  }

  const formatMoney = (value?: number | null): string => {
    if (isNil(value)) return '--'
    return `${Number(value).toFixed(2)} 元`
  }
</script>

<style scoped lang="scss">
  .vehicle-inspection-detail {
    min-height: 100%;
    padding: 16px;
    background: var(--art-main-bg-color);

    &__content {
      padding: 20px;
      margin-top: 12px;
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

    &__section + &__section {
      margin-top: 22px;
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 128px;
      font-weight: 600;
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
