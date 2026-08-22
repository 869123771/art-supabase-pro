<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle> 危险源是风险评估的辨识对象；已进入评估的内容会保存历史快照。 </template>

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
  import { addHazardSource, editHazardSource } from '@/api/smis'

  defineOptions({ name: 'SmisHazardSourceDialog' })

  type HazardSource = Api.Smis.RiskControl.HazardSourceRecord

  interface OpenData {
    riskPointId: string
    row?: HazardSource
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

  const createInitialForm = (riskPointId = ''): HazardSource => ({
    id: undefined,
    riskPointId,
    sourceNo: '',
    hazardName: '',
    hazardDescription: '',
    accidentType: '',
    possibleConsequence: '',
    existingControls: '',
    enabled: true,
    sort: 0,
    remark: ''
  })

  const form = reactive<HazardSource>(createInitialForm())
  const booleanOptions = computed<FormItemOption[]>(() =>
    (getDictMap.value?.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const formItems = computed<FormItem[]>(() => [
    { label: '辨识信息', key: 'identitySection', type: 'divider', span: 24 },
    {
      label: '危险源编号',
      key: 'sourceNo',
      type: 'input',
      props: { maxlength: 32, placeholder: '如 HZ-WH-001' }
    },
    {
      label: '危险源名称',
      key: 'hazardName',
      type: 'input',
      props: { maxlength: 100, placeholder: '用现场可识别的对象或行为命名' }
    },
    {
      label: '事故类型',
      key: 'accidentType',
      type: 'input',
      props: { maxlength: 50, placeholder: '如车辆伤害、火灾、高处坠落' }
    },
    {
      label: '是否启用',
      key: 'enabled',
      type: 'radioGroup',
      options: booleanOptions.value
    },
    {
      label: '危险源描述',
      key: 'hazardDescription',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    },
    {
      label: '可能后果',
      key: 'possibleConsequence',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    },
    {
      label: '既有措施',
      key: 'existingControls',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 1000, showWordLimit: true }
    },
    { label: '管理信息', key: 'managementSection', type: 'divider', span: 24 },
    {
      label: '排序',
      key: 'sort',
      type: 'number',
      props: { min: 0, max: 9999, step: 1, stepStrictly: true, class: '!w-full' }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 2, maxlength: 500, showWordLimit: true }
    }
  ])

  const formRules: FormRules<HazardSource> = {
    sourceNo: [
      { required: true, message: '请输入危险源编号', trigger: 'blur' },
      {
        pattern: /^[A-Za-z0-9][A-Za-z0-9_-]{1,31}$/,
        message: '请输入 2-32 位字母、数字、下划线或短横线',
        trigger: 'blur'
      }
    ],
    hazardName: [
      { required: true, message: '请输入危险源名称', trigger: 'blur' },
      { min: 2, max: 100, message: '危险源名称应为 2-100 个字符', trigger: 'blur' }
    ],
    hazardDescription: [{ max: 500, message: '危险源描述不能超过 500 个字符' }],
    possibleConsequence: [{ max: 500, message: '可能后果不能超过 500 个字符' }],
    existingControls: [{ max: 1000, message: '既有措施不能超过 1000 个字符' }],
    remark: [{ max: 500, message: '备注不能超过 500 个字符' }]
  }

  const replaceForm = (next: HazardSource): void => {
    Object.assign(form, createInitialForm(), next)
  }

  const emptyToNull = (value?: string | null): string | null => value?.trim() || null

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      const payload: HazardSource = {
        ...structuredClone(toRaw(form)),
        sourceNo: form.sourceNo.trim(),
        hazardName: form.hazardName.trim(),
        hazardDescription: emptyToNull(form.hazardDescription),
        accidentType: emptyToNull(form.accidentType),
        possibleConsequence: emptyToNull(form.possibleConsequence),
        existingControls: emptyToNull(form.existingControls),
        remark: emptyToNull(form.remark)
      }
      if (payload.id) await editHazardSource(payload)
      else await addHazardSource(payload)
      emit('success')
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
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(
      { riskPointId, row },
      {
        title: row ? '编辑危险源' : '新增危险源',
        onConfirm: handleSubmit,
        onReset: () => replaceForm(createInitialForm(riskPointId))
      }
    )
  }

  defineExpose({ handleOpen })
</script>
