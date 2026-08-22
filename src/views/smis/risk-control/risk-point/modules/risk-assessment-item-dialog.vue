<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      按 L（可能性）× E（暴露频次）× C（后果严重度）计算 D 值，等级由数据库统一判定。
    </template>

    <ArtForm
      ref="formRef"
      v-model="form"
      :items="formItems"
      :rules="formRules"
      :span="8"
      :gutter="20"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    />

    <div class="smis-lec-preview art-card-xs" aria-live="polite">
      <div>
        <span>计算过程</span>
        <strong>{{ form.likelihood }} × {{ form.exposure }} × {{ form.consequence }}</strong>
      </div>
      <div>
        <span>风险 D 值</span>
        <strong>{{ riskScore }}</strong>
      </div>
      <div>
        <span>预判等级</span>
        <ArtDictDisplay dict-code="smisRiskLevel" :value="riskLevel" display="tag" />
      </div>
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import { storeToRefs } from 'pinia'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtForm, {
    type FormItem,
    type FormItemOption
  } from '@/components/core/forms/art-form/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import { addRiskAssessmentItem, editRiskAssessmentItem } from '@/api/smis'

  defineOptions({ name: 'SmisRiskAssessmentItemDialog' })

  type HazardSource = Api.Smis.RiskControl.HazardSourceRecord
  type RiskAssessmentItem = Api.Smis.RiskControl.RiskAssessmentItemRecord

  interface OpenData {
    assessmentId: string
    hazards: HazardSource[]
    row?: RiskAssessmentItem
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
  const hazardOptions = ref<FormItemOption[]>([])

  const createInitialForm = (assessmentId = ''): RiskAssessmentItem => ({
    id: undefined,
    assessmentId,
    hazardSourceId: '',
    likelihood: 1,
    exposure: 1,
    consequence: 1,
    evaluationNote: ''
  })

  const form = reactive<RiskAssessmentItem>(createInitialForm())

  const toNumericOptions = (code: string): FormItemOption[] =>
    ((getDictMap.value?.[code] ?? []) as Array<{ label: string; value: string }>).map((item) => ({
      label: item.label,
      value: Number(item.value)
    }))

  const formItems = computed<FormItem[]>(() => [
    {
      label: '危险源',
      key: 'hazardSourceId',
      type: 'select',
      span: 24,
      options: hazardOptions.value,
      props: { filterable: true, placeholder: '请选择本次需要评估的危险源' }
    },
    {
      label: '可能性 L',
      key: 'likelihood',
      type: 'select',
      options: toNumericOptions('smisLecLikelihood'),
      props: { placeholder: '选择 L 值' }
    },
    {
      label: '暴露频次 E',
      key: 'exposure',
      type: 'select',
      options: toNumericOptions('smisLecExposure'),
      props: { placeholder: '选择 E 值' }
    },
    {
      label: '后果 C',
      key: 'consequence',
      type: 'select',
      options: toNumericOptions('smisLecConsequence'),
      props: { placeholder: '选择 C 值' }
    },
    {
      label: '评估说明',
      key: 'evaluationNote',
      type: 'input',
      span: 24,
      props: {
        type: 'textarea',
        rows: 4,
        maxlength: 1000,
        showWordLimit: true,
        placeholder: '记录分值依据、现场证据或需要补充的说明'
      }
    }
  ])

  const formRules: FormRules<RiskAssessmentItem> = {
    hazardSourceId: [{ required: true, message: '请选择危险源', trigger: 'change' }],
    likelihood: [{ required: true, message: '请选择可能性 L 值', trigger: 'change' }],
    exposure: [{ required: true, message: '请选择暴露频次 E 值', trigger: 'change' }],
    consequence: [{ required: true, message: '请选择后果 C 值', trigger: 'change' }],
    evaluationNote: [{ max: 1000, message: '评估说明不能超过 1000 个字符' }]
  }

  const riskScore = computed(() =>
    Number((form.likelihood * form.exposure * form.consequence).toFixed(2))
  )
  const riskLevel = computed<Api.Smis.RiskControl.RiskLevel>(() => {
    if (riskScore.value >= 320) return 'critical'
    if (riskScore.value >= 160) return 'major'
    if (riskScore.value >= 70) return 'general'
    return 'low'
  })

  const replaceForm = (next: RiskAssessmentItem): void => {
    Object.assign(form, createInitialForm(), next)
  }

  const handleSubmit = async (): Promise<boolean> => {
    try {
      await formRef.value?.validate()
      const payload: RiskAssessmentItem = {
        ...structuredClone(toRaw(form)),
        evaluationNote: form.evaluationNote?.trim() || null
      }
      if (payload.id) await editRiskAssessmentItem(payload)
      else await addRiskAssessmentItem(payload)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  const handleOpen = async ({ assessmentId, hazards, row }: OpenData): Promise<void> => {
    hazardOptions.value = hazards.map((item) => ({
      label: `${item.hazardName}（${item.sourceNo}）`,
      value: item.id!
    }))
    replaceForm(
      row
        ? { ...createInitialForm(assessmentId), ...structuredClone(toRaw(row)), assessmentId }
        : createInitialForm(assessmentId)
    )
    await nextTick()
    formRef.value?.clearValidate()
    await dialogRef.value?.handleOpen(
      { assessmentId, hazards, row },
      {
        title: row ? '编辑 LEC 评估项' : '新增 LEC 评估项',
        onConfirm: handleSubmit,
        onReset: () => replaceForm(createInitialForm(assessmentId))
      }
    )
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .smis-lec-preview {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: var(--art-space-4);
    padding: var(--art-space-4);
    margin-top: var(--art-space-3);

    > div {
      display: grid;
      gap: var(--art-space-1);
      min-width: 0;
    }

    span {
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    strong {
      font-size: 18px;
      font-variant-numeric: tabular-nums;
      color: var(--el-text-color-primary);
    }

    @media (width <= 680px) {
      grid-template-columns: 1fr;
    }
  }
</style>
