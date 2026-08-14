<template>
  <ArtDialog ref="dialogRef" size="md">
    <ElAlert class="payment-dialog__summary" type="success" :closable="false" show-icon>
      <template #title>
        <strong>{{ state.reimbursement?.reimbursementNo }}</strong>
        · {{ state.reimbursement?.payeeName }} · {{ money(state.reimbursement?.totalAmount) }}
      </template>
    </ElAlert>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="24"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #voucherUrls>
        <ArtUploadImage
          v-model="form.data.voucherUrls"
          title="付款凭证"
          :size="82"
          :limit="5"
          multiple
        />
      </template>
    </ArtForm>
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { ComputedRef } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import { executeExpenseReimbursement } from '@/api/tms'
  import { formatCurrencyValue } from '@/utils/ui'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'

  defineOptions({ name: 'TmsWaybillExpensePaymentDialog' })

  type Reimbursement = Api.Tms.Finance.ExpenseReimbursementRecord

  interface PaymentForm {
    paymentNo: string
    paymentDate: string
    bankReference: string
    voucherUrls: string[]
    remark: string
  }

  interface FormGroup {
    data: PaymentForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<PaymentForm>
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<Reimbursement>>()
  const formRef = ref<FormExpose>()
  const state = reactive<{ reimbursement?: Reimbursement }>({ reimbursement: undefined })
  const paymentNumber = useDocumentNumberRule('tms.expense_payment')
  const createInitialForm = (): PaymentForm => ({
    paymentNo: '',
    paymentDate: dayjs().format('YYYY-MM-DD'),
    bankReference: '',
    voucherUrls: [],
    remark: ''
  })
  const form = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      paymentNo: [
        {
          validator: (_rule, value, callback) =>
            paymentNumber.manualRequired(false) && !String(value || '').trim()
              ? callback(new Error('请输入费用付款单号'))
              : callback(),
          trigger: 'blur'
        }
      ],
      paymentDate: [{ required: true, message: '请选择实际付款日期', trigger: 'change' }],
      bankReference: [
        {
          validator: (_rule, value, callback) =>
            state.reimbursement?.paymentMethod !== 'bank_transfer' || String(value || '').trim()
              ? callback()
              : callback(new Error('银行转账必须填写银行流水号')),
          trigger: 'blur'
        }
      ]
    },
    items: computed<FormItem[]>(() => [
      {
        label: '付款单号',
        key: 'paymentNo',
        type: 'input',
        props: { maxlength: 50, ...paymentNumber.inputProps(false, '请输入费用付款单号') },
        description: paymentNumber.description.value
      },
      {
        label: '付款日期',
        key: 'paymentDate',
        type: 'date',
        props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
      },
      {
        label: '银行流水号',
        key: 'bankReference',
        type: 'input',
        props: {
          maxlength: 160,
          placeholder: state.reimbursement?.paymentMethod === 'bank_transfer' ? '必填' : '可选'
        }
      },
      {
        label: '付款备注',
        key: 'remark',
        type: 'textarea',
        props: { rows: 3, maxlength: 500, showWordLimit: true }
      },
      { label: '付款凭证', key: 'voucherUrls', type: 'input' }
    ])
  })

  function money(value?: number | null): string {
    return formatCurrencyValue(Number(value ?? 0))
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    if (!state.reimbursement) return false
    try {
      await executeExpenseReimbursement({
        paymentNo: form.data.paymentNo.trim() || null,
        reimbursementId: state.reimbursement.id,
        paymentDate: form.data.paymentDate,
        bankReference: form.data.bankReference.trim() || null,
        voucherUrls: [...form.data.voucherUrls],
        remark: form.data.remark.trim() || null
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function resetForm(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    state.reimbursement = undefined
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleOpen(row: Reimbursement): Promise<void> {
    await Promise.all([resetForm(), paymentNumber.loadRule()])
    state.reimbursement = structuredClone(toRaw(row))
    await dialogRef.value?.handleOpen(row, {
      title: '出纳登记付款',
      subtitle: '确认付款后不可撤回，系统将自动核销报销单内的每一笔在途费用',
      confirmText: '确认付款并核销',
      contentMaxHeight: '70vh',
      onConfirm: handleSubmit,
      onReset: () => void resetForm(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .payment-dialog {
    &__summary {
      margin-bottom: var(--art-space-4);
    }
  }
</style>
