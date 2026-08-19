<template>
  <div
    class="business-workspace-page art-full-height fms-accounting-page accounting-currency-page"
    :class="{ 'is-focus-mode': focusMode }"
  >
    <BusinessWorkspaceHeader
      v-show="!focusMode"
      density="compact"
      eyebrow="财务基础 · 多币种核算"
      title="币种与汇率"
      description="以账套本位币为核算基准，统一外币档案、日期汇率和期末折算口径。"
      icon="ri:exchange-dollar-line"
      :tags="[
        { label: '本位币保护', type: 'primary' },
        { label: '多汇率口径', type: 'success' },
        { label: '按日可追溯', type: 'info' }
      ]"
      :metrics="metrics"
    >
      <template #actions>
        <AccountingWorkspaceFocusToggle v-model="focusMode" />
      </template>
    </BusinessWorkspaceHeader>

    <ElAlert
      v-if="!isPlatformSuper"
      v-show="!focusMode"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户币种及汇率；币种、汇率维护仅平台超级管理员可执行。"
    />

    <ArtPageSection
      v-show="!focusMode"
      title="核算范围"
      subtitle="切换账套后，币种和汇率按法人核算主体完全隔离"
      class="accounting-workspace-scope-section"
    >
      <div class="accounting-currency-page__scope">
        <span>当前账套</span>
        <ElSelect
          v-model="scope.accountSetId"
          aria-label="当前账套"
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
      </div>
      <AccountingSetupGuide
        :loading="scope.loading"
        :has-account-set="scope.options.length > 0"
        :can-configure="isPlatformSuper"
        @configure="goToAccountSet"
      />
    </ArtPageSection>

    <div class="accounting-currency-page__workspace" :class="{ 'is-focused': focusMode }">
      <ArtPageSection
        title="核算币种"
        subtitle="本位币不可停用，外币可独立启停"
        class="accounting-workspace-fill-section"
      >
        <template #actions>
          <ElButton v-if="isPlatformSuper" type="primary" @click="openCurrencyDialog()">
            <ArtSvgIcon icon="ri:add-line" />新增外币
          </ElButton>
        </template>
        <ArtAsyncState
          class="accounting-workspace-content-state"
          :class="{ 'is-empty': workspace.currencies.length === 0 }"
          :loading="workspace.loading"
          :empty-image-size="68"
          :min-height="150"
          :error="workspace.error"
          :empty="workspace.currencies.length === 0"
          empty-text="暂无核算币种"
          empty-description="账套初始化时会自动生成本位币。"
          @retry="loadWorkspace"
        >
          <ElScrollbar class="accounting-currency-page__currency-scrollbar">
            <div class="accounting-currency-page__currency-grid">
              <div
                v-for="item in workspace.currencies"
                :key="item.id"
                class="accounting-currency-page__currency-card"
                :class="{ 'is-active': item.id === workspace.selectedCurrencyId }"
              >
                <button
                  type="button"
                  class="accounting-currency-page__currency-select"
                  :aria-label="`选择${item.currencyName}`"
                  :aria-pressed="item.id === workspace.selectedCurrencyId"
                  @click="workspace.selectedCurrencyId = item.id"
                >
                  <span class="accounting-currency-page__symbol">{{
                    item.symbol || item.currencyCode
                  }}</span>
                  <span class="accounting-currency-page__currency-name">
                    <span class="accounting-currency-page__currency-title">
                      <strong>{{ item.currencyName }}</strong>
                      <span
                        v-if="item.id === workspace.selectedCurrencyId"
                        class="accounting-currency-page__selected-badge"
                      >
                        <ArtSvgIcon icon="ri:check-line" />当前
                      </span>
                    </span>
                    <span class="accounting-currency-page__currency-meta">
                      <small>{{ item.currencyCode }} · {{ item.decimalPlaces }} 位小数</small>
                      <ElTag v-if="item.isBase" type="primary" size="small" effect="plain">
                        本位币
                      </ElTag>
                      <ElTag
                        :type="item.isEnabled ? 'success' : 'info'"
                        size="small"
                        effect="plain"
                      >
                        {{ item.isEnabled ? '启用' : '停用' }}
                      </ElTag>
                    </span>
                  </span>
                </button>
                <ArtButtonMore
                  v-if="isPlatformSuper"
                  class="accounting-currency-page__currency-more"
                  :list="getCurrencyActions(item)"
                  @click="handleCurrencyAction($event, item)"
                />
              </div>
            </div>
          </ElScrollbar>
        </ArtAsyncState>
      </ArtPageSection>

      <ArtPageSection
        title="汇率台账"
        :subtitle="
          selectedCurrency ? `${selectedCurrency.currencyCode} 对本位币的直接汇率` : '请选择外币'
        "
        class="accounting-workspace-fill-section"
      >
        <template #actions>
          <AccountingWorkspaceFocusToggle v-if="focusMode" v-model="focusMode" />
          <ElButton v-if="isPlatformSuper" type="primary" @click="openRateDialog()">
            <ArtSvgIcon icon="ri:add-line" />新增汇率
          </ElButton>
        </template>
        <div v-if="selectedCurrency" class="accounting-currency-page__rate-context">
          <span class="accounting-currency-page__rate-context-symbol">
            {{ selectedCurrency.symbol || selectedCurrency.currencyCode }}
          </span>
          <div>
            <strong>
              {{ selectedCurrency.currencyName }}（{{ selectedCurrency.currencyCode }}）
              <ArtSvgIcon icon="ri:arrow-right-line" />
              {{ baseCurrency?.currencyCode || '本位币' }}
            </strong>
            <span>
              直接汇率 · 共 {{ selectedCurrencyRates.length }} 条记录 ·
              {{ selectedCurrency.isEnabled ? '当前启用' : '当前停用' }}
            </span>
          </div>
        </div>
        <ArtSearchBar
          v-model="rateFilterForm"
          class="accounting-currency-page__rate-search"
          :items="rateSearchItems"
          :span="8"
          :gutter="12"
          label-position="left"
          label-width="76px"
          :show-expand="false"
          :button-left-limit="0"
          @search="applyRateFilters"
          @reset="resetRateFilters"
        />
        <ArtAsyncState
          class="accounting-workspace-content-state"
          :class="{ 'is-empty': filteredRates.length === 0 }"
          :loading="workspace.loading"
          :empty-image-size="72"
          :min-height="160"
          :error="workspace.error"
          :empty="filteredRates.length === 0"
          empty-text="暂无汇率记录"
          empty-description="选择已启用外币后维护汇率；本位币无需维护汇率。"
          @retry="loadWorkspace"
        >
          <ArtTable
            :data="filteredRates"
            :columns="columns"
            :pagination="false"
            table-layout="fixed"
            empty-text="暂无汇率记录"
          />
        </ArtAsyncState>
      </ArtPageSection>
    </div>

    <CurrencyDialog ref="currencyDialogRef" @success="loadWorkspace" />
    <ExchangeRateDialog ref="rateDialogRef" @success="loadWorkspace" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElMessage, ElTag } from 'element-plus'
  import { storeToRefs } from 'pinia'
  import BusinessWorkspaceHeader, {
    type BusinessWorkspaceMetric
  } from '@/components/business/business-workspace-header/index.vue'
  import AccountingWorkspaceFocusToggle from '../modules/accounting-workspace-focus-toggle.vue'
  import { useAccountingWorkspaceFocus } from '../modules/use-accounting-workspace-focus'
  import AccountingSetupGuide from '../modules/accounting-setup-guide.vue'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import ArtPageSection from '@/components/core/layouts/art-page-section/index.vue'
  import ArtAsyncState from '@/components/core/layouts/art-async-state/index.vue'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtButtonMore, {
    type ButtonMoreItem
  } from '@/components/core/forms/art-button-more/index.vue'
  import ArtSearchBar, {
    type SearchFormItem
  } from '@/components/core/forms/art-search-bar/index.vue'
  import type { ColumnOption } from '@/types'
  import { formatWithDayjs } from '@/utils/time'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchAccountSetOptions,
    fetchCurrencyList,
    fetchExchangeRateList,
    setCurrencyEnabled
  } from '@/api/fms'
  import CurrencyDialog from './modules/currency-dialog.vue'
  import ExchangeRateDialog from './modules/exchange-rate-dialog.vue'

  defineOptions({ name: 'FinanceAccountingCurrency' })

  type Currency = Api.Fms.CurrencyRecord
  type ExchangeRate = Api.Fms.ExchangeRateRecord

  interface RateFilter extends Record<string, unknown> {
    keyword: string
    rateType?: Api.Fms.ExchangeRateType
  }

  const { confirmAction } = useArtFeedback()
  const { focusMode } = useAccountingWorkspaceFocus()
  const { ensureAccountSet, goToAccountSet } = useFinanceAccountSetPrerequisite()
  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const currencyDialogRef = ref<{
    handleOpen: (accountSet: Api.Fms.AccountSetOption, row?: Currency) => Promise<void>
  }>()
  const rateDialogRef = ref<{
    handleOpen: (
      accountSet: Api.Fms.AccountSetOption,
      currencies: Currency[],
      selectedCurrency?: Currency,
      row?: ExchangeRate
    ) => Promise<void>
  }>()
  const scope = reactive({
    accountSetId: '',
    loading: true,
    options: [] as Api.Fms.AccountSetOption[]
  })
  const workspace = reactive({
    loading: false,
    error: '',
    currencies: [] as Currency[],
    rates: [] as ExchangeRate[],
    selectedCurrencyId: ''
  })
  const rateFilterForm = ref<RateFilter>(createDefaultRateFilter())
  const appliedRateFilter = reactive<RateFilter>(createDefaultRateFilter())

  const currentAccountSet = computed(() =>
    scope.options.find((item) => item.value === scope.accountSetId)
  )
  const selectedCurrency = computed(() =>
    workspace.currencies.find((item) => item.id === workspace.selectedCurrencyId)
  )
  const baseCurrency = computed(() => workspace.currencies.find((item) => item.isBase))
  const selectedCurrencyRates = computed(() =>
    workspace.rates.filter((item) => item.currencyId === workspace.selectedCurrencyId)
  )
  const rateTypeOptions = computed(() => getDictMap.value.fmsExchangeRateType ?? [])
  const rateSearchItems = computed<SearchFormItem[]>(() => [
    {
      label: '汇率记录',
      key: 'keyword',
      type: 'input',
      props: { clearable: true, placeholder: '搜索币种、来源或日期' }
    },
    {
      label: '汇率类型',
      key: 'rateType',
      type: 'select',
      props: { clearable: true, placeholder: '全部类型', options: rateTypeOptions.value }
    }
  ])
  const filteredRates = computed(() => {
    const keyword = appliedRateFilter.keyword.trim().toLowerCase()
    return workspace.rates.filter((item) => {
      const currency = item.currency
      const matchesCurrency =
        !workspace.selectedCurrencyId || item.currencyId === workspace.selectedCurrencyId
      const matchesType =
        !appliedRateFilter.rateType || item.rateType === appliedRateFilter.rateType
      const matchesKeyword =
        !keyword ||
        item.rateDate.includes(keyword) ||
        item.source?.toLowerCase().includes(keyword) ||
        currency?.currencyCode.toLowerCase().includes(keyword) ||
        currency?.currencyName.toLowerCase().includes(keyword)
      return matchesCurrency && matchesType && Boolean(matchesKeyword)
    })
  })
  const metrics = computed<BusinessWorkspaceMetric[]>(() => [
    {
      key: 'base',
      label: '本位币',
      value: baseCurrency.value?.currencyCode ?? '—',
      description: baseCurrency.value?.currencyName ?? '尚未初始化',
      icon: 'ri:money-cny-circle-line'
    },
    {
      key: 'currencies',
      label: '启用币种',
      value: workspace.currencies.filter((item) => item.isEnabled).length,
      description: `共 ${workspace.currencies.length} 个核算币种`,
      icon: 'ri:coins-line',
      tone: 'success'
    },
    {
      key: 'rates',
      label: '汇率记录',
      value: workspace.rates.length,
      description: '按日期和类型留存',
      icon: 'ri:line-chart-line',
      tone: 'warning'
    },
    {
      key: 'selected',
      label: '当前外币',
      value: selectedCurrency.value?.currencyCode ?? '—',
      description: selectedCurrency.value?.isBase ? '本位币无需折算' : '直接汇率维护范围',
      icon: 'ri:exchange-line',
      tone: 'info'
    }
  ])

  const columns: ColumnOption<ExchangeRate>[] = [
    {
      prop: 'rateDate',
      label: '汇率日期',
      width: 125,
      formatter: (row) => formatWithDayjs(row.rateDate, 'YYYY-MM-DD') || '—'
    },
    {
      prop: 'currency',
      label: '币种',
      width: 120,
      formatter: (row) => <strong>{row.currency?.currencyCode ?? '—'}</strong>
    },
    {
      prop: 'rateType',
      label: '汇率类型',
      width: 110,
      dict: { code: 'fmsExchangeRateType', display: 'tag' }
    },
    {
      prop: 'directRate',
      label: '直接汇率',
      minWidth: 150,
      align: 'right',
      formatter: (row) =>
        Number(row.directRate).toLocaleString('zh-CN', { maximumFractionDigits: 8 })
    },
    { prop: 'source', label: '来源', minWidth: 170, showOverflowTooltip: true },
    { prop: 'remark', label: '备注', minWidth: 180, showOverflowTooltip: true },
    ...(isPlatformSuper.value
      ? [
          {
            prop: 'operation',
            label: '操作',
            width: 80,
            fixed: 'right' as const,
            formatter: (row: ExchangeRate) => (
              <ArtButtonTable type="edit" onClick={() => openRateDialog(row)} />
            )
          } satisfies ColumnOption<ExchangeRate>
        ]
      : [])
  ]

  function createDefaultRateFilter(): RateFilter {
    return { keyword: '', rateType: undefined }
  }

  function getCurrencyActions(row: Currency): ButtonMoreItem[] {
    const actions: ButtonMoreItem[] = [{ key: 'edit', label: '编辑币种', icon: 'ri:edit-line' }]
    if (!row.isBase) {
      actions.push({
        key: 'toggle',
        label: row.isEnabled ? '停用币种' : '启用币种',
        icon: row.isEnabled ? 'ri:forbid-line' : 'ri:checkbox-circle-line',
        color: row.isEnabled ? 'var(--el-color-danger)' : 'var(--el-color-success)'
      })
    }
    return actions
  }

  function handleCurrencyAction(action: ButtonMoreItem, row: Currency): void {
    if (action.key === 'edit') {
      void openCurrencyDialog(row)
      return
    }
    if (action.key === 'toggle') void toggleCurrency(row)
  }

  function applyRateFilters(params: Record<string, unknown>): void {
    appliedRateFilter.keyword = typeof params.keyword === 'string' ? params.keyword : ''
    appliedRateFilter.rateType =
      typeof params.rateType === 'string'
        ? (params.rateType as Api.Fms.ExchangeRateType)
        : undefined
  }

  function resetRateFilters(): void {
    rateFilterForm.value = createDefaultRateFilter()
    Object.assign(appliedRateFilter, createDefaultRateFilter())
  }

  async function loadWorkspace(): Promise<void> {
    if (!scope.accountSetId) return
    workspace.loading = true
    workspace.error = ''
    try {
      const [currencyResult, rateResult] = await Promise.all([
        fetchCurrencyList(scope.accountSetId),
        fetchExchangeRateList(scope.accountSetId)
      ])
      workspace.currencies = currencyResult.data ?? []
      workspace.rates = rateResult.data ?? []
      if (!workspace.currencies.some((item) => item.id === workspace.selectedCurrencyId)) {
        workspace.selectedCurrencyId =
          workspace.currencies.find((item) => !item.isBase)?.id ?? workspace.currencies[0]?.id ?? ''
      }
    } catch (error) {
      workspace.error = error instanceof Error ? error.message : '币种与汇率加载失败'
    } finally {
      workspace.loading = false
    }
  }

  async function openCurrencyDialog(row?: Currency): Promise<void> {
    if (
      !(await ensureAccountSet({
        actionLabel: row ? '编辑核算币种' : '新增外币',
        available: Boolean(currentAccountSet.value)
      }))
    )
      return
    await currencyDialogRef.value?.handleOpen(currentAccountSet.value!, row)
  }

  async function openRateDialog(row?: ExchangeRate): Promise<void> {
    if (
      !(await ensureAccountSet({
        actionLabel: row ? '编辑汇率' : '新增汇率',
        available: Boolean(currentAccountSet.value)
      }))
    )
      return
    if (!row && !selectedCurrency.value) {
      ElMessage.info('请先在左侧选择一个已启用的外币')
      return
    }
    if (!row && selectedCurrency.value?.isBase) {
      ElMessage.info('本位币无需维护兑换汇率，请选择外币')
      return
    }
    if (!row && !selectedCurrency.value?.isEnabled) {
      ElMessage.info('请先启用该外币，再维护汇率')
      return
    }
    await rateDialogRef.value?.handleOpen(
      currentAccountSet.value!,
      workspace.currencies,
      selectedCurrency.value,
      row
    )
  }

  async function toggleCurrency(row: Currency): Promise<void> {
    await confirmAction(
      `确定${row.isEnabled ? '停用' : '启用'}币种“${row.currencyCode} ${row.currencyName}”吗？`,
      `${row.isEnabled ? '停用' : '启用'}核算币种`
    )
    await setCurrencyEnabled(row.id, !row.isEnabled)
    await loadWorkspace()
  }

  function handleAccountSetChange(): void {
    resetRateFilters()
    void loadWorkspace()
  }

  async function loadAccountSets(): Promise<void> {
    scope.loading = true
    try {
      const result = await fetchAccountSetOptions({ from: 0, to: 999 })
      scope.options = result.data ?? []
      if (!scope.accountSetId && scope.options.length) {
        scope.accountSetId = scope.options[0].value
        await loadWorkspace()
      }
    } finally {
      scope.loading = false
    }
  }

  onMounted(loadAccountSets)
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .accounting-currency-page {
    @include accounting.accounting-workspace-layout;

    &.is-focus-mode {
      gap: 0;
    }

    &__scope {
      display: grid;
      grid-template-columns: 76px minmax(280px, 560px);
      gap: 10px;
      align-items: center;

      > span {
        flex: none;
        font-size: 12px;
        font-weight: 600;
        line-height: 18px;
        color: var(--el-text-color-regular);
      }

      :deep(.el-select) {
        flex: 1;
      }
    }

    &__workspace {
      display: grid;
      flex: 1;
      grid-template-rows: minmax(0, 1fr);
      grid-template-columns: minmax(300px, 360px) minmax(0, 1fr);
      gap: 12px;
      min-width: 0;
      min-height: 0;

      &.is-focused {
        height: 100%;
      }

      > .accounting-workspace-fill-section {
        min-height: 0;
      }
    }

    &__currency-grid {
      display: grid;
      gap: 8px;
      padding-right: 4px;
    }

    &__currency-scrollbar {
      flex: 1;
      min-height: 0;
    }

    &__currency-card {
      display: grid;
      grid-template-columns: minmax(0, 1fr) 30px;
      gap: 6px;
      align-items: center;
      width: 100%;
      padding: 6px;
      color: var(--art-text-gray-800);
      text-align: left;
      background: var(--art-main-bg-color);
      border: 1px solid var(--art-border-dashed-color);
      border-radius: var(--el-border-radius-base);
      transition:
        color 0.18s ease,
        background-color 0.18s ease,
        border-color 0.18s ease,
        box-shadow 0.18s ease;

      &:hover,
      &:focus-within,
      &.is-active {
        background: color-mix(in srgb, var(--theme-color) 11%, var(--art-main-bg-color));
      }

      &.is-active {
        border-color: color-mix(in srgb, var(--theme-color) 62%, var(--el-border-color));
        box-shadow: inset 3px 0 0 var(--theme-color);
      }
    }

    &__currency-select {
      display: grid;
      grid-template-columns: 40px minmax(0, 1fr);
      gap: 10px;
      align-items: center;
      min-width: 0;
      padding: 4px;
      color: inherit;
      text-align: left;
      touch-action: manipulation;
      cursor: pointer;
      background: transparent;
      border: 0;
      border-radius: var(--el-border-radius-small);

      &:focus-visible {
        outline: 2px solid color-mix(in srgb, var(--theme-color) 55%, transparent);
        outline-offset: 1px;
      }
    }

    :global([data-box-mode='border-mode']) &__currency-card:hover,
    :global([data-box-mode='border-mode']) &__currency-card:focus-within,
    :global([data-box-mode='border-mode']) &__currency-card.is-active {
      border-color: color-mix(in srgb, var(--theme-color) 55%, var(--el-border-color));
      box-shadow:
        inset 3px 0 0 var(--theme-color),
        inset 0 0 0 1px color-mix(in srgb, var(--theme-color) 20%, transparent);
    }

    :global([data-box-mode='shadow-mode']) &__currency-card:hover,
    :global([data-box-mode='shadow-mode']) &__currency-card:focus-within,
    :global([data-box-mode='shadow-mode']) &__currency-card.is-active {
      border-color: transparent;
      box-shadow:
        inset 3px 0 0 var(--theme-color),
        0 8px 20px color-mix(in srgb, var(--theme-color) 16%, transparent);
    }

    &__symbol {
      display: grid;
      place-items: center;
      width: 40px;
      height: 40px;
      font-weight: 700;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 10%, transparent);
      border-radius: var(--custom-radius);
    }

    &__currency-card.is-active &__symbol {
      color: #fff;
      background: var(--theme-color);
    }

    &__currency-name {
      display: flex;
      flex-direction: column;
      gap: 4px;
      min-width: 0;
    }

    &__currency-title,
    &__currency-meta {
      display: flex;
      gap: 7px;
      align-items: center;
      min-width: 0;

      strong,
      small {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__currency-title strong {
      flex: 1;
      min-width: 0;
    }

    &__currency-meta {
      flex-wrap: nowrap;

      small {
        min-width: 0;
        color: var(--art-text-gray-500);
      }

      :deep(.el-tag) {
        flex: none;
      }
    }

    &__selected-badge {
      display: inline-flex;
      gap: 3px;
      align-items: center;
      font-size: 12px;
      font-weight: 650;
      color: var(--theme-color);
      white-space: nowrap;
    }

    &__currency-more {
      flex: none;
    }

    &__rate-search {
      margin-bottom: 12px;
    }

    &__rate-context {
      display: grid;
      grid-template-columns: 38px minmax(0, 1fr);
      gap: 10px;
      align-items: center;
      min-height: 50px;
      padding: 7px 10px;
      margin-bottom: 10px;
      background: color-mix(in srgb, var(--theme-color) 5%, var(--default-box-color));
      border: 1px solid color-mix(in srgb, var(--theme-color) 16%, var(--el-border-color));
      border-radius: var(--el-border-radius-base);

      strong,
      span {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      strong {
        display: flex;
        gap: 6px;
        align-items: center;
        font-size: 13px;
        color: var(--el-text-color-primary);
      }

      > div > span {
        display: block;
        margin-top: 2px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__rate-context-symbol {
      display: grid;
      place-items: center;
      width: 38px;
      height: 38px;
      font-weight: 700;
      color: var(--theme-color);
      background: color-mix(in srgb, var(--theme-color) 11%, transparent);
      border-radius: var(--el-border-radius-base);
    }
  }

  @media only screen and (width <= 1050px) {
    .accounting-currency-page__workspace {
      grid-template-rows: none;
      grid-template-columns: 1fr;

      > .accounting-workspace-fill-section {
        min-height: 216px;
      }
    }
  }

  @media only screen and (width <= 640px) {
    .accounting-currency-page {
      &__scope {
        grid-template-columns: 1fr;

        :deep(.el-select) {
          width: 100%;
        }
      }
    }
  }
</style>
