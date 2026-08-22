<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle
      >任务可来自人工、检查计划、车辆例检或运输运单，外部业务仅保存关联 ID。</template
    >
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="112px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import {
    addInspectionTask,
    editInspectionTask,
    fetchInspectionPlanOptions,
    fetchSmisRiskPointOptions,
    fetchSmisUserOptions
  } from '@/api/smis'

  defineOptions({ name: 'SmisInspectionTaskDialog' })

  type Task = Api.Smis.InspectionControl.InspectionTaskRecord
  interface DialogFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<Task | undefined>>()
  const formRef = ref<DialogFormExpose>()
  const riskPointOptions = ref<Array<{ label: string; value: string }>>([])
  const userOptions = ref<Array<{ label: string; value: string }>>([])
  const planOptions = ref<Array<{ label: string; value: string }>>([])

  const createTaskNo = (): string => `JC-${dayjs().format('YYYYMMDD-HHmmss')}`
  const createInitialForm = (): Task => ({
    taskNo: createTaskNo(),
    taskName: '',
    planId: null,
    riskPointId: '',
    inspectorUserId: null,
    sourceType: 'manual',
    sourceBusinessId: null,
    scheduledStartAt: dayjs().format('YYYY-MM-DD HH:mm:ss'),
    scheduledEndAt: dayjs().add(1, 'hour').format('YYYY-MM-DD HH:mm:ss'),
    status: 'pending',
    remark: ''
  })
  const form = reactive<Task>(createInitialForm())

  const formItems = computed<FormItem[]>(() => [
    { label: '任务信息', key: 'identitySection', type: 'divider', span: 24 },
    {
      label: '任务编号',
      key: 'taskNo',
      type: 'input',
      props: { maxlength: 40, placeholder: '如 JC-20260821-001' }
    },
    {
      label: '任务名称',
      key: 'taskName',
      type: 'input',
      props: { maxlength: 100, placeholder: '用检查对象和目的命名' }
    },
    {
      label: '风险点',
      key: 'riskPointId',
      type: 'select',
      props: { options: riskPointOptions.value, filterable: true, placeholder: '请选择风险点' }
    },
    {
      label: '检查人',
      key: 'inspectorUserId',
      type: 'select',
      props: { options: userOptions.value, filterable: true, clearable: true }
    },
    {
      label: '来源类型',
      key: 'sourceType',
      type: 'select',
      props: {
        options: [
          { label: '人工创建', value: 'manual' },
          { label: '检查计划', value: 'plan' },
          { label: '车辆例检', value: 'vms_routine_inspection' },
          { label: '运输运单', value: 'tms_waybill' }
        ]
      }
    },
    ...(form.sourceType === 'plan'
      ? [
          {
            label: '检查计划',
            key: 'planId',
            type: 'select' as const,
            props: { options: planOptions.value, filterable: true, clearable: true }
          }
        ]
      : []),
    ...(form.sourceType === 'vms_routine_inspection' || form.sourceType === 'tms_waybill'
      ? [
          {
            label: '来源业务 ID',
            key: 'sourceBusinessId',
            type: 'input' as const,
            props: { placeholder: '选择器接入前可粘贴现有业务记录 UUID' }
          }
        ]
      : []),
    { label: '执行安排', key: 'scheduleSection', type: 'divider', span: 24 },
    {
      label: '计划开始',
      key: 'scheduledStartAt',
      type: 'date',
      props: { type: 'datetime', valueFormat: 'YYYY-MM-DD HH:mm:ss', class: '!w-full' }
    },
    {
      label: '计划结束',
      key: 'scheduledEndAt',
      type: 'date',
      props: { type: 'datetime', valueFormat: 'YYYY-MM-DD HH:mm:ss', class: '!w-full' }
    },
    {
      label: '检查说明',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  const formRules: FormRules<Task> = {
    taskNo: [{ required: true, message: '请输入任务编号', trigger: 'blur' }],
    taskName: [{ required: true, message: '请输入任务名称', trigger: 'blur' }],
    riskPointId: [{ required: true, message: '请选择风险点', trigger: 'change' }],
    sourceType: [{ required: true, message: '请选择来源类型', trigger: 'change' }],
    scheduledStartAt: [{ required: true, message: '请选择计划开始时间', trigger: 'change' }],
    scheduledEndAt: [{ required: true, message: '请选择计划结束时间', trigger: 'change' }]
  }

  watch(
    () => form.sourceType,
    (sourceType) => {
      if (sourceType !== 'plan') form.planId = null
      if (!['vms_routine_inspection', 'tms_waybill'].includes(sourceType)) {
        form.sourceBusinessId = null
      }
    }
  )

  const loadOptions = async (): Promise<void> => {
    const [riskPoints, users, plans] = await Promise.all([
      fetchSmisRiskPointOptions(),
      fetchSmisUserOptions(),
      fetchInspectionPlanOptions()
    ])
    riskPointOptions.value = (riskPoints.data ?? []).map((item) => ({
      label: `${item.riskPointNo} · ${item.riskPointName}`,
      value: item.id!
    }))
    userOptions.value = (users.data ?? [])
      .filter((item): item is typeof item & { id: string } => Boolean(item.id))
      .map((item) => ({
        label: item.nickName || item.userName || item.userEmail,
        value: item.id
      }))
    planOptions.value = (plans.data ?? []).map((item) => ({
      label: `${item.planNo} · ${item.planName}`,
      value: item.id!
    }))
  }

  const replaceForm = (next?: Task): void => {
    Object.assign(form, createInitialForm(), next ? structuredClone(toRaw(next)) : {})
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      if (dayjs(form.scheduledEndAt).isBefore(dayjs(form.scheduledStartAt))) {
        throw new Error('计划结束时间不能早于开始时间')
      }
      const payload: Task = {
        ...structuredClone(toRaw(form)),
        taskNo: form.taskNo.trim(),
        taskName: form.taskName.trim(),
        planId: form.planId || null,
        inspectorUserId: form.inspectorUserId || null,
        sourceBusinessId: form.sourceBusinessId || null,
        remark: form.remark?.trim() || null
      }
      if (payload.id) await editInspectionTask(payload)
      else await addInspectionTask(payload)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (row?: Task): Promise<void> => {
    replaceForm(row)
    await loadOptions()
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(row, {
      title: row ? '编辑检查任务' : '新增检查任务',
      onConfirm: handleSubmit,
      onReset: () => replaceForm(row)
    })
  }

  defineExpose({ handleOpen })
</script>
