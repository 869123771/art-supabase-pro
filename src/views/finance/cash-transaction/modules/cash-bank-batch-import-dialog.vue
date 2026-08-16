<template>
  <ArtDialog ref="dialogRef" size="full" :show-fullscreen-button="true">
    <div class="bank-batch">
      <section class="bank-batch__hero">
        <header>
          <div class="bank-batch__hero-main">
            <span class="bank-batch__hero-icon" aria-hidden="true">
              <ArtSvgIcon icon="ri:bank-line" />
            </span>
            <div>
              <span class="bank-batch__eyebrow"><i />AI BANK STATEMENT MATCHING</span>
              <h3>导入银行流水，自动完成匹配建议</h3>
              <p>识别银行表头、匹配往来单位与待核销对账单，确认前不会写入财务数据。</p>
            </div>
          </div>
          <ArtExcelImport
            v-if="state.result"
            accept=".xlsx,.xls,.csv"
            :disabled="state.analyzing || state.committing"
            :button-props="{ type: 'primary', plain: true, loading: state.analyzing }"
            icon="ri:refresh-line"
            @import-success="handleImport"
            @import-error="handleImportError"
          >
            重新导入并分析
          </ArtExcelImport>
          <ElTag v-else type="primary" effect="plain" round>
            <ArtSvgIcon icon="ri:shield-check-line" aria-hidden="true" />导入分析不会自动入账
          </ElTag>
        </header>

        <div class="bank-batch__steps" aria-label="银行流水批量导入流程">
          <article class="is-active">
            <span>1</span>
            <div><strong>导入文件</strong><small>Excel 或 CSV</small></div>
          </article>
          <i aria-hidden="true" />
          <article :class="{ 'is-active': state.result }">
            <span>2</span>
            <div><strong>AI 匹配</strong><small>识别与校验</small></div>
          </article>
          <i aria-hidden="true" />
          <article :class="{ 'is-active': selectedRows.length }">
            <span>3</span>
            <div><strong>核对入账</strong><small>人工最终确认</small></div>
          </article>
        </div>
      </section>

      <ElAlert v-if="!isPlatformSuper" type="info" :closable="false" show-icon>
        <template #title>当前为只读分析模式</template>
        普通用户可导入并查看 AI 匹配建议；批量写入财务流水仅允许平台超级管理员执行。
      </ElAlert>

      <ArtAsyncState
        :loading="state.analyzing"
        loading-mode="skeleton"
        :error="state.error"
        :retryable="false"
        :min-height="320"
      >
        <template #error-action>
          <ArtExcelImport
            accept=".xlsx,.xls,.csv"
            :disabled="state.analyzing || state.committing"
            :button-props="{ type: 'primary' }"
            icon="ri:upload-cloud-2-line"
            @import-success="handleImport"
            @import-error="handleImportError"
          >
            重新选择文件
          </ArtExcelImport>
        </template>

        <template v-if="state.result">
          <section class="bank-batch__source art-card-xs">
            <div
              ><small>本次文件</small><strong>{{ state.fileName }}</strong></div
            >
            <div>
              <small>表头映射</small>
              <strong>{{ state.result.usedAi ? 'AI 映射 + 规则校验' : '规则映射' }}</strong>
            </div>
            <div>
              <small>匹配置信度</small><strong>{{ percent(state.result.confidence) }}</strong>
            </div>
            <div>
              <small>复核阈值</small>
              <strong>{{ percent(state.result.reviewConfidenceThreshold) }}</strong>
            </div>
          </section>

          <section class="bank-batch__metrics">
            <article v-for="metric in metrics" :key="metric.key" :class="`is-${metric.tone}`">
              <span class="bank-batch__metric-icon" aria-hidden="true">
                <ArtSvgIcon :icon="metric.icon" />
              </span>
              <div>
                <span>{{ metric.label }}</span>
                <strong>{{ metric.value }}</strong>
                <small>{{ metric.hint }}</small>
              </div>
            </article>
          </section>

          <section class="bank-batch__table art-card-xs">
            <header>
              <div><h4>逐行匹配结果</h4><p>默认勾选信息完整且往来单位高置信匹配的流水。</p></div>
              <ElTag type="primary" effect="plain" round>已选 {{ selectedRows.length }} 条</ElTag>
            </header>
            <ArtTable
              :data="state.result.rows"
              :columns="columns"
              :pagination="false"
              :show-table-header="false"
              max-height="430px"
              border
            />
          </section>
        </template>

        <section v-else class="bank-batch__onboarding">
          <article class="bank-batch__upload art-card-xs">
            <span class="bank-batch__upload-icon" aria-hidden="true">
              <ArtSvgIcon icon="ri:file-excel-2-line" />
            </span>
            <div>
              <span>STEP 01</span>
              <h4>选择银行流水文件</h4>
              <p>系统将读取首个工作表，并自动识别常见银行字段。</p>
            </div>
            <ArtExcelImport
              accept=".xlsx,.xls,.csv"
              :disabled="state.analyzing || state.committing"
              :button-props="{ type: 'primary', size: 'large', loading: state.analyzing }"
              icon="ri:upload-cloud-2-line"
              @import-success="handleImport"
              @import-error="handleImportError"
            >
              选择流水文件
            </ArtExcelImport>
            <div class="bank-batch__formats">
              <span>支持 .xlsx</span><span>.xls</span><span>.csv</span><span>单次最多 300 行</span>
            </div>
          </article>

          <aside class="bank-batch__guide art-card-xs">
            <header>
              <span aria-hidden="true"><ArtSvgIcon icon="ri:list-check-3" /></span>
              <div><h4>导入前请确认</h4><p>完整字段有助于获得更准确的匹配结果</p></div>
            </header>
            <ul>
              <li>
                <ArtSvgIcon icon="ri:calendar-check-line" aria-hidden="true" />
                <div><strong>交易日期与金额</strong><small>用于校验流水有效性</small></div>
              </li>
              <li>
                <ArtSvgIcon icon="ri:building-2-line" aria-hidden="true" />
                <div><strong>对方户名或往来单位</strong><small>用于匹配客户与承运商</small></div>
              </li>
              <li>
                <ArtSvgIcon icon="ri:fingerprint-line" aria-hidden="true" />
                <div><strong>银行流水号</strong><small>用于识别并拦截重复导入</small></div>
              </li>
            </ul>
            <div class="bank-batch__safe-note">
              <ArtSvgIcon icon="ri:shield-check-line" aria-hidden="true" />
              <span>AI 只生成匹配建议，入账前仍需人工确认。</span>
            </div>
          </aside>
        </section>
      </ArtAsyncState>
    </div>

    <template #footer="{ api }">
      <div class="bank-batch__footer">
        <span>
          <ArtSvgIcon icon="ri:lock-2-line" aria-hidden="true" />
          {{
            state.result ? '请核对选中流水，确认后将整批写入' : '选择文件后才能进入核对与入账步骤'
          }}
        </span>
        <div>
          <ElButton @click="api.handleClose()">取消</ElButton>
          <ElTooltip
            :disabled="isPlatformSuper"
            content="仅平台超级管理员可批量入账"
            placement="top"
          >
            <span>
              <ElButton
                type="primary"
                :loading="state.committing"
                :disabled="!isPlatformSuper || !selectedRows.length || state.analyzing"
                @click="handleCommit"
              >
                确认入账 {{ selectedRows.length ? `(${selectedRows.length})` : '' }}
              </ElButton>
            </span>
          </ElTooltip>
        </div>
      </div>
    </template>
  </ArtDialog>
</template>

<script setup lang="tsx">
  import { createFriendlySupabaseError, getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { ElCheckbox, ElMessage, ElTag } from 'element-plus'
  import { uniq } from 'lodash-es'
  import ArtDialog from '@/components/core/dialogs/art-dialog/index.vue'
  import type { ArtDialogExpose } from '@/components/core/dialogs/art-dialog/types'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtExcelImport from '@/components/core/forms/art-excel-import/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { analyzeBankStatementBatchByAi, commitBankStatementBatchByAi } from '@/api/finance'
  import { useUserStore } from '@/store/modules/user'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'

  defineOptions({ name: 'FinanceCashBankBatchImportDialog' })
  type Row = Api.Finance.BankBatchMatchRow
  type Status = Api.Finance.BankBatchRowStatus
  const emit = defineEmits<{ success: [] }>()
  const dialogRef = ref<ArtDialogExpose>()
  const { confirm } = useArtFeedback()
  const { isPlatformSuper } = storeToRefs(useUserStore())
  const selectedRowIds = ref<string[]>([])
  const selectedRows = computed(() =>
    (state.result?.rows ?? []).filter((row) => selectedRowIds.value.includes(row.rowId))
  )
  const state = reactive<{
    analyzing: boolean
    committing: boolean
    error: Error | null
    fileName: string
    result?: Api.Finance.BankBatchAnalyzeResponse
  }>({
    analyzing: false,
    committing: false,
    error: null,
    fileName: '',
    result: undefined
  })
  const statusMeta: Record<
    Status,
    { label: string; type: 'success' | 'warning' | 'info' | 'danger' }
  > = {
    ready: { label: '可入账', type: 'success' },
    review: { label: '需复核', type: 'warning' },
    duplicate: { label: '重复', type: 'info' },
    invalid: { label: '无效', type: 'danger' }
  }
  const metrics = computed(() => [
    {
      key: 'total',
      label: '导入流水',
      value: state.result?.rows.length ?? 0,
      hint: '本次文件有效数据行',
      tone: 'primary',
      icon: 'ri:file-list-3-line'
    },
    {
      key: 'ready',
      label: '可直接入账',
      value: state.result?.summary.ready ?? 0,
      hint: '完整且高置信匹配',
      tone: 'success',
      icon: 'ri:checkbox-circle-line'
    },
    {
      key: 'review',
      label: '需要复核',
      value: state.result?.summary.review ?? 0,
      hint: '往来单位匹配不足',
      tone: 'warning',
      icon: 'ri:search-eye-line'
    },
    {
      key: 'blocked',
      label: '已拦截',
      value: (state.result?.summary.duplicate ?? 0) + (state.result?.summary.invalid ?? 0),
      hint: '重复或关键字段无效',
      tone: 'danger',
      icon: 'ri:forbid-2-line'
    }
  ])

  const columns: ColumnOption<Row>[] = [
    {
      prop: 'selected',
      label: '选择',
      width: 58,
      fixed: 'left',
      align: 'center',
      formatter: (row) => (
        <ElCheckbox
          modelValue={selectedRowIds.value.includes(row.rowId)}
          disabled={!isSelectable(row)}
          onChange={(checked) => toggleRow(row, Boolean(checked))}
        />
      )
    },
    { prop: 'sourceRow', label: '源行', width: 66, align: 'center' },
    {
      prop: 'status',
      label: '状态',
      width: 92,
      formatter: (row) => (
        <ElTag type={getStatusMeta(row.status).type} size="small" effect="light">
          {getStatusMeta(row.status).label}
        </ElTag>
      )
    },
    {
      prop: 'direction',
      label: '方向',
      width: 78,
      formatter: (row) =>
        row.direction === 'receipt' ? '收款' : row.direction === 'payment' ? '付款' : '-'
    },
    { prop: 'transactionDate', label: '交易日期', width: 112 },
    {
      prop: 'amount',
      label: '金额',
      width: 128,
      align: 'right',
      formatter: (row) => money(row.amount)
    },
    {
      prop: 'counterpartyName',
      label: '往来单位',
      minWidth: 180,
      showOverflowTooltip: true,
      formatter: (row) =>
        `${row.counterpartyName || '-'} · ${row.counterpartyId ? `匹配 ${row.counterpartyScore}%` : '未匹配'}`
    },
    { prop: 'bankReference', label: '银行流水号', minWidth: 150, showOverflowTooltip: true },
    {
      prop: 'statement',
      label: '推荐对账单',
      minWidth: 170,
      formatter: (row) => row.statementMatches[0]?.statementNo || '暂不核销'
    },
    {
      prop: 'issues',
      label: '校验说明',
      minWidth: 220,
      showOverflowTooltip: true,
      formatter: (row) => row.issues.join('；') || '信息完整，可批量入账'
    }
  ]

  function money(value: number) {
    return `¥${Number(value || 0).toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
  }
  function percent(value: number) {
    return `${Math.round(Number(value || 0) * 100)}%`
  }
  function getStatusMeta(status: unknown) {
    return statusMeta[status as Status] ?? statusMeta.invalid
  }
  function isSelectable(row: Row) {
    return row.status === 'ready' && Boolean(row.counterpartyId)
  }
  function toggleRow(row: Row, selected: boolean) {
    selectedRowIds.value = selected
      ? uniq([...selectedRowIds.value, row.rowId])
      : selectedRowIds.value.filter((id) => id !== row.rowId)
  }
  async function handleImport(rows: Array<Record<string, unknown>>, file: File) {
    state.analyzing = true
    state.error = null
    state.fileName = file.name
    state.result = undefined
    selectedRowIds.value = []
    try {
      const response = await analyzeBankStatementBatchByAi({ rows, fileName: file.name })
      if (response.error || !response.data) throw response.error || new Error('AI 未返回匹配结果')
      state.result = response.data
      selectedRowIds.value = response.data.rows.filter(isSelectable).map((row) => row.rowId)
      ElMessage.success(`已完成 ${response.data.rows.length} 条流水匹配`)
    } catch (error) {
      state.error = createFriendlySupabaseError(error, '银行流水分析失败')
      ElMessage.error(state.error.message)
    } finally {
      state.analyzing = false
    }
  }
  function handleImportError(error: Error) {
    state.error = createFriendlySupabaseError(error, '文件解析失败，请检查文件格式后重试')
    ElMessage.error(getFriendlySupabaseErrorMessage(error, '文件解析失败，请检查文件格式后重试'))
  }

  async function handleCommit() {
    if (!state.result || !selectedRows.value.length || !isPlatformSuper.value) return
    try {
      await confirm(
        `将一次性写入 ${selectedRows.value.length} 条收付款流水，并按推荐对账单完成核销。整批校验失败时不会写入任何数据。`,
        {
          title: '确认批量入账',
          confirmButtonText: '确认入账',
          cancelButtonText: '继续核对'
        }
      )
      state.committing = true
      const response = await commitBankStatementBatchByAi({
        artifactId: state.result.artifactId,
        rows: selectedRows.value
      })
      if (response.error || !response.data) throw response.error || new Error('批量入账结果未返回')
      ElMessage.success(`已成功入账 ${response.data.committedCount} 条银行流水`)
      emit('success')
      dialogRef.value?.handleClose()
    } catch (error) {
      if (error !== 'cancel' && error !== 'close') {
        ElMessage.error(getFriendlySupabaseErrorMessage(error, '银行流水入账失败，请稍后重试'))
      }
    } finally {
      state.committing = false
    }
  }
  async function handleOpen() {
    state.error = null
    state.result = undefined
    state.fileName = ''
    selectedRowIds.value = []
    await dialogRef.value?.handleOpen(undefined, {
      title: 'AI 银行流水批量导入',
      subtitle: 'AI 自动映射表头、匹配往来单位与待核销对账单；确认后才会写入财务数据',
      contentMaxHeight: '74vh',
      dialogProps: {
        appendToBody: true,
        closeOnClickModal: false
      }
    })
  }
  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .bank-batch {
    display: grid;
    gap: 18px;
    width: 100%;
    min-width: 0;
    max-width: 1460px;
    margin-inline: auto;

    &__hero header,
    &__hero-main,
    &__steps,
    &__steps article,
    &__source,
    &__table header,
    &__guide header,
    &__guide li,
    &__safe-note,
    &__footer,
    &__footer > div {
      display: flex;
      align-items: center;
    }

    &__hero {
      display: grid;
      gap: 18px;
      padding: 20px 22px;
      overflow: hidden;
      background: linear-gradient(135deg, var(--el-color-primary-light-9), var(--el-bg-color));
      border: 1px solid var(--el-color-primary-light-8);
      border-top: 3px solid var(--el-color-primary);
      border-radius: var(--el-border-radius-base);

      header {
        gap: 20px;
        justify-content: space-between;
      }
    }

    &__hero-main {
      gap: 13px;
      min-width: 0;

      > div {
        min-width: 0;
      }

      h3 {
        margin: 2px 0 4px;
        font-size: 18px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
      }
    }

    &__hero-icon {
      display: grid;
      flex: 0 0 48px;
      place-items: center;
      width: 48px;
      height: 48px;
      font-size: 23px;
      color: var(--el-color-primary);
      background: var(--el-bg-color);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 8px 22px rgb(64 116 255 / 12%);
    }

    &__eyebrow {
      display: flex;
      gap: 6px;
      align-items: center;
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.1em;

      i {
        width: 5px;
        height: 5px;
        background: currentcolor;
        border-radius: 50%;
      }
    }

    &__hero .el-tag {
      flex: none;
      gap: 5px;
    }

    &__steps {
      display: grid;
      grid-template-columns: auto minmax(24px, 1fr) auto minmax(24px, 1fr) auto;
      gap: 10px;
      max-width: 760px;
      padding-left: 61px;

      > i {
        height: 1px;
        background: var(--el-border-color);
      }

      article {
        gap: 8px;
        color: var(--el-text-color-placeholder);

        > span {
          display: grid;
          flex: none;
          place-items: center;
          width: 28px;
          height: 28px;
          font-weight: 700;
          background: var(--el-fill-color);
          border-radius: 50%;
        }

        > div {
          display: grid;
          min-width: 0;
        }

        strong {
          font-size: 12px;
        }

        small {
          margin-top: 2px;
          font-size: 10px;
        }

        &.is-active {
          color: var(--el-color-primary);

          > span {
            color: #fff;
            background: var(--el-color-primary);
          }
        }
      }
    }

    &__onboarding {
      display: grid;
      grid-template-columns: minmax(0, 1.35fr) minmax(360px, 0.65fr);
      gap: 18px;
      min-height: 320px;
    }

    &__upload,
    &__guide {
      min-width: 0;
      padding: 24px;
    }

    &__upload {
      display: grid;
      align-content: center;
      justify-items: center;
      min-height: 320px;
      text-align: center;
      background: linear-gradient(145deg, var(--el-bg-color), var(--el-color-primary-light-9));
      border: 1px dashed var(--el-color-primary-light-5);

      > div:first-of-type > span {
        font-size: 10px;
        font-weight: 700;
        color: var(--el-color-primary);
        letter-spacing: 0.12em;
      }

      h4 {
        margin: 5px 0;
        font-size: 18px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0 0 18px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__upload-icon {
      display: grid;
      place-items: center;
      width: 62px;
      height: 62px;
      margin-bottom: 13px;
      font-size: 30px;
      color: var(--el-color-primary);
      background: var(--el-bg-color);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 12px 28px rgb(64 116 255 / 14%);
    }

    &__formats {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      justify-content: center;
      margin-top: 15px;

      span {
        padding: 4px 8px;
        font-size: 10px;
        color: var(--el-text-color-secondary);
        background: var(--el-fill-color);
        border-radius: 999px;
      }
    }

    &__guide {
      display: grid;
      gap: 18px;
      align-content: start;

      header {
        gap: 11px;

        > span {
          display: grid;
          flex: none;
          place-items: center;
          width: 40px;
          height: 40px;
          font-size: 19px;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: var(--el-border-radius-base);
        }

        h4,
        p {
          margin: 0;
        }

        h4 {
          color: var(--el-text-color-primary);
        }

        p {
          margin-top: 3px;
          font-size: 11px;
          color: var(--el-text-color-secondary);
        }
      }

      ul {
        display: grid;
        gap: 10px;
        padding: 0;
        margin: 0;
        list-style: none;
      }

      li {
        gap: 10px;
        padding: 11px 12px;
        background: var(--el-fill-color-extra-light);
        border: 1px solid var(--el-border-color-extra-light);
        border-radius: var(--el-border-radius-small);

        > .art-svg-icon {
          flex: none;
          color: var(--el-color-primary);
        }

        > div {
          display: grid;
          gap: 2px;
        }

        strong {
          font-size: 12px;
          color: var(--el-text-color-primary);
        }

        small {
          font-size: 10px;
          color: var(--el-text-color-secondary);
        }
      }
    }

    &__safe-note {
      gap: 8px;
      padding: 10px 12px;
      font-size: 11px;
      color: var(--el-color-success-dark-2);
      background: var(--el-color-success-light-9);
      border-radius: var(--el-border-radius-small);
    }

    &__source {
      display: grid;
      grid-template-columns: 1.8fr repeat(3, 1fr);
      gap: 10px;
      padding: 14px 17px;

      div,
      .bank-batch__counterparty {
        display: grid;
        gap: 3px;
        min-width: 0;
      }

      small {
        color: var(--el-text-color-secondary);
      }

      strong {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;

      article {
        display: flex;
        gap: 12px;
        align-items: center;
        min-width: 0;
        padding: 14px;
        background: var(--el-bg-color);
        border: 1px solid var(--el-border-color-lighter);
        border-top: 3px solid var(--el-color-primary);
        border-radius: var(--el-border-radius-base);

        > div {
          display: grid;
          gap: 2px;
          min-width: 0;
        }

        &.is-success {
          border-top-color: var(--el-color-success);
        }

        &.is-warning {
          border-top-color: var(--el-color-warning);
        }

        &.is-danger {
          border-top-color: var(--el-color-danger);
        }

        span,
        small {
          font-size: 11px;
          color: var(--el-text-color-secondary);
        }

        strong {
          font-size: 23px;
          font-variant-numeric: tabular-nums;
        }
      }
    }

    &__metric-icon {
      display: grid;
      flex: none;
      place-items: center;
      width: 38px;
      height: 38px;
      font-size: 18px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
    }

    &__table {
      padding: 0;
      overflow: hidden;

      header {
        gap: 16px;
        justify-content: space-between;
        padding: 14px 17px;
        border-bottom: 1px solid var(--el-border-color-lighter);
      }

      h4 {
        margin: 0 0 3px;
      }

      p {
        margin: 0;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__footer {
      gap: 20px;
      justify-content: space-between;
      width: 100%;

      > span {
        display: inline-flex;
        gap: 6px;
        align-items: center;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }

      > div {
        flex: none;
        gap: 10px;
      }
    }

    &__counterparty strong {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .is-risk {
      color: var(--el-color-warning-dark-2);
    }

    @media (width <= 1000px) {
      &__onboarding {
        grid-template-columns: 1fr;
      }

      &__source,
      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (width <= 680px) {
      &__hero header,
      &__footer {
        flex-direction: column;
        align-items: stretch;
      }

      &__steps {
        grid-template-columns: 1fr;
        padding-left: 0;

        > i {
          display: none;
        }
      }

      &__source,
      &__metrics {
        grid-template-columns: 1fr;
      }

      &__footer > div {
        justify-content: flex-end;
      }
    }
  }
</style>
