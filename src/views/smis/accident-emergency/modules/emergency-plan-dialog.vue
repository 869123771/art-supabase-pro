<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle
      >预案正文和签批文件复用系统附件库，台账管理版本、适用范围和有效期。</template
    >
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
    <SmisAttachmentEvidence v-model="form.attachmentRefs" title="预案文件" />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import SmisAttachmentEvidence from '@/views/smis/components/smis-attachment-evidence.vue'
  import { fetchSmisUserOptions, saveEmergencyPlan } from '@/api/smis'

  defineOptions({ name: 'SmisEmergencyPlanDialog' })
  type Plan = Api.Smis.AccidentEmergency.EmergencyPlanRecord
  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<Plan>>()
  const formRef = ref<FormExpose>()
  const userOptions = ref<Array<{ label: string; value: string }>>([])
  const initial = (): Plan => ({
    ownerUserId: null,
    planNo: '',
    planName: '',
    planType: 'comprehensive',
    responseLevel: 'enterprise',
    versionNo: 1,
    applicableScope: '',
    contentSummary: '',
    effectiveFrom: null,
    effectiveTo: null,
    status: 'draft',
    attachmentRefs: [],
    remark: ''
  })
  const form = reactive<Plan>(initial())
  const items = computed<FormItem[]>(() => [
    { label: '预案编号', key: 'planNo', type: 'input', props: { maxlength: 40 } },
    { label: '预案名称', key: 'planName', type: 'input', props: { maxlength: 120 } },
    {
      label: '预案类型',
      key: 'planType',
      type: 'select',
      props: {
        options: [
          { label: '综合预案', value: 'comprehensive' },
          { label: '专项预案', value: 'special' },
          { label: '现场处置方案', value: 'onsite' }
        ]
      }
    },
    {
      label: '响应层级',
      key: 'responseLevel',
      type: 'select',
      props: {
        options: [
          { label: '企业级', value: 'enterprise' },
          { label: '部门级', value: 'department' },
          { label: '现场级', value: 'site' }
        ]
      }
    },
    { label: '版本号', key: 'versionNo', type: 'number', props: { min: 1, precision: 0 } },
    {
      label: '责任人',
      key: 'ownerUserId',
      type: 'select',
      props: {
        options: userOptions.value,
        filterable: true,
        clearable: true
      }
    },
    {
      label: '生效日期',
      key: 'effectiveFrom',
      type: 'date',
      props: {
        type: 'date',
        valueFormat: 'YYYY-MM-DD',
        class: '!w-full'
      }
    },
    {
      label: '失效日期',
      key: 'effectiveTo',
      type: 'date',
      props: {
        type: 'date',
        valueFormat: 'YYYY-MM-DD',
        class: '!w-full'
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        options: [
          { label: '草稿', value: 'draft' },
          { label: '生效中', value: 'active' },
          { label: '已停用', value: 'retired' }
        ]
      }
    },
    {
      label: '适用范围',
      key: 'applicableScope',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 2,
        maxlength: 1000
      }
    },
    {
      label: '内容摘要',
      key: 'contentSummary',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 2000,
        showWordLimit: true
      }
    }
  ])
  const rules: FormRules<Plan> = {
    planNo: [{ required: true, message: '请输入预案编号', trigger: 'blur' }],
    planName: [{ required: true, message: '请输入预案名称', trigger: 'blur' }]
  }
  const submit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      await saveEmergencyPlan(structuredClone(toRaw(form)))
      emit('success')
      return true
    } catch {
      return false
    }
  }
  const handleOpen = async (row?: Plan): Promise<void> => {
    const users = await fetchSmisUserOptions()
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
      title: row ? '编辑应急预案' : '新增应急预案',
      onConfirm: submit,
      onReset: () => Object.assign(form, row ? structuredClone(toRaw(row)) : initial())
    })
  }
  defineExpose({ handleOpen })
</script>
