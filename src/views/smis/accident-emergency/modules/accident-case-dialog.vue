<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>可关联现有 VMS 事故记录，SMIS 只保存来源引用和安全治理结论。</template>
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
    <SmisAttachmentEvidence
      v-if="canViewAccidentField(form, 'caseEvidence')"
      v-model="formAttachments"
      title="事故现场与调查附件"
      description="统一上传到系统附件库，事故台账仅保存引用。"
      :readonly="!canEditAccidentField(form, 'caseEvidence')"
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
  import {
    addAccidentCase,
    editAccidentCase,
    fetchSmisRiskPointOptions,
    fetchVmsAccidentOptions
  } from '@/api/smis'
  import {
    buildAccidentCaseWritePayload,
    canEditAccidentField,
    canViewAccidentField,
    getAccidentFieldAccess,
    normalizeAccidentCase
  } from './accident-field-access'

  defineOptions({ name: 'SmisAccidentCaseDialog' })
  type AccidentCase = Api.Smis.AccidentEmergency.AccidentCaseRecord
  type VmsOption = Api.Smis.AccidentEmergency.VmsAccidentOption
  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<AccidentCase>>()
  const formRef = ref<FormExpose>()
  const riskPointOptions = ref<Array<{ label: string; value: string }>>([])
  const vmsAccidents = ref<VmsOption[]>([])

  const initialForm = (): AccidentCase => ({
    riskPointId: null,
    sourceType: 'manual',
    sourceBusinessId: null,
    caseNo: `SG-${dayjs().format('YYYYMMDD-HHmmss')}`,
    caseTitle: '',
    incidentType: 'accident',
    severity: 'general',
    occurredAt: dayjs().format('YYYY-MM-DD HH:mm:ss'),
    location: '',
    longitude: null,
    latitude: null,
    description: '',
    casualties: 0,
    economicLoss: 0,
    immediateActions: '',
    causeAnalysis: '',
    correctiveActions: '',
    status: 'reported',
    attachmentRefs: [],
    remark: ''
  })
  const form = reactive<AccidentCase>(initialForm())
  const formAttachments = computed({
    get: () => form.attachmentRefs ?? [],
    set: (value: Api.Smis.AccidentEmergency.AttachmentRef[]) => {
      form.attachmentRefs = value
    }
  })
  const vmsOptions = computed(() =>
    vmsAccidents.value.map((item) => ({
      label: `${item.plateNo} · ${dayjs(item.accidentTime).format('YYYY-MM-DD HH:mm')} · ${item.accidentSummary}`,
      value: item.id
    }))
  )
  const formItems = computed<FormItem[]>(() => [
    { label: '来源与分类', key: 'sourceSection', type: 'divider', span: 24 },
    {
      label: '来源类型',
      key: 'sourceType',
      type: 'select',
      props: {
        disabled: Boolean(form.id),
        options: [
          { label: '现场直接上报', value: 'manual' },
          { label: '关联 VMS 事故', value: 'vms_accident' }
        ]
      }
    },
    ...(form.sourceType === 'vms_accident'
      ? [
          {
            label: 'VMS事故记录',
            key: 'sourceBusinessId',
            type: 'select' as const,
            props: { options: vmsOptions.value, filterable: true, disabled: Boolean(form.id) }
          }
        ]
      : []),
    { label: '事件编号', key: 'caseNo', type: 'input', props: { maxlength: 40 } },
    {
      label: '事件类型',
      key: 'incidentType',
      type: 'select',
      props: {
        options: [
          { label: '事故', value: 'accident' },
          { label: '未遂事件', value: 'near_miss' },
          { label: '不安全事件', value: 'unsafe_event' }
        ]
      }
    },
    {
      label: '严重程度',
      key: 'severity',
      type: 'select',
      props: {
        options: [
          { label: '轻微', value: 'slight' },
          { label: '一般', value: 'general' },
          { label: '较大', value: 'major' },
          { label: '重大', value: 'critical' }
        ]
      }
    },
    {
      label: '关联风险点',
      key: 'riskPointId',
      type: 'select',
      props: { options: riskPointOptions.value, filterable: true, clearable: true }
    },
    { label: '发生与损失', key: 'occurredSection', type: 'divider', span: 24 },
    { label: '事件标题', key: 'caseTitle', type: 'input', span: 24, props: { maxlength: 120 } },
    {
      label: '发生时间',
      key: 'occurredAt',
      type: 'date',
      props: { type: 'datetime', valueFormat: 'YYYY-MM-DD HH:mm:ss', class: '!w-full' }
    },
    ...(canViewAccidentField(form, 'incidentLocation')
      ? [
          {
            label: '发生地点',
            key: 'location',
            type: 'input' as const,
            props: {
              maxlength: 200,
              disabled: !canEditAccidentField(form, 'incidentLocation')
            }
          }
        ]
      : []),
    ...(canViewAccidentField(form, 'casualtyAndLoss')
      ? [
          {
            label: '伤亡人数',
            key: 'casualties',
            type:
              getAccidentFieldAccess(form, 'casualtyAndLoss') === 'masked'
                ? ('input' as const)
                : ('number' as const),
            props: {
              min: 0,
              precision: 0,
              disabled: !canEditAccidentField(form, 'casualtyAndLoss')
            }
          },
          {
            label: '经济损失',
            key: 'economicLoss',
            type:
              getAccidentFieldAccess(form, 'casualtyAndLoss') === 'masked'
                ? ('input' as const)
                : ('number' as const),
            props: {
              min: 0,
              precision: 2,
              disabled: !canEditAccidentField(form, 'casualtyAndLoss')
            }
          }
        ]
      : []),
    ...(canViewAccidentField(form, 'investigationDetails')
      ? [
          {
            label: '事件描述',
            key: 'description',
            type: 'input' as const,
            span: 24,
            props: {
              type: 'textarea',
              rows: 4,
              maxlength: 2000,
              showWordLimit: true,
              disabled: !canEditAccidentField(form, 'investigationDetails')
            }
          },
          {
            label: '即时处置',
            key: 'immediateActions',
            type: 'input' as const,
            span: 24,
            props: {
              type: 'textarea',
              rows: 3,
              maxlength: 1500,
              disabled: !canEditAccidentField(form, 'investigationDetails')
            }
          },
          {
            label: '纠正措施',
            key: 'correctiveActions',
            type: 'input' as const,
            span: 24,
            props: {
              type: 'textarea',
              rows: 3,
              maxlength: 1500,
              disabled: !canEditAccidentField(form, 'investigationDetails')
            }
          }
        ]
      : [])
  ])
  const formRules = computed<FormRules<AccidentCase>>(() => ({
    sourceBusinessId: [
      {
        validator: (_rule, value, callback) => {
          if (form.sourceType === 'vms_accident' && !value) callback(new Error('请选择VMS事故记录'))
          else callback()
        },
        trigger: 'change'
      }
    ],
    caseNo: [{ required: true, message: '请输入事件编号', trigger: 'blur' }],
    caseTitle: [{ required: true, message: '请输入事件标题', trigger: 'blur' }],
    occurredAt: [{ required: true, message: '请选择发生时间', trigger: 'change' }],
    description: canEditAccidentField(form, 'investigationDetails')
      ? [{ required: true, message: '请输入事件描述', trigger: 'blur' }]
      : []
  }))

  watch(
    () => form.sourceType,
    (value) => {
      if (value === 'manual') form.sourceBusinessId = null
    }
  )
  watch(
    () => form.sourceBusinessId,
    (id) => {
      if (form.sourceType !== 'vms_accident' || !id || form.id) return
      const source = vmsAccidents.value.find((item) => item.id === id)
      if (!source) return
      form.caseTitle = `${source.plateNo} 车辆事故`
      form.occurredAt = source.accidentTime
      form.location = source.accidentLocation || ''
      form.description = source.accidentSummary
      form.economicLoss = source.economicLoss || 0
    }
  )

  const submit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      const payload = buildAccidentCaseWritePayload(structuredClone(toRaw(form)))
      if (payload.id) await editAccidentCase(payload)
      else await addAccidentCase(payload)
      emit('success')
      return true
    } catch {
      return false
    }
  }
  const handleOpen = async (row?: AccidentCase): Promise<void> => {
    const [riskPoints, vms] = await Promise.all([
      fetchSmisRiskPointOptions(),
      fetchVmsAccidentOptions()
    ])
    riskPointOptions.value = (riskPoints.data ?? []).map((item) => ({
      label: `${item.riskPointNo} · ${item.riskPointName}`,
      value: item.id!
    }))
    vmsAccidents.value = vms.data ?? []
    Object.keys(form).forEach((key) => delete form[key as keyof AccidentCase])
    Object.assign(
      form,
      row ? normalizeAccidentCase(structuredClone(toRaw(row))) : initialForm()
    )
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(row, {
      title: row ? '编辑事故事件' : '上报事故事件',
      onConfirm: submit,
      onReset: () =>
        Object.assign(
          form,
          row ? normalizeAccidentCase(structuredClone(toRaw(row))) : initialForm()
        )
    })
  }
  defineExpose({ handleOpen })
</script>
