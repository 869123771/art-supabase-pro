<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>{{ config.subtitle }}</template>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="24"
      label-width="110px"
      :show-reset="false"
      :show-submit="false"
    />
    <SmisAttachmentEvidence
      v-if="canEditEvidence"
      v-model="form.attachmentRefs"
      title="本次处理证据"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import SmisAttachmentEvidence from '@/views/smis/components/smis-attachment-evidence.vue'
  import { fetchSmisUserOptions, transitionAccidentCase } from '@/api/smis'
  import { canEditAccidentField } from './accident-field-access'

  defineOptions({ name: 'SmisAccidentActionDialog' })
  type Row = Api.Smis.AccidentEmergency.AccidentCaseRecord
  type Action = Api.Smis.AccidentEmergency.AccidentCaseAction
  interface OpenData {
    row: Row
    action: Action
  }
  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<FormExpose>()
  const state = reactive<{ row: Row | null; action: Action }>({ row: null, action: 'investigate' })
  const form = reactive<{
    investigatorUserId: string
    comment: string
    attachmentRefs: Api.Smis.AccidentEmergency.AttachmentRef[]
  }>({
    investigatorUserId: '',
    comment: '',
    attachmentRefs: []
  })
  const userOptions = ref<Array<{ label: string; value: string }>>([])
  const configs: Record<Action, { title: string; subtitle: string }> = {
    investigate: { title: '立案调查', subtitle: '明确调查负责人，进入原因调查。' },
    rectify: { title: '进入整改', subtitle: '记录原因分析和纠正措施要求。' },
    close: { title: '事故结案', subtitle: '确认整改落实并形成结案证据。' },
    cancel: { title: '作废事件', subtitle: '仅用于误报或重复记录。' }
  }
  const config = computed(() => configs[state.action])
  const canEditParticipants = computed(
    () => !!state.row && canEditAccidentField(state.row, 'caseParticipants')
  )
  const canEditInvestigation = computed(
    () => !!state.row && canEditAccidentField(state.row, 'investigationDetails')
  )
  const canEditEvidence = computed(
    () => !!state.row && canEditAccidentField(state.row, 'caseEvidence')
  )
  const items = computed<FormItem[]>(() => [
    ...(state.action === 'investigate' && canEditParticipants.value
      ? [
          {
            label: '调查负责人',
            key: 'investigatorUserId',
            type: 'select' as const,
            props: { options: userOptions.value, filterable: true }
          }
        ]
      : []),
    ...(canEditInvestigation.value
      ? [
          {
            label: config.value.title + '说明',
            key: 'comment',
            type: 'input' as const,
            props: {
              type: 'textarea',
              rows: 4,
              maxlength: 1500,
              showWordLimit: true
            }
          }
        ]
      : [])
  ])
  const rules = computed<FormRules>(() => ({
    investigatorUserId:
      state.action === 'investigate' && canEditParticipants.value
        ? [{ required: true, message: '请选择调查负责人', trigger: 'change' }]
        : [],
    comment:
      state.action === 'investigate' || !canEditInvestigation.value
        ? []
        : [{ required: true, message: '请填写处理说明', trigger: 'blur' }]
  }))
  const submit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      if (!state.row?.id) return false
      await transitionAccidentCase({
        id: state.row.id,
        action: state.action,
        investigatorUserId: canEditParticipants.value ? form.investigatorUserId || null : null,
        comment: canEditInvestigation.value ? form.comment.trim() || null : null,
        attachmentRefs: canEditEvidence.value ? form.attachmentRefs : []
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }
  const handleOpen = async (data: OpenData): Promise<void> => {
    state.row = data.row
    state.action = data.action
    Object.assign(form, { investigatorUserId: '', comment: '', attachmentRefs: [] })
    if (data.action === 'investigate' && canEditParticipants.value) {
      const response = await fetchSmisUserOptions()
      userOptions.value = (response.data ?? [])
        .filter((item) => Boolean(item.id))
        .map((item) => ({
          label: item.nickName || item.userName || item.userEmail,
          value: item.id!
        }))
    }
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(data, { title: config.value.title, onConfirm: submit })
  }
  defineExpose({ handleOpen })
</script>
