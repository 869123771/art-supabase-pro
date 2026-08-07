<template>
  <ArtDialog ref="dialogRef" size="md">
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
  import { omit } from 'lodash-es'

  type Tenant = Api.SystemManage.TenantListItem

  interface Emits {
    (e: 'success', type: 'add' | 'edit'): void
  }

  const emit = defineEmits<Emits>()
  const { getDictMap } = storeToRefs(useUserStore())
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
    remark: '',
    createBy: undefined,
    createTime: undefined,
    updateBy: undefined,
    updateTime: undefined
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
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const items = computed<FormItem[]>(() => [
    {
      label: '租户身份',
      key: 'identitySection',
      type: 'divider',
      span: 24
    },
    {
      label: '租户编码',
      key: 'tenantCode',
      type: 'input',
      props: {
        maxlength: 50,
        disabled: !!form.id,
        placeholder: '如：north_china_ops'
      },
      help: '租户编码用于系统隔离与内部识别，创建后不可修改。',
      description: form.id ? '该租户编码已锁定。' : '建议使用简短、稳定的英文编码。'
    },
    {
      label: '租户名称',
      key: 'tenantName',
      type: 'input',
      props: {
        maxlength: 100,
        placeholder: '请输入组织或业务主体名称'
      },
      description: '名称将用于租户识别与后台管理展示。'
    },
    {
      label: '状态与说明',
      key: 'statusSection',
      type: 'divider',
      span: 24
    },
    {
      label: '状态',
      key: 'status',
      type: 'radioGroup',
      props: {
        options: getDictMap.value.status ?? []
      },
      span: 24,
      description: '停用前请确认租户内账号及业务安排已妥善处理。'
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
        placeholder: '补充租户用途、负责人或管理说明（选填）'
      },
      description: '建议记录该租户的业务范围，便于后续运维识别。'
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
      const payload = omit(toRaw(form), ['createBy', 'createTime', 'updateBy', 'updateTime'])
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
      contentMaxHeight: '68vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({
    handleOpen,
    handleClose: () => dialogRef.value?.handleClose()
  })
</script>
