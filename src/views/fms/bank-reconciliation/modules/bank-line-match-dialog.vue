<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>
      可按剩余金额进行部分匹配；同一银行流水与资金流水均可分摊到多条匹配记录。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :span="24"
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
  import { fetchFundLedgerList, matchBankStatementLine } from '@/api/fms'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FinanceBankLineMatchDialog' })

  interface FormData {
    ledgerEntryId: string
    amount: number
    remark: string
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const line = shallowRef<Api.Fms.BankStatementLineRecord>()
  const ledgerOptions = ref<Array<{ label: string; value: string; amount: number }>>([])
  const form = reactive<{ data: FormData; rules: FormRules<FormData> }>({
    data: { ledgerEntryId: '', amount: 0, remark: '' },
    rules: {
      ledgerEntryId: [{ required: true, message: '请选择资金流水', trigger: 'change' }],
      amount: [
        { required: true, message: '请输入匹配金额', trigger: 'change' },
        {
          validator: (_rule, value, callback) =>
            Number(value) > 0 && Number(value) <= Number(line.value?.remainingAmount ?? 0)
              ? callback()
              : callback(new Error('匹配金额必须大于 0 且不超过银行流水剩余金额')),
          trigger: 'change'
        }
      ]
    }
  })

  const formItems = computed<FormItem[]>(() => [
    {
      label: '银行流水',
      key: '__statementLine',
      type: 'input',
      props: {
        modelValue: line.value
          ? `${line.value.transactionDate} · ${formatCurrencyValue(line.value.amount)} · ${line.value.counterpartyName || '未知对方'}`
          : '--',
        disabled: true
      }
    },
    {
      label: '资金流水',
      key: 'ledgerEntryId',
      type: 'select',
      props: {
        options: ledgerOptions.value,
        filterable: true,
        placeholder: '选择同账户、同方向的资金流水'
      }
    },
    {
      label: '匹配金额',
      key: 'amount',
      type: 'number',
      props: {
        min: 0.01,
        max: line.value?.remainingAmount ?? 0,
        precision: 2,
        controlsPosition: 'right',
        class: '!w-full'
      }
    },
    {
      label: '匹配说明',
      key: 'remark',
      type: 'input',
      props: { type: 'textarea', rows: 3, maxlength: 300, showWordLimit: true }
    }
  ])

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      if (!line.value) return false
      await matchBankStatementLine(
        line.value.id,
        form.data.ledgerEntryId,
        form.data.amount,
        form.data.remark.trim() || null
      )
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(row: Api.Fms.BankStatementLineRecord): Promise<void> {
    line.value = row
    Object.assign(form.data, {
      ledgerEntryId: '',
      amount: row.remainingAmount,
      remark: ''
    })
    const { data } = await fetchFundLedgerList({
      fundAccountId: row.fundAccountId,
      direction: row.direction,
      entryDateRange: [
        dayjs(row.transactionDate).subtract(30, 'day').format('YYYY-MM-DD'),
        dayjs(row.transactionDate).add(30, 'day').format('YYYY-MM-DD')
      ],
      from: 0,
      to: 199
    })
    ledgerOptions.value = (data ?? []).map((item) => ({
      label: `${item.entryDate} · ${item.summary} · ${formatCurrencyValue(item.amount)}${item.sourceNo ? ` · ${item.sourceNo}` : ''}`,
      value: item.id,
      amount: item.amount
    }))
    await dialogRef.value?.handleOpen(undefined, {
      title: `手工匹配 · 第 ${row.lineNo} 行`,
      confirmText: '确认匹配',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
