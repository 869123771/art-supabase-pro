<template>
  <ArtDialog ref="dialogRef" size="md"
    ><template #subtitle
      >同一会计期间、同一税种仅保留一份台账；税率和调整金额不在前端硬编码。</template
    ><ArtForm
      ref="formRef"
      v-model="form"
      :items="items"
      :rules="rules"
      :span="12"
      :gutter="18"
      label-width="112px"
      :show-reset="false"
      :show-submit="false"
  /></ArtDialog>
</template>
<script setup lang="ts">
  import { storeToRefs } from 'pinia'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import {
    fetchAccountingPeriodList,
    fetchAccountSetOptions,
    fetchTaxPeriodDetail,
    saveTaxPeriod
  } from '@/api/fms'
  import { canEditField, canViewField } from '@/utils/field-permission'
  import { formatCurrencyValue } from '@/utils/ui'
  import { useUserStore } from '@/store/modules/user'
  import { ACCOUNTING_SELECT_EMPTY_TEXT } from '../../modules/accounting-select-text'
  defineOptions({ name: 'FinanceTaxPeriodDialog' })
  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const periodOptions = ref<Array<{ label: string; value: string }>>([])
  const currentRecord = shallowRef<Api.Fms.TaxPeriodRecord>()
  const fieldAccess = ref<Api.Fms.TaxFieldAccessMap>({})
  const form = reactive<Api.Fms.SaveTaxPeriodPayload & { accountSetId: string }>({
    accountSetId: '',
    accountingPeriodId: '',
    taxType: 'vat',
    transferableInputAmount: 0,
    adjustmentAmount: 0,
    remark: null
  })
  const rules: FormRules = {
    accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
    accountingPeriodId: [{ required: true, message: '请选择期间', trigger: 'change' }],
    taxType: [{ required: true, message: '请选择税种', trigger: 'change' }]
  }
  const isEditing = computed(() => Boolean(form.id))
  const canViewAmounts = computed(
    () => !isEditing.value || canViewField(fieldAccess.value, 'taxAmounts')
  )
  const canEditAmounts = computed(
    () => !isEditing.value || canEditField(fieldAccess.value, 'taxAmounts')
  )
  const items = computed<FormItem[]>(() => {
    const result: FormItem[] = [
      {
        label: '所属账套',
        key: 'accountSetId',
        type: 'select',
        span: 24,
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
        span: 24,
        props: {
          options: periodOptions.value,
          disabled: Boolean(form.id) || !form.accountSetId,
          noDataText: form.accountSetId
            ? ACCOUNTING_SELECT_EMPTY_TEXT.openAccountingPeriod
            : ACCOUNTING_SELECT_EMPTY_TEXT.chooseAccountSet
        }
      },
      {
        label: '税种',
        key: 'taxType',
        type: 'select',
        props: { options: getDictMap.value.fmsTaxType ?? [], disabled: Boolean(form.id) }
      }
    ]
    if (canViewAmounts.value) {
      result.push(
        ...(canEditAmounts.value
          ? [
              {
                label: '上期留抵',
                key: 'transferableInputAmount',
                type: 'number' as const,
                props: { min: 0, precision: 2, class: '!w-full' }
              },
              {
                label: '调整金额',
                key: 'adjustmentAmount',
                type: 'number' as const,
                props: { precision: 2, class: '!w-full' }
              }
            ]
          : [
              {
                label: '上期留抵',
                key: '__transferableInputAmountDisplay',
                type: 'input' as const,
                props: {
                  modelValue: formatProtectedAmount(currentRecord.value?.transferableInputAmount),
                  disabled: true
                }
              },
              {
                label: '调整金额',
                key: '__adjustmentAmountDisplay',
                type: 'input' as const,
                props: {
                  modelValue: formatProtectedAmount(currentRecord.value?.adjustmentAmount),
                  disabled: true
                }
              }
            ])
      )
    }
    result.push({
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 300 }
    })
    return result
  })
  async function loadPeriods() {
    periodOptions.value = []
    if (!form.accountSetId) return
    const { data } = await fetchAccountingPeriodList(form.accountSetId)
    periodOptions.value = (data ?? [])
      .filter((i) => i.status === 'open')
      .map((i) => ({ label: `${i.fiscalYear} 年第 ${i.periodNo} 期`, value: i.id }))
    if (!form.id) form.accountingPeriodId = periodOptions.value[0]?.value ?? ''
  }
  watch(() => form.accountSetId, loadPeriods)
  async function submit() {
    try {
      await formRef.value?.validate()
      await saveTaxPeriod({
        id: form.id,
        accountingPeriodId: form.accountingPeriodId,
        taxType: form.taxType,
        ...(canEditAmounts.value
          ? {
              transferableInputAmount: Number(form.transferableInputAmount ?? 0),
              adjustmentAmount: Number(form.adjustmentAmount ?? 0)
            }
          : {}),
        remark: form.remark
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }
  async function handleOpen(row?: Api.Fms.TaxPeriodRecord) {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    const record = row ? ((await fetchTaxPeriodDetail(row.id)).data ?? row) : undefined
    currentRecord.value = record
    fieldAccess.value = record?.fieldAccess ?? {}
    Object.assign(form, {
      id: record?.id,
      accountSetId: record?.accountSetId || accountSetOptions.value[0]?.value || '',
      accountingPeriodId: record?.accountingPeriodId || '',
      taxType: record?.taxType || 'vat',
      transferableInputAmount: canEditField(record?.fieldAccess, 'taxAmounts')
        ? toFiniteNumber(record?.transferableInputAmount)
        : 0,
      adjustmentAmount: canEditField(record?.fieldAccess, 'taxAmounts')
        ? toFiniteNumber(record?.adjustmentAmount)
        : 0,
      remark: record?.remark || null
    })
    await loadPeriods()
    await dialogRef.value?.handleOpen(undefined, {
      title: record ? '编辑税务期间' : '新建税务期间',
      confirmText: record ? '保存修改' : '创建台账',
      onConfirm: submit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }
  function toFiniteNumber(value: Api.Tms.BasicData.SensitiveNumber | undefined): number {
    const numberValue = Number(value)
    return Number.isFinite(numberValue) ? numberValue : 0
  }
  function formatProtectedAmount(value: Api.Tms.BasicData.SensitiveNumber | undefined): string {
    if (value === null || value === undefined || value === '') return '--'
    return formatCurrencyValue(value)
  }
  defineExpose({ handleOpen })
</script>
