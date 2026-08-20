<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <ArtAsyncState
      :loading="loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail"
      empty-text="暂无银行对账详情"
      @retry="retryLoad"
    >
      <div v-if="detail" class="bank-reconciliation-detail">
        <div class="bank-reconciliation-detail__toolbar">
          <div>
            <ElTag :type="detail.statementBalanceDifference === 0 ? 'success' : 'danger'">
              余额差 {{ formatMoney(detail.statementBalanceDifference) }}
            </ElTag>
            <span>已匹配 {{ detail.matchedCount }}/{{ detail.lineCount }} 行</span>
          </div>
          <div v-if="['draft', 'reconciling'].includes(detail.status)">
            <ElButton v-auth="'FinanceBankReconciliation:AutoMatch'" @click="handleAutoMatch">
              <ArtSvgIcon icon="ri:magic-line" />
              自动匹配
            </ElButton>
            <ElButton
              v-auth="'FinanceBankReconciliation:Complete'"
              type="success"
              @click="handleComplete"
            >
              <ArtSvgIcon icon="ri:checkbox-circle-line" />
              完成对账
            </ElButton>
            <ElButton
              v-auth="'FinanceBankReconciliation:Void'"
              type="danger"
              plain
              @click="handleVoid"
              >作废批次</ElButton
            >
          </div>
        </div>

        <ArtSectionTitle>批次信息</ArtSectionTitle>
        <ArtDescriptions :data="detail" :items="descriptionItems" :columns="3" />

        <section class="bank-reconciliation-detail__section">
          <ArtSectionTitle>银行流水</ArtSectionTitle>
          <ArtTable
            :data="lines"
            :columns="lineColumns"
            :pagination="false"
            :show-table-header="false"
            table-layout="fixed"
            empty-height="220px"
            max-height="430px"
            empty-text="暂无银行流水"
            border
          />
        </section>

        <section v-if="selectedLine" class="bank-reconciliation-detail__section">
          <ArtSectionTitle> 匹配记录 · 第 {{ selectedLine.lineNo }} 行 </ArtSectionTitle>
          <ArtTable
            :data="matches"
            :columns="matchColumns"
            :pagination="false"
            :show-table-header="false"
            table-layout="fixed"
            empty-height="150px"
            max-height="260px"
            empty-text="该银行流水暂无匹配记录"
            border
          />
        </section>

        <BankLineMatchDialog ref="matchDialogRef" @success="handleMatchChanged" />
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import type { ColumnOption } from '@/types'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import {
    autoMatchBankReconciliation,
    fetchBankReconciliationDetail,
    fetchBankStatementLines,
    fetchBankStatementMatches,
    ignoreBankStatementLine,
    transitionBankReconciliation,
    unmatchBankStatementLine
  } from '@/api/fms'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import BankLineMatchDialog from './bank-line-match-dialog.vue'

  defineOptions({ name: 'FinanceBankReconciliationDetailDrawer' })

  type Batch = Api.Fms.BankReconciliationBatchRecord
  type Line = Api.Fms.BankStatementLineRecord
  type Match = Api.Fms.BankStatementMatchRecord

  interface MatchDialogExpose {
    handleOpen: (row: Line) => Promise<void>
  }

  const emit = defineEmits<{ changed: [] }>()
  const { confirmAction, promptReason } = useArtFeedback()
  const { hasAuth } = useAuth()
  const drawerRef = ref<ArtDrawerExpose<Batch>>()
  const matchDialogRef = ref<MatchDialogExpose>()
  const detail = shallowRef<Batch>()
  const lines = shallowRef<Line[]>([])
  const selectedLine = shallowRef<Line>()
  const matches = shallowRef<Match[]>([])
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)

  const descriptionItems: ArtDescriptionItem<Batch>[] = [
    { key: 'batchNo', label: '对账批次号', field: 'batchNo', copyable: true },
    { key: 'status', label: '批次状态', field: 'status', dictCode: 'fmsBankReconciliationStatus' },
    { key: 'accountName', label: '对账账户', field: 'accountName' },
    { key: 'statementStartDate', label: '期间开始', field: 'statementStartDate', format: 'date' },
    { key: 'statementEndDate', label: '期间结束', field: 'statementEndDate', format: 'date' },
    { key: 'currencyCode', label: '币种', field: 'currencyCode' },
    { key: 'openingBalance', label: '期初余额', field: 'openingBalance', format: 'money' },
    { key: 'closingBalance', label: '期末余额', field: 'closingBalance', format: 'money' },
    {
      key: 'calculatedClosingBalance',
      label: '流水推算余额',
      field: 'calculatedClosingBalance',
      format: 'money'
    },
    { key: 'importedFileName', label: '来源文件', field: 'importedFileName', span: 2 },
    { key: 'remark', label: '导入说明', field: 'remark', span: 3 },
    { key: 'voidReason', label: '作废原因', field: 'voidReason', span: 3 }
  ]

  const lineColumns: ColumnOption<Line>[] = [
    { prop: 'lineNo', label: '#', width: 54, align: 'center' },
    { prop: 'transactionDate', label: '交易日期', width: 112 },
    {
      prop: 'direction',
      label: '方向',
      width: 90,
      dict: { code: 'fmsFundLedgerDirection', display: 'tag' }
    },
    {
      prop: 'amount',
      label: '银行金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatMoney(row.amount)
    },
    { prop: 'counterpartyName', label: '对方名称', minWidth: 150, showOverflowTooltip: true },
    { prop: 'bankReference', label: '银行参考号', minWidth: 145, showOverflowTooltip: true },
    {
      prop: 'matchedAmount',
      label: '已匹配',
      width: 125,
      align: 'right',
      formatter: (row) => formatMoney(row.matchedAmount)
    },
    {
      prop: 'status',
      label: '状态',
      width: 110,
      dict: { code: 'fmsBankStatementLineStatus', display: 'tag' }
    },
    {
      prop: 'operation',
      label: '操作',
      width: 170,
      fixed: 'right',
      formatter: (row) => (
        <div class="flex items-center">
          <ArtButtonTable type="view" label="查看匹配" onClick={() => void loadMatches(row)} />
          {['unmatched', 'partial_matched'].includes(row.status) ? (
            <>
              <ArtButtonTable
                type="edit"
                permission="FinanceBankReconciliation:Match"
                label="手工匹配"
                onClick={() => void matchDialogRef.value?.handleOpen(row)}
              />
              {row.status === 'unmatched' ? (
                <ArtButtonTable
                  type="delete"
                  permission="FinanceBankReconciliation:Ignore"
                  label="忽略流水"
                  onClick={() => void handleIgnore(row)}
                />
              ) : null}
            </>
          ) : null}
        </div>
      )
    }
  ]

  const matchColumns = computed<ColumnOption<Match>[]>(() => [
    {
      prop: 'matchedAt',
      label: '匹配时间',
      width: 165,
      formatter: (row) => formatWithDayjs(row.matchedAt, 'YYYY-MM-DD HH:mm') || '--'
    },
    {
      prop: 'matchType',
      label: '方式',
      width: 100,
      dict: { code: 'fmsBankMatchType', display: 'tag' }
    },
    {
      prop: 'ledgerEntry',
      label: '资金流水',
      minWidth: 230,
      formatter: (row) =>
        row.ledgerEntry ? `${row.ledgerEntry.entryDate} · ${row.ledgerEntry.summary}` : '--'
    },
    {
      prop: 'matchedAmount',
      label: '匹配金额',
      width: 125,
      align: 'right',
      formatter: (row) => formatMoney(row.matchedAmount)
    },
    { prop: 'matchedBy', label: '操作人', minWidth: 140, showOverflowTooltip: true },
    ...(hasAuth('FinanceBankReconciliation:Unmatch') && detail.value?.status !== 'reconciled'
      ? [
          {
            prop: 'operation',
            label: '操作',
            width: 78,
            fixed: 'right' as const,
            formatter: (row: Match) => (
              <ArtButtonTable
                type="delete"
                permission="FinanceBankReconciliation:Unmatch"
                label="撤销匹配"
                onClick={() => void handleUnmatch(row)}
              />
            )
          } satisfies ColumnOption<Match>
        ]
      : [])
  ])

  function formatMoney(value: number): string {
    return formatCurrencyValue(value, detail.value?.currencyCode)
  }

  async function loadDetail(): Promise<void> {
    if (!detail.value) return
    loading.value = true
    loadError.value = null
    try {
      const batchId = detail.value.id
      const [batchResult, lineResult] = await Promise.all([
        fetchBankReconciliationDetail(batchId),
        fetchBankStatementLines(batchId)
      ])
      if (batchResult.data) detail.value = batchResult.data
      lines.value = lineResult.data ?? []
      if (selectedLine.value) {
        const refreshed = lines.value.find((item) => item.id === selectedLine.value?.id)
        selectedLine.value = refreshed
        if (refreshed) await loadMatches(refreshed)
      }
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('银行对账详情加载失败')
    } finally {
      loading.value = false
    }
  }

  async function loadMatches(row: Line): Promise<void> {
    selectedLine.value = row
    const { data } = await fetchBankStatementMatches(row.id)
    matches.value = data ?? []
  }

  function retryLoad(): void {
    void loadDetail()
  }

  async function handleAutoMatch(): Promise<void> {
    if (!detail.value) return
    await autoMatchBankReconciliation(detail.value.id)
    await loadDetail()
    emit('changed')
  }

  async function handleComplete(): Promise<void> {
    if (!detail.value) return
    try {
      await confirmAction(
        '完成后批次与匹配关系将锁定，请确认所有未匹配项已处理且期末余额差为 0。',
        '完成银行对账',
        { type: 'success', confirmButtonText: '确认完成' }
      )
      const { data } = await transitionBankReconciliation(detail.value.id, 'complete', {
        version: detail.value.version
      })
      if (data) detail.value = { ...detail.value, ...data, status: 'reconciled' }
      emit('changed')
    } catch {
      // 用户取消或数据库校验阻止时不重复提示。
    }
  }

  async function handleVoid(): Promise<void> {
    if (!detail.value) return
    try {
      const reason = await promptReason(
        '作废将撤销本批次全部匹配关系，但保留导入记录供审计。',
        '作废对账批次',
        {
          emptyMessage: '请填写作废原因',
          placeholder: '说明作废原因及后续处理安排'
        }
      )
      const { data } = await transitionBankReconciliation(detail.value.id, 'void', {
        reason,
        version: detail.value.version
      })
      if (data) detail.value = { ...detail.value, ...data, status: 'voided' }
      await loadDetail()
      emit('changed')
    } catch {
      // 用户取消或数据库校验阻止时不重复提示。
    }
  }

  async function handleIgnore(row: Line): Promise<void> {
    try {
      const reason = await promptReason(
        '忽略项不会参与资金流水匹配，但仍参与银行余额计算。',
        '忽略银行流水',
        {
          emptyMessage: '请填写忽略原因',
          placeholder: '例如 银行利息待补录资金流水'
        }
      )
      await ignoreBankStatementLine(row.id, reason)
      await loadDetail()
      emit('changed')
    } catch {
      // 用户取消时不处理。
    }
  }

  async function handleUnmatch(row: Match): Promise<void> {
    try {
      await confirmAction('确定撤销该匹配关系吗？', '撤销银行流水匹配', {
        type: 'warning',
        confirmButtonText: '确认撤销'
      })
      await unmatchBankStatementLine(row.id)
      await loadDetail()
      emit('changed')
    } catch {
      // 用户取消时不处理。
    }
  }

  async function handleMatchChanged(): Promise<void> {
    await loadDetail()
    emit('changed')
  }

  async function handleOpen(row: Batch): Promise<void> {
    detail.value = row
    lines.value = []
    selectedLine.value = undefined
    matches.value = []
    await drawerRef.value?.handleOpen(row, {
      title: `银行对账 · ${row.batchNo}`,
      size: 'full',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: loadDetail,
      drawerProps: { appendToBody: true, resizable: false, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .bank-reconciliation-detail {
    min-width: 0;

    &__toolbar {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      padding: 14px 16px;
      margin-bottom: 20px;
      background: color-mix(in srgb, var(--el-color-primary) 4%, var(--default-box-color));
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > div {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        align-items: center;
      }

      span {
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }
    }

    &__section {
      margin-top: var(--art-space-6);
    }

    @media (width <= 760px) {
      &__toolbar {
        flex-direction: column;
        align-items: stretch;
      }
    }
  }
</style>
