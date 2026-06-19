<template>
  <ArtDialog ref="dialogRef" width="800px">
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
  import { addSupplier, editSupplier } from '@/api/vehicle-mgt-sys'
  import { fetchRegionOptions } from '@/api/common'

  type Supplier = Api.VehicleMgtSys.BasicInfo.Supplier
  type SupplierForm = Supplier & {
    regionPath?: string[]
  }
  type RegionOption = Record<string, unknown> & { children?: RegionOption[] }

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const dialogRef = ref<ArtDialogExpose<Supplier | undefined>>()
  const formRef = ref<{
    validate: () => Promise<boolean>
    clearValidate: () => void
  }>()

  const createInitialForm = (): SupplierForm => ({
    id: undefined,
    supplierName: '',
    contactPerson: '',
    contactPhone: '',
    region: '',
    regionPath: [],
    addressDetail: '',
    remark: ''
  })

  const form = reactive<SupplierForm>(createInitialForm())

  const rules: FormRules<SupplierForm> = {
    supplierName: [
      { required: true, message: '请输入供应厂商名称', trigger: 'blur' },
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
      label: '供应厂商名称',
      key: 'supplierName',
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
      label: '省/市/区',
      key: 'regionPath',
      type: 'cascader',
      props: {
        props: {
          label: 'name',
          value: 'name',
          children: 'children',
          emitPath: true,
          checkStrictly: true
        },
        class: '!w-full'
      },
      api: fetchRegionOptions,
      labelField: 'name',
      valueField: 'name',
      childrenField: 'children',
      afterFetch: (data: unknown) => {
        const normalizeRegionOptions = (options: RegionOption[]): RegionOption[] => {
          return options.map((option) => ({
            ...option,
            children: Array.isArray(option.children)
              ? normalizeRegionOptions(option.children)
              : undefined
          }))
        }
        if (Array.isArray(data)) return normalizeRegionOptions(data as RegionOption[])
        if (typeof data !== 'string') return []
        try {
          const parsed = JSON.parse(data) as unknown
          return Array.isArray(parsed) ? normalizeRegionOptions(parsed as RegionOption[]) : []
        } catch {
          return []
        }
      }
    },
    {
      label: '详细地址',
      key: 'addressDetail',
      type: 'input',
      props: {
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

  const replaceForm = (nextForm: SupplierForm): void => {
    Object.keys(form).forEach((key) => {
      delete form[key as keyof SupplierForm]
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
      payload.region = regionPath?.join('/') || ''
      if (form.id) {
        await editSupplier(payload)
      } else {
        await addSupplier(payload)
      }
      emit('success', form.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Supplier): Promise<void> => {
    await resetForm()
    const isEdit = !!row?.id
    if (isEdit) {
      const editData = structuredClone(toRaw(row)) as SupplierForm
      editData.regionPath = editData.region?.split('/').filter(Boolean) || []
      replaceForm(editData)
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑供应厂商' : '新增供应厂商',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
