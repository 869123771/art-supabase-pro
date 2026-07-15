<template>
  <div class="routine-inspection-detail" v-loading="page.loading">
    <div class="routine-inspection-detail__header art-card-xs">
      <div>
        <h2>{{ detail.data?.routineInspectionNo || '例检记录详情' }}</h2>
        <p>{{
          [detail.data?.plateNo, detail.data?.companyName].filter(Boolean).join(' / ') || '--'
        }}</p>
      </div>
      <ElButton @click="goBack">返回</ElButton>
    </div>

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
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="车牌号">{{
            formatValue(detail.data?.plateNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="所属公司">{{
            formatValue(detail.data?.companyName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="例检编号">{{
            formatValue(detail.data?.routineInspectionNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="例检类型">
            <ArtDictDisplay
              dict-code="vehicleRoutineInspectionType"
              :value="detail.data?.inspectionType"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="例检时间">{{
            formatValue(detail.data?.inspectionTime)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="检查人">{{
            formatValue(detail.data?.inspector)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="驾驶员">{{
            formatValue(detail.data?.driverName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="检查结果">
            <ArtDictDisplay
              dict-code="vehicleRoutineInspectionResult"
              :value="detail.data?.checkResult"
              display="text"
            />
          </ElDescriptionsItem>
        </ElDescriptions>
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
  </div>
</template>

<script setup lang="tsx">
  import { isNil } from 'lodash-es'
  import { ElButton, ElDescriptions, ElDescriptionsItem } from 'element-plus'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleRoutineInspectionDetail } from '@/api/vehicle-manage-system'
  import { downloadAttachment, viewAttachment } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'

  defineOptions({ name: 'VehicleRoutineInspectionDetail' })

  type RoutineInspection = Api.VehicleMgtSys.VehicleManage.VehicleRoutineInspectionRecord
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive({ loading: false })
  const detail = reactive<{ data?: RoutineInspection }>({ data: undefined })

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
    if (!id) return
    page.loading = true
    try {
      const { data } = await fetchVehicleRoutineInspectionDetail(id)
      detail.data = data ? { ...data, attachments: data.attachments ?? [] } : undefined
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vehicle-manage-system/vehicle-manage/routine-inspection')
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

    &__section + &__section {
      margin-top: 22px;
    }

    &__text {
      min-height: 48px;
      padding: 12px 14px;
      line-height: 1.7;
      color: var(--el-text-color-regular);
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);
      overflow-wrap: anywhere;
    }

    :deep(.el-descriptions__label) {
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
