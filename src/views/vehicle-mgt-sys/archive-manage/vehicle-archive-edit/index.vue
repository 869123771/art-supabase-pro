<template>
  <div class="vehicle-archive-edit">
    <div class="vehicle-archive-edit__header">
      <div>
        <h2>{{ isEdit ? '编辑车辆档案' : '新增车辆档案' }}</h2>
        <p>维护车辆基础资料、车身参数、发动机参数和运营信息。</p>
      </div>
      <div class="vehicle-archive-edit__actions">
        <ElButton @click="goBack">返回</ElButton>
        <ElButton type="primary" :loading="saving" @click="handleSave">保存</ElButton>
      </div>
    </div>

    <ElTabs v-model="activeTab" class="vehicle-archive-edit__tabs">
      <ElTabPane label="基础信息" name="basic">
        <ArtForm
          ref="basicFormRef"
          v-model="form"
          :items="basicItems"
          :rules="rules"
          :span="8"
          :gutter="20"
          label-width="130px"
          :show-reset="false"
          :show-submit="false"
        />

        <section class="vehicle-archive-edit__section">
          <h3>车辆证件</h3>
          <div class="vehicle-archive-edit__images">
            <div
              v-for="item in certificateItems"
              :key="item.key"
              class="vehicle-archive-edit__image-item"
            >
              <ArtUploadImage v-model="form[item.key]" :title="item.label" :size="128" />
              <span>{{ item.label }}</span>
            </div>
          </div>
        </section>
      </ElTabPane>

      <ElTabPane label="车身参数" name="body">
        <ArtForm
          ref="bodyFormRef"
          v-model="form"
          :items="bodyItems"
          :span="8"
          :gutter="20"
          label-width="130px"
          :show-reset="false"
          :show-submit="false"
        />
      </ElTabPane>

      <ElTabPane label="发动机参数" name="engine">
        <ArtForm
          ref="engineFormRef"
          v-model="form"
          :items="engineItems"
          :span="8"
          :gutter="20"
          label-width="130px"
          :show-reset="false"
          :show-submit="false"
        />
      </ElTabPane>

      <ElTabPane label="其他信息" name="other">
        <ArtForm
          ref="otherFormRef"
          v-model="form"
          :items="otherItems"
          :span="8"
          :gutter="20"
          label-width="130px"
          :show-reset="false"
          :show-submit="false"
        />

        <section class="vehicle-archive-edit__section">
          <div class="vehicle-archive-edit__section-header">
            <h3>车辆档案附件</h3>
            <ElUpload :show-file-list="false" :http-request="handleAttachmentUpload">
              <ElButton type="primary" plain>上传附件</ElButton>
            </ElUpload>
          </div>
          <ArtTable
            :data="form.attachments"
            :columns="attachmentColumns"
            :pagination="undefined"
            :show-table-header="false"
            empty-height="180px"
          />
        </section>
      </ElTabPane>
    </ElTabs>
  </div>
</template>

<script setup lang="tsx">
  import type { FormRules, UploadRequestOptions } from 'element-plus'
  import { ElButton, ElMessage, ElMessageBox, ElTabPane, ElTabs, ElUpload } from 'element-plus'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    addVehicleArchive,
    editVehicleArchive,
    fetchVehicleArchiveDetail
  } from '@/api/vehicle-mgt-sys'
  import { uploadAttachment } from '@/api/common'

  defineOptions({ name: 'VehicleArchiveEdit' })

  type VehicleArchive = Api.VehicleMgtSys.ArchiveManage.VehicleArchive
  type ArchiveAttachment = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveAttachment
  type ImageKey =
    | 'vehiclePhotoUrl'
    | 'drivingLicenseFrontUrl'
    | 'drivingLicenseBackUrl'
    | 'operationLicenseUrl'

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const route = useRoute()
  const router = useRouter()
  const activeTab = ref('basic')
  const saving = ref(false)
  const basicFormRef = ref<FormExpose>()
  const bodyFormRef = ref<FormExpose>()
  const engineFormRef = ref<FormExpose>()
  const otherFormRef = ref<FormExpose>()

  const isEdit = computed(() => typeof route.params.id === 'string' && route.params.id.length > 0)

  const createInitialForm = (): VehicleArchive => ({
    id: undefined,
    plateNo: '',
    companyName: '',
    selfNo: '',
    vehicleType: '',
    originType: 'domestic',
    vin: '',
    manufacturer: '',
    brandModel: '',
    operationCertNo: '',
    purchaseCertNo: '',
    registrationCertNo: '',
    vehicleColor: '',
    chassisNo: '',
    acCode: '',
    gearboxSerialNo: '',
    registerDate: '',
    issueDate: '',
    invoiceDate: '',
    startUseDate: '',
    serviceYears: null,
    approvedPassengerCount: null,
    seatCount: null,
    businessType: '',
    isAirConditioned: false,
    operationStatus: 'operating',
    operationStatusChangeDate: '',
    purchaseStatus: '',
    purchaseStatusChangeDate: '',
    inspectionStartDate: '',
    vehicleLevel: '',
    isNewEnergy: false,
    threeGuaranteeMileage: null,
    threeGuaranteeDuration: null,
    warrantyMileage: null,
    warrantyDuration: null,
    remark: '',
    grossMass: null,
    curbWeight: null,
    approvedLoadMass: null,
    overallLength: null,
    overallWidth: null,
    overallHeight: null,
    platform: '',
    frontTrack: null,
    rearTrack: null,
    wheelbase: null,
    axleCount: null,
    tireCount: null,
    leafSpringCount: null,
    isDoubleDeck: false,
    engineNo: '',
    engineModel: '',
    fuelType: '',
    displacement: null,
    emissionStandard: '',
    enginePower: null,
    ratedTorqueSpeed: null,
    engineTorque: null,
    plateColor: '',
    transportIndustry: '',
    operationType: '',
    ownerId: '',
    ownerName: '',
    ownerPhone: '',
    terminalPhone: '',
    ownerGender: '',
    idCardNo: '',
    mailingAddress: '',
    tonnageOrSeat: '',
    driverOneName: '',
    driverOnePhone: '',
    driverTwoName: '',
    driverTwoPhone: '',
    operationRoute: '',
    licensePlateCode: '',
    serviceStartTime: '',
    serviceEndTime: '',
    supportPhoto: false,
    vehiclePhotoUrl: '',
    drivingLicenseFrontUrl: '',
    drivingLicenseBackUrl: '',
    operationLicenseUrl: '',
    attachments: [],
    auditStatus: 'pending',
    auditRemark: ''
  })

  const form = reactive<VehicleArchive>(createInitialForm())

  const rules: FormRules<VehicleArchive> = {
    plateNo: [{ required: true, message: '请输入车牌号', trigger: 'blur' }],
    companyName: [{ required: true, message: '请输入所属公司', trigger: 'blur' }],
    vehicleType: [{ required: true, message: '请选择车型', trigger: 'change' }],
    vin: [{ required: true, message: '请输入车架号（VIN）', trigger: 'blur' }],
    registerDate: [{ required: true, message: '请选择登记日期', trigger: 'change' }],
    issueDate: [{ required: true, message: '请选择发证日期', trigger: 'change' }],
    invoiceDate: [{ required: true, message: '请选择购入开票日期', trigger: 'change' }],
    startUseDate: [{ required: true, message: '请选择启用日期', trigger: 'change' }],
    serviceYears: [{ required: true, message: '请输入使用年限', trigger: 'blur' }],
    approvedPassengerCount: [{ required: true, message: '请输入核定乘员数', trigger: 'blur' }],
    operationStatus: [{ required: true, message: '请选择营运状态', trigger: 'change' }],
    threeGuaranteeMileage: [{ required: true, message: '请输入整车三包里程', trigger: 'blur' }],
    threeGuaranteeDuration: [{ required: true, message: '请输入整车三包时长', trigger: 'blur' }],
    warrantyMileage: [{ required: true, message: '请输入整车包修里程', trigger: 'blur' }],
    warrantyDuration: [{ required: true, message: '请输入整车包修时长', trigger: 'blur' }]
  }

  const basicItems = computed<FormItem[]>(() => [
    { label: '车牌号', key: 'plateNo', type: 'input' },
    { label: '所属公司', key: 'companyName', type: 'input' },
    { label: '自编号', key: 'selfNo', type: 'input' },
    { label: '车型', key: 'vehicleType', type: 'select', props: { options: vehicleTypeOptions } },
    {
      label: '国产/进口',
      key: 'originType',
      type: 'radioGroup',
      props: { options: originTypeOptions }
    },
    { label: '车架号（VIN）', key: 'vin', type: 'input' },
    { label: '车辆厂商', key: 'manufacturer', type: 'input' },
    { label: '厂牌型号', key: 'brandModel', type: 'input' },
    { label: '营运证号', key: 'operationCertNo', type: 'input' },
    { label: '购置证号', key: 'purchaseCertNo', type: 'input' },
    { label: '登记证号', key: 'registrationCertNo', type: 'input' },
    { label: '车身颜色', key: 'vehicleColor', type: 'select', props: { options: colorOptions } },
    { label: '底盘号', key: 'chassisNo', type: 'input' },
    { label: '空调号码', key: 'acCode', type: 'input' },
    { label: '波箱系列号', key: 'gearboxSerialNo', type: 'input' },
    { label: '登记日期', key: 'registerDate', type: 'date', props: dateProps },
    { label: '发证日期', key: 'issueDate', type: 'date', props: dateProps },
    { label: '购入开票日期', key: 'invoiceDate', type: 'date', props: dateProps },
    { label: '启用日期', key: 'startUseDate', type: 'date', props: dateProps },
    {
      label: '使用年限',
      key: 'serviceYears',
      type: 'number',
      description: '单位：年',
      props: numberProps
    },
    {
      label: '核定乘员数',
      key: 'approvedPassengerCount',
      type: 'number',
      description: '单位：人',
      props: numberProps
    },
    { label: '座位数', key: 'seatCount', type: 'number', props: numberProps },
    {
      label: '业务类型',
      key: 'businessType',
      type: 'select',
      props: { options: businessTypeOptions }
    },
    {
      label: '是否空调车',
      key: 'isAirConditioned',
      type: 'radioGroup',
      props: { options: yesNoOptions }
    },
    {
      label: '营运状态',
      key: 'operationStatus',
      type: 'select',
      props: { options: operationStatusOptions }
    },
    { label: '营运状态变更', key: 'operationStatusChangeDate', type: 'date', props: dateProps },
    {
      label: '购置状态',
      key: 'purchaseStatus',
      type: 'select',
      props: { options: purchaseStatusOptions }
    },
    { label: '购置状态变更', key: 'purchaseStatusChangeDate', type: 'date', props: dateProps },
    { label: '例检启用日期', key: 'inspectionStartDate', type: 'date', props: dateProps },
    {
      label: '车辆等级',
      key: 'vehicleLevel',
      type: 'select',
      props: { options: vehicleLevelOptions }
    },
    {
      label: '是否新能源车',
      key: 'isNewEnergy',
      type: 'radioGroup',
      props: { options: yesNoOptions }
    },
    {
      label: '整车三包里程',
      key: 'threeGuaranteeMileage',
      type: 'number',
      description: '单位：公里',
      props: numberProps
    },
    {
      label: '整车三包时长',
      key: 'threeGuaranteeDuration',
      type: 'number',
      description: '单位：个月',
      props: numberProps
    },
    {
      label: '整车包修里程',
      key: 'warrantyMileage',
      type: 'number',
      description: '单位：公里',
      props: numberProps
    },
    {
      label: '整车包修时长',
      key: 'warrantyDuration',
      type: 'number',
      description: '单位：个月',
      props: numberProps
    },
    { label: '备注', key: 'remark', type: 'input', span: 24, props: { type: 'textarea', rows: 3 } }
  ])

  const bodyItems = computed<FormItem[]>(() => [
    {
      label: '满载总质量',
      key: 'grossMass',
      type: 'number',
      description: 'kg',
      props: numberProps
    },
    { label: '整备质量', key: 'curbWeight', type: 'number', description: 'kg', props: numberProps },
    {
      label: '核定载质量',
      key: 'approvedLoadMass',
      type: 'number',
      description: 'kg',
      props: numberProps
    },
    {
      label: '外廓长度',
      key: 'overallLength',
      type: 'number',
      description: 'mm',
      props: numberProps
    },
    {
      label: '外廓宽度',
      key: 'overallWidth',
      type: 'number',
      description: 'mm',
      props: numberProps
    },
    {
      label: '外廓高度',
      key: 'overallHeight',
      type: 'number',
      description: 'mm',
      props: numberProps
    },
    { label: '标台', key: 'platform', type: 'input' },
    { label: '前轮距', key: 'frontTrack', type: 'number', description: 'mm', props: numberProps },
    { label: '后轮距', key: 'rearTrack', type: 'number', description: 'mm', props: numberProps },
    { label: '轴距', key: 'wheelbase', type: 'number', props: numberProps },
    { label: '车轴数', key: 'axleCount', type: 'number', props: numberProps },
    { label: '轮胎数', key: 'tireCount', type: 'number', props: numberProps },
    {
      label: '钢板弹簧数',
      key: 'leafSpringCount',
      type: 'number',
      description: '片',
      props: numberProps
    },
    { label: '是否双层', key: 'isDoubleDeck', type: 'radioGroup', props: { options: yesNoOptions } }
  ])

  const engineItems = computed<FormItem[]>(() => [
    { label: '发动机号', key: 'engineNo', type: 'input' },
    { label: '发动机型号', key: 'engineModel', type: 'input' },
    { label: '燃油类型', key: 'fuelType', type: 'select', props: { options: fuelTypeOptions } },
    {
      label: '发动机排量',
      key: 'displacement',
      type: 'number',
      description: 'L',
      props: numberProps
    },
    {
      label: '排放标准',
      key: 'emissionStandard',
      type: 'select',
      props: { options: emissionStandardOptions }
    },
    {
      label: '发动机功率',
      key: 'enginePower',
      type: 'number',
      description: 'KW',
      props: numberProps
    },
    {
      label: '额定扭矩转速',
      key: 'ratedTorqueSpeed',
      type: 'number',
      description: 'r/min',
      props: numberProps
    },
    {
      label: '发动机扭矩',
      key: 'engineTorque',
      type: 'number',
      description: 'N-M',
      props: numberProps
    }
  ])

  const otherItems = computed<FormItem[]>(() => [
    { label: '车牌颜色', key: 'plateColor', type: 'select', props: { options: colorOptions } },
    {
      label: '运输行业',
      key: 'transportIndustry',
      type: 'select',
      props: { options: transportIndustryOptions }
    },
    {
      label: '营运类型',
      key: 'operationType',
      type: 'select',
      props: { options: operationTypeOptions }
    },
    { label: '业户ID', key: 'ownerId', type: 'input' },
    { label: '业户名称', key: 'ownerName', type: 'input' },
    { label: '业户联系电话', key: 'ownerPhone', type: 'input' },
    { label: '车载终端电话', key: 'terminalPhone', type: 'input' },
    { label: '车主性别', key: 'ownerGender', type: 'select', props: { options: genderOptions } },
    { label: '身份证号码', key: 'idCardNo', type: 'input' },
    { label: '通讯地址', key: 'mailingAddress', type: 'input' },
    { label: '吨位/座位', key: 'tonnageOrSeat', type: 'input' },
    { label: '驾驶员一名称', key: 'driverOneName', type: 'input' },
    { label: '驾驶员一电话', key: 'driverOnePhone', type: 'input' },
    { label: '驾驶员二名称', key: 'driverTwoName', type: 'input' },
    { label: '驾驶员二电话', key: 'driverTwoPhone', type: 'input' },
    { label: '营运线路', key: 'operationRoute', type: 'input' },
    { label: '车籍地代码', key: 'licensePlateCode', type: 'input' },
    { label: '服务开始时间', key: 'serviceStartTime', type: 'date', props: dateProps },
    { label: '服务结束时间', key: 'serviceEndTime', type: 'date', props: dateProps },
    { label: '支持拍照', key: 'supportPhoto', type: 'radioGroup', props: { options: yesNoOptions } }
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
          <ArtButtonTable type="delete" onClick={() => removeAttachment(row)} />
        </div>
      )
    }
  ]

  onMounted(() => {
    void loadArchiveDetail()
  })

  const loadArchiveDetail = async (): Promise<void> => {
    if (!isEdit.value) return
    const id = String(route.params.id)
    const { data } = await fetchVehicleArchiveDetail(id)
    if (data) replaceForm({ ...createInitialForm(), ...data, attachments: data.attachments ?? [] })
  }

  const replaceForm = (nextForm: VehicleArchive): void => {
    Object.keys(form).forEach((key) => {
      delete form[key as keyof VehicleArchive]
    })
    Object.assign(form, nextForm)
  }

  const validateForms = async (): Promise<boolean> => {
    try {
      await basicFormRef.value?.validate()
      await bodyFormRef.value?.validate()
      await engineFormRef.value?.validate()
      await otherFormRef.value?.validate()
      return true
    } catch {
      activeTab.value = 'basic'
      return false
    }
  }

  const handleSave = async (): Promise<void> => {
    const valid = await validateForms()
    if (!valid) return

    saving.value = true
    try {
      const payload = toRaw(form)
      if (isEdit.value) {
        await editVehicleArchive(payload)
      } else {
        await addVehicleArchive(payload)
      }
      goBack()
    } finally {
      saving.value = false
    }
  }

  const handleAttachmentUpload = async (options: UploadRequestOptions): Promise<void> => {
    const [resource] = await uploadAttachment(options.file)
    const nextAttachment: ArchiveAttachment = {
      name: resource.origin_name,
      url: resource.url,
      fileType: resource.suffix ? `.${resource.suffix}` : '',
      fileSize: resource.size_info
    }
    form.attachments = [...(form.attachments ?? []), nextAttachment]
    ElMessage.success('附件上传成功')
  }

  const removeAttachment = async (row: ArchiveAttachment): Promise<void> => {
    try {
      await ElMessageBox.confirm(`确定删除附件“${row.name}”吗？`, '删除确认', {
        confirmButtonText: '删除',
        cancelButtonText: '取消',
        type: 'warning',
        confirmButtonClass: 'el-button--danger'
      })
      form.attachments = (form.attachments ?? []).filter((item) => item.url !== row.url)
    } catch {
      // 用户取消删除时无须提示
    }
  }

  const goBack = (): void => {
    void router.push('/vehicle-mgt-sys/archive-manage/vehicle-archive-entry')
  }

  const dateProps = {
    type: 'date',
    valueFormat: 'YYYY-MM-DD'
  }

  const numberProps = {
    min: 0,
    controlsPosition: 'right',
    class: '!w-full'
  }

  const yesNoOptions = [
    { label: '是', value: true },
    { label: '否', value: false }
  ]

  const originTypeOptions = [
    { label: '国产', value: 'domestic' },
    { label: '进口', value: 'imported' }
  ]

  const vehicleTypeOptions = [
    { label: '大型城市客车', value: 'large-city-bus' },
    { label: '中型客车', value: 'medium-bus' },
    { label: '小型客车', value: 'small-bus' },
    { label: '货车', value: 'truck' },
    { label: '专用车', value: 'special-vehicle' }
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
  .vehicle-archive-edit {
    min-height: 100%;
    padding: 16px;
    background: var(--art-main-bg-color);

    &__header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 18px 20px;
      margin-bottom: 12px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-light);
      border-radius: 8px;

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
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-light);
      border-radius: 8px;
    }

    &__section {
      margin-top: 16px;

      h3 {
        margin: 0 0 14px;
        font-size: 16px;
        font-weight: 600;
      }
    }

    &__section-header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 12px;
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
      color: var(--el-text-color-regular);
    }

    :deep(.el-tabs__content) {
      padding-top: 8px;
    }
  }
</style>
