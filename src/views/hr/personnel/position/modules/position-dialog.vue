<template>
  <ArtDialog ref="dialogRef" size="lg">
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, {
    type FormItem,
    type FormItemOption
  } from '@/components/core/forms/art-form/index.vue'
  import { addPosition, editPosition } from '@/api/hr'
  import { fetchGetEnableTenantList } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'HrPositionDialog' })

  type Position = Api.Hr.Position

  interface DialogExposeForm {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ (event: 'success', type: 'add' | 'edit'): void }>()
  const { getUserInfo, isPlatformSuper } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Position | undefined>>()
  const formRef = ref<DialogExposeForm>()
  const tenantOptions = ref<FormItemOption[]>([])

  const createInitialForm = (): Position => ({
    tenantId: isPlatformSuper.value ? undefined : getUserInfo.value.tenantId,
    positionCode: '',
    positionName: '',
    positionKind: 'standard',
    systemCode: null,
    enabled: true,
    sort: 0,
    description: ''
  })
  const form = reactive<Position>(createInitialForm())
  const isSystemPosition = computed(() => Boolean(form.systemCode))

  const formRules: FormRules<Position> = {
    tenantId: isPlatformSuper.value
      ? [{ required: true, message: '请选择所属租户', trigger: 'change' }]
      : [],
    positionCode: [
      { required: true, message: '请输入岗位编码', trigger: 'blur' },
      {
        pattern: /^[A-Za-z][A-Za-z0-9_-]{1,31}$/,
        message: '请输入 2-32 位字母开头的编码',
        trigger: 'blur'
      }
    ],
    positionName: [
      { required: true, message: '请输入岗位名称', trigger: 'blur' },
      { min: 2, max: 50, message: '岗位名称应为 2-50 个字符', trigger: 'blur' }
    ],
    sort: [{ required: true, message: '请输入排序值', trigger: 'change' }],
    description: [{ max: 300, message: '岗位说明不能超过 300 个字符', trigger: 'blur' }]
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '岗位信息', key: 'baseSection', type: 'divider', span: 24 },
    {
      label: '所属租户',
      key: 'tenantId',
      type: 'select',
      span: 24,
      hidden: !isPlatformSuper.value,
      options: tenantOptions.value,
      props: { filterable: true, disabled: Boolean(form.id), placeholder: '请选择所属租户' }
    },
    {
      label: '岗位编码',
      key: 'positionCode',
      type: 'input',
      props: { maxlength: 32, disabled: isSystemPosition.value, placeholder: '如 DRIVER' }
    },
    {
      label: '岗位名称',
      key: 'positionName',
      type: 'input',
      props: { maxlength: 50, placeholder: '请输入岗位名称' }
    },
    {
      label: '业务属性',
      key: 'positionKind',
      type: 'select',
      props: {
        disabled: true,
        options: [
          { label: '普通岗位', value: 'standard' },
          { label: '司机岗位', value: 'driver' }
        ]
      },
      description: isSystemPosition.value
        ? '系统司机岗位会触发员工与司机档案联动。'
        : '普通岗位仅用于员工任职管理。'
    },
    {
      label: '排序',
      key: 'sort',
      type: 'number',
      props: { min: 0, max: 9999, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '状态',
      key: 'enabled',
      type: 'switch',
      props: {
        disabled: form.systemCode === 'driver',
        activeText: '启用',
        inactiveText: '停用',
        inlinePrompt: true
      }
    },
    {
      label: '岗位说明',
      key: 'description',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 4, maxlength: 300, showWordLimit: true }
    }
  ])

  const replaceForm = (next: Position): void => {
    Object.keys(form).forEach((key) => delete form[key as keyof Position])
    Object.assign(form, next)
  }
  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      const type = form.id ? 'edit' : 'add'
      if (type === 'edit') await editPosition(structuredClone(toRaw(form)))
      else await addPosition(structuredClone(toRaw(form)))
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Position): Promise<void> => {
    await resetForm()
    if (isPlatformSuper.value && !tenantOptions.value.length) {
      const response = await fetchGetEnableTenantList()
      tenantOptions.value = (response.data ?? []).map((tenant) => ({
        label: `${tenant.tenantName}（${tenant.tenantCode}）`,
        value: tenant.id!
      }))
    }
    if (row) replaceForm({ ...createInitialForm(), ...structuredClone(toRaw(row)) })
    await dialogRef.value?.handleOpen(row, {
      title: row ? '编辑岗位' : '新增岗位',
      subtitle: '维护岗位名称、编码、业务属性与启用状态',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({ handleOpen, handleClose: () => dialogRef.value?.handleClose() })
</script>
