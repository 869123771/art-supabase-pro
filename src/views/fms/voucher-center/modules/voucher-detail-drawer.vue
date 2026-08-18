<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <ArtAsyncState
      :loading="loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail"
      empty-text="暂无凭证详情"
      @retry="retryLoad"
    >
      <div v-if="detail" class="voucher-detail">
        <div class="voucher-detail__hero">
          <div>
            <span>{{ detail.accountSet?.accountSetName }}</span>
            <h3>{{ detail.voucherNo }}</h3>
            <p>{{ detail.summary }}</p>
          </div>
          <ElTag :type="statusType(detail.status)" effect="dark" size="large">
            {{ statusLabel(detail.status) }}
          </ElTag>
        </div>

        <ArtSectionTitle>凭证信息</ArtSectionTitle>
        <ArtDescriptions :data="detail" :items="descriptionItems" :columns="2" />

        <section class="voucher-detail__section">
          <ArtSectionTitle>会计分录</ArtSectionTitle>
          <ArtTable
            :data="detail.lines ?? []"
            :columns="lineColumns"
            :pagination="false"
            table-layout="fixed"
            border
            empty-text="暂无会计分录"
          />
          <div class="voucher-detail__totals">
            <strong>借方合计 {{ formatMoney(detail.totalDebit) }}</strong>
            <strong>贷方合计 {{ formatMoney(detail.totalCredit) }}</strong>
          </div>
        </section>

        <section v-if="detail.attachments?.length" class="voucher-detail__section">
          <ArtSectionTitle>原始凭证附件</ArtSectionTitle>
          <div class="voucher-detail__attachments">
            <ElButton
              v-for="attachment in detail.attachments"
              :key="attachment.url"
              plain
              @click="downloadAttachment(attachment)"
            >
              <ArtSvgIcon icon="ri:attachment-2" />{{ attachment.name }}
            </ElButton>
          </div>
        </section>

        <section class="voucher-detail__section">
          <ArtSectionTitle>操作流水</ArtSectionTitle>
          <ElTimeline v-if="detail.actions?.length" class="voucher-detail__timeline">
            <ElTimelineItem
              v-for="item in detail.actions"
              :key="item.id"
              :timestamp="formatTime(item.actionTime)"
              placement="top"
            >
              <div class="voucher-detail__timeline-card">
                <strong>{{ actionLabel(item.action) }}</strong>
                <span>{{ item.actor }}</span>
                <p v-if="item.reason">{{ item.reason }}</p>
              </div>
            </ElTimelineItem>
          </ElTimeline>
          <ElEmpty v-else description="暂无操作流水" :image-size="72" />
        </section>
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import { ElButton, ElEmpty, ElTag, ElTimeline, ElTimelineItem } from 'element-plus'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { fetchVoucherDetail } from '@/api/fms'
  import type { ColumnOption } from '@/types'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import { downloadAttachment } from '@/utils/file'

  defineOptions({ name: 'FinanceVoucherDetailDrawer' })

  type Voucher = Api.Fms.VoucherRecord
  type Line = Api.Fms.VoucherLineRecord

  const drawerRef = ref<ArtDrawerExpose<Voucher>>()
  const detail = shallowRef<Voucher>()
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)

  const descriptionItems: ArtDescriptionItem<Voucher>[] = [
    { key: 'voucherNo', label: '凭证号', field: 'voucherNo', copyable: true },
    { key: 'status', label: '凭证状态', field: 'status', dictCode: 'fmsVoucherStatus' },
    { key: 'voucherDate', label: '凭证日期', field: 'voucherDate', format: 'date' },
    { key: 'voucherType', label: '凭证类型', field: 'voucherType', dictCode: 'fmsVoucherType' },
    {
      key: 'periodNo',
      label: '会计期间',
      field: 'periodNo',
      formatter: (_value, row) => `${row.fiscalYear} 年第 ${row.periodNo} 期`
    },
    { key: 'sourceType', label: '业务来源', field: 'sourceType', dictCode: 'fmsVoucherSourceType' },
    { key: 'sourceNo', label: '来源单号', field: 'sourceNo', copyable: true },
    {
      key: 'lineCount',
      label: '分录数',
      field: 'lineCount',
      formatter: (value) => `${Number(value ?? 0)} 条`
    },
    { key: 'createBy', label: '制单人', field: 'createBy' },
    { key: 'createTime', label: '制单时间', field: 'createTime', format: 'datetime' },
    { key: 'reviewedBy', label: '审核人', field: 'reviewedBy' },
    { key: 'postedBy', label: '过账人', field: 'postedBy' },
    { key: 'reviewComment', label: '审核意见', field: 'reviewComment', span: 2 },
    { key: 'voidReason', label: '作废原因', field: 'voidReason', span: 2 },
    { key: 'reversalReason', label: '冲销原因', field: 'reversalReason', span: 2 }
  ]

  const lineColumns: ColumnOption<Line>[] = [
    { prop: 'lineNo', label: '行号', width: 68, align: 'center', fixed: 'left' },
    { prop: 'summary', label: '摘要', minWidth: 180, showOverflowTooltip: true },
    {
      prop: 'subjectId',
      label: '会计科目',
      minWidth: 220,
      formatter: (row) => `${row.subjectCodeSnapshot} ${row.subjectNameSnapshot}`
    },
    {
      prop: 'currencyCodeSnapshot',
      label: '外币',
      width: 90,
      formatter: (row) => row.currencyCodeSnapshot || '—'
    },
    {
      prop: 'originalAmount',
      label: '原币金额',
      width: 120,
      align: 'right',
      formatter: (row) =>
        row.currencyCodeSnapshot ? Number(row.originalAmount).toLocaleString('zh-CN') : '—'
    },
    {
      prop: 'debitAmount',
      label: '借方金额',
      width: 135,
      align: 'right',
      formatter: (row) => (row.debitAmount ? formatMoney(row.debitAmount) : '—')
    },
    {
      prop: 'creditAmount',
      label: '贷方金额',
      width: 135,
      align: 'right',
      formatter: (row) => (row.creditAmount ? formatMoney(row.creditAmount) : '—')
    }
  ]

  function statusLabel(status: Api.Fms.VoucherStatus): string {
    return {
      draft: '草稿',
      pending_review: '待审核',
      approved: '已审核',
      rejected: '已驳回',
      posted: '已过账',
      reversed: '已冲销',
      voided: '已作废'
    }[status]
  }

  function statusType(
    status: Api.Fms.VoucherStatus
  ): 'success' | 'warning' | 'danger' | 'info' | 'primary' {
    return {
      draft: 'info',
      pending_review: 'warning',
      approved: 'primary',
      rejected: 'danger',
      posted: 'success',
      reversed: 'warning',
      voided: 'info'
    }[status] as 'success' | 'warning' | 'danger' | 'info' | 'primary'
  }

  function actionLabel(action: Api.Fms.VoucherAction): string {
    return {
      create: '创建凭证',
      save: '保存凭证',
      submit: '提交审核',
      approve: '审核通过',
      reject: '审核驳回',
      post: '凭证过账',
      void: '凭证作废',
      reverse: '凭证冲销',
      reversal_create: '生成冲销凭证'
    }[action]
  }

  function formatMoney(value: number): string {
    return formatCurrencyValue(Number(value || 0))
  }

  function formatTime(value: string): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm:ss') ?? '—'
  }

  async function loadDetail(id: string): Promise<void> {
    loading.value = true
    loadError.value = null
    try {
      const { data } = await fetchVoucherDetail(id)
      detail.value = data ?? undefined
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('凭证详情加载失败')
    } finally {
      loading.value = false
    }
  }

  function retryLoad(): void {
    if (detail.value?.id) void loadDetail(detail.value.id)
  }

  async function handleOpen(row: Voucher): Promise<void> {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `会计凭证详情 · ${row.voucherNo}`,
      subtitle: '查看会计分录、业务来源、附件及全生命周期操作记录。',
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: () => loadDetail(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .voucher-detail {
    min-width: 0;

    &__hero {
      display: flex;
      gap: var(--art-space-4);
      align-items: flex-start;
      justify-content: space-between;
      padding: var(--art-space-5);
      margin-bottom: var(--art-space-5);
      color: var(--el-text-color-primary);
      background: linear-gradient(135deg, var(--el-color-primary-light-9), var(--el-bg-color));
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--el-border-radius-base);

      span,
      p {
        color: var(--el-text-color-secondary);
      }

      h3 {
        margin: 4px 0;
        font-size: 24px;
      }

      p {
        margin: 0;
      }
    }

    &__section {
      margin-top: var(--art-space-6);
    }

    &__totals,
    &__attachments {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-3);
    }

    &__totals {
      justify-content: flex-end;
      padding-top: var(--art-space-3);
    }

    &__timeline-card {
      display: grid;
      grid-template-columns: auto 1fr;
      gap: 4px var(--art-space-3);
      padding: var(--art-space-3);
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);

      span {
        color: var(--el-text-color-secondary);
        text-align: right;
      }

      p {
        grid-column: 1 / -1;
        margin: 0;
      }
    }

    @media (width <= 680px) {
      &__hero {
        flex-direction: column;
      }
    }
  }
</style>
