<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle> 每次创建都会生成新的评估版本；只有草稿版本可以修改评估信息。 </template>

    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="24"
      label-width="104px"
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
  import ArtForm, {
    type FormItem,
    type FormItemOption
  } from '@/components/core/forms/art-form/index.vue'
  import { createRiskAssessment, editRiskAssessment, fetchSmisUserOptions } from '@/api/smis'

  defineOptions({ name: 'SmisRiskAssessmentDialog' })

  type RiskAssessment = Api.Smis.RiskControl.RiskAssessmentRecord

  interface OpenData {
    riskPointId: string
    row?: RiskAssessment
  }

  interface DialogFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [assessmentId?: string] }>()
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<DialogFormExpose>()
  const userOptions = ref<FormItemOption[]>([])

  const createInitialForm = (riskPointId = ''): RiskAssessment => ({
    id: undefined,
    riskPointId,
    assessorUserId: null,
    reviewerUserId: null,
    versionNo: 1,
    assessmentMethod: 'LEC',
    status: 'draft',
    assessmentDate: dayjs().format('YYYY-MM-DD'),
    assessmentSummary: ''
  })

  const form = reactive<RiskAssessment>(createInitialForm())

  const formItems = computed<FormItem[]>(() => [
    {
      label: '评估日期',
      key: 'assessmentDate',
      type: 'date',
      props: {
        type: 'date',
        valueFormat: 'YYYY-MM-DD',
        placeholder: '请选择评估日期',
        class: '!w-full'
      }
    },
    {
      label: '评估负责人',
      key: 'assessorUserId',
      type: 'select',
      hidden: !form.id,
      options: userOptions.value,
      props: { clearable: true, filterable: true, placeholder: '请选择评估负责人' }
    },
    {
      label: '评估说明',
      key: 'assessmentSummary',
      type: 'input',
      props: {
        type: 'textarea',
        rows: 5,
        maxlength: 1000,
        showWordLimit: true,
        placeholder: '说明评估范围、参与人员或本版本调整原因'
      }
    }
  ])

  const formRules: FormRules<RiskAssessment> = {
    assessmentDate: [{ required: true, message: '请选择评估日期', trigger: 'change' }],
    assessmentSummary: [{ max: 1000, message: '评估说明不能超过 1000 个字符' }]
  }

  const replaceForm = (next: RiskAssessment): void => {
    Object.assign(form, createInitialForm(), next)
  }

  const loadUsers = async (): Promise<void> => {
    const result = await fetchSmisUserOptions()
    userOptions.value = (result.data ?? []).map((item) => ({
      label: item.nickName || item.userName || item.userEmail,
      value: item.id!
    }))
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      const summary = form.assessmentSummary?.trim() || null
      if (form.id) {
        await editRiskAssessment({
          ...structuredClone(toRaw(form)),
          assessmentSummary: summary
        })
        emit('success', form.id)
      } else {
        const result = await createRiskAssessment(form.riskPointId, form.assessmentDate, summary)
        emit('success', result.data?.id)
      }
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async ({ riskPointId, row }: OpenData): Promise<void> => {
    replaceForm(
      row
        ? { ...createInitialForm(riskPointId), ...structuredClone(toRaw(row)), riskPointId }
        : createInitialForm(riskPointId)
    )
    await dialogRef.value?.handleOpen(
      { riskPointId, row },
      {
        title: row ? `编辑评估 · V${row.versionNo}` : '创建评估版本',
        loading: true,
        onOpen: async (_data, api) => {
          try {
            await loadUsers()
            await nextTick()
            formRef.value?.clearValidate()
          } finally {
            api.setLoading(false)
          }
        },
        onConfirm: handleSubmit,
        onReset: () => replaceForm(createInitialForm(riskPointId))
      }
    )
  }

  defineExpose({ handleOpen })
</script>
