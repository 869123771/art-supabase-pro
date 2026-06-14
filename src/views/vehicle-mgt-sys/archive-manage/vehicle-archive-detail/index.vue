<template>
  <div class="vehicle-archive-detail">
    <div class="vehicle-archive-detail__header">
      <div>
        <h2>{{ archive?.plateNo || '车辆档案详情' }}</h2>
        <p>{{ archive?.companyName || '--' }}</p>
      </div>
      <div class="vehicle-archive-detail__actions">
        <ElButton @click="goBack">返回</ElButton>
        <ElButton type="primary" @click="openEditPage">编辑</ElButton>
      </div>
    </div>

    <ElTabs v-model="activeTab" class="vehicle-archive-detail__tabs">
      <ElTabPane label="基础信息" name="basic">
        <InfoGrid :items="basicInfoItems" />
        <section class="vehicle-archive-detail__section">
          <h3>车辆证件</h3>
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
        <InfoGrid :items="bodyInfoItems" />
      </ElTabPane>

      <ElTabPane label="发动机参数" name="engine">
        <InfoGrid :items="engineInfoItems" />
      </ElTabPane>

      <ElTabPane label="其他信息" name="other">
        <InfoGrid :items="otherInfoItems" />
        <section class="vehicle-archive-detail__section">
          <h3>车辆档案附件</h3>
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

    <ElCard class="vehicle-archive-detail__audit" shadow="never">
      <template #header>
        <span>审核状态</span>
      </template>
      <ElForm label-width="90px">
        <ElFormItem label="审核状态" required>
          <ElRadioGroup v-model="auditForm.auditStatus">
            <ElRadio value="approved">通过</ElRadio>
            <ElRadio value="rejected">未通过</ElRadio>
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
          <ElButton type="primary" :loading="savingAudit" @click="handleSaveAudit"
            >保存审核</ElButton
          >
        </ElFormItem>
      </ElForm>
    </ElCard>
  </div>
</template>

<script setup lang="tsx">
  import {
    ElButton,
    ElCard,
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
  import type { ColumnOption } from '@/types'
  import { auditVehicleArchive, fetchVehicleArchiveDetail } from '@/api/vehicle-mgt-sys'

  defineOptions({ name: 'VehicleArchiveDetail' })

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
    value: string | number | null | undefined
    suffix?: string
  }

  const InfoGrid = defineComponent({
    props: {
      items: {
        type: Array as PropType<InfoItem[]>,
        required: true
      }
    },
    setup(props) {
      return () => (
        <div class="vehicle-archive-detail__grid">
          {props.items.map((item) => (
            <div class="vehicle-archive-detail__grid-item">
              <span>{item.label}</span>
              <strong>{formatValue(item.value, item.suffix)}</strong>
            </div>
          ))}
        </div>
      )
    }
  })

  const route = useRoute()
  const router = useRouter()
  const activeTab = ref('basic')
  const archive = ref<VehicleArchive>()
  const savingAudit = ref(false)
  const auditForm = reactive<{
    auditStatus: AuditStatus
    auditRemark: string
  }>({
    auditStatus: 'approved',
    auditRemark: ''
  })

  onMounted(() => {
    void loadArchiveDetail()
  })

  const basicInfoItems = computed<InfoItem[]>(() => [
    { label: '车牌号', value: archive.value?.plateNo },
    { label: '所属公司', value: archive.value?.companyName },
    { label: '自编号', value: archive.value?.selfNo },
    { label: '车型', value: getOptionLabel(vehicleTypeOptions, archive.value?.vehicleType) },
    { label: '国产/进口', value: getOptionLabel(originTypeOptions, archive.value?.originType) },
    { label: '车架号（VIN）', value: archive.value?.vin },
    { label: '车辆厂商', value: archive.value?.manufacturer },
    { label: '厂牌型号', value: archive.value?.brandModel },
    { label: '营运证号', value: archive.value?.operationCertNo },
    { label: '购置证号', value: archive.value?.purchaseCertNo },
    { label: '登记证号', value: archive.value?.registrationCertNo },
    { label: '车身颜色', value: getOptionLabel(colorOptions, archive.value?.vehicleColor) },
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
    { label: '业务类型', value: getOptionLabel(businessTypeOptions, archive.value?.businessType) },
    { label: '是否空调车', value: formatBoolean(archive.value?.isAirConditioned) },
    {
      label: '营运状态',
      value: getOptionLabel(operationStatusOptions, archive.value?.operationStatus)
    },
    { label: '营运状态变更', value: archive.value?.operationStatusChangeDate },
    {
      label: '购置状态',
      value: getOptionLabel(purchaseStatusOptions, archive.value?.purchaseStatus)
    },
    { label: '购置状态变更', value: archive.value?.purchaseStatusChangeDate },
    { label: '例检启用日期', value: archive.value?.inspectionStartDate },
    { label: '车辆等级', value: getOptionLabel(vehicleLevelOptions, archive.value?.vehicleLevel) },
    { label: '是否新能源车', value: formatBoolean(archive.value?.isNewEnergy) },
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
    { label: '是否双层', value: formatBoolean(archive.value?.isDoubleDeck) }
  ])

  const engineInfoItems = computed<InfoItem[]>(() => [
    { label: '发动机号', value: archive.value?.engineNo },
    { label: '发动机型号', value: archive.value?.engineModel },
    { label: '燃油类型', value: getOptionLabel(fuelTypeOptions, archive.value?.fuelType) },
    { label: '发动机排量', value: archive.value?.displacement, suffix: 'L' },
    {
      label: '排放标准',
      value: getOptionLabel(emissionStandardOptions, archive.value?.emissionStandard)
    },
    { label: '发动机功率', value: archive.value?.enginePower, suffix: 'KW' },
    { label: '额定扭矩转速', value: archive.value?.ratedTorqueSpeed, suffix: 'r/min' },
    { label: '发动机扭矩', value: archive.value?.engineTorque, suffix: 'N-M' }
  ])

  const otherInfoItems = computed<InfoItem[]>(() => [
    { label: '车牌颜色', value: getOptionLabel(colorOptions, archive.value?.plateColor) },
    {
      label: '运输行业',
      value: getOptionLabel(transportIndustryOptions, archive.value?.transportIndustry)
    },
    {
      label: '营运类型',
      value: getOptionLabel(operationTypeOptions, archive.value?.operationType)
    },
    { label: '业户ID', value: archive.value?.ownerId },
    { label: '业户名称', value: archive.value?.ownerName },
    { label: '业户联系电话', value: archive.value?.ownerPhone },
    { label: '车载终端电话', value: archive.value?.terminalPhone },
    { label: '车主性别', value: getOptionLabel(genderOptions, archive.value?.ownerGender) },
    { label: '身份证号码', value: archive.value?.idCardNo },
    { label: '通讯地址', value: archive.value?.mailingAddress },
    { label: '吨位/座位', value: archive.value?.tonnageOrSeat },
    { label: '驾驶员一名称', value: archive.value?.driverOneName },
    { label: '驾驶员一电话', value: archive.value?.driverOnePhone },
    { label: '驾驶员二名称', value: archive.value?.driverTwoName },
    { label: '驾驶员二电话', value: archive.value?.driverTwoPhone },
    { label: '营运线路', value: archive.value?.operationRoute },
    { label: '车籍地代码', value: archive.value?.licensePlateCode },
    { label: '服务开始时间', value: archive.value?.serviceStartTime },
    { label: '服务结束时间', value: archive.value?.serviceEndTime },
    { label: '支持拍照', value: formatBoolean(archive.value?.supportPhoto) }
  ])

  const certificateItems: Array<{ key: ImageKey; label: string }> = [
    { key: 'vehiclePhotoUrl', label: '车辆照片' },
    { key: 'drivingLicenseFrontUrl', label: '行驶证正页' },
    { key: 'drivingLicenseBackUrl', label: '行驶证副页' },
    { key: 'operationLicenseUrl', label: '运营证照片' }
  ]

  const attachmentColumns: ColumnOption<ArchiveAttachment>[] = [
    { type: 'globalIndex', label: '序号', width: 80 },
    { prop: 'name', label: '档案附件名称', minWidth: 220 },
    { prop: 'fileType', label: '格式类型', width: 120 },
    { prop: 'fileSize', label: '附件大小', width: 120 },
    {
      prop: 'operation',
      label: '操作',
      width: 120,
      formatter: (row) => (
        <div>
          <ArtButtonTable type="view" onClick={() => window.open(row.url, '_blank')} />
        </div>
      )
    }
  ]

  const loadArchiveDetail = async (): Promise<void> => {
    const id = String(route.params.id || '')
    if (!id) return
    const { data } = await fetchVehicleArchiveDetail(id)
    if (!data) return

    archive.value = { ...data, attachments: data.attachments ?? [] }
    auditForm.auditStatus = data.auditStatus === 'rejected' ? 'rejected' : 'approved'
    auditForm.auditRemark = data.auditRemark || ''
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
      await loadArchiveDetail()
    } finally {
      savingAudit.value = false
    }
  }

  const openEditPage = (): void => {
    if (!archive.value?.id) return
    void router.push(`/vehicle-mgt-sys/archive-manage/vehicle-archive-edit/${archive.value.id}`)
  }

  const goBack = (): void => {
    void router.push('/vehicle-mgt-sys/archive-manage/vehicle-archive-entry')
  }

  const formatValue = (value: InfoItem['value'], suffix = ''): string => {
    if (value === undefined || value === null || value === '') return '--'
    return suffix ? `${value}${suffix}` : String(value)
  }

  const formatBoolean = (value?: boolean): string => {
    if (value === undefined || value === null) return '--'
    return value ? '是' : '否'
  }

  const getOptionLabel = (options: Array<{ label: string; value: string }>, value?: string) => {
    return options.find((item) => item.value === value)?.label || value || ''
  }

  const vehicleTypeOptions = [
    { label: '大型城市客车', value: 'large-city-bus' },
    { label: '中型客车', value: 'medium-bus' },
    { label: '小型客车', value: 'small-bus' },
    { label: '货车', value: 'truck' },
    { label: '专用车', value: 'special-vehicle' }
  ]
  const originTypeOptions = [
    { label: '国产', value: 'domestic' },
    { label: '进口', value: 'imported' }
  ]
  const colorOptions = [
    { label: '蓝色', value: 'blue' },
    { label: '黄色', value: 'yellow' },
    { label: '绿色', value: 'green' },
    { label: '白色', value: 'white' },
    { label: '黑色', value: 'black' },
    { label: '其他', value: 'other' }
  ]
  const businessTypeOptions = [
    { label: '公交线路车', value: 'bus-line' },
    { label: '旅游客运', value: 'tourism' },
    { label: '包车客运', value: 'charter' },
    { label: '货运', value: 'freight' }
  ]
  const operationStatusOptions = [
    { label: '营运', value: 'operating' },
    { label: '停运', value: 'stopped' },
    { label: '维修', value: 'maintenance' },
    { label: '报废', value: 'scrapped' }
  ]
  const purchaseStatusOptions = [
    { label: '新购置', value: 'new' },
    { label: '转入', value: 'transferred' },
    { label: '租赁', value: 'leased' }
  ]
  const vehicleLevelOptions = [
    { label: '城市公交车', value: 'city-bus' },
    { label: '一级车', value: 'level-1' },
    { label: '二级车', value: 'level-2' },
    { label: '三级车', value: 'level-3' }
  ]
  const fuelTypeOptions = [
    { label: '纯电动车', value: 'electric' },
    { label: '柴油', value: 'diesel' },
    { label: '汽油', value: 'gasoline' },
    { label: '天然气', value: 'gas' },
    { label: '混合动力', value: 'hybrid' }
  ]
  const emissionStandardOptions = [
    { label: '国V及以上', value: 'china-v-plus' },
    { label: '国IV', value: 'china-iv' },
    { label: '国III', value: 'china-iii' }
  ]
  const transportIndustryOptions = [
    { label: '城市公交', value: 'city-bus' },
    { label: '道路客运', value: 'road-passenger' },
    { label: '道路货运', value: 'road-freight' }
  ]
  const operationTypeOptions = [
    { label: '公交车', value: 'bus' },
    { label: '班线客车', value: 'line-bus' },
    { label: '旅游客车', value: 'tour-bus' }
  ]
  const genderOptions = [
    { label: '男', value: 'male' },
    { label: '女', value: 'female' }
  ]
</script>

<style scoped lang="scss">
  .vehicle-archive-detail {
    min-height: 100%;
    padding: 16px;
    background: var(--art-main-bg-color);

    &__header,
    &__tabs,
    &__audit {
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-light);
      border-radius: 8px;
    }

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

    &__grid {
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 18px 28px;
    }

    &__grid-item {
      display: grid;
      grid-template-columns: 120px minmax(0, 1fr);
      gap: 12px;
      min-height: 32px;
      align-items: center;

      span {
        font-weight: 600;
        color: var(--el-text-color-regular);
      }

      strong {
        min-width: 0;
        font-weight: 400;
        color: var(--el-text-color-secondary);
        overflow-wrap: anywhere;
      }
    }

    &__section {
      margin-top: 24px;

      h3 {
        margin: 0 0 14px;
        font-size: 16px;
        font-weight: 600;
      }
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
        border-radius: 8px;
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
      &__grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (max-width: 760px) {
      &__header {
        align-items: flex-start;
        flex-direction: column;
        gap: 12px;
      }

      &__grid {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
