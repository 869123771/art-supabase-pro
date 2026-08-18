<template>
  <ArtDialog ref="dialogRef" size="md">
    <template #subtitle>
      本位币由账套初始化生成且不可变更；外币启用后可维护即期、平均及期末汇率。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :span="12"
      :gutter="20"
      label-width="104px"
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
  import { saveCurrency } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceCurrencyDialog' })

  type FormData = Api.Fms.SaveCurrencyPayload

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()

  const createInitialForm = (): FormData => ({
    id: undefined,
    tenantId: '',
    accountSetId: '',
    currencyCode: '',
    currencyName: '',
    symbol: null,
    decimalPlaces: 2,
    isBase: false,
    isEnabled: true,
    sort: 100,
    remark: null
  })

  const form = reactive<{ data: FormData; rules: FormRules<FormData> }>({
    data: createInitialForm(),
    rules: {
      currencyCode: [
        { required: true, message: '请输入币种代码', trigger: 'blur' },
        { pattern: /^[A-Z]{3}$/, message: '请输入 3 位大写 ISO 币种代码', trigger: 'blur' }
      ],
      currencyName: [
        { required: true, message: '请输入币种名称', trigger: 'blur' },
        { max: 60, message: '币种名称不能超过 60 个字符', trigger: 'blur' }
      ],
      decimalPlaces: [{ required: true, message: '请输入小数位数', trigger: 'change' }]
    }
  })

  const booleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )
  const isBaseCurrency = computed(() => form.data.isBase)
  const formItems = computed<FormItem[]>(() => [
    {
      label: '币种代码',
      key: 'currencyCode',
      type: 'input',
      span: 12,
      props: {
        disabled: isBaseCurrency.value || Boolean(form.data.id),
        maxlength: 3,
        placeholder: '例如 USD',
        onInput: (value: string) => (form.data.currencyCode = value.toUpperCase())
      }
    },
    {
      label: '币种名称',
      key: 'currencyName',
      type: 'input',
      span: 12,
      props: { maxlength: 60, placeholder: '例如 美元' }
    },
    {
      label: '货币符号',
      key: 'symbol',
      type: 'input',
      span: 12,
      props: { maxlength: 12, placeholder: '例如 $' }
    },
    {
      label: '金额小数位',
      key: 'decimalPlaces',
      type: 'number',
      span: 12,
      props: { min: 0, max: 6, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '启用状态',
      key: 'isEnabled',
      type: 'radioGroup',
      span: 12,
      props: { disabled: isBaseCurrency.value, options: booleanOptions.value }
    },
    {
      label: '排序号',
      key: 'sort',
      type: 'number',
      span: 12,
      props: { min: 0, max: 9999, controlsPosition: 'right', class: '!w-full' }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      await saveCurrency({
        id: form.data.id,
        tenantId: form.data.tenantId,
        accountSetId: form.data.accountSetId,
        currencyCode: form.data.currencyCode.trim().toUpperCase(),
        currencyName: form.data.currencyName.trim(),
        symbol: form.data.symbol?.trim() || null,
        decimalPlaces: form.data.decimalPlaces,
        isBase: form.data.isBase,
        isEnabled: form.data.isBase || form.data.isEnabled,
        sort: form.data.sort,
        remark: form.data.remark?.trim() || null
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(
    accountSet: Api.Fms.AccountSetOption,
    row?: Api.Fms.CurrencyRecord
  ): Promise<void> {
    Object.assign(form.data, createInitialForm(), {
      id: row?.id,
      tenantId: accountSet.tenantId,
      accountSetId: accountSet.value,
      currencyCode: row?.currencyCode ?? '',
      currencyName: row?.currencyName ?? '',
      symbol: row?.symbol ?? null,
      decimalPlaces: row?.decimalPlaces ?? 2,
      isBase: row?.isBase ?? false,
      isEnabled: row?.isEnabled ?? true,
      sort: row?.sort ?? 100,
      remark: row?.remark ?? null
    })
    await dialogRef.value?.handleOpen(undefined, {
      title: row ? `编辑币种 · ${row.currencyCode}` : '新增核算币种',
      confirmText: row ? '保存修改' : '创建币种',
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate(),
      dialogProps: { closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>
