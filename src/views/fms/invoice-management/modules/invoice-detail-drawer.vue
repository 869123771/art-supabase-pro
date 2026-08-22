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

        <section
          v-if="canViewField(detail.fieldAccess, 'invoiceAttachments')"
          class="invoice-detail__section"
        >
          <ArtSectionTitle>发票附件</ArtSectionTitle>
          <div v-if="attachmentUrls.length" class="invoice-detail__attachments">
            <ElImage
              v-for="(url, index) in attachmentUrls"
              :key="url"
              :src="url"
              :preview-src-list="attachmentUrls"
              :initial-index="index"
              preview-teleported
              fit="cover"
              class="invoice-detail__attachment"
            />
          </div>
          <div v-else class="invoice-detail__restricted">
            {{
              getFieldAccess(detail.fieldAccess, 'invoiceAttachments') === 'masked'
                ? '附件内容已脱敏'
                : '暂无发票附件'
            }}
          </div>
        </section>

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
          <WorkflowBusinessHistory business-type="tms_invoice" :business-id="detail.id" />
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
  import WorkflowBusinessHistory from '@/components/business/workflow-business-history/index.vue'
  import { fetchInvoiceDetail } from '@/api/fms'
  import { canViewField, formatSensitiveNumber, getFieldAccess } from '@/utils/field-permission'

  defineOptions({ name: 'FinanceInvoiceDetailDrawer' })

  type Invoice = Api.Fms.InvoiceRecord
  type StatementLink = NonNullable<Invoice['statementLinks']>[number]

  const drawerRef = ref<ArtDrawerExpose<Invoice>>()
  const detail = shallowRef<Invoice>()
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)
  const attachmentUrls = computed(() =>
    (detail.value?.attachments ?? [])
      .map((item) => (typeof item.url === 'string' ? item.url : ''))
      .filter(Boolean)
  )

  const descriptionItems = computed<ArtDescriptionItem<Invoice>[]>(() => [
    { key: 'invoiceRecordNo', label: '登记单号', field: 'invoiceRecordNo', copyable: true },
    { key: 'status', label: '发票状态', field: 'status', dictCode: 'tmsInvoiceStatus' },
    { key: 'direction', label: '发票方向', field: 'direction', dictCode: 'tmsInvoiceDirection' },
    { key: 'invoiceType', label: '发票类型', field: 'invoiceType', dictCode: 'tmsInvoiceType' },
    { key: 'counterparty', label: '往来单位', field: 'counterpartyNameSnapshot' },
    { key: 'issueDate', label: '开票日期', field: 'issueDate', format: 'date' },
    { key: 'invoiceCode', label: '发票代码', field: 'invoiceCode', copyable: true },
    { key: 'invoiceNo', label: '发票号码', field: 'invoiceNo', copyable: true },
    { key: 'invoiceTitle', label: '发票抬头', field: 'invoiceTitle' },
    ...(canViewField(detail.value?.fieldAccess, 'taxIdentity')
      ? [
          {
            key: 'taxNumber',
            label: '纳税人识别号',
            field: 'taxNumber' as const,
            copyable: detail.value?.taxNumber !== '***'
          }
        ]
      : []),
    ...(canViewField(detail.value?.fieldAccess, 'invoiceAmounts')
      ? [
          {
            key: 'amountExcludingTax',
            label: '不含税金额',
            field: 'amountExcludingTax' as const,
            formatter: (value: unknown) => formatMoney(value as Api.Tms.BasicData.SensitiveNumber)
          },
          {
            key: 'taxRate',
            label: '税率',
            field: 'taxRate' as const,
            formatter: (value: unknown) => formatPercent(value)
          },
          {
            key: 'taxAmount',
            label: '税额',
            field: 'taxAmount' as const,
            formatter: (value: unknown) => formatMoney(value as Api.Tms.BasicData.SensitiveNumber)
          },
          {
            key: 'totalAmount',
            label: '价税合计',
            field: 'totalAmount' as const,
            formatter: (value: unknown) => formatMoney(value as Api.Tms.BasicData.SensitiveNumber)
          },
          {
            key: 'linkedAmount',
            label: '已关联金额',
            field: 'linkedAmount' as const,
            formatter: (value: unknown) => formatMoney(value as Api.Tms.BasicData.SensitiveNumber)
          },
          {
            key: 'unlinkedAmount',
            label: '未关联金额',
            field: 'unlinkedAmount' as const,
            formatter: (value: unknown) => formatMoney(value as Api.Tms.BasicData.SensitiveNumber)
          }
        ]
      : []),
    { key: 'remark', label: '备注', field: 'remark', span: 2 }
  ])

  const statementLinkColumns = computed<ColumnOption<StatementLink>[]>(() => {
    const columns: ColumnOption<StatementLink>[] = [
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
      }
    ]
    if ((detail.value?.statementLinks ?? []).some((row) => row.statementAmount !== undefined)) {
      columns.push({
        prop: 'statementAmount',
        label: '对账金额',
        width: 135,
        align: 'right',
        formatter: (row) => formatStatementMoney(row.statementAmount)
      })
    }
    if (canViewField(detail.value?.fieldAccess, 'invoiceAmounts')) {
      columns.push({
        prop: 'linkedAmount',
        label: '关联金额',
        width: 135,
        align: 'right',
        formatter: (row) => formatMoney(row.linkedAmount)
      })
    }
    return columns
  })

  function formatMoney(value?: Api.Tms.BasicData.SensitiveNumber): string {
    const formatted = formatSensitiveNumber(value)
    return formatted === '***' || formatted === '--' ? formatted : `¥${formatted}`
  }

  function formatPercent(value: unknown): string {
    const formatted = formatSensitiveNumber(value as Api.Tms.BasicData.SensitiveNumber)
    return formatted === '***' || formatted === '--' ? formatted : `${formatted}%`
  }

  function formatStatementMoney(value?: Api.Tms.BasicData.SensitiveNumber): string {
    const formatted = formatSensitiveNumber(value)
    return formatted === '***' || formatted === '--' ? formatted : `¥${formatted}`
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

    &__attachments {
      display: flex;
      flex-wrap: wrap;
      gap: var(--art-space-3);
    }

    &__attachment {
      width: 112px;
      height: 112px;
      border-radius: var(--el-border-radius-base);
    }

    &__restricted {
      padding: var(--art-space-4);
      color: var(--el-text-color-secondary);
      text-align: center;
      background: var(--el-fill-color-light);
      border-radius: var(--el-border-radius-base);
    }
  }
</style>
