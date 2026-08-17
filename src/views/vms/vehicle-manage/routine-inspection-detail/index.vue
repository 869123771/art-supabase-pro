<template>
  <ArtPageShell
    class="routine-inspection-detail"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    :empty="!detail.data"
    empty-text="暂无例检记录详情"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.routineInspectionNo || '例检记录详情'"
      :subtitle="
        [detail.data?.plateNo, detail.data?.companyName].filter(Boolean).join(' / ') || '--'
      "
      show-back
      @back="goBack"
    />

    <section class="routine-inspection-detail__summary art-card-xs">
      <div class="routine-inspection-detail__summary-item">
        <span>例检类型</span>
        <strong>
          <ArtDictDisplay
            dict-code="vehicleRoutineInspectionType"
            :value="detail.data?.inspectionType"
            display="auto"
          />
        </strong>
      </div>
      <div class="routine-inspection-detail__summary-item">
        <span>检查结果</span>
        <strong>
          <ArtDictDisplay
            dict-code="vehicleRoutineInspectionResult"
            :value="detail.data?.checkResult"
            display="auto"
          />
        </strong>
      </div>
      <div class="routine-inspection-detail__summary-item">
        <span>附件数量</span>
        <strong>{{ detail.data?.attachments?.length ?? 0 }}</strong>
      </div>
    </section>

    <div class="routine-inspection-detail__content art-card-xs">
      <section class="routine-inspection-detail__section">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ArtDescriptions :data="descriptionData" :items="descriptionItems" :columns="2" />
      </section>

      <section class="routine-inspection-detail__section">
        <ArtSectionTitle>检查情况</ArtSectionTitle>
        <div class="routine-inspection-detail__text">
          {{ formatValue(detail.data?.checkCondition) }}
        </div>
      </section>

      <section class="routine-inspection-detail__section">
        <ArtSectionTitle>处理方式</ArtSectionTitle>
        <div class="routine-inspection-detail__text">
          {{ formatValue(detail.data?.handlingMethod) }}
        </div>
      </section>

      <section class="routine-inspection-detail__section">
        <ArtSectionTitle>备注</ArtSectionTitle>
        <div class="routine-inspection-detail__text">{{ formatValue(detail.data?.remark) }}</div>
      </section>

      <section class="routine-inspection-detail__section">
        <ArtSectionTitle>例检附件</ArtSectionTitle>
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
  import { fetchVehicleRoutineInspectionDetail } from '@/api/vms'
  import { downloadAttachment, viewAttachment } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'

  defineOptions({ name: 'VehicleRoutineInspectionDetail' })

  type RoutineInspection = Api.Vms.VehicleManage.VehicleRoutineInspectionRecord
  type Attachment = Api.Vms.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive<{ loading: boolean; error: Error | null }>({ loading: false, error: null })
  const detail = reactive<{ data?: RoutineInspection }>({ data: undefined })
  const descriptionData = computed<Partial<RoutineInspection>>(() => detail.data ?? {})
  const descriptionItems: ArtDescriptionItem<Partial<RoutineInspection>>[] = [
    { key: 'plateNo', label: '车牌号', field: 'plateNo' },
    { key: 'companyName', label: '所属公司', field: 'companyName' },
    {
      key: 'routineInspectionNo',
      label: '例检编号',
      field: 'routineInspectionNo',
      copyable: true
    },
    {
      key: 'inspectionType',
      label: '例检类型',
      field: 'inspectionType',
      dictCode: 'vehicleRoutineInspectionType',
      dictDisplay: 'text'
    },
    { key: 'inspectionTime', label: '例检时间', field: 'inspectionTime', format: 'datetime' },
    { key: 'inspector', label: '检查人', field: 'inspector' },
    { key: 'driverName', label: '驾驶员', field: 'driverName' },
    {
      key: 'checkResult',
      label: '检查结果',
      field: 'checkResult',
      dictCode: 'vehicleRoutineInspectionResult',
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
      page.error = new Error('缺少例检记录标识')
      return
    }
    page.loading = true
    page.error = null
    try {
      const { data } = await fetchVehicleRoutineInspectionDetail(id)
      detail.data = data ? { ...data, attachments: data.attachments ?? [] } : undefined
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('例检记录详情加载失败')
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vms/vehicle-manage/routine-inspection')
  }

  const formatValue = (value?: string | number | null): string => {
    if (isNil(value) || value === '') return '--'
    return String(value)
  }
</script>

<style scoped lang="scss">
  .routine-inspection-detail {
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

    &__text {
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
