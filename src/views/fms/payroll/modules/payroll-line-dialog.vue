<template>
  <ArtDialog ref="dialogRef" size="md"
    ><template #subtitle>金额构成按员工快照保存，不依赖后续人事档案变更。</template
    ><ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="12"
      :gutter="18"
      label-width="100px"
      :show-reset="false"
      :show-submit="false"
  /></ArtDialog>
</template>
<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchPayrollEmployeeOptions, savePayrollLine } from '@/api/fms'
  import { canEditField } from '@/utils/field-permission'
  defineOptions({ name: 'FinancePayrollLineDialog' })
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const runId = ref('')
  const employeeOptions = ref<Array<{ label: string; value: string }>>([])
  const form = reactive({
    employeeId: '',
    grossAmount: 0,
    deductionAmount: 0,
    netAmount: 0,
    employerCostAmount: 0,
    remark: null as string | null
  })
  const rules: FormRules = {
    employeeId: [{ required: true, message: '请选择员工', trigger: 'change' }],
    grossAmount: [{ required: true, message: '请输入应发金额', trigger: 'change' }]
  }
  const items = computed<FormItem[]>(() => [
    {
      label: '员工',
      key: 'employeeId',
      type: 'select',
      span: 24,
      props: {
        options: employeeOptions.value,
        filterable: true,
        disabled: Boolean(currentLine.value)
      }
    },
    {
      label: '应发金额',
      key: 'grossAmount',
      type: 'number',
      props: { min: 0, precision: 2, class: '!w-full' }
    },
    {
      label: '扣款金额',
      key: 'deductionAmount',
      type: 'number',
      props: { min: 0, precision: 2, class: '!w-full' }
    },
    {
      label: '企业成本',
      key: 'employerCostAmount',
      type: 'number',
      props: { min: 0, precision: 2, class: '!w-full' }
    },
    {
      label: '实发金额',
      key: 'netAmount',
      type: 'input',
      props: {
        disabled: true
      }
    },
    { label: '备注', key: 'remark', type: 'input', span: 24, props: { type: 'textarea', rows: 3 } }
  ])
  watch(
    () => [form.grossAmount, form.deductionAmount] as const,
    ([grossAmount, deductionAmount]) => {
      form.netAmount = Math.max(grossAmount - deductionAmount, 0)
    },
    { immediate: true }
  )
  const currentLine = ref<Api.Fms.PayrollLineRecord>()
  async function submit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (form.deductionAmount > form.grossAmount) {
        ElMessage.warning('扣款金额不能超过应发金额')
        return false
      }
      await savePayrollLine(runId.value, {
        employeeId: form.employeeId,
        earningItems: { gross: form.grossAmount },
        deductionItems: { deduction: form.deductionAmount },
        employerCostItems: { employerCost: form.employerCostAmount },
        grossAmount: form.grossAmount,
        deductionAmount: form.deductionAmount,
        employerCostAmount: form.employerCostAmount,
        remark: form.remark
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen(
    run: Api.Fms.PayrollRunRecord,
    line?: Api.Fms.PayrollLineRecord
  ): Promise<void> {
    const access = line?.fieldAccess ?? run.fieldAccess
    if (!canEditField(access, 'employeeIdentity') || !canEditField(access, 'salaryAmounts')) {
      ElMessage.warning('你没有该薪资批次员工与金额字段的编辑权限')
      return
    }
    runId.value = run.id
    currentLine.value = line
    const { data } = await fetchPayrollEmployeeOptions(run.id)
    employeeOptions.value = (data ?? []).map((item) => ({
      label: `${item.employeeName}（${item.employeeNo}）`,
      value: item.id
    }))
    Object.assign(form, {
      employeeId: line?.employeeId || '',
      grossAmount: toFiniteNumber(line?.grossAmount),
      deductionAmount: toFiniteNumber(line?.deductionAmount),
      employerCostAmount: toFiniteNumber(line?.employerCostAmount),
      remark: line?.remark || null
    })
    await dialogRef.value?.handleOpen(undefined, {
      title: line ? `编辑薪资 · ${line.employeeNameSnapshot}` : '新增员工薪资',
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
  defineExpose({ handleOpen })
</script>
