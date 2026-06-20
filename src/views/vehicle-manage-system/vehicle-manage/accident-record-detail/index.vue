<template>
  <div class="accident-record-detail" v-loading="page.loading">
    <div class="accident-record-detail__header">
      <div>
        <h2>{{ detail.data?.plateNo || '事故记录详情' }}</h2>
        <p>{{ detail.data?.companyName || '--' }}</p>
      </div>
      <ElButton @click="goBack">返回</ElButton>
    </div>

    <section class="accident-record-detail__summary">
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

    <div class="accident-record-detail__content">
      <section class="accident-record-detail__section">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="车牌号">{{
            formatValue(detail.data?.plateNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="所属公司">{{
            formatValue(detail.data?.companyName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="驾驶员">{{
            formatValue(detail.data?.driverName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="事故时间">{{
            formatValue(detail.data?.accidentTime)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="事故地点">{{
            formatValue(detail.data?.accidentLocation)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="事故等级">{{
            formatValue(detail.data?.damageLevel)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="事故概述" :span="2">
            {{ formatValue(detail.data?.accidentSummary) }}
          </ElDescriptionsItem>
        </ElDescriptions>
      </section>

      <section class="accident-record-detail__section">
        <ArtSectionTitle>责任及处理</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="责任类型">
            <ArtDictDisplay
              dict-code="vehicleAccidentResponsibility"
              :value="detail.data?.responsibilityType"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="责任比例">{{
            formatPercent(detail.data?.responsibilityPercent)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="经济损失">{{
            formatMoney(detail.data?.economicLoss)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="公司承担">{{
            formatMoney(detail.data?.companyBearAmount)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="是否报案">
            <ArtDictDisplay
              dict-code="commonBoolean"
              :value="getBooleanDictValue(detail.data?.reported)"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="保险报案">
            <ArtDictDisplay
              dict-code="commonBoolean"
              :value="getBooleanDictValue(detail.data?.insuranceReported)"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="已处理">
            <ArtDictDisplay
              dict-code="vehicleRecordProcessed"
              :value="getBooleanDictValue(detail.data?.processed)"
              display="auto"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="数据来源">
            <ArtDictDisplay
              dict-code="vehicleAccidentDataSource"
              :value="detail.data?.dataSource"
              display="text"
            />
          </ElDescriptionsItem>
        </ElDescriptions>
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
  </div>
</template>

<script setup lang="tsx">
  import { isNil } from 'lodash-es'
  import { ElButton, ElDescriptions, ElDescriptionsItem } from 'element-plus'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleAccidentDetail } from '@/api/vehicle-manage-system'
  import { downloadAttachment, viewAttachment } from '@/utils/file'

  defineOptions({ name: 'VehicleAccidentDetail' })

  type AccidentRecord = Api.VehicleMgtSys.VehicleManage.VehicleAccidentRecord
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive({ loading: false })
  const detail = reactive<{ data?: AccidentRecord }>({ data: undefined })

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
      width: 120,
      formatter: (row) => (
        <div class="flex">
          <ArtButtonTable type="view" onClick={() => viewAttachment(row)} />
          <ArtButtonTable icon="ri:download-2-line" onClick={() => downloadAttachment(row)} />
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
      const { data } = await fetchVehicleAccidentDetail(id)
      detail.data = data ? { ...data, attachments: data.attachments ?? [] } : undefined
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vehicle-manage-system/vehicle-manage/accident-record')
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

  const getBooleanDictValue = (value?: boolean | null): string | undefined =>
    isNil(value) ? undefined : String(value)
</script>

<style scoped lang="scss">
  .accident-record-detail {
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

    &__section + &__section {
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
      &__summary {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
