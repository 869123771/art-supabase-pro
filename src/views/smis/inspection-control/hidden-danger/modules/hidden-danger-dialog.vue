<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>上报后进入整改闭环；风险点和危险源关系会在数据库再次校验。</template>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="12"
      :gutter="20"
      label-width="116px"
      :show-reset="false"
      :show-submit="false"
    />
    <SmisAttachmentEvidence
      v-model="form.attachmentRefs"
      title="隐患现场证据"
      description="上传现场照片、检查记录或其他佐证材料。"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import SmisAttachmentEvidence from '@/views/smis/components/smis-attachment-evidence.vue'
  import { addHiddenDanger, fetchHazardSourceList, fetchSmisRiskPointOptions } from '@/api/smis'

  defineOptions({ name: 'SmisHiddenDangerDialog' })

  type Danger = Api.Smis.InspectionControl.HiddenDangerRecord
  type Task = Api.Smis.InspectionControl.InspectionTaskRecord
  interface OpenData {
    task?: Task
    riskPointId?: string
  }
  interface DialogFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<DialogFormExpose>()
  const riskPointOptions = ref<Array<{ label: string; value: string }>>([])
  const hazardOptions = ref<Array<{ label: string; value: string }>>([])

  const createDangerNo = (): string => `YH-${dayjs().format('YYYYMMDD-HHmmss')}`
  const createInitialForm = (data?: OpenData): Danger => ({
    taskId: data?.task?.id || null,
    riskPointId: data?.task?.riskPointId || data?.riskPointId || '',
    hazardSourceId: null,
    dangerNo: createDangerNo(),
    dangerTitle: '',
    dangerDescription: '',
    dangerLevel: 'general',
    rectificationRequirement: '',
    rectificationDeadline: null,
    status: 'reported',
    attachmentRefs: [],
    remark: ''
  })
  const form = reactive<Danger>(createInitialForm())

  const formItems = computed<FormItem[]>(() => [
    { label: '隐患定位', key: 'scopeSection', type: 'divider', span: 24 },
    {
      label: '隐患编号',
      key: 'dangerNo',
      type: 'input',
      props: { maxlength: 40, placeholder: '如 YH-20260821-001' }
    },
    {
      label: '风险点',
      key: 'riskPointId',
      type: 'select',
      props: { options: riskPointOptions.value, filterable: true, disabled: Boolean(form.taskId) }
    },
    {
      label: '关联危险源',
      key: 'hazardSourceId',
      type: 'select',
      props: { options: hazardOptions.value, filterable: true, clearable: true }
    },
    {
      label: '隐患等级',
      key: 'dangerLevel',
      type: 'select',
      props: {
        options: [
          { label: '低风险', value: 'low' },
          { label: '一般风险', value: 'general' },
          { label: '较大风险', value: 'major' },
          { label: '重大风险', value: 'critical' }
        ]
      }
    },
    { label: '问题描述', key: 'contentSection', type: 'divider', span: 24 },
    {
      label: '隐患标题',
      key: 'dangerTitle',
      type: 'input',
      span: 24,
      props: { maxlength: 120, placeholder: '简明描述问题对象和异常现象' }
    },
    {
      label: '隐患描述',
      key: 'dangerDescription',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 4, maxlength: 1000, showWordLimit: true }
    },
    {
      label: '整改要求',
      key: 'rectificationRequirement',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 1000, showWordLimit: true }
    },
    {
      label: '建议期限',
      key: 'rectificationDeadline',
      type: 'date',
      props: { type: 'datetime', valueFormat: 'YYYY-MM-DD HH:mm:ss', class: '!w-full' }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      props: { maxlength: 500 }
    }
  ])

  const formRules: FormRules<Danger> = {
    dangerNo: [{ required: true, message: '请输入隐患编号', trigger: 'blur' }],
    riskPointId: [{ required: true, message: '请选择风险点', trigger: 'change' }],
    dangerTitle: [{ required: true, message: '请输入隐患标题', trigger: 'blur' }],
    dangerDescription: [{ required: true, message: '请输入隐患描述', trigger: 'blur' }],
    dangerLevel: [{ required: true, message: '请选择隐患等级', trigger: 'change' }]
  }

  const loadHazards = async (riskPointId: string): Promise<void> => {
    if (!riskPointId) {
      hazardOptions.value = []
      return
    }
    const response = await fetchHazardSourceList(riskPointId)
    hazardOptions.value = (response.data ?? [])
      .filter((item) => item.enabled)
      .map((item) => ({
        label: `${item.sourceNo} · ${item.hazardName}`,
        value: item.id!
      }))
  }

  watch(
    () => form.riskPointId,
    async (riskPointId, previous) => {
      if (riskPointId !== previous) form.hazardSourceId = null
      await loadHazards(riskPointId)
    }
  )

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      await addHiddenDanger({
        ...structuredClone(toRaw(form)),
        dangerNo: form.dangerNo.trim(),
        dangerTitle: form.dangerTitle.trim(),
        dangerDescription: form.dangerDescription.trim(),
        rectificationRequirement: form.rectificationRequirement?.trim() || null,
        rectificationDeadline: form.rectificationDeadline || null,
        hazardSourceId: form.hazardSourceId || null,
        remark: form.remark?.trim() || null
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (data: OpenData = {}): Promise<void> => {
    Object.assign(form, createInitialForm(data))
    const riskPoints = await fetchSmisRiskPointOptions()
    riskPointOptions.value = (riskPoints.data ?? []).map((item) => ({
      label: `${item.riskPointNo} · ${item.riskPointName}`,
      value: item.id!
    }))
    await loadHazards(form.riskPointId)
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(data, {
      title: data.task ? `登记检查隐患 · ${data.task.taskNo}` : '上报隐患',
      onConfirm: handleSubmit,
      onReset: () => Object.assign(form, createInitialForm(data))
    })
  }

  defineExpose({ handleOpen })
</script>
