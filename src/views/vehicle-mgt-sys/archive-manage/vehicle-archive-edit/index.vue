<template>
  <div class="vehicle-archive-edit">
    <div class="vehicle-archive-edit__header">
      <div>
        <h2>{{ isEdit ? '编辑车辆档案' : '新增车辆档案' }}</h2>
        <p>维护车辆基础资料、车身参数、发动机参数和运营信息。</p>
      </div>
      <div class="vehicle-archive-edit__actions">
        <ElButton @click="goBack">返回</ElButton>
        <ElButton type="primary" :loading="page.saving" @click="handleSave">保存</ElButton>
      </div>
    </div>

    <ElTabs v-model="page.activeTab" class="vehicle-archive-edit__tabs">
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
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
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
  import { useUserStore } from '@/store/modules/user'

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

  interface PageGroup {
    activeTab: string
    saving: boolean
  }

  interface OptionGroup {
    vehicleType: ComputedRef<Api.DataCenter.DictListItem[]>
    originType: ComputedRef<Api.DataCenter.DictListItem[]>
    color: ComputedRef<Api.DataCenter.DictListItem[]>
    businessType: ComputedRef<Api.DataCenter.DictListItem[]>
    operationStatus: ComputedRef<Api.DataCenter.DictListItem[]>
    purchaseStatus: ComputedRef<Api.DataCenter.DictListItem[]>
    vehicleLevel: ComputedRef<Api.DataCenter.DictListItem[]>
    fuelType: ComputedRef<Api.DataCenter.DictListItem[]>
    emissionStandard: ComputedRef<Api.DataCenter.DictListItem[]>
    transportIndustry: ComputedRef<Api.DataCenter.DictListItem[]>
    operationType: ComputedRef<Api.DataCenter.DictListItem[]>
    gender: ComputedRef<Api.DataCenter.DictListItem[]>
  }

  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const page = reactive<PageGroup>({
    activeTab: 'basic',
    saving: false
  })
  const basicFormRef = ref<FormExpose>()
  const bodyFormRef = ref<FormExpose>()
  const engineFormRef = ref<FormExpose>()
  const otherFormRef = ref<FormExpose>()

  const isEdit = computed(() => typeof route.params.id === 'string' && route.params.id.length > 0)

  const options: UnwrapNestedRefs<OptionGroup> = reactive<OptionGroup>({
    vehicleType: computed(() => getDictMap.value.vehicleType ?? []),
    originType: computed(() => getDictMap.value.vehicleOriginType ?? []),
    color: computed(() => getDictMap.value.vehicleColor ?? []),
    businessType: computed(() => getDictMap.value.vehicleBusinessType ?? []),
    operationStatus: computed(() => getDictMap.value.vehicleOperationStatus ?? []),
    purchaseStatus: computed(() => getDictMap.value.vehiclePurchaseStatus ?? []),
    vehicleLevel: computed(() => getDictMap.value.vehicleLevel ?? []),
    fuelType: computed(() => getDictMap.value.vehicleFuelType ?? []),
    emissionStandard: computed(() => getDictMap.value.vehicleEmissionStandard ?? []),
    transportIndustry: computed(() => getDictMap.value.vehicleTransportIndustry ?? []),
    operationType: computed(() => getDictMap.value.vehicleOperationType ?? []),
    gender: computed(() => getDictMap.value.sex ?? [])
  })

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
    { label: '车型', key: 'vehicleType', type: 'select', props: { options: options.vehicleType } },
    {
      label: '国产/进口',
      key: 'originType',
      type: 'radioGroup',
      props: { options: options.originType }
    },
    { label: '车架号（VIN）', key: 'vin', type: 'input' },
    { label: '车辆厂商', key: 'manufacturer', type: 'input' },
    { label: '厂牌型号', key: 'brandModel', type: 'input' },
    { label: '营运证号', key: 'operationCertNo', type: 'input' },
    { label: '购置证号', key: 'purchaseCertNo', type: 'input' },
    { label: '登记证号', key: 'registrationCertNo', type: 'input' },
    { label: '车身颜色', key: 'vehicleColor', type: 'select', props: { options: options.color } },
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
      props: { options: options.businessType }
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
      props: { options: options.operationStatus }
    },
    { label: '营运状态变更', key: 'operationStatusChangeDate', type: 'date', props: dateProps },
    {
      label: '购置状态',
      key: 'purchaseStatus',
      type: 'select',
      props: { options: options.purchaseStatus }
    },
    { label: '购置状态变更', key: 'purchaseStatusChangeDate', type: 'date', props: dateProps },
    { label: '例检启用日期', key: 'inspectionStartDate', type: 'date', props: dateProps },
    {
      label: '车辆等级',
      key: 'vehicleLevel',
      type: 'select',
      props: { options: options.vehicleLevel }
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
      props: numberProps,
      slots: {
        suffix: () => 'kg'
      }
    },
    {
      label: '整备质量',
      key: 'curbWeight',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'kg'
      }
    },
    {
      label: '核定载质量',
      key: 'approvedLoadMass',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'kg'
      }
    },
    {
      label: '外廓长度',
      key: 'overallLength',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'mm'
      }
    },
    {
      label: '外廓宽度',
      key: 'overallWidth',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'mm'
      }
    },
    {
      label: '外廓高度',
      key: 'overallHeight',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'mm'
      }
    },
    { label: '标台', key: 'platform', type: 'input' },
    {
      label: '前轮距',
      key: 'frontTrack',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'mm'
      }
    },
    {
      label: '后轮距',
      key: 'rearTrack',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'mm'
      }
    },
    { label: '轴距', key: 'wheelbase', type: 'number', props: numberProps },
    { label: '车轴数', key: 'axleCount', type: 'number', props: numberProps },
    { label: '轮胎数', key: 'tireCount', type: 'number', props: numberProps },
    {
      label: '钢板弹簧数',
      key: 'leafSpringCount',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => '片'
      }
    },
    { label: '是否双层', key: 'isDoubleDeck', type: 'radioGroup', props: { options: yesNoOptions } }
  ])

  const engineItems = computed<FormItem[]>(() => [
    { label: '发动机号', key: 'engineNo', type: 'input' },
    { label: '发动机型号', key: 'engineModel', type: 'input' },
    { label: '燃油类型', key: 'fuelType', type: 'select', props: { options: options.fuelType } },
    {
      label: '发动机排量',
      key: 'displacement',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'L'
      }
    },
    {
      label: '排放标准',
      key: 'emissionStandard',
      type: 'select',
      props: { options: options.emissionStandard }
    },
    {
      label: '发动机功率',
      key: 'enginePower',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'KW'
      }
    },
    {
      label: '额定扭矩转速',
      key: 'ratedTorqueSpeed',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'r/min'
      }
    },
    {
      label: '发动机扭矩',
      key: 'engineTorque',
      type: 'number',
      props: numberProps,
      slots: {
        suffix: () => 'N-M'
      }
    }
  ])

  const otherItems = computed<FormItem[]>(() => [
    { label: '车牌颜色', key: 'plateColor', type: 'select', props: { options: options.color } },
    {
      label: '运输行业',
      key: 'transportIndustry',
      type: 'select',
      props: { options: options.transportIndustry }
    },
    {
      label: '营运类型',
      key: 'operationType',
      type: 'select',
      props: { options: options.operationType }
    },
    { label: '业户ID', key: 'ownerId', type: 'input' },
    { label: '业户名称', key: 'ownerName', type: 'input' },
    { label: '业户联系电话', key: 'ownerPhone', type: 'input' },
    { label: '车载终端电话', key: 'terminalPhone', type: 'input' },
    { label: '车主性别', key: 'ownerGender', type: 'select', props: { options: options.gender } },
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
      page.activeTab = 'basic'
      return false
    }
  }

  const handleSave = async (): Promise<void> => {
    const valid = await validateForms()
    if (!valid) return

    page.saving = true
    try {
      const payload = toRaw(form)
      if (isEdit.value) {
        await editVehicleArchive(payload)
      } else {
        await addVehicleArchive(payload)
      }
      goBack()
    } finally {
      page.saving = false
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
    const source =
      route.query.source === 'manage' ? 'vehicle-archive-manage' : 'vehicle-archive-entry'
    void router.push(`/vehicle-mgt-sys/archive-manage/${source}`)
  }

  const dateProps = {
    type: 'date',
    valueFormat: 'YYYY-MM-DD',
    class: '!w-full'
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
