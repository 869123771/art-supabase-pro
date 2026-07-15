<template>
  <div class="vehicle-archive-detail" v-loading="loading">
    <div class="vehicle-archive-detail__header art-card-xs">
      <div>
        <h2>{{ archive?.plateNo || '车辆档案详情' }}</h2>
        <p>{{ archive?.companyName || '--' }}</p>
      </div>
      <div class="vehicle-archive-detail__actions">
        <ElButton @click="goBack">返回</ElButton>
      </div>
    </div>

    <ElTabs v-model="activeTab" class="vehicle-archive-detail__tabs art-card-xs">
      <ElTabPane label="基础信息" name="basic">
        <InfoDescriptions :items="basicInfoItems" />
        <section class="vehicle-archive-detail__section">
          <ArtSectionTitle>车辆证件</ArtSectionTitle>
          <div class="vehicle-archive-detail__images">
            <div
              v-for="item in certificateItems"
              :key="item.key"
              class="vehicle-archive-detail__image-item"
            >
              <ElImage
                v-if="archive?.[item.key]"
                :src="archive[item.key]"
                fit="cover"
                :preview-src-list="[archive[item.key] || '']"
              />
              <div v-else class="vehicle-archive-detail__image-empty">--</div>
              <span>{{ item.label }}</span>
            </div>
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
    </ElTabs>

    <ElCard v-if="showAuditPanel" class="vehicle-archive-detail__audit art-card-xs" shadow="never">
      <template #header>
        <span>审核状态</span>
      </template>
      <ElForm label-width="90px">
        <ElFormItem label="审核状态" required>
          <ElRadioGroup v-model="auditForm.auditStatus">
            <ElRadio v-for="option in auditStatusOptions" :key="option.value" :value="option.value">
              {{ option.label }}
            </ElRadio>
          </ElRadioGroup>
        </ElFormItem>
        <ElFormItem label="备注">
          <ElInput
            v-model="auditForm.auditRemark"
            type="textarea"
            :rows="4"
            maxlength="500"
            show-word-limit
          />
        </ElFormItem>
        <ElFormItem>
          <ElButton type="primary" :loading="savingAudit" @click="handleSaveAudit">
            保存审核
          </ElButton>
        </ElFormItem>
      </ElForm>
    </ElCard>
  </div>
</template>

<script setup lang="tsx">
  import type { VNodeChild } from 'vue'
  import {
    ElButton,
    ElCard,
    ElDescriptions,
    ElDescriptionsItem,
    ElForm,
    ElFormItem,
    ElImage,
    ElInput,
    ElRadio,
    ElRadioGroup,
    ElTabPane,
    ElTabs
  } from 'element-plus'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
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
  type ImageKey =
    | 'vehiclePhotoUrl'
    | 'drivingLicenseFrontUrl'
    | 'drivingLicenseBackUrl'
    | 'operationLicenseUrl'

  interface InfoItem {
    label: string
    value: VNodeChild
    suffix?: string
  }

  const InfoDescriptions = defineComponent({
    props: {
      items: {
        type: Array as PropType<InfoItem[]>,
        required: true
      }
    },
    setup(props) {
      return () => (
        <ElDescriptions class="vehicle-archive-detail__descriptions" column={3} border>
          {props.items.map((item) => (
            <ElDescriptionsItem
              key={item.label}
              label={item.label}
              labelClassName="vehicle-archive-detail__description-label"
              className="vehicle-archive-detail__description-content"
            >
              {formatValue(item.value, item.suffix)}
            </ElDescriptionsItem>
          ))}
        </ElDescriptions>
      )
    }
  })

  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const activeTab = ref('basic')
  const archive = ref<VehicleArchive>()
  const loading = ref(false)
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
    { key: 'vehiclePhotoUrl', label: '车辆照片' },
    { key: 'drivingLicenseFrontUrl', label: '行驶证正页' },
    { key: 'drivingLicenseBackUrl', label: '行驶证副页' },
    { key: 'operationLicenseUrl', label: '运营证照片' }
  ]

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
    if (!id) return
    loading.value = true
    try {
      const { data } = await fetchVehicleArchiveDetail(id)
      if (!data) return

      archive.value = { ...data, attachments: data.attachments ?? [] }
      auditForm.auditStatus = data.auditStatus === 'rejected' ? 'rejected' : 'approved'
      auditForm.auditRemark = data.auditRemark ?? ''
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
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 18px 20px;
      margin-bottom: 12px;

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

    &__actions {
      display: flex;
      gap: 8px;
    }

    &__tabs {
      padding: 16px 20px 24px;
    }

    &__descriptions {
      :deep(.vehicle-archive-detail__description-label) {
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

    &__images {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
      gap: 16px;
      max-width: 760px;
    }

    &__image-item {
      display: flex;
      flex-direction: column;
      gap: 8px;
      align-items: center;

      :deep(.el-image),
      .vehicle-archive-detail__image-empty {
        width: 128px;
        height: 128px;
        border: 1px solid var(--el-border-color);
        border-radius: var(--el-border-radius-base);
      }
    }

    &__image-empty {
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--el-text-color-placeholder);
      background: var(--el-fill-color-lighter);
    }

    &__audit {
      margin-top: 12px;
    }

    @media (max-width: 1100px) {
      &__descriptions {
        :deep(.el-descriptions__body) {
          overflow-x: auto;
        }
      }
    }

    @media (max-width: 760px) {
      &__header {
        align-items: flex-start;
        flex-direction: column;
        gap: 12px;
      }

      &__descriptions {
        :deep(.vehicle-archive-detail__description-label) {
          width: 108px;
        }
      }
    }
  }
</style>
