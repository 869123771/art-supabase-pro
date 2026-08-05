<template>
  <ArtDialog ref="dialogRef" size="md">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="12"
      :gutter="20"
      label-width="120px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #addressPicker>
        <ArtAddressPicker
          v-model:region-path="form.regionPath"
          v-model:address-detail="form.addressDetail"
          :region-api="fetchRegionOptions"
          :show-coordinate-hint="false"
          hide-region-selector
          label-width="120px"
        />
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtAddressPicker from '@/components/core/forms/art-address-picker/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { addInsuranceCompany, editInsuranceCompany } from '@/api/vehicle-manage-system'
  import { fetchRegionOptions } from '@/api/common'

  type InsuranceCompany = Api.VehicleMgtSys.BasicInfo.InsuranceCompany
  type InsuranceCompanyForm = InsuranceCompany & {
    addressPicker?: undefined
    regionPath?: string[]
  }

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<InsuranceCompany | undefined>>()
  const formRef = ref<{
    validate: () => Promise<boolean>
    clearValidate: () => void
  }>()

  const createInitialForm = (): InsuranceCompanyForm => ({
    id: undefined,
    companyName: '',
    contactPerson: '',
    contactPhone: '',
    region: '',
    addressPicker: undefined,
    regionPath: [],
    addressDetail: '',
    remark: ''
  })

  const form = reactive<InsuranceCompanyForm>(createInitialForm())

  const rules: FormRules<InsuranceCompanyForm> = {
    companyName: [
      { required: true, message: '请输入保险公司名称', trigger: 'blur' },
      { min: 2, max: 100, message: '长度应为 2 到 100 个字符', trigger: 'blur' }
    ],
    contactPerson: [{ max: 50, message: '联系人不能超过 50 个字符', trigger: 'blur' }],
    contactPhone: [
      {
        pattern: /^(?:1[3-9]\d{9}|0\d{2,3}-?\d{7,8})$/,
        message: '请输入正确的手机号或座机号',
        trigger: 'blur'
      }
    ],
    region: [{ max: 100, message: '省/市/区不能超过 100 个字符', trigger: 'blur' }],
    addressDetail: [{ max: 200, message: '详细地址不能超过 200 个字符', trigger: 'blur' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const items = computed<FormItem[]>(() => [
    {
      label: '保险公司名称',
      key: 'companyName',
      type: 'input',
      span: 24,
      props: {
        maxlength: 100
      }
    },
    {
      label: '联系人',
      key: 'contactPerson',
      type: 'input',
      props: {
        maxlength: 50
      }
    },
    {
      label: '联系电话',
      key: 'contactPhone',
      type: 'input',
      props: {
        maxlength: 20,
        placeholder: '请输入手机号或座机号'
      }
    },
    {
      label: '',
      key: 'addressPicker',
      type: 'input',
      span: 24,
      labelWidth: 0
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 3,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '请输入备注'
      }
    }
  ])

  const replaceForm = (nextForm: InsuranceCompanyForm): void => {
    Object.keys(form).forEach((key) => {
      delete form[key as keyof InsuranceCompanyForm]
    })
    Object.assign(form, nextForm)
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }

    try {
      const { regionPath, ...payload } = toRaw(form)
      delete payload.addressPicker
      payload.region = regionPath?.join('/') || ''
      if (form.id) {
        await editInsuranceCompany(payload)
      } else {
        await addInsuranceCompany(payload)
      }
      emit('success', form.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: InsuranceCompany): Promise<void> => {
    await resetForm()
    const isEdit = !!row?.id
    if (isEdit) {
      const editData = structuredClone(toRaw(row)) as InsuranceCompanyForm
      editData.regionPath = editData.region?.split('/').filter(Boolean) || []
      replaceForm(editData)
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑保险公司' : '新增保险公司',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
