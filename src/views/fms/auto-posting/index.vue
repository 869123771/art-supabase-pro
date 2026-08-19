<template>
  <div class="business-workspace-page art-full-height fms-accounting-page auto-posting-page">
    <BusinessWorkspaceHeader
      density="compact"
      eyebrow="ACCOUNTING AUTOMATION"
      title="自动入账"
      description="以可审计的业务事件和制证规则连接结算、收付、发票、报销与总账，异常事件可追踪、可修复、可重试。"
      icon="ri:git-merge-line"
      :tags="[
        { label: '业务财务一体化', type: 'primary' },
        { label: '幂等制证', type: 'success' },
        { label: '职责分离', type: 'info' }
      ]"
    >
      <template #actions>
        <BusinessTableWorkspaceActions :table="activeTableRef" />
      </template>
    </BusinessWorkspaceHeader>

    <ElAlert
      v-if="!isPlatformSuper"
      type="info"
      :closable="false"
      show-icon
      title="当前账号可查看本租户规则与入账事件；规则维护、异常重试和批量处理仅平台超级管理员可执行。"
    />

    <ElTabs v-model="activeTab" class="auto-posting-page__tabs">
      <ElTabPane name="rules">
        <template #label>
          <span class="auto-posting-page__tab-label">
            <ArtSvgIcon icon="ri:flow-chart" />
            <span>
              <strong>制证规则</strong>
              <small>配置业务事件、会计科目与核算维度</small>
            </span>
          </span>
        </template>

        <ArtTableQuery
          ref="ruleTableRef"
          v-model="ruleTable.search"
          :search-items="ruleTable.searchItems"
          :api-fn="fetchRuleTableData"
          :columns-factory="ruleColumnsFactory"
          :header-actions="ruleTable.headerActions"
          header-actions-placement="workspace"
          :search-bar-props="{ span: 6, labelWidth: 86, showExpand: false }"
          :table-props="{
            rowKey: 'id',
            tableLayout: 'fixed',
            emptyText: '暂无自动入账规则',
            emptyDescription: '选择账套并新增首条规则，开始连接业务单据与会计凭证。'
          }"
          focusable
        />
      </ElTabPane>

      <ElTabPane name="events">
        <template #label>
          <span class="auto-posting-page__tab-label">
            <ArtSvgIcon icon="ri:pulse-line" />
            <span>
              <strong>事件监控</strong>
              <small>跟踪凭证生成、待配置与失败重试</small>
            </span>
          </span>
        </template>

        <ArtTableQuery
          ref="eventTableRef"
          v-model="eventTable.search"
          :search-items="eventTable.searchItems"
          :api-fn="fetchEventTableData"
          :columns-factory="eventColumnsFactory"
          :header-actions="eventTable.headerActions"
          header-actions-placement="workspace"
          :search-bar-props="{ span: 6, labelWidth: 86, showExpand: true }"
          :table-props="{
            rowKey: 'id',
            tableLayout: 'fixed',
            emptyText: '暂无自动入账事件',
            emptyDescription: '业务单据达到触发状态后，系统会在这里记录制证处理结果。'
          }"
          focusable
        />
      </ElTabPane>
    </ElTabs>

    <PostingRuleDialog ref="ruleDialogRef" @success="handleRuleSaved" />
    <PostingEventDetailDrawer ref="eventDetailRef" @view-voucher="openVoucherById" />
    <VoucherDetailDrawer ref="voucherDetailRef" />
  </div>
</template>

<script setup lang="tsx">
  import { ElButton, ElTag } from 'element-plus'
  import type { ComputedRef, UnwrapNestedRefs } from 'vue'
  import type { SearchFormItem } from '@/components/core/forms/art-search-bar/index.vue'
  import type {
    ArtTableQueryExpose,
    ArtTableQueryHeaderAction
  } from '@/components/core/tables/art-table-query/index.vue'
  import type { ColumnOption } from '@/types'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import BusinessTableWorkspaceActions from '@/components/business/business-table-workspace-actions/index.vue'
  import BusinessWorkspaceHeader from '@/components/business/business-workspace-header/index.vue'
  import { useFinanceAccountSetPrerequisite } from '../modules/use-finance-account-set-prerequisite'
  import { useUserStore } from '@/store/modules/user'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import { pageInfoHandler } from '@/utils/table/tableUtils'
  import { formatCurrencyValue } from '@/utils/ui'
  import { formatWithDayjs } from '@/utils/time'
  import {
    deletePostingRule,
    fetchAccountSetOptions,
    fetchAuxiliaryTypeList,
    fetchPostingEventList,
    fetchPostingRuleList,
    fetchSubjectList,
    fetchVoucherDetail,
    processPendingPostingEvents,
    retryPostingEvent
  } from '@/api/fms'
  import PostingRuleDialog from './modules/posting-rule-dialog.vue'
  import PostingEventDetailDrawer from './modules/posting-event-detail-drawer.vue'
  import VoucherDetailDrawer from '@/views/fms/voucher-center/modules/voucher-detail-drawer.vue'

  defineOptions({ name: 'FinanceAutoPosting' })

  type Rule = Api.Fms.PostingRuleRecord
  type Event = Api.Fms.PostingEventRecord
  type RuleParams = Api.Fms.PostingRuleSearchParams &
    Pick<Api.Common.PaginationParams, 'current' | 'size'>
  type EventParams = Api.Fms.PostingEventSearchParams &
    Pick<Api.Common.PaginationParams, 'current' | 'size'>

  interface RuleDialogContext {
    accountSet: Api.Fms.AccountSetOption
    subjects: Api.Fms.SubjectRecord[]
    auxiliaryTypes: Api.Fms.AuxiliaryTypeRecord[]
  }

  interface RuleDialogExpose {
    handleOpen: (context: RuleDialogContext, row?: Rule) => Promise<void>
  }

  interface EventDetailExpose {
    handleOpen: (row: Event) => Promise<void>
  }

  interface VoucherDetailExpose {
    handleOpen: (row: Api.Fms.VoucherRecord) => Promise<void>
  }

  interface RuleTableGroup {
    search: Api.Fms.PostingRuleSearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
  }

  interface EventTableGroup {
    search: Api.Fms.PostingEventSearchParams
    searchItems: ComputedRef<SearchFormItem[]>
    headerActions: ComputedRef<ArtTableQueryHeaderAction[]>
  }

  const { getDictMap, isPlatformSuper } = storeToRefs(useUserStore())
  const { confirm, confirmDelete } = useArtFeedback()
  const { ensureAccountSet } = useFinanceAccountSetPrerequisite()
  const route = useRoute()
  const postingEventStatuses = new Set<Api.Fms.PostingEventStatus>([
    'pending',
    'processing',
    'generated',
    'pending_configuration',
    'failed',
    'reversed',
    'ignored'
  ])
  const parsePostingEventStatus = (value: unknown): Api.Fms.PostingEventStatus | '' =>
    typeof value === 'string' && postingEventStatuses.has(value as Api.Fms.PostingEventStatus)
      ? (value as Api.Fms.PostingEventStatus)
      : ''
  const activeTab = ref<'rules' | 'events'>(route.query.tab === 'events' ? 'events' : 'rules')
  const accountSetOptions = ref<Api.Fms.AccountSetOption[]>([])
  const ruleTableRef = ref<ArtTableQueryExpose>()
  const eventTableRef = ref<ArtTableQueryExpose>()
  const activeTableRef = computed(() =>
    activeTab.value === 'rules' ? ruleTableRef.value : eventTableRef.value
  )
  const ruleDialogRef = ref<RuleDialogExpose>()
  const eventDetailRef = ref<EventDetailExpose>()
  const voucherDetailRef = ref<VoucherDetailExpose>()
  const ruleContext = shallowRef<RuleDialogContext>()

  const commonAccountSetSearchItem = (onChange?: () => void): SearchFormItem => ({
    label: '账套',
    key: 'accountSetId',
    type: 'select',
    props: {
      options: accountSetOptions.value,
      filterable: true,
      clearable: true,
      placeholder: '全部可查看账套',
      onChange
    }
  })

  const ruleTable: UnwrapNestedRefs<RuleTableGroup> = reactive<RuleTableGroup>({
    search: { accountSetId: '', sourceEvent: '', isEnabled: '', keyword: '' },
    searchItems: computed<SearchFormItem[]>(() => [
      commonAccountSetSearchItem(() => {
        ruleContext.value = undefined
      }),
      {
        label: '业务事件',
        key: 'sourceEvent',
        type: 'select',
        props: {
          options: getDictMap.value.fmsPostingSourceEvent ?? [],
          clearable: true,
          filterable: true
        }
      },
      {
        label: '启用状态',
        key: 'isEnabled',
        type: 'select',
        props: {
          options: (getDictMap.value.commonBoolean ?? []).map((item) => ({
            ...item,
            value: item.value === 'true'
          })),
          clearable: true
        }
      },
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { clearable: true, placeholder: '规则编码、名称或说明' }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() =>
      isPlatformSuper.value
        ? [
            {
              type: 'add',
              label: '新增规则',
              onClick: () => void openRuleDialog()
            }
          ]
        : []
    )
  })

  const eventTable: UnwrapNestedRefs<EventTableGroup> = reactive<EventTableGroup>({
    search: {
      accountSetId: '',
      sourceEvent: '',
      status: parsePostingEventStatus(route.query.status),
      eventDateRange: [],
      keyword: ''
    },
    searchItems: computed<SearchFormItem[]>(() => [
      commonAccountSetSearchItem(),
      {
        label: '业务事件',
        key: 'sourceEvent',
        type: 'select',
        props: {
          options: getDictMap.value.fmsPostingSourceEvent ?? [],
          clearable: true,
          filterable: true
        }
      },
      {
        label: '处理状态',
        key: 'status',
        type: 'select',
        props: { options: getDictMap.value.fmsPostingEventStatus ?? [], clearable: true }
      },
      {
        label: '业务日期',
        key: 'eventDateRange',
        type: 'date',
        props: {
          type: 'daterange',
          valueFormat: 'YYYY-MM-DD',
          rangeSeparator: '至',
          startPlaceholder: '开始日期',
          endPlaceholder: '结束日期',
          clearable: true
        }
      },
      {
        label: '关键词',
        key: 'keyword',
        type: 'input',
        props: { clearable: true, placeholder: '来源单号、摘要或异常信息' }
      }
    ]),
    headerActions: computed<ArtTableQueryHeaderAction[]>(() =>
      isPlatformSuper.value
        ? [
            {
              key: 'process-pending',
              label: '批量处理待办',
              icon: 'ri:refresh-line',
              buttonProps: { type: 'primary', plain: true },
              onClick: () => void handleBatchProcess()
            }
          ]
        : []
    )
  })

  function fetchRuleTableData(params: RuleParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchPostingRuleList({ ...params, from, to })
  }

  function fetchEventTableData(params: EventParams) {
    const { from, to } = pageInfoHandler({ current: params.current, size: params.size })
    return fetchPostingEventList({ ...params, from, to })
  }

  const ruleColumnsFactory = (): ColumnOption<Rule>[] => [
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'ruleCode',
      label: '规则编码',
      width: 190,
      formatter: (row) => <span class="auto-posting-page__code">{row.ruleCode}</span>
    },
    { prop: 'ruleName', label: '规则名称', minWidth: 210, showOverflowTooltip: true },
    {
      prop: 'sourceEvent',
      label: '业务事件',
      minWidth: 180,
      dict: { code: 'fmsPostingSourceEvent', display: 'tag' }
    },
    {
      prop: 'voucherType',
      label: '凭证类型',
      width: 112,
      dict: { code: 'fmsVoucherType', display: 'text' }
    },
    {
      prop: 'submissionMode',
      label: '生成状态',
      width: 140,
      dict: { code: 'fmsPostingSubmissionMode', display: 'tag' }
    },
    { prop: 'priority', label: '优先级', width: 88, align: 'center' },
    {
      prop: 'effectiveFrom',
      label: '有效期',
      width: 205,
      formatter: (row) => `${row.effectiveFrom || '即时'} 至 ${row.effectiveTo || '长期'}`
    },
    {
      prop: 'isEnabled',
      label: '状态',
      width: 88,
      formatter: (row) => (
        <ElTag type={row.isEnabled ? 'success' : 'info'}>{row.isEnabled ? '启用' : '停用'}</ElTag>
      )
    },
    {
      prop: 'operation',
      label: '操作',
      width: 140,
      fixed: 'right',
      formatter: (row) =>
        isPlatformSuper.value ? (
          <div class="auto-posting-page__actions">
            <ElButton link type="primary" onClick={() => void openRuleDialog(row)}>
              编辑
            </ElButton>
            <ElButton link type="danger" onClick={() => void handleDeleteRule(row)}>
              删除
            </ElButton>
          </div>
        ) : (
          <span>只读</span>
        )
    }
  ]

  const eventColumnsFactory = (): ColumnOption<Event>[] => [
    { type: 'globalIndex', label: '序号', width: 72 },
    {
      prop: 'sourceNo',
      label: '来源单号',
      minWidth: 190,
      formatter: (row) => (
        <ElButton link type="primary" onClick={() => void eventDetailRef.value?.handleOpen(row)}>
          {row.sourceNo || '查看事件'}
        </ElButton>
      )
    },
    {
      prop: 'sourceEvent',
      label: '业务事件',
      minWidth: 180,
      dict: { code: 'fmsPostingSourceEvent', display: 'tag' }
    },
    { prop: 'summary', label: '事件摘要', minWidth: 250, showOverflowTooltip: true },
    {
      prop: 'eventDate',
      label: '业务日期',
      width: 112,
      formatter: (row) => formatWithDayjs(row.eventDate, 'YYYY-MM-DD') ?? '—'
    },
    {
      prop: 'status',
      label: '处理状态',
      width: 124,
      dict: { code: 'fmsPostingEventStatus', display: 'tag' }
    },
    {
      prop: 'rule',
      label: '命中规则',
      minWidth: 180,
      showOverflowTooltip: true,
      formatter: (row) => row.rule?.ruleName || '—'
    },
    {
      prop: 'voucher',
      label: '生成凭证',
      minWidth: 150,
      formatter: (row) =>
        row.voucherId ? (
          <ElButton link type="primary" onClick={() => void openVoucherById(row.voucherId!)}>
            {row.voucher?.voucherNo || '查看凭证'}
          </ElButton>
        ) : (
          '—'
        )
    },
    {
      prop: 'amount',
      label: '业务金额',
      width: 130,
      align: 'right',
      formatter: (row) => formatCurrencyValue(Number(row.payload.gross_amount || 0))
    },
    { prop: 'attemptCount', label: '处理次数', width: 92, align: 'center' },
    {
      prop: 'operation',
      label: '操作',
      width: 150,
      fixed: 'right',
      formatter: (row) => (
        <div class="auto-posting-page__actions">
          <ElButton link type="primary" onClick={() => void eventDetailRef.value?.handleOpen(row)}>
            详情
          </ElButton>
          {isPlatformSuper.value && canRetry(row) ? (
            <ElButton link type="warning" onClick={() => void handleRetryEvent(row)}>
              重试
            </ElButton>
          ) : null}
        </div>
      )
    }
  ]

  async function loadRuleContext(): Promise<RuleDialogContext | undefined> {
    const accountSet = accountSetOptions.value.find(
      (item) => item.value === ruleTable.search.accountSetId
    )
    if (!accountSet) return undefined
    if (ruleContext.value?.accountSet.value === accountSet.value) return ruleContext.value
    const [subjectResult, auxiliaryTypeResult] = await Promise.all([
      fetchSubjectList(accountSet.value),
      fetchAuxiliaryTypeList(accountSet.value)
    ])
    ruleContext.value = {
      accountSet,
      subjects: subjectResult.data ?? [],
      auxiliaryTypes: auxiliaryTypeResult.data ?? []
    }
    return ruleContext.value
  }

  async function openRuleDialog(row?: Rule): Promise<void> {
    if (
      !(await ensureAccountSet({
        actionLabel: row ? '编辑自动入账规则' : '新增自动入账规则',
        activeRequired: true,
        available: Boolean(row?.accountSetId || ruleTable.search.accountSetId)
      }))
    )
      return
    if (row?.accountSetId && ruleTable.search.accountSetId !== row.accountSetId) {
      ruleTable.search.accountSetId = row.accountSetId
      ruleContext.value = undefined
    }
    const context = await loadRuleContext()
    if (context) await ruleDialogRef.value?.handleOpen(context, row)
  }

  async function handleDeleteRule(row: Rule): Promise<void> {
    try {
      await confirmDelete(
        `确定删除规则 ${row.ruleCode} · ${row.ruleName} 吗？已产生事件的规则只能停用。`
      )
      await deletePostingRule(row.id)
      await ruleTableRef.value?.refreshRemove()
    } catch {
      // 用户取消或后端阻止删除时，由统一反馈处理。
    }
  }

  function handleRuleSaved(): void {
    ruleContext.value = undefined
    void ruleTableRef.value?.refreshUpdate()
  }

  function canRetry(row: Event): boolean {
    return ['pending', 'pending_configuration', 'failed'].includes(row.status)
  }

  async function handleRetryEvent(row: Event): Promise<void> {
    await retryPostingEvent(row.id)
    await eventTableRef.value?.refreshUpdate()
  }

  async function handleBatchProcess(): Promise<void> {
    try {
      await confirm('系统将重新处理最多 50 条待处理、待配置或失败事件，是否继续？', {
        title: '批量处理确认',
        confirmButtonText: '开始处理'
      })
      await processPendingPostingEvents(50)
      await eventTableRef.value?.refreshUpdate()
    } catch {
      // 用户取消时无需提示。
    }
  }

  async function openVoucherById(voucherId: string): Promise<void> {
    const { data } = await fetchVoucherDetail(voucherId)
    if (data) await voucherDetailRef.value?.handleOpen(data)
  }

  async function loadAccountSets(): Promise<void> {
    const { data } = await fetchAccountSetOptions({ status: 'active', from: 0, to: 999 })
    accountSetOptions.value = data ?? []
    const defaultId = accountSetOptions.value[0]?.value ?? ''
    if (!ruleTable.search.accountSetId) ruleTable.search.accountSetId = defaultId
    if (!eventTable.search.accountSetId) eventTable.search.accountSetId = defaultId
    await nextTick()
    await Promise.all([ruleTableRef.value?.getData(), eventTableRef.value?.getData()])
  }

  onMounted(() => void loadAccountSets())

  watch(
    () => [route.query.tab, route.query.status] as const,
    ([tab, status]) => {
      let changed = false
      const nextStatus = parsePostingEventStatus(status)
      if (tab === 'events' && activeTab.value !== 'events') {
        activeTab.value = 'events'
        changed = true
      }
      if (eventTable.search.status !== nextStatus) {
        eventTable.search.status = nextStatus
        changed = true
      }
      if (changed && activeTab.value === 'events') void eventTableRef.value?.getData()
    }
  )
</script>

<style scoped lang="scss">
  @use '../modules/accounting-workspace.scss' as accounting;

  .auto-posting-page {
    @include accounting.accounting-workspace-layout;

    &__tabs {
      @include accounting.accounting-workspace-tabs;
    }

    &__tab-label {
      @include accounting.accounting-workspace-tab-label;
    }

    &__code {
      font-weight: 600;
      font-variant-numeric: tabular-nums;
      color: var(--el-color-primary);
    }

    &__actions {
      display: flex;
      align-items: center;
    }

    @media (width <= 640px) {
      &__tab-label > span small {
        display: none;
      }
    }
  }
</style>
