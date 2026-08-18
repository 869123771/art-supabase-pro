<template>
  <ArtDialog ref="dialogRef" size="md"
    ><template #subtitle
      >执行后期间进入“关账中”，系统生成九项检查结果；阻断项修复后可重新检查。</template
    ><ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="24"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
  /></ArtDialog>
</template>
<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import {
    fetchAccountingPeriodList,
    fetchAccountSetOptions,
    runPeriodCloseChecks
  } from '@/api/fms'
  import { ACCOUNTING_SELECT_EMPTY_TEXT } from '../../modules/accounting-select-text'
  defineOptions({ name: 'FinancePeriodCloseStartDialog' })
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const periodOptions = ref<Array<{ label: string; value: string }>>([])
  const form = reactive({ accountSetId: '', periodId: '' })
  const rules: FormRules = {
    accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
    periodId: [{ required: true, message: '请选择会计期间', trigger: 'change' }]
  }
  const items = computed<FormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      props: {
        options: accountSetOptions.value,
        filterable: true,
        noDataText: ACCOUNTING_SELECT_EMPTY_TEXT.accountSet
      }
    },
    {
      label: '会计期间',
      key: 'periodId',
      type: 'select',
      props: {
        options: periodOptions.value,
        placeholder: '选择开放或关账中期间',
        disabled: !form.accountSetId,
        noDataText: form.accountSetId
          ? ACCOUNTING_SELECT_EMPTY_TEXT.openAccountingPeriod
          : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
      }
    }
  ])
  async function loadPeriods() {
    periodOptions.value = []
    if (!form.accountSetId) return
    const { data } = await fetchAccountingPeriodList(form.accountSetId)
    periodOptions.value = (data ?? [])
      .filter((i) => ['open', 'closing'].includes(i.status))
      .map((i) => ({
        label: `${i.fiscalYear} 年第 ${i.periodNo} 期 · ${i.startDate} 至 ${i.endDate}`,
        value: i.id
      }))
    form.periodId = periodOptions.value[0]?.value ?? ''
  }
  watch(() => form.accountSetId, loadPeriods)
  async function submit() {
    try {
      await formRef.value?.validate()
      await runPeriodCloseChecks(form.periodId)
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen() {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    form.accountSetId = accountSetOptions.value[0]?.value ?? ''
    await loadPeriods()
    await dialogRef.value?.handleOpen(undefined, {
      title: '执行月末关账检查',
      confirmText: '开始检查',
      onConfirm: submit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }
  defineExpose({ handleOpen })
</script>
