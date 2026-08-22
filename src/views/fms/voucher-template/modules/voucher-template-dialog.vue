<template>
  <ArtDialog ref="dialogRef" size="full">
    <div class="voucher-template-dialog">
      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :span="6"
        :gutter="18"
        label-width="112px"
        :show-reset="false"
        :show-submit="false"
        scroll-to-error
      />

      <ElAlert
        v-if="narrativeAccess === 'masked'"
        title="默认摘要与模板说明已按字段权限脱敏"
        type="info"
        :closable="false"
        show-icon
      />

      <VoucherEntryLines
        v-if="canShowEntries"
        v-model="form.lines"
        :subjects="context.subjects"
        :currencies="context.currencies"
        :auxiliary-items="context.auxiliaryItems"
        :direction-options="directionOptions"
        mode="template"
        allow-zero-amount
        :readonly="!canEditEntries"
      />
      <ElAlert
        v-else-if="entryAccess === 'masked'"
        :title="`模板分录已脱敏${detailLineCount ? `，共 ${detailLineCount} 条` : ''}`"
        description="科目、借贷方向、核算维度和默认金额不会发送到无明文权限的客户端。"
        type="warning"
        :closable="false"
        show-icon
      />
    </div>
  </ArtDialog>
</template>

<script setup lang="ts">
  import { cloneDeep } from 'lodash-es'
  import { ElAlert, ElMessage } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import { fetchVoucherTemplateDetail, saveVoucherTemplate } from '@/api/fms'
  import VoucherEntryLines from '@/views/fms/modules/voucher-entry-lines.vue'
  import { useUserStore } from '@/store/modules/user'
  import { canEditField, getFieldAccess, type FieldAccessLevel } from '@/utils/field-permission'

  defineOptions({ name: 'FinanceVoucherTemplateDialog' })

  type Template = Api.Fms.VoucherTemplateRecord
  type Line = Api.Fms.VoucherLineRecord

  interface FormData {
    id?: string
    accountSetId: string
    templateCode: string
    templateName: string
    voucherType: Exclude<Api.Fms.VoucherType, 'reversal'>
    summary: string
    isEnabled: boolean
    sort: number
    remark: string
  }

  interface DialogContext {
    accountSet: Api.Fms.AccountSetOption
    subjects: Api.Fms.SubjectRecord[]
    currencies: Api.Fms.CurrencyRecord[]
    auxiliaryItems: Api.Fms.AuxiliaryItemRecord[]
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: FormData
    lines: Line[]
    items: ComputedRef<FormItem[]>
    rules: FormRules<FormData>
  }

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Template | undefined>>()
  const formRef = ref<FormExpose>()
  const fieldAccess = ref<Api.Fms.VoucherTemplateFieldAccessMap>({})
  const detailLineCount = ref(0)
  const context = reactive<DialogContext>({
    accountSet: { label: '', value: '', status: 'draft', tenantId: '' },
    subjects: [],
    currencies: [],
    auxiliaryItems: []
  })

  function createLine(lineNo: number, direction: Api.Fms.BalanceDirection): Line {
    return {
      lineNo,
      summary: '',
      subjectId: '',
      auxiliaryValues: {},
      currencyId: null,
      exchangeRate: 1,
      originalAmount: 0,
      quantity: 0,
      debitAmount: 0,
      creditAmount: 0,
      entryDirection: direction
    }
  }

  function createInitialForm(): FormData {
    return {
      accountSetId: '',
      templateCode: '',
      templateName: '',
      voucherType: 'general',
      summary: '',
      isEnabled: true,
      sort: 100,
      remark: ''
    }
  }

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    lines: [createLine(1, 'debit'), createLine(2, 'credit')],
    items: computed<FormItem[]>(() => [
      {
        label: '账套',
        key: 'accountSetId',
        type: 'select',
        props: {
          options: [{ label: context.accountSet.label, value: context.accountSet.value }],
          disabled: true
        }
      },
      {
        label: '模板编码',
        key: 'templateCode',
        type: 'input',
        props: { maxlength: 30, placeholder: '如 CASH_RECEIPT' }
      },
      {
        label: '模板名称',
        key: 'templateName',
        type: 'input',
        props: { maxlength: 80, placeholder: '请输入模板名称' }
      },
      ...(canShowEntries.value
        ? ([
            {
              label: '凭证类型',
              key: 'voucherType',
              type: 'select',
              props: {
                options: voucherTypeOptions.value,
                clearable: false,
                disabled: !canEditEntries.value
              }
            }
          ] as FormItem[])
        : []),
      ...(canShowNarrative.value
        ? ([
            {
              label: '默认摘要',
              key: 'summary',
              type: 'input',
              span: 12,
              props: {
                maxlength: 200,
                showWordLimit: true,
                placeholder: '套用模板时带入凭证摘要',
                disabled: !canEditNarrative.value
              }
            }
          ] as FormItem[])
        : []),
      {
        label: '启用状态',
        key: 'isEnabled',
        type: 'switch',
        props: { activeText: '启用', inactiveText: '停用', inlinePrompt: true }
      },
      {
        label: '排序',
        key: 'sort',
        type: 'number',
        props: { min: 0, max: 9999, controlsPosition: 'right', class: '!w-full' }
      },
      ...(canShowNarrative.value
        ? ([
            {
              label: '模板说明',
              key: 'remark',
              type: 'input',
              span: 24,
              props: {
                type: 'textarea',
                rows: 3,
                maxlength: 500,
                showWordLimit: true,
                disabled: !canEditNarrative.value
              }
            }
          ] as FormItem[])
        : [])
    ]),
    rules: {
      accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
      templateCode: [
        { required: true, message: '请输入模板编码', trigger: 'blur' },
        {
          pattern: /^[A-Za-z0-9_-]{2,30}$/,
          message: '模板编码只能包含字母、数字、下划线和短横线',
          trigger: 'blur'
        }
      ],
      templateName: [{ required: true, message: '请输入模板名称', trigger: 'blur' }],
      voucherType: [{ required: true, message: '请选择凭证类型', trigger: 'change' }]
    }
  })

  const voucherTypeOptions = computed(() =>
    (getDictMap.value.fmsVoucherType ?? []).filter((item) => item.value !== 'reversal')
  )
  const sensitiveFieldFallback = computed<FieldAccessLevel>(() =>
    form.data.id ? 'hidden' : 'edit'
  )
  const narrativeAccess = computed(() =>
    getFieldAccess(fieldAccess.value, 'templateNarrative', sensitiveFieldFallback.value)
  )
  const entryAccess = computed(() =>
    getFieldAccess(fieldAccess.value, 'templateEntries', sensitiveFieldFallback.value)
  )
  const canShowNarrative = computed(() => ['read', 'edit'].includes(narrativeAccess.value))
  const canShowEntries = computed(() => ['read', 'edit'].includes(entryAccess.value))
  const canEditNarrative = computed(() =>
    canEditField(fieldAccess.value, 'templateNarrative', sensitiveFieldFallback.value)
  )
  const canEditEntries = computed(() =>
    canEditField(fieldAccess.value, 'templateEntries', sensitiveFieldFallback.value)
  )
  const directionOptions = computed(() =>
    (getDictMap.value.fmsBalanceDirection ?? [])
      .filter((item) => item.value === 'debit' || item.value === 'credit')
      .map((item) => ({
        label: item.label ?? item.name,
        value: item.value as Api.Fms.BalanceDirection
      }))
  )

  function validateLines(): boolean {
    if (!canEditEntries.value) return true
    if (!form.lines.length) {
      ElMessage.warning('凭证模板至少需要一条分录')
      return false
    }
    const invalidIndex = form.lines.findIndex((line) => {
      return !line.subjectId || !['debit', 'credit'].includes(line.entryDirection ?? '')
    })
    if (invalidIndex >= 0) {
      ElMessage.warning(`请为第 ${invalidIndex + 1} 条模板分录选择科目并明确借贷方向`)
      return false
    }
    return true
  }

  async function handleSubmit(): Promise<boolean> {
    try {
      await formRef.value?.validate()
    } catch {
      return false
    }
    if (!validateLines()) return false
    try {
      const payload: Api.Fms.SaveVoucherTemplatePayload = {
        id: form.data.id,
        accountSetId: form.data.accountSetId,
        templateCode: form.data.templateCode.trim().toUpperCase(),
        templateName: form.data.templateName.trim(),
        isEnabled: form.data.isEnabled,
        sort: form.data.sort
      }
      if (canEditNarrative.value) {
        payload.summary = form.data.summary.trim() || null
        payload.remark = form.data.remark.trim() || null
      }
      if (canEditEntries.value) {
        payload.voucherType = form.data.voucherType
        payload.lines = cloneDeep(form.lines).map((line, index) => ({
          lineNo: index + 1,
          summary: line.summary.trim() || null,
          subjectId: line.subjectId,
          entryDirection: line.entryDirection ?? 'debit',
          defaultAmount: Math.max(Number(line.debitAmount || 0), Number(line.creditAmount || 0)),
          auxiliaryValues: Object.fromEntries(
            Object.entries(line.auxiliaryValues).filter(([, value]) => Boolean(value))
          ),
          currencyId: line.currencyId ?? null,
          exchangeRate: Number(line.exchangeRate || 1),
          quantity: Number(line.quantity || 0)
        }))
      }
      await saveVoucherTemplate(payload)
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(dialogContext: DialogContext, row?: Template): Promise<void> {
    Object.assign(context, dialogContext)
    fieldAccess.value = {}
    detailLineCount.value = 0
    Object.assign(form.data, createInitialForm(), { accountSetId: context.accountSet.value })
    form.lines = [createLine(1, 'debit'), createLine(2, 'credit')]
    if (row?.id) {
      const { data } = await fetchVoucherTemplateDetail(row.id)
      if (!data) return
      fieldAccess.value = data.fieldAccess ?? {}
      detailLineCount.value = data.lineCount ?? 0
      Object.assign(form.data, {
        id: data.id,
        accountSetId: data.accountSetId,
        templateCode: data.templateCode,
        templateName: data.templateName,
        isEnabled: data.isEnabled,
        sort: data.sort,
        ...(['read', 'edit'].includes(getFieldAccess(data.fieldAccess, 'templateNarrative'))
          ? { summary: data.summary ?? '', remark: data.remark ?? '' }
          : {}),
        ...(['read', 'edit'].includes(getFieldAccess(data.fieldAccess, 'templateEntries')) &&
        data.voucherType !== '***'
          ? {
              voucherType:
                data.voucherType ?? ('general' as Exclude<Api.Fms.VoucherType, 'reversal'>)
            }
          : {})
      })
      form.lines = (Array.isArray(data.lines) ? data.lines : []).map((line, index) => ({
        lineNo: index + 1,
        summary: line.summary ?? '',
        subjectId: line.subjectId,
        auxiliaryValues: { ...line.auxiliaryValues },
        currencyId: line.currencyId ?? null,
        exchangeRate: Number(line.exchangeRate || 1),
        originalAmount: line.currencyId ? Number(line.defaultAmount || 0) : 0,
        quantity: Number(line.quantity || 0),
        debitAmount: line.entryDirection === 'debit' ? Number(line.defaultAmount || 0) : 0,
        creditAmount: line.entryDirection === 'credit' ? Number(line.defaultAmount || 0) : 0,
        entryDirection: line.entryDirection
      }))
    }
    await dialogRef.value?.handleOpen(row, {
      title: row ? `编辑凭证模板 · ${row.templateCode}` : '新增凭证模板',
      subtitle: '模板仅用于生成草稿凭证，不会绕过审核与过账控制。默认金额可在套用后调整。',
      contentMaxHeight: '78vh',
      showFullscreenButton: true,
      dialogProps: { closeOnClickModal: false },
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate()
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .voucher-template-dialog {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-3);
    min-width: 0;

    @media (width <= 680px) {
      :deep(.art-form .el-col) {
        flex: 0 0 100%;
        max-width: 100%;
      }
    }
  }
</style>
