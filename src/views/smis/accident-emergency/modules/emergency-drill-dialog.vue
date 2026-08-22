<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>关联已有应急预案，记录演练场景、问题和改进措施。</template>
    <ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="12"
      :gutter="20"
      label-width="110px"
      :show-reset="false"
      :show-submit="false"
    />
    <SmisAttachmentEvidence v-model="form.attachmentRefs" title="演练影像与评估材料" />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import SmisAttachmentEvidence from '@/views/smis/components/smis-attachment-evidence.vue'
  import { fetchEmergencyPlanList, fetchSmisUserOptions, saveEmergencyDrill } from '@/api/smis'

  defineOptions({ name: 'SmisEmergencyDrillDialog' })
  type Drill = Api.Smis.AccidentEmergency.EmergencyDrillRecord
  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<Drill>>()
  const formRef = ref<FormExpose>()
  const planOptions = ref<Array<{ label: string; value: string }>>([])
  const userOptions = ref<Array<{ label: string; value: string }>>([])
  const initial = (): Drill => ({
    planId: '',
    organizerUserId: null,
    drillNo: '',
    drillName: '',
    drillType: 'desktop',
    scheduledAt: '',
    actualAt: null,
    scenario: '',
    participants: '',
    result: null,
    issuesFound: '',
    improvementActions: '',
    status: 'planned',
    attachmentRefs: [],
    remark: ''
  })
  const form = reactive<Drill>(initial())
  const items = computed<FormItem[]>(() => [
    { label: '演练编号', key: 'drillNo', type: 'input', props: { maxlength: 40 } },
    { label: '演练名称', key: 'drillName', type: 'input', props: { maxlength: 120 } },
    {
      label: '关联预案',
      key: 'planId',
      type: 'select',
      props: {
        options: planOptions.value,
        filterable: true
      }
    },
    {
      label: '演练类型',
      key: 'drillType',
      type: 'select',
      props: {
        options: [
          { label: '桌面推演', value: 'desktop' },
          { label: '功能演练', value: 'functional' },
          { label: '综合实战', value: 'full_scale' }
        ]
      }
    },
    {
      label: '计划时间',
      key: 'scheduledAt',
      type: 'date',
      props: {
        type: 'datetime',
        valueFormat: 'YYYY-MM-DD HH:mm:ss',
        class: '!w-full'
      }
    },
    {
      label: '实际时间',
      key: 'actualAt',
      type: 'date',
      props: {
        type: 'datetime',
        valueFormat: 'YYYY-MM-DD HH:mm:ss',
        class: '!w-full'
      }
    },
    {
      label: '组织人',
      key: 'organizerUserId',
      type: 'select',
      props: {
        options: userOptions.value,
        filterable: true,
        clearable: true
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        options: [
          { label: '待演练', value: 'planned' },
          { label: '已完成', value: 'completed' },
          { label: '已取消', value: 'cancelled' }
        ]
      }
    },
    {
      label: '演练结果',
      key: 'result',
      type: 'select',
      props: {
        clearable: true,
        options: [
          { label: '优秀', value: 'excellent' },
          { label: '良好', value: 'good' },
          { label: '需改进', value: 'needs_improvement' }
        ]
      }
    },
    { label: '参与人员', key: 'participants', type: 'input', props: { maxlength: 500 } },
    {
      label: '演练场景',
      key: 'scenario',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 1500 }
    },
    {
      label: '发现问题',
      key: 'issuesFound',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 1500 }
    },
    {
      label: '改进措施',
      key: 'improvementActions',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 1500 }
    }
  ])
  const rules: FormRules<Drill> = {
    drillNo: [{ required: true, message: '请输入演练编号', trigger: 'blur' }],
    drillName: [{ required: true, message: '请输入演练名称', trigger: 'blur' }],
    planId: [{ required: true, message: '请选择应急预案', trigger: 'change' }],
    scheduledAt: [{ required: true, message: '请选择计划时间', trigger: 'change' }]
  }
  const submit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      await saveEmergencyDrill(structuredClone(toRaw(form)))
      emit('success')
      return true
    } catch {
      return false
    }
  }
  const handleOpen = async (row?: Drill): Promise<void> => {
    const [plans, users] = await Promise.all([fetchEmergencyPlanList(), fetchSmisUserOptions()])
    planOptions.value = (plans.data ?? []).map((item) => ({
      label: `${item.planNo} · ${item.planName}`,
      value: item.id!
    }))
    userOptions.value = (users.data ?? [])
      .filter((item) => Boolean(item.id))
      .map((item) => ({
        label: item.nickName || item.userName || item.userEmail,
        value: item.id!
      }))
    Object.assign(form, row ? structuredClone(toRaw(row)) : initial())
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(row, {
      title: row ? '编辑应急演练' : '新增应急演练',
      onConfirm: submit,
      onReset: () => Object.assign(form, row ? structuredClone(toRaw(row)) : initial())
    })
  }
  defineExpose({ handleOpen })
</script>
