<template>
  <ArtDialog ref="dialogRef" size="full">
    <div class="voucher-dialog">
      <ArtForm
        ref="formRef"
        v-model="form.data"
        :items="form.items"
        :rules="form.rules"
        :span="6"
        :gutter="18"
        label-width="108px"
        :show-reset="false"
        :show-submit="false"
        scroll-to-error
      />

      <VoucherEntryLines
        ref="lineEditorRef"
        v-model="form.data.lines"
        :subjects="context.subjects"
        :currencies="context.currencies"
        :auxiliary-items="context.auxiliaryItems"
      />

      <CashFlowAllocationPanel
        ref="cashFlowPanelRef"
        v-model="cashFlowDrafts"
        :lines="form.data.lines"
        :subjects="context.subjects"
        :statement-items="context.cashFlowItems"
      />

      <section class="voucher-dialog__attachments art-card-xs">
        <div class="voucher-dialog__section-header">
          <div>
            <ArtSectionTitle :show-line="false">原始凭证附件</ArtSectionTitle>
            <p>支持上传回单、发票、合同或其他记账依据，附件与凭证一并留存。</p>
          </div>
          <ArtExcelImport
            accept=""
            :parse-excel="false"
            :disabled="form.attachmentUploading"
            :button-props="{ type: 'primary', plain: true, loading: form.attachmentUploading }"
            @file-change="handleAttachmentUpload"
          >
            上传附件
          </ArtExcelImport>
        </div>
        <ArtTable
          :data="form.data.attachments"
          :columns="attachmentColumns"
          :pagination="false"
          :show-table-header="false"
          empty-height="120px"
          empty-text="暂无附件"
        />
      </section>
    </div>

    <template #footer="{ loading, api }">
      <div class="voucher-dialog__footer">
        <ElButton :disabled="loading" @click="api.handleClose()">取消</ElButton>
        <ElButton
          :loading="loading && submitMode === 'save'"
          @click="handleFooterConfirm(api, 'save')"
        >
          保存草稿
        </ElButton>
        <ElButton
          type="primary"
          :loading="loading && submitMode === 'submit'"
          @click="handleFooterConfirm(api, 'submit')"
        >
          保存并提交
        </ElButton>
      </div>
    </template>
  </ArtDialog>
</template>

<script setup lang="tsx">
  import dayjs from 'dayjs'
  import { cloneDeep } from 'lodash-es'
  import { ElButton, ElMessage } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { FormRules } from 'element-plus'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtForm, { type FormItem } from '@/components/core/forms/art-form/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import type { ColumnOption } from '@/types'
  import { uploadAttachment } from '@/api/common'
  import {
    fetchCashFlowAllocations,
    fetchFinancialStatementItems,
    fetchVoucherDetail,
    fetchVoucherTemplateDetail,
    saveCashFlowAllocations,
    saveVoucher,
    transitionVoucher
  } from '@/api/fms'
  import { renderAttachmentLink } from '@/components/core/media/art-file-viewer/render'
  import { downloadAttachment, getFileExtension } from '@/utils/file'
  import VoucherEntryLines from '@/views/fms/modules/voucher-entry-lines.vue'
  import CashFlowAllocationPanel from './cash-flow-allocation-panel.vue'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'FinanceVoucherDialog' })

  type Voucher = Api.Fms.VoucherRecord
  type FormData = Api.Fms.SaveVoucherPayload & { templateId?: string }
  type SubmitMode = 'save' | 'submit'
  type FooterApi = Pick<ArtDialogExpose<Voucher | undefined>, 'handleConfirm'>

  interface DialogContext {
    accountSet: Api.Fms.AccountSetOption
    subjects: Api.Fms.SubjectRecord[]
    currencies: Api.Fms.CurrencyRecord[]
    auxiliaryItems: Api.Fms.AuxiliaryItemRecord[]
    templates: Api.Fms.VoucherTemplateRecord[]
    cashFlowItems: Api.Fms.FinancialStatementItemRecord[]
  }

  interface FormExpose {
    validate: () => Promise<boolean>
    clearValidate: () => void
  }

  interface FormGroup {
    data: FormData
    items: ComputedRef<FormItem[]>
    rules: FormRules<FormData>
    attachmentUploading: boolean
  }

  const emit = defineEmits<{ success: [mode: SubmitMode] }>()
  const { getDictMap } = storeToRefs(useUserStore())
  const dialogRef = ref<ArtDialogExpose<Voucher | undefined>>()
  const formRef = ref<FormExpose>()
  const lineEditorRef = ref<{ isBalanced: boolean }>()
  const cashFlowPanelRef = ref<{ validate: (requireComplete?: boolean) => boolean }>()
  const cashFlowDrafts = ref<Api.Fms.VoucherCashFlowAllocationDraft[]>([])
  const submitMode = ref<SubmitMode>('save')
  const context = reactive<DialogContext>({
    accountSet: { label: '', value: '', status: 'draft', tenantId: '' },
    subjects: [],
    currencies: [],
    auxiliaryItems: [],
    templates: [],
    cashFlowItems: []
  })

  function createLine(lineNo: number): Api.Fms.VoucherLineRecord {
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
      creditAmount: 0
    }
  }

  function createInitialForm(): FormData {
    return {
      accountSetId: '',
      voucherType: 'general',
      voucherDate: dayjs().format('YYYY-MM-DD'),
      sourceType: 'manual',
      sourceId: null,
      sourceNo: null,
      summary: '',
      attachments: [],
      lines: [createLine(1), createLine(2)],
      templateId: ''
    }
  }

  const form: UnwrapNestedRefs<FormGroup> = reactive<FormGroup>({
    data: createInitialForm(),
    attachmentUploading: false,
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
        label: '凭证日期',
        key: 'voucherDate',
        type: 'date',
        props: { type: 'date', valueFormat: 'YYYY-MM-DD', class: '!w-full' }
      },
      {
        label: '凭证类型',
        key: 'voucherType',
        type: 'select',
        props: {
          options: voucherTypeOptions.value,
          clearable: false,
          disabled: form.data.voucherType === 'reversal'
        }
      },
      {
        label: '套用模板',
        key: 'templateId',
        type: 'select',
        props: {
          options: context.templates
            .filter((item) => item.isEnabled)
            .map((item) => ({
              label: `${item.templateCode} ${item.templateName}`,
              value: item.id
            })),
          clearable: true,
          filterable: true,
          placeholder: '可选，快速生成分录',
          disabled: Boolean(form.data.id),
          onChange: (value?: string) => void applyTemplate(value)
        }
      },
      {
        label: '凭证摘要',
        key: 'summary',
        type: 'input',
        span: 12,
        props: { maxlength: 200, showWordLimit: true, placeholder: '概括本次经济业务' }
      },
      {
        label: '业务来源',
        key: 'sourceType',
        type: 'select',
        props: { options: sourceTypeOptions.value, disabled: true }
      },
      {
        label: '来源单号',
        key: 'sourceNo',
        type: 'input',
        span: 6,
        props: { maxlength: 80, clearable: true, disabled: form.data.sourceType === 'manual' }
      }
    ]),
    rules: {
      accountSetId: [{ required: true, message: '请选择账套', trigger: 'change' }],
      voucherDate: [{ required: true, message: '请选择凭证日期', trigger: 'change' }],
      voucherType: [{ required: true, message: '请选择凭证类型', trigger: 'change' }],
      summary: [
        { required: true, message: '请输入凭证摘要', trigger: 'blur' },
        { max: 200, message: '凭证摘要不能超过 200 个字符', trigger: 'blur' }
      ]
    }
  })

  const voucherTypeOptions = computed(() =>
    (getDictMap.value.fmsVoucherType ?? []).filter((item) => item.value !== 'reversal')
  )
  const sourceTypeOptions = computed(() => getDictMap.value.fmsVoucherSourceType ?? [])

  const attachmentColumns: ColumnOption<Api.Fms.VoucherAttachment>[] = [
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'name',
      label: '附件名称',
      minWidth: 240,
      showOverflowTooltip: true,
      formatter: renderAttachmentLink
    },
    { prop: 'fileType', label: '格式', width: 100 },
    { prop: 'fileSize', label: '大小', width: 110 },
    {
      prop: 'operation',
      label: '操作',
      width: 96,
      formatter: (row) => (
        <div class="flex items-center">
          <ArtIconButton icon="ri:download-2-line" onClick={() => downloadAttachment(row)} />
          <ArtIconButton
            icon="ri:delete-bin-5-line"
            tone="danger"
            onClick={() => removeAttachment(row)}
          />
        </div>
      )
    }
  ]

  function subjectFor(line: Api.Fms.VoucherLineRecord): Api.Fms.SubjectRecord | undefined {
    return context.subjects.find((item) => item.id === line.subjectId)
  }

  function validateLines(): boolean {
    if (form.data.lines.length < 2) {
      ElMessage.warning('凭证至少需要两条分录')
      return false
    }
    const invalidIndex = form.data.lines.findIndex((line) => {
      const subject = subjectFor(line)
      const amountCount = Number(line.debitAmount > 0) + Number(line.creditAmount > 0)
      if (!subject || !line.summary.trim() || amountCount !== 1) return true
      if (
        (subject.auxiliaryConfigs ?? []).some(
          (config) => config.isRequired && !line.auxiliaryValues[config.auxiliaryTypeId]
        )
      )
        return true
      if (line.currencyId && (line.originalAmount <= 0 || line.exchangeRate <= 0)) return true
      return false
    })
    if (invalidIndex >= 0) {
      ElMessage.warning(`请完整填写第 ${invalidIndex + 1} 条分录的摘要、科目、核算维度和金额`)
      return false
    }
    const debit = form.data.lines.reduce((sum, line) => sum + Number(line.debitAmount || 0), 0)
    const credit = form.data.lines.reduce((sum, line) => sum + Number(line.creditAmount || 0), 0)
    if (debit <= 0 || Math.abs(debit - credit) > 0.001) {
      ElMessage.warning('凭证借贷金额必须大于零且保持平衡')
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
    if (!cashFlowPanelRef.value?.validate(submitMode.value === 'submit')) return false
    try {
      const payload = cloneDeep(toRaw(form.data))
      delete payload.templateId
      payload.lines = payload.lines.map((line, index) => ({
        ...line,
        lineNo: index + 1,
        summary: line.summary.trim(),
        auxiliaryValues: Object.fromEntries(
          Object.entries(line.auxiliaryValues).filter(([, value]) => Boolean(value))
        )
      }))
      const { data } = await saveVoucher(payload)
      if (data?.id) {
        const { data: detail } = await fetchVoucherDetail(data.id)
        const lineIdByNo = new Map(
          (detail?.lines ?? [])
            .filter((line): line is Api.Fms.VoucherLineRecord & { id: string } => Boolean(line.id))
            .map((line) => [line.lineNo, line.id])
        )
        await saveCashFlowAllocations(
          data.id,
          cashFlowDrafts.value.map((item) => ({
            voucherLineId: lineIdByNo.get(item.voucherLineNo) ?? '',
            statementItemId: item.statementItemId,
            amount: Number(item.amount),
            remark: item.remark?.trim() || null
          }))
        )
      }
      if (submitMode.value === 'submit' && data?.id) {
        await transitionVoucher(data.id, 'submit')
      }
      emit('success', submitMode.value)
      return true
    } catch {
      return false
    }
  }

  async function applyTemplate(templateId?: string): Promise<void> {
    if (!templateId) return
    try {
      const { data } = await fetchVoucherTemplateDetail(templateId)
      if (!data) return
      form.data.voucherType = data.voucherType
      form.data.summary = data.summary || form.data.summary
      form.data.lines = (data.lines ?? []).map((line, index) => ({
        lineNo: index + 1,
        summary: line.summary || data.summary || '',
        subjectId: line.subjectId,
        auxiliaryValues: { ...line.auxiliaryValues },
        currencyId: line.currencyId ?? null,
        exchangeRate: Number(line.exchangeRate || 1),
        originalAmount: line.currencyId ? Number(line.defaultAmount || 0) : 0,
        quantity: Number(line.quantity || 0),
        debitAmount: line.entryDirection === 'debit' ? Number(line.defaultAmount || 0) : 0,
        creditAmount: line.entryDirection === 'credit' ? Number(line.defaultAmount || 0) : 0
      }))
      ElMessage.success('凭证模板已套用，请核对金额与核算维度')
    } catch {
      form.data.templateId = ''
    }
  }

  async function handleAttachmentUpload(file: File): Promise<void> {
    form.attachmentUploading = true
    try {
      const [resource] = await uploadAttachment(file)
      if (!resource?.url) throw new Error('附件上传失败')
      if (form.data.attachments.some((item) => item.url === resource.url)) {
        ElMessage.info('该附件已在当前凭证中')
        return
      }
      form.data.attachments.push({
        name: resource.originName || file.name,
        url: resource.url,
        fileType: getFileExtension(file.name, resource.suffix),
        fileSize: resource.sizeInfo
      })
      ElMessage.success('附件上传成功')
    } catch {
      ElMessage.error('附件上传失败')
    } finally {
      form.attachmentUploading = false
    }
  }

  function removeAttachment(row: Api.Fms.VoucherAttachment): void {
    form.data.attachments = form.data.attachments.filter((item) => item.url !== row.url)
  }

  async function handleOpen(dialogContext: DialogContext, row?: Voucher): Promise<void> {
    Object.assign(context, dialogContext)
    cashFlowDrafts.value = []
    Object.assign(form.data, createInitialForm(), { accountSetId: context.accountSet.value })
    const { data: cashFlowItems } = await fetchFinancialStatementItems(
      context.accountSet.value,
      'cash_flow_statement'
    )
    context.cashFlowItems = cashFlowItems ?? []
    if (row?.id) {
      const [{ data }, { data: allocations }] = await Promise.all([
        fetchVoucherDetail(row.id),
        fetchCashFlowAllocations(row.id)
      ])
      if (!data) return
      Object.assign(form.data, {
        id: data.id,
        accountSetId: data.accountSetId,
        voucherType: data.voucherType,
        voucherDate: data.voucherDate,
        sourceType: data.sourceType,
        sourceId: data.sourceId,
        sourceNo: data.sourceNo,
        summary: data.summary,
        attachments: cloneDeep(data.attachments ?? []),
        lines: cloneDeep(data.lines ?? [])
      })
      const lineNoById = new Map(
        (data.lines ?? [])
          .filter((line): line is Api.Fms.VoucherLineRecord & { id: string } => Boolean(line.id))
          .map((line) => [line.id, line.lineNo])
      )
      cashFlowDrafts.value = (allocations ?? [])
        .map((allocation) => ({
          voucherLineNo: lineNoById.get(allocation.voucherLineId) ?? 0,
          statementItemId: allocation.statementItemId,
          amount: Number(allocation.amount),
          remark: allocation.remark ?? null
        }))
        .filter((item) => item.voucherLineNo > 0)
    }
    await dialogRef.value?.handleOpen(row, {
      title: row ? `编辑凭证 · ${row.voucherNo}` : '新增会计凭证',
      subtitle: '凭证提交后锁定核算范围与分录，过账后只能通过反向凭证冲销。',
      contentMaxHeight: '78vh',
      showFullscreenButton: true,
      fullscreen: false,
      dialogProps: { closeOnClickModal: false },
      onConfirm: handleSubmit,
      onOpen: () => formRef.value?.clearValidate()
    })
  }

  async function handleFooterConfirm(api: FooterApi, mode: SubmitMode): Promise<void> {
    submitMode.value = mode
    await api.handleConfirm()
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .voucher-dialog {
    display: flex;
    flex-direction: column;
    gap: var(--art-space-3);
    min-width: 0;

    &__attachments {
      min-width: 0;
      padding: var(--art-space-4);
    }

    &__section-header,
    &__footer {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      justify-content: space-between;
    }

    &__section-header {
      margin-bottom: var(--art-space-3);

      p {
        margin: 4px 0 0;
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }
    }

    &__footer {
      justify-content: flex-end;
      width: 100%;
    }

    @media (width <= 680px) {
      &__section-header,
      &__footer {
        flex-wrap: wrap;
      }

      :deep(.art-form .el-col) {
        flex: 0 0 100%;
        max-width: 100%;
      }
    }
  }
</style>
