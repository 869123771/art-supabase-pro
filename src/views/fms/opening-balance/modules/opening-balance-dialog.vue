<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      期初余额仅录入末级启用科目；方向、外币、数量和辅助核算要求由科目档案自动控制。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :validate-on-rule-change="false"
      :span="12"
      :gutter="20"
      label-width="118px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import { ElMessage, type FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { saveOpeningBalance } from '@/api/fms'

  defineOptions({ name: 'FinanceOpeningBalanceDialog' })

  interface OpeningBalanceForm {
    id?: string
    tenantId: string
    accountSetId: string
    fiscalYear: number
    subjectId: string
    currencyId?: string | null
    auxiliaryValues: Record<string, string>
    openingAmount: number
    yearToDateDebit: number
    yearToDateCredit: number
    openingQuantity: number
    originalCurrencyAmount: number
  }

  interface DialogContext {
    subjects: Api.Fms.SubjectRecord[]
    currencies: Api.Fms.CurrencyRecord[]
    auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[]
    auxiliaryItems: Api.Fms.AuxiliaryItemRecord[]
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const context = reactive<DialogContext>({
    subjects: [],
    currencies: [],
    auxiliaryTypes: [],
    auxiliaryItems: []
  })

  const createInitialForm = (): OpeningBalanceForm => ({
    id: undefined,
    tenantId: '',
    accountSetId: '',
    fiscalYear: new Date().getFullYear(),
    subjectId: '',
    currencyId: null,
    auxiliaryValues: {},
    openingAmount: 0,
    yearToDateDebit: 0,
    yearToDateCredit: 0,
    openingQuantity: 0,
    originalCurrencyAmount: 0
  })
  const form = reactive<{ data: OpeningBalanceForm; rules: FormRules<OpeningBalanceForm> }>({
    data: createInitialForm(),
    rules: {
      subjectId: [{ required: true, message: '请选择末级科目', trigger: 'change' }],
      openingAmount: [
        { required: true, message: '请输入期初余额', trigger: 'blur' },
        { type: 'number', min: 0, message: '期初余额不能小于 0', trigger: 'blur' }
      ],
      yearToDateDebit: [{ type: 'number', min: 0, message: '借方累计不能小于 0' }],
      yearToDateCredit: [{ type: 'number', min: 0, message: '贷方累计不能小于 0' }],
      openingQuantity: [{ type: 'number', min: 0, message: '期初数量不能小于 0' }],
      originalCurrencyAmount: [{ type: 'number', min: 0, message: '原币金额不能小于 0' }]
    }
  })

  const selectedSubject = computed(() =>
    context.subjects.find((item) => item.id === form.data.subjectId)
  )
  const subjectOptions = computed(() =>
    context.subjects.map((item) => ({
      label: `${item.subjectCode} ${item.subjectName}`,
      value: item.id
    }))
  )
  const currencyOptions = computed(() =>
    context.currencies
      .filter((item) => item.isEnabled && !item.isBase)
      .map((item) => ({ label: `${item.currencyName}（${item.currencyCode}）`, value: item.id }))
  )
  const subjectAuxiliaryConfigs = computed(() => selectedSubject.value?.auxiliaryConfigs ?? [])

  const formItems = computed<FormItem[]>(() => [
    { label: '科目余额', key: 'balanceSection', type: 'divider', span: 24 },
    {
      label: '会计科目',
      key: 'subjectId',
      type: 'select',
      span: 24,
      props: {
        disabled: Boolean(form.data.id),
        filterable: true,
        options: subjectOptions.value,
        placeholder: '搜索科目编码或名称',
        onChange: handleSubjectChange
      }
    },
    {
      label: selectedSubject.value?.balanceDirection === 'credit' ? '期初贷方余额' : '期初借方余额',
      key: 'openingAmount',
      type: 'number',
      span: 12,
      props: { min: 0, precision: 2, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '本年借方累计',
      key: 'yearToDateDebit',
      type: 'number',
      span: 12,
      props: { min: 0, precision: 2, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '本年贷方累计',
      key: 'yearToDateCredit',
      type: 'number',
      span: 12,
      props: { min: 0, precision: 2, controlsPosition: 'right', class: '!w-full' }
    },
    ...(selectedSubject.value?.allowQuantity
      ? [
          {
            label: `期初数量${selectedSubject.value.unitName ? `（${selectedSubject.value.unitName}）` : ''}`,
            key: 'openingQuantity',
            type: 'number' as const,
            span: 12,
            props: { min: 0, precision: 4, controlsPosition: 'right', class: '!w-full' }
          }
        ]
      : []),
    ...(selectedSubject.value?.allowForeignCurrency
      ? [
          { label: '外币核算', key: 'currencySection', type: 'divider' as const, span: 24 },
          {
            label: '核算外币',
            key: 'currencyId',
            type: 'select' as const,
            span: 12,
            props: {
              clearable: true,
              filterable: true,
              options: currencyOptions.value,
              placeholder: '请选择外币'
            }
          },
          {
            label: '原币期初金额',
            key: 'originalCurrencyAmount',
            type: 'number' as const,
            span: 12,
            props: { min: 0, precision: 2, controlsPosition: 'right', class: '!w-full' }
          }
        ]
      : []),
    ...(subjectAuxiliaryConfigs.value.length
      ? [
          { label: '辅助核算', key: 'auxiliarySection', type: 'divider' as const, span: 24 },
          ...subjectAuxiliaryConfigs.value.map((config) => ({
            label: config.auxiliaryType?.typeName ?? '核算维度',
            key: `auxiliaryValues.${config.auxiliaryTypeId}`,
            type: 'select' as const,
            span: 12,
            required: config.isRequired,
            help: config.isRequired ? '该维度为科目必录项' : undefined,
            props: {
              clearable: !config.isRequired,
              filterable: true,
              options: context.auxiliaryItems
                .filter((item) => item.auxiliaryTypeId === config.auxiliaryTypeId && item.isEnabled)
                .map((item) => ({ label: `${item.itemCode} ${item.itemName}`, value: item.id }))
            }
          }))
        ]
      : [])
  ])

  function handleSubjectChange(): void {
    form.data.currencyId = null
    form.data.auxiliaryValues = {}
    form.data.openingQuantity = 0
    form.data.originalCurrencyAmount = 0
  }

  function validateBusinessRules(): boolean {
    const subject = selectedSubject.value
    if (!subject) return false
    if (subject.allowForeignCurrency && !form.data.currencyId) {
      ElMessage.warning('该科目启用了外币核算，请选择核算外币')
      return false
    }
    const missing = subjectAuxiliaryConfigs.value.find(
      (config) => config.isRequired && !form.data.auxiliaryValues[config.auxiliaryTypeId]
    )
    if (missing) {
      ElMessage.warning(`请选择必录维度“${missing.auxiliaryType?.typeName ?? '辅助核算'}”`)
      return false
    }
    return true
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (!validateBusinessRules() || !selectedSubject.value) return false
      const isDebit = selectedSubject.value.balanceDirection === 'debit'
      await saveOpeningBalance({
        id: form.data.id,
        tenantId: form.data.tenantId,
        accountSetId: form.data.accountSetId,
        fiscalYear: form.data.fiscalYear,
        subjectId: form.data.subjectId,
        currencyId: selectedSubject.value.allowForeignCurrency ? form.data.currencyId : null,
        auxiliaryValues: Object.fromEntries(
          Object.entries(form.data.auxiliaryValues).filter(([, value]) => Boolean(value))
        ),
        openingDebit: isDebit ? Number(form.data.openingAmount) : 0,
        openingCredit: isDebit ? 0 : Number(form.data.openingAmount),
        yearToDateDebit: Number(form.data.yearToDateDebit),
        yearToDateCredit: Number(form.data.yearToDateCredit),
        openingQuantity: selectedSubject.value.allowQuantity
          ? Number(form.data.openingQuantity)
          : 0,
        originalCurrencyAmount: selectedSubject.value.allowForeignCurrency
          ? Number(form.data.originalCurrencyAmount)
          : 0
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(
    accountSet: Api.Fms.AccountSetOption,
    fiscalYear: number,
    dialogContext: DialogContext,
    row?: Api.Fms.OpeningBalanceRecord
  ): Promise<void> {
    Object.assign(context, dialogContext)
    Object.assign(form.data, createInitialForm(), {
      id: row?.id,
      tenantId: accountSet.tenantId,
      accountSetId: accountSet.value,
      fiscalYear,
      subjectId: row?.subjectId ?? '',
      currencyId: row?.currencyId ?? null,
      auxiliaryValues: { ...(row?.auxiliaryValues ?? {}) },
      openingAmount: Number(row ? row.openingDebit || row.openingCredit : 0),
      yearToDateDebit: Number(row?.yearToDateDebit ?? 0),
      yearToDateCredit: Number(row?.yearToDateCredit ?? 0),
      openingQuantity: Number(row?.openingQuantity ?? 0),
      originalCurrencyAmount: Number(row?.originalCurrencyAmount ?? 0)
    })
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑期初余额 · ${row.subject?.subjectCode ?? ''}` : '录入期初余额',
      confirmText: row ? '保存修改' : '保存余额',
      contentMaxHeight: '70vh',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
