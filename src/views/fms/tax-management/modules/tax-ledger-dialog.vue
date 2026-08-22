<template>
  <ArtDialog ref="dialogRef" size="md"
    ><template #subtitle
      >税率由业务单据或财务人员录入，系统仅校验金额并汇总，不内置固定税率。</template
    ><ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="12"
      :gutter="18"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
  /></ArtDialog>
</template>
<script setup lang="ts">
  import dayjs from 'dayjs'
  import { storeToRefs } from 'pinia'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { saveTaxLedgerLine } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'
  import { canEditField } from '@/utils/field-permission'
  defineOptions({ name: 'FinanceTaxLedgerDialog' })
  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const periodId = ref('')
  const form = reactive<Api.Fms.SaveTaxLedgerLinePayload>({
    sourceType: 'manual',
    sourceNo: null,
    occurredOn: dayjs().format('YYYY-MM-DD'),
    direction: 'output',
    taxableAmount: 0,
    taxRate: null,
    taxAmount: 0,
    isDeductible: true,
    remark: null
  })
  const rules: FormRules = {
    sourceType: [{ required: true, message: '请输入来源类型', trigger: 'blur' }],
    occurredOn: [{ required: true, message: '请选择发生日期', trigger: 'change' }],
    direction: [{ required: true, message: '请选择方向', trigger: 'change' }],
    taxAmount: [{ required: true, message: '请输入税额', trigger: 'change' }]
  }
  const items = computed<FormItem[]>(() => [
    {
      label: '来源类型',
      key: 'sourceType',
      type: 'input',
      props: { maxlength: 60, placeholder: 'invoice / manual' }
    },
    { label: '来源单号', key: 'sourceNo', type: 'input', props: { maxlength: 120 } },
    {
      label: '发生日期',
      key: 'occurredOn',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '税额方向',
      key: 'direction',
      type: 'select',
      props: { options: getDictMap.value.fmsTaxLedgerDirection ?? [] }
    },
    {
      label: '计税金额',
      key: 'taxableAmount',
      type: 'number',
      props: { min: 0, precision: 2, class: '!w-full' }
    },
    {
      label: '税率',
      key: 'taxRate',
      type: 'number',
      props: { min: 0, precision: 6, step: 0.01, class: '!w-full' }
    },
    {
      label: '税额',
      key: 'taxAmount',
      type: 'number',
      props: { min: 0, precision: 2, class: '!w-full' }
    },
    { label: '允许抵扣', key: 'isDeductible', type: 'switch' },
    { label: '备注', key: 'remark', type: 'input', span: 24, props: { type: 'textarea', rows: 3 } }
  ])
  async function submit() {
    try {
      await formRef.value?.validate()
      await saveTaxLedgerLine(periodId.value, {
        ...form,
        sourceType: form.sourceType.trim(),
        sourceNo: form.sourceNo?.trim() || null
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen(period: Api.Fms.TaxPeriodRecord, line?: Api.Fms.TaxLedgerLineRecord) {
    const access = line?.fieldAccess ?? period.fieldAccess
    if (!canEditField(access, 'taxSources') || !canEditField(access, 'taxAmounts')) {
      ElMessage.warning('你没有该税务期间来源与税额字段的编辑权限')
      return
    }
    periodId.value = period.id
    Object.assign(form, {
      id: line?.id,
      sourceType: line?.sourceType || 'manual',
      sourceNo: line?.sourceNo || null,
      occurredOn: line?.occurredOn || dayjs().format('YYYY-MM-DD'),
      direction: line?.direction || 'output',
      taxableAmount: toFiniteNumber(line?.taxableAmount),
      taxRate: toNullableFiniteNumber(line?.taxRate),
      taxAmount: toFiniteNumber(line?.taxAmount),
      isDeductible: line?.isDeductible ?? true,
      remark: line?.remark || null
    })
    await dialogRef.value?.handleOpen(undefined, {
      title: line ? '编辑税务明细' : '新增税务明细',
      confirmText: '保存明细',
      onConfirm: submit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }
  function toFiniteNumber(value: Api.Tms.BasicData.SensitiveNumber | undefined): number {
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue : 0
  }
  function toNullableFiniteNumber(
    value: Api.Tms.BasicData.SensitiveNumber | undefined | null
  ): number | null {
    if (value === null || value === undefined || value === '') return null
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue : null
  }
  defineExpose({ handleOpen })
</script>
