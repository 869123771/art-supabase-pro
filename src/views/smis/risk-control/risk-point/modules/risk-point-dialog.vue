<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      风险点用于关联危险源、评估版本与管控措施；风险等级由生效的 LEC 评估自动确定。
    </template>

    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="108px"
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
  import {
    addRiskPoint,
    editRiskPoint,
    fetchAreaOptions,
    fetchSiteOptions,
    fetchSmisOrganizationOptions,
    fetchSmisUserOptions
  } from '@/api/smis'

  defineOptions({ name: 'SmisRiskPointDialog' })

  type RiskPoint = Api.Smis.RiskControl.RiskPointRecord

  interface DialogFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ (event: 'success', type: 'add' | 'edit'): void }>()
  const dialogRef = ref<ArtDialogExpose<RiskPoint | undefined>>()
  const formRef = ref<DialogFormExpose>()
  const siteOptions = ref<FormItemOption[]>([])
  const allAreaOptions = ref<Array<FormItemOption & { siteId: string }>>([])
  const organizationOptions = ref<FormItemOption[]>([])
  const userOptions = ref<FormItemOption[]>([])

  const createInitialForm = (): RiskPoint => ({
    siteId: '',
    areaId: '',
    organizationId: null,
    responsibleUserId: null,
    riskPointNo: '',
    riskPointName: '',
    operationActivity: '',
    riskCategory: '',
    possibleConsequence: '',
    status: 'active',
    inspectionFrequency: '',
    remark: ''
  })

  const form = reactive<RiskPoint>(createInitialForm())
  const areaOptions = computed(() =>
    allAreaOptions.value.filter((option) => option.siteId === form.siteId)
  )

  const formRules: FormRules<RiskPoint> = {
    riskPointNo: [
      { required: true, message: '请输入风险点编号', trigger: 'blur' },
      {
        pattern: /^[A-Za-z0-9][A-Za-z0-9_-]{1,31}$/,
        message: '请输入 2-32 位字母、数字、下划线或短横线',
        trigger: 'blur'
      }
    ],
    riskPointName: [
      { required: true, message: '请输入风险点名称', trigger: 'blur' },
      { min: 2, max: 100, message: '风险点名称应为 2-100 个字符', trigger: 'blur' }
    ],
    siteId: [{ required: true, message: '请选择所属场所', trigger: 'change' }],
    areaId: [{ required: true, message: '请选择所属区域', trigger: 'change' }],
    operationActivity: [{ max: 300, message: '作业活动不能超过 300 个字符', trigger: 'blur' }],
    possibleConsequence: [{ max: 500, message: '可能后果不能超过 500 个字符', trigger: 'blur' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
  }

  const formItems = computed<FormItem[]>(() => [
    { label: '风险点标识', key: 'identitySection', type: 'divider', span: 24 },
    {
      label: '风险点编号',
      key: 'riskPointNo',
      type: 'input',
      props: { maxlength: 32, placeholder: '如 RP-WH-001' }
    },
    {
      label: '风险点名称',
      key: 'riskPointName',
      type: 'input',
      props: { maxlength: 100, placeholder: '请输入可识别的现场名称' }
    },
    {
      label: '所属场所',
      key: 'siteId',
      type: 'select',
      options: siteOptions.value,
      props: { filterable: true, placeholder: '请选择场所' }
    },
    {
      label: '所属区域',
      key: 'areaId',
      type: 'select',
      options: areaOptions.value,
      props: {
        filterable: true,
        disabled: !form.siteId,
        placeholder: form.siteId ? '请选择区域' : '请先选择场所'
      }
    },
    {
      label: '责任组织',
      key: 'organizationId',
      type: 'select',
      options: organizationOptions.value,
      props: { clearable: true, filterable: true, placeholder: '请选择责任组织' }
    },
    {
      label: '责任人',
      key: 'responsibleUserId',
      type: 'select',
      options: userOptions.value,
      props: { clearable: true, filterable: true, placeholder: '请选择责任人' }
    },
    { label: '风险描述', key: 'riskSection', type: 'divider', span: 24 },
    {
      label: '风险类别',
      key: 'riskCategory',
      type: 'input',
      props: { maxlength: 50, placeholder: '如火灾、车辆伤害、高处坠落' }
    },
    {
      label: '检查频次',
      key: 'inspectionFrequency',
      type: 'input',
      props: { maxlength: 50, placeholder: '如每班、每日、每周' }
    },
    {
      label: '作业活动',
      key: 'operationActivity',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 2, maxlength: 300, showWordLimit: true }
    },
    {
      label: '可能后果',
      key: 'possibleConsequence',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      options: [
        { label: '启用', value: 'active' },
        { label: '停用', value: 'inactive' },
        { label: '已归档', value: 'archived' }
      ]
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 2, maxlength: 500, showWordLimit: true }
    }
  ])

  const replaceForm = (next: RiskPoint): void => {
    Object.keys(form).forEach((key) => delete form[key as keyof RiskPoint])
    Object.assign(form, next)
  }

  const resetForm = async (): Promise<void> => {
    replaceForm(createInitialForm())
    await nextTick()
    formRef.value?.clearValidate()
  }

  const loadOptions = async (): Promise<void> => {
    const [sites, areas, organizations, users] = await Promise.all([
      fetchSiteOptions(),
      fetchAreaOptions(),
      fetchSmisOrganizationOptions(),
      fetchSmisUserOptions()
    ])
    siteOptions.value = (sites.data ?? []).map((item) => ({
      label: `${item.siteName}（${item.siteCode}）`,
      value: item.id!
    }))
    allAreaOptions.value = (areas.data ?? []).map((item) => ({
      label: `${item.areaName}（${item.areaCode}）`,
      value: item.id!,
      siteId: item.siteId
    }))
    organizationOptions.value = (organizations.data ?? []).map((item) => ({
      label: `${item.organizationName}（${item.organizationCode}）`,
      value: item.id!
    }))
    userOptions.value = (users.data ?? []).map((item) => ({
      label: item.nickName || item.userName || item.userEmail,
      value: item.id!
    }))
  }

  watch(
    () => form.siteId,
    (siteId, previousSiteId) => {
      if (!previousSiteId || siteId === previousSiteId) return
      if (!areaOptions.value.some((option) => option.value === form.areaId)) form.areaId = ''
    }
  )

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      const type = form.id ? 'edit' : 'add'
      const payload = structuredClone(toRaw(form))
      if (type === 'edit') await editRiskPoint(payload)
      else await addRiskPoint(payload)
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: RiskPoint): Promise<void> => {
    await resetForm()
    await loadOptions()
    if (row) replaceForm({ ...createInitialForm(), ...structuredClone(toRaw(row)) })
    await dialogRef.value?.handleOpen(row, {
      title: row ? '编辑风险点' : '新增风险点',
      onConfirm: handleSubmit,
      onReset: () => void resetForm()
    })
  }

  defineExpose({ handleOpen, handleClose: () => dialogRef.value?.handleClose() })
</script>
