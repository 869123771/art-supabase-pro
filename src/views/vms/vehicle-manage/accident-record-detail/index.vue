<template>
  <ArtPageShell
    class="accident-record-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无事故记录详情"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.plateNo || '事故记录详情'"
      :subtitle="detail.data?.companyName || '--'"
      show-back
      @back="goBack"
    />

    <section class="accident-record-detail__summary art-card-xs">
      <div class="accident-record-detail__summary-item">
        <span>事故时间</span>
        <strong>{{ formatValue(detail.data?.accidentTime) }}</strong>
      </div>
      <div class="accident-record-detail__summary-item">
        <span>经济损失</span>
        <strong>{{ formatMoney(detail.data?.economicLoss) }}</strong>
      </div>
      <div class="accident-record-detail__summary-item">
        <span>处理状态</span>
        <strong>
          <ArtDictDisplay
            dict-code="vehicleRecordProcessed"
            :value="getBooleanDictValue(detail.data?.processed)"
            display="auto"
          />
        </strong>
      </div>
    </section>

    <div class="accident-record-detail__content art-card-xs">
      <section class="accident-record-detail__section">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="basicItems" :columns="2" />
      </section>

      <section class="accident-record-detail__section">
        <ArtSectionTitle>责任及处理</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="responsibilityItems" :columns="2" />
      </section>

      <section class="accident-record-detail__section">
        <ArtSectionTitle>备注</ArtSectionTitle>
        <div class="accident-record-detail__remark">{{ formatValue(detail.data?.remark) }}</div>
      </section>

      <section class="accident-record-detail__section">
        <ArtSectionTitle>事故附件</ArtSectionTitle>
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
  import { fetchVehicleAccidentDetail } from '@/api/vms'
  import { downloadAttachment, viewAttachment } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'

  defineOptions({ name: 'VehicleAccidentDetail' })

  type AccidentRecord = Api.Vms.VehicleManage.VehicleAccidentRecord
  type Attachment = Api.Vms.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive<{ loading: boolean; error: Error | null }>({ loading: false, error: null })
  const detail = reactive<{ data?: AccidentRecord }>({ data: undefined })
  const descriptionData = computed<Partial<AccidentRecord>>(() => detail.data ?? {})
  const basicItems: ArtDescriptionItem<Partial<AccidentRecord>>[] = [
    { key: 'plateNo', label: '车牌号', field: 'plateNo' },
    { key: 'companyName', label: '所属公司', field: 'companyName' },
    { key: 'driverName', label: '驾驶员', field: 'driverName' },
    { key: 'driverPhone', label: '联系方式', field: 'driverPhone' },
    { key: 'accidentTime', label: '事故时间', field: 'accidentTime', format: 'datetime' },
    { key: 'accidentLocation', label: '事故地点', field: 'accidentLocation' },
    {
      key: 'accidentCoordinate',
      label: '事故坐标',
      value: (data: Partial<AccidentRecord>) =>
        formatCoordinate(data.accidentLongitude, data.accidentLatitude)
    },
    { key: 'damageLevel', label: '事故等级', field: 'damageLevel' },
    { key: 'accidentSummary', label: '事故概述', field: 'accidentSummary', span: 2 }
  ]
  const responsibilityItems: ArtDescriptionItem<Partial<AccidentRecord>>[] = [
    {
      key: 'responsibilityType',
      label: '责任类型',
      field: 'responsibilityType',
      dictCode: 'vehicleAccidentResponsibility',
      dictDisplay: 'text'
    },
    {
      key: 'responsibilityPercent',
      label: '责任比例',
      field: 'responsibilityPercent',
      formatter: (value) => formatPercent(value as number | null | undefined)
    },
    {
      key: 'economicLoss',
      label: '经济损失',
      field: 'economicLoss',
      formatter: (value) => formatMoney(value as number | null | undefined)
    },
    {
      key: 'companyBearAmount',
      label: '公司承担',
      field: 'companyBearAmount',
      formatter: (value) => formatMoney(value as number | null | undefined)
    },
    ...(['reported', 'insuranceReported', 'processed'] as const).map((field) => ({
      key: field,
      label: { reported: '是否报案', insuranceReported: '保险报案', processed: '已处理' }[field],
      field,
      value: (data: Partial<AccidentRecord>) => getBooleanDictValue(data[field]),
      dictCode: field === 'processed' ? 'vehicleRecordProcessed' : 'commonBoolean',
      dictDisplay: field === 'processed' ? ('auto' as const) : ('text' as const)
    })),
    {
      key: 'dataSource',
      label: '数据来源',
      field: 'dataSource',
      dictCode: 'vehicleAccidentDataSource',
      dictDisplay: 'text'
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
      page.error = new Error('缺少事故记录标识')
      return
    }
    page.loading = true
    page.error = null
    try {
      const { data } = await fetchVehicleAccidentDetail(id)
      detail.data = data ? { ...data, attachments: data.attachments ?? [] } : undefined
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('事故记录详情加载失败')
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vms/vehicle-manage/accident-record')
  }

  const formatValue = (value?: string | number | null): string => {
    if (isNil(value) || value === '') return '--'
    return String(value)
  }

  const formatMoney = (value?: number | null): string => {
    if (isNil(value)) return '--'
    return `${Number(value).toFixed(2)} 元`
  }

  const formatPercent = (value?: number | null): string => {
    if (isNil(value)) return '--'
    return `${value}%`
  }

  const formatCoordinate = (longitude?: number | null, latitude?: number | null): string => {
    if (isNil(longitude) || isNil(latitude)) return '--'
    return `${Number(longitude).toFixed(7)}, ${Number(latitude).toFixed(7)}`
  }

  const getBooleanDictValue = (value?: boolean | null): string | undefined =>
    isNil(value) ? undefined : String(value)
</script>

<style scoped lang="scss">
  .accident-record-detail {
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
      overflow-wrap: anywhere;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 128px;
      font-weight: 600;
    }

    @media (width <= 900px) {
      &__summary {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
