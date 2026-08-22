<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>检查结果和结论会形成不可绕过的任务完成记录。</template>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="24"
      label-width="102px"
      :show-reset="false"
      :show-submit="false"
    />
    <SmisAttachmentEvidence
      v-if="current.action === 'complete'"
      v-model="form.attachmentRefs"
      title="检查结果附件"
      description="上传检查表、现场照片或检测报告。"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import SmisAttachmentEvidence from '@/views/smis/components/smis-attachment-evidence.vue'
  import { transitionInspectionTask } from '@/api/smis'

  defineOptions({ name: 'SmisInspectionTaskActionDialog' })
  type Task = Api.Smis.InspectionControl.InspectionTaskRecord
  interface OpenData {
    row: Task
    action: 'complete' | 'cancel'
  }
  interface DialogFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }
  interface ActionForm {
    checkResult: Api.Smis.InspectionControl.InspectionResult | ''
    resultSummary: string
    comment: string
    attachmentRefs: Api.Smis.InspectionControl.AttachmentRef[]
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<DialogFormExpose>()
  const current = reactive<OpenData>({ row: {} as Task, action: 'complete' })
  const form = reactive<ActionForm>({
    checkResult: '',
    resultSummary: '',
    comment: '',
    attachmentRefs: []
  })
  const formItems = computed<FormItem[]>(() =>
    current.action === 'complete'
      ? [
          {
            label: '检查结果',
            key: 'checkResult',
            type: 'select',
            props: {
              options: [
                { label: '正常', value: 'normal' },
                { label: '发现隐患', value: 'hidden_danger' },
                { label: '不适用', value: 'not_applicable' }
              ]
            }
          },
          {
            label: '检查结论',
            key: 'resultSummary',
            type: 'input',
            props: { type: 'textarea', rows: 5, maxlength: 1000, showWordLimit: true }
          }
        ]
      : [
          {
            label: '取消原因',
            key: 'comment',
            type: 'input',
            props: { type: 'textarea', rows: 4, maxlength: 500, showWordLimit: true }
          }
        ]
  )
  const formRules: FormRules<ActionForm> = {
    checkResult: [{ required: true, message: '请选择检查结果', trigger: 'change' }],
    resultSummary: [{ required: true, message: '请填写检查结论', trigger: 'blur' }],
    comment: [{ required: true, message: '请填写取消原因', trigger: 'blur' }]
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      await transitionInspectionTask({
        id: current.row.id!,
        action: current.action,
        checkResult: current.action === 'complete' ? form.checkResult || null : null,
        resultSummary: current.action === 'complete' ? form.resultSummary.trim() : null,
        comment: current.action === 'cancel' ? form.comment.trim() : null,
        attachmentRefs: form.attachmentRefs
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async (data: OpenData): Promise<void> => {
    Object.assign(current, data)
    Object.assign(form, { checkResult: '', resultSummary: '', comment: '', attachmentRefs: [] })
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(data, {
      title: data.action === 'complete' ? '完成检查任务' : '取消检查任务',
      onConfirm: handleSubmit
    })
  }
  defineExpose({ handleOpen })
</script>
