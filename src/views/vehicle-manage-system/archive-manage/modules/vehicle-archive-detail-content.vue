<template>
  <ArtPageShell
    class="vehicle-archive-detail"
    :loading="loading"
    loading-mode="skeleton"
    :error="loadError"
    :empty="!archive"
    empty-text="暂无车辆档案详情"
    @retry="loadArchiveDetail"
  >
    <ArtPageHeader
      class="vehicle-archive-detail__header"
      :title="archive?.plateNo || '车辆档案详情'"
      show-back
      @back="goBack"
    >
      <template #title>
        <div class="vehicle-archive-detail__identity">
          <ArtUploadImage
            v-if="archive?.vehiclePhotoUrl"
            class="vehicle-archive-detail__vehicle-photo"
            :model-value="archive.vehiclePhotoUrl"
            :size="88"
            :limit="1"
            readonly
          />
          <span v-else class="vehicle-archive-detail__vehicle-photo-empty" aria-hidden="true">
            <ArtSvgIcon icon="ri:truck-line" />
          </span>
          <div class="vehicle-archive-detail__identity-copy">
            <div class="vehicle-archive-detail__identity-primary">
              <h1>{{ archive?.plateNo || '车辆档案详情' }}</h1>
              <div v-if="archive" class="vehicle-archive-detail__header-statuses">
                <ArtDictDisplay
                  dict-code="vehicleOperationStatus"
                  :value="archive.operationStatus"
                  display="tag"
                />
                <ArtDictDisplay
                  dict-code="vehicleAuditStatus"
                  :value="archive.auditStatus"
                  display="tag"
                />
              </div>
            </div>
            <p>{{ archive?.companyName || '--' }}</p>
          </div>
        </div>
      </template>
    </ArtPageHeader>

    <ElTabs v-model="activeTab" class="vehicle-archive-detail__tabs art-card-xs">
      <ElTabPane label="基础信息" name="basic">
        <InfoDescriptions :items="basicInfoItems" />
        <section class="vehicle-archive-detail__section vehicle-archive-detail__certificate-panel">
          <header class="vehicle-archive-detail__section-heading">
            <div>
              <ArtSectionTitle :show-line="false">车辆证件</ArtSectionTitle>
              <p>车辆证件影像归档，点击已上传图片可查看原图</p>
            </div>
            <span>{{ certificatePreviewUrls.length }}/{{ certificateItems.length }} 已归档</span>
          </header>
          <div class="vehicle-archive-detail__images">
            <article
              v-for="item in certificateItems"
              :key="item.key"
              class="vehicle-archive-detail__image-item"
            >
              <header>
                <strong>{{ item.label }}</strong>
                <span :class="{ 'is-ready': archive?.[item.key] }">
                  {{ archive?.[item.key] ? '已上传' : '待补充' }}
                </span>
              </header>
              <ElImage
                v-if="archive?.[item.key]"
                :src="archive[item.key]"
                :alt="item.label"
                fit="contain"
                :initial-index="certificatePreviewUrls.indexOf(archive[item.key] || '')"
                :preview-src-list="certificatePreviewUrls"
                preview-teleported
              >
                <template #error>
                  <span class="vehicle-archive-detail__image-empty is-error">
                    <ArtSvgIcon icon="ri:image-line" />
                    图片加载失败
                  </span>
                </template>
              </ElImage>
              <div v-else class="vehicle-archive-detail__image-empty">
                <ArtSvgIcon icon="ri:file-image-line" />
                <span>暂无{{ item.label }}</span>
              </div>
            </article>
          </div>
        </section>
      </ElTabPane>

      <ElTabPane label="车身参数" name="body">
        <InfoDescriptions :items="bodyInfoItems" />
      </ElTabPane>

      <ElTabPane label="发动机参数" name="engine">
        <InfoDescriptions :items="engineInfoItems" />
      </ElTabPane>

      <ElTabPane label="其他信息" name="other">
        <InfoDescriptions :items="otherInfoItems" />
        <section class="vehicle-archive-detail__section">
          <ArtSectionTitle>车辆档案附件</ArtSectionTitle>
          <ArtTable
            :data="archive?.attachments ?? []"
            :columns="attachmentColumns"
            :pagination="undefined"
            :show-table-header="false"
            empty-height="180px"
          />
        </section>
      </ElTabPane>
      <ElTabPane label="审批历程" name="approvalHistory" lazy>
        <WorkflowBusinessHistory
          v-if="archive?.id"
          business-type="vehicle_archive"
          :business-id="archive.id"
        />
      </ElTabPane>
    </ElTabs>

    <ElCard v-if="showAuditPanel" class="vehicle-archive-detail__audit art-card-xs" shadow="never">
      <template #header>
        <span>审核状态</span>
      </template>
      <ArtForm
        :model-value="auditForm"
        :items="auditFormItems"
        :span="24"
        label-width="90px"
        :show-reset="false"
        submit-text="保存审核"
        :disabled-submit="savingAudit"
        @update:model-value="Object.assign(auditForm, $event)"
        @submit="handleSaveAudit"
      />
    </ElCard>
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import type { VNodeChild } from 'vue'
  import { ElCard, ElImage, ElTabPane, ElTabs } from 'element-plus'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import WorkflowBusinessHistory from '@/components/business/workflow-business-history/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import type { ColumnOption } from '@/types'
  import { auditVehicleArchive, fetchVehicleArchiveDetail } from '@/api/vehicle-manage-system'
  import { useUserStore } from '@/store/modules/user'
  import { viewAttachment } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'

  defineOptions({ name: 'VehicleArchiveDetailContent' })

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type ArchiveAttachment = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveAttachment
  type AuditStatus = Api.VehicleMgtSys.ArchiveManage.AuditStatus
  type ImageKey = 'drivingLicenseFrontUrl' | 'drivingLicenseBackUrl' | 'operationLicenseUrl'

  interface InfoItem {
    label: string
    value: VNodeChild
    suffix?: string
  }

  const infoDescriptionData = Object.freeze({})

  const InfoDescriptions = defineComponent({
    props: {
      items: {
        type: Array as PropType<InfoItem[]>,
        required: true
      }
    },
    setup(props) {
      return () => {
        const descriptionItems: ArtDescriptionItem[] = props.items.map((item, index) => ({
          key: `${item.label}-${index}`,
          label: item.label,
          value: item.value,
          render: (value) => formatValue(value as InfoItem['value'], item.suffix),
          className: 'vehicle-archive-detail__description-content'
        }))

        return (
          <ArtDescriptions
            class="vehicle-archive-detail__descriptions"
            data={infoDescriptionData}
            items={descriptionItems}
            columns={3}
          />
        )
      }
    }
  })

  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const activeTab = ref('basic')
  const archive = ref<VehicleArchive>()
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)
  const savingAudit = ref(false)
  const auditForm = reactive<{
    auditStatus: Extract<AuditStatus, 'approved' | 'rejected'>
    auditRemark: string
  }>({
    auditStatus: 'approved',
    auditRemark: ''
  })
  const showAuditPanel = computed(
    () => route.query.source !== 'manage' && archive.value?.auditStatus === 'pending'
  )
  const auditStatusOptions = computed(() =>
    (userStore.getDictMap.vehicleAuditStatus ?? []).filter((item) =>
      ['approved', 'rejected'].includes(item.value)
    )
  )
  const auditFormItems = computed<FormItem[]>(() => [
    {
      label: '审核状态',
      key: 'auditStatus',
      type: 'radioGroup',
      props: { options: auditStatusOptions.value }
    },
    {
      label: '备注',
      key: 'auditRemark',
      type: 'input',
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '请输入审核说明'
      }
    }
  ])

  onMounted(async () => {
    await Promise.all([
      loadArchiveDetail(),
      userStore.ensureDictLoaded('FILE_EXTENSION_LABEL_MAP'),
      userStore.ensureDictLoaded('vehicleAuditStatus')
    ])
  })

  const basicInfoItems = computed<InfoItem[]>(() => [
    { label: '车牌号', value: archive.value?.plateNo },
    { label: '所属公司', value: archive.value?.companyName },
    { label: '自编号', value: archive.value?.selfNo },
    { label: '车型', value: getDictLabel('vehicleType', archive.value?.vehicleType) },
    { label: '国产/进口', value: getDictLabel('vehicleOriginType', archive.value?.originType) },
    { label: '车架号（VIN）', value: archive.value?.vin },
    { label: '车辆厂商', value: archive.value?.manufacturer },
    { label: '厂牌型号', value: archive.value?.brandModel },
    { label: '营运证号', value: archive.value?.operationCertNo },
    { label: '购置证号', value: archive.value?.purchaseCertNo },
    { label: '登记证号', value: archive.value?.registrationCertNo },
    { label: '车身颜色', value: getDictLabel('vehicleColor', archive.value?.vehicleColor) },
    { label: '底盘号', value: archive.value?.chassisNo },
    { label: '空调号码', value: archive.value?.acCode },
    { label: '波箱系列号', value: archive.value?.gearboxSerialNo },
    { label: '登记日期', value: archive.value?.registerDate },
    { label: '发证日期', value: archive.value?.issueDate },
    { label: '购入开票日期', value: archive.value?.invoiceDate },
    { label: '启用日期', value: archive.value?.startUseDate },
    { label: '使用年限', value: archive.value?.serviceYears, suffix: '年' },
    { label: '核定乘员数', value: archive.value?.approvedPassengerCount, suffix: '人' },
    { label: '座位数', value: archive.value?.seatCount },
    {
      label: '业务类型',
      value: getDictLabel('vehicleBusinessType', archive.value?.businessType)
    },
    { label: '是否空调车', value: getBooleanDictLabel(archive.value?.isAirConditioned) },
    {
      label: '营运状态',
      value: getDictLabel('vehicleOperationStatus', archive.value?.operationStatus)
    },
    { label: '营运状态变更', value: archive.value?.operationStatusChangeDate },
    {
      label: '购置状态',
      value: getDictLabel('vehiclePurchaseStatus', archive.value?.purchaseStatus)
    },
    { label: '购置状态变更', value: archive.value?.purchaseStatusChangeDate },
    { label: '例检启用日期', value: archive.value?.inspectionStartDate },
    { label: '车辆等级', value: getDictLabel('vehicleLevel', archive.value?.vehicleLevel) },
    { label: '是否新能源车', value: getBooleanDictLabel(archive.value?.isNewEnergy) },
    { label: '整车三包里程', value: archive.value?.threeGuaranteeMileage, suffix: '公里' },
    { label: '整车三包时长', value: archive.value?.threeGuaranteeDuration, suffix: '个月' },
    { label: '整车包修里程', value: archive.value?.warrantyMileage, suffix: '公里' },
    { label: '整车包修时长', value: archive.value?.warrantyDuration, suffix: '个月' },
    { label: '备注', value: archive.value?.remark }
  ])

  const bodyInfoItems = computed<InfoItem[]>(() => [
    { label: '满载总质量', value: archive.value?.grossMass, suffix: 'kg' },
    { label: '整备质量', value: archive.value?.curbWeight, suffix: 'kg' },
    { label: '核定载质量', value: archive.value?.approvedLoadMass, suffix: 'kg' },
    { label: '外廓长度', value: archive.value?.overallLength, suffix: 'mm' },
    { label: '外廓宽度', value: archive.value?.overallWidth, suffix: 'mm' },
    { label: '外廓高度', value: archive.value?.overallHeight, suffix: 'mm' },
    { label: '标台', value: archive.value?.platform },
    { label: '前轮距', value: archive.value?.frontTrack, suffix: 'mm' },
    { label: '后轮距', value: archive.value?.rearTrack, suffix: 'mm' },
    { label: '轴距', value: archive.value?.wheelbase },
    { label: '车轴数', value: archive.value?.axleCount },
    { label: '轮胎数', value: archive.value?.tireCount },
    { label: '钢板弹簧数', value: archive.value?.leafSpringCount, suffix: '片' },
    { label: '是否双层', value: getBooleanDictLabel(archive.value?.isDoubleDeck) }
  ])

  const engineInfoItems = computed<InfoItem[]>(() => [
    { label: '发动机号', value: archive.value?.engineNo },
    { label: '发动机型号', value: archive.value?.engineModel },
    { label: '燃油类型', value: getDictLabel('vehicleFuelType', archive.value?.fuelType) },
    { label: '发动机排量', value: archive.value?.displacement, suffix: 'L' },
    {
      label: '排放标准',
      value: getDictLabel('vehicleEmissionStandard', archive.value?.emissionStandard)
    },
    { label: '发动机功率', value: archive.value?.enginePower, suffix: 'KW' },
    { label: '额定扭矩转速', value: archive.value?.ratedTorqueSpeed, suffix: 'r/min' },
    { label: '发动机扭矩', value: archive.value?.engineTorque, suffix: 'N-M' }
  ])

  const otherInfoItems = computed<InfoItem[]>(() => [
    { label: '车牌颜色', value: getDictLabel('vehicleColor', archive.value?.plateColor) },
    {
      label: '运输行业',
      value: getDictLabel('vehicleTransportIndustry', archive.value?.transportIndustry)
    },
    {
      label: '营运类型',
      value: getDictLabel('vehicleOperationType', archive.value?.operationType)
    },
    { label: '业户ID', value: archive.value?.ownerId },
    { label: '业户名称', value: archive.value?.ownerName },
    { label: '业户联系电话', value: archive.value?.ownerPhone },
    { label: '车载终端电话', value: archive.value?.terminalPhone },
    { label: '车主性别', value: getDictLabel('sex', archive.value?.ownerGender) },
    { label: '身份证号码', value: archive.value?.idCardNo },
    { label: '通讯地址', value: archive.value?.mailingAddress },
    { label: '吨位/座位', value: archive.value?.tonnageOrSeat },
    { label: '主司机姓名', value: archive.value?.primaryDriver?.driverName },
    { label: '主司机电话', value: archive.value?.primaryDriver?.phone },
    { label: '辅司机姓名', value: archive.value?.secondaryDriver?.driverName },
    { label: '辅司机电话', value: archive.value?.secondaryDriver?.phone },
    { label: '营运线路', value: archive.value?.operationRoute },
    { label: '车籍地代码', value: archive.value?.licensePlateCode },
    { label: '服务开始时间', value: archive.value?.serviceStartTime },
    { label: '服务结束时间', value: archive.value?.serviceEndTime },
    { label: '支持拍照', value: getBooleanDictLabel(archive.value?.supportPhoto) }
  ])

  const certificateItems: Array<{ key: ImageKey; label: string }> = [
    { key: 'drivingLicenseFrontUrl', label: '行驶证正页' },
    { key: 'drivingLicenseBackUrl', label: '行驶证副页' },
    { key: 'operationLicenseUrl', label: '运营证照片' }
  ]

  const certificatePreviewUrls = computed(() =>
    certificateItems
      .map((item) => archive.value?.[item.key])
      .filter((url): url is string => Boolean(url))
  )

  const attachmentColumns: ColumnOption<ArchiveAttachment>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    {
      prop: 'name',
      label: '档案附件名称',
      minWidth: 220,
      formatter: renderAttachmentLink
    },
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
        <div>
          <ArtButtonTable type="view" onClick={() => viewAttachment(row)} />
        </div>
      )
    }
  ]

  const loadArchiveDetail = async (): Promise<void> => {
    const id = String(route.params.id || '')
    if (!id) {
      loadError.value = new Error('缺少车辆档案标识')
      return
    }
    loading.value = true
    loadError.value = null
    try {
      const { data } = await fetchVehicleArchiveDetail(id)
      if (!data) return

      archive.value = { ...data, attachments: data.attachments ?? [] }
      auditForm.auditStatus = data.auditStatus === 'rejected' ? 'rejected' : 'approved'
      auditForm.auditRemark = data.auditRemark ?? ''
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('车辆档案详情加载失败')
    } finally {
      loading.value = false
    }
  }

  const handleSaveAudit = async (): Promise<void> => {
    if (!archive.value?.id) return

    savingAudit.value = true
    try {
      await auditVehicleArchive({
        id: archive.value.id,
        auditStatus: auditForm.auditStatus,
        auditRemark: auditForm.auditRemark
      })
      await goBack()
    } finally {
      savingAudit.value = false
    }
  }

  const goBack = async (): Promise<void> => {
    const source =
      route.query.source === 'manage' ? 'vehicle-archive-manage' : 'vehicle-archive-entry'
    await router.push(`/vehicle-manage-system/archive-manage/${source}`)
  }

  const formatValue = (value: InfoItem['value'], suffix = ''): VNodeChild => {
    if (value === undefined || value === null || value === '') return '--'
    if (typeof value !== 'string' && typeof value !== 'number') return value
    return suffix ? `${value}${suffix}` : String(value)
  }

  const getDictLabel = (dictCode: string, value?: string): VNodeChild => {
    return (
      <ArtDictDisplay dictCode={dictCode} value={value} display="text" emptyText={value || '--'} />
    )
  }

  const getBooleanDictLabel = (value?: boolean | null): VNodeChild =>
    getDictLabel('commonBoolean', value === undefined || value === null ? undefined : String(value))
</script>

<style scoped lang="scss">
  .vehicle-archive-detail {
    min-height: 100%;
    padding: 16px;
    background: var(--art-main-bg-color);

    &__header {
      :deep(.art-page-header__title-row) {
        width: 100%;
      }
    }

    &__identity {
      display: flex;
      gap: 14px;
      align-items: center;
      min-width: 0;
    }

    &__identity-copy {
      display: grid;
      gap: 8px;
      min-width: 0;

      > p {
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 13px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }
    }

    &__identity-primary {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      align-items: center;
      min-width: 0;
    }

    &__vehicle-photo {
      flex: none;

      :deep(.upload-container) {
        box-shadow: 0 4px 12px rgb(15 23 42 / 8%);
      }
    }

    &__vehicle-photo-empty {
      display: inline-flex;
      flex: none;
      align-items: center;
      justify-content: center;
      width: 88px;
      height: 88px;
      font-size: 28px;
      color: var(--theme-color);
      background: var(--el-fill-color-lighter);
      border: 1px dashed var(--el-border-color);
      border-radius: var(--el-border-radius-base);
    }

    h1 {
      min-width: 0;
      margin: 0;
      overflow: hidden;
      text-overflow: ellipsis;
      font-size: var(--art-font-size-page-title);
      font-weight: 650;
      line-height: var(--art-line-height-title);
      color: var(--el-text-color-primary);
      white-space: nowrap;
    }

    &__header-statuses {
      display: inline-flex;
      gap: 8px;
      align-items: center;
    }

    &__tabs {
      padding: 0 20px 24px;
      margin-top: 12px;

      :deep(.el-tabs__header) {
        margin-bottom: 20px;
      }
    }

    &__descriptions {
      overflow: hidden;
      border-radius: var(--el-border-radius-base);

      :deep(.el-descriptions__label) {
        width: 132px;
        font-weight: 600;
        color: var(--el-text-color-regular);
        background: var(--el-fill-color-lighter);
      }

      :deep(.vehicle-archive-detail__description-content) {
        min-width: 180px;
        color: var(--el-text-color-primary);
        overflow-wrap: anywhere;
      }
    }

    &__section {
      margin-top: 24px;
    }

    &__certificate-panel {
      padding: 18px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__section-heading {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 16px;

      > div {
        min-width: 0;

        :deep(.art-section-title) {
          margin: 0;
        }

        p {
          margin: 4px 0 0;
          font-size: 12px;
          color: var(--el-text-color-secondary);
        }
      }

      > span {
        flex: none;
        padding: 5px 10px;
        font-size: 12px;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 9%, var(--el-bg-color));
        border-radius: 999px;
      }
    }

    &__images {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 16px;
    }

    &__image-item {
      min-width: 0;
      overflow: hidden;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > header {
        display: flex;
        gap: 10px;
        align-items: center;
        justify-content: space-between;
        padding: 11px 12px;
        border-bottom: 1px solid var(--el-border-color-lighter);

        strong {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 13px;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }

        span {
          flex: none;
          font-size: 11px;
          color: var(--el-text-color-placeholder);

          &.is-ready {
            color: var(--el-color-success);
          }
        }
      }

      :deep(.el-image),
      .vehicle-archive-detail__image-empty {
        width: 100%;
        height: 180px;
      }

      :deep(.el-image) {
        display: block;
        cursor: zoom-in;
        background: var(--el-fill-color-lighter);
      }
    }

    &__image-empty {
      display: flex;
      flex-direction: column;
      gap: 8px;
      align-items: center;
      justify-content: center;
      font-size: 12px;
      color: var(--el-text-color-placeholder);
      background: var(--el-fill-color-lighter);

      .art-svg-icon {
        font-size: 28px;
      }

      &.is-error {
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
      }
    }

    &__audit {
      margin-top: 12px;
    }

    @media (width <= 760px) {
      padding: 12px;

      &__descriptions {
        :deep(.el-descriptions__label) {
          width: 108px;
        }
      }

      &__images {
        grid-template-columns: 1fr;
      }

      &__image-item {
        :deep(.el-image),
        .vehicle-archive-detail__image-empty {
          height: clamp(180px, 52vw, 260px);
        }
      }

      &__section-heading {
        align-items: center;
      }
    }
  }
</style>
