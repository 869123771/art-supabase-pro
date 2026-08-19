<template>
  <ArtDialog ref="dialogRef" size="sm">
    <ElAlert
      class="fund-execution-dialog__notice"
      :type="context.direction === 'inflow' ? 'success' : 'warning'"
      :closable="false"
      show-icon
      :title="noticeTitle"
      description="确认后会同时登记资金日记账并触发对应会计入账事件。"
    />
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      label-width="96px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { ComputedRef } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchFundAccountOptions } from '@/api/fms'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FinanceFundExecutionDialog' })

  export interface FundExecutionPayload {
    fundAccountId: string
    actionDate: string
    referenceNo?: string
  }

  export interface FundExecutionOptions {
    accountSetId: string
    amount: number
    direction: 'inflow' | 'outflow'
    title: string
    subtitle: string
    confirmText: string
    accountLabel?: string
  }

  interface ExecutionForm {
    fundAccountId: string
    actionDate: string
    referenceNo: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose<FundExecutionOptions>>()
  const formRef = ref<FormExpose>()
  const submitter = shallowRef<(payload: FundExecutionPayload) => Promise<void>>()
  const accountOptions = ref<Api.Fms.FundAccountOption[]>([])
  const context = reactive<FundExecutionOptions>({
    accountSetId: '',
    amount: 0,
    direction: 'outflow',
    title: '',
    subtitle: '',
    confirmText: '确认'
  })
  const createInitialForm = (): ExecutionForm => ({
    fundAccountId: '',
    actionDate: dayjs().format('YYYY-MM-DD'),
    referenceNo: ''
  })
  const form = reactive<{
    data: ExecutionForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<ExecutionForm>
  }>({
    data: createInitialForm(),
    rules: {
      fundAccountId: [{ required: true, message: '请选择实际资金账户', trigger: 'change' }],
      actionDate: [{ required: true, message: '请选择实际发生日期', trigger: 'change' }]
    },
    items: computed<FormItem[]>(() => [
      {
        label: '发生日期',
        key: 'actionDate',
        type: 'date',
        span: 24,
        props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
      },
      {
        label: context.accountLabel || (context.direction === 'inflow' ? '收款账户' : '付款账户'),
        key: 'fundAccountId',
        type: 'select',
        span: 24,
        props: {
          options: accountOptions.value,
          filterable: true,
          placeholder: context.direction === 'inflow' ? '选择实际入账账户' : '选择实际扣款账户'
        },
        description: accountOptions.value.length
          ? '仅显示当前账套、本位币且状态正常的资金账户'
          : '当前账套没有可用资金账户，请先前往资金账户维护'
      },
      {
        label: '银行流水号',
        key: 'referenceNo',
        type: 'input',
        span: 24,
        props: { clearable: true, maxlength: 120, placeholder: '选填，用于对账和追溯' }
      }
    ])
  })

  const noticeTitle = computed(
    () =>
      `${context.direction === 'inflow' ? '资金流入' : '资金流出'} · ${formatCurrencyValue(context.amount)}`
  )

  async function reset(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    accountOptions.value = []
    submitter.value = undefined
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    if (!submitter.value) return false
    await submitter.value({
      fundAccountId: form.data.fundAccountId,
      actionDate: form.data.actionDate,
      referenceNo: form.data.referenceNo.trim() || undefined
    })
    emit('success')
    return true
  }

  async function handleOpen(
    options: FundExecutionOptions,
    onSubmit: (payload: FundExecutionPayload) => Promise<void>
  ): Promise<void> {
    await reset()
    Object.assign(context, options)
    submitter.value = onSubmit
    const { data } = await fetchFundAccountOptions({
      accountSetId: options.accountSetId,
      status: 'active',
      baseCurrencyOnly: true
    })
    accountOptions.value = data ?? []
    await dialogRef.value?.handleOpen(options, {
      title: options.title,
      subtitle: options.subtitle,
      confirmText: options.confirmText,
      contentMaxHeight: '64vh',
      onConfirm: handleSubmit,
      onReset: () => void reset(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .fund-execution-dialog__notice {
    margin-bottom: var(--art-space-4);
  }
</style>
