<template>
  <ArtPageShell
    class="maintenance-record-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无维修保养详情"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.maintenanceNo || '维修保养详情'"
      :subtitle="
        [detail.data?.plateNo, detail.data?.companyName].filter(Boolean).join(' / ') || '--'
      "
      show-back
      @back="goBack"
    />

    <section class="maintenance-record-detail__summary art-card-xs">
      <div class="maintenance-record-detail__summary-item">
        <span>维修类型</span>
        <strong>
          <ArtDictDisplay
            dict-code="vehicleMaintenanceType"
            :value="detail.data?.maintenanceType"
            display="auto"
          />
        </strong>
      </div>
      <div class="maintenance-record-detail__summary-item">
        <span>费用金额</span>
        <strong>{{ formatMoney(detail.data?.costAmount) }}</strong>
      </div>
      <div class="maintenance-record-detail__summary-item">
        <span>维修项目数</span>
        <strong>{{ detail.data?.items?.length ?? 0 }}</strong>
      </div>
    </section>

    <div class="maintenance-record-detail__content art-card-xs">
      <section class="maintenance-record-detail__section">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="descriptionItems" :columns="2" />
      </section>

      <section class="maintenance-record-detail__section">
        <ArtSectionTitle>维修项目</ArtSectionTitle>
        <ArtTable
          :data="detail.data?.items ?? []"
          :columns="itemColumns"
          :pagination="undefined"
          :show-table-header="false"
          empty-height="180px"
        />
      </section>

      <section class="maintenance-record-detail__section">
        <ArtSectionTitle>备注</ArtSectionTitle>
        <div class="maintenance-record-detail__remark">{{ formatValue(detail.data?.remark) }}</div>
      </section>

      <section class="maintenance-record-detail__section">
        <ArtSectionTitle>维修附件</ArtSectionTitle>
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
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleMaintenanceDetail } from '@/api/vehicle-manage-system'
  import { downloadAttachment, viewAttachment } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'

  defineOptions({ name: 'VehicleMaintenanceDetail' })

  type MaintenanceRecord = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceRecord
  type MaintenanceItem = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceItem
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive<{ loading: boolean; error: Error | null }>({ loading: false, error: null })
  const detail = reactive<{ data?: MaintenanceRecord }>({ data: undefined })
  const descriptionData = computed<Partial<MaintenanceRecord>>(() => detail.data ?? {})
  const descriptionItems: ArtDescriptionItem<Partial<MaintenanceRecord>>[] = [
    { key: 'plateNo', label: '车牌号', field: 'plateNo' },
    { key: 'companyName', label: '所属公司', field: 'companyName' },
    { key: 'maintenanceNo', label: '维修单号', field: 'maintenanceNo', copyable: true },
    {
      key: 'maintenanceType',
      label: '维修类型',
      field: 'maintenanceType',
      dictCode: 'vehicleMaintenanceType',
      dictDisplay: 'text'
    },
    { key: 'initiator', label: '发起人', field: 'initiator' },
    { key: 'workshop', label: '维修厂', field: 'workshop' },
    { key: 'startTime', label: '开始时间', field: 'startTime', format: 'datetime' },
    { key: 'endTime', label: '结束时间', field: 'endTime', format: 'datetime' },
    {
      key: 'costAmount',
      label: '费用金额',
      field: 'costAmount',
      formatter: (value) => formatMoney(value as number | null | undefined)
    },
    {
      key: 'externalRepair',
      label: '外部维修',
      field: 'externalRepair',
      dictCode: 'commonBoolean',
      dictDisplay: 'text',
      value: (data: Partial<MaintenanceRecord>) => getBooleanDictValue(data.externalRepair)
    }
  ]

  const itemColumns: ColumnOption<MaintenanceItem>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'itemName', label: '项目名称', minWidth: 180 },
    { prop: 'partName', label: '配件名称', minWidth: 160 },
    { prop: 'quantity', label: '数量', width: 100 },
    {
      prop: 'partPrice',
      label: '配件金额',
      width: 120,
      formatter: (row) => formatMoney(row.partPrice)
    },
    {
      prop: 'laborAmount',
      label: '工时费',
      width: 120,
      formatter: (row) => formatMoney(row.laborAmount)
    },
    {
      prop: 'totalAmount',
      label: '合计',
      width: 120,
      formatter: (row) => formatMoney(row.totalAmount)
    }
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
      width: 96,
      formatter: (row) => (
        <div class="flex items-center">
          <ArtIconButton icon="ri:eye-line" onClick={() => viewAttachment(row)} />
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
      page.error = new Error('缺少维修记录标识')
      return
    }
    page.loading = true
    page.error = null
    try {
      const { data } = await fetchVehicleMaintenanceDetail(id)
      detail.data = data
        ? { ...data, items: data.items ?? [], attachments: data.attachments ?? [] }
        : undefined
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('维修保养详情加载失败')
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vehicle-manage-system/vehicle-manage/maintenance-record')
  }

  const formatValue = (value?: string | number | null): string => {
    if (isNil(value) || value === '') return '--'
    return String(value)
  }

  const formatMoney = (value?: number | null): string => {
    if (isNil(value)) return '--'
    return `${Number(value).toFixed(2)} 元`
  }

  const getBooleanDictValue = (value?: boolean | null): string | undefined =>
    isNil(value) ? undefined : String(value)
</script>

<style scoped lang="scss">
  .maintenance-record-detail {
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

    &__section + &__section {
      margin-top: 22px;
    }

    &__remark {
      min-height: 48px;
      padding: 12px 14px;
      line-height: 1.7;
      color: var(--el-text-color-regular);
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);
      overflow-wrap: anywhere;
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 128px;
      font-weight: 600;
    }

    @media (max-width: 900px) {
      &__summary {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
