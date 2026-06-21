<template>
  <div class="vehicle-inspection-detail" v-loading="page.loading">
    <div class="vehicle-inspection-detail__header art-card-xs">
      <div>
        <h2>{{ detail.data?.inspectionNo || '车辆年检详情' }}</h2>
        <p>{{
          [detail.data?.plateNo, detail.data?.companyName].filter(Boolean).join(' / ') || '--'
        }}</p>
      </div>
      <ElButton @click="goBack">返回</ElButton>
    </div>

    <div class="vehicle-inspection-detail__content art-card-xs">
      <section class="vehicle-inspection-detail__section">
        <ArtSectionTitle>年检信息</ArtSectionTitle>
        <ElDescriptions :column="2" border>
          <ElDescriptionsItem label="车牌号">{{
            formatValue(detail.data?.plateNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="所属公司">{{
            formatValue(detail.data?.companyName)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="年检日期">{{
            formatValue(detail.data?.inspectionDate)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="年检号">{{
            formatValue(detail.data?.inspectionNo)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="年检金额">{{
            formatMoney(detail.data?.inspectionAmount)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="车管所">{{
            formatValue(detail.data?.vehicleOffice)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="到期日期">{{
            formatValue(detail.data?.expireDate)
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="备注">{{
            formatValue(detail.data?.remark)
          }}</ElDescriptionsItem>
        </ElDescriptions>
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
  </div>
</template>

<script setup lang="tsx">
  import { isNil } from 'lodash-es'
  import { ElButton, ElDescriptions, ElDescriptionsItem } from 'element-plus'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchVehicleInspectionDetail } from '@/api/vehicle-manage-system'
  import { downloadAttachment } from '@/utils/file'

  defineOptions({ name: 'VehicleInspectionDetail' })

  type VehicleInspection = Api.VehicleMgtSys.VehicleManage.VehicleInspection
  type Attachment = Api.VehicleMgtSys.VehicleManage.VehicleAttachment

  const route = useRoute()
  const router = useRouter()
  const page = reactive({ loading: false })
  const detail = reactive<{ data?: VehicleInspection }>({ data: undefined })

  const attachmentColumns: ColumnOption<Attachment>[] = [
    { type: 'globalIndex', label: '序号', width: 56 },
    { prop: 'name', label: '附件名称', minWidth: 180 },
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
    if (!id) return
    page.loading = true
    try {
      const { data } = await fetchVehicleInspectionDetail(id)
      detail.data = data ? { ...data, attachments: data.attachments ?? [] } : undefined
    } finally {
      page.loading = false
    }
  }

  const goBack = (): void => {
    void router.push('/vehicle-manage-system/vehicle-manage/vehicle-inspection')
  }

  const formatValue = (value?: string | number | null): string => {
    if (isNil(value) || value === '') return '--'
    return String(value)
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

    &__content {
      padding: 20px;
      margin-top: 12px;
    }

    &__section + &__section {
      margin-top: 22px;
    }

    :deep(.el-descriptions__label) {
      width: 128px;
      font-weight: 600;
    }
  }
</style>
