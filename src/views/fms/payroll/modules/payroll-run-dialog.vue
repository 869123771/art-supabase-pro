<template>
  <ArtDialog ref="dialogRef" size="md"
    ><template #subtitle>每个会计期间仅保留一个薪资批次；创建后在明细工作台维护员工金额。</template
    ><ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="24"
      label-width="106px"
      :show-reset="false"
      :show-submit="false"
  /></ArtDialog>
</template>
<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchAccountingPeriodList, fetchAccountSetOptions, savePayrollRun } from '@/api/fms'
  import { ACCOUNTING_SELECT_EMPTY_TEXT } from '../../modules/accounting-select-text'
  defineOptions({ name: 'FinancePayrollRunDialog' })
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const periodOptions = ref<Array<{ label: string; value: string }>>([])
  const form = reactive<Api.Fms.SavePayrollRunPayload & { accountSetId: string }>({
    accountSetId: '',
    accountingPeriodId: '',
    remark: null
  })
  const rules: FormRules = {
    accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
    accountingPeriodId: [{ required: true, message: '请选择开放期间', trigger: 'change' }]
  }
  const items = computed<FormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      props: {
        options: accountSetOptions.value,
        filterable: true,
        disabled: Boolean(form.id),
        noDataText: ACCOUNTING_SELECT_EMPTY_TEXT.accountSet
      }
    },
    {
      label: '会计期间',
      key: 'accountingPeriodId',
      type: 'select',
      props: {
        options: periodOptions.value,
        disabled: Boolean(form.id) || !form.accountSetId,
        placeholder: '选择开放期间',
        noDataText: form.accountSetId
          ? ACCOUNTING_SELECT_EMPTY_TEXT.openAccountingPeriod
          : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
      }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      props: { type: 'textarea', rows: 3, maxlength: 300 }
    }
  ])
  async function loadPeriods(): Promise<void> {
    periodOptions.value = []
    if (!form.accountSetId) return
    const { data } = await fetchAccountingPeriodList(form.accountSetId)
    periodOptions.value = (data ?? [])
      .filter((item) => item.status === 'open')
      .map((item) => ({ label: `${item.fiscalYear} 年第 ${item.periodNo} 期`, value: item.id }))
    if (!form.id) form.accountingPeriodId = periodOptions.value[0]?.value ?? ''
  }
  watch(() => form.accountSetId, loadPeriods)
  async function submit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      await savePayrollRun({
        id: form.id,
        accountingPeriodId: form.accountingPeriodId,
        remark: form.remark
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen(row?: Api.Fms.PayrollRunRecord): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    Object.assign(form, {
      id: row?.id,
      accountSetId: row?.accountSetId || accountSetOptions.value[0]?.value || '',
      accountingPeriodId: row?.accountingPeriodId || '',
      remark: row?.remark || null
    })
    await loadPeriods()
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑薪资批次 · ${row.runNo}` : '新建薪资批次',
      confirmText: row ? '保存修改' : '创建批次',
      onConfirm: submit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }
  defineExpose({ handleOpen })
</script>
