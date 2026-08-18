<template>
  <ArtDrawer ref="drawerRef" :show-footer="false">
    <ArtAsyncState
      :loading="loading"
      loading-mode="skeleton"
      :error="loadError"
      :empty="!detail"
      empty-text="暂无自动入账事件详情"
      @retry="retryLoad"
    >
      <div v-if="detail" class="posting-event-detail">
        <div class="posting-event-detail__hero">
          <div>
            <span>{{ detail.accountSet?.accountSetName || '待匹配账套' }}</span>
            <h3>{{ detail.sourceNo || detail.id }}</h3>
            <p>{{ detail.summary }}</p>
          </div>
          <ElTag :type="statusType(detail.status)" effect="dark" size="large">
            {{ statusLabel(detail.status) }}
          </ElTag>
        </div>

        <ArtSectionTitle>处理信息</ArtSectionTitle>
        <ArtDescriptions :data="detail" :items="descriptionItems" :columns="2" />

        <section v-if="detail.lastError" class="posting-event-detail__section">
          <ArtSectionTitle>异常信息</ArtSectionTitle>
          <ElAlert type="error" :closable="false" show-icon :title="detail.lastError" />
        </section>

        <section class="posting-event-detail__section">
          <ArtSectionTitle>业务事件载荷</ArtSectionTitle>
          <ArtTable
            :data="payloadRows"
            :columns="payloadColumns"
            :pagination="false"
            table-layout="fixed"
            border
            empty-text="暂无业务载荷"
          />
        </section>

        <section v-if="detail.voucherId" class="posting-event-detail__voucher art-card-xs">
          <div>
            <strong>{{ detail.voucher?.voucherNo || '已生成会计凭证' }}</strong>
            <span>凭证状态与后续审核、过账仍由凭证中心统一控制。</span>
          </div>
          <ElButton type="primary" plain @click="emit('view-voucher', detail.voucherId)">
            查看凭证
          </ElButton>
        </section>
      </div>
    </ArtAsyncState>
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import { ElButton, ElTag } from 'element-plus'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtDescriptions from '@/components/core/base/art-descriptions/index.vue'
  import type { ArtDescriptionItem } from '@/components/core/base/art-descriptions/types'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import type { ColumnOption } from '@/types'
  import { fetchPostingEventDetail } from '@/api/fms'

  defineOptions({ name: 'FinancePostingEventDetailDrawer' })

  type Event = Api.Fms.PostingEventRecord

  interface PayloadRow {
    key: string
    label: string
    value: string
  }

  const emit = defineEmits<{ 'view-voucher': [voucherId: string] }>()
  const drawerRef = ref<ArtDrawerExpose<Event>>()
  const detail = shallowRef<Event>()
  const loading = ref(false)
  const loadError = shallowRef<Error | null>(null)

  const payloadLabelMap: Record<string, string> = {
    gross_amount: '业务总额',
    net_amount: '不含税金额',
    tax_amount: '税额',
    customer_id: '客户 ID',
    carrier_id: '承运商 ID',
    applicant_user_id: '报销申请人 ID',
    waybill_id: '运单 ID',
    driver_id: '司机 ID',
    expense_item_id: '费用项目 ID',
    customer_name: '客户名称',
    carrier_name: '承运商名称',
    counterparty_name: '往来方名称',
    payee_name: '收款方',
    payment_method: '收付方式',
    invoice_no: '发票号码',
    tax_rate: '税率',
    cost_type: '费用类型',
    waybill_no: '运单号'
  }

  const descriptionItems: ArtDescriptionItem<Event>[] = [
    {
      key: 'sourceEvent',
      label: '业务事件',
      field: 'sourceEvent',
      dictCode: 'fmsPostingSourceEvent'
    },
    { key: 'eventDate', label: '业务日期', field: 'eventDate', format: 'date' },
    { key: 'status', label: '处理状态', field: 'status', dictCode: 'fmsPostingEventStatus' },
    {
      key: 'attemptCount',
      label: '处理次数',
      field: 'attemptCount',
      formatter: (value) => `${Number(value ?? 0)} 次`
    },
    {
      key: 'rule',
      label: '命中规则',
      field: 'rule',
      formatter: (_value, row) =>
        row.rule ? `${row.rule.ruleCode} · ${row.rule.ruleName}` : '未命中规则'
    },
    {
      key: 'voucher',
      label: '生成凭证',
      field: 'voucher',
      formatter: (_value, row) => row.voucher?.voucherNo || '—'
    },
    { key: 'createBy', label: '事件发起人', field: 'createBy' },
    { key: 'createTime', label: '捕获时间', field: 'createTime', format: 'datetime' },
    { key: 'processedAt', label: '处理时间', field: 'processedAt', format: 'datetime' },
    { key: 'sourceId', label: '来源数据 ID', field: 'sourceId', copyable: true }
  ]

  const payloadRows = computed<PayloadRow[]>(() =>
    Object.entries(detail.value?.payload ?? {}).map(([key, value]) => ({
      key,
      label: payloadLabelMap[key] ?? key,
      value: value == null ? '—' : typeof value === 'object' ? JSON.stringify(value) : String(value)
    }))
  )

  const payloadColumns: ColumnOption<PayloadRow>[] = [
    { prop: 'label', label: '字段', minWidth: 150 },
    { prop: 'key', label: '技术字段', minWidth: 180, showOverflowTooltip: true },
    { prop: 'value', label: '业务值', minWidth: 260, showOverflowTooltip: true }
  ]

  function statusLabel(status: Api.Fms.PostingEventStatus): string {
    return {
      pending: '待处理',
      processing: '处理中',
      generated: '已生成凭证',
      pending_configuration: '待配置',
      failed: '生成失败',
      reversed: '已冲销',
      ignored: '无需处理'
    }[status]
  }

  function statusType(
    status: Api.Fms.PostingEventStatus
  ): 'success' | 'warning' | 'danger' | 'info' | 'primary' {
    return {
      pending: 'info',
      processing: 'primary',
      generated: 'success',
      pending_configuration: 'warning',
      failed: 'danger',
      reversed: 'warning',
      ignored: 'info'
    }[status] as 'success' | 'warning' | 'danger' | 'info' | 'primary'
  }

  async function loadDetail(id: string): Promise<void> {
    loading.value = true
    loadError.value = null
    try {
      const { data } = await fetchPostingEventDetail(id)
      detail.value = data ?? undefined
    } catch (error) {
      loadError.value = error instanceof Error ? error : new Error('自动入账事件详情加载失败')
    } finally {
      loading.value = false
    }
  }

  function retryLoad(): void {
    if (detail.value?.id) void loadDetail(detail.value.id)
  }

  async function handleOpen(row: Event): Promise<void> {
    detail.value = row
    await drawerRef.value?.handleOpen(row, {
      title: `自动入账事件 · ${row.sourceNo || row.id}`,
      subtitle: '查看规则命中、凭证生成、错误原因与业务事件载荷。',
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      onOpen: () => loadDetail(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .posting-event-detail {
    min-width: 0;

    &__hero {
      display: flex;
      gap: var(--art-space-4);
      align-items: flex-start;
      justify-content: space-between;
      padding: var(--art-space-5);
      margin-bottom: var(--art-space-5);
      background: linear-gradient(135deg, var(--el-color-primary-light-9), var(--el-bg-color));
      border: 1px solid var(--el-color-primary-light-7);
      border-radius: var(--el-border-radius-base);

      span,
      p {
        color: var(--el-text-color-secondary);
      }

      h3 {
        margin: 4px 0;
        font-size: 22px;
        overflow-wrap: anywhere;
      }

      p {
        margin: 0;
      }
    }

    &__section {
      margin-top: var(--art-space-6);
    }

    &__voucher {
      display: flex;
      gap: var(--art-space-4);
      align-items: center;
      justify-content: space-between;
      padding: var(--art-space-4);
      margin-top: var(--art-space-6);
      border: 1px solid var(--el-border-color-lighter);

      div {
        display: flex;
        flex-direction: column;
        gap: 4px;
      }

      span {
        font-size: 13px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 640px) {
      &__hero,
      &__voucher {
        flex-direction: column;
        align-items: flex-start;
      }
    }
  }
</style>
