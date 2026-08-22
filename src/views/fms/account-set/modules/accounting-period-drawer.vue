<template>
  <ArtDrawer ref="drawerRef">
    <ArtAsyncState
      :loading="state.loading"
      loading-mode="skeleton"
      :error="state.error"
      :empty="!state.accountSet"
      empty-text="暂无账套期间信息"
      @retry="retryLoad"
    >
      <div v-if="state.accountSet" class="accounting-period-drawer">
        <section class="accounting-period-drawer__overview">
          <article
            v-for="metric in overviewMetrics"
            :key="metric.label"
            class="accounting-period-drawer__metric art-card-xs"
          >
            <ArtSvgIcon :icon="metric.icon" />
            <div>
              <strong>{{ metric.value }}</strong>
              <span>{{ metric.label }}</span>
            </div>
          </article>
        </section>

        <ArtSectionTitle>会计期间</ArtSectionTitle>
        <p class="accounting-period-drawer__hint">
          {{ periodPolicyHint }}
        </p>

        <ArtTable
          :data="state.periods"
          :columns="columns"
          :pagination="false"
          :show-table-header="false"
          empty-text="暂无会计期间"
          border
        />
      </div>
    </ArtAsyncState>

    <template #footer="{ api }">
      <ElButton @click="api.handleClose()">关闭</ElButton>
    </template>
  </ArtDrawer>
</template>

<script setup lang="tsx">
  import { ElButton } from 'element-plus'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtTable from '@/components/core/tables/art-table/index.vue'
  import ArtSectionTitle from '@/components/core/forms/art-section-title/index.vue'
  import type { ColumnOption } from '@/types'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'
  import {
    fetchAccountingFoundationSummary,
    fetchAccountingPeriodList,
    setAccountingPeriodStatus
  } from '@/api/fms'
  import { formatWithDayjs } from '@/utils/time'
  import { getFieldAccess } from '@/utils/field-permission'

  defineOptions({ name: 'FinanceAccountingPeriodDrawer' })

  type AccountSet = Api.Fms.AccountSetRecord
  type AccountingPeriod = Api.Fms.AccountingPeriodRecord
  type FoundationSummary = Api.Fms.AccountingFoundationSummary

  interface DrawerState {
    accountSet?: AccountSet
    periods: AccountingPeriod[]
    summary?: FoundationSummary
    loading: boolean
    error: Error | null
  }

  const { confirmAction, promptReason } = useArtFeedback()
  const { hasAuth } = useAuth()
  const drawerRef = ref<ArtDrawerExpose<AccountSet>>()
  const state = reactive<DrawerState>({
    accountSet: undefined,
    periods: [],
    summary: undefined,
    loading: false,
    error: null
  })

  const overviewMetrics = computed(() => [
    {
      label: '会计科目',
      value: state.summary?.subjectCount ?? 0,
      icon: 'ri:node-tree'
    },
    {
      label: '启用币别',
      value: state.summary?.currencyCount ?? 0,
      icon: 'ri:exchange-dollar-line'
    },
    {
      label: '开启期间',
      value: state.summary?.openPeriodCount ?? 0,
      icon: 'ri:calendar-check-line'
    },
    {
      label: '已结期间',
      value: state.summary?.closedPeriodCount ?? 0,
      icon: 'ri:lock-2-line'
    }
  ])

  const periodPolicyHint = computed(() => {
    const accountSet = state.accountSet
    if (!accountSet) return ''
    const policyAccess = getFieldAccess(accountSet.fieldAccess, 'accountingPolicy')
    if (!['read', 'edit'].includes(policyAccess)) {
      return '账套启用月份、会计年度起始月和本位币受字段权限保护；期间状态与操作仍按期间按钮权限执行。'
    }
    const enabledMonth = formatWithDayjs(accountSet.enabledOn, 'YYYY-MM')
    return `当前配置：账套启用月份 ${enabledMonth}，会计年度从 ${accountSet.fiscalYearStartMonth} 月开始。两者是不同口径；期间必须按时间顺序结账，反结账需从最后一个已结期间开始。`
  })

  const columns = computed<ColumnOption<AccountingPeriod>[]>(() => [
    {
      prop: 'periodNo',
      label: '期间',
      width: 132,
      formatter: (row) => (
        <div
          class="accounting-period-drawer__period"
          title={`${row.fiscalYear} 会计年度第 ${row.periodNo} 期`}
        >
          <strong>第 {String(row.periodNo).padStart(2, '0')} 期</strong>
          <span>{row.fiscalYear} 会计年度</span>
        </div>
      )
    },
    {
      prop: 'dateRange',
      label: '起止日期',
      minWidth: 210,
      formatter: (row) => `${row.startDate} 至 ${row.endDate}`
    },
    {
      prop: 'status',
      label: '状态',
      width: 105,
      dict: { code: 'fmsAccountingPeriodStatus', display: 'tag' }
    },
    {
      prop: 'closedBy',
      label: '最近结账',
      minWidth: 190,
      formatter: (row) =>
        row.closedAt
          ? `${row.closedBy || '系统'} · ${formatWithDayjs(row.closedAt, 'YYYY-MM-DD HH:mm')}`
          : '--'
    },
    {
      prop: 'reopenCount',
      label: '反结账',
      width: 85,
      align: 'center',
      formatter: (row) => `${row.reopenCount} 次`
    },
    ...(hasAuth('FinanceAccountSet:ManagePeriod')
      ? [
          {
            prop: 'operation',
            label: '操作',
            width: 190,
            fixed: 'right' as const,
            formatter: (row: AccountingPeriod) => renderPeriodActions(row)
          } satisfies ColumnOption<AccountingPeriod>
        ]
      : [])
  ])

  function renderPeriodActions(row: AccountingPeriod) {
    if (row.status === 'not_opened') {
      return (
        <ElButton link type="primary" onClick={() => void changeStatus(row, 'open')}>
          启用期间
        </ElButton>
      )
    }
    if (row.status === 'open') {
      return (
        <ElButton link type="warning" onClick={() => void changeStatus(row, 'closing')}>
          开始结账
        </ElButton>
      )
    }
    if (row.status === 'closing') {
      return (
        <>
          <ElButton link type="success" onClick={() => void changeStatus(row, 'closed')}>
            确认结账
          </ElButton>
          <ElButton link type="primary" onClick={() => void changeStatus(row, 'open')}>
            取消结账
          </ElButton>
        </>
      )
    }
    return (
      <ElButton link type="danger" onClick={() => void reopenPeriod(row)}>
        反结账
      </ElButton>
    )
  }

  async function loadData(accountSetId: string): Promise<void> {
    state.loading = true
    state.error = null
    try {
      const [periodResult, summaryResult] = await Promise.all([
        fetchAccountingPeriodList(accountSetId),
        fetchAccountingFoundationSummary(accountSetId)
      ])
      state.periods = periodResult.data ?? []
      state.summary = summaryResult.data ?? undefined
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('会计期间加载失败，请稍后重试')
    } finally {
      state.loading = false
    }
  }

  function retryLoad(): void {
    if (state.accountSet?.id) void loadData(state.accountSet.id)
  }

  async function changeStatus(
    row: AccountingPeriod,
    status: Api.Fms.AccountingPeriodStatus
  ): Promise<void> {
    const actionLabels: Partial<Record<Api.Fms.AccountingPeriodStatus, string>> = {
      open: row.status === 'closing' ? '取消结账' : '启用期间',
      closing: '开始结账',
      closed: '确认结账'
    }
    const actionLabel = actionLabels[status] || '变更状态'
    try {
      await confirmAction(
        `确定对 ${row.fiscalYear} 年第 ${row.periodNo} 期执行“${actionLabel}”吗？`,
        actionLabel,
        {
          type: status === 'closed' ? 'warning' : 'info',
          confirmButtonText: actionLabel,
          cancelButtonText: '取消'
        }
      )
      await setAccountingPeriodStatus(row.id, status)
      if (state.accountSet?.id) await loadData(state.accountSet.id)
    } catch {
      // 用户取消或数据库业务约束阻止时，不重复提示。
    }
  }

  async function reopenPeriod(row: AccountingPeriod): Promise<void> {
    try {
      const reason = await promptReason(
        '反结账会重新开放该期间，后续期间已结账时系统将阻止操作。',
        '反结账确认',
        {
          confirmButtonText: '确认反结账',
          emptyMessage: '反结账原因不能为空',
          placeholder: '请填写反结账原因和后续处理说明'
        }
      )
      await setAccountingPeriodStatus(row.id, 'open', reason)
      if (state.accountSet?.id) await loadData(state.accountSet.id)
    } catch {
      // 用户取消或数据库业务约束阻止时，不重复提示。
    }
  }

  async function handleOpen(row: AccountSet): Promise<void> {
    const policyAccess = getFieldAccess(row.fieldAccess, 'accountingPolicy')
    const subtitle = [`${row.accountSetCode}`]
    if (policyAccess !== 'hidden') subtitle.push(`本位币 ${row.baseCurrencyCode || '--'}`)
    Object.assign(state, {
      accountSet: row,
      periods: [],
      summary: undefined,
      loading: true,
      error: null
    })
    await drawerRef.value?.handleOpen(row, {
      title: `会计期间 · ${row.accountSetName}`,
      subtitle: subtitle.join(' · '),
      size: 'xl',
      contentHeight: 'calc(100vh - 132px)',
      scrollbarAlways: true,
      onOpen: () => loadData(row.id),
      drawerProps: { appendToBody: true, resizable: true, closeOnClickModal: false }
    })
  }

  defineExpose({ handleOpen })
</script>

<style scoped lang="scss">
  .accounting-period-drawer {
    min-width: 0;

    &__overview {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: var(--art-space-3);
      margin: var(--art-space-4) 0 var(--art-space-6);
    }

    &__metric {
      display: flex;
      gap: var(--art-space-3);
      align-items: center;
      min-width: 0;
      padding: var(--art-space-4);

      > svg {
        flex: none;
        width: 24px;
        height: 24px;
        color: var(--el-color-primary);
      }

      div {
        display: grid;
        min-width: 0;
      }

      strong {
        font-size: 20px;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-primary);
      }

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__hint {
      margin: calc(var(--art-space-2) * -1) 0 var(--art-space-4);
      font-size: 12px;
      line-height: 1.6;
      color: var(--el-text-color-secondary);
    }

    :deep(.accounting-period-drawer__period) {
      display: grid;
      gap: 2px;
      line-height: 1.35;

      strong {
        font-weight: 600;
        font-variant-numeric: tabular-nums;
        color: var(--el-text-color-primary);
      }

      span {
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    @media (width <= 900px) {
      &__overview {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (width <= 560px) {
      &__overview {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
