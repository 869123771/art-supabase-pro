<template>
  <ArtPageSection
    title="核算运行状态"
    subtitle="把基础配置、期间和资金账户的阻断集中到一个入口"
    class="accounting-readiness-panel"
  >
    <template #actions>
      <ElSelect
        v-model="state.accountSetId"
        class="accounting-readiness-panel__account-set"
        placeholder="选择核算账套"
        @change="loadReadiness"
      >
        <ElOption
          v-for="item in state.accountSets"
          :key="item.value"
          :label="item.label"
          :value="item.value"
        />
      </ElSelect>
    </template>

    <ArtAsyncState
      :loading="state.loading"
      :error="state.error"
      :empty="!state.accountSetId"
      empty-title="尚无可用账套"
      empty-description="先创建并启用企业账套，再开始会计核算。"
      @retry="load"
    >
      <div class="accounting-readiness-panel__summary">
        <span
          class="accounting-readiness-panel__score"
          :class="{ 'is-ready': readiness?.transactionReady }"
        >
          <strong>{{ completedStepCount }}/4</strong>
          <small>{{ readiness?.transactionReady ? '已可运行' : '项已就绪' }}</small>
        </span>
        <div>
          <strong>{{ readinessTitle }}</strong>
          <p>{{ readinessDescription }}</p>
        </div>
      </div>

      <div class="accounting-readiness-panel__steps" role="list" aria-label="财务核算启用步骤">
        <article
          v-for="item in readinessSteps"
          :key="item.key"
          class="accounting-readiness-panel__step"
          :class="item.ready ? 'is-ready' : 'is-pending'"
          role="listitem"
        >
          <span class="accounting-readiness-panel__step-icon" aria-hidden="true">
            <ArtSvgIcon :icon="item.ready ? 'ri:check-line' : item.icon" />
          </span>
          <div class="accounting-readiness-panel__step-copy">
            <div>
              <strong>{{ item.label }}</strong>
              <ElTag :type="item.ready ? 'success' : 'warning'" size="small" effect="plain">
                {{ item.ready ? '已就绪' : '待处理' }}
              </ElTag>
            </div>
            <p>{{ item.description }}</p>
          </div>
          <ElButton
            v-if="!item.ready || item.alwaysShowAction"
            link
            type="primary"
            :loading="item.key === 'foundation' && state.initializing"
            @click="handleStep(item)"
          >
            {{ item.actionLabel }}<ArtSvgIcon icon="ri:arrow-right-s-line" />
          </ElButton>
        </article>
      </div>
    </ArtAsyncState>
  </ArtPageSection>
</template>

<script setup lang="ts">
  import {
    fetchAccountingReadiness,
    fetchAccountSetOptions,
    initializeAccountingDefaults
  } from '@/api/fms'
  import { financeRouteNames } from '@/router/business-paths'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useAuth } from '@/hooks/core/useAuth'

  defineOptions({ name: 'AccountingReadinessPanel' })

  interface ReadinessStep {
    key: 'foundation' | 'period' | 'fund' | 'operation'
    label: string
    description: string
    icon: string
    ready: boolean
    actionLabel: string
    routeName: string
    alwaysShowAction?: boolean
  }

  const router = useRouter()
  const { confirmAction } = useArtFeedback()
  const { hasAuth } = useAuth()
  const state = reactive({
    loading: false,
    initializing: false,
    error: null as Error | null,
    accountSetId: '',
    accountSets: [] as Api.Fms.AccountSetOption[]
  })
  const readiness = ref<Api.Fms.AccountingReadiness | null>(null)

  const readinessSteps = computed<ReadinessStep[]>(() => {
    const current = readiness.value
    const foundationDescription = current?.foundationReady
      ? `${current.subjectCount} 个科目 · ${current.postingRuleCount} 条制证规则 · ${current.statementMappingCount} 条报表映射`
      : `缺 ${current?.missingSubjectCodes.length ?? 0} 个核心科目、${current?.missingPostingRuleCodes.length ?? 0} 条制证规则`

    return [
      {
        key: 'foundation',
        label: '核算基础',
        description: foundationDescription,
        icon: 'ri:book-2-line',
        ready: Boolean(current?.foundationReady),
        actionLabel: current?.foundationReady
          ? '查看科目'
          : hasAuth('FinanceAccountingSubject:Initialize')
            ? '一键补齐'
            : '查看科目',
        routeName: financeRouteNames.accountingSubject,
        alwaysShowAction: true
      },
      {
        key: 'period',
        label: '开放期间',
        description: current?.openPeriodCount
          ? `当前有 ${current.openPeriodCount} 个开放会计期间`
          : '需要开放一个会计期间，凭证才能保存和过账',
        icon: 'ri:calendar-check-line',
        ready: Boolean(current?.openPeriodCount),
        actionLabel: '管理期间',
        routeName: financeRouteNames.accountSet
      },
      {
        key: 'fund',
        label: '资金账户',
        description: current?.fundAccountCount
          ? `已配置 ${current.fundAccountCount} 个可用资金账户`
          : '登记真实银行、现金或第三方支付账户后，收付款链路才可执行',
        icon: 'ri:bank-card-line',
        ready: Boolean(current?.fundAccountCount),
        actionLabel: '配置账户',
        routeName: financeRouteNames.fundAccount
      },
      {
        key: 'operation',
        label: '日常核算',
        description: current?.transactionReady
          ? '业务单据可进入自动入账、凭证审核和账簿报表链路'
          : '完成以上前置后，系统会自动开放完整交易核算链路',
        icon: 'ri:flow-chart',
        ready: Boolean(current?.transactionReady),
        actionLabel: '查看自动入账',
        routeName: financeRouteNames.autoPosting,
        alwaysShowAction: Boolean(current?.transactionReady)
      }
    ]
  })
  const completedStepCount = computed(
    () => readinessSteps.value.filter((item) => item.ready).length
  )
  const readinessTitle = computed(() =>
    readiness.value?.transactionReady ? '财务核算链路已可运行' : '还有前置事项需要处理'
  )
  const readinessDescription = computed(() => {
    if (readiness.value?.transactionReady)
      return '可以从业务结算进入自动入账、凭证、账簿报表和月末结账。'
    const pending = readinessSteps.value.filter((item) => !item.ready).map((item) => item.label)
    return pending.length
      ? `当前阻断：${pending.join('、')}。完成后无需重新启用账套。`
      : '正在核验账套状态。'
  })

  async function loadReadiness(): Promise<void> {
    if (!state.accountSetId) {
      readiness.value = null
      return
    }
    state.loading = true
    state.error = null
    try {
      const { data } = await fetchAccountingReadiness(state.accountSetId)
      readiness.value = data ?? null
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('核算运行状态加载失败')
    } finally {
      state.loading = false
    }
  }

  async function load(): Promise<void> {
    state.loading = true
    state.error = null
    try {
      const { data } = await fetchAccountSetOptions({ status: 'active' })
      state.accountSets = data ?? []
      if (!state.accountSets.some((item) => item.value === state.accountSetId)) {
        state.accountSetId = state.accountSets[0]?.value ?? ''
      }
      await loadReadiness()
    } catch (error) {
      state.error = error instanceof Error ? error : new Error('核算运行状态加载失败')
    } finally {
      state.loading = false
    }
  }

  async function handleStep(item: ReadinessStep): Promise<void> {
    if (
      item.key === 'foundation' &&
      !item.ready &&
      hasAuth('FinanceAccountingSubject:Initialize')
    ) {
      try {
        await confirmAction(
          '将只新增缺失的核心科目、默认制证规则和报表映射，不覆盖已有配置。',
          '补齐核算基础',
          {
            type: 'warning',
            confirmButtonText: '确认补齐',
            cancelButtonText: '暂不处理'
          }
        )
        state.initializing = true
        await initializeAccountingDefaults(state.accountSetId)
        await loadReadiness()
      } catch {
        // 用户取消或数据库业务约束阻止时，不重复提示。
      } finally {
        state.initializing = false
      }
      return
    }
    await router.push({ name: item.routeName })
  }

  onMounted(() => void load())
</script>

<style scoped lang="scss">
  .accounting-readiness-panel {
    &__account-set {
      width: min(360px, 42vw);
    }

    &__summary {
      display: grid;
      grid-template-columns: 64px minmax(0, 1fr);
      gap: 14px;
      align-items: center;
      padding: 12px 14px;
      margin-bottom: 12px;
      background: color-mix(in srgb, var(--el-color-warning) 6%, var(--default-box-color));
      border: 1px solid color-mix(in srgb, var(--el-color-warning) 18%, var(--el-border-color));
      border-radius: var(--el-border-radius-base);

      > div > strong {
        display: block;
        margin-bottom: 3px;
        font-size: 14px;
        color: var(--el-text-color-primary);
      }

      p {
        margin: 0;
        font-size: 12px;
        line-height: 19px;
        color: var(--el-text-color-secondary);
      }
    }

    &__score {
      display: grid;
      place-content: center;
      width: 64px;
      height: 54px;
      color: var(--el-color-warning-dark-2);
      text-align: center;
      background: color-mix(in srgb, var(--el-color-warning) 13%, transparent);
      border-radius: var(--el-border-radius-base);

      strong,
      small {
        display: block;
        white-space: nowrap;
      }

      strong {
        font-size: 18px;
        font-variant-numeric: tabular-nums;
        line-height: 22px;
      }

      small {
        font-size: 11px;
      }

      &.is-ready {
        color: var(--el-color-success-dark-2);
        background: color-mix(in srgb, var(--el-color-success) 12%, transparent);
      }
    }

    &__steps {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
    }

    &__step {
      display: grid;
      grid-template-columns: 32px minmax(0, 1fr);
      gap: 10px;
      align-content: start;
      min-width: 0;
      padding: 12px;
      background: var(--default-box-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      > .el-button {
        grid-column: 2;
        justify-self: start;
        height: auto;
        padding: 0;
      }

      &.is-pending {
        border-color: color-mix(in srgb, var(--el-color-warning) 24%, var(--el-border-color));
      }
    }

    &__step-icon {
      display: grid;
      place-items: center;
      width: 32px;
      height: 32px;
      font-size: 17px;
      color: var(--el-color-warning-dark-2);
      background: color-mix(in srgb, var(--el-color-warning) 11%, transparent);
      border-radius: var(--el-border-radius-base);
    }

    &__step.is-ready &__step-icon {
      color: var(--el-color-success-dark-2);
      background: color-mix(in srgb, var(--el-color-success) 11%, transparent);
    }

    &__step-copy {
      min-width: 0;

      > div {
        display: flex;
        gap: 7px;
        align-items: center;

        strong {
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 13px;
          white-space: nowrap;
        }
      }

      p {
        display: -webkit-box;
        min-height: 38px;
        margin: 5px 0 0;
        overflow: hidden;
        -webkit-line-clamp: 2;
        font-size: 12px;
        line-height: 19px;
        color: var(--el-text-color-secondary);
        -webkit-box-orient: vertical;
      }
    }
  }

  @media (width <= 1180px) {
    .accounting-readiness-panel__steps {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (width <= 640px) {
    .accounting-readiness-panel {
      &__account-set {
        width: 100%;
      }

      &__steps {
        grid-template-columns: 1fr;
      }
    }
  }
</style>
