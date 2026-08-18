<template>
  <ArtDialog ref="dialogRef" size="lg">
    <template #subtitle>
      账套确定法人核算边界、会计准则和启用期间；产生期初余额或凭证后，关键口径将受系统保护。
    </template>
    <ArtForm
      ref="formRef"
      v-model="form.data"
      :items="formItems"
      :rules="form.rules"
      :validate-on-rule-change="false"
      :span="12"
      :gutter="20"
      label-width="116px"
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
  import { saveAccountSet } from '@/api/fms'
  import { fetchGetEnableTenantList } from '@/api/system-manage'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceAccountSetDialog' })

  type AccountSet = Api.Fms.AccountSetRecord
  type AccountSetForm = Api.Fms.SaveAccountSetPayload

  interface FormGroup {
    data: AccountSetForm
    rules: FormRules<AccountSetForm>
  }

  const emit = defineEmits<{ success: [type: 'add' | 'edit'] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<{ row?: AccountSet }>>()
  const formRef = ref<{ validate: () => Promise<boolean>; clearValidate: () => void }>()

  const createInitialForm = (): AccountSetForm => ({
    id: undefined,
    tenantId: '',
    accountSetCode: '',
    accountSetName: '',
    legalEntityName: '',
    unifiedSocialCreditCode: null,
    accountingStandard: 'enterprise_2019',
    vatTaxpayerType: 'general',
    baseCurrencyCode: 'CNY',
    enabledOn: new Date().toISOString().slice(0, 10),
    fiscalYearStartMonth: 1,
    status: 'draft',
    isDefault: false,
    remark: null
  })

  const form = reactive<FormGroup>({
    data: createInitialForm(),
    rules: {
      tenantId: [{ required: true, message: '请选择所属租户', trigger: 'change' }],
      accountSetCode: [
        { required: true, message: '请输入账套编码', trigger: 'blur' },
        {
          pattern: /^[A-Z0-9_-]{2,30}$/,
          message: '编码仅支持 2 到 30 位大写字母、数字、下划线和中横线',
          trigger: 'blur'
        }
      ],
      accountSetName: [
        { required: true, message: '请输入账套名称', trigger: 'blur' },
        { max: 80, message: '账套名称不能超过 80 个字符', trigger: 'blur' }
      ],
      legalEntityName: [
        { required: true, message: '请输入法人主体名称', trigger: 'blur' },
        { max: 120, message: '法人主体名称不能超过 120 个字符', trigger: 'blur' }
      ],
      unifiedSocialCreditCode: [
        {
          pattern: /^[0-9A-Z]{15,20}$/,
          message: '请输入 15 到 20 位大写统一社会信用代码',
          trigger: 'blur'
        }
      ],
      accountingStandard: [{ required: true, message: '请选择会计准则', trigger: 'change' }],
      vatTaxpayerType: [{ required: true, message: '请选择纳税人类型', trigger: 'change' }],
      baseCurrencyCode: [
        { required: true, message: '请输入本位币代码', trigger: 'blur' },
        { pattern: /^[A-Z]{3}$/, message: '本位币使用三位大写代码，如 CNY', trigger: 'blur' }
      ],
      enabledOn: [{ required: true, message: '请选择启用日期', trigger: 'change' }],
      fiscalYearStartMonth: [
        { required: true, message: '请输入会计年度起始月份', trigger: 'change' },
        { type: 'number', min: 1, max: 12, message: '起始月份必须为 1 到 12' }
      ],
      remark: [{ max: 500, message: '备注不能超过 500 个字符', trigger: 'blur' }]
    }
  })

  const isEdit = computed(() => Boolean(form.data.id))
  const booleanOptions = computed(() =>
    (getDictMap.value.commonBoolean ?? []).map((item) => ({
      ...item,
      value: item.value === 'true'
    }))
  )

  const formItems = computed<FormItem[]>(() => [
    { label: '核算主体', key: 'entitySection', type: 'divider', span: 24 },
    {
      label: '所属租户',
      key: 'tenantId',
      type: 'select',
      span: 24,
      api: fetchGetEnableTenantList,
      resultField: 'data',
      labelField: 'tenantName',
      valueField: 'id',
      labelFn: (item) => `${item.tenantName}（${item.tenantCode}）`,
      props: {
        placeholder: '请选择账套所属租户',
        filterable: true,
        disabled: isEdit.value
      }
    },
    {
      label: '账套名称',
      key: 'accountSetName',
      type: 'input',
      span: 12,
      props: { maxlength: 80, placeholder: '例如：华东物流有限公司账套' }
    },
    {
      label: '账套编码',
      key: 'accountSetCode',
      type: 'input',
      span: 12,
      props: {
        maxlength: 30,
        placeholder: '例如：HDWL_2026',
        onInput: (value: string) => {
          form.data.accountSetCode = value.toUpperCase()
        }
      }
    },
    {
      label: '法人主体',
      key: 'legalEntityName',
      type: 'input',
      span: 12,
      props: { maxlength: 120, placeholder: '请输入营业执照上的企业名称' }
    },
    {
      label: '信用代码',
      key: 'unifiedSocialCreditCode',
      type: 'input',
      span: 12,
      props: {
        maxlength: 20,
        placeholder: '统一社会信用代码',
        onInput: (value: string) => {
          form.data.unifiedSocialCreditCode = value.toUpperCase() || null
        }
      }
    },
    { label: '核算政策', key: 'policySection', type: 'divider', span: 24 },
    {
      label: '会计准则',
      key: 'accountingStandard',
      type: 'select',
      span: 12,
      props: {
        options: getDictMap.value.fmsAccountingStandard ?? [],
        placeholder: '请选择会计准则'
      }
    },
    {
      label: '纳税人类型',
      key: 'vatTaxpayerType',
      type: 'select',
      span: 12,
      props: {
        options: getDictMap.value.fmsVatTaxpayerType ?? [],
        placeholder: '请选择纳税人类型'
      }
    },
    {
      label: '本位币',
      key: 'baseCurrencyCode',
      type: 'input',
      span: 12,
      help: '使用 ISO 4217 三位币种代码；已有期初余额后不可变更。',
      props: {
        maxlength: 3,
        placeholder: 'CNY',
        onInput: (value: string) => {
          form.data.baseCurrencyCode = value.toUpperCase()
        }
      }
    },
    {
      label: '默认账套',
      key: 'isDefault',
      type: 'radioGroup',
      span: 12,
      props: { options: booleanOptions.value }
    },
    { label: '启用期间', key: 'periodSection', type: 'divider', span: 24 },
    {
      label: '启用日期',
      key: 'enabledOn',
      type: 'date',
      span: 12,
      description: isEdit.value
        ? '账套创建后启用日期不可变更。'
        : '系统会据此生成首个会计年度的 12 个期间。',
      props: {
        type: 'date',
        valueFormat: 'YYYY-MM-DD',
        format: 'YYYY-MM-DD',
        class: '!w-full',
        disabled: isEdit.value
      }
    },
    {
      label: '年度起始月',
      key: 'fiscalYearStartMonth',
      type: 'number',
      span: 12,
      props: {
        min: 1,
        max: 12,
        controlsPosition: 'right',
        class: '!w-full',
        disabled: isEdit.value
      }
    },
    {
      label: '备注',
      key: 'remark',
      type: 'input',
      span: 24,
      props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
    }
  ])

  function createPayload(): AccountSetForm {
    return {
      ...toRaw(form.data),
      accountSetCode: form.data.accountSetCode.trim().toUpperCase(),
      accountSetName: form.data.accountSetName.trim(),
      legalEntityName: form.data.legalEntityName.trim(),
      unifiedSocialCreditCode: form.data.unifiedSocialCreditCode?.trim().toUpperCase() || null,
      baseCurrencyCode: form.data.baseCurrencyCode.trim().toUpperCase(),
      remark: form.data.remark?.trim() || null
    }
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
      const type = form.data.id ? 'edit' : 'add'
      await saveAccountSet(createPayload())
      emit('success', type)
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(row?: AccountSet): Promise<void> {
    Object.assign(
      form.data,
      createInitialForm(),
      row
        ? {
            id: row.id,
            tenantId: row.tenantId,
            accountSetCode: row.accountSetCode,
            accountSetName: row.accountSetName,
            legalEntityName: row.legalEntityName,
            unifiedSocialCreditCode: row.unifiedSocialCreditCode ?? null,
            accountingStandard: row.accountingStandard,
            vatTaxpayerType: row.vatTaxpayerType,
            baseCurrencyCode: row.baseCurrencyCode,
            enabledOn: row.enabledOn,
            fiscalYearStartMonth: row.fiscalYearStartMonth,
            status: row.status,
            isDefault: row.isDefault,
            remark: row.remark ?? null
          }
        : {}
    )

    await dialogRef.value?.handleOpen(
      { row },
      {
        title: row ? `编辑账套 · ${row.accountSetName}` : '新建企业账套',
        confirmText: row ? '保存修改' : '创建账套',
        contentMaxHeight: '72vh',
        onConfirm: handleSubmit,
        onOpen: () => formRef.value?.clearValidate(),
        dialogProps: { appendToBody: true, closeOnClickModal: false }
      }
    )
  }

  defineExpose({ handleOpen })
</script>
