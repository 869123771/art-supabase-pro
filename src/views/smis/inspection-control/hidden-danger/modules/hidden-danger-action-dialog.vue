<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>{{ actionDescription }}</template>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="24"
      label-width="112px"
      :show-reset="false"
      :show-submit="false"
    />
    <SmisAttachmentEvidence
      v-model="form.attachmentRefs"
      :title="current.action === 'submit_review' ? '整改完成证据' : '处理附件'"
      description="附件会随本次状态流转写入审计时间线。"
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
  import { fetchSmisUserOptions, transitionHiddenDanger } from '@/api/smis'

  defineOptions({ name: 'SmisHiddenDangerActionDialog' })

  type Danger = Api.Smis.InspectionControl.HiddenDangerRecord
  type Action = Api.Smis.InspectionControl.HiddenDangerAction
  interface OpenData {
    row: Danger
    action: Action
  }
  interface DialogFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }
  interface ActionForm {
    responsibleUserId: string
    rectificationDeadline: string
    comment: string
    attachmentRefs: Api.Smis.InspectionControl.AttachmentRef[]
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<DialogFormExpose>()
  const current = reactive<OpenData>({ row: {} as Danger, action: 'assign' })
  const form = reactive<ActionForm>({
    responsibleUserId: '',
    rectificationDeadline: '',
    comment: '',
    attachmentRefs: []
  })
  const userOptions = ref<Array<{ label: string; value: string }>>([])

  const titleMap: Record<Action, string> = {
    assign: '指派整改',
    submit_review: '提交复查',
    reject: '退回整改',
    close: '复查销号',
    cancel: '作废隐患'
  }
  const actionDescription = computed(
    () =>
      ({
        assign: '明确整改责任人和完成期限，系统会发送站内通知。',
        submit_review: '填写整改完成情况；提交后等待复查人员确认。',
        reject: '说明未通过原因并退回整改，责任人会收到提醒。',
        close: '确认整改有效后销号，完整过程保留在审计时间线。',
        cancel: '仅用于误报或重复隐患，作废原因会永久留痕。'
      })[current.action]
  )

  const formItems = computed<FormItem[]>(() =>
    current.action === 'assign'
      ? [
          {
            label: '整改责任人',
            key: 'responsibleUserId',
            type: 'select',
            props: { options: userOptions.value, filterable: true, placeholder: '请选择责任人' }
          },
          {
            label: '整改期限',
            key: 'rectificationDeadline',
            type: 'date',
            props: { type: 'datetime', valueFormat: 'YYYY-MM-DD HH:mm:ss', class: '!w-full' }
          },
          {
            label: '指派说明',
            key: 'comment',
            type: 'input',
            props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
          }
        ]
      : [
          {
            label: current.action === 'submit_review' ? '整改说明' : '处理意见',
            key: 'comment',
            type: 'input',
            props: { type: 'textarea', rows: 5, maxlength: 1000, showWordLimit: true }
          }
        ]
  )

  const formRules: FormRules<ActionForm> = {
    responsibleUserId: [{ required: true, message: '请选择整改责任人', trigger: 'change' }],
    rectificationDeadline: [{ required: true, message: '请选择整改期限', trigger: 'change' }],
    comment: [{ required: true, message: '请填写处理说明', trigger: 'blur' }]
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      await transitionHiddenDanger({
        id: current.row.id!,
        action: current.action,
        responsibleUserId: current.action === 'assign' ? form.responsibleUserId : null,
        rectificationDeadline: current.action === 'assign' ? form.rectificationDeadline : null,
        comment: form.comment.trim(),
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
    Object.assign(form, {
      responsibleUserId: data.row.responsibleUserId || '',
      rectificationDeadline:
        data.row.rectificationDeadline || dayjs().add(7, 'day').format('YYYY-MM-DD HH:mm:ss'),
      comment: '',
      attachmentRefs: []
    })
    if (data.action === 'assign') {
      const response = await fetchSmisUserOptions()
      userOptions.value = (response.data ?? [])
        .filter((item): item is typeof item & { id: string } => Boolean(item.id))
        .map((item) => ({
          label: item.nickName || item.userName || item.userEmail,
          value: item.id
        }))
    }
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(data, {
      title: titleMap[data.action],
      onConfirm: handleSubmit
    })
  }

  defineExpose({ handleOpen })
</script>
