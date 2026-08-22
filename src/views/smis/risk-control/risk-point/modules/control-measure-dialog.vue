<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      管控措施必须落实到类型、责任人、验证标准和目标日期，评估提交前每项至少配置一条。
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
  import { storeToRefs } from 'pinia'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, {
    type FormItem,
    type FormItemOption
  } from '@/components/core/forms/art-form/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import { addControlMeasure, editControlMeasure, fetchSmisUserOptions } from '@/api/smis'

  defineOptions({ name: 'SmisControlMeasureDialog' })

  type ControlMeasure = Api.Smis.RiskControl.ControlMeasureRecord

  interface OpenData {
    assessmentItemId: string
    row?: ControlMeasure
  }

  interface DialogFormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const userStore = useUserStore()
  const { getDictMap } = storeToRefs(userStore)
  const dialogRef = ref<ArtDialogExpose<OpenData>>()
  const formRef = ref<DialogFormExpose>()
  const userOptions = ref<FormItemOption[]>([])

  const createInitialForm = (assessmentItemId = ''): ControlMeasure => ({
    id: undefined,
    assessmentItemId,
    responsibleUserId: null,
    measureType: 'engineering',
    measureContent: '',
    verificationCriteria: '',
    targetDate: null,
    status: 'active'
  })

  const form = reactive<ControlMeasure>(createInitialForm())

  const formItems = computed<FormItem[]>(() => [
    {
      label: '措施类型',
      key: 'measureType',
      type: 'select',
      options: getDictMap.value?.smisControlMeasureType ?? [],
      props: { placeholder: '请选择措施类型' }
    },
    {
      label: '责任人',
      key: 'responsibleUserId',
      type: 'select',
      options: userOptions.value,
      props: { clearable: true, filterable: true, placeholder: '请选择责任人' }
    },
    {
      label: '目标日期',
      key: 'targetDate',
      type: 'date',
      props: {
        type: 'date',
        valueFormat: 'YYYY-MM-DD',
        clearable: true,
        placeholder: '请选择目标日期',
        class: '!w-full'
      }
    },
    {
      label: '措施状态',
      key: 'status',
      type: 'select',
      options: getDictMap.value?.smisControlMeasureStatus ?? [],
      props: { placeholder: '请选择措施状态' }
    },
    {
      label: '措施内容',
      key: 'measureContent',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 1000,
        showWordLimit: true,
        placeholder: '写明要采取的具体工程、管理、培训、防护或应急措施'
      }
    },
    {
      label: '验证标准',
      key: 'verificationCriteria',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 3,
        maxlength: 500,
        showWordLimit: true,
        placeholder: '写明可检查、可判定的达标标准'
      }
    }
  ])

  const formRules: FormRules<ControlMeasure> = {
    measureType: [{ required: true, message: '请选择措施类型', trigger: 'change' }],
    measureContent: [
      { required: true, message: '请输入措施内容', trigger: 'blur' },
      { min: 4, max: 1000, message: '措施内容应为 4-1000 个字符', trigger: 'blur' }
    ],
    verificationCriteria: [{ max: 500, message: '验证标准不能超过 500 个字符' }],
    status: [{ required: true, message: '请选择措施状态', trigger: 'change' }]
  }

  const replaceForm = (next: ControlMeasure): void => {
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
      const payload: ControlMeasure = {
        ...structuredClone(toRaw(form)),
        responsibleUserId: form.responsibleUserId || null,
        targetDate: form.targetDate || null,
        measureContent: form.measureContent.trim(),
        verificationCriteria: form.verificationCriteria?.trim() || null
      }
      if (payload.id) await editControlMeasure(payload)
      else await addControlMeasure(payload)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async ({ assessmentItemId, row }: OpenData): Promise<void> => {
    replaceForm(
      row
        ? {
            ...createInitialForm(assessmentItemId),
            ...structuredClone(toRaw(row)),
            assessmentItemId
          }
        : createInitialForm(assessmentItemId)
    )
    await dialogRef.value?.handleOpen(
      { assessmentItemId, row },
      {
        title: row ? '编辑管控措施' : '新增管控措施',
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
        onReset: () => replaceForm(createInitialForm(assessmentItemId))
      }
    )
  }

  defineExpose({ handleOpen })
</script>
