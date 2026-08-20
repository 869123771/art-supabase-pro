<template>
  <ArtDialog ref="dialogRef" size="xl">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="8"
      :gutter="20"
      label-width="118px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #idCardFrontUrl>
        <ArtUploadImage
          v-model="form.idCardFrontUrl"
          title="身份证正面"
          :size="104"
          :limit="1"
          :readonly="!canEditDriverField('identityDocuments')"
        />
      </template>
      <template #idCardBackUrl>
        <ArtUploadImage
          v-model="form.idCardBackUrl"
          title="身份证反面"
          :size="104"
          :limit="1"
          :readonly="!canEditDriverField('identityDocuments')"
        />
      </template>
      <template #driverLicenseFrontUrl>
        <ArtUploadImage
          v-model="form.driverLicenseFrontUrl"
          title="驾驶证正面"
          :size="104"
          :limit="1"
          :readonly="!canEditDriverField('identityDocuments')"
        />
      </template>
      <template #driverLicenseBackUrl>
        <ArtUploadImage
          v-model="form.driverLicenseBackUrl"
          title="驾驶证反面"
          :size="104"
          :limit="1"
          :readonly="!canEditDriverField('identityDocuments')"
        />
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { omit } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import {
    addDriver,
    editDriver,
    fetchCarrierOptions,
    fetchDriverAssignedVehicles
  } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { canEditField, canViewField, getFieldAccess } from '@/utils/field-permission'

  defineOptions({ name: 'TmsDriverDialog' })

  type Driver = Api.Tms.BasicData.Driver
  type DriverForm = Driver & { carrierVehiclePlates: string[] }
  type CarrierOption = Api.Tms.BasicData.CarrierOption

  interface DialogExposeForm {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{
    (event: 'success', type: 'add' | 'edit'): void
  }>()

  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Driver | undefined>>()
  const formRef = ref<DialogExposeForm>()
  const vehicleState = reactive({ loading: false, error: '', requestId: 0 })

  const genderOptions = computed(() => getDictMap.value.sex ?? [])
  const licenseTypeOptions = computed(() => getDictMap.value.tmsDriverLicenseType ?? [])
  const driverTypeOptions = computed(() => getDictMap.value.tmsDriverType ?? [])

  const createInitialForm = (): DriverForm => ({
    id: undefined,
    carrierId: '',
    driverName: '',
    phone: '',
    driverType: 'primary',
    gender: '',
    idCardNo: '',
    licenseType: '',
    licenseExpireDate: '',
    homeAddress: '',
    emergencyContactName: '',
    emergencyContactPhone: '',
    enabled: true,
    idCardFrontUrl: '',
    idCardBackUrl: '',
    driverLicenseFrontUrl: '',
    driverLicenseBackUrl: '',
    remark: '',
    carrierVehiclePlates: [],
    fieldAccess: {
      contactPhone: 'edit',
      idCardNo: 'edit',
      homeAddress: 'edit',
      emergencyContact: 'edit',
      identityDocuments: 'edit'
    },
    isRecordOwner: true
  })

  const form = reactive<DriverForm>(createInitialForm())

  const canViewDriverField = (field: Api.Tms.BasicData.DriverFieldKey): boolean =>
    canViewField(form.fieldAccess, field)

  const canEditDriverField = (field: Api.Tms.BasicData.DriverFieldKey): boolean =>
    canEditField(form.fieldAccess, field)

  const canViewIdentityDocuments = computed(() =>
    ['read', 'edit'].includes(getFieldAccess(form.fieldAccess, 'identityDocuments'))
  )

  const formRules = computed<FormRules<DriverForm>>(() => ({
    driverName: [
      { required: true, message: '请输入姓名', trigger: 'blur' },
      { min: 2, max: 50, message: '长度应为 2 到 50 个字符', trigger: 'blur' }
    ],
    carrierId: [{ required: true, message: '请选择所属承运商', trigger: 'change' }],
    driverType: [{ required: true, message: '请选择司机类型', trigger: 'change' }],
    phone: canEditDriverField('contactPhone')
      ? [
          { required: true, message: '请输入手机号码', trigger: 'blur' },
          {
            pattern: /^1[3-9]\d{9}$/,
            message: '请输入正确的手机号码',
            trigger: 'blur'
          }
        ]
      : [],
    idCardNo: canEditDriverField('idCardNo')
      ? [
          { required: true, message: '请输入身份证号', trigger: 'blur' },
          {
            pattern:
              /^(^[1-9]\d{5}(18|19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\d{3}[\dXx]$)|(^[1-9]\d{7}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])\d{3}$)$/,
            message: '请输入正确的身份证号',
            trigger: 'blur'
          }
        ]
      : [],
    gender: [{ required: true, message: '请选择性别', trigger: 'change' }],
    licenseType: [{ required: true, message: '请选择驾照类型', trigger: 'change' }],
    licenseExpireDate: [{ required: true, message: '请选择驾照有效期', trigger: 'change' }],
    emergencyContactPhone: canEditDriverField('emergencyContact')
      ? [
          {
            pattern: /^$|^1[3-9]\d{9}$/,
            message: '请输入正确的紧急联系人电话',
            trigger: 'blur'
          }
        ]
      : [],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }))

  const formItems = computed<FormItem[]>(() => [
    { label: '基础信息', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '姓名',
      key: 'driverName',
      type: 'input',
      props: { maxlength: 50, placeholder: '请输入姓名' }
    },
    {
      label: '手机号码',
      key: 'phone',
      type: 'input',
      hidden: !canViewDriverField('contactPhone'),
      props: {
        maxlength: 11,
        placeholder: '请输入手机号码',
        disabled: !canEditDriverField('contactPhone')
      }
    },
    {
      label: '身份证号',
      key: 'idCardNo',
      type: 'input',
      hidden: !canViewDriverField('idCardNo'),
      props: {
        maxlength: 18,
        placeholder: '请输入身份证号',
        disabled: !canEditDriverField('idCardNo')
      }
    },
    {
      label: '司机类型',
      key: 'driverType',
      type: 'radioGroup',
      props: { options: driverTypeOptions.value }
    },
    {
      label: '性别',
      key: 'gender',
      type: 'select',
      props: {
        options: genderOptions.value,
        clearable: true,
        placeholder: '请选择性别'
      }
    },
    {
      label: '驾照类型',
      key: 'licenseType',
      type: 'select',
      props: {
        options: licenseTypeOptions.value,
        clearable: true,
        placeholder: '请选择驾照类型'
      }
    },
    {
      label: '驾照有效期',
      key: 'licenseExpireDate',
      type: 'date',
      props: {
        type: 'date',
        valueFormat: 'YYYY-MM-DD',
        class: '!w-full',
        placeholder: '请选择日期'
      }
    },
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
        placeholder: '公司名称/承运商编码',
        onChange: () => {
          form.carrierVehiclePlates = []
          void reloadAssignedVehicles()
        }
      }
    },
    {
      label: '车牌号',
      key: 'carrierVehiclePlates',
      type: 'inputTag',
      span: 16,
      hidden: () => !form.id,
      props: {
        disabled: true,
        tagType: 'primary',
        tagEffect: 'light',
        placeholder: vehicleState.loading
          ? '正在加载关联车辆'
          : vehicleState.error
            ? '关联车辆加载失败'
            : '暂无关联车辆'
      }
    },
    {
      label: '家庭住址',
      key: 'homeAddress',
      type: 'input',
      span: 16,
      hidden: !canViewDriverField('homeAddress'),
      props: {
        maxlength: 200,
        placeholder: '请输入家庭住址',
        disabled: !canEditDriverField('homeAddress')
      }
    },
    {
      label: '紧急联系人',
      key: 'emergencyContactName',
      type: 'input',
      hidden: !canViewDriverField('emergencyContact'),
      props: {
        maxlength: 50,
        placeholder: '请输入紧急联系人',
        disabled: !canEditDriverField('emergencyContact')
      }
    },
    {
      label: '紧急联系人电话',
      key: 'emergencyContactPhone',
      type: 'input',
      hidden: !canViewDriverField('emergencyContact'),
      props: {
        maxlength: 11,
        placeholder: '请输入紧急联系人电话',
        disabled: !canEditDriverField('emergencyContact')
      }
    },
    {
      label: '状态',
      key: 'enabled',
      type: 'switch',
      props: {
        activeText: '启用',
        inactiveText: '停用',
        inlinePrompt: true
      }
    },
    {
      label: '证件照',
      key: 'certificateSection',
      type: 'divider',
      span: 24,
      hidden: !canViewIdentityDocuments.value
    },
    {
      label: '身份证正面',
      key: 'idCardFrontUrl',
      hidden: !canViewIdentityDocuments.value
    },
    {
      label: '身份证反面',
      key: 'idCardBackUrl',
      hidden: !canViewIdentityDocuments.value
    },
    {
      label: '驾驶证正面',
      key: 'driverLicenseFrontUrl',
      hidden: !canViewIdentityDocuments.value
    },
    {
      label: '驾驶证反面',
      key: 'driverLicenseBackUrl',
      hidden: !canViewIdentityDocuments.value
    },
    {
      label: '备注信息',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 3,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '请输入备注信息'
      }
    }
  ])

  const replaceForm = (nextForm: DriverForm): void => {
    Object.keys(form).forEach((key) => delete form[key as keyof DriverForm])
    Object.assign(form, nextForm)
  }

  const resetForm = async (): Promise<void> => {
    vehicleState.requestId += 1
    vehicleState.loading = false
    vehicleState.error = ''
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const normalizePayload = (): Driver => {
    const rawPayload = structuredClone(toRaw(form))
    if (rawPayload.id && !canEditField(rawPayload.fieldAccess, 'contactPhone')) {
      delete rawPayload.phone
    }
    if (rawPayload.id && !canEditField(rawPayload.fieldAccess, 'idCardNo')) {
      delete rawPayload.idCardNo
    }
    if (rawPayload.id && !canEditField(rawPayload.fieldAccess, 'homeAddress')) {
      delete rawPayload.homeAddress
    }
    if (rawPayload.id && !canEditField(rawPayload.fieldAccess, 'emergencyContact')) {
      delete rawPayload.emergencyContactName
      delete rawPayload.emergencyContactPhone
    }
    if (rawPayload.id && !canEditField(rawPayload.fieldAccess, 'identityDocuments')) {
      delete rawPayload.idCardFrontUrl
      delete rawPayload.idCardBackUrl
      delete rawPayload.driverLicenseFrontUrl
      delete rawPayload.driverLicenseBackUrl
    }

    const payload = omit(rawPayload, [
      'tenantId',
      'createdByUserId',
      'createBy',
      'createTime',
      'updateBy',
      'updateTime',
      'carrier',
      'assignedVehicles',
      'carrierVehiclePlates',
      'fieldAccess',
      'isRecordOwner'
    ]) as Driver

    return {
      ...payload,
      licenseExpireDate: payload.licenseExpireDate || null,
      idCardFrontUrl: payload.idCardFrontUrl || null,
      idCardBackUrl: payload.idCardBackUrl || null,
      driverLicenseFrontUrl: payload.driverLicenseFrontUrl || null,
      driverLicenseBackUrl: payload.driverLicenseBackUrl || null
    }
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const payload = normalizePayload()
      const type = form.id ? 'edit' : 'add'
      if (type === 'edit') await editDriver(payload)
      else await addDriver(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Driver): Promise<void> => {
    await resetForm()
    const isEdit = Boolean(row?.id)
    if (row) {
      const editData = omit(structuredClone(toRaw(row)), ['assignedVehicles'])
      replaceForm({
        ...createInitialForm(),
        ...editData,
        carrierVehiclePlates: (row.assignedVehicles ?? []).map((vehicle) => vehicle.plateNo)
      })
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑司机' : '新增司机',
      subtitle: '维护司机基础资料与证件信息',
      contentMaxHeight: '72vh',
      onOpen: async () => {
        await reloadAssignedVehicles()
      },
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  const reloadAssignedVehicles = async (): Promise<void> => {
    const driverId = form.id
    const carrierId = form.carrierId
    const requestId = ++vehicleState.requestId
    vehicleState.error = ''

    if (!driverId || !carrierId) {
      form.carrierVehiclePlates = []
      vehicleState.loading = false
      return
    }

    vehicleState.loading = true
    try {
      const result = await fetchDriverAssignedVehicles({ driverId, carrierId })
      if (requestId !== vehicleState.requestId) return
      if (result.error) {
        vehicleState.error = '关联车辆加载失败，请重试'
        return
      }
      form.carrierVehiclePlates = (result.data ?? []).map((vehicle) => vehicle.plateNo)
    } catch {
      if (requestId !== vehicleState.requestId) return
      form.carrierVehiclePlates = []
      vehicleState.error = '关联车辆加载失败，请重试'
    } finally {
      if (requestId === vehicleState.requestId) vehicleState.loading = false
    }
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
