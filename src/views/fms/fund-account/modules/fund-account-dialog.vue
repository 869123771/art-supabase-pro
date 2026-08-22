<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      账号仅在保存时用于生成掩码和不可逆指纹，系统不存储完整明文账号。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :span="12"
      :gutter="20"
      label-width="112px"
      :show-reset="false"
      :show-submit="false"
    />
  </ArtDialog>
</template>

<script setup lang="ts">
  import type { FormRules } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchAccountSetOptions, fetchCurrencyList, saveFundAccount } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'
  import { canEditField, canViewField } from '@/utils/field-permission'

  defineOptions({ name: 'FinanceFundAccountDialog' })

  type FormData = Omit<Api.Fms.SaveFundAccountPayload, 'openingBalance' | 'frozenBalance'> & {
    openingBalance: Api.Tms.BasicData.SensitiveNumber
    frozenBalance: Api.Tms.BasicData.SensitiveNumber
    fieldAccess?: Api.Fms.FundAccountFieldAccessMap
  }
  type Account = Api.Fms.FundAccountRecord

  const emit = defineEmits<{ success: [type: 'add' | 'edit'] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const currencyOptions = ref<Array<{ label: string; value: string }>>([])
  const canViewSensitiveField = (field: Api.Fms.FundAccountFieldKey): boolean =>
    canViewField(form.data.fieldAccess, field, form.data.id ? 'hidden' : 'edit')
  const canEditSensitiveField = (field: Api.Fms.FundAccountFieldKey): boolean =>
    canEditField(form.data.fieldAccess, field, form.data.id ? 'hidden' : 'edit')

  const createInitialForm = (): FormData => ({
    id: undefined,
    accountSetId: '',
    currencyId: '',
    accountCode: '',
    accountName: '',
    accountType: 'bank',
    bankName: null,
    bankBranch: null,
    accountNo: null,
    openingBalance: 0,
    frozenBalance: 0,
    status: 'active',
    isDefault: false,
    onlineBankingEnabled: false,
    reconciliationEnabled: true,
    balanceAsOf: null,
    remark: null
  })

  const form = reactive<{ data: FormData; rules: FormRules<FormData> }>({
    data: createInitialForm(),
    rules: {
      accountSetId: [{ required: true, message: '请选择所属账套', trigger: 'change' }],
      currencyId: [{ required: true, message: '请选择账户币种', trigger: 'change' }],
      accountCode: [
        { required: true, message: '请输入账户编码', trigger: 'blur' },
        {
          pattern: /^[A-Z0-9_-]{2,30}$/,
          message: '请输入 2-30 位大写字母、数字、下划线或连字符',
          trigger: 'blur'
        }
      ],
      accountName: [{ required: true, message: '请输入账户名称', trigger: 'blur' }],
      accountType: [{ required: true, message: '请选择账户类型', trigger: 'change' }],
      accountNo: [
        {
          validator: (_rule, value, callback) => {
            if (!form.data.id && !String(value ?? '').trim()) callback(new Error('请输入资金账号'))
            else callback()
          },
          trigger: 'blur'
        }
      ],
      bankName: [
        {
          validator: (_rule, value, callback) => {
            if (
              canEditSensitiveField('accountDetails') &&
              form.data.accountType === 'bank' &&
              !String(value ?? '').trim()
            ) {
              callback(new Error('银行账户必须填写开户银行'))
            } else callback()
          },
          trigger: 'blur'
        }
      ],
      openingBalance: [{ required: true, message: '请输入期初余额', trigger: 'change' }],
      frozenBalance: [{ required: true, message: '请输入冻结金额', trigger: 'change' }],
      balanceAsOf: [
        {
          validator: (_rule, value, callback) => {
            if (Number(form.data.openingBalance) !== 0 && !value) {
              callback(new Error('存在期初余额时必须填写余额日期'))
            } else callback()
          },
          trigger: 'change'
        }
      ]
    }
  })

  const booleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )
  const isBank = computed(() => form.data.accountType === 'bank')

  const formItems = computed<FormItem[]>(() => [
    {
      label: '所属账套',
      key: 'accountSetId',
      type: 'select',
      props: {
        options: accountSetOptions.value,
        filterable: true,
        disabled: Boolean(form.data.id),
        placeholder: '选择核算账套',
        onChange: (value: string) => void loadCurrencies(value, true)
      }
    },
    {
      label: '账户币种',
      key: 'currencyId',
      type: 'select',
      props: {
        options: currencyOptions.value,
        filterable: true,
        disabled: Boolean(form.data.id),
        placeholder: '选择币种'
      }
    },
    {
      label: '账户编码',
      key: 'accountCode',
      type: 'input',
      props: {
        maxlength: 30,
        placeholder: '例如 CMB_BASIC',
        onInput: (value: string) => (form.data.accountCode = value.toUpperCase())
      }
    },
    {
      label: '账户名称',
      key: 'accountName',
      type: 'input',
      props: { maxlength: 80, placeholder: '例如 招商银行基本户' }
    },
    {
      label: '账户类型',
      key: 'accountType',
      type: 'select',
      props: { options: getDictMap.value.fmsFundAccountType ?? [] }
    },
    {
      label: '资金账号',
      key: 'accountNo',
      type: 'input',
      hidden: !canViewSensitiveField('accountDetails'),
      props: {
        maxlength: 64,
        showPassword: canEditSensitiveField('accountDetails'),
        disabled: !canEditSensitiveField('accountDetails'),
        autocomplete: 'new-password',
        placeholder: form.data.id ? '留空表示不变' : '输入银行卡号、现金箱编号或钱包账号'
      }
    },
    {
      label: '开户银行',
      key: 'bankName',
      type: 'input',
      hidden: !canViewSensitiveField('accountDetails'),
      props: {
        disabled: !isBank.value || !canEditSensitiveField('accountDetails'),
        maxlength: 80,
        placeholder: '银行账户必填'
      }
    },
    {
      label: '开户支行',
      key: 'bankBranch',
      type: 'input',
      hidden: !canViewSensitiveField('accountDetails'),
      props: {
        disabled: !isBank.value || !canEditSensitiveField('accountDetails'),
        maxlength: 120,
        placeholder: '选填'
      }
    },
    {
      label: '期初余额',
      key: 'openingBalance',
      type: canEditSensitiveField('accountBalances') ? 'number' : 'input',
      hidden: !canViewSensitiveField('accountBalances'),
      props: canEditSensitiveField('accountBalances')
        ? { precision: 2, step: 100, controlsPosition: 'right', class: '!w-full' }
        : { disabled: true }
    },
    {
      label: '余额日期',
      key: 'balanceAsOf',
      type: canEditSensitiveField('accountBalances') ? 'date' : 'input',
      hidden: !canViewSensitiveField('accountBalances'),
      props: canEditSensitiveField('accountBalances')
        ? {
            valueFormat: 'YYYY-MM-DD',
            placeholder: '期初余额对应日期',
            class: '!w-full'
          }
        : { disabled: true }
    },
    {
      label: '冻结金额',
      key: 'frozenBalance',
      type: canEditSensitiveField('accountBalances') ? 'number' : 'input',
      hidden: !canViewSensitiveField('accountBalances'),
      props: canEditSensitiveField('accountBalances')
        ? {
            min: 0,
            precision: 2,
            step: 100,
            controlsPosition: 'right',
            class: '!w-full'
          }
        : { disabled: true }
    },
    {
      label: '账户状态',
      key: 'status',
      type: 'select',
      props: { options: getDictMap.value.fmsFundAccountStatus ?? [] }
    },
    {
      label: '默认账户',
      key: 'isDefault',
      type: 'radioGroup',
      props: { options: booleanOptions.value }
    },
    {
      label: '银企直联',
      key: 'onlineBankingEnabled',
      type: 'radioGroup',
      props: { options: booleanOptions.value, disabled: !isBank.value }
    },
    {
      label: '银行对账',
      key: 'reconciliationEnabled',
      type: 'radioGroup',
      props: { options: booleanOptions.value, disabled: form.data.accountType === 'cash' }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  async function loadCurrencies(accountSetId: string, reset = false): Promise<void> {
    if (reset) form.data.currencyId = ''
    if (!accountSetId) {
      currencyOptions.value = []
      return
    }
    const { data } = await fetchCurrencyList(accountSetId)
    currencyOptions.value = (data ?? [])
      .filter((item) => item.isEnabled)
      .map((item) => ({
        label: `${item.currencyCode} · ${item.currencyName}${item.isBase ? '（本位币）' : ''}`,
        value: item.id
      }))
    if (reset && currencyOptions.value.length === 1) {
      form.data.currencyId = currencyOptions.value[0].value
    }
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      const payload: Partial<Api.Fms.SaveFundAccountPayload> = {
        ...form.data,
        accountCode: form.data.accountCode.trim().toUpperCase(),
        accountName: form.data.accountName.trim(),
        bankName: isBank.value ? form.data.bankName?.trim() || null : null,
        bankBranch: isBank.value ? form.data.bankBranch?.trim() || null : null,
        accountNo: form.data.accountNo?.trim() || null,
        onlineBankingEnabled: isBank.value && form.data.onlineBankingEnabled,
        reconciliationEnabled: form.data.accountType !== 'cash' && form.data.reconciliationEnabled,
        remark: form.data.remark?.trim() || null,
        openingBalance: Number(form.data.openingBalance ?? 0),
        frozenBalance: Number(form.data.frozenBalance ?? 0)
      }
      delete (payload as Record<string, unknown>).fieldAccess
      if (form.data.id && !canEditSensitiveField('accountDetails')) {
        delete payload.accountNo
        delete payload.bankName
        delete payload.bankBranch
      }
      if (form.data.id && !canEditSensitiveField('accountBalances')) {
        delete payload.openingBalance
        delete payload.frozenBalance
        delete payload.balanceAsOf
      }
      await saveFundAccount(payload as Api.Fms.SaveFundAccountPayload)
      emit('success', form.data.id ? 'edit' : 'add')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(row?: Account): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    Object.assign(
      form.data,
      createInitialForm(),
      row && {
        id: row.id,
        accountSetId: row.accountSetId,
        currencyId: row.currencyId,
        accountCode: row.accountCode,
        accountName: row.accountName,
        accountType: row.accountType,
        bankName: row.bankName ?? null,
        bankBranch: row.bankBranch ?? null,
        openingBalance: row.openingBalance ?? 0,
        frozenBalance: row.frozenBalance ?? 0,
        status: row.status,
        isDefault: row.isDefault,
        onlineBankingEnabled: row.onlineBankingEnabled,
        reconciliationEnabled: row.reconciliationEnabled,
        balanceAsOf: row.balanceAsOf ?? null,
        remark: row.remark ?? null,
        fieldAccess: row.fieldAccess
      }
    )
    if (row && !canEditSensitiveField('accountDetails')) {
      form.data.accountNo = row.accountNoMasked ?? null
    }
    if (form.data.accountSetId) await loadCurrencies(form.data.accountSetId)
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑资金账户 · ${row.accountName}` : '新建资金账户',
      confirmText: row ? '保存修改' : '创建账户',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false, destroyOnClose: true }
    })
  }

  defineExpose({ handleOpen })
</script>
