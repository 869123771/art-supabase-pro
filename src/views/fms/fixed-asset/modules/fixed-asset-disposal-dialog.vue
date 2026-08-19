<template>
  <ArtDialog ref="dialogRef" size="sm">
    <ElAlert
      class="fixed-asset-disposal-dialog__notice"
      :type="disposalResult.type"
      :closable="false"
      show-icon
      :title="disposalResult.title"
      :description="disposalResult.description"
    />
    <div
      v-if="form.data.amount > 0 && !accountOptions.length"
      class="fixed-asset-disposal-dialog__prerequisite"
      role="status"
    >
      <span>
        <strong>缺少可用资金账户</strong>
        <small>先登记真实银行、现金或第三方支付账户，再回来确认处置收入。</small>
      </span>
      <ElButton type="primary" link @click="goToFundAccount">前往资金账户</ElButton>
    </div>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="form.items"
      :rules="form.rules"
      label-width="104px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import dayjs from 'dayjs'
  import type { ComputedRef } from 'vue'
  import type { FormItemRule, FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { actFixedAsset, fetchFundAccountOptions } from '@/api/fms'
  import { financeRouteNames } from '@/router/business-paths'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FinanceFixedAssetDisposalDialog' })

  type Asset = Api.Fms.FixedAssetRecord

  interface DisposalForm {
    actionDate: string
    amount: number
    fundAccountId: string
    referenceNo: string
    reason: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  const emit = defineEmits<{ success: [] }>()
  const router = useRouter()
  const dialogRef = ref<ArtDialogExpose<Asset>>()
  const formRef = ref<FormExpose>()
  const currentAsset = shallowRef<Asset>()
  const accountOptions = ref<Api.Fms.FundAccountOption[]>([])
  const createInitialForm = (): DisposalForm => ({
    actionDate: dayjs().format('YYYY-MM-DD'),
    amount: 0,
    fundAccountId: '',
    referenceNo: '',
    reason: ''
  })
  const formData = reactive<DisposalForm>(createInitialForm())

  const validateFundAccount: NonNullable<FormItemRule['validator']> = (_rule, value, callback) => {
    if (Number(formData.amount || 0) > 0 && !String(value || '').trim()) {
      callback(new Error('有处置收入时必须选择实际收款账户'))
      return
    }
    callback()
  }

  const form = reactive<{
    data: DisposalForm
    items: ComputedRef<FormItem[]>
    rules: FormRules<DisposalForm>
  }>({
    data: formData,
    rules: {
      actionDate: [{ required: true, message: '请选择处置日期', trigger: 'change' }],
      amount: [{ required: true, message: '请输入处置收入', trigger: 'blur' }],
      fundAccountId: [{ validator: validateFundAccount, trigger: 'change' }],
      reason: [{ required: true, message: '请填写处置原因', trigger: 'blur' }]
    },
    items: computed<FormItem[]>(() => [
      {
        label: '处置日期',
        key: 'actionDate',
        type: 'date',
        span: 24,
        props: { valueFormat: 'YYYY-MM-DD', class: '!w-full' }
      },
      {
        label: '处置收入',
        key: 'amount',
        type: 'number',
        span: 24,
        props: { min: 0, precision: 2, step: 100, controlsPosition: 'right', class: '!w-full' },
        description: '无处置收入时填写 0；有收入时必须登记实际收款账户'
      },
      {
        label: '收款账户',
        key: 'fundAccountId',
        type: 'select',
        span: 24,
        hidden: Number(formData.amount || 0) <= 0,
        props: {
          options: accountOptions.value,
          filterable: true,
          placeholder: '选择处置收入实际到账账户'
        },
        description: accountOptions.value.length
          ? '确认后同步登记资金日记账'
          : '当前账套没有可用资金账户，请先前往资金账户维护'
      },
      {
        label: '银行流水号',
        key: 'referenceNo',
        type: 'input',
        span: 24,
        hidden: Number(formData.amount || 0) <= 0,
        props: { clearable: true, maxlength: 120, placeholder: '选填，用于银行对账和追溯' }
      },
      {
        label: '处置原因',
        key: 'reason',
        type: 'textarea',
        span: 24,
        props: {
          maxlength: 500,
          showWordLimit: true,
          autosize: { minRows: 3, maxRows: 6 },
          placeholder: '填写报废、出售、盘亏等真实处置原因'
        }
      }
    ])
  })

  const netBookValue = computed(() => {
    const asset = currentAsset.value
    if (!asset) return 0
    return Math.max(
      Number(asset.originalValue || 0) -
        Number(asset.accumulatedDepreciation || 0) -
        Number(asset.impairmentAmount || 0),
      0
    )
  })

  const disposalResult = computed(() => {
    const difference = Number(form.data.amount || 0) - netBookValue.value
    const result = difference >= 0 ? '预计处置收益' : '预计处置损失'
    return {
      type: difference >= 0 ? ('success' as const) : ('warning' as const),
      title: `账面净值 ${formatCurrencyValue(netBookValue.value)} · ${result} ${formatCurrencyValue(Math.abs(difference))}`,
      description:
        Number(form.data.amount || 0) > 0
          ? '确认后将同步生成资产处置事件、会计凭证和资金日记账。'
          : '确认后将生成资产处置事件和会计凭证，不产生资金流水。'
    }
  })

  async function reset(): Promise<void> {
    Object.assign(form.data, createInitialForm())
    accountOptions.value = []
    currentAsset.value = undefined
    await nextTick()
    formRef.value?.clearValidate()
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    const asset = currentAsset.value
    if (!asset) return false
    await actFixedAsset(asset.id, 'dispose', {
      actionDate: form.data.actionDate,
      amount: Number(form.data.amount || 0),
      fundAccountId: form.data.fundAccountId || undefined,
      referenceNo: form.data.referenceNo.trim() || undefined,
      reason: form.data.reason.trim()
    })
    emit('success')
    return true
  }

  async function handleOpen(asset: Asset): Promise<void> {
    await reset()
    currentAsset.value = asset
    const { data } = await fetchFundAccountOptions({
      accountSetId: asset.accountSetId,
      status: 'active',
      baseCurrencyOnly: true
    })
    accountOptions.value = data ?? []
    await dialogRef.value?.handleOpen(asset, {
      title: '处置固定资产',
      subtitle: `${asset.assetNo} · ${asset.assetName}`,
      confirmText: '确认处置',
      contentMaxHeight: '68vh',
      onConfirm: handleSubmit,
      onReset: () => void reset(),
      dialogProps: { appendToBody: true, closeOnClickModal: false }
    })
  }

  function goToFundAccount(): void {
    void router.push({ name: financeRouteNames.fundAccount })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .fixed-asset-disposal-dialog__notice {
    margin-bottom: var(--art-space-4);
  }

  .fixed-asset-disposal-dialog__prerequisite {
    display: flex;
    gap: var(--art-space-3);
    align-items: center;
    justify-content: space-between;
    padding: var(--art-space-3) var(--art-space-4);
    margin-bottom: var(--art-space-4);
    color: var(--el-color-warning-dark-2);
    background: var(--el-color-warning-light-9);
    border: 1px solid var(--el-color-warning-light-7);
    border-radius: var(--el-border-radius-base);

    span {
      display: grid;
      gap: 2px;
      min-width: 0;
    }

    small {
      color: var(--el-text-color-regular);
    }
  }
</style>
