<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <ArtAsyncState
      :loading="loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail"
      empty-text="暂无发票详情"
      @retry="retryLoad"
    >
      <div v-if="detail" class="invoice-detail">
        <ArtSectionTitle>发票信息</ArtSectionTitle>
        <ArtDescriptions :data="detail" :items="descriptionItems" :columns="2" />

        <section class="invoice-detail__section">
          <ArtSectionTitle>关联对账单</ArtSectionTitle>
          <ArtTable
            :data="detail.statementLinks ?? []"
            :columns="statementLinkColumns"
            :pagination="false"
            :show-table-header="false"
            table-layout="fixed"
            empty-height="180px"
            max-height="360px"
            empty-text="暂未关联对账单"
            border
          />
        </section>

        <section class="invoice-detail__section">
          <ArtProcessTimeline
            :items="processTimelineItems"
            title="处理记录"
            summary="完整业务操作轨迹"
            empty-description="发票发生登记、复核或作废动作后，记录会自动展示在这里。"
          />
        </section>
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import type { ColumnOption } from '@/types'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtProcessTimeline from '@/components/core/layouts/art-process-timeline/index.vue'
  import type { ArtProcessTimelineItem } from '@/components/core/layouts/art-process-timeline/types'
  import { fetchInvoiceDetail } from '@/api/tms'
  import { formatCurrencyValue } from '@/utils/ui'

  defineOptions({ name: 'TmsInvoiceDetailDrawer' })

  type Invoice = Api.Tms.Finance.InvoiceRecord
  type StatementLink = NonNullable<Invoice['statementLinks']>[number]

  const drawerRef = ref<ArtDrawerExpose<Invoice>>()
  const detail = shallowRef<Invoice>()
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)

  const processTimelineItems = computed<ArtProcessTimelineItem[]>(() => {
    if (!detail.value) return []

    const invoice = detail.value
    const items: ArtProcessTimelineItem[] = [
      {
        id: `${invoice.id}-created`,
        actorName: invoice.createBy || '系统用户',
        actionLabel: '登记',
        title: '登记发票',
        time: invoice.createTime,
        tone: 'primary',
        system: !invoice.createBy
      }
    ]

    if (invoice.submittedAt) {
      items.push({
        id: `${invoice.id}-submitted`,
        actorName: invoice.submittedBy || '系统用户',
        actionLabel: '提交复核',
        title: '发起财务复核',
        time: invoice.submittedAt,
        tone: 'warning',
        system: !invoice.submittedBy
      })
    }

    if (invoice.reviewedAt) {
      const rejected = invoice.status === 'draft'
      items.push({
        id: `${invoice.id}-reviewed`,
        actorName: invoice.reviewedBy || '系统用户',
        actionLabel: rejected ? '复核驳回' : '复核通过',
        title: rejected ? '财务复核未通过' : '完成财务复核',
        description: invoice.reviewRemark,
        time: invoice.reviewedAt,
        tone: rejected ? 'danger' : 'success',
        system: !invoice.reviewedBy
      })
    }

    if (invoice.voidedAt) {
      items.push({
        id: `${invoice.id}-voided`,
        actorName: invoice.voidedBy || '系统用户',
        actionLabel: '作废',
        title: '作废发票',
        description: invoice.voidReason,
        time: invoice.voidedAt,
        tone: 'danger',
        system: !invoice.voidedBy
      })
    }

    return items
  })

  const descriptionItems: ArtDescriptionItem<Invoice>[] = [
    { key: 'invoiceRecordNo', label: '登记单号', field: 'invoiceRecordNo', copyable: true },
    { key: 'status', label: '发票状态', field: 'status', dictCode: 'tmsInvoiceStatus' },
    { key: 'direction', label: '发票方向', field: 'direction', dictCode: 'tmsInvoiceDirection' },
    { key: 'invoiceType', label: '发票类型', field: 'invoiceType', dictCode: 'tmsInvoiceType' },
    { key: 'counterparty', label: '往来单位', field: 'counterpartyNameSnapshot' },
    { key: 'issueDate', label: '开票日期', field: 'issueDate', format: 'date' },
    { key: 'invoiceCode', label: '发票代码', field: 'invoiceCode', copyable: true },
    { key: 'invoiceNo', label: '发票号码', field: 'invoiceNo', copyable: true },
    { key: 'invoiceTitle', label: '发票抬头', field: 'invoiceTitle' },
    { key: 'taxNumber', label: '纳税人识别号', field: 'taxNumber', copyable: true },
    {
      key: 'amountExcludingTax',
      label: '不含税金额',
      field: 'amountExcludingTax',
      format: 'money'
    },
    {
      key: 'taxRate',
      label: '税率',
      field: 'taxRate',
      formatter: (value) => `${Number(value ?? 0).toFixed(2)}%`
    },
    { key: 'taxAmount', label: '税额', field: 'taxAmount', format: 'money' },
    { key: 'totalAmount', label: '价税合计', field: 'totalAmount', format: 'money' },
    { key: 'linkedAmount', label: '已关联金额', field: 'linkedAmount', format: 'money' },
    { key: 'unlinkedAmount', label: '未关联金额', field: 'unlinkedAmount', format: 'money' },
    { key: 'remark', label: '备注', field: 'remark', span: 2 }
  ]

  const statementLinkColumns: ColumnOption<StatementLink>[] = [
    { prop: 'statementNo', label: '对账单号', minWidth: 180 },
    {
      prop: 'counterpartyName',
      label: '往来单位',
      minWidth: 180,
      showOverflowTooltip: true
    },
    {
      prop: 'periodLabel',
      label: '账期',
      width: 205,
      formatter: (row) => `${row.periodStart} 至 ${row.periodEnd}`
    },
    {
      prop: 'statementAmount',
      label: '对账金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.statementAmount)
    },
    {
      prop: 'linkedAmount',
      label: '关联金额',
      width: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.linkedAmount)
    }
  ]

  function formatMoney(value?: number | null): string {
    return formatCurrencyValue(value ?? 0)
  }

  async function loadDetail(id: string): Promise<void> {
    loading.value = true
    loadError.value = null
    try {
      const { data } = await fetchInvoiceDetail(id)
      detail.value = data ?? undefined
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('发票详情加载失败')
    } finally {
      loading.value = false
    }
  }

  function retryLoad(): void {
    if (detail.value?.id) void loadDetail(detail.value.id)
  }

  async function handleOpen(row: Invoice): Promise<void> {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `发票详情 · ${row.invoiceNo || row.invoiceRecordNo}`,
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: () => loadDetail(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .invoice-detail {
    &__section {
      margin-top: var(--art-space-6);
    }
  }
</style>
