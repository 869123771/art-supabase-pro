<template>
  <ArtPageShell
    class="vehicle-archive-edit"
    :loading="page.loading"
    loading-mode="skeleton"
    :error="page.error"
    full-height
    @retry="initializePage"
  >
    <ArtPageHeader
      class="vehicle-archive-edit__header"
      :title="isEdit ? '编辑车辆档案' : '新增车辆档案'"
      :subtitle="pageSubtitle"
      show-back
      @back="goBack"
    />

    <div ref="pageRef" class="vehicle-archive-edit__content">
      <ElTabs v-model="page.activeTab" class="vehicle-archive-edit__tabs art-card-xs">
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

          <section class="vehicle-archive-edit__section vehicle-archive-edit__certificate-panel">
            <header class="vehicle-archive-edit__certificate-heading">
              <div>
                <ArtSectionTitle :show-line="false">车辆证件影像</ArtSectionTitle>
                <p>可直接上传或从资源库选择，上传后支持预览、替换和删除</p>
              </div>
              <span>{{ certificateFilledCount }}/{{ certificateItems.length }} 已完成</span>
            </header>
            <div class="vehicle-archive-edit__images">
              <ArtUploadImage
                v-for="item in certificateItems"
                :key="item.key"
                v-model="form[item.key]"
                :title="item.label"
                :size="120"
                :limit="1"
              />
            </div>
          </section>
        </ElTabPane>

        <ElTabPane label="车身参数" name="body">
          <ArtForm
            ref="bodyFormRef"
            v-model="form"
            :items="bodyItems"
            :rules="rules"
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
            :rules="rules"
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
            :rules="rules"
            :span="8"
            :gutter="20"
            label-width="130px"
            :show-reset="false"
            :show-submit="false"
          />

          <section class="vehicle-archive-edit__section">
            <div class="vehicle-archive-edit__section-header">
              <ArtSectionTitle class="vehicle-archive-edit__section-title" :show-line="false">
                车辆档案附件
              </ArtSectionTitle>
              <ArtExcelImport
                accept=""
                :parse-excel="false"
                :disabled="page.attachmentUploading"
                :button-props="{
                  type: 'primary',
                  plain: true,
                  loading: page.attachmentUploading
                }"
                @file-change="handleAttachmentUpload"
              >
                上传附件
              </ArtExcelImport>
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

    <ArtStickyActionBar class="vehicle-archive-edit__footer">
      <ElButton :disabled="page.saving" @click="goBack">取消</ElButton>
      <ElButton type="primary" :loading="page.saving" @click="handleSave">
        {{ saveButtonLabel }}
      </ElButton>
    </ArtStickyActionBar>
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import type { ComputedRef, Ref, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import { ElButton, ElMessage, ElTabPane, ElTabs } from 'element-plus'
  import ArtForm, {
    type FormItem,
    type FormItemOption
  } from '@/components/core/forms/art-form/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import type { ColumnOption } from '@/types'
  import {
    addVehicleArchive,
    editVehicleArchive,
    fetchVehicleArchiveDetail,
    submitVehicleArchiveForApproval
  } from '@/api/vehicle-manage-system'
  import { fetchCarrierOptions, fetchDriverOptions } from '@/api/tms'
  import { uploadAttachment } from '@/api/common'
  import { useUserStore } from '@/store/modules/user'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import { downloadAttachment, getFileExtension, viewAttachment } from '@/utils/file'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import {
    createInitialVehicleArchiveForm,
    requiresVehicleArchiveResubmission,
    sanitizeVehicleArchivePayload,
    type VehicleArchive,
    type VehicleArchiveForm
  } from './modules/vehicle-archive-model'

  defineOptions({ name: 'VehicleArchiveEdit' })

  const { confirmAction } = useArtFeedback()

  type ArchiveAttachment = Api.VehicleMgtSys.ArchiveManage.VehicleArchiveAttachment
  type CarrierOption = Api.Tms.BasicData.CarrierOption
  type DriverOption = Api.Tms.BasicData.DriverOption
  type ArchiveTabName = 'basic' | 'body' | 'engine' | 'other'
  type BooleanDictOption = Omit<Api.DataCenter.DictListItem, 'value'> & { value: boolean }
  type ImageKey =
    'vehiclePhotoUrl' | 'drivingLicenseFrontUrl' | 'drivingLicenseBackUrl' | 'operationLicenseUrl'

  const originalAuditStatus = ref<VehicleArchive['auditStatus']>()
  const shouldResubmit = computed(
    () => isEdit.value && requiresVehicleArchiveResubmission(originalAuditStatus.value)
  )
  const pageSubtitle = computed(() =>
    shouldResubmit.value
      ? '修正驳回问题；保存成功后将自动重新提交审批'
      : isEdit.value
        ? '维护车辆基础资料、车身参数、发动机参数和运营信息'
        : '填写完整车辆资料；提交后将自动进入配置的审批流程'
  )
  const saveButtonLabel = computed(() => {
    if (!isEdit.value) return '提交审核'
    return shouldResubmit.value ? '保存并重新提交' : '保存'
  })

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
    reloadOptions: (key?: string) => Promise<unknown>
  }

  interface PageGroup {
    activeTab: ArchiveTabName
    loading: boolean
    saving: boolean
    attachmentUploading: boolean
    error: Error | null
  }

  interface FormTab {
    name: ArchiveTabName
    formRef: Readonly<Ref<FormExpose | undefined>>
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
    boolean: ComputedRef<BooleanDictOption[]>
  }

  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const page = reactive<PageGroup>({
    activeTab: 'basic',
    loading: false,
    saving: false,
    attachmentUploading: false,
    error: null
  })
  const pageRef = ref<HTMLElement>()
  const basicFormRef = ref<FormExpose>()
  const bodyFormRef = ref<FormExpose>()
  const engineFormRef = ref<FormExpose>()
  const otherFormRef = ref<FormExpose>()
  const formTabs: FormTab[] = [
    { name: 'basic', formRef: basicFormRef },
    { name: 'body', formRef: bodyFormRef },
    { name: 'engine', formRef: engineFormRef },
    { name: 'other', formRef: otherFormRef }
  ]
  const carrierCache = ref(new Map<string, CarrierOption>())
  const driverCache = ref(new Map<string, DriverOption>())

  const isEdit = computed(() => typeof route.params.id === 'string' && route.params.id.length > 0)
  const selectedPrimaryDriverOptions = computed<FormItemOption[]>(() => {
    const driver = getSelectedPrimaryDriver()
    return driver ? [createDriverOption(driver)] : []
  })
  const selectedSecondaryDriverOptions = computed<FormItemOption[]>(() => {
    const driver = getSelectedSecondaryDriver()
    return driver ? [createDriverOption(driver)] : []
  })

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
    gender: computed(() => getDictMap.value.sex ?? []),
    boolean: computed(() =>
      (getDictMap.value.commonBoolean ?? []).map((item) => ({
        ...item,
        value: item.value === 'true'
      }))
    )
  })

  const createInitialForm = createInitialVehicleArchiveForm

  const form = reactive<VehicleArchiveForm>(createInitialForm())
  const archiveNumber = useDocumentNumberRule('vehicle.archive_self')

  const rules: FormRules<VehicleArchiveForm> = {
    plateNo: [{ required: true, message: '请输入车牌号', trigger: 'blur' }],
    carrierId: [{ required: true, message: '请选择所属承运商', trigger: 'change' }],
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
    {
      label: '所属承运商',
      key: 'carrierId',
      type: 'select',
      span: 16,
      api: fetchCarrierOptions,
      resultField: 'data',
      labelField: 'companyName',
      valueField: 'id',
      labelFn: (option) => {
        const carrier = option as CarrierOption
        return carrier.carrierCode
          ? `${carrier.companyName}（${carrier.carrierCode}）`
          : carrier.companyName
      },
      props: {
        filterable: true,
        clearable: true,
        placeholder: '请选择所属承运商',
        onVisibleChange: async (visible: boolean) => {
          if (!visible) return
          const { data } = await fetchCarrierOptions()
          carrierCache.value = new Map((data ?? []).map((item) => [item.id, item]))
        },
        onChange: (value?: string) => {
          if (!value) {
            form.companyName = ''
            form.primaryDriverId = null
            form.primaryDriver = null
            form.primaryDriverName = ''
            form.primaryDriverPhone = ''
            form.secondaryDriverId = null
            form.secondaryDriver = null
            form.secondaryDriverName = ''
            form.secondaryDriverPhone = ''
            driverCache.value = new Map()
            return
          }
          const carrier = carrierCache.value.get(value)
          if (carrier) {
            form.companyName = carrier.companyName
          }
          form.primaryDriverId = null
          form.primaryDriver = null
          form.primaryDriverName = ''
          form.primaryDriverPhone = ''
          form.secondaryDriverId = null
          form.secondaryDriver = null
          form.secondaryDriverName = ''
          form.secondaryDriverPhone = ''
          driverCache.value = new Map()
        }
      }
    },
    { label: '所属公司', key: 'companyName', type: 'input', props: { readonly: true } },
    {
      label: '自编号',
      key: 'selfNo',
      type: 'input',
      props: {
        maxlength: 50,
        ...archiveNumber.inputProps(Boolean(form.id), '可手工填写车辆自编号', true)
      },
      description: archiveNumber.description.value
    },
    { label: '车型', key: 'vehicleType', type: 'select', props: { options: options.vehicleType } },
    {
      label: '国产/进口',
      key: 'originType',
      type: 'radioGroup',
      props: { options: options.originType, optionType: 'button' }
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
      props: { options: options.boolean }
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
      props: { options: options.boolean }
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
    {
      label: '是否双层',
      key: 'isDoubleDeck',
      type: 'radioGroup',
      props: { options: options.boolean }
    }
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
    {
      label: '主司机',
      key: 'primaryDriverId',
      type: 'select',
      span: 8,
      api: fetchDriverOptions,
      options: selectedPrimaryDriverOptions.value,
      resultField: 'data',
      labelField: 'driverName',
      valueField: 'id',
      immediate: false,
      beforeFetch: () => ({
        carrierId: form.carrierId ?? undefined,
        driverType: 'primary'
      }),
      shouldFetch: () => Boolean(form.carrierId),
      afterFetch: syncPrimaryDriverOptions,
      labelFn: (option) => {
        const driver = option as DriverOption
        return driver.phone ? `${driver.driverName}（${driver.phone}）` : driver.driverName
      },
      props: {
        filterable: true,
        clearable: true,
        disabled: !form.carrierId,
        placeholder: form.carrierId ? '请选择主司机' : '请先选择所属承运商',
        onVisibleChange: (visible: boolean) => {
          if (visible && form.carrierId) void otherFormRef.value?.reloadOptions('primaryDriverId')
        },
        onChange: (value?: string) => {
          if (!value) {
            form.primaryDriver = null
            form.primaryDriverName = ''
            form.primaryDriverPhone = ''
            return
          }
          const driver = driverCache.value.get(value)
          form.primaryDriver = driver ?? null
          form.primaryDriverName = driver?.driverName ?? ''
          form.primaryDriverPhone = driver?.phone ?? ''
        }
      }
    },
    { label: '主司机姓名', key: 'primaryDriverName', type: 'input', props: { readonly: true } },
    { label: '主司机电话', key: 'primaryDriverPhone', type: 'input', props: { readonly: true } },
    {
      label: '辅司机',
      key: 'secondaryDriverId',
      type: 'select',
      span: 8,
      api: fetchDriverOptions,
      options: selectedSecondaryDriverOptions.value,
      resultField: 'data',
      labelField: 'driverName',
      valueField: 'id',
      immediate: false,
      beforeFetch: () => ({
        carrierId: form.carrierId ?? undefined,
        driverType: 'secondary'
      }),
      shouldFetch: () => Boolean(form.carrierId),
      afterFetch: syncSecondaryDriverOptions,
      labelFn: (option) => {
        const driver = option as DriverOption
        return driver.phone ? `${driver.driverName}（${driver.phone}）` : driver.driverName
      },
      props: {
        filterable: true,
        clearable: true,
        disabled: !form.carrierId,
        placeholder: form.carrierId ? '请选择辅司机' : '请先选择所属承运商',
        onVisibleChange: (visible: boolean) => {
          if (visible && form.carrierId) void otherFormRef.value?.reloadOptions('secondaryDriverId')
        },
        onChange: (value?: string) => {
          if (!value) {
            form.secondaryDriver = null
            form.secondaryDriverName = ''
            form.secondaryDriverPhone = ''
            return
          }
          const driver = driverCache.value.get(value)
          form.secondaryDriver = driver ?? null
          form.secondaryDriverName = driver?.driverName ?? ''
          form.secondaryDriverPhone = driver?.phone ?? ''
        }
      }
    },
    { label: '辅司机姓名', key: 'secondaryDriverName', type: 'input', props: { readonly: true } },
    { label: '辅司机电话', key: 'secondaryDriverPhone', type: 'input', props: { readonly: true } },
    { label: '营运线路', key: 'operationRoute', type: 'input' },
    { label: '车籍地代码', key: 'licensePlateCode', type: 'input' },
    { label: '服务开始时间', key: 'serviceStartTime', type: 'date', props: dateProps },
    { label: '服务结束时间', key: 'serviceEndTime', type: 'date', props: dateProps },
    {
      label: '支持拍照',
      key: 'supportPhoto',
      type: 'radioGroup',
      props: { options: options.boolean }
    }
  ])

  function syncPrimaryDriverOptions(result: unknown): unknown {
    return syncDriverOptions(result, getSelectedPrimaryDriver())
  }

  function syncSecondaryDriverOptions(result: unknown): unknown {
    return syncDriverOptions(result, getSelectedSecondaryDriver())
  }

  function syncDriverOptions(result: unknown, selectedDriver?: DriverOption): unknown {
    if (!result || typeof result !== 'object') return result

    const data = (result as { data?: DriverOption[] }).data
    if (Array.isArray(data)) {
      const nextData =
        selectedDriver && !data.some((item) => item.id === selectedDriver.id)
          ? [selectedDriver, ...data]
          : data

      driverCache.value = new Map(nextData.map((item) => [item.id, item]))
      return {
        ...(result as Record<string, unknown>),
        data: nextData
      }
    }

    return result
  }

  function getSelectedPrimaryDriver(): DriverOption | undefined {
    if (!form.primaryDriverId) return undefined
    return (
      driverCache.value.get(form.primaryDriverId) ??
      (form.primaryDriver?.id === form.primaryDriverId ? form.primaryDriver : undefined)
    )
  }

  function getSelectedSecondaryDriver(): DriverOption | undefined {
    if (!form.secondaryDriverId) return undefined
    return (
      driverCache.value.get(form.secondaryDriverId) ??
      (form.secondaryDriver?.id === form.secondaryDriverId ? form.secondaryDriver : undefined)
    )
  }

  function createDriverOption(driver: DriverOption): FormItemOption {
    return {
      ...driver,
      label: driver.phone ? `${driver.driverName}（${driver.phone}）` : driver.driverName,
      value: driver.id
    }
  }

  const certificateItems: Array<{ key: ImageKey; label: string }> = [
    { key: 'vehiclePhotoUrl', label: '车辆照片' },
    { key: 'drivingLicenseFrontUrl', label: '行驶证正页' },
    { key: 'drivingLicenseBackUrl', label: '行驶证副页' },
    { key: 'operationLicenseUrl', label: '运营证照片' }
  ]
  const certificateFilledCount = computed(
    () => certificateItems.filter((item) => Boolean(form[item.key])).length
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
        <div class="flex">
          <ArtButtonTable type="view" onClick={() => viewAttachment(row)} />
          <ArtButtonMore
            list={getAttachmentMoreActions()}
            onClick={(item: ButtonMoreItem) => handleAttachmentMoreAction(item, row)}
          />
        </div>
      )
    }
  ]

  onMounted(() => {
    void initializePage()
  })

  const initializePage = async (): Promise<void> => {
    page.loading = true
    page.error = null
    try {
      await Promise.all([
        loadArchiveDetail(),
        archiveNumber.loadRule(),
        userStore.ensureDictLoaded('FILE_EXTENSION_LABEL_MAP')
      ])
      await nextTick()
      formTabs.forEach((tab) => tab.formRef.value?.clearValidate())
    } catch (error) {
      page.error = error instanceof Error ? error : new Error('车辆档案加载失败')
    } finally {
      page.loading = false
    }
  }

  const loadArchiveDetail = async (): Promise<void> => {
    if (!isEdit.value) return
    const id = String(route.params.id)
    const { data } = await fetchVehicleArchiveDetail(id)
    if (!data) throw new Error('车辆档案不存在或无权访问')
    originalAuditStatus.value = data.auditStatus
    replaceForm({ ...createInitialForm(), ...data, attachments: data.attachments ?? [] })
  }

  const replaceForm = (nextForm: VehicleArchiveForm): void => {
    Object.keys(form).forEach((key) => {
      delete form[key as keyof VehicleArchive]
    })
    Object.assign(form, nextForm)
    if (nextForm.carrier?.id) {
      carrierCache.value.set(nextForm.carrier.id, nextForm.carrier)
      form.companyName = nextForm.carrier.companyName
    }
    if (nextForm.primaryDriver?.id) {
      driverCache.value.set(nextForm.primaryDriver.id, nextForm.primaryDriver)
      form.primaryDriverName = nextForm.primaryDriver.driverName
      form.primaryDriverPhone = nextForm.primaryDriver.phone ?? ''
    }
    if (nextForm.secondaryDriver?.id) {
      driverCache.value.set(nextForm.secondaryDriver.id, nextForm.secondaryDriver)
      form.secondaryDriverName = nextForm.secondaryDriver.driverName
      form.secondaryDriverPhone = nextForm.secondaryDriver.phone ?? ''
    }
  }

  const focusFirstInvalidField = (tabName: ArchiveTabName): void => {
    const invalidItem = pageRef.value?.querySelector<HTMLElement>(
      `#pane-${tabName} .el-form-item.is-error`
    )
    if (!invalidItem) return

    invalidItem.scrollIntoView({ behavior: 'smooth', block: 'center' })
    invalidItem
      .querySelector<HTMLElement>(
        'input:not([type="hidden"]):not([disabled]), textarea:not([disabled]), button:not([disabled]), [tabindex]:not([tabindex="-1"])'
      )
      ?.focus()
  }

  const validateForms = async (): Promise<boolean> => {
    for (const tab of formTabs) {
      try {
        await tab.formRef.value?.validate()
      } catch {
        page.activeTab = tab.name
        await nextTick()
        focusFirstInvalidField(tab.name)
        return false
      }
    }

    return true
  }

  const handleSave = async (): Promise<void> => {
    const valid = await validateForms()
    if (!valid) return

    page.saving = true
    try {
      const payload = sanitizeVehicleArchivePayload(toRaw(form))
      if (isEdit.value) {
        await editVehicleArchive(payload, { showMessage: !shouldResubmit.value })
        if (shouldResubmit.value) {
          await submitVehicleArchiveForApproval(
            String(payload.id),
            String(payload.plateNo || '未编号车辆')
          )
        }
      } else {
        const response = await addVehicleArchive(payload, { showMessage: false })
        if (!response.data?.id) throw new Error('车辆档案创建成功，但未返回档案 ID')
        await submitVehicleArchiveForApproval(
          response.data.id,
          String(payload.plateNo || '未编号车辆')
        )
      }
      goBack()
    } finally {
      page.saving = false
    }
  }

  const getAttachmentMoreActions = (): ButtonMoreItem[] => [
    {
      key: 'download',
      label: '下载',
      icon: 'ri:download-2-line'
    },
    {
      key: 'delete',
      label: '删除',
      icon: 'ri:delete-bin-5-line',
      color: '#f56c6c'
    }
  ]

  const handleAttachmentMoreAction = (item: ButtonMoreItem, row: ArchiveAttachment): void => {
    if (item.key === 'download') {
      downloadAttachment(row)
      return
    }

    if (item.key === 'delete') {
      void removeAttachment(row)
    }
  }

  const handleAttachmentUpload = async (file: File): Promise<void> => {
    page.attachmentUploading = true
    try {
      const [resource] = await uploadAttachment(file)
      if (!resource?.url) {
        throw new Error('附件上传失败')
      }

      const nextAttachment: ArchiveAttachment = {
        name: resource.originName || file.name,
        url: resource.url,
        fileType: getFileExtension(file.name, resource.suffix),
        fileSize: resource.sizeInfo
      }
      form.attachments = [...(form.attachments ?? []), nextAttachment]
      ElMessage.success('附件上传成功')
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '附件上传失败'))
    } finally {
      page.attachmentUploading = false
    }
  }

  const removeAttachment = async (row: ArchiveAttachment): Promise<void> => {
    try {
      await confirmAction(`确定删除附件“${row.name}”吗？`, '删除确认', {
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
    void router.push('/vehicle-manage-system/vehicle-archive-manage')
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
</script>

<style scoped lang="scss">
  .vehicle-archive-edit {
    min-height: 100%;
    padding: var(--art-space-4) var(--art-space-4) 0;
    background: var(--art-main-bg-color);

    :deep(> .art-async-state) {
      display: flex;
      flex-direction: column;
      min-height: 0;
    }

    &__header {
      margin-bottom: 16px;
    }

    &__content {
      flex: 1 0 auto;
      min-width: 0;
    }

    &__tabs {
      padding: 0 20px 24px;

      :deep(.el-tabs__header) {
        margin-bottom: 22px;
      }

      :deep(.el-form-item) {
        margin-bottom: 22px;
      }
    }

    &__footer {
      flex: none;
      // Sticky 向上偏移时会压缩视觉间距，提前补偿以稳定保持 16px 卡片间隔。
      margin-top: calc(var(--art-space-4) + var(--art-sticky-offset));
    }

    &__section {
      margin-top: 20px;

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

    &__section-title {
      flex: 1;
      margin: 0 !important;
    }

    &__certificate-panel {
      padding: 18px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__certificate-heading {
      display: flex;
      gap: 16px;
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: 18px;

      > div {
        min-width: 0;

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
      grid-template-columns: repeat(4, minmax(120px, 1fr));
      gap: 16px;
      justify-items: center;
    }

    :deep(.el-tabs__content) {
      padding-top: 8px;
    }

    @media (width <= 760px) {
      &__images {
        grid-template-columns: repeat(2, minmax(120px, 1fr));
      }
    }

    @media (width <= 420px) {
      &__images {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
