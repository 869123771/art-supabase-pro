<template>
  <div class="maintenance-record-detail" v-loading="page.loading">
    <div class="maintenance-record-detail__header">
      <div>
        <h2>{{ detail.data?.maintenanceNo || '维修保养详情' }}</h2>
        <p>{{
          [detail.data?.plateNo, detail.data?.companyName].filter(Boolean).join(' / ') || '--'
        }}</p>
      </div>
      <ElButton @click="goBack">返回</ElButton>
    </div>

    <section class="maintenance-record-detail__summary">
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

    <div class="maintenance-record-detail__content">
      <section class="maintenance-record-detail__section">
        <ArtSectionTitle>基础信息</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="车牌号">{{
            formatValue(detail.data?.plateNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="所属公司">{{
            formatValue(detail.data?.companyName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="维修单号">{{
            formatValue(detail.data?.maintenanceNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="维修类型">
            <ArtDictDisplay
              dict-code="vehicleMaintenanceType"
              :value="detail.data?.maintenanceType"
              display="text"
            />
          </ElDescriptionsItem>
          <ElDescriptionsItem label="发起人">{{
            formatValue(detail.data?.initiator)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="维修厂">{{
            formatValue(detail.data?.workshop)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="开始时间">{{
            formatValue(detail.data?.startTime)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="结束时间">{{
            formatValue(detail.data?.endTime)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="费用金额">{{
            formatMoney(detail.data?.costAmount)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="外部维修">
            <ArtDictDisplay
              dict-code="commonBoolean"
              :value="getBooleanDictValue(detail.data?.externalRepair)"
              display="text"
            />
          </ElDescriptionsItem>
        </ElDescriptions>
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
  import { fetchVehicleMaintenanceDetail } from '@/api/vehicle-manage-system'
  import { downloadAttachment, viewAttachment } from '@/utils/file'

  defineOptions({ name: 'VehicleMaintenanceDetail' })

  type MaintenanceRecord = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceRecord
  type MaintenanceItem = Api.VehicleMgtSys.VehicleManage.VehicleMaintenanceItem
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive({ loading: false })
  const detail = reactive<{ data?: MaintenanceRecord }>({ data: undefined })

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
      const { data } = await fetchVehicleMaintenanceDetail(id)
      detail.data = data
        ? { ...data, items: data.items ?? [], attachments: data.attachments ?? [] }
        : undefined
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
