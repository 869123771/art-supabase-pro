<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      调拨仅支持同账套、同币种账户；执行时转出账户扣减调拨金额与手续费，转入账户增加调拨金额。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :span="12"
      :gutter="20"
      label-width="108px"
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
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchAccountSetOptions, fetchFundAccountOptions, saveFundTransfer } from '@/api/fms'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FinanceFundTransferDialog' })

  type FormData = Api.Fms.SaveFundTransferPayload
  type Transfer = Api.Fms.FundTransferRecord

  const emit = defineEmits<{ success: [type: 'add' | 'edit'] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetId = ref('')
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const accountOptions = ref<Api.Fms.FundAccountOption[]>([])

  const createInitialForm = (): FormData => ({
    id: undefined,
    version: undefined,
    sourceAccountId: '',
    targetAccountId: '',
    transferDate: dayjs().format('YYYY-MM-DD'),
    amount: 0,
    feeAmount: 0,
    purpose: '',
    bankReference: null
  })

  const form = reactive<{ data: FormData; rules: FormRules<FormData> }>({
    data: createInitialForm(),
    rules: {
      sourceAccountId: [{ required: true, message: '请选择转出账户', trigger: 'change' }],
      targetAccountId: [{ required: true, message: '请选择转入账户', trigger: 'change' }],
      transferDate: [{ required: true, message: '请选择调拨日期', trigger: 'change' }],
      amount: [
        { required: true, message: '请输入调拨金额', trigger: 'change' },
        {
          validator: (_rule, value, callback) =>
            Number(value) > 0 ? callback() : callback(new Error('调拨金额必须大于 0')),
          trigger: 'change'
        }
      ],
      feeAmount: [
        {
          validator: (_rule, value, callback) =>
            Number(value) >= 0 ? callback() : callback(new Error('手续费不能为负数')),
          trigger: 'change'
        }
      ],
      purpose: [{ required: true, message: '请填写调拨用途', trigger: 'blur' }]
    }
  })

  const sourceOption = computed(() =>
    accountOptions.value.find((item) => item.value === form.data.sourceAccountId)
  )
  const targetOptions = computed(() =>
    accountOptions.value.filter(
      (item) =>
        item.value !== form.data.sourceAccountId &&
        (!sourceOption.value || item.currencyId === sourceOption.value.currencyId)
    )
  )
  const sourceOptions = computed(() =>
    accountOptions.value.filter((item) => item.value !== form.data.targetAccountId)
  )

  const formItems = computed<FormItem[]>(() => [
    {
      label: '所属账套',
      key: '__accountSetId',
      type: 'select',
      props: {
        modelValue: accountSetId.value,
        options: accountSetOptions.value,
        filterable: true,
        disabled: Boolean(form.data.id),
        placeholder: '先选择核算账套',
        onChange: (value: string) => void handleAccountSetChange(value)
      }
    },
    {
      label: '调拨日期',
      key: 'transferDate',
      type: 'date',
      props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
    },
    {
      label: '转出账户',
      key: 'sourceAccountId',
      type: 'select',
      span: 24,
      props: {
        options: sourceOptions.value,
        filterable: true,
        disabled: !accountSetId.value,
        placeholder: '选择承担资金流出的账户'
      }
    },
    {
      label: '可用余额',
      key: '__availableBalance',
      type: 'input',
      props: {
        modelValue: sourceOption.value
          ? formatCurrencyValue(
              sourceOption.value.availableBalance,
              sourceOption.value.currencyCode
            )
          : '--',
        disabled: true
      }
    },
    {
      label: '转入账户',
      key: 'targetAccountId',
      type: 'select',
      props: {
        options: targetOptions.value,
        filterable: true,
        disabled: !form.data.sourceAccountId,
        placeholder: '选择同币种目标账户'
      }
    },
    {
      label: '调拨金额',
      key: 'amount',
      type: 'number',
      props: { min: 0.01, precision: 2, step: 100, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '银行手续费',
      key: 'feeAmount',
      type: 'number',
      props: { min: 0, precision: 2, step: 1, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '银行参考号',
      key: 'bankReference',
      type: 'input',
      props: { maxlength: 120, placeholder: '选填，便于银行自动对账' }
    },
    {
      label: '调拨用途',
      key: 'purpose',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 300, showWordLimit: true }
    }
  ])

  async function handleAccountSetChange(value: string): Promise<void> {
    accountSetId.value = value
    form.data.sourceAccountId = ''
    form.data.targetAccountId = ''
    if (!value) {
      accountOptions.value = []
      return
    }
    const { data } = await fetchFundAccountOptions({ accountSetId: value, status: 'active' })
    accountOptions.value = data ?? []
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (
        sourceOption.value &&
        form.data.amount + form.data.feeAmount > sourceOption.value.availableBalance
      ) {
        throw new Error('转出账户可用余额不足')
      }
      await saveFundTransfer({
        ...form.data,
        purpose: form.data.purpose.trim(),
        bankReference: form.data.bankReference?.trim() || null
      })
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch (error) {
      if (error instanceof Error && error.message === '转出账户可用余额不足') {
        ElMessage.warning(error.message)
      }
      return false
    }
  }

  async function handleOpen(row?: Transfer): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    Object.assign(
      form.data,
      createInitialForm(),
      row && {
        id: row.id,
        version: row.version,
        sourceAccountId: row.sourceAccountId,
        targetAccountId: row.targetAccountId,
        transferDate: row.transferDate,
        amount: row.amount,
        feeAmount: row.feeAmount,
        purpose: row.purpose,
        bankReference: row.bankReference ?? null
      }
    )
    accountSetId.value = row?.accountSetId ?? ''
    if (accountSetId.value) {
      const { data: accounts } = await fetchFundAccountOptions({
        accountSetId: accountSetId.value,
        status: 'active'
      })
      accountOptions.value = accounts ?? []
    } else {
      accountOptions.value = []
    }
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑资金调拨 · ${row.transferNo}` : '新建资金调拨',
      confirmText: row ? '保存修改' : '创建草稿',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false, destroyOnClose: true }
    })
  }

  defineExpose({ handleOpen })
</script>
