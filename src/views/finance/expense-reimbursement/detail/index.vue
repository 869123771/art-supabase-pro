<template>
  <ArtPageShell
    class="expense-reimbursement-detail"
    :loading="detail.loading"
    loading-mode="skeleton"
    :error="detail.error"
    :empty="detail.loaded && !detail.data"
    empty-text="未找到该费用报销单，或当前账号无权查看"
    @retry="loadDetail"
  >
    <ArtPageHeader
      :title="detail.data?.reimbursementNo || '费用报销详情'"
      subtitle="费用申报、审批、付款与逐笔核销详情"
      show-back
      @back="goBack"
    >
      <template #status>
        <ArtDictDisplay
          v-if="detail.data"
          dict-code="tmsReimbursementApprovalStatus"
          :value="detail.data.status"
          display="tag"
        />
      </template>
      <template #meta>
        <div v-if="detail.data" class="expense-reimbursement-detail__header-meta">
          <span>
            <ArtSvgIcon icon="ri:user-3-line" aria-hidden="true" />
            {{ detail.data.applicantNameSnapshot || '申请人待补充' }}
          </span>
          <span>
            <ArtSvgIcon icon="ri:calendar-event-line" aria-hidden="true" />
            计划付款 {{ formatDate(detail.data.plannedPaymentDate) }}
          </span>
          <span>
            <ArtSvgIcon icon="ri:time-line" aria-hidden="true" />
            更新于 {{ formatDateTime(detail.data.updateTime) }}
          </span>
        </div>
      </template>
      <ElButton v-if="primaryWaybillId" @click="openPrimaryWaybill">
        <ArtSvgIcon icon="ri:route-line" aria-hidden="true" />
        查看关联运单
      </ElButton>
    </ArtPageHeader>

    <section v-if="detail.data" class="expense-reimbursement-detail__overview art-card-xs">
      <article v-for="item in overviewItems" :key="item.label">
        <span :class="`is-${item.tone}`">
          <ArtSvgIcon :icon="item.icon" aria-hidden="true" />
        </span>
        <div>
          <small>{{ item.label }}</small>
          <strong :title="item.value">{{ item.value }}</strong>
          <p>{{ item.hint }}</p>
        </div>
      </article>
    </section>

    <div v-if="detail.data" class="expense-reimbursement-detail__content">
      <section class="expense-reimbursement-detail__section art-card-xs">
        <ArtSectionTitle>报销信息</ArtSectionTitle>
        <ArtDescriptions
          :data="detail.data"
          :items="reimbursementItems"
          :columns="descriptionColumns"
        />
      </section>

      <section class="expense-reimbursement-detail__section art-card-xs">
        <ArtSectionTitle>审批与付款</ArtSectionTitle>
        <ArtDescriptions
          :data="detail.data"
          :items="approvalPaymentItems"
          :columns="descriptionColumns"
        />
      </section>

      <section class="expense-reimbursement-detail__section art-card-xs">
        <ArtSectionTitle>逐笔核销明细</ArtSectionTitle>
        <ArtTable
          :data="detail.data.items ?? []"
          :columns="expenseColumns"
          :pagination="false"
          :show-table-header="false"
          table-layout="fixed"
          border
        />
        <div v-if="!detail.data.items?.length" class="expense-reimbursement-detail__empty-inline">
          <ArtSvgIcon icon="ri:file-damage-line" aria-hidden="true" />
          当前报销单暂无费用明细
        </div>
      </section>

      <section class="expense-reimbursement-detail__section art-card-xs">
        <ArtSectionTitle>报销与付款凭证</ArtSectionTitle>
        <div class="expense-reimbursement-detail__evidence-grid">
          <div>
            <h3>报销依据</h3>
            <div v-if="basisFiles.length" class="expense-reimbursement-detail__attachments">
              <div
                v-for="file in basisFiles"
                :key="file.url"
                class="expense-reimbursement-detail__attachment"
              >
                <span><ArtSvgIcon icon="ri:attachment-2" aria-hidden="true" /></span>
                <ArtAttachmentLink :file="file" />
              </div>
            </div>
            <div v-else class="expense-reimbursement-detail__empty-inline">
              <ArtSvgIcon icon="ri:file-damage-line" aria-hidden="true" />
              未上传报销依据
            </div>
          </div>
          <div>
            <h3>付款凭证</h3>
            <div v-if="paymentFiles.length" class="expense-reimbursement-detail__attachments">
              <div
                v-for="file in paymentFiles"
                :key="file.url"
                class="expense-reimbursement-detail__attachment"
              >
                <span><ArtSvgIcon icon="ri:bank-card-line" aria-hidden="true" /></span>
                <ArtAttachmentLink :file="file" />
              </div>
            </div>
            <div v-else class="expense-reimbursement-detail__empty-inline">
              <ArtSvgIcon icon="ri:file-damage-line" aria-hidden="true" />
              尚未形成付款凭证
            </div>
          </div>
        </div>
      </section>

      <section v-if="detail.data.id" class="expense-reimbursement-detail__section art-card-xs">
        <WorkflowBusinessHistory
          business-type="tms_expense_reimbursement"
          :business-id="detail.data.id"
        />
      </section>
    </div>
  </ArtPageShell>
</template>

<script setup lang="tsx">
  import { RouterLink } from 'vue-router'
  import { useMediaQuery } from '@vueuse/core'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import type { FilePreviewTarget } from '@/hooks/core/useFilePreview'
  import type { ColumnOption } from '@/types'
  import ArtAttachmentLink from '@/components/core/media/art-file-viewer/attachment-link.vue'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import ArtDictDisplay from '@/components/core/base/art-dict-display/index.vue'
  import ArtPageHeader from '@/components/core/layouts/art-page-header/index.vue'
  import ArtPageShell from '@/components/core/layouts/art-page-shell/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import WorkflowBusinessHistory from '@/components/business/workflow-business-history/index.vue'
  import { fetchExpenseReimbursementDetail } from '@/api/finance'
  import { getWaybillCostDetailPath } from '@/router/business-paths'
  import { formatWithDayjs } from '@/utils/time'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'FinanceExpenseReimbursementDetail' })

  type Reimbursement = Api.Finance.ExpenseReimbursementRecord
  type ExpenseItem = Api.Finance.ExpenseReimbursementItem

  interface DetailState {
    data?: Reimbursement
    error: Error | null
    loaded: boolean
    loading: boolean
  }

  interface OverviewItem {
    label: string
    value: string
    hint: string
    icon: string
    tone: 'primary' | 'success' | 'warning' | 'info'
  }

  const route = useRoute()
  const router = useRouter()
  const isMobile = useMediaQuery('(max-width: 640px)')
  const isNarrow = useMediaQuery('(max-width: 1100px)')
  const detail = reactive<DetailState>({
    data: undefined,
    error: null,
    loaded: false,
    loading: false
  })

  const descriptionColumns = computed(() => (isMobile.value ? 1 : isNarrow.value ? 2 : 4))
  const primaryWaybillId = computed(() => detail.data?.items?.[0]?.waybillId)
  const basisFiles = computed<FilePreviewTarget[]>(() =>
    createFiles(detail.data?.basisUrls, '报销依据')
  )
  const paymentFiles = computed<FilePreviewTarget[]>(() =>
    createFiles(detail.data?.paymentVoucherUrls, '付款凭证')
  )
  const overviewItems = computed<OverviewItem[]>(() => [
    {
      label: '报销金额',
      value: money(detail.data?.totalAmount),
      hint: '本单申请报销总额',
      icon: 'ri:money-cny-circle-line',
      tone: 'primary'
    },
    {
      label: '费用笔数',
      value: `${detail.data?.itemCount ?? 0} 笔`,
      hint: '逐笔保留费用快照',
      icon: 'ri:file-list-3-line',
      tone: 'warning'
    },
    {
      label: '关联运单',
      value: detail.data?.waybillNos || `${detail.data?.waybillCount ?? 0} 单`,
      hint: '同一运单费用集中报销',
      icon: 'ri:truck-line',
      tone: 'success'
    },
    {
      label: '付款进度',
      value: detail.data?.paymentNo || (detail.data?.status === 'paid' ? '已支付' : '待支付'),
      hint: detail.data?.paymentReference || '付款后自动逐笔核销',
      icon: 'ri:secure-payment-line',
      tone: 'info'
    }
  ])

  const reimbursementItems: ArtDescriptionItem<Reimbursement>[] = [
    { key: 'reimbursementNo', label: '报销单号', field: 'reimbursementNo', copyable: true },
    { key: 'applicantName', label: '申请人', field: 'applicantNameSnapshot' },
    { key: 'payeeName', label: '收款人', field: 'payeeName' },
    { key: 'totalAmount', label: '报销金额', field: 'totalAmount', format: 'money' },
    {
      key: 'paymentMethod',
      label: '付款方式',
      field: 'paymentMethod',
      dictCode: 'tmsCashPaymentMethod'
    },
    {
      key: 'plannedPaymentDate',
      label: '计划付款日',
      field: 'plannedPaymentDate',
      format: 'date'
    },
    { key: 'payeeBank', label: '收款银行', field: 'payeeBank' },
    { key: 'payeeAccount', label: '收款账号', field: 'payeeAccount', copyable: true },
    { key: 'remark', label: '报销说明', field: 'remark', span: 4 }
  ]

  const approvalPaymentItems: ArtDescriptionItem<Reimbursement>[] = [
    {
      key: 'status',
      label: '审批/支付状态',
      field: 'status',
      dictCode: 'tmsReimbursementApprovalStatus'
    },
    { key: 'submittedAt', label: '提交时间', field: 'submittedAt', format: 'datetime' },
    { key: 'submittedBy', label: '提交人', field: 'submittedBy' },
    { key: 'reviewedAt', label: '审批完成时间', field: 'reviewedAt', format: 'datetime' },
    { key: 'reviewedBy', label: '最终审批人', field: 'reviewedBy' },
    { key: 'reviewRemark', label: '审批意见', field: 'reviewRemark', span: 2 },
    { key: 'paymentNo', label: '付款单号', field: 'paymentNo', copyable: true },
    {
      key: 'paymentReference',
      label: '银行流水号',
      field: 'paymentReference',
      copyable: true
    },
    { key: 'paidAt', label: '付款时间', field: 'paidAt', format: 'datetime' },
    { key: 'paidBy', label: '付款登记人', field: 'paidBy' },
    { key: 'createTime', label: '创建时间', field: 'createTime', format: 'datetime' },
    { key: 'updateTime', label: '最后更新', field: 'updateTime', format: 'datetime' }
  ]

  const expenseColumns: ColumnOption<ExpenseItem>[] = [
    {
      prop: 'costNoSnapshot',
      label: '费用单号',
      minWidth: 190,
      formatter: (row) => (
        <RouterLink
          class="expense-reimbursement-detail__document-link"
          to={getWaybillCostDetailPath(row.costId)}
        >
          {row.costNoSnapshot || '--'}
        </RouterLink>
      )
    },
    {
      prop: 'waybillNoSnapshot',
      label: '运单号',
      minWidth: 180,
      formatter: (row) => (
        <RouterLink
          class="expense-reimbursement-detail__document-link"
          to={{ name: 'TmsWaybillDetail', params: { id: row.waybillId } }}
        >
          {row.waybillNoSnapshot || '--'}
        </RouterLink>
      )
    },
    {
      prop: 'expenseItemNameSnapshot',
      label: '费用项目',
      minWidth: 150,
      formatter: (row) => row.expenseItemNameSnapshot || '--'
    },
    {
      prop: 'occurredOnSnapshot',
      label: '发生日期',
      width: 125,
      formatter: (row) => formatDate(row.occurredOnSnapshot)
    },
    {
      prop: 'amountSnapshot',
      label: '核销金额',
      width: 140,
      align: 'right',
      formatter: (row) => money(row.amountSnapshot)
    }
  ]

  onMounted(() => {
    void loadDetail()
  })

  async function loadDetail(): Promise<void> {
    const reimbursementId = String(route.params.id || '')
    if (!reimbursementId) {
      Object.assign(detail, { error: new Error('缺少报销单标识'), loaded: true })
      return
    }

    detail.loading = true
    detail.error = null
    try {
      const { data } = await fetchExpenseReimbursementDetail(reimbursementId)
      detail.data = data
    } catch (error) {
      detail.error = error instanceof Error ? error : new Error('报销详情加载失败，请稍后重试')
    } finally {
      detail.loaded = true
      detail.loading = false
    }
  }

  function createFiles(urls: string[] | undefined, prefix: string): FilePreviewTarget[] {
    return (urls ?? []).map((url, index) => ({ url, name: `${prefix} ${index + 1}` }))
  }

  function openPrimaryWaybill(): void {
    if (!primaryWaybillId.value) return
    void router.push({ name: 'TmsWaybillDetail', params: { id: primaryWaybillId.value } })
  }

  function goBack(): void {
    void router.back()
  }

  function money(value?: number | null): string {
    return formatCurrencyValue(Number(value ?? 0))
  }

  function formatDate(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD') || '--'
  }

  function formatDateTime(value?: string | null): string {
    return formatWithDayjs(value, 'YYYY-MM-DD HH:mm') || '--'
  }
</script>

<style scoped lang="scss">
  .expense-reimbursement-detail {
    min-height: 100%;
    padding: 12px 16px 18px;
    background: var(--art-main-bg-color);

    &__header-meta,
    &__attachments,
    &__attachment,
    &__empty-inline {
      display: flex;
      align-items: center;
    }

    &__header-meta {
      flex-wrap: wrap;
      gap: var(--art-space-3);

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
      }
    }

    &__overview {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      padding: 0;
      margin-top: var(--art-space-3);
      overflow: hidden;

      article {
        display: flex;
        gap: var(--art-space-3);
        min-width: 0;
        padding: var(--art-space-4);

        &:not(:last-child) {
          border-right: 1px solid var(--el-border-color-lighter);
        }

        > span {
          display: grid;
          flex: none;
          place-items: center;
          width: 42px;
          height: 42px;
          font-size: 20px;
          border-radius: var(--el-border-radius-base);

          &.is-primary {
            color: var(--el-color-primary);
            background: var(--el-color-primary-light-9);
          }

          &.is-success {
            color: var(--el-color-success);
            background: var(--el-color-success-light-9);
          }

          &.is-warning {
            color: var(--el-color-warning);
            background: var(--el-color-warning-light-9);
          }

          &.is-info {
            color: var(--el-color-info);
            background: var(--el-color-info-light-9);
          }
        }

        > div {
          display: grid;
          gap: 2px;
          min-width: 0;
        }

        small,
        p {
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 17px;
          font-variant-numeric: tabular-nums;
          color: var(--el-text-color-primary);
          white-space: nowrap;
        }

        p {
          margin: 0;
          font-size: 11px;
        }
      }
    }

    &__content {
      display: flex;
      flex-direction: column;
      gap: var(--art-space-3);
      margin-top: var(--art-space-3);
    }

    &__section {
      min-width: 0;
      padding: var(--art-space-5);
    }

    &__evidence-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: var(--art-space-5);

      > div {
        min-width: 0;
      }

      h3 {
        margin: 0 0 var(--art-space-3);
        font-size: var(--art-font-size-body);
        color: var(--el-text-color-regular);
      }
    }

    &__attachments {
      flex-wrap: wrap;
      gap: var(--art-space-3);
    }

    &__attachment {
      gap: var(--art-space-2);
      min-width: 180px;
      max-width: 100%;
      padding: 10px 12px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > span {
        display: grid;
        flex: none;
        place-items: center;
        width: 30px;
        height: 30px;
        color: var(--theme-color);
        background: color-mix(in srgb, var(--theme-color) 9%, transparent);
        border-radius: var(--el-border-radius-small);
      }
    }

    &__empty-inline {
      gap: var(--art-space-2);
      min-height: 40px;
      color: var(--el-text-color-secondary);
    }

    :deep(.expense-reimbursement-detail__document-link) {
      display: inline-block;
      max-width: 100%;
      overflow: hidden;
      text-overflow: ellipsis;
      font-weight: 600;
      color: var(--theme-color);
      white-space: nowrap;
      text-decoration: none;

      &:hover {
        text-decoration: underline;
        text-underline-offset: 3px;
      }

      &:focus-visible {
        outline: 2px solid var(--theme-color);
        outline-offset: 2px;
        border-radius: var(--el-border-radius-small);
      }
    }

    :deep(.art-descriptions .el-descriptions__label) {
      width: 132px;
      font-weight: 600;
    }

    @media (width <= 1100px) {
      &__overview {
        grid-template-columns: repeat(2, minmax(0, 1fr));

        article:nth-child(2) {
          border-right: 0;
        }

        article:nth-child(-n + 2) {
          border-bottom: 1px solid var(--el-border-color-lighter);
        }
      }
    }

    @media (width <= 767px) {
      &__evidence-grid {
        grid-template-columns: 1fr;
      }
    }

    @media (width <= 640px) {
      padding-inline: 10px;

      &__overview {
        grid-template-columns: 1fr;

        article {
          border-right: 0 !important;

          &:not(:last-child) {
            border-bottom: 1px solid var(--el-border-color-lighter);
          }
        }
      }

      &__section {
        padding: var(--art-space-4);
      }
    }
  }
</style>
