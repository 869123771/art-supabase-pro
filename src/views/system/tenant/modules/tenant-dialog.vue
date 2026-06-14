<template>
  <ArtDialog ref="dialogRef" width="760px">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="12"
      :gutter="20"
      label-width="100px"
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
  import { addTenant, editTenant } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'

  type Tenant = Api.SystemManage.TenantListItem

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore()) as Record<string, any>
  const dialogRef = ref<ArtDialogExpose<Tenant | undefined>>()
  const formRef = ref<{
    validate: () => Promise<boolean>
    clearValidate: () => void
  }>()

  const createInitialForm = (): Tenant => ({
    id: undefined,
    tenantCode: '',
    tenantName: '',
    status: '1',
    contactName: '',
    contactPhone: '',
    contactEmail: '',
    remark: ''
  })

  const form = reactive<Tenant>(createInitialForm())

  const rules: FormRules<Tenant> = {
    tenantCode: [
      { required: true, message: '请输入租户编码', trigger: 'blur' },
      { min: 2, max: 50, message: '长度应为 2 到 50 个字符', trigger: 'blur' },
      {
        pattern: /^[A-Za-z0-9_-]+$/,
        message: '租户编码只能包含字母、数字、下划线和短横线',
        trigger: 'blur'
      }
    ],
    tenantName: [
      { required: true, message: '请输入租户名称', trigger: 'blur' },
      { min: 2, max: 100, message: '长度应为 2 到 100 个字符', trigger: 'blur' }
    ],
    contactName: [{ max: 50, message: '联系人不能超过 50 个字符', trigger: 'blur' }],
    contactPhone: [{ max: 30, message: '联系电话不能超过 30 个字符', trigger: 'blur' }],
    contactEmail: [
      { type: 'email', message: '请输入正确的邮箱地址', trigger: 'blur' },
      { max: 100, message: '联系邮箱不能超过 100 个字符', trigger: 'blur' }
    ],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const items = computed<FormItem[]>(() => [
    {
      label: '租户编码',
      key: 'tenantCode',
      type: 'input',
      props: {
        maxlength: 50,
        disabled: !!form.id
      }
    },
    {
      label: '租户名称',
      key: 'tenantName',
      type: 'input',
      props: {
        maxlength: 100
      }
    },
    {
      label: '联系人',
      key: 'contactName',
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
        maxlength: 30
      }
    },
    {
      label: '联系邮箱',
      key: 'contactEmail',
      type: 'input',
      props: {
        maxlength: 100
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'radioGroup',
      props: {
        options: getDictMap.value.status ?? []
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
        showWordLimit: true
      }
    }
  ])

  const replaceForm = (nextForm: Tenant): void => {
    Object.keys(form).forEach((key) => {
      delete form[key as keyof Tenant]
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
      const payload = toRaw(form)
      if (form.id) {
        await editTenant(payload)
      } else {
        await addTenant(payload)
      }
      emit('success', form.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Tenant): Promise<void> => {
    await resetForm()
    const isEdit = !!row?.id
    if (isEdit) {
      replaceForm(structuredClone(toRaw(row)) as Tenant)
    }

    await dialogRef.value?.handleOpen(row, {
      title: isEdit ? '编辑租户' : '新增租户',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
