<template>
  <div class="ai-planner">
    <section class="ai-planner__hero art-card-xs">
      <div class="ai-planner__hero-copy">
        <div class="ai-planner__brand"><ArtSvgIcon icon="ri:compass-3-line" /></div>
        <div>
          <span class="ai-planner__eyebrow">PROJECT NEXT STEP</span>
          <h1>AI 项目规划台</h1>
          <p>结合当前代码、Supabase 能力与历史反馈，生成可直接交给 Codex 的下一步提示词。</p>
          <div class="ai-planner__access-note">
            <ArtSvgIcon :icon="canManageWorkflow ? 'ri:admin-line' : 'ri:shield-check-line'" />
            <span>
              {{
                canManageWorkflow
                  ? '管理员规划模式：可推进建议状态'
                  : '普通用户只读分析：可查询、生成与复用建议，不修改业务数据'
              }}
            </span>
          </div>
        </div>
      </div>
      <div class="ai-planner__controls">
        <ElSelect v-model="controls.focus" class="ai-planner__select" placeholder="关注方向">
          <ElOption label="综合平衡" value="balanced" />
          <ElOption
            v-for="item in categoryOptions"
            :key="String(item.value)"
            :label="String(item.label)"
            :value="String(item.value)"
          />
        </ElSelect>
        <ElSelect v-model="controls.effort" class="ai-planner__select" placeholder="工作量">
          <ElOption
            v-for="item in effortOptions"
            :key="String(item.value)"
            :label="String(item.label)"
            :value="String(item.value)"
          />
        </ElSelect>
        <ElButton
          type="primary"
          :loading="loading.generate"
          :disabled="capabilities !== null && !capabilities.providerConfigured"
          @click="handleGenerate"
        >
          <ArtSvgIcon icon="ri:sparkling-2-line" />
          生成下一步
        </ElButton>
      </div>
    </section>

    <ElAlert
      v-if="capabilities && !capabilities.providerConfigured"
      class="ai-planner__alert"
      title="尚未配置 AI 模型服务"
      description="请在 Supabase Edge Function Secrets 中设置 AI_API_KEY、AI_BASE_URL 和 AI_MODEL。密钥只保存在服务端，不会进入浏览器或数据库。"
      type="warning"
      show-icon
      :closable="false"
    />

    <section class="ai-planner__decision-grid" :class="{ 'has-priority': prioritySuggestion }">
      <section v-if="prioritySuggestion" class="ai-planner__priority art-card-xs">
        <div class="ai-planner__priority-main">
          <div class="ai-planner__priority-icon"><ArtSvgIcon icon="ri:focus-3-line" /></div>
          <div>
            <span class="ai-planner__priority-eyebrow">AI PRIORITY</span>
            <strong>建议优先推进：{{ prioritySuggestion.title }}</strong>
            <p>{{ prioritySuggestion.summary }}</p>
          </div>
        </div>
        <div class="ai-planner__priority-score">
          <div>
            <span>影响力</span>
            <strong>{{ prioritySuggestion.impact }}/5</strong>
          </div>
          <div>
            <span>置信度</span>
            <strong>{{ Math.round(prioritySuggestion.confidence * 100) }}%</strong>
          </div>
          <div>
            <span>投入</span>
            <strong>{{ dictLabel('aiSuggestionEffort', prioritySuggestion.effort) }}</strong>
          </div>
        </div>
        <div class="ai-planner__priority-actions">
          <ElButton
            :loading="isActionPending(prioritySuggestion.id, 'copied')"
            :disabled="isSuggestionPending(prioritySuggestion.id)"
            @click="handleCopy(prioritySuggestion)"
          >
            <ArtSvgIcon icon="ri:file-copy-line" />复制 Prompt
          </ElButton>
          <ElButton
            v-if="canManageWorkflow"
            type="primary"
            :loading="isActionPending(prioritySuggestion.id, 'accepted')"
            :disabled="isSuggestionPending(prioritySuggestion.id)"
            @click="handleWorkflow(prioritySuggestion, 'accepted')"
          >
            <ArtSvgIcon icon="ri:check-line" />采纳优先建议
          </ElButton>
        </div>
      </section>

      <section class="ai-planner__metrics">
        <article v-for="metric in metrics" :key="metric.label" class="art-card-xs">
          <div :class="['ai-planner__metric-icon', `is-${metric.tone}`]">
            <ArtSvgIcon :icon="metric.icon" />
          </div>
          <div>
            <span>{{ metric.label }}</span>
            <strong>{{ metric.value }}</strong>
            <small>{{ metric.hint }}</small>
          </div>
        </article>
      </section>
    </section>

    <section class="ai-planner__control-panel art-card-xs">
      <header class="ai-planner__toolbar">
        <div>
          <strong>建议池</strong>
          <span v-if="latestBatchHasSuggestions && state.latestBatch">
            最近由 {{ state.latestBatch.model }} 生成 ·
            {{ formatTime(state.latestBatch.createTime) }}
          </span>
          <span v-else-if="latestAvailableSuggestions.length">
            最近可用建议 · {{ formatTime(latestAvailableSuggestions[0].createTime) }}
          </span>
          <span v-else-if="capabilities?.providerConfigured">
            已连接 {{ capabilities.provider }} · {{ capabilities.model }}
          </span>
          <span v-else>生成后会根据反馈持续调整排序</span>
        </div>
        <div class="ai-planner__toolbar-actions">
          <ElSegmented v-model="filters.status" :options="statusFilterOptions" />
          <ElTooltip content="刷新建议" placement="bottom">
            <ArtIconButton
              icon="ri:refresh-line"
              circle
              :loading="loading.state"
              @click="loadState(true)"
            />
          </ElTooltip>
        </div>
      </header>

      <section v-if="state.suggestions.length" class="ai-planner__filters">
        <ElSelect v-model="filters.batchId" class="ai-planner__batch-select" placeholder="生成批次">
          <ElOption
            v-for="item in batchOptions"
            :key="item.value"
            :label="item.label"
            :value="item.value"
          />
        </ElSelect>
        <ElInput
          v-model="filters.keyword"
          clearable
          class="ai-planner__filter-search"
          placeholder="搜索标题、说明、证据或风险"
        >
          <template #prefix><ArtSvgIcon icon="ri:search-line" /></template>
        </ElInput>
        <ElSelect
          v-model="filters.category"
          class="ai-planner__filter-select"
          placeholder="能力类别"
        >
          <ElOption label="全部类别" value="all" />
          <ElOption
            v-for="item in categoryOptions"
            :key="String(item.value)"
            :label="String(item.label)"
            :value="String(item.value)"
          />
        </ElSelect>
        <ElSelect v-model="filters.effort" class="ai-planner__filter-select" placeholder="工作量">
          <ElOption label="全部工作量" value="all" />
          <ElOption
            v-for="item in effortFilterOptions"
            :key="String(item.value)"
            :label="String(item.label)"
            :value="String(item.value)"
          />
        </ElSelect>
        <ElSelect v-model="filters.sort" class="ai-planner__filter-sort" placeholder="排序方式">
          <ElOption
            v-for="item in sortOptions"
            :key="item.value"
            :label="item.label"
            :value="item.value"
          />
        </ElSelect>
        <div class="ai-planner__filter-result">
          <span>显示 {{ filteredSuggestions.length }} / {{ scopedSuggestions.length }} 条</span>
          <ElButton v-if="hasActiveFilters" link type="primary" @click="resetFilters">
            <ArtSvgIcon icon="ri:filter-off-line" />清除筛选
          </ElButton>
        </div>
      </section>
    </section>

    <div v-loading="loading.state" class="ai-planner__list">
      <section
        v-if="!state.suggestions.length && !loading.state"
        class="ai-planner__empty art-card-xs"
      >
        <div class="ai-planner__empty-main">
          <div class="ai-planner__empty-visual" aria-hidden="true">
            <span><ArtSvgIcon icon="ri:code-box-line" /></span>
            <strong><ArtSvgIcon icon="ri:sparkling-2-line" /></strong>
            <span><ArtSvgIcon icon="ri:database-2-line" /></span>
          </div>
          <div class="ai-planner__empty-copy">
            <span class="ai-planner__empty-eyebrow">READY FOR FIRST ANALYSIS</span>
            <h2>让 AI 为项目排出下一步</h2>
            <p>
              综合当前代码结构、Supabase 能力和历史反馈，生成带证据、风险与验收标准的可执行建议。
            </p>
            <div class="ai-planner__empty-badges">
              <span><ArtSvgIcon icon="ri:shield-check-line" />只读分析</span>
              <span><ArtSvgIcon icon="ri:file-copy-2-line" />一键复制 Prompt</span>
              <span><ArtSvgIcon icon="ri:history-line" />反馈持续优化</span>
            </div>
            <ElButton
              type="primary"
              size="large"
              :loading="loading.generate"
              :disabled="capabilities !== null && !capabilities.providerConfigured"
              @click="handleGenerate"
            >
              <ArtSvgIcon icon="ri:sparkling-2-line" />生成第一批项目建议
            </ElButton>
          </div>
        </div>

        <div class="ai-planner__empty-flow" aria-label="AI 项目规划流程">
          <article>
            <span>01</span>
            <div>
              <strong>读取项目现状</strong>
              <p>识别代码结构、现有能力和运行边界</p>
            </div>
          </article>
          <article>
            <span>02</span>
            <div>
              <strong>评估机会优先级</strong>
              <p>综合影响、投入、风险和置信度排序</p>
            </div>
          </article>
          <article>
            <span>03</span>
            <div>
              <strong>交付执行 Prompt</strong>
              <p>输出可直接交给 Codex 的任务与验收标准</p>
            </div>
          </article>
        </div>
      </section>

      <div
        v-else-if="!filteredSuggestions.length && !loading.state"
        class="ai-planner__filtered-empty art-card-xs"
      >
        <div class="ai-planner__filtered-empty-icon">
          <ArtSvgIcon icon="ri:search-eye-line" />
        </div>
        <div>
          <strong>没有符合当前筛选条件的建议</strong>
          <p>可以调整关键词、批次或能力类别，或者清除全部筛选条件。</p>
        </div>
        <ElButton type="primary" plain @click="resetFilters">
          <ArtSvgIcon icon="ri:filter-off-line" />清除筛选
        </ElButton>
      </div>

      <article
        v-for="(suggestion, displayIndex) in filteredSuggestions"
        :key="suggestion.id"
        v-loading="isSuggestionPending(suggestion.id)"
        element-loading-text="正在更新建议..."
        :class="{ 'is-processing': isSuggestionPending(suggestion.id) }"
        class="ai-planner__suggestion art-card-xs"
      >
        <header>
          <div class="ai-planner__rank">{{ displayIndex + 1 }}</div>
          <div class="ai-planner__title">
            <div>
              <ElTag
                :type="dictTagType('aiSuggestionCategory', suggestion.category)"
                effect="light"
              >
                {{ dictLabel('aiSuggestionCategory', suggestion.category) }}
              </ElTag>
              <ElTag :type="dictTagType('aiSuggestionStatus', suggestion.status)" effect="plain">
                {{ dictLabel('aiSuggestionStatus', suggestion.status) }}
              </ElTag>
            </div>
            <h2>{{ suggestion.title }}</h2>
            <p>{{ suggestion.summary }}</p>
          </div>
          <div class="ai-planner__scores">
            <span>
              <ArtSvgIcon icon="ri:bar-chart-box-line" />
              影响 <strong>{{ suggestion.impact }}/5</strong>
            </span>
            <span>
              <ArtSvgIcon icon="ri:time-line" />
              工作量 <strong>{{ dictLabel('aiSuggestionEffort', suggestion.effort) }}</strong>
            </span>
            <span>
              <ArtSvgIcon icon="ri:shield-check-line" />
              置信度 <strong>{{ Math.round(suggestion.confidence * 100) }}%</strong>
            </span>
          </div>
        </header>

        <div class="ai-planner__context">
          <div class="is-opportunity">
            <span><ArtSvgIcon icon="ri:flashlight-line" />为什么现在做</span>
            <p>{{ suggestion.whyNow }}</p>
          </div>
          <div class="is-evidence">
            <span><ArtSvgIcon icon="ri:code-box-line" />项目证据</span>
            <ul>
              <li v-for="item in suggestion.evidence" :key="`${item.path}-${item.fact}`">
                <code>{{ item.path }}</code> {{ item.fact }}
              </li>
            </ul>
          </div>
          <div class="is-risk">
            <span><ArtSvgIcon icon="ri:error-warning-line" />主要风险</span>
            <p>{{ suggestion.risk }}</p>
          </div>
        </div>

        <ElCollapse
          class="ai-planner__collapse"
          @change="(names) => handleExpand(suggestion, names)"
        >
          <ElCollapseItem name="prompt">
            <template #title>
              <span class="ai-planner__prompt-toggle">
                <ArtSvgIcon icon="ri:terminal-box-line" />
                查看可复制的 Codex 提示词
                <small>{{ suggestion.acceptanceCriteria.length }} 项验收标准</small>
              </span>
            </template>
            <ElScrollbar max-height="460px" class="ai-planner__prompt-scroll">
              <pre>{{ suggestion.prompt }}</pre>
            </ElScrollbar>
            <div class="ai-planner__criteria">
              <strong>验收标准</strong>
              <ol>
                <li v-for="item in suggestion.acceptanceCriteria" :key="item">{{ item }}</li>
              </ol>
            </div>
          </ElCollapseItem>
        </ElCollapse>

        <footer>
          <div class="ai-planner__action-group">
            <span class="ai-planner__action-label">反馈与复用</span>
            <div class="ai-planner__feedback">
              <ElTooltip content="复制完整提示词">
                <ElButton
                  :loading="isActionPending(suggestion.id, 'copied')"
                  :disabled="isSuggestionPending(suggestion.id)"
                  @click="handleCopy(suggestion)"
                >
                  <ArtSvgIcon icon="ri:file-copy-line" />
                  复制{{ suggestion.feedback.copied ? ` · ${suggestion.feedback.copied}` : '' }}
                </ElButton>
              </ElTooltip>
              <ElButton
                :type="suggestion.feedback.sentiment === 1 ? 'success' : ''"
                :loading="isActionPending(suggestion.id, 'liked')"
                :disabled="isSuggestionPending(suggestion.id)"
                @click="handleFeedback(suggestion, 'liked')"
              >
                <ArtSvgIcon icon="ri:thumb-up-line" />
                有帮助
              </ElButton>
              <ElDropdown
                trigger="click"
                :disabled="isSuggestionPending(suggestion.id)"
                @command="(reason) => handleFeedback(suggestion, 'disliked', String(reason))"
              >
                <ElButton
                  :type="suggestion.feedback.sentiment === -1 ? 'danger' : ''"
                  :loading="isActionPending(suggestion.id, 'disliked')"
                  :disabled="isSuggestionPending(suggestion.id)"
                >
                  <ArtSvgIcon icon="ri:thumb-down-line" />
                  不合适
                </ElButton>
                <template #dropdown>
                  <ElDropdownMenu>
                    <ElDropdownItem
                      v-for="item in feedbackReasonOptions"
                      :key="String(item.value)"
                      :command="item.value"
                    >
                      {{ item.label }}
                    </ElDropdownItem>
                  </ElDropdownMenu>
                </template>
              </ElDropdown>
            </div>
          </div>
          <div v-if="canManageWorkflow" class="ai-planner__action-group is-workflow">
            <span class="ai-planner__action-label">推进决策</span>
            <div class="ai-planner__workflow">
              <ElButton
                v-if="suggestion.status === 'active'"
                :loading="isActionPending(suggestion.id, 'dismissed')"
                :disabled="isSuggestionPending(suggestion.id)"
                @click="handleWorkflow(suggestion, 'dismissed')"
              >
                <ArtSvgIcon icon="ri:inbox-archive-line" />
                暂不考虑
              </ElButton>
              <ElButton
                v-if="suggestion.status === 'active'"
                type="primary"
                :loading="isActionPending(suggestion.id, 'accepted')"
                :disabled="isSuggestionPending(suggestion.id)"
                @click="handleWorkflow(suggestion, 'accepted')"
              >
                <ArtSvgIcon icon="ri:check-line" />
                采纳
              </ElButton>
              <ElButton
                v-if="suggestion.status === 'active' || suggestion.status === 'accepted'"
                type="success"
                :loading="isActionPending(suggestion.id, 'completed')"
                :disabled="isSuggestionPending(suggestion.id)"
                @click="handleWorkflow(suggestion, 'completed')"
              >
                <ArtSvgIcon icon="ri:verified-badge-line" />
                标记完成
              </ElButton>
              <div v-if="suggestion.status === 'dismissed'" class="ai-planner__status-note">
                <ArtSvgIcon icon="ri:inbox-archive-line" />已暂不考虑
              </div>
              <ElButton
                v-if="suggestion.status === 'dismissed'"
                type="primary"
                plain
                :loading="isActionPending(suggestion.id, 'restored')"
                :disabled="isSuggestionPending(suggestion.id)"
                @click="handleWorkflow(suggestion, 'restored')"
              >
                <ArtSvgIcon icon="ri:arrow-go-back-line" />
                恢复评估
              </ElButton>
              <div
                v-else-if="suggestion.status === 'completed'"
                class="ai-planner__status-note is-completed"
              >
                <ArtSvgIcon icon="ri:verified-badge-line" />已完成
              </div>
            </div>
          </div>
          <div v-else class="ai-planner__read-only-note">
            <ArtSvgIcon icon="ri:shield-check-line" />
            <span>只读模式：可查看、反馈和复制建议；建议状态由管理员推进</span>
          </div>
        </footer>
      </article>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import dayjs from 'dayjs'
  import { countBy, groupBy, orderBy } from 'lodash-es'
  import { ElMessage } from 'element-plus'
  import type { TagProps } from 'element-plus'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import {
    fetchAiPlannerCapabilities,
    fetchAiPlannerState,
    generateAiSuggestions,
    recordAiSuggestionEvent
  } from '@/api/ai-project-planner'
  import type {
    AiPlannerCapabilities,
    AiPlannerEffort,
    AiPlannerState,
    AiProjectSuggestion,
    AiSuggestionCategory,
    AiSuggestionEffort,
    AiSuggestionEventType,
    AiSuggestionStatus
  } from '@/types/ai-project-planner'

  defineOptions({ name: 'AiProjectPlanner' })

  type DictCode =
    | 'aiSuggestionCategory'
    | 'aiSuggestionStatus'
    | 'aiSuggestionEffort'
    | 'aiSuggestionFeedbackReason'
  type SuggestionPendingAction = Extract<
    AiSuggestionEventType,
    'copied' | 'liked' | 'disliked' | 'accepted' | 'completed' | 'dismissed' | 'restored'
  >
  type SuggestionSort = 'recommended' | 'quick_win' | 'impact' | 'confidence' | 'recent'

  const LATEST_BATCH = '__latest__'
  const ALL_BATCHES = '__all__'

  interface Metric {
    label: string
    value: string
    hint: string
    icon: string
    tone: 'primary' | 'success' | 'warning' | 'info'
  }

  interface FilterGroup {
    batchId: string
    keyword: string
    status: AiSuggestionStatus | 'all'
    category: AiSuggestionCategory | 'all'
    effort: AiPlannerEffort | 'all'
    sort: SuggestionSort
  }

  interface SortOption {
    label: string
    value: SuggestionSort
  }

  interface BatchOption {
    label: string
    value: string
  }

  const userStore = useUserStore()
  const { getDictMap, isPlatformSuper } = storeToRefs(userStore)
  const capabilities = ref<AiPlannerCapabilities | null>(null)
  const state = reactive<AiPlannerState>({
    latestBatch: null,
    suggestions: [],
    preferenceSummary: {
      totalSignals: 0,
      categoryScores: {
        product: 0,
        business: 0,
        ui_ux: 0,
        security: 0,
        performance: 0,
        quality: 0,
        developer_experience: 0
      },
      preferredCategories: [],
      avoidedCategories: []
    },
    statusCounts: { active: 0, accepted: 0, completed: 0, dismissed: 0, expired: 0 },
    snapshot: { schemaVersion: '', generatedAt: '', sourceHash: '', sourceVersion: '' }
  })
  const controls = reactive<{ focus: 'balanced' | AiSuggestionCategory; effort: AiPlannerEffort }>({
    focus: 'balanced',
    effort: 'mixed'
  })
  const loading = reactive({ state: false, generate: false })
  const pendingActions = reactive<Record<string, SuggestionPendingAction | undefined>>({})
  const filters = reactive<FilterGroup>({
    batchId: LATEST_BATCH,
    keyword: '',
    status: 'all',
    category: 'all',
    effort: 'all',
    sort: 'recommended'
  })
  const expandedTracked = new Set<string>()
  let silentSyncVersion = 0

  const canManageWorkflow = computed(
    () => capabilities.value?.access?.canManageWorkflow ?? isPlatformSuper.value
  )

  const sortOptions: SortOption[] = [
    { label: '智能推荐排序', value: 'recommended' },
    { label: '优先快速收益', value: 'quick_win' },
    { label: '影响力优先', value: 'impact' },
    { label: '置信度优先', value: 'confidence' },
    { label: '最近生成优先', value: 'recent' }
  ]

  const categoryOptions = computed(() => getDictMap.value.aiSuggestionCategory ?? [])
  const effortOptions = computed(() => getDictMap.value.aiSuggestionEffort ?? [])
  const effortFilterOptions = computed(() =>
    effortOptions.value.filter((option) => option.value !== 'mixed')
  )
  const feedbackReasonOptions = computed(() => getDictMap.value.aiSuggestionFeedbackReason ?? [])
  const statusFilterOptions = computed(() => [
    { label: '全部', value: 'all' },
    ...(getDictMap.value.aiSuggestionStatus ?? [])
      .filter((item) => item.value !== 'expired')
      .map((item) => ({ label: String(item.label), value: String(item.value) }))
  ])
  const suggestionBatches = computed(() =>
    orderBy(
      Object.entries(groupBy(state.suggestions, (suggestion) => suggestion.batchId)),
      ([, suggestions]) => suggestions[0]?.createTime ?? '',
      ['desc']
    )
  )
  const latestAvailableBatchId = computed(() => suggestionBatches.value[0]?.[0])
  const latestBatchHasSuggestions = computed(() =>
    state.latestBatch?.id
      ? state.suggestions.some((suggestion) => suggestion.batchId === state.latestBatch?.id)
      : false
  )
  const latestBatchId = computed(() =>
    latestBatchHasSuggestions.value ? state.latestBatch?.id : latestAvailableBatchId.value
  )
  const latestAvailableSuggestions = computed(() =>
    latestBatchId.value
      ? (groupBy(state.suggestions, (suggestion) => suggestion.batchId)[latestBatchId.value] ?? [])
      : []
  )
  const batchOptions = computed<BatchOption[]>(() => {
    const latestSuggestions = latestAvailableSuggestions.value
    const historyOptions = suggestionBatches.value
      .filter(([batchId]) => batchId !== latestBatchId.value)
      .map(([batchId, suggestions], index) => {
        const batchTime = suggestions[0]?.createTime ?? ''
        return {
          value: batchId,
          label: `历史批次 ${index + 1} · ${formatTime(batchTime)} · ${suggestions.length} 条`
        }
      })
    return [
      {
        value: LATEST_BATCH,
        label: latestSuggestions.length
          ? `${latestBatchHasSuggestions.value ? '最新批次' : '最新可用批次'} · ${formatTime(latestSuggestions[0].createTime)} · ${latestSuggestions.length} 条`
          : '暂无可用批次'
      },
      { value: ALL_BATCHES, label: `全部历史批次 · ${state.suggestions.length} 条` },
      ...historyOptions
    ]
  })
  const scopedSuggestions = computed(() => {
    if (filters.batchId === ALL_BATCHES) return state.suggestions
    const selectedBatchId = filters.batchId === LATEST_BATCH ? latestBatchId.value : filters.batchId
    return selectedBatchId
      ? state.suggestions.filter((suggestion) => suggestion.batchId === selectedBatchId)
      : state.suggestions
  })
  const scopedStatusCounts = computed(() => {
    const counts = countBy(scopedSuggestions.value, (suggestion) => suggestion.status)
    return {
      active: counts.active ?? 0,
      accepted: counts.accepted ?? 0,
      completed: counts.completed ?? 0,
      dismissed: counts.dismissed ?? 0,
      expired: counts.expired ?? 0
    }
  })
  const filteredSuggestions = computed(() => {
    const keyword = filters.keyword.trim().toLowerCase()
    const matches = scopedSuggestions.value.filter((suggestion) => {
      if (filters.status !== 'all' && suggestion.status !== filters.status) return false
      if (filters.category !== 'all' && suggestion.category !== filters.category) return false
      if (filters.effort !== 'all' && suggestion.effort !== filters.effort) return false
      if (!keyword) return true
      const searchableText = [
        suggestion.title,
        suggestion.summary,
        suggestion.whyNow,
        suggestion.risk,
        ...suggestion.evidence.flatMap((item) => [item.path, item.fact])
      ]
        .join(' ')
        .toLowerCase()
      return searchableText.includes(keyword)
    })

    if (filters.sort === 'quick_win') {
      const effortScore: Record<AiSuggestionEffort, number> = { small: 3, medium: 2, large: 1 }
      return orderBy(
        matches,
        [
          (item) => item.impact * effortScore[item.effort] * item.confidence,
          (item) => item.rankScore
        ],
        ['desc', 'desc']
      )
    }
    if (filters.sort === 'impact')
      return orderBy(matches, ['impact', 'confidence'], ['desc', 'desc'])
    if (filters.sort === 'confidence') {
      return orderBy(matches, ['confidence', 'impact'], ['desc', 'desc'])
    }
    if (filters.sort === 'recent') return orderBy(matches, ['createTime'], ['desc'])
    return orderBy(matches, ['rankScore', 'position'], ['desc', 'asc'])
  })
  const prioritySuggestion = computed(
    () =>
      orderBy(
        scopedSuggestions.value.filter((item) => item.status === 'active'),
        ['rankScore', 'impact', 'confidence'],
        ['desc', 'desc', 'desc']
      )[0]
  )
  const hasActiveFilters = computed(
    () =>
      Boolean(filters.keyword.trim()) ||
      filters.batchId !== LATEST_BATCH ||
      filters.status !== 'all' ||
      filters.category !== 'all' ||
      filters.effort !== 'all' ||
      filters.sort !== 'recommended'
  )
  const metrics = computed<Metric[]>(() => [
    {
      label: '待评估',
      value: String(scopedStatusCounts.value.active),
      hint: '等待选择的下一步',
      icon: 'ri:lightbulb-flash-line',
      tone: 'primary'
    },
    {
      label: '已采纳',
      value: String(scopedStatusCounts.value.accepted),
      hint: '已进入实施队列',
      icon: 'ri:checkbox-circle-line',
      tone: 'warning'
    },
    {
      label: '已完成',
      value: String(scopedStatusCounts.value.completed),
      hint: '已产生项目进展',
      icon: 'ri:verified-badge-line',
      tone: 'success'
    },
    {
      label: '偏好信号',
      value: String(state.preferenceSummary.totalSignals),
      hint: preferenceHint.value,
      icon: 'ri:radar-line',
      tone: 'info'
    }
  ])
  const preferenceHint = computed(() => {
    const preferred = state.preferenceSummary.preferredCategories[0]
    return preferred
      ? `当前偏好：${dictLabel('aiSuggestionCategory', preferred)}`
      : '点赞、复制、采纳都会参与排序'
  })

  function assignState(next: AiPlannerState): void {
    Object.assign(state, next)
  }

  function dictItem(code: DictCode, value: string) {
    return (getDictMap.value[code] ?? []).find((item) => String(item.value) === value)
  }

  function dictLabel(code: DictCode, value: string): string {
    return String(dictItem(code, value)?.label ?? value)
  }

  function dictTagType(code: DictCode, value: string): TagProps['type'] {
    const type = dictItem(code, value)?.tagType
    return ['primary', 'success', 'warning', 'info', 'danger'].includes(String(type))
      ? (type as TagProps['type'])
      : 'info'
  }

  function formatTime(value: string): string {
    return value ? dayjs(value).format('YYYY-MM-DD HH:mm') : '—'
  }

  function isSuggestionPending(suggestionId: string): boolean {
    return Boolean(pendingActions[suggestionId])
  }

  function isActionPending(suggestionId: string, action: SuggestionPendingAction): boolean {
    return pendingActions[suggestionId] === action
  }

  function resetFilters(): void {
    Object.assign(filters, {
      batchId: LATEST_BATCH,
      keyword: '',
      status: 'all',
      category: 'all',
      effort: 'all',
      sort: 'recommended'
    } satisfies FilterGroup)
  }

  function applySuggestionStatus(
    suggestion: AiProjectSuggestion,
    nextStatus: Extract<AiSuggestionStatus, 'active' | 'accepted' | 'completed' | 'dismissed'>
  ): void {
    const previousStatus = suggestion.status
    if (previousStatus === nextStatus) return
    state.statusCounts[previousStatus] = Math.max(0, state.statusCounts[previousStatus] - 1)
    state.statusCounts[nextStatus] += 1
    suggestion.status = nextStatus
    const changedAt = new Date().toISOString()
    if (nextStatus === 'accepted') suggestion.acceptedAt = changedAt
    if (nextStatus === 'completed') suggestion.completedAt = changedAt
    if (nextStatus === 'dismissed') suggestion.dismissedAt = changedAt
    if (nextStatus === 'active') suggestion.dismissedAt = null
    suggestion.updateTime = changedAt
  }

  async function syncStateSilently(): Promise<void> {
    const requestVersion = ++silentSyncVersion
    try {
      const next = await fetchAiPlannerState()
      if (requestVersion === silentSyncVersion) assignState(next)
    } catch {
      // The write already succeeded; the next manual refresh will reconcile transient read failures.
    }
  }

  async function loadState(showMessage = false): Promise<void> {
    loading.state = true
    try {
      assignState(await fetchAiPlannerState())
      if (showMessage) ElMessage.success('建议已刷新')
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '加载建议失败'))
    } finally {
      loading.state = false
    }
  }

  async function loadCapabilities(): Promise<void> {
    try {
      capabilities.value = await fetchAiPlannerCapabilities()
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '读取 AI 能力失败'))
    }
  }

  async function handleGenerate(): Promise<void> {
    if (loading.generate) return
    loading.generate = true
    try {
      assignState(await generateAiSuggestions(controls))
      resetFilters()
      ElMessage.success('新一批项目建议已生成')
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '生成建议失败'))
    } finally {
      loading.generate = false
    }
  }

  async function handleCopy(suggestion: AiProjectSuggestion): Promise<void> {
    if (isSuggestionPending(suggestion.id)) return
    pendingActions[suggestion.id] = 'copied'
    try {
      await navigator.clipboard.writeText(suggestion.prompt)
      await recordAiSuggestionEvent({ suggestionId: suggestion.id, eventType: 'copied' })
      suggestion.feedback.copied += 1
      ElMessage.success('提示词已复制，可以直接粘贴到 Codex')
      void syncStateSilently()
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '复制失败'))
    } finally {
      delete pendingActions[suggestion.id]
    }
  }

  async function handleFeedback(
    suggestion: AiProjectSuggestion,
    eventType: 'liked' | 'disliked',
    reason?: string
  ): Promise<void> {
    if (isSuggestionPending(suggestion.id)) return
    pendingActions[suggestion.id] = eventType
    try {
      await recordAiSuggestionEvent({ suggestionId: suggestion.id, eventType, reason })
      suggestion.feedback.sentiment = eventType === 'liked' ? 1 : -1
      ElMessage.success(eventType === 'liked' ? '已记住你的偏好' : '已记录，本类建议会降低权重')
      void syncStateSilently()
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '反馈提交失败'))
    } finally {
      delete pendingActions[suggestion.id]
    }
  }

  async function handleWorkflow(
    suggestion: AiProjectSuggestion,
    eventType: Extract<AiSuggestionEventType, 'accepted' | 'completed' | 'dismissed' | 'restored'>
  ): Promise<void> {
    if (isSuggestionPending(suggestion.id)) return
    pendingActions[suggestion.id] = eventType
    try {
      const result = await recordAiSuggestionEvent({ suggestionId: suggestion.id, eventType })
      const statusByEvent = {
        accepted: 'accepted',
        completed: 'completed',
        dismissed: 'dismissed',
        restored: 'active'
      } as const
      const resolvedStatus = ['active', 'accepted', 'completed', 'dismissed'].includes(
        String(result.status)
      )
        ? (result.status as 'active' | 'accepted' | 'completed' | 'dismissed')
        : statusByEvent[eventType]
      applySuggestionStatus(suggestion, resolvedStatus)
      const messages = {
        accepted: '建议已采纳',
        completed: '建议已标记完成',
        dismissed: '建议已暂不考虑',
        restored: '建议已恢复到待评估'
      }
      ElMessage.success(messages[eventType])
      void syncStateSilently()
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '状态更新失败'))
    } finally {
      delete pendingActions[suggestion.id]
    }
  }

  function handleExpand(suggestion: AiProjectSuggestion, names: unknown): void {
    const opened = Array.isArray(names) ? names.includes('prompt') : names === 'prompt'
    if (!opened || expandedTracked.has(suggestion.id)) return
    expandedTracked.add(suggestion.id)
    void recordAiSuggestionEvent({ suggestionId: suggestion.id, eventType: 'expanded' }).catch(
      () => {
        expandedTracked.delete(suggestion.id)
      }
    )
  }

  onMounted(() => {
    void Promise.all([loadCapabilities(), loadState()])
  })
</script>

<style scoped lang="scss">
  .ai-planner {
    display: grid;
    gap: 16px;
    width: 100%;
    min-width: 0;
    padding-bottom: 20px;

    &__hero {
      display: flex;
      gap: 24px;
      align-items: center;
      justify-content: space-between;
      padding: 26px 28px;
      background:
        radial-gradient(circle at 86% 18%, rgb(99 102 241 / 13%), transparent 30%),
        var(--art-main-bg-color);
    }

    &__hero-copy,
    &__controls,
    &__toolbar-actions,
    &__feedback,
    &__workflow {
      display: flex;
      gap: 12px;
      align-items: center;
    }

    &__brand {
      display: grid;
      flex: 0 0 58px;
      place-items: center;
      width: 58px;
      height: 58px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), #7c3aed);
      border-radius: var(--custom-radius);
      box-shadow: 0 10px 28px rgb(99 102 241 / 20%);

      :deep(svg) {
        width: 28px;
        height: 28px;
      }
    }

    &__eyebrow {
      font-size: 11px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.14em;
    }

    h1 {
      margin: 3px 0 5px;
      font-size: 24px;
      color: var(--art-text-gray-900);
    }

    &__hero p,
    &__toolbar span,
    &__metric-icon + div small {
      color: var(--art-text-gray-500);
    }

    &__access-note,
    &__read-only-note {
      display: inline-flex;
      gap: 7px;
      align-items: center;
      color: var(--el-color-success);

      :deep(svg) {
        flex: 0 0 auto;
        width: 15px;
        height: 15px;
      }
    }

    &__access-note {
      margin-top: 8px;
      font-size: 12px;
    }

    &__select {
      width: 142px;
    }

    &__alert {
      margin: 0;
    }

    &__decision-grid {
      display: grid;
      grid-template-columns: 1fr;
      gap: 16px;
      min-width: 0;

      &.has-priority {
        grid-template-columns: minmax(0, 1.45fr) minmax(360px, 0.75fr);

        .ai-planner__priority {
          grid-row: 1;
          grid-column: 1;
        }

        .ai-planner__metrics {
          grid-template-columns: repeat(2, minmax(0, 1fr));
          grid-row: 1;
          grid-column: 2;
        }
      }
    }

    &__metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 16px;

      article {
        display: flex;
        gap: 14px;
        align-items: center;
        min-width: 0;
        padding: 19px 20px;

        > div:last-child {
          min-width: 0;
        }
      }

      span,
      small {
        display: block;
        font-size: 12px;
      }

      strong {
        display: block;
        margin: 2px 0;
        font-size: 23px;
        color: var(--art-text-gray-900);
      }

      small {
        display: block;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }
    }

    &__metric-icon {
      display: grid;
      place-items: center;
      width: 42px;
      height: 42px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);

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

    &__priority {
      display: grid;
      grid-template-columns: minmax(0, 1fr) auto auto;
      gap: 24px;
      align-items: center;
      padding: 18px 20px;
      background:
        radial-gradient(circle at 78% 0%, rgb(99 102 241 / 10%), transparent 34%),
        linear-gradient(110deg, var(--el-color-primary-light-9), var(--art-main-bg-color) 46%);
      border-color: var(--el-color-primary-light-8);
    }

    &__decision-grid.has-priority &__priority {
      grid-template-columns: minmax(0, 1fr);
      gap: 15px;
      align-content: center;

      .ai-planner__priority-score {
        padding: 13px 0;
        border-top: 1px solid var(--el-border-color-lighter);
        border-bottom: 1px solid var(--el-border-color-lighter);
      }
    }

    &__priority-main,
    &__priority-score,
    &__priority-actions {
      display: flex;
      align-items: center;
    }

    &__priority-main {
      min-width: 0;

      > div:last-child {
        min-width: 0;
      }

      strong,
      p,
      span {
        display: block;
      }

      strong {
        margin: 2px 0 4px;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 15px;
        color: var(--art-text-gray-900);
        white-space: nowrap;
      }

      p {
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 12px;
        color: var(--art-text-gray-500);
        white-space: nowrap;
      }
    }

    &__priority-icon {
      display: grid;
      flex: 0 0 42px;
      place-items: center;
      width: 42px;
      height: 42px;
      margin-right: 13px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary), #7c3aed);
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 21px;
        height: 21px;
      }
    }

    &__priority-eyebrow {
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.12em;
    }

    &__priority-score {
      gap: 18px;

      > div {
        display: grid;
        gap: 2px;
        min-width: 54px;
      }

      span {
        font-size: 11px;
        color: var(--art-text-gray-400);
      }

      strong {
        font-size: 13px;
        color: var(--art-text-gray-800);
      }
    }

    &__priority-actions {
      gap: 8px;

      :deep(.el-button + .el-button) {
        margin-left: 0;
      }
    }

    &__control-panel {
      position: sticky;
      top: 8px;
      z-index: 4;
      overflow: hidden;
      box-shadow: var(--el-box-shadow-lighter);
    }

    &__toolbar {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      padding: 14px 18px;
      background: linear-gradient(
        90deg,
        color-mix(in srgb, var(--theme-color) 5%, transparent),
        transparent 36%
      );

      > div:first-child {
        display: flex;
        flex-direction: column;
        gap: 3px;
      }
    }

    &__filters {
      display: flex;
      gap: 10px;
      align-items: center;
      padding: 12px 14px;
      border-top: 1px solid var(--el-border-color-lighter);
    }

    &__filter-search {
      flex: 1 1 300px;
      min-width: 220px;
    }

    &__batch-select {
      flex: 0 0 238px;
    }

    &__filter-select {
      flex: 0 0 150px;
    }

    &__filter-sort {
      flex: 0 0 166px;
    }

    &__filter-result {
      display: flex;
      flex: 0 0 auto;
      gap: 9px;
      align-items: center;
      min-width: 150px;
      margin-left: auto;
      font-size: 12px;
      color: var(--art-text-gray-500);

      :deep(.el-button) {
        gap: 4px;
      }
    }

    &__list {
      min-height: 240px;
    }

    &__empty {
      position: relative;
      display: grid;
      grid-template-columns: minmax(0, 1.15fr) minmax(360px, 0.85fr);
      gap: 34px;
      align-items: center;
      min-height: 300px;
      padding: 30px 34px;
      overflow: hidden;
      background:
        radial-gradient(circle at 12% 18%, rgb(99 102 241 / 11%), transparent 27%),
        radial-gradient(circle at 92% 88%, rgb(59 130 246 / 8%), transparent 24%),
        var(--art-main-bg-color);
      border-color: var(--el-color-primary-light-8);
    }

    &__empty-main {
      display: flex;
      gap: 24px;
      align-items: center;
      min-width: 0;
    }

    &__empty-visual {
      position: relative;
      display: grid;
      flex: 0 0 116px;
      place-items: center;
      width: 116px;
      height: 116px;

      &::before,
      &::after {
        position: absolute;
        content: '';
        border: 1px dashed var(--el-color-primary-light-5);
        border-radius: 50%;
      }

      &::before {
        inset: 8px;
      }

      &::after {
        inset: 24px;
        opacity: 0.7;
      }

      strong,
      span {
        position: absolute;
        z-index: 1;
        display: grid;
        place-items: center;
        color: var(--el-color-primary);
        background: var(--art-main-bg-color);
        border: 1px solid var(--el-color-primary-light-8);
        border-radius: 50%;
        box-shadow: var(--el-box-shadow-lighter);
      }

      strong {
        width: 56px;
        height: 56px;
        color: white;
        background: linear-gradient(145deg, var(--el-color-primary), #7c3aed);
        border: 0;

        :deep(svg) {
          width: 27px;
          height: 27px;
        }
      }

      span {
        width: 34px;
        height: 34px;

        &:first-child {
          top: 0;
          left: 4px;
        }

        &:last-child {
          right: 0;
          bottom: 4px;
        }
      }
    }

    &__empty-copy {
      min-width: 0;

      h2 {
        margin: 5px 0 8px;
        font-size: 22px;
        color: var(--art-text-gray-900);
      }

      > p {
        max-width: 620px;
        margin: 0 0 16px;
        line-height: 1.75;
        color: var(--art-text-gray-600);
      }

      :deep(.el-button) {
        margin-top: 18px;
      }
    }

    &__empty-eyebrow {
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.14em;
    }

    &__empty-badges {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        padding: 5px 9px;
        font-size: 11px;
        color: var(--art-text-gray-600);
        background: color-mix(in srgb, var(--art-main-bg-color) 92%, var(--el-color-primary));
        border: 1px solid var(--el-border-color-lighter);
        border-radius: 999px;

        :deep(svg) {
          width: 14px;
          height: 14px;
          color: var(--el-color-primary);
        }
      }
    }

    &__empty-flow {
      display: grid;
      gap: 10px;

      article {
        display: grid;
        grid-template-columns: 34px minmax(0, 1fr);
        gap: 12px;
        align-items: center;
        min-width: 0;
        padding: 14px 15px;
        background: color-mix(in srgb, var(--art-main-bg-color) 96%, var(--el-color-primary));
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);

        > span {
          display: grid;
          place-items: center;
          width: 32px;
          height: 32px;
          font-size: 11px;
          font-weight: 700;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: 50%;
        }

        strong {
          display: block;
          margin-bottom: 3px;
          color: var(--art-text-gray-800);
        }

        p {
          margin: 0;
          font-size: 12px;
          line-height: 1.55;
          color: var(--art-text-gray-500);
        }
      }
    }

    &__filtered-empty {
      display: flex;
      gap: 16px;
      align-items: center;
      min-height: 150px;
      padding: 26px 30px;

      > div:nth-child(2) {
        flex: 1;
        min-width: 0;
      }

      strong {
        color: var(--art-text-gray-800);
      }

      p {
        margin: 5px 0 0;
        color: var(--art-text-gray-500);
      }
    }

    &__filtered-empty-icon {
      display: grid;
      flex: 0 0 46px;
      place-items: center;
      width: 46px;
      height: 46px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);

      :deep(svg) {
        width: 22px;
        height: 22px;
      }
    }

    &__suggestion {
      position: relative;
      padding: 20px;
      overflow: hidden;
      transition:
        transform 0.2s ease,
        box-shadow 0.2s ease;

      & + & {
        margin-top: 16px;
      }

      &:hover:not(.is-processing) {
        box-shadow: var(--el-box-shadow-light);
        transform: translateY(-1px);
      }

      &.is-processing {
        box-shadow: 0 0 0 1px var(--el-color-primary-light-7);
      }

      :deep(.el-loading-mask) {
        background-color: color-mix(in srgb, var(--art-main-bg-color) 82%, transparent);
        border-radius: var(--custom-radius);
        backdrop-filter: blur(2px);
      }

      :deep(.el-loading-spinner .circular) {
        width: 34px;
        height: 34px;
      }

      :deep(.el-loading-text) {
        margin-top: 8px;
        font-size: 12px;
        font-weight: 600;
      }

      header {
        display: grid;
        grid-template-columns: 34px minmax(0, 1fr) auto;
        gap: 14px;
      }

      footer {
        display: flex;
        gap: 16px;
        align-items: flex-end;
        justify-content: space-between;
        padding: 15px 20px 16px;
        margin: 14px -20px -20px;
        background: color-mix(in srgb, var(--art-main-bg-color) 96%, var(--el-color-primary));
        border-top: 1px solid var(--el-border-color-lighter);
      }
    }

    &__rank {
      display: grid;
      place-items: center;
      width: 30px;
      height: 30px;
      font-weight: 700;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 50%;
    }

    &__title {
      min-width: 0;

      > div {
        display: flex;
        gap: 6px;
      }

      h2 {
        margin: 9px 0 5px;
        font-size: 18px;
        color: var(--art-text-gray-900);
      }

      p {
        line-height: 1.7;
        color: var(--art-text-gray-600);
      }
    }

    &__scores {
      display: flex;
      gap: 8px;
      align-items: flex-start;

      span {
        display: inline-flex;
        gap: 5px;
        align-items: center;
        padding: 6px 9px;
        font-size: 12px;
        color: var(--art-text-gray-500);
        white-space: nowrap;
        background: var(--art-main-bg-color);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: 999px;

        :deep(svg) {
          width: 14px;
          height: 14px;
          color: var(--el-color-primary);
        }
      }

      strong {
        color: var(--art-text-gray-800);
      }
    }

    &__context {
      display: grid;
      grid-template-columns: 1fr 1.4fr 1fr;
      gap: 10px;
      margin: 18px 0 6px 48px;

      > div {
        position: relative;
        min-width: 0;
        padding: 14px 15px;
        background: color-mix(in srgb, var(--art-main-bg-color) 97%, var(--el-color-primary));
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);

        &.is-opportunity {
          border-top-color: var(--el-color-primary-light-5);
        }

        &.is-evidence {
          border-top-color: var(--el-color-success-light-5);
        }

        &.is-risk {
          border-top-color: var(--el-color-warning-light-5);
        }
      }

      span {
        display: inline-flex;
        gap: 6px;
        align-items: center;
        font-size: 12px;
        font-weight: 700;
        color: var(--art-text-gray-500);

        :deep(svg) {
          width: 15px;
          height: 15px;
          color: var(--el-color-primary);
        }
      }

      p,
      ul {
        margin: 7px 0 0;
        line-height: 1.65;
        color: var(--art-text-gray-700);
      }

      ul {
        padding-left: 18px;

        li + li {
          margin-top: 6px;
        }
      }

      code {
        color: var(--el-color-primary);
        overflow-wrap: anywhere;
      }
    }

    &__collapse {
      margin: 4px 0 0 48px;
      border-bottom: 0;

      :deep(.el-collapse-item__header) {
        height: 48px;
        color: var(--el-color-primary);
        border-bottom-color: var(--el-border-color-lighter);
      }

      :deep(.el-collapse-item__wrap) {
        border-bottom: 0;
      }

      pre {
        min-height: 100%;
        padding: 16px;
        margin: 0;
        font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
        line-height: 1.7;
        color: var(--art-text-gray-800);
        white-space: pre-wrap;
        background: var(--art-main-bg-color);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
      }
    }

    &__prompt-toggle {
      display: inline-flex;
      gap: 7px;
      align-items: center;
      font-weight: 600;

      :deep(svg) {
        width: 16px;
        height: 16px;
      }

      small {
        padding: 2px 7px;
        font-size: 11px;
        font-weight: 500;
        color: var(--art-text-gray-500);
        background: var(--art-main-bg-color);
        border-radius: 999px;
      }
    }

    &__prompt-scroll {
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);

      pre {
        border: 0;
        border-radius: 0;
      }
    }

    &__criteria {
      margin-top: 14px;
      color: var(--art-text-gray-700);

      ol {
        padding-left: 22px;
        margin: 8px 0 0;
        line-height: 1.8;
      }
    }

    &__action-group {
      display: grid;
      gap: 7px;

      &.is-workflow {
        justify-items: end;
      }
    }

    &__action-label {
      font-size: 11px;
      font-weight: 600;
      color: var(--art-text-gray-400);
      letter-spacing: 0.04em;
    }

    &__feedback,
    &__workflow {
      gap: 8px;

      :deep(.el-button + .el-button) {
        margin-left: 0;
      }
    }

    &__workflow {
      justify-content: flex-end;
    }

    &__status-note {
      display: inline-flex;
      gap: 6px;
      align-items: center;
      min-height: 32px;
      padding: 0 11px;
      font-size: 12px;
      color: var(--art-text-gray-500);
      background: var(--el-fill-color-light);
      border-radius: var(--el-border-radius-base);

      &.is-completed {
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
      }

      :deep(svg) {
        width: 15px;
        height: 15px;
      }
    }

    &__read-only-note {
      align-self: flex-end;
      max-width: 360px;
      padding: 8px 11px;
      font-size: 12px;
      line-height: 1.5;
      background: var(--el-color-success-light-9);
      border: 1px solid var(--el-color-success-light-7);
      border-radius: var(--el-border-radius-base);
    }
  }

  @media (width <= 1100px) {
    .ai-planner {
      &__hero,
      &__toolbar,
      &__suggestion footer {
        flex-direction: column;
        align-items: flex-start;
      }

      &__metrics {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__decision-grid.has-priority {
        grid-template-columns: 1fr;

        .ai-planner__priority,
        .ai-planner__metrics {
          grid-column: 1;
        }

        .ai-planner__priority {
          grid-row: 1;
        }

        .ai-planner__metrics {
          grid-row: 2;
        }
      }

      &__priority {
        grid-template-columns: minmax(0, 1fr);
        gap: 14px;
      }

      &__empty {
        grid-template-columns: minmax(0, 1fr);
      }

      &__filters {
        flex-wrap: wrap;
      }

      &__filter-search {
        flex-basis: 100%;
      }

      &__filter-result {
        margin-left: 0;
      }

      &__context {
        grid-template-columns: 1fr;
      }

      &__action-group {
        width: 100%;

        &.is-workflow {
          justify-items: start;
        }
      }

      &__read-only-note {
        align-self: flex-start;
        max-width: 100%;
      }

      &__suggestion header {
        grid-template-columns: 34px minmax(0, 1fr);
      }

      &__scores {
        grid-column: 2;
      }
    }
  }

  @media (width <= 680px) {
    .ai-planner {
      &__hero-copy,
      &__controls,
      &__toolbar-actions,
      &__workflow,
      &__priority-actions {
        flex-direction: column;
        align-items: stretch;
        width: 100%;
      }

      &__hero-copy {
        align-items: flex-start;
      }

      &__select {
        width: 100%;
      }

      &__metrics {
        grid-template-columns: 1fr;
      }

      &__control-panel {
        position: static;
      }

      &__decision-grid.has-priority .ai-planner__metrics {
        grid-template-columns: 1fr;
      }

      &__empty {
        padding: 24px 20px;
      }

      &__empty-main,
      &__filtered-empty {
        flex-direction: column;
        align-items: flex-start;
      }

      &__empty-visual {
        flex-basis: 96px;
        width: 96px;
        height: 96px;
      }

      &__priority-score {
        flex-wrap: wrap;
      }

      &__filter-search,
      &__batch-select,
      &__filter-select,
      &__filter-sort,
      &__filter-result {
        flex: 1 1 100%;
        width: 100%;
      }

      &__context,
      &__collapse {
        margin-left: 0;
      }

      &__scores {
        flex-wrap: wrap;
      }

      &__feedback {
        flex-wrap: wrap;
      }
    }
  }
</style>
