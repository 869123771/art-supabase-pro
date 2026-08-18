<template>
  <div class="business-workspace-page art-full-height fms-accounting-page opening-balance-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="财务基础 · 期初初始化"
      title="期初余额"
      description="按账套、会计年度、末级科目及辅助维度录入期初数据，通过借贷平衡校验后统一确认锁定。"
      icon="ri:scales-3-line"
      :tags="[
        { label: '借贷平衡', type: 'primary' },
        { label: '确认锁定', type: 'success' },
        { label: '反确认留痕', type: 'info' }
      ]"
      :metrics="metrics"
    />

    <ElAlert
      v-if="!isPlatformSuper"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户期初余额；录入、删除、确认及反确认仅平台超级管理员可执行。"
    />

    <ArtPageSection
      title="初始化范围"
      subtitle="期初数据按账套与会计年度分别管控"
      class="opening-balance-page__scope-section"
    >
      <div class="opening-balance-page__scope">
        <label>
          <span>账套</span>
          <ElSelect
            v-model="scope.accountSetId"
            aria-label="账套"
            filterable
            :loading="scope.loading"
            placeholder="请选择账套"
            @change="handleAccountSetChange"
          >
            <ElOption
              v-for="item in scope.options"
              :key="item.value"
              :label="item.label"
              :value="item.value"
            />
          </ElSelect>
        </label>
        <label>
          <span>会计年度</span>
          <ElSelect
            v-model="scope.fiscalYear"
            aria-label="会计年度"
            placeholder="请选择年度"
            @change="loadBalances"
          >
            <ElOption
              v-for="year in scope.fiscalYears"
              :key="year"
              :label="`${year} 年`"
              :value="year"
            />
          </ElSelect>
        </label>
      </div>
      <AccountingSetupGuide
        :loading="scope.loading"
        :has-account-set="scope.options.length > 0"
        :can-configure="isPlatformSuper"
        @configure="goToAccountSet"
      />
    </ArtPageSection>

    <ArtPageSection
      title="期初余额明细"
      :subtitle="
        summary.status === 'confirmed'
          ? '已确认锁定，反确认后方可调整'
          : '草稿状态，可继续录入和校验'
      "
      class="opening-balance-page__detail accounting-workspace-fill-section"
    >
      <template #actions>
        <div
          class="opening-balance-page__status-group"
          role="status"
          aria-live="polite"
          aria-atomic="true"
        >
          <ElTag
            class="opening-balance-page__status-tag"
            :type="summary.status === 'confirmed' ? 'success' : 'warning'"
            size="small"
            effect="plain"
            round
          >
            {{ summary.status === 'confirmed' ? '已确认' : '草稿' }}
          </ElTag>
          <div
            class="opening-balance-page__balance-check"
            :class="summary.isBalanced ? 'is-balanced' : 'is-unbalanced'"
          >
            <ArtSvgIcon
              aria-hidden="true"
              :icon="summary.isBalanced ? 'ri:checkbox-circle-line' : 'ri:error-warning-line'"
            />
            <span>{{
              summary.isBalanced ? '借贷平衡' : `差额 ${formatMoney(summary.difference)}`
            }}</span>
          </div>
        </div>
        <ElButton
          v-if="isPlatformSuper && summary.status === 'draft'"
          type="primary"
          :disabled="!currentAccountSet || workspace.leafSubjects.length === 0"
          :title="
            !currentAccountSet
              ? '请先创建并选择企业账套'
              : workspace.leafSubjects.length === 0
                ? '当前账套尚未维护末级会计科目'
                : undefined
          "
          @click="openDialog()"
        >
          <ArtSvgIcon icon="ri:add-line" />录入余额
        </ElButton>
        <ElButton
          v-if="isPlatformSuper && summary.status === 'draft'"
          type="success"
          :disabled="!summary.isBalanced || summary.entryCount === 0"
          :title="
            summary.entryCount === 0
              ? '请先录入期初余额'
              : !summary.isBalanced
                ? '借贷合计平衡后才能确认锁定'
                : undefined
          "
          :loading="workspace.statusChanging"
          @click="confirmOpeningBalance"
        >
          确认并锁定
        </ElButton>
        <ElButton
          v-if="isPlatformSuper && summary.status === 'confirmed'"
          :loading="workspace.statusChanging"
          @click="reopenOpeningBalance"
        >
          反确认
        </ElButton>
      </template>

      <ArtSearchBar
        v-model="balanceFilterForm"
        class="opening-balance-page__filter-search"
        :items="balanceSearchItems"
        :span="8"
        :gutter="12"
        label-position="left"
        label-width="76px"
        :show-expand="false"
        :button-left-limit="0"
        @search="applyBalanceFilters"
        @reset="resetBalanceFilters"
      />

      <ArtAsyncState
        class="accounting-workspace-content-state"
        :class="{ 'is-empty': filteredBalances.length === 0 }"
        :loading="workspace.loading"
        :empty-image-size="56"
        :min-height="0"
        :error="workspace.error"
        :empty="filteredBalances.length === 0"
        empty-text="暂无期初余额"
        empty-description="按末级科目录入期初借贷余额；借贷合计平衡后方可确认。"
        @retry="loadBalances"
      >
        <ArtTable
          :data="filteredBalances"
          :columns="columns"
          :pagination="false"
          table-layout="fixed"
          empty-text="暂无期初余额"
        />
      </ArtAsyncState>
    </ArtPageSection>

    <OpeningBalanceDialog ref="dialogRef" @success="loadBalances" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElTag } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import AccountingSetupGuide from '../modules/accounting-setup-guide.vue'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSearchBar, {
    type SearchFormItem
  } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ColumnOption } from '@/types'
  import { formatCurrencyValue } from '@/utils/ui/format'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    deleteOpeningBalance,
    fetchAccountingPeriodList,
    fetchAccountSetOptions,
    fetchAuxiliaryItemList,
    fetchAuxiliaryTypeList,
    fetchCurrencyList,
    fetchOpeningBalanceList,
    fetchOpeningBalanceSummary,
    fetchSubjectList,
    setOpeningBalanceStatus
  } from '@/api/fms'
  import OpeningBalanceDialog from './modules/opening-balance-dialog.vue'

  defineOptions({ name: 'FinanceOpeningBalance' })

  type OpeningBalance = Api.Fms.OpeningBalanceRecord

  interface BalanceFilter extends Record<string, unknown> {
    keyword: string
    direction?: Api.Fms.BalanceDirection
  }

  const { confirmAction, promptReason } = useArtFeedback()
  const router = useRouter()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const dialogRef = ref<{
    handleOpen: (
      accountSet: Api.Fms.AccountSetOption,
      fiscalYear: number,
      context: {
        subjects: Api.Fms.SubjectRecord[]
        currencies: Api.Fms.CurrencyRecord[]
        auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[]
        auxiliaryItems: Api.Fms.AuxiliaryItemRecord[]
      },
      row?: OpeningBalance
    ) => Promise<void>
  }>()
  const scope = reactive({
    accountSetId: '',
    fiscalYear: new Date().getFullYear(),
    fiscalYears: [] as number[],
    loading: true,
    options: [] as Api.Fms.AccountSetOption[]
  })
  const workspace = reactive({
    loading: false,
    error: '',
    statusChanging: false,
    balances: [] as OpeningBalance[],
    leafSubjects: [] as Api.Fms.SubjectRecord[],
    currencies: [] as Api.Fms.CurrencyRecord[],
    auxiliaryTypes: [] as Api.Fms.AuxiliaryTypeRecord[],
    auxiliaryItems: [] as Api.Fms.AuxiliaryItemRecord[]
  })
  const balanceFilterForm = ref<BalanceFilter>(createDefaultBalanceFilter())
  const appliedBalanceFilter = reactive<BalanceFilter>(createDefaultBalanceFilter())
  const summary = reactive<Api.Fms.OpeningBalanceSummary>({
    accountSetId: '',
    fiscalYear: scope.fiscalYear,
    status: 'draft',
    entryCount: 0,
    openingDebit: 0,
    openingCredit: 0,
    difference: 0,
    isBalanced: true
  })

  const currentAccountSet = computed(() =>
    scope.options.find((item) => item.value === scope.accountSetId)
  )
  const baseCurrency = computed(() => workspace.currencies.find((item) => item.isBase))
  const directionOptions = computed(() => getDictMap.value.fmsBalanceDirection ?? [])
  const balanceSearchItems = computed<SearchFormItem[]>(() => [
    {
      label: '会计科目',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '搜索科目编码或名称' }
    },
    {
      label: '余额方向',
      key: 'direction',
      type: 'select',
      props: { clearable: true, placeholder: '全部方向', options: directionOptions.value }
    }
  ])
  const filteredBalances = computed(() => {
    const keyword = appliedBalanceFilter.keyword.trim().toLowerCase()
    return workspace.balances.filter((item) => {
      const subject = item.subject
      const matchesKeyword =
        !keyword ||
        subject?.subjectCode.toLowerCase().includes(keyword) ||
        subject?.subjectName.toLowerCase().includes(keyword)
      return (
        Boolean(matchesKeyword) &&
        (!appliedBalanceFilter.direction ||
          subject?.balanceDirection === appliedBalanceFilter.direction)
      )
    })
  })
  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      key: 'entries',
      label: '余额记录',
      value: summary.entryCount,
      description: `${scope.fiscalYear} 年期初`,
      icon: 'ri:file-list-3-line'
    },
    {
      key: 'debit',
      label: '借方合计',
      value: formatMoney(summary.openingDebit),
      description: baseCurrency.value?.currencyCode ?? '本位币',
      icon: 'ri:arrow-left-down-line',
      tone: 'success'
    },
    {
      key: 'credit',
      label: '贷方合计',
      value: formatMoney(summary.openingCredit),
      description: baseCurrency.value?.currencyCode ?? '本位币',
      icon: 'ri:arrow-right-up-line',
      tone: 'warning'
    },
    {
      key: 'status',
      label: '平衡状态',
      value: summary.isBalanced ? '已平衡' : '待调整',
      description: summary.status === 'confirmed' ? '已确认锁定' : '草稿可编辑',
      icon: summary.isBalanced ? 'ri:scales-3-line' : 'ri:error-warning-line',
      tone: summary.isBalanced ? 'primary' : 'danger'
    }
  ])

  const columns: ColumnOption<OpeningBalance>[] = [
    {
      prop: 'subject',
      label: '会计科目',
      minWidth: 230,
      fixed: 'left',
      formatter: (row) => (
        <div class="opening-balance-page__subject">
          <strong>{row.subject?.subjectName ?? '—'}</strong>
          <small>{row.subject?.subjectCode ?? '—'}</small>
        </div>
      )
    },
    {
      prop: 'balanceDirection',
      label: '方向',
      width: 90,
      formatter: (row) => (
        <ElTag type={row.subject?.balanceDirection === 'debit' ? 'success' : 'warning'}>
          {row.subject?.balanceDirection === 'debit' ? '借' : '贷'}
        </ElTag>
      )
    },
    {
      prop: 'openingDebit',
      label: '期初借方',
      minWidth: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.openingDebit)
    },
    {
      prop: 'openingCredit',
      label: '期初贷方',
      minWidth: 135,
      align: 'right',
      formatter: (row) => formatMoney(row.openingCredit)
    },
    {
      prop: 'auxiliaryValues',
      label: '辅助核算',
      minWidth: 220,
      showOverflowTooltip: true,
      formatter: (row) => formatAuxiliaryValues(row.auxiliaryValues)
    },
    {
      prop: 'currency',
      label: '外币',
      width: 90,
      formatter: (row) => row.currency?.currencyCode ?? '—'
    },
    {
      prop: 'originalCurrencyAmount',
      label: '原币金额',
      minWidth: 125,
      align: 'right',
      formatter: (row) =>
        row.currency ? Number(row.originalCurrencyAmount).toLocaleString('zh-CN') : '—'
    },
    ...(isPlatformSuper.value
      ? [
          {
            prop: 'operation',
            label: '操作',
            width: 110,
            fixed: 'right' as const,
            formatter: (row: OpeningBalance) =>
              summary.status === 'draft' ? (
                <div class="opening-balance-page__actions">
                  <ArtButtonTable type="edit" onClick={() => openDialog(row)} />
                  <ArtButtonTable type="delete" onClick={() => removeBalance(row)} />
                </div>
              ) : (
                <span class="opening-balance-page__locked">已锁定</span>
              )
          } satisfies ColumnOption<OpeningBalance>
        ]
      : [])
  ]

  function createDefaultBalanceFilter(): BalanceFilter {
    return { keyword: '', direction: undefined }
  }

  function applyBalanceFilters(params: Record<string, unknown>): void {
    appliedBalanceFilter.keyword = typeof params.keyword === 'string' ? params.keyword : ''
    appliedBalanceFilter.direction =
      typeof params.direction === 'string'
        ? (params.direction as Api.Fms.BalanceDirection)
        : undefined
  }

  function resetBalanceFilters(): void {
    balanceFilterForm.value = createDefaultBalanceFilter()
    Object.assign(appliedBalanceFilter, createDefaultBalanceFilter())
  }

  function formatMoney(value: number): string {
    return formatCurrencyValue(value, baseCurrency.value?.currencyCode ?? 'CNY')
  }

  function formatAuxiliaryValues(values: Record<string, string>): string {
    const labels = Object.entries(values).map(([typeId, itemId]) => {
      const type = workspace.auxiliaryTypes.find((item) => item.id === typeId)
      const item = workspace.auxiliaryItems.find((candidate) => candidate.id === itemId)
      return `${type?.typeName ?? '维度'}：${item?.itemName ?? itemId}`
    })
    return labels.join('；') || '—'
  }

  async function loadBalances(): Promise<void> {
    if (!scope.accountSetId || !scope.fiscalYear) return
    workspace.loading = true
    workspace.error = ''
    try {
      const [balanceResult, summaryResult] = await Promise.all([
        fetchOpeningBalanceList(scope.accountSetId, scope.fiscalYear),
        fetchOpeningBalanceSummary(scope.accountSetId, scope.fiscalYear)
      ])
      workspace.balances = balanceResult.data ?? []
      if (summaryResult.data) Object.assign(summary, summaryResult.data)
    } catch (error) {
      workspace.error = error instanceof Error ? error.message : '期初余额加载失败'
    } finally {
      workspace.loading = false
    }
  }

  async function loadFoundation(): Promise<void> {
    if (!scope.accountSetId) return
    workspace.loading = true
    workspace.error = ''
    try {
      const [periodResult, subjectResult, currencyResult, typeResult, itemResult] =
        await Promise.all([
          fetchAccountingPeriodList(scope.accountSetId),
          fetchSubjectList(scope.accountSetId),
          fetchCurrencyList(scope.accountSetId),
          fetchAuxiliaryTypeList(scope.accountSetId),
          fetchAuxiliaryItemList(scope.accountSetId)
        ])
      const periods = periodResult.data ?? []
      scope.fiscalYears = [...new Set(periods.map((item) => item.fiscalYear))].sort(
        (left, right) => right - left
      )
      if (!scope.fiscalYears.length) scope.fiscalYears = [new Date().getFullYear()]
      if (!scope.fiscalYears.includes(scope.fiscalYear)) scope.fiscalYear = scope.fiscalYears[0]

      const subjects = subjectResult.data ?? []
      const parentIds = new Set(subjects.map((item) => item.parentId).filter(Boolean))
      workspace.leafSubjects = subjects.filter((item) => item.isEnabled && !parentIds.has(item.id))
      workspace.currencies = currencyResult.data ?? []
      workspace.auxiliaryTypes = typeResult.data ?? []
      workspace.auxiliaryItems = itemResult.data ?? []
      await loadBalances()
    } catch (error) {
      workspace.error = error instanceof Error ? error.message : '期初基础数据加载失败'
    } finally {
      workspace.loading = false
    }
  }

  function handleAccountSetChange(): void {
    workspace.balances = []
    resetBalanceFilters()
    void loadFoundation()
  }

  async function openDialog(row?: OpeningBalance): Promise<void> {
    if (!currentAccountSet.value || summary.status !== 'draft') return
    await dialogRef.value?.handleOpen(
      currentAccountSet.value,
      scope.fiscalYear,
      {
        subjects: workspace.leafSubjects,
        currencies: workspace.currencies,
        auxiliaryTypes: workspace.auxiliaryTypes,
        auxiliaryItems: workspace.auxiliaryItems
      },
      row
    )
  }

  async function removeBalance(row: OpeningBalance): Promise<void> {
    await confirmAction(
      `确定删除“${row.subject?.subjectCode ?? ''} ${row.subject?.subjectName ?? ''}”的期初余额吗？`,
      '删除期初余额'
    )
    await deleteOpeningBalance(row.id)
    await loadBalances()
  }

  async function confirmOpeningBalance(): Promise<void> {
    await confirmAction(
      `确认 ${scope.fiscalYear} 年期初余额后将锁定全部记录，确定继续吗？`,
      '确认期初余额',
      { type: 'success', confirmButtonText: '确认并锁定' }
    )
    workspace.statusChanging = true
    try {
      await setOpeningBalanceStatus(scope.accountSetId, scope.fiscalYear, 'confirmed')
      await loadBalances()
    } finally {
      workspace.statusChanging = false
    }
  }

  async function reopenOpeningBalance(): Promise<void> {
    const reason = await promptReason(
      '反确认后可重新调整期初余额，操作原因将写入审计记录。',
      '反确认期初余额',
      {
        confirmButtonText: '确认反确认',
        emptyMessage: '请填写反确认原因',
        placeholder: '请说明差错原因和调整安排'
      }
    )
    workspace.statusChanging = true
    try {
      await setOpeningBalanceStatus(scope.accountSetId, scope.fiscalYear, 'draft', reason)
      await loadBalances()
    } finally {
      workspace.statusChanging = false
    }
  }

  function goToAccountSet(): void {
    void router.push('/fms/account-set')
  }

  async function loadAccountSets(): Promise<void> {
    scope.loading = true
    try {
      const result = await fetchAccountSetOptions({ from: 0, to: 999 })
      scope.options = result.data ?? []
      if (!scope.accountSetId && scope.options.length) {
        scope.accountSetId = scope.options[0].value
        await loadFoundation()
      }
    } finally {
      scope.loading = false
    }
  }

  onMounted(loadAccountSets)
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .opening-balance-page {
    @include accounting.accounting-workspace-layout;

    &__scope,
    &__actions,
    &__status-group,
    &__balance-check {
      display: flex;
      align-items: center;
    }

    &__scope {
      display: grid;
      grid-template-columns: minmax(320px, 520px) 220px;
      gap: 16px;
      align-items: center;

      label {
        display: grid;
        grid-template-columns: auto minmax(0, 1fr);
        gap: 8px;
        align-items: center;
        min-width: 0;

        > span {
          flex: none;
          font-size: 12px;
          font-weight: 600;
          line-height: 18px;
          color: var(--el-text-color-regular);
        }
      }

      :deep(.el-select) {
        width: 100%;
      }

      label:last-child :deep(.el-select) {
        width: 100%;
      }
    }

    &__scope-section,
    &__detail {
      :deep(.art-page-section__header) {
        align-items: center;
        margin-bottom: 10px;
      }
    }

    &__scope-section.art-page-section.art-card-xs {
      padding: 14px 20px;
    }

    &__detail.art-page-section.art-card-xs {
      flex: 1;
      min-height: 0;
      padding: 12px 20px;
      overflow: hidden;

      :deep(.art-page-section__body) {
        display: flex;
        flex: 1;
        flex-direction: column;
        min-height: 0;
        overflow: hidden;
      }

      :deep(.accounting-workspace-content-state),
      :deep(.accounting-workspace-content-state.is-empty > .art-async-state__empty) {
        min-height: 0 !important;
      }

      :deep(.accounting-workspace-content-state .art-empty-state) {
        padding-block: 6px;
      }
    }

    &__filter-search {
      flex: none;
      margin-bottom: var(--art-space-2);
    }

    :deep(.opening-balance-page__filter-search.art-form.art-search-bar) {
      padding: var(--art-space-3) var(--art-space-3) 0;

      .el-form-item {
        margin-bottom: var(--art-space-3);
      }
    }

    &__status-group {
      gap: 6px;
    }

    &__status-tag {
      height: 22px;
      padding-inline: 7px;
      font-size: 11px;
      font-weight: 600;
    }

    &__balance-check {
      gap: 5px;
      min-height: 24px;
      padding: 2px 8px;
      font-size: 12px;
      font-weight: 600;
      line-height: 18px;
      white-space: nowrap;
      border-radius: var(--el-border-radius-base);

      :deep(.art-svg-icon) {
        font-size: 14px;
      }

      &.is-balanced {
        color: var(--el-color-success-dark-2);
        background: color-mix(in srgb, var(--el-color-success) 9%, transparent);
        border: 1px solid color-mix(in srgb, var(--el-color-success) 18%, transparent);
      }

      &.is-unbalanced {
        color: var(--el-color-danger-dark-2);
        background: color-mix(in srgb, var(--el-color-danger) 8%, transparent);
        border: 1px solid color-mix(in srgb, var(--el-color-danger) 18%, transparent);
      }
    }

    &__locked {
      color: var(--art-text-gray-500);
    }
  }

  :deep(.opening-balance-page__subject) {
    min-width: 0;

    strong,
    small {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    small {
      margin-top: 3px;
      color: var(--art-text-gray-500);
    }
  }

  @media only screen and (width <= 720px) {
    .opening-balance-page {
      &__scope {
        grid-template-columns: 1fr;
      }

      &__scope label {
        grid-template-columns: 72px minmax(0, 1fr);
      }

      &__scope :deep(.el-select),
      &__scope label:last-child :deep(.el-select) {
        width: 100%;
      }

      &__balance-check {
        justify-content: center;
      }
    }
  }
</style>
