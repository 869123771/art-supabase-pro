<template>
  <ArtDialog ref="dialogRef">
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
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { addInsuranceCompany, editInsuranceCompany } from '@/api/vehicle-mgt-sys'
  import { fetchRegionOptions, type RegionOption } from '@/api/common'

  type InsuranceCompany = Api.VehicleMgtSys.BasicInfo.InsuranceCompany
  type InsuranceCompanyForm = InsuranceCompany & {
    regionPath?: string[]
  }

  interface OpenData {
    type: 'add' | 'edit'
    editData?: InsuranceCompany
  }

  interface Emits {
    (e: 'success', type: OpenData['type']): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
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
    regionPath: [],
    addressDetail: '',
    remark: ''
  })

  const form = reactive<InsuranceCompanyForm>(createInitialForm())
  const regionOptions = ref<RegionOption[]>([])
  const regionLoading = ref(false)

  const rules: FormRules<InsuranceCompany> = {
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
        clearable: true,
        maxlength: 100,
        placeholder: '请输入保险公司名称'
      }
    },
    {
      label: '联系人',
      key: 'contactPerson',
      type: 'input',
      props: {
        clearable: true,
        maxlength: 50,
        placeholder: '请输入联系人'
      }
    },
    {
      label: '联系电话',
      key: 'contactPhone',
      type: 'input',
      props: {
        clearable: true,
        maxlength: 20,
        placeholder: '请输入手机号或座机号'
      }
    },
    {
      label: '省/市/区',
      key: 'regionPath',
      type: 'cascader',
      props: {
        clearable: true,
        filterable: true,
        options: regionOptions.value,
        placeholder: '请选择省/市/区',
        props: {
          checkStrictly: true
        },
        loading: regionLoading.value
      }
    },
    {
      label: '详细地址',
      key: 'addressDetail',
      type: 'input',
      props: {
        clearable: true,
        maxlength: 200,
        placeholder: '请输入道路、门牌号、小区、楼栋等'
      }
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

  const resetForm = async (): Promise<void> => {
    Object.assign(form, createInitialForm())
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

  const handleOpen = async (data: OpenData): Promise<void> => {
    await resetForm()
    await loadRegionOptions()
    if (data.editData) {
      const editData = structuredClone(toRaw(data.editData)) as InsuranceCompanyForm
      editData.regionPath = editData.region?.split('/').filter(Boolean) || []
      Object.assign(form, editData)
    }

    await dialogRef.value?.handleOpen(data, {
      title: data.type === 'add' ? '新增保险公司' : '编辑保险公司',
      width: '720px',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })

  const loadRegionOptions = async (): Promise<void> => {
    if (regionOptions.value.length || regionLoading.value) return

    regionLoading.value = true
    try {
      regionOptions.value = await fetchRegionOptions()
    } catch {
      // HTTP layer already shows the error; keep dialog usable.
    } finally {
      regionLoading.value = false
    }
  }
</script>
