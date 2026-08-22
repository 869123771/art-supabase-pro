<template>
  <ArtDialog ref="dialogRef" size="full">
    <div class="posting-rule-dialog">
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

      <section class="posting-rule-dialog__lines art-card-xs" aria-label="制证分录规则">
        <div class="posting-rule-dialog__section-head">
          <div>
            <ArtSectionTitle :show-line="false">制证分录规则</ArtSectionTitle>
            <p>金额口径与倍率共同计算分录金额；借贷双方必须至少各一条。</p>
          </div>
          <ElButton type="primary" plain @click="addLine">
            <ArtSvgIcon icon="ri:add-line" />新增分录
          </ElButton>
        </div>

        <ArtTable
          :data="form.lines"
          :columns="lineColumns"
          :pagination="false"
          table-layout="fixed"
          border
          empty-text="暂无制证分录"
          empty-description="请新增借方和贷方分录，形成完整的会计规则。"
          empty-height="180px"
        />
      </section>
    </div>

    <PostingLineAuxiliaryDialog ref="auxiliaryDialogRef" />
  </ArtDialog>
</template>

<script setup lang="tsx">
  import { ElButton, ElInput, ElInputNumber, ElMessage, ElOption, ElSelect } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchFinancialStatementItems, fetchPostingRuleDetail, savePostingRule } from '@/api/fms'
  import { useUserStore } from '@/store/modules/user'
  import { canEditField } from '@/utils/field-permission'
  import PostingLineAuxiliaryDialog from './posting-line-auxiliary-dialog.vue'

  defineOptions({ name: 'FinancePostingRuleDialog' })

  type Rule = Api.Fms.SecurePostingRuleRecord
  type Line = Api.Fms.PostingRuleLineRecord

  interface SelectOption {
    label: string
    value: string
  }

  interface DialogContext {
    accountSet: Api.Fms.AccountSetOption
    subjects: Api.Fms.SubjectRecord[]
    auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[]
    cashFlowItems: Api.Fms.FinancialStatementItemRecord[]
  }

  interface FormData {
    id?: string
    accountSetId: string
    ruleCode: string
    ruleName: string
    sourceEvent: string
    voucherType: Exclude<Api.Fms.VoucherType, 'reversal'>
    submissionMode: Api.Fms.PostingSubmissionMode
    costTypeCondition: string
    priority: number
    effectiveFrom: string
    effectiveTo: string
    isEnabled: boolean
    remark: string
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface AuxiliaryDialogExpose {
    handleOpen: (
      value: Record<string, string>,
      auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[],
      sourceOptions: SelectOption[],
      onSave: (result: Record<string, string>) => void
    ) => Promise<void>
  }

  interface FormGroup {
    data: FormData
    lines: Line[]
    items: ComputedRef<FormItem[]>
    rules: FormRules<FormData>
  }

  const emit = defineEmits<{ success: [] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Rule | undefined>>()
  const auxiliaryDialogRef = ref<AuxiliaryDialogExpose>()
  const formRef = ref<FormExpose>()
  const context = reactive<DialogContext>({
    accountSet: { label: '', value: '', status: 'draft', tenantId: '' },
    subjects: [],
    auxiliaryTypes: [],
    cashFlowItems: []
  })

  function createInitialForm(): FormData {
    return {
      accountSetId: '',
      ruleCode: '',
      ruleName: '',
      sourceEvent: '',
      voucherType: 'general',
      submissionMode: 'pending_review',
      costTypeCondition: '',
      priority: 100,
      effectiveFrom: '',
      effectiveTo: '',
      isEnabled: true,
      remark: ''
    }
  }

  function createLine(lineNo: number, direction: Api.Fms.BalanceDirection): Line {
    return {
      lineNo,
      direction,
      amountKey: 'gross_amount',
      amountMultiplier: 1,
      subjectId: '',
      cashFlowItemId: null,
      summary: '',
      auxiliaryBindings: {}
    }
  }

  const sourceEventOptions = computed<SelectOption[]>(() =>
    (getDictMap.value.fmsPostingSourceEvent ?? [])
      .filter((item) => !String(item.value).endsWith(':voided'))
      .map((item) => ({
        label: item.label ?? item.name,
        value: String(item.value)
      }))
  )
  const amountKeyOptions = computed<SelectOption[]>(() =>
    (getDictMap.value.fmsPostingAmountKey ?? []).map((item) => ({
      label: item.label ?? item.name,
      value: String(item.value)
    }))
  )
  const directionOptions = computed<SelectOption[]>(() =>
    (getDictMap.value.fmsBalanceDirection ?? [])
      .filter((item) => ['debit', 'credit'].includes(String(item.value)))
      .map((item) => ({ label: item.label ?? item.name, value: String(item.value) }))
  )
  const subjectOptions = computed<SelectOption[]>(() =>
    context.subjects
      .filter(
        (subject) =>
          subject.isEnabled &&
          !context.subjects.some((candidate) => candidate.parentId === subject.id)
      )
      .map((subject) => ({
        label: `${subject.subjectCode} ${subject.subjectName}`,
        value: subject.id
      }))
  )
  const payloadOptions = computed<SelectOption[]>(() => {
    const event = form.data.sourceEvent
    const allowed: Record<string, string[]> = {
      'customer_statement:confirmed': ['customer_id'],
      'carrier_statement:confirmed': ['carrier_id'],
      'customer_receipt:recorded': ['customer_id'],
      'carrier_payment:recorded': ['carrier_id'],
      'invoice:output_issued': ['customer_id'],
      'invoice:input_certified': ['carrier_id'],
      'expense_reimbursement:paid': ['applicant_user_id'],
      'waybill_cost:approved': ['waybill_id', 'carrier_id', 'driver_id', 'expense_item_id']
    }
    const values = new Set(allowed[event] ?? [])
    return (getDictMap.value.fmsPostingAuxiliaryPayloadKey ?? [])
      .filter((item) => values.has(String(item.value)))
      .map((item) => ({ label: item.label ?? item.name, value: String(item.value) }))
  })

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
        label: '规则编码',
        key: 'ruleCode',
        type: 'input',
        props: { maxlength: 40, placeholder: '如 CUSTOMER_RECEIPT' }
      },
      {
        label: '规则名称',
        key: 'ruleName',
        type: 'input',
        props: { maxlength: 80, placeholder: '请输入规则名称' }
      },
      {
        label: '业务事件',
        key: 'sourceEvent',
        type: 'select',
        props: {
          options: sourceEventOptions.value,
          clearable: false,
          onChange: () => {
            if (form.data.sourceEvent !== 'waybill_cost:approved') form.data.costTypeCondition = ''
            form.lines.forEach((line) => {
              line.auxiliaryBindings = {}
            })
          }
        }
      },
      {
        label: '凭证类型',
        key: 'voucherType',
        type: 'select',
        props: {
          options: (getDictMap.value.fmsVoucherType ?? []).filter(
            (item) => item.value !== 'reversal'
          ),
          clearable: false
        }
      },
      {
        label: '生成状态',
        key: 'submissionMode',
        type: 'select',
        props: { options: getDictMap.value.fmsPostingSubmissionMode ?? [], clearable: false }
      },
      {
        label: '规则优先级',
        key: 'priority',
        type: 'number',
        props: { min: 1, max: 9999, controlsPosition: 'right', class: '!w-full' }
      },
      {
        label: '启用状态',
        key: 'isEnabled',
        type: 'switch',
        props: { activeText: '启用', inactiveText: '停用', inlinePrompt: true }
      },
      ...(form.data.sourceEvent === 'waybill_cost:approved'
        ? [
            {
              label: '费用类型',
              key: 'costTypeCondition',
              type: 'select' as const,
              props: {
                options: getDictMap.value.fmsPostingWaybillCostType ?? [],
                clearable: true,
                placeholder: '全部费用类型'
              }
            }
          ]
        : []),
      {
        label: '生效日期',
        key: 'effectiveFrom',
        type: 'date',
        props: { type: 'date', valueFormat: 'YYYY-MM-DD', class: '!w-full', clearable: true }
      },
      {
        label: '失效日期',
        key: 'effectiveTo',
        type: 'date',
        props: { type: 'date', valueFormat: 'YYYY-MM-DD', class: '!w-full', clearable: true }
      },
      {
        label: '规则说明',
        key: 'remark',
        type: 'input',
        span: 24,
        props: { type: 'textarea', rows: 3, maxlength: 500, showWordLimit: true }
      }
    ]),
    rules: {
      accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
      ruleCode: [
        { required: true, message: '请输入规则编码', trigger: 'blur' },
        {
          pattern: /^[A-Za-z0-9_-]{2,40}$/,
          message: '规则编码只能包含字母、数字、下划线和短横线',
          trigger: 'blur'
        }
      ],
      ruleName: [{ required: true, message: '请输入规则名称', trigger: 'blur' }],
      sourceEvent: [{ required: true, message: '请选择业务事件', trigger: 'change' }],
      voucherType: [{ required: true, message: '请选择凭证类型', trigger: 'change' }],
      submissionMode: [{ required: true, message: '请选择生成状态', trigger: 'change' }]
    }
  })

  function updateLine(row: Line, patch: Partial<Line>): void {
    Object.assign(row, patch)
  }

  function lineSubject(row: Line): Api.Fms.SubjectRecord | undefined {
    return context.subjects.find((subject) => subject.id === row.subjectId)
  }

  function cashFlowOptions(row: Line): SelectOption[] {
    const direction: Api.Fms.CashFlowDirection = row.direction === 'debit' ? 'receipt' : 'payment'
    return context.cashFlowItems
      .filter(
        (item) =>
          item.isEnabled &&
          item.calculationMethod === 'mapping' &&
          item.cashFlowDirection === direction
      )
      .map((item) => ({ label: `${item.itemCode} ${item.itemName}`, value: item.id }))
  }

  function updateLineSubject(row: Line, subjectId: string): void {
    const subject = context.subjects.find((item) => item.id === subjectId)
    updateLine(row, {
      subjectId,
      cashFlowItemId: subject?.cashFlowRequired ? (row.cashFlowItemId ?? null) : null
    })
  }

  function updateLineDirection(row: Line, direction: Api.Fms.BalanceDirection): void {
    updateLine(row, { direction, cashFlowItemId: null })
  }

  function addLine(): void {
    const direction =
      form.lines.filter((item) => item.direction === 'debit').length <=
      form.lines.filter((item) => item.direction === 'credit').length
        ? 'debit'
        : 'credit'
    form.lines.push(createLine(form.lines.length + 1, direction))
  }

  function removeLine(row: Line): void {
    form.lines = form.lines
      .filter((item) => item !== row)
      .map((item, index) => ({ ...item, lineNo: index + 1 }))
  }

  function openAuxiliaryDialog(row: Line): void {
    void auxiliaryDialogRef.value?.handleOpen(
      row.auxiliaryBindings,
      context.auxiliaryTypes,
      payloadOptions.value,
      (result) => updateLine(row, { auxiliaryBindings: result })
    )
  }

  const lineColumns = computed<ColumnOption<Line>[]>(() => [
    { prop: 'lineNo', label: '行号', width: 64, fixed: 'left', align: 'center' },
    {
      prop: 'direction',
      label: '借贷方向',
      width: 126,
      formatter: (row) => (
        <ElSelect
          modelValue={row.direction}
          class="w-full!"
          onUpdate:modelValue={(value: Api.Fms.BalanceDirection) => updateLineDirection(row, value)}
        >
          {directionOptions.value.map((item) => (
            <ElOption key={item.value} label={item.label} value={item.value} />
          ))}
        </ElSelect>
      )
    },
    {
      prop: 'subjectId',
      label: '会计科目',
      minWidth: 230,
      formatter: (row) => (
        <ElSelect
          modelValue={row.subjectId}
          filterable
          class="w-full!"
          placeholder="选择末级科目"
          onUpdate:modelValue={(value: string) => updateLineSubject(row, value)}
        >
          {subjectOptions.value.map((item) => (
            <ElOption key={item.value} label={item.label} value={item.value} />
          ))}
        </ElSelect>
      )
    },
    {
      prop: 'cashFlowItemId',
      label: '现金流量项目',
      minWidth: 240,
      formatter: (row) =>
        lineSubject(row)?.cashFlowRequired ? (
          <ElSelect
            modelValue={row.cashFlowItemId ?? ''}
            filterable
            class="w-full!"
            placeholder="现金科目必选"
            onUpdate:modelValue={(value: string) => updateLine(row, { cashFlowItemId: value })}
          >
            {cashFlowOptions(row).map((item) => (
              <ElOption key={item.value} label={item.label} value={item.value} />
            ))}
          </ElSelect>
        ) : (
          <span class="text-g-500">无需归集</span>
        )
    },
    {
      prop: 'amountKey',
      label: '金额口径',
      width: 170,
      formatter: (row) => (
        <ElSelect
          modelValue={row.amountKey}
          class="w-full!"
          onUpdate:modelValue={(value: Api.Fms.PostingAmountKey) =>
            updateLine(row, { amountKey: value })
          }
        >
          {amountKeyOptions.value.map((item) => (
            <ElOption key={item.value} label={item.label} value={item.value} />
          ))}
        </ElSelect>
      )
    },
    {
      prop: 'amountMultiplier',
      label: '倍率',
      width: 130,
      formatter: (row) => (
        <ElInputNumber
          modelValue={row.amountMultiplier}
          min={0.000001}
          max={999999}
          precision={6}
          controlsPosition="right"
          class="w-full!"
          onUpdate:modelValue={(value: number | undefined) =>
            updateLine(row, { amountMultiplier: Number(value ?? 1) })
          }
        />
      )
    },
    {
      prop: 'summary',
      label: '分录摘要',
      minWidth: 180,
      formatter: (row) => (
        <ElInput
          modelValue={row.summary ?? ''}
          maxlength={120}
          placeholder="默认使用事件摘要"
          onUpdate:modelValue={(value: string) => updateLine(row, { summary: value })}
        />
      )
    },
    {
      prop: 'auxiliaryBindings',
      label: '核算维度',
      width: 132,
      align: 'center',
      formatter: (row) => (
        <ElButton link type="primary" onClick={() => openAuxiliaryDialog(row)}>
          {Object.keys(row.auxiliaryBindings).length
            ? `已绑定 ${Object.keys(row.auxiliaryBindings).length} 项`
            : '配置绑定'}
        </ElButton>
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: 72,
      fixed: 'right',
      align: 'center',
      formatter: (row) => <ArtButtonTable type="delete" onClick={() => removeLine(row)} />
    }
  ])

  function validateLines(): boolean {
    if (form.lines.length < 2) {
      ElMessage.warning('制证规则至少需要两条分录')
      return false
    }
    const invalidIndex = form.lines.findIndex(
      (line) =>
        !line.subjectId ||
        !line.amountKey ||
        Number(line.amountMultiplier) <= 0 ||
        (lineSubject(line)?.cashFlowRequired && !line.cashFlowItemId)
    )
    if (invalidIndex >= 0) {
      ElMessage.warning(`请完整填写第 ${invalidIndex + 1} 条制证分录`)
      return false
    }
    if (!form.lines.some((line) => line.direction === 'debit')) {
      ElMessage.warning('制证规则至少需要一条借方分录')
      return false
    }
    if (!form.lines.some((line) => line.direction === 'credit')) {
      ElMessage.warning('制证规则至少需要一条贷方分录')
      return false
    }
    if (
      form.data.effectiveFrom &&
      form.data.effectiveTo &&
      form.data.effectiveFrom > form.data.effectiveTo
    ) {
      ElMessage.warning('失效日期不能早于生效日期')
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
    const [sourceType, eventCode] = form.data.sourceEvent.split(':') as [
      Api.Fms.PostingSourceType,
      string
    ]
    try {
      await savePostingRule({
        id: form.data.id,
        accountSetId: form.data.accountSetId,
        ruleCode: form.data.ruleCode.trim().toUpperCase(),
        ruleName: form.data.ruleName.trim(),
        sourceType,
        eventCode,
        voucherType: form.data.voucherType,
        submissionMode: form.data.submissionMode,
        matchConditions: form.data.costTypeCondition
          ? { cost_type: form.data.costTypeCondition }
          : {},
        priority: Number(form.data.priority || 100),
        effectiveFrom: form.data.effectiveFrom || null,
        effectiveTo: form.data.effectiveTo || null,
        isEnabled: form.data.isEnabled,
        remark: form.data.remark.trim() || null,
        lines: form.lines.map((line, index) => ({
          ...line,
          lineNo: index + 1,
          amountMultiplier: Number(line.amountMultiplier),
          summary: line.summary?.trim() || null,
          auxiliaryBindings: { ...line.auxiliaryBindings }
        }))
      })
      emit('success')
      return true
    } catch {
      return false
    }
  }

  async function handleOpen(dialogContext: DialogContext, row?: Rule): Promise<void> {
    Object.assign(context, dialogContext)
    const { data: cashFlowItems } = await fetchFinancialStatementItems(
      context.accountSet.value,
      'cash_flow_statement'
    )
    context.cashFlowItems = cashFlowItems ?? []
    Object.assign(form.data, createInitialForm(), { accountSetId: context.accountSet.value })
    form.lines = [createLine(1, 'debit'), createLine(2, 'credit')]
    if (row?.id) {
      const { data } = await fetchPostingRuleDetail(row.id)
      if (!data) return
      if (!canEditField(data.fieldAccess, 'ruleConfiguration')) {
        ElMessage.warning('当前账号无权编辑该规则的制证配置')
        return
      }
      if (
        !data.voucherType ||
        data.voucherType === '***' ||
        !data.submissionMode ||
        data.submissionMode === '***'
      ) {
        ElMessage.warning('规则配置已受字段权限保护，无法进入编辑')
        return
      }
      Object.assign(form.data, {
        id: data.id,
        accountSetId: data.accountSetId,
        ruleCode: data.ruleCode,
        ruleName: data.ruleName,
        sourceEvent: `${data.sourceType}:${data.eventCode}`,
        voucherType: data.voucherType,
        submissionMode: data.submissionMode,
        costTypeCondition: String(data.matchConditions?.cost_type ?? ''),
        priority: data.priority,
        effectiveFrom: data.effectiveFrom ?? '',
        effectiveTo: data.effectiveTo ?? '',
        isEnabled: data.isEnabled,
        remark: data.remark ?? ''
      })
      form.lines = (data.lines ?? []).map((line, index) => ({
        ...line,
        lineNo: index + 1,
        amountMultiplier: Number(line.amountMultiplier),
        auxiliaryBindings: { ...line.auxiliaryBindings }
      }))
    }
    await dialogRef.value?.handleOpen(row, {
      title: row ? `编辑自动入账规则 · ${row.ruleCode}` : '新增自动入账规则',
      subtitle: '规则只生成草稿或待复核凭证，不会自动审核或过账。',
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
  .posting-rule-dialog {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-4);
    min-width: 0;

    &__lines {
      min-width: 0;
      padding: var(--art-space-4);
      border: 1px solid var(--el-border-color-lighter);
    }

    &__section-head {
      display: flex;
      gap: var(--art-space-4);
      align-items: flex-start;
      justify-content: space-between;
      margin-bottom: var(--art-space-4);

      p {
        margin: 6px 0 0;
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 680px) {
      :deep(.art-form .el-col) {
        flex: 0 0 100%;
        max-width: 100%;
      }

      &__section-head {
        flex-direction: column;
      }
    }
  }
</style>
