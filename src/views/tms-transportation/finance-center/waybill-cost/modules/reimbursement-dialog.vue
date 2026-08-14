<template>
  <ArtDialog ref="dialogRef" size="xl">
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      :span="isCompact ? 24 : 12"
      :gutter="20"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    >
      <template #basisUrls>
        <ArtUploadImage
          v-model="form.data.basisUrls"
          title="补充报销依据"
          :size="82"
          :limit="5"
          multiple
        />
      </template>
    </ArtForm>

    <section class="reimbursement-dialog__items">
      <div class="reimbursement-dialog__items-head">
        <ArtSectionTitle :show-line="false">待报销费用明细</ArtSectionTitle>
        <strong>{{ money(totalAmount) }}</strong>
      </div>
      <ArtTable
        :data="state.expenses"
        :columns="columns"
        :pagination="false"
        :show-table-header="false"
        table-layout="fixed"
        max-height="280px"
        border
      />
    </section>
  </ArtDialog>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import { uniq } from 'lodash-es'
  import { useMediaQuery } from '@vueuse/core'
  import type { ComputedRef } from 'vue'
  import { ElMessage, type FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtUploadImage from '@/components/core/forms/art-upload-image/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { createExpenseReimbursement } from '@/api/tms'
  import { useUserStore } from '@/store/modules/user'
  import { formatCurrencyValue } from '@/utils/ui'
  import { useDocumentNumberRule } from '@/hooks/core/useDocumentNumberRule'
  import {
    cloneReimbursementExpenses,
    validateReimbursementSelection
  } from './reimbursement-selection'

  defineOptions({ name: 'TmsWaybillExpenseReimbursementDialog' })

  type Expense = Api.Tms.Finance.WaybillCostRecord

  interface ReimbursementForm {
    reimbursementNo: string
    payeeName: string
    payeeBank: string
    payeeAccount: string
    plannedPaymentDate: string
    paymentMethod: Api.Tms.Finance.CashPaymentMethod
    basisUrls: string[]
    remark: string
  }

  interface FormGroup {
    data: ReimbursementForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<ReimbursementForm>
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const isCompact = useMediaQuery('(max-width: 767px)')
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<{ expenses: Expense[] }>>()
  const formRef = ref<FormExpose>()
  const state = reactive<{ expenses: Expense[] }>({ expenses: [] })
  const reimbursementNumber = useDocumentNumberRule('tms.expense_reimbursement')

  const createInitialForm = (): ReimbursementForm => ({
    reimbursementNo: '',
    payeeName: '',
    payeeBank: '',
    payeeAccount: '',
    plannedPaymentDate: dayjs().format('YYYY-MM-DD'),
    paymentMethod: 'bank_transfer',
    basisUrls: [],
    remark: ''
  })

  const form = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      reimbursementNo: [
        {
          validator: (_rule, value, callback) =>
            reimbursementNumber.manualRequired(false) && !String(value || '').trim()
              ? callback(new Error('请输入费用报销单号'))
              : callback(),
          trigger: 'blur'
        }
      ],
      payeeName: [{ required: true, message: '请填写实际收款人', trigger: 'blur' }],
      plannedPaymentDate: [{ required: true, message: '请选择计划付款日期', trigger: 'change' }],
      paymentMethod: [{ required: true, message: '请选择付款方式', trigger: 'change' }]
    },
    items: computed<FormItem[]>(() => [
      { label: '报销收款', key: 'payeeSection', type: 'divider', span: 24 },
      {
        label: '报销单号',
        key: 'reimbursementNo',
        type: 'input',
        props: {
          maxlength: 50,
          ...reimbursementNumber.inputProps(false, '请输入费用报销单号')
        },
        description: reimbursementNumber.description.value
      },
      {
        label: '收款人',
        key: 'payeeName',
        type: 'input',
        props: { maxlength: 200, placeholder: '司机、员工或费用垫付人' }
      },
      {
        label: '计划付款日',
        key: 'plannedPaymentDate',
        type: 'date',
        props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
      },
      {
        label: '付款方式',
        key: 'paymentMethod',
        type: 'select',
        props: { options: getDictMap.value.tmsCashPaymentMethod ?? [] }
      },
      {
        label: '开户银行',
        key: 'payeeBank',
        type: 'input',
        props: { maxlength: 200, placeholder: '非转账可不填' }
      },
      {
        label: '收款账号',
        key: 'payeeAccount',
        type: 'input',
        span: 24,
        props: { maxlength: 200, placeholder: '银行卡号或收款账户，可选' }
      },
      {
        label: '报销说明',
        key: 'remark',
        type: 'textarea',
        span: 24,
        props: {
          rows: 3,
          maxlength: 500,
          showWordLimit: true,
          placeholder: '说明报销用途、收款安排或需财务关注的事项'
        }
      },
      { label: '报销依据', key: 'basisSection', type: 'divider', span: 24 },
      { label: '补充附件', key: 'basisUrls', type: 'input', span: 24 }
    ])
  })

  const totalAmount = computed(() =>
    state.expenses.reduce((sum, item) => sum + Number(item.amount || 0), 0)
  )
  const columns: ColumnOption<Expense>[] = [
    { prop: 'costNo', label: '费用单号', width: 190 },
    { prop: 'waybillNoSnapshot', label: '运单号', width: 180 },
    { prop: 'plateNoSnapshot', label: '车牌号', width: 115 },
    {
      prop: 'expenseItem.itemName',
      label: '费用项目',
      width: 130,
      formatter: (row) => row.expenseItem?.itemName || '--'
    },
    { prop: 'occurredOn', label: '发生日期', width: 120 },
    {
      prop: 'amount',
      label: '报销金额',
      width: 130,
      align: 'right',
      formatter: (row) => money(row.amount)
    }
  ]

  function money(value: number): string {
    return formatCurrencyValue(value)
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    try {
      await createExpenseReimbursement({
        reimbursementNo: form.data.reimbursementNo.trim() || null,
        costIds: state.expenses.flatMap((item) => (item.id ? [item.id] : [])),
        payeeName: form.data.payeeName.trim(),
        payeeBank: form.data.payeeBank.trim() || null,
        payeeAccount: form.data.payeeAccount.trim() || null,
        plannedPaymentDate: form.data.plannedPaymentDate,
        paymentMethod: form.data.paymentMethod,
        basisUrls: [...form.data.basisUrls],
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
    state.expenses = []
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleOpen(expenses: Expense[]): Promise<void> {
    const validation = validateReimbursementSelection(expenses)
    if (!validation.valid) {
      ElMessage.warning(validation.message)
      return
    }

    await Promise.all([resetForm(), reimbursementNumber.loadRule()])
    state.expenses = cloneReimbursementExpenses(expenses)
    const suggestedPayee =
      expenses.find((item) => item.payeeName)?.payeeName ||
      expenses.find((item) => item.driverNameSnapshot)?.driverNameSnapshot ||
      ''
    form.data.payeeName = suggestedPayee ?? ''
    form.data.basisUrls = uniq(expenses.flatMap((item) => item.attachments ?? [])).slice(0, 5)
    await dialogRef.value?.handleOpen(
      { expenses },
      {
        title: `转费用报销 · ${expenses.length} 笔`,
        subtitle: '报销审批通过后由出纳登记付款，付款完成即逐笔核销运单费用',
        confirmText: '生成报销单',
        contentMaxHeight: '78vh',
        onConfirm: handleSubmit,
        onReset: () => void resetForm(),
        dialogProps: { appendToBody: true, closeOnClickModal: false }
      }
    )
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .reimbursement-dialog {
    &__items {
      margin-top: var(--art-space-4);
    }

    &__items-head {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      justify-content: space-between;
      margin-bottom: var(--art-space-3);

      > strong {
        font-size: 18px;
        color: var(--el-color-primary);
      }
    }
  }
</style>
