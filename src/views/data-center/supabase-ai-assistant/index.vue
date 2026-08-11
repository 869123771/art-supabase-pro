<template>
  <ArtPageShell
    class="project-assistant-shell"
    :loading="initialLoading"
    loading-mode="skeleton"
    :error="pageError"
    min-height="720px"
    @retry="loadInitialData"
  >
    <div class="project-assistant art-full-height" :class="{ 'is-focus-mode': focusMode }">
      <header v-if="!focusMode" class="project-assistant__hero art-card-xs">
        <div>
          <div class="project-assistant__eyebrow">
            <ArtSvgIcon icon="ri:database-2-line" />
            SUPABASE PROJECT COPILOT
          </div>
          <h1>Supabase AI 助手</h1>
          <p>
            统一洞察 Database、RLS、Auth、Storage、Realtime 与 Edge
            Functions，并生成可审计的治理方案。
          </p>
        </div>
        <div class="project-assistant__safety">
          <div class="project-assistant__hero-actions">
            <ElButton plain type="primary" @click="openCapabilityCenter">
              <ArtSvgIcon icon="ri:radar-line" /> 全域能力
            </ElButton>
            <ElTag
              :type="assistantMode === 'controlled_write' ? 'warning' : 'success'"
              effect="light"
              round
            >
              <ArtSvgIcon
                :icon="
                  assistantMode === 'controlled_write' ? 'ri:admin-line' : 'ri:shield-check-line'
                "
              />
              {{ assistantMode === 'controlled_write' ? '管理员受控变更' : '只读安全模式' }}
            </ElTag>
          </div>
          <span>项目：{{ overview?.projectRef || 'ckbftoopuyophiebamwy' }}</span>
        </div>
      </header>

      <section v-if="!focusMode" class="project-assistant__stats art-card-xs">
        <button
          v-for="stat in stats"
          :key="stat.type"
          type="button"
          :class="{ 'is-active': filters.objectType === stat.type }"
          :aria-pressed="filters.objectType === stat.type"
          @click="selectStat(stat.type)"
        >
          <span><ArtSvgIcon :icon="stat.icon" /></span>
          <div
            ><strong>{{ stat.value }}</strong
            ><small>{{ stat.label }}</small></div
          >
        </button>
      </section>

      <section class="project-assistant__workspace">
        <ElSplitter class="project-assistant__splitter" lazy>
          <ElSplitterPanel size="280px" min="240px" max="400px" collapsible>
            <ProjectAssistantObjectBrowser
              :focus-mode="focusMode"
              :schemas="schemas"
              :objects="objects"
              :selected-object="selectedObject"
              :filters="filters"
              :loading="loading.objects"
              :load-source="objectLoadSource"
              :error="errors.objects"
              @toggle-focus="toggleFocusMode"
              @refresh="loadObjects('refresh')"
              @filter="loadObjects('filter')"
              @select="selectObject"
              @update:keyword="filters.keyword = $event"
              @update:schema="filters.schema = $event"
              @update:object-type="filters.objectType = $event"
            />
          </ElSplitterPanel>

          <ElSplitterPanel min="380px">
            <main class="project-assistant__detail art-card-xs">
              <div class="project-assistant__panel-title">
                <div>
                  <strong>{{ selectedObject?.objectName || '对象详情' }}</strong>
                  <small
                    v-if="selectedObject"
                    class="project-assistant__detail-description"
                    :title="detail?.description || selectedObject.description || '暂无对象说明'"
                  >
                    {{ detail?.description || selectedObject.description || '暂无对象说明' }}
                  </small>
                  <small v-else>从左侧选择数据库对象</small>
                </div>
                <div class="project-assistant__detail-actions">
                  <ElButton
                    v-if="selectedObject"
                    text
                    type="primary"
                    :disabled="chat.sending"
                    @click="runObjectAnalysis(objectAiActions[0])"
                  >
                    <ArtSvgIcon icon="ri:sparkling-2-line" /> AI 解读
                  </ElButton>
                  <ElButton
                    v-if="canEditSelectedDescription"
                    text
                    :type="assistantMode === 'controlled_write' ? 'warning' : 'primary'"
                    @click="editObjectDescription"
                  >
                    <ArtSvgIcon icon="ri:edit-2-line" /> 编辑说明
                  </ElButton>
                  <ElButton v-if="detail?.ddl" text type="primary" @click="copyDdl">
                    <ArtSvgIcon icon="ri:file-copy-line" /> 复制 DDL
                  </ElButton>
                </div>
              </div>

              <ArtAsyncState
                v-if="selectedObject"
                class="project-assistant__detail-state"
                :loading="loading.detail"
                :loading-mode="detail ? 'mask' : 'skeleton'"
                :error="errors.detail"
                full-height
                min-height="0"
                @retry="selectObject(selectedObject)"
              >
                <ElTabs v-model="detailTab" class="project-assistant__detail-tabs">
                  <ElTabPane label="智能概览" name="insights">
                    <ElScrollbar class="project-assistant__insights-scroll">
                      <div class="project-assistant__insights">
                        <section>
                          <ArtSectionTitle :show-line="false">对象画像</ArtSectionTitle>
                          <div class="project-assistant__insight-grid">
                            <article v-for="metric in objectInsightMetrics" :key="metric.label">
                              <span><ArtSvgIcon :icon="metric.icon" /></span>
                              <div>
                                <small>{{ metric.label }}</small>
                                <strong>{{ metric.value }}</strong>
                                <p>{{ metric.helper }}</p>
                              </div>
                            </article>
                          </div>
                        </section>

                        <section>
                          <ArtSectionTitle :show-line="false">治理检查</ArtSectionTitle>
                          <div class="project-assistant__governance-list">
                            <article v-for="item in objectGovernanceChecks" :key="item.label">
                              <span :class="`is-${item.status}`">
                                <ArtSvgIcon :icon="item.icon" />
                              </span>
                              <div>
                                <strong>{{ item.label }}</strong>
                                <small>{{ item.detail }}</small>
                              </div>
                              <ElTag :type="item.status" size="small" effect="light" round>
                                {{ item.statusLabel }}
                              </ElTag>
                            </article>
                          </div>
                        </section>

                        <section>
                          <ArtSectionTitle :show-line="false">AI 分析动作</ArtSectionTitle>
                          <div class="project-assistant__analysis-actions">
                            <button
                              v-for="action in objectAiActions"
                              :key="action.label"
                              type="button"
                              :disabled="chat.sending"
                              @click="runObjectAnalysis(action)"
                            >
                              <span><ArtSvgIcon :icon="action.icon" /></span>
                              <span>
                                <strong>{{ action.label }}</strong>
                                <small>{{ action.description }}</small>
                              </span>
                              <ArtSvgIcon icon="ri:arrow-right-up-line" />
                            </button>
                          </div>
                        </section>
                      </div>
                    </ElScrollbar>
                  </ElTabPane>
                  <ElTabPane label="对象定义" name="ddl">
                    <ArtAsyncState
                      :empty="!detail?.ddl"
                      empty-text="当前对象没有可显示的定义"
                      full-height
                      min-height="0"
                    >
                      <ElScrollbar class="project-assistant__code-scroll">
                        <pre
                          class="project-assistant__code"
                          aria-label="SQL 对象定义"
                        ><code v-sql-highlight="detail?.ddl || ''" class="language-sql"></code></pre>
                      </ElScrollbar>
                    </ArtAsyncState>
                  </ElTabPane>
                  <ElTabPane v-if="detail?.columns?.length" label="字段" name="columns">
                    <div class="project-assistant__fields-panel">
                      <div class="project-assistant__fields-toolbar">
                        <ElInput
                          v-model="fieldKeyword"
                          clearable
                          placeholder="搜索字段、类型或说明"
                        >
                          <template #prefix><ArtSvgIcon icon="ri:search-line" /></template>
                        </ElInput>
                        <span>
                          {{ filteredColumns.length }} / {{ detail.columns.length }} 个字段
                        </span>
                      </div>
                      <ArtTable
                        :data="filteredColumns"
                        :columns="fieldColumns"
                        :pagination="false"
                        height="calc(100% - 49px)"
                        stripe
                      />
                    </div>
                  </ElTabPane>
                  <ElTabPane
                    v-if="selectedObject.objectType === 'table'"
                    label="外键关系"
                    name="relations"
                  >
                    <ArtAsyncState
                      :loading="loading.relationships"
                      :loading-mode="relationships.length ? 'mask' : 'skeleton'"
                      :error="errors.relationships"
                      :empty="
                        !loading.relationships && !errors.relationships && !relationships.length
                      "
                      empty-text="没有关联此外键的记录"
                      full-height
                      min-height="0"
                      @retry="selectObject(selectedObject)"
                    >
                      <ElScrollbar class="project-assistant__relation-list">
                        <article v-for="relation in relationships" :key="relation.constraintName">
                          <strong>{{ relation.constraintName }}</strong>
                          <span>
                            {{ relation.sourceSchema }}.{{ relation.sourceTable }} →
                            {{ relation.targetSchema }}.{{ relation.targetTable }}
                          </span>
                          <code>{{ relation.definition }}</code>
                        </article>
                      </ElScrollbar>
                    </ArtAsyncState>
                  </ElTabPane>
                </ElTabs>
              </ArtAsyncState>
              <div v-else class="project-assistant__detail-empty">
                <div class="project-assistant__empty-icon">
                  <ArtSvgIcon icon="ri:code-box-line" />
                </div>
                <h3>选择对象查看定义</h3>
                <p>支持表、视图、函数、触发器、RLS 策略和索引。</p>
              </div>
            </main>
          </ElSplitterPanel>

          <ElSplitterPanel size="390px" min="320px" max="540px" collapsible>
            <aside class="project-assistant__chat art-card-xs">
              <div class="project-assistant__panel-title project-assistant__chat-header">
                <div class="project-assistant__assistant-heading">
                  <span class="project-assistant__assistant-avatar">
                    <ArtSvgIcon icon="ri:sparkling-2-fill" />
                  </span>
                  <span>
                    <strong>项目助手</strong>
                    <small>
                      <i :class="{ 'is-offline': !assistantStatus.online }"></i>
                      {{ assistantStatusLabel }}
                    </small>
                  </span>
                </div>
                <div class="project-assistant__chat-actions">
                  <ElTooltip content="会话历史" placement="bottom">
                    <ElButton text circle aria-label="会话历史" @click="openHistory">
                      <ArtSvgIcon icon="ri:history-line" />
                    </ElButton>
                  </ElTooltip>
                  <ElTooltip content="导出当前会话" placement="bottom">
                    <ElButton
                      text
                      circle
                      aria-label="导出当前会话"
                      :disabled="!chat.messages.length"
                      @click="exportConversation"
                    >
                      <ArtSvgIcon icon="ri:download-2-line" />
                    </ElButton>
                  </ElTooltip>
                  <ElButton text type="primary" @click="resetChat">
                    <ArtSvgIcon icon="ri:chat-new-line" /> 新对话
                  </ElButton>
                </div>
              </div>
              <div v-if="activeChatObject" class="project-assistant__chat-context">
                <ArtSvgIcon :icon="getObjectIcon(activeChatObject.objectType)" />
                <span>正在分析</span>
                <strong>{{ activeChatObject.schemaName }}.{{ activeChatObject.objectName }}</strong>
                <ElTooltip :content="chat.contextLocked ? '解除上下文锁定' : '锁定当前对象上下文'">
                  <ElButton
                    text
                    circle
                    size="small"
                    :type="chat.contextLocked ? 'primary' : ''"
                    :aria-label="chat.contextLocked ? '解除上下文锁定' : '锁定当前对象上下文'"
                    @click="toggleContextLock"
                  >
                    <ArtSvgIcon
                      :icon="chat.contextLocked ? 'ri:pushpin-fill' : 'ri:pushpin-line'"
                    />
                  </ElButton>
                </ElTooltip>
              </div>
              <ElScrollbar ref="chatScrollbarRef" class="project-assistant__messages">
                <div v-if="!chat.messages.length" class="project-assistant__chat-welcome">
                  <div class="project-assistant__welcome-mark">
                    <span><ArtSvgIcon icon="ri:sparkling-2-fill" /></span>
                  </div>
                  <small>PROJECT INTELLIGENCE</small>
                  <h3>询问这个 Supabase 项目</h3>
                  <p>
                    {{
                      assistantMode === 'controlled_write'
                        ? '超级管理员受控变更已开启；执行前仍需明确确认，并记录完整审计。'
                        : '基于项目实时元数据提供分析建议，全程只读，不执行 SQL 或修改项目。'
                    }}
                  </p>
                  <ElButton
                    v-for="suggestion in chatSuggestions"
                    :key="suggestion"
                    text
                    @click="sendSuggestion(suggestion)"
                  >
                    <span>{{ suggestion }}</span>
                    <ArtSvgIcon icon="ri:arrow-right-up-line" />
                  </ElButton>
                </div>
                <article
                  v-for="message in chat.messages"
                  :key="message.id"
                  :class="['project-assistant__message', `is-${message.role}`]"
                >
                  <span>
                    <ArtSvgIcon
                      :icon="
                        message.role === 'assistant' ? 'ri:sparkling-2-fill' : 'ri:user-3-line'
                      "
                    />
                  </span>
                  <div>
                    <div class="project-assistant__message-content">{{ message.content }}</div>
                    <div
                      v-if="
                        message.role === 'assistant' && (message.runId || message.tools?.length)
                      "
                      class="project-assistant__message-trace"
                    >
                      <span v-if="message.model">{{ message.model }}</span>
                      <span v-if="message.latencyMs != null">{{
                        formatDuration(message.latencyMs)
                      }}</span>
                      <span v-if="message.usage">
                        {{ (message.usage.inputTokens || 0) + (message.usage.outputTokens || 0) }}
                        tokens
                      </span>
                      <ElTag
                        v-for="tool in message.tools"
                        :key="`${message.id}:${tool.name}`"
                        size="small"
                        :type="tool.status === 'succeeded' ? 'success' : 'danger'"
                        effect="plain"
                      >
                        {{ getToolLabel(tool.name) }}
                      </ElTag>
                    </div>
                    <div
                      v-if="message.role === 'assistant'"
                      class="project-assistant__message-actions"
                    >
                      <ElButton text size="small" @click="copyMessage(message.content)">
                        <ArtSvgIcon icon="ri:file-copy-line" /> 复制
                      </ElButton>
                      <ElButton text size="small" @click="retryMessage(message.id)">
                        <ArtSvgIcon icon="ri:refresh-line" /> 重试
                      </ElButton>
                      <ArtAiFeedback
                        v-if="message.runId"
                        :run-id="message.runId"
                        context-label="Supabase AI 项目助手"
                        compact
                        @submitted="message.feedback = $event.rating"
                      />
                    </div>
                  </div>
                </article>
                <article v-if="chat.sending" class="project-assistant__message is-assistant">
                  <span><ArtSvgIcon icon="ri:sparkling-2-fill" /></span>
                  <div class="project-assistant__typing">
                    <i></i><i></i><i></i>
                    <small>{{ chatPhase }} · {{ formatDuration(chat.elapsedMs) }}</small>
                  </div>
                </article>
              </ElScrollbar>
              <footer class="project-assistant__composer">
                <div v-if="chat.messages.length" class="project-assistant__quick-actions">
                  <button
                    v-for="action in quickActions"
                    :key="action.label"
                    type="button"
                    :disabled="chat.sending"
                    @click="sendSuggestion(action.prompt)"
                  >
                    <ArtSvgIcon :icon="action.icon" /> {{ action.label }}
                  </button>
                </div>
                <div class="project-assistant__composer-box">
                  <ElInput
                    v-model="chat.input"
                    type="textarea"
                    resize="none"
                    :autosize="{ minRows: 3, maxRows: 6 }"
                    maxlength="4000"
                    placeholder="向项目助手提问…"
                    @keydown.enter.exact.prevent="sendMessage"
                  />
                  <div>
                    <button
                      v-if="canUseControlledWrite"
                      type="button"
                      class="project-assistant__safety-toggle"
                      :class="{ 'is-write-mode': assistantMode === 'controlled_write' }"
                      @click="toggleAssistantMode"
                    >
                      <ArtSvgIcon
                        :icon="
                          assistantMode === 'controlled_write'
                            ? 'ri:admin-fill'
                            : 'ri:shield-check-line'
                        "
                      />
                      {{ assistantMode === 'controlled_write' ? '受控变更模式' : '只读安全模式' }}
                    </button>
                    <span v-else><ArtSvgIcon icon="ri:shield-check-line" /> 只读安全模式</span>
                    <span class="project-assistant__send-actions">
                      <small>Enter 发送</small>
                      <ElButton
                        type="primary"
                        circle
                        :class="{ 'is-stopping': chat.sending }"
                        :disabled="!chat.sending && !chat.input.trim()"
                        :aria-label="chat.sending ? '停止等待' : '发送消息'"
                        :title="chat.sending ? '停止等待' : '发送消息'"
                        @click="chat.sending ? stopGeneration() : sendMessage()"
                      >
                        <ArtSvgIcon :icon="chat.sending ? 'ri:stop-fill' : 'ri:arrow-up-line'" />
                      </ElButton>
                    </span>
                  </div>
                </div>
              </footer>
            </aside>
          </ElSplitterPanel>
        </ElSplitter>
      </section>

      <ProjectAssistantHistoryDrawer
        ref="historyDrawerRef"
        v-model:query="history.query"
        :loading="history.loading"
        :error="history.error"
        :items="history.items"
        :active-id="chat.conversationId"
        @search="scheduleHistorySearch"
        @retry="loadHistory"
        @select="restoreConversation"
        @rename="renameConversation"
      />

      <ProjectCapabilityCenterDrawer
        ref="capabilityCenterRef"
        @analyze="analyzePlatformCapability"
      />
    </div>
  </ArtPageShell>
</template>

<script setup lang="ts">
  import { getFriendlySupabaseErrorMessage } from '@/utils/supabase'
  import { useDebounceFn, useIntervalFn, useStorage } from '@vueuse/core'
  import { ElMessage } from 'element-plus'
  import type { ScrollbarInstance } from 'element-plus'
  import hljs from 'highlight.js/lib/core'
  import sqlLanguage from 'highlight.js/lib/languages/sql'
  import type { Directive } from 'vue'
  import type { ColumnOption } from '@/types'
  import {
    chatWithProjectAssistant,
    fetchProjectAssistantCapabilities,
    fetchProjectAssistantConversation,
    fetchProjectAssistantHistory,
    fetchProjectCatalog,
    renameProjectAssistantConversation,
    updateProjectObjectDescription
  } from '@/api/supabase-ai-assistant'
  import ArtAiFeedback from '@/components/core/base/art-ai-feedback/index.vue'
  import type { AiAssistantToolResult } from '@/types/ai-assistant'
  import type {
    ProjectAssistantCapabilities,
    ProjectAssistantConversationSummary,
    ProjectAssistantSafetyMode,
    ProjectDatabaseObject,
    ProjectEdgeFunctionResult,
    ProjectObjectColumn,
    ProjectObjectDetail,
    ProjectObjectType,
    ProjectOverview,
    ProjectRelationship
  } from '@/types/supabase-ai-assistant'
  import { useArtFeedback } from '@/hooks/core/useArtFeedback'
  import ProjectCapabilityCenterDrawer from './modules/capability-center-drawer.vue'
  import ProjectAssistantHistoryDrawer from './modules/project-assistant-history-drawer.vue'
  import ProjectAssistantObjectBrowser from './modules/project-assistant-object-browser.vue'

  defineOptions({ name: 'SupabaseAiAssistant' })

  hljs.registerLanguage('sql', sqlLanguage)

  const { promptText, confirmAction } = useArtFeedback()

  const vSqlHighlight: Directive<HTMLElement, string> = {
    mounted(element, binding) {
      element.textContent = binding.value
      hljs.highlightElement(element)
    },
    updated(element, binding) {
      if (binding.value === binding.oldValue) return
      element.removeAttribute('data-highlighted')
      element.textContent = binding.value
      hljs.highlightElement(element)
    }
  }

  interface ChatMessage {
    id: string
    role: 'user' | 'assistant'
    content: string
    runId?: string
    model?: string
    promptVersion?: string
    latencyMs?: number | null
    tools?: AiAssistantToolResult[]
    usage?: { inputTokens?: number; outputTokens?: number }
    feedback?: -1 | 1
    createdAt?: string
  }

  interface ObjectInsightMetric {
    label: string
    value: string | number
    helper: string
    icon: string
  }

  interface ObjectGovernanceCheck {
    label: string
    detail: string
    status: 'success' | 'warning' | 'info'
    statusLabel: string
    icon: string
  }

  interface ObjectAiAction {
    label: string
    description: string
    prompt: string
    icon: string
  }

  interface CapabilityCenterExpose {
    handleOpen: (data: { edgeFunctions: ProjectEdgeFunctionResult | null }) => Promise<void>
  }

  interface HistoryDrawerExpose {
    handleOpen: () => Promise<void>
    handleClose: () => void
  }

  const overview = ref<ProjectOverview | null>(null)
  const schemas = ref<string[]>(['public'])
  const objects = ref<ProjectDatabaseObject[]>([])
  const detail = ref<ProjectObjectDetail | null>(null)
  const relationships = ref<ProjectRelationship[]>([])
  const edgeFunctions = ref<ProjectEdgeFunctionResult | null>(null)
  const selectedObject = ref<ProjectDatabaseObject | null>(null)
  const detailTab = ref('ddl')
  const fieldKeyword = ref('')
  const chatScrollbarRef = ref<ScrollbarInstance>()
  const historyDrawerRef = ref<HistoryDrawerExpose>()
  const capabilityCenterRef = ref<CapabilityCenterExpose>()
  const focusMode = useStorage('supabase-ai-assistant:focus-mode', false)
  const assistantMode = useStorage<ProjectAssistantSafetyMode>(
    'supabase-ai-assistant:safety-mode',
    'read_only'
  )
  const objectLoadSource = ref<'initial' | 'filter' | 'refresh' | null>(null)
  const loading = reactive({ overview: false, objects: false, detail: false, relationships: false })
  const errors = reactive({
    overview: null as Error | null,
    objects: null as Error | null,
    detail: null as Error | null,
    relationships: null as Error | null
  })
  const initialSettled = ref(false)
  const filters = reactive<{ schema: string; objectType: ProjectObjectType; keyword: string }>({
    schema: 'public',
    objectType: 'table',
    keyword: ''
  })
  const chat = reactive({
    input: '',
    sending: false,
    startedAt: 0,
    elapsedMs: 0,
    conversationId: undefined as string | undefined,
    contextLocked: false,
    contextObject: null as ProjectDatabaseObject | null,
    messages: [] as ChatMessage[]
  })
  const history = reactive({
    loading: false,
    query: '',
    error: '',
    items: [] as ProjectAssistantConversationSummary[]
  })
  const assistantStatus = reactive({
    loading: true,
    online: false,
    capabilities: null as ProjectAssistantCapabilities | null
  })
  let activeChatRequest = 0
  let activeHistoryRequest = 0
  let activeObjectRequest = 0
  let chatAbortController: AbortController | undefined

  const { pause: pauseElapsedTimer, resume: resumeElapsedTimer } = useIntervalFn(
    () => {
      chat.elapsedMs = Math.max(0, Date.now() - chat.startedAt)
    },
    250,
    { immediate: false }
  )

  const activeChatObject = computed(() =>
    chat.contextLocked ? chat.contextObject : selectedObject.value
  )
  const initialLoading = computed(
    () => !initialSettled.value && (loading.overview || loading.objects)
  )
  const pageError = computed(() => {
    if (!initialSettled.value || overview.value || objects.value.length) return null
    return errors.overview || errors.objects
  })
  const canUseControlledWrite = computed(
    () => assistantStatus.capabilities?.access?.controlledWrite === true
  )
  const canEditSelectedDescription = computed(
    () =>
      canUseControlledWrite.value &&
      ['table', 'view', 'materialized_view'].includes(selectedObject.value?.objectType || '')
  )
  const detailColumns = computed<ProjectObjectColumn[]>(() => detail.value?.columns ?? [])
  const filteredColumns = computed(() => {
    const keyword = fieldKeyword.value.trim().toLowerCase()
    if (!keyword) return detailColumns.value
    return detailColumns.value.filter((column) =>
      [column.name, column.dataType, column.defaultValue, column.description]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(keyword))
    )
  })
  const fieldColumns: ColumnOption<ProjectObjectColumn>[] = [
    { prop: 'name', label: '字段', minWidth: 150 },
    { prop: 'dataType', label: '类型', minWidth: 160 },
    {
      prop: 'nullable',
      label: '可空',
      width: 80,
      align: 'center',
      formatter: (row) => (row.nullable ? '是' : '否')
    },
    {
      prop: 'defaultValue',
      label: '默认值',
      minWidth: 180,
      showOverflowTooltip: true
    },
    {
      prop: 'description',
      label: '字段说明',
      minWidth: 180,
      showOverflowTooltip: true
    }
  ]
  const describedColumnCount = computed(
    () => detailColumns.value.filter((column) => column.description?.trim()).length
  )
  const objectMetadataCoverage = computed(() => {
    const descriptionCount = (
      detail.value?.description || selectedObject.value?.description
    )?.trim()
      ? 1
      : 0
    const total = detailColumns.value.length + 1
    return Math.round(((describedColumnCount.value + descriptionCount) / total) * 100)
  })
  const hasPrimaryKey = computed(() =>
    (detail.value?.constraints ?? []).some((constraint) =>
      /primary\s+key/i.test(`${constraint.type} ${constraint.definition}`)
    )
  )
  const objectInsightMetrics = computed<ObjectInsightMetric[]>(() => {
    const ddlLineCount = detail.value?.ddl?.split(/\r?\n/).length ?? 0
    return [
      {
        label: '字段规模',
        value: detailColumns.value.length,
        helper: detailColumns.value.length ? '已读取完整字段元数据' : '当前对象没有字段结构',
        icon: 'ri:table-line'
      },
      {
        label: '约束数量',
        value: detail.value?.constraints?.length ?? 0,
        helper: hasPrimaryKey.value ? '已识别主键约束' : '未识别主键约束',
        icon: 'ri:link-m'
      },
      {
        label: '定义行数',
        value: ddlLineCount,
        helper: detail.value?.ddl ? 'DDL 可查看与复制' : '暂无可显示的 DDL',
        icon: 'ri:code-s-slash-line'
      },
      {
        label: '说明覆盖',
        value: `${objectMetadataCoverage.value}%`,
        helper: `${describedColumnCount.value} 个字段已有说明`,
        icon: 'ri:file-list-3-line'
      }
    ]
  })
  const objectGovernanceChecks = computed<ObjectGovernanceCheck[]>(() => {
    const checks: ObjectGovernanceCheck[] = []
    const hasDescription = Boolean(
      (detail.value?.description || selectedObject.value?.description)?.trim()
    )
    checks.push({
      label: '对象说明',
      detail: hasDescription ? '已配置数据库 COMMENT，业务语义可追溯' : '建议补充用途和数据边界',
      status: hasDescription ? 'success' : 'warning',
      statusLabel: hasDescription ? '完整' : '待补充',
      icon: hasDescription ? 'ri:check-line' : 'ri:error-warning-line'
    })
    checks.push({
      label: '对象定义',
      detail: detail.value?.ddl
        ? '已获取只读 DDL，可用于评审和变更草案'
        : '当前对象没有可显示的 DDL',
      status: detail.value?.ddl ? 'success' : 'warning',
      statusLabel: detail.value?.ddl ? '可追溯' : '不可用',
      icon: detail.value?.ddl ? 'ri:check-line' : 'ri:error-warning-line'
    })
    if (detailColumns.value.length) {
      const allColumnsDescribed = describedColumnCount.value === detailColumns.value.length
      checks.push({
        label: '字段说明',
        detail: `${describedColumnCount.value} / ${detailColumns.value.length} 个字段已有 COMMENT`,
        status: allColumnsDescribed ? 'success' : 'warning',
        statusLabel: allColumnsDescribed ? '完整' : '可提升',
        icon: allColumnsDescribed ? 'ri:check-line' : 'ri:information-line'
      })
    }
    if (selectedObject.value?.objectType === 'table') {
      checks.push({
        label: '主键约束',
        detail: hasPrimaryKey.value ? '已识别 PRIMARY KEY' : '未在对象定义中识别到 PRIMARY KEY',
        status: hasPrimaryKey.value ? 'success' : 'warning',
        statusLabel: hasPrimaryKey.value ? '已配置' : '需复核',
        icon: hasPrimaryKey.value ? 'ri:key-2-line' : 'ri:error-warning-line'
      })
      checks.push({
        label: '外键关系',
        detail: relationships.value.length
          ? `已识别 ${relationships.value.length} 条关联关系`
          : '当前没有已识别的外键关系',
        status: relationships.value.length ? 'success' : 'info',
        statusLabel: relationships.value.length ? '已映射' : '无关系',
        icon: relationships.value.length ? 'ri:git-branch-line' : 'ri:information-line'
      })
    }
    return checks
  })
  const objectAiActions = computed<ObjectAiAction[]>(() => {
    const target = selectedObject.value
      ? `${selectedObject.value.schemaName}.${selectedObject.value.objectName}`
      : '当前对象'
    const actions: ObjectAiAction[] = [
      {
        label: '解释对象设计',
        description: '结合字段、约束和关系说明设计意图',
        prompt: `深度解释 ${target} 的设计意图、核心字段、约束和上下游关系；所有结论必须基于实时工具查询结果。`,
        icon: 'ri:book-open-line'
      },
      {
        label: '安全与性能审计',
        description: '识别权限、索引和结构风险',
        prompt: `对 ${target} 做企业级安全与性能审计，核对 RLS、策略、索引、约束和潜在高风险变更点，并区分已验证事实与建议。`,
        icon: 'ri:shield-check-line'
      },
      {
        label: '生成数据字典',
        description: '输出可交付的字段与关系文档',
        prompt: `为 ${target} 生成结构化数据字典，包含对象用途、字段、类型、默认值、可空性、约束、关系及缺失说明清单。`,
        icon: 'ri:file-list-3-line'
      }
    ]
    if (selectedObject.value?.objectType === 'table') {
      actions.push({
        label: '生成 RLS 方案',
        description: '给出策略草案、验证和回滚步骤',
        prompt: `检查 ${target} 当前 RLS 策略并生成企业级优化草案，覆盖 SELECT、INSERT、UPDATE、DELETE、租户隔离、验证 SQL 和回滚步骤；不要直接执行。`,
        icon: 'ri:shield-keyhole-line'
      })
    }
    return actions
  })
  const chatPhase = computed(() => {
    if (chat.elapsedMs < 2500) return '正在理解问题'
    if (chat.elapsedMs < 8000) return '正在查询项目元数据'
    return '正在整理分析结果'
  })
  const assistantStatusLabel = computed(() => {
    if (assistantStatus.loading) return '能力检测中'
    if (!assistantStatus.online) return '服务待同步'
    const modeLabel = assistantMode.value === 'controlled_write' ? '受控变更' : '只读分析'
    return `AI 在线 · ${modeLabel} · v${assistantStatus.capabilities?.version || '-'}`
  })
  const quickActions = computed(() => [
    {
      label: '安全审计',
      icon: 'ri:shield-check-line',
      prompt: activeChatObject.value
        ? `审计 ${activeChatObject.value.schemaName}.${activeChatObject.value.objectName} 的安全风险，并给出证据和修复草案`
        : '审计当前项目的 RLS 策略与 Edge Function JWT 配置，按严重程度列出风险'
    },
    {
      label: '影响分析',
      icon: 'ri:git-branch-line',
      prompt: activeChatObject.value
        ? `分析修改 ${activeChatObject.value.schemaName}.${activeChatObject.value.objectName} 可能影响的关系与对象`
        : '分析当前项目的核心对象关系与高影响变更点'
    },
    {
      label: '变更方案',
      icon: 'ri:file-list-3-line',
      prompt: activeChatObject.value
        ? `为 ${activeChatObject.value.schemaName}.${activeChatObject.value.objectName} 生成企业级变更方案，包含校验与回滚步骤`
        : '生成一份当前项目的企业级治理优化路线图，不执行任何变更'
    }
  ])

  const stats = computed(() => [
    {
      label: '数据表',
      value: overview.value?.tables ?? '-',
      type: 'table' as ProjectObjectType,
      icon: 'ri:table-2'
    },
    {
      label: '视图',
      value: overview.value?.views ?? '-',
      type: 'view' as ProjectObjectType,
      icon: 'ri:layout-grid-line'
    },
    {
      label: '函数',
      value: overview.value?.functions ?? '-',
      type: 'function' as ProjectObjectType,
      icon: 'ri:function-line'
    },
    {
      label: '触发器',
      value: overview.value?.triggers ?? '-',
      type: 'trigger' as ProjectObjectType,
      icon: 'ri:flashlight-line'
    },
    {
      label: 'RLS 策略',
      value: overview.value?.policies ?? '-',
      type: 'policy' as ProjectObjectType,
      icon: 'ri:shield-keyhole-line'
    },
    {
      label: 'Edge Functions',
      value: edgeFunctions.value?.functions.length ?? '-',
      type: 'all' as ProjectObjectType,
      icon: 'ri:cloud-line'
    }
  ])
  const chatSuggestions = computed(() => {
    if (selectedObject.value) {
      return [
        `解释 ${selectedObject.value.schemaName}.${selectedObject.value.objectName} 的设计`,
        '检查当前对象的安全与性能风险',
        '为当前对象生成优化方案'
      ]
    }
    return ['概览当前 Supabase 项目', '检查 RLS 策略概况', '列出项目 Edge Functions']
  })

  function getObjectIcon(type: ProjectObjectType): string {
    return {
      table: 'ri:table-2',
      view: 'ri:layout-grid-line',
      materialized_view: 'ri:layout-grid-line',
      function: 'ri:function-line',
      trigger: 'ri:flashlight-line',
      policy: 'ri:shield-keyhole-line',
      index: 'ri:list-ordered-2',
      all: 'ri:database-2-line'
    }[type]
  }

  async function loadOverview(): Promise<void> {
    loading.overview = true
    errors.overview = null
    try {
      const [overviewResult, schemaResult, edgeResult] = await Promise.all([
        fetchProjectCatalog<ProjectOverview>({ catalogAction: 'overview' }),
        fetchProjectCatalog<string[]>({ catalogAction: 'schemas' }),
        fetchProjectCatalog<ProjectEdgeFunctionResult>({ catalogAction: 'edge_functions' })
      ])
      overview.value = overviewResult
      schemas.value = schemaResult
      edgeFunctions.value = edgeResult
    } catch (error) {
      errors.overview = error instanceof Error ? error : new Error('项目概览加载失败')
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '项目概览加载失败'))
    } finally {
      loading.overview = false
    }
  }

  async function loadObjects(source: 'initial' | 'filter' | 'refresh' = 'filter'): Promise<void> {
    const requestId = ++activeObjectRequest
    objectLoadSource.value = source
    loading.objects = true
    errors.objects = null
    try {
      const result = await fetchProjectCatalog<ProjectDatabaseObject[]>({
        catalogAction: 'list_objects',
        args: { ...filters, limit: 100 }
      })
      if (requestId !== activeObjectRequest) return
      objects.value = result
    } catch (error) {
      if (requestId !== activeObjectRequest) return
      errors.objects = error instanceof Error ? error : new Error('数据库对象加载失败')
    } finally {
      if (requestId === activeObjectRequest) {
        loading.objects = false
        objectLoadSource.value = null
      }
    }
  }

  async function selectObject(item: ProjectDatabaseObject): Promise<void> {
    selectedObject.value = item
    detail.value = null
    relationships.value = []
    detailTab.value = 'ddl'
    fieldKeyword.value = ''
    loading.detail = true
    errors.detail = null
    errors.relationships = null
    try {
      const requests: [Promise<ProjectObjectDetail>, Promise<ProjectRelationship[]>?] = [
        fetchProjectCatalog<ProjectObjectDetail>({
          catalogAction: 'object_detail',
          args: { objectType: item.objectType, schema: item.schemaName, name: item.objectName }
        })
      ]
      if (item.objectType === 'table') {
        loading.relationships = true
        requests.push(
          fetchProjectCatalog<ProjectRelationship[]>({
            catalogAction: 'relationships',
            args: { schema: item.schemaName, name: item.objectName }
          })
        )
      }
      const [detailResult, relationResult] = await Promise.all(requests)
      detail.value = detailResult
      relationships.value = relationResult ?? []
    } catch (error) {
      errors.detail = error instanceof Error ? error : new Error('对象详情加载失败')
      if (item.objectType === 'table') errors.relationships = errors.detail
    } finally {
      loading.detail = false
      loading.relationships = false
    }
  }

  async function loadInitialData(): Promise<void> {
    initialSettled.value = false
    await Promise.all([loadOverview(), loadObjects('initial')])
    initialSettled.value = true
  }

  function selectStat(type: ProjectObjectType): void {
    if (type === 'all') {
      chat.input = '列出项目 Edge Functions，并指出未启用 JWT 校验的函数'
      void sendMessage()
      return
    }
    filters.objectType = type
    void loadObjects('filter')
  }

  async function toggleAssistantMode(): Promise<boolean> {
    if (assistantMode.value === 'controlled_write') {
      assistantMode.value = 'read_only'
      ElMessage.success('已切换为只读安全模式')
      return false
    }
    if (!canUseControlledWrite.value) {
      ElMessage.warning('仅平台超级管理员可开启受控变更模式')
      return false
    }
    try {
      await confirmAction(
        '受控变更模式允许执行已确认的白名单操作，并会记录操作者、SQL、结果与耗时。是否继续？',
        '开启管理员受控变更',
        {
          type: 'warning',
          confirmButtonText: '确认开启',
          cancelButtonText: '保持只读'
        }
      )
      assistantMode.value = 'controlled_write'
      ElMessage.success('受控变更模式已开启')
      return true
    } catch {
      // 用户取消后保持只读模式。
      return false
    }
  }

  async function editObjectDescription(): Promise<void> {
    const target = selectedObject.value
    if (!target || !canEditSelectedDescription.value) return
    if (assistantMode.value !== 'controlled_write') {
      const enabled = await toggleAssistantMode()
      if (!enabled) return
    }
    try {
      const description = await promptText(
        `为 ${target.schemaName}.${target.objectName} 填写数据库对象说明；留空将清除 COMMENT。`,
        '编辑对象说明',
        {
          allowEmpty: true,
          initialValue: detail.value?.description || target.description || '',
          maxLength: 500,
          maxLengthMessage: '对象说明不能超过 500 个字符',
          multiline: true,
          placeholder: '请输入对象用途、数据范围或业务含义',
          confirmButtonText: '下一步',
          type: 'info'
        }
      )
      await confirmAction(
        `即将写入 ${target.schemaName}.${target.objectName} 的数据库 COMMENT，此操作会记录审计日志。`,
        '确认执行变更',
        {
          type: 'warning',
          confirmButtonText: '确认写入',
          cancelButtonText: '返回检查'
        }
      )
      const response = await updateProjectObjectDescription({
        objectType: target.objectType as 'table' | 'view' | 'materialized_view',
        schema: target.schemaName,
        name: target.objectName,
        description: description || null,
        safetyMode: 'controlled_write',
        confirmed: true
      })
      target.description = response.object.description
      if (detail.value) detail.value.description = response.object.description
      ElMessage.success('对象说明已写入数据库并记录审计')
    } catch (error) {
      if (error !== 'cancel' && error !== 'close') {
        ElMessage.error(getFriendlySupabaseErrorMessage(error, '对象说明更新失败'))
      }
    }
  }

  async function copyDdl(): Promise<void> {
    if (!detail.value?.ddl) return
    await navigator.clipboard.writeText(detail.value.ddl)
    ElMessage.success('DDL 已复制')
  }

  function resetChat(): void {
    activeChatRequest += 1
    chatAbortController?.abort()
    chatAbortController = undefined
    pauseElapsedTimer()
    Object.assign(chat, {
      input: '',
      sending: false,
      startedAt: 0,
      elapsedMs: 0,
      conversationId: undefined,
      messages: []
    })
  }

  function toggleContextLock(): void {
    if (chat.contextLocked) {
      chat.contextLocked = false
      chat.contextObject = selectedObject.value
      ElMessage.info('已解除对象上下文锁定')
      return
    }
    if (!selectedObject.value) return
    chat.contextObject = selectedObject.value
    chat.contextLocked = true
    ElMessage.success(
      `已锁定 ${selectedObject.value.schemaName}.${selectedObject.value.objectName}`
    )
  }

  function getToolLabel(name: string): string {
    return (
      {
        get_project_overview: '项目概览',
        list_database_schemas: 'Schema',
        list_database_objects: '对象目录',
        get_database_object_detail: '对象定义',
        get_table_relationships: '关系分析',
        list_edge_functions: 'Edge Functions',
        get_supabase_capability_snapshot: '全域能力',
        get_security_posture: '安全态势',
        get_performance_posture: '性能态势',
        get_auth_overview: 'Auth',
        get_storage_overview: 'Storage',
        get_realtime_overview: 'Realtime',
        get_database_extensions: '数据库扩展',
        get_async_capabilities: 'Cron / Queues / Vectors'
      }[name] ?? name
    )
  }

  function formatDuration(value?: number | null): string {
    if (value == null) return '-'
    return value < 1000 ? `${value}ms` : `${(value / 1000).toFixed(1)}s`
  }

  async function copyMessage(content: string): Promise<void> {
    await navigator.clipboard.writeText(content)
    ElMessage.success('回答已复制')
  }

  function retryMessage(messageId: string): void {
    const messageIndex = chat.messages.findIndex((item) => item.id === messageId)
    for (let index = messageIndex - 1; index >= 0; index -= 1) {
      if (chat.messages[index].role === 'user') {
        chat.input = chat.messages[index].content
        void sendMessage()
        return
      }
    }
  }

  function exportConversation(): void {
    if (!chat.messages.length) return
    const content = [
      '# Supabase AI 助手会话',
      '',
      `- 导出时间：${new Date().toLocaleString('zh-CN')}`,
      `- 项目：${overview.value?.projectRef || 'ckbftoopuyophiebamwy'}`,
      `- 安全模式：只读`,
      '',
      ...chat.messages.flatMap((message) => [
        `## ${message.role === 'user' ? '用户' : '项目助手'}`,
        '',
        message.content,
        '',
        ...(message.runId
          ? [
              `> Run: ${message.runId} · ${message.model || '-'} · ${formatDuration(message.latencyMs)}`,
              ''
            ]
          : [])
      ])
    ].join('\n')
    const url = URL.createObjectURL(new Blob([content], { type: 'text/markdown;charset=utf-8' }))
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `supabase-ai-${new Date().toISOString().slice(0, 10)}.md`
    anchor.click()
    URL.revokeObjectURL(url)
    ElMessage.success('会话已导出为 Markdown')
  }

  async function openHistory(): Promise<void> {
    await historyDrawerRef.value?.handleOpen()
    await loadHistory()
  }

  async function loadHistory(): Promise<void> {
    const requestId = ++activeHistoryRequest
    history.loading = true
    history.error = ''
    try {
      const result = await fetchProjectAssistantHistory(history.query, 30)
      if (requestId !== activeHistoryRequest) return
      history.items = result.conversations
    } catch (error) {
      if (requestId !== activeHistoryRequest) return
      history.error = getFriendlySupabaseErrorMessage(error, '会话历史加载失败，请稍后重试')
    } finally {
      if (requestId === activeHistoryRequest) history.loading = false
    }
  }

  const scheduleHistorySearch = useDebounceFn(() => {
    void loadHistory()
  }, 320)

  async function loadAssistantCapabilities(): Promise<void> {
    assistantStatus.loading = true
    try {
      const capabilities = await fetchProjectAssistantCapabilities()
      Object.assign(assistantStatus, { online: true, capabilities })
      if (!capabilities.allowedSafetyModes?.includes(assistantMode.value)) {
        assistantMode.value = 'read_only'
      }
    } catch {
      Object.assign(assistantStatus, { online: false, capabilities: null })
    } finally {
      assistantStatus.loading = false
    }
  }

  async function restoreConversation(conversationId: string): Promise<void> {
    if (history.loading) return
    history.loading = true
    try {
      const result = await fetchProjectAssistantConversation(conversationId)
      let runIndex = 0
      const successfulRuns = result.runs.filter((run) => run.status === 'succeeded')
      chat.conversationId = result.conversation.id
      chat.messages = result.messages.map((message) => {
        const run = message.role === 'assistant' ? successfulRuns[runIndex++] : undefined
        return {
          id: String(message.id),
          role: message.role,
          content: message.content,
          createdAt: message.createTime,
          runId: run?.id,
          model: run?.model,
          promptVersion: run?.promptVersion,
          latencyMs: run?.latencyMs,
          tools: run?.toolCalls,
          usage: message.usage
        }
      })
      historyDrawerRef.value?.handleClose()
      scrollChatToBottom()
      ElMessage.success('已恢复历史会话')
    } catch (error) {
      ElMessage.error(getFriendlySupabaseErrorMessage(error, '会话恢复失败'))
    } finally {
      history.loading = false
    }
  }

  async function renameConversation(item: ProjectAssistantConversationSummary): Promise<void> {
    try {
      const title = await promptText('请输入新的会话标题', '重命名会话', {
        initialValue: item.title,
        maxLength: 80,
        maxLengthMessage: '会话标题不能超过 80 个字符',
        emptyMessage: '会话标题不能为空',
        placeholder: '请输入会话标题',
        type: 'info'
      })
      await renameProjectAssistantConversation(item.id, title)
      item.title = title
      ElMessage.success('会话标题已更新')
    } catch (error) {
      if (error !== 'cancel' && error !== 'close') {
        ElMessage.error(getFriendlySupabaseErrorMessage(error, '会话重命名失败'))
      }
    }
  }

  function sendSuggestion(content: string): void {
    chat.input = content
    void sendMessage()
  }

  function openCapabilityCenter(): void {
    void capabilityCenterRef.value?.handleOpen({ edgeFunctions: edgeFunctions.value })
  }

  function analyzePlatformCapability(prompt: string): void {
    chat.contextLocked = false
    chat.contextObject = null
    sendSuggestion(prompt)
  }

  function runObjectAnalysis(action?: ObjectAiAction): void {
    if (!action || !selectedObject.value || chat.sending) return
    chat.contextObject = selectedObject.value
    chat.contextLocked = true
    sendSuggestion(action.prompt)
  }

  function scrollChatToBottom(): void {
    nextTick(() => chatScrollbarRef.value?.setScrollTop(Number.MAX_SAFE_INTEGER))
  }

  function toggleFocusMode(): void {
    focusMode.value = !focusMode.value
    nextTick(() => window.dispatchEvent(new Event('resize')))
  }

  function stopGeneration(): void {
    if (!chat.sending) return
    activeChatRequest += 1
    chatAbortController?.abort()
    chatAbortController = undefined
    chat.sending = false
    pauseElapsedTimer()
    ElMessage.info('已停止等待，你可以调整问题后重新发送')
  }

  async function sendMessage(): Promise<void> {
    const content = chat.input.trim()
    if (!content || chat.sending) return
    const requestId = ++activeChatRequest
    const controller = new AbortController()
    chatAbortController = controller
    chat.messages.push({ id: crypto.randomUUID(), role: 'user', content })
    chat.input = ''
    chat.sending = true
    chat.startedAt = Date.now()
    chat.elapsedMs = 0
    resumeElapsedTimer()
    scrollChatToBottom()
    try {
      const response = await chatWithProjectAssistant(
        {
          conversationId: chat.conversationId,
          safetyMode: assistantMode.value,
          context: {
            routeName: 'SupabaseAiAssistant',
            routePath: '/data-center/supabase-ai-assistant',
            pageTitle: 'Supabase AI 助手',
            ...(activeChatObject.value ? { query: { selectedObject: activeChatObject.value } } : {})
          },
          messages: chat.messages.map(({ role, content: messageContent }) => ({
            role,
            content: messageContent
          }))
        },
        { signal: controller.signal }
      )
      if (requestId !== activeChatRequest) return
      chat.conversationId = response.conversationId
      chat.messages.push({
        id: crypto.randomUUID(),
        role: 'assistant',
        content: response.message,
        runId: response.runId,
        model: response.model,
        promptVersion: response.promptVersion,
        latencyMs: response.latencyMs,
        tools: response.tools,
        usage: response.usage
      })
    } catch (error) {
      if (controller.signal.aborted || requestId !== activeChatRequest) return
      const errorMessage = getFriendlySupabaseErrorMessage(error, '操作失败，请稍后重试')
      const friendlyMessage = /aborted|aborterror|signal|timeout|timed out/i.test(errorMessage)
        ? '模型响应超时，请稍后重试；本次请求未修改任何项目数据。'
        : errorMessage
      chat.messages.push({
        id: crypto.randomUUID(),
        role: 'assistant',
        content: `暂时无法完成这次请求：${friendlyMessage}`
      })
    } finally {
      if (requestId === activeChatRequest) {
        chatAbortController = undefined
        chat.sending = false
        pauseElapsedTimer()
        scrollChatToBottom()
      }
    }
  }

  onBeforeUnmount(() => {
    chatAbortController?.abort()
  })

  onMounted(async () => {
    await Promise.all([loadInitialData(), loadAssistantCapabilities()])
  })
</script>

<style scoped lang="scss">
  .project-assistant-shell {
    height: var(--art-full-height);
    min-height: 720px;

    :deep(> .art-async-state) {
      height: 100%;
    }
  }

  .project-assistant {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-height: 720px;
    overflow: hidden;
    background: var(--art-main-bg-color);

    &__hero {
      position: relative;
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: 104px;
      padding: 17px 22px;
      overflow: hidden;
      background:
        linear-gradient(105deg, transparent 42%, var(--el-color-primary-light-9) 100%),
        var(--default-box-color);

      &::after {
        position: absolute;
        top: -64px;
        right: 8%;
        width: 180px;
        height: 180px;
        pointer-events: none;
        content: '';
        background: radial-gradient(circle, var(--el-color-primary-light-8), transparent 68%);
        border-radius: 50%;
      }

      h1 {
        margin: 4px 0;
        font-size: 22px;
        line-height: 1.35;
        letter-spacing: -0.3px;
        text-wrap: balance;
      }

      p {
        margin: 0;
        line-height: 1.6;
        color: var(--el-text-color-secondary);
      }
    }

    &__eyebrow {
      display: flex;
      gap: 6px;
      align-items: center;
      font-size: 12px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 1.1px;
    }

    &__safety {
      z-index: 1;
      display: flex;
      flex-direction: column;
      gap: 7px;
      align-items: flex-end;
      font-size: 12px;
      color: var(--el-text-color-secondary);

      :deep(.el-tag) {
        border-color: var(--el-color-success-light-7);
      }
    }

    &__hero-actions {
      display: flex;
      gap: 8px;
      align-items: center;

      .el-button {
        height: 28px;
        margin: 0;
        border-radius: 999px;
      }
    }

    &__stats {
      display: grid;
      grid-template-columns: repeat(6, minmax(110px, 1fr));
      padding: 7px;

      button {
        position: relative;
        display: flex;
        gap: 10px;
        align-items: center;
        padding: 10px 13px;
        text-align: left;
        touch-action: manipulation;
        cursor: pointer;
        background: transparent;
        border: 0;
        border-radius: var(--el-border-radius-base);
        transition:
          color 0.2s ease,
          background-color 0.2s ease,
          transform 0.2s ease;

        &:hover {
          background: var(--el-color-primary-light-9);
          transform: translateY(-1px);
        }

        &:focus-visible {
          outline: 2px solid var(--el-color-primary-light-3);
          outline-offset: 1px;
        }

        &.is-active {
          color: var(--el-color-primary);
          background: linear-gradient(135deg, var(--el-color-primary-light-9), transparent);

          &::after {
            position: absolute;
            right: 14px;
            bottom: 5px;
            left: 14px;
            height: 2px;
            content: '';
            background: linear-gradient(90deg, var(--el-color-primary), transparent);
            border-radius: 999px;
          }
        }

        > span {
          display: grid;
          place-items: center;
          width: 32px;
          height: 32px;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: var(--el-border-radius-base);
        }

        strong,
        small {
          display: block;
        }

        strong {
          font-size: 17px;
          font-variant-numeric: tabular-nums;
        }

        small {
          margin-top: 2px;
          color: var(--el-text-color-secondary);
        }
      }
    }

    &__workspace {
      flex: 1;
      min-height: 0;
    }

    &.is-focus-mode {
      gap: 8px;

      .project-assistant__workspace {
        min-height: 640px;
      }
    }

    &__splitter {
      height: 100%;

      :deep(.el-splitter-panel) {
        min-width: 0;
        overflow: hidden;
      }

      :deep(.el-splitter-bar) {
        width: 14px;
        cursor: col-resize;
      }

      :deep(.el-splitter-bar::before) {
        position: absolute;
        top: 12px;
        bottom: 12px;
        left: 50%;
        width: 1px;
        content: '';
        background: var(--el-border-color-lighter);
        transform: translateX(-50%);
        transition: background-color 0.18s ease;
      }

      :deep(.el-splitter-bar__dragger) {
        width: 14px;
        height: 64px;
        border-radius: 999px;
        transition:
          background-color 0.18s ease,
          box-shadow 0.18s ease;
      }

      :deep(.el-splitter-bar__dragger::before) {
        width: 3px;
        height: 30px;
        background: var(--el-border-color);
        border-radius: 999px;
      }

      :deep(.el-splitter-bar:hover::before),
      :deep(.el-splitter-bar:has(.el-splitter-bar__dragger-active)::before) {
        background: var(--el-color-primary-light-6);
      }

      :deep(.el-splitter-bar:hover .el-splitter-bar__dragger),
      :deep(.el-splitter-bar__dragger-active) {
        background: var(--el-color-primary-light-9);
        box-shadow: 0 4px 14px rgb(64 128 255 / 16%);
      }

      :deep(.el-splitter-bar:hover .el-splitter-bar__dragger::before),
      :deep(.el-splitter-bar__dragger-active::before) {
        background: var(--el-color-primary);
      }

      :deep(.el-splitter-bar__collapse-icon) {
        width: 20px;
        height: 30px;
        color: var(--el-text-color-secondary);
        background: var(--el-bg-color);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-small);
        box-shadow: 0 5px 14px rgb(0 0 0 / 8%);
        opacity: 0.9;
        transition:
          color 0.18s ease,
          background-color 0.18s ease,
          border-color 0.18s ease,
          opacity 0.18s ease;
      }

      :deep(.el-splitter-bar__collapse-icon:hover) {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-color: var(--el-color-primary-light-6);
        opacity: 1;
      }
    }

    &__detail,
    &__chat {
      display: flex;
      flex-direction: column;
      min-width: 0;
      height: 100%;
      min-height: 0;
      overflow: hidden;
    }

    &__panel-title {
      display: flex;
      flex: 0 0 auto;
      align-items: center;
      justify-content: space-between;
      min-height: 62px;
      padding: 12px 15px;
      border-bottom: 1px solid var(--el-border-color-lighter);

      strong,
      small {
        display: block;
      }

      small {
        margin-top: 3px;
        font-size: 12px;
        color: var(--el-text-color-secondary);
      }
    }

    &__detail-actions {
      display: flex;
      flex: 0 0 auto;
      align-items: center;
    }

    &__detail-description {
      max-width: min(52vw, 720px);
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    &__detail-state {
      flex: 1;
      min-height: 0;
    }

    &__detail-tabs {
      flex: 1;
      min-height: 0;
      padding: 0 14px 14px;
    }

    &__detail-tabs :deep(.el-tabs__content),
    &__detail-tabs :deep(.el-tab-pane) {
      height: calc(100% - 28px);
    }

    &__insights-scroll,
    &__code-scroll,
    &__relation-list {
      height: 100%;
    }

    &__insights {
      display: flex;
      flex-direction: column;
      gap: 18px;
      padding: 4px 2px 16px;

      :deep(.art-section-title) {
        margin-bottom: 10px;
      }
    }

    &__insight-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(145px, 1fr));
      gap: 10px;

      article {
        display: flex;
        gap: 10px;
        align-items: flex-start;
        min-width: 0;
        padding: 13px;
        background:
          linear-gradient(145deg, var(--el-color-primary-light-9), transparent 72%),
          var(--el-bg-color);
        border: 1px solid var(--el-border-color-extra-light);
        border-radius: var(--el-border-radius-base);

        > span {
          display: grid;
          flex: 0 0 auto;
          place-items: center;
          width: 32px;
          height: 32px;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: var(--el-border-radius-base);
        }

        > div {
          min-width: 0;
        }

        small,
        strong,
        p {
          display: block;
        }

        small {
          font-size: 11px;
          color: var(--el-text-color-secondary);
        }

        strong {
          margin-top: 2px;
          font-size: 19px;
          color: var(--el-text-color-primary);
        }

        p {
          margin: 3px 0 0;
          overflow: hidden;
          text-overflow: ellipsis;
          font-size: 10px;
          color: var(--el-text-color-placeholder);
          white-space: nowrap;
        }
      }
    }

    &__governance-list {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 8px;

      article {
        display: flex;
        gap: 9px;
        align-items: center;
        min-width: 0;
        padding: 10px 12px;
        background: var(--el-fill-color-extra-light);
        border: 1px solid var(--el-border-color-extra-light);
        border-radius: var(--el-border-radius-base);

        > span {
          display: grid;
          flex: 0 0 auto;
          place-items: center;
          width: 28px;
          height: 28px;
          border-radius: 50%;

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
          flex: 1;
          min-width: 0;

          strong,
          small {
            display: block;
          }

          strong {
            font-size: 12px;
          }

          small {
            margin-top: 2px;
            overflow: hidden;
            text-overflow: ellipsis;
            font-size: 10px;
            color: var(--el-text-color-secondary);
            white-space: nowrap;
          }
        }
      }
    }

    &__analysis-actions {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 8px;

      button {
        display: flex;
        gap: 10px;
        align-items: center;
        min-width: 0;
        padding: 11px 12px;
        text-align: left;
        cursor: pointer;
        background: var(--el-bg-color);
        border: 1px solid var(--el-border-color-lighter);
        border-radius: var(--el-border-radius-base);
        transition:
          color 0.18s ease,
          border-color 0.18s ease,
          box-shadow 0.18s ease,
          transform 0.18s ease;

        > span:first-child {
          display: grid;
          flex: 0 0 auto;
          place-items: center;
          width: 32px;
          height: 32px;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: var(--el-border-radius-base);
        }

        > span:nth-child(2) {
          flex: 1;
          min-width: 0;
        }

        strong,
        small {
          display: block;
        }

        small {
          margin-top: 3px;
          overflow: hidden;
          text-overflow: ellipsis;
          color: var(--el-text-color-secondary);
          white-space: nowrap;
        }

        > svg {
          flex: 0 0 auto;
          color: var(--el-text-color-placeholder);
        }

        &:hover:not(:disabled) {
          color: var(--el-color-primary);
          border-color: var(--el-color-primary-light-6);
          box-shadow: 0 8px 20px rgb(64 128 255 / 10%);
          transform: translateY(-1px);
        }

        &:disabled {
          cursor: not-allowed;
          opacity: 0.55;
        }
      }
    }

    &__fields-panel {
      height: 100%;
      min-height: 0;
    }

    &__fields-toolbar {
      display: flex;
      gap: 12px;
      align-items: center;
      justify-content: space-between;
      height: 49px;
      padding-bottom: 9px;

      .el-input {
        width: min(320px, 65%);
      }

      > span {
        flex: 0 0 auto;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }
    }

    &__code {
      box-sizing: border-box;
      width: max-content;
      min-width: 100%;
      min-height: 100%;
      padding: 16px;
      margin: 0;
      font:
        12px/1.7 Consolas,
        monospace;
      color: #d7e0ff;
      white-space: pre;
      background: #111827;
      border-radius: var(--el-border-radius-base);

      code {
        display: block;
      }

      :deep(.hljs-comment),
      :deep(.hljs-quote) {
        font-style: italic;
        color: #68758f;
      }

      :deep(.hljs-keyword),
      :deep(.hljs-selector-tag),
      :deep(.hljs-literal),
      :deep(.hljs-type) {
        color: #c792ea;
      }

      :deep(.hljs-title),
      :deep(.hljs-title.function_),
      :deep(.hljs-built_in) {
        color: #82aaff;
      }

      :deep(.hljs-string),
      :deep(.hljs-regexp) {
        color: #addb67;
      }

      :deep(.hljs-number),
      :deep(.hljs-symbol) {
        color: #f78c6c;
      }

      :deep(.hljs-params),
      :deep(.hljs-variable),
      :deep(.hljs-attr) {
        color: #89ddff;
      }
    }

    &__detail-empty {
      display: flex;
      flex: 1;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      color: var(--el-text-color-secondary);
      text-align: center;
    }

    &__empty-icon {
      display: grid;
      place-items: center;
      width: 72px;
      height: 72px;
      font-size: 34px;
      color: var(--el-color-primary-light-3);
      background: linear-gradient(145deg, var(--el-color-primary-light-9), transparent);
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: 50%;
    }

    &__detail-empty h3 {
      margin: 14px 0 4px;
      color: var(--el-text-color-primary);
    }

    &__detail-empty p {
      margin: 0;
    }

    &__relation-list article {
      display: flex;
      flex-direction: column;
      gap: 7px;
      padding: 12px;
      margin: 10px 0;
      background: var(--el-fill-color-lighter);
      border-radius: var(--el-border-radius-base);
    }

    &__relation-list code {
      color: var(--el-text-color-secondary);
      white-space: pre-wrap;
    }

    &__chat {
      background:
        linear-gradient(180deg, var(--el-color-primary-light-9), transparent 110px),
        var(--default-box-color);
    }

    &__chat-header {
      min-height: 68px;
      background: rgb(255 255 255 / 38%);
      backdrop-filter: blur(10px);
    }

    &__assistant-heading {
      display: flex;
      gap: 10px;
      align-items: center;

      > span:last-child {
        min-width: 0;
      }

      small {
        display: flex;
        gap: 5px;
        align-items: center;

        i {
          box-sizing: content-box;
          width: 7px;
          height: 7px;
          background: var(--el-color-success);
          border: 2px solid var(--el-color-success-light-8);
          border-radius: 50%;

          &.is-offline {
            background: var(--el-color-warning);
            border-color: var(--el-color-warning-light-8);
          }
        }
      }
    }

    &__assistant-avatar {
      display: grid;
      flex: 0 0 auto;
      place-items: center;
      width: 36px;
      height: 36px;
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary-light-3), var(--el-color-primary));
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 8px 18px rgb(64 128 255 / 24%);
    }

    &__chat-actions {
      display: flex;
      flex: 0 0 auto;
      gap: 2px;
      align-items: center;

      .el-button + .el-button {
        margin-left: 0;
      }
    }

    &__chat-context {
      display: flex;
      flex: 0 0 auto;
      gap: 6px;
      align-items: center;
      min-width: 0;
      padding: 8px 14px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-extra-light);
      border-bottom: 1px solid var(--el-border-color-extra-light);

      > svg {
        flex: 0 0 auto;
        color: var(--el-color-primary);
      }

      strong {
        flex: 1;
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        color: var(--el-text-color-regular);
        white-space: nowrap;
      }

      .el-button {
        flex: 0 0 auto;
        margin-left: auto;
      }
    }

    &__messages {
      flex: 1;
      min-height: 0;
      padding: 15px;
      background:
        radial-gradient(circle at 100% 0, var(--el-color-primary-light-9), transparent 34%),
        var(--el-fill-color-extra-light);
    }

    &__chat-welcome {
      display: flex;
      flex-direction: column;
      align-items: stretch;
      padding: 30px 8px 18px;
      text-align: center;
    }

    &__welcome-mark {
      display: grid;
      place-items: center;
      width: 70px;
      height: 70px;
      margin: 0 auto 11px;
      background: radial-gradient(circle, var(--el-color-primary-light-8), transparent 70%);
      border: 1px solid var(--el-color-primary-light-8);
      border-radius: 50%;

      span {
        display: grid;
        place-items: center;
        width: 45px;
        height: 45px;
        font-size: 20px;
        color: white;
        background: linear-gradient(
          145deg,
          var(--el-color-primary-light-3),
          var(--el-color-primary)
        );
        border-radius: var(--el-border-radius-base);
        box-shadow: 0 10px 22px rgb(64 128 255 / 28%);
      }
    }

    &__chat-welcome > small {
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 1.4px;
    }

    &__chat-welcome h3 {
      margin: 7px 0 5px;
      font-size: 17px;
    }

    &__chat-welcome p {
      max-width: 330px;
      margin: 0 auto 18px;
      font-size: 12px;
      line-height: 1.7;
      color: var(--el-text-color-secondary);
    }

    &__chat-welcome .el-button {
      justify-content: space-between;
      width: 100%;
      height: auto;
      min-height: 42px;
      padding: 9px 12px;
      margin: 4px 0;
      color: var(--el-text-color-regular);
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-extra-light);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 4px 12px rgb(0 0 0 / 3%);
      transition:
        color 0.18s ease,
        border-color 0.18s ease,
        transform 0.18s ease,
        box-shadow 0.18s ease;

      span {
        min-width: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        text-align: left;
        white-space: nowrap;
      }

      &:hover {
        color: var(--el-color-primary);
        border-color: var(--el-color-primary-light-7);
        box-shadow: 0 8px 18px rgb(64 128 255 / 10%);
        transform: translateY(-1px);
      }
    }

    &__message {
      display: flex;
      gap: 8px;
      align-items: flex-start;
      margin-bottom: 14px;
    }

    &__message > span {
      display: grid;
      flex: 0 0 auto;
      place-items: center;
      width: 28px;
      height: 28px;
      font-size: 14px;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 4px 12px rgb(64 128 255 / 10%);
    }

    &__message > div {
      max-width: calc(100% - 42px);
      padding: 9px 11px;
      line-height: 1.65;
      white-space: pre-wrap;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 5px 16px rgb(0 0 0 / 4%);
    }

    &__message.is-user {
      flex-direction: row-reverse;
    }

    &__message.is-user > div {
      color: white;
      background: linear-gradient(145deg, var(--el-color-primary-light-3), var(--el-color-primary));
      border-color: var(--el-color-primary);
    }

    &__message.is-user > span {
      color: var(--el-text-color-regular);
      background: var(--el-fill-color);
      box-shadow: none;
    }

    &__message-content {
      white-space: pre-wrap;
    }

    &__message-trace {
      display: flex;
      flex-wrap: wrap;
      gap: 5px;
      align-items: center;
      padding-top: 8px;
      margin-top: 8px;
      font-size: 10px;
      color: var(--el-text-color-secondary);
      border-top: 1px solid var(--el-border-color-extra-light);

      > span {
        padding: 2px 6px;
        background: var(--el-fill-color-light);
        border-radius: 999px;
      }

      :deep(.el-tag) {
        height: 20px;
        font-size: 10px;
        border-radius: 999px;
      }
    }

    &__message-actions {
      display: flex;
      align-items: center;
      min-height: 24px;
      margin: 6px -5px -5px;
      opacity: 0;
      transition: opacity 0.18s ease;

      .el-button + .el-button {
        margin-left: 0;
      }
    }

    &__message:hover &__message-actions,
    &__message:focus-within &__message-actions {
      opacity: 1;
    }

    &__typing {
      display: flex;
      gap: 4px;
      align-items: center;
      color: var(--el-text-color-secondary);

      i {
        width: 5px;
        height: 5px;
        background: var(--el-color-primary-light-3);
        border-radius: 50%;
        animation: project-assistant-typing 1.2s ease-in-out infinite;

        &:nth-child(2) {
          animation-delay: 0.16s;
        }

        &:nth-child(3) {
          animation-delay: 0.32s;
        }
      }

      small {
        margin-left: 4px;
      }
    }

    &__composer {
      flex: 0 0 auto;
      padding: 11px;
      background: var(--el-bg-color);
      border-top: 1px solid var(--el-border-color-lighter);
    }

    &__quick-actions {
      display: flex;
      gap: 6px;
      padding-bottom: 8px;
      overflow-x: auto;
      scrollbar-width: none;

      &::-webkit-scrollbar {
        display: none;
      }

      button {
        display: inline-flex;
        flex: 0 0 auto;
        gap: 4px;
        align-items: center;
        padding: 5px 8px;
        font-size: 11px;
        color: var(--el-text-color-secondary);
        cursor: pointer;
        background: var(--el-fill-color-extra-light);
        border: 1px solid var(--el-border-color-extra-light);
        border-radius: 999px;
        transition:
          color 0.18s ease,
          background-color 0.18s ease,
          border-color 0.18s ease;

        &:hover:not(:disabled) {
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-color: var(--el-color-primary-light-7);
        }

        &:disabled {
          cursor: not-allowed;
          opacity: 0.55;
        }
      }
    }

    &__composer-box {
      padding: 7px 8px 8px;
      background: var(--el-fill-color-extra-light);
      border: 1px solid var(--el-border-color-light);
      border-radius: var(--el-border-radius-base);
      transition:
        border-color 0.18s ease,
        box-shadow 0.18s ease;

      &:focus-within {
        border-color: var(--el-color-primary-light-5);
        box-shadow: 0 0 0 3px var(--el-color-primary-light-9);
      }

      :deep(.el-textarea__inner) {
        min-height: 62px !important;
        padding: 5px 4px;
        background: transparent;
        border: 0;
        box-shadow: none;
      }

      > div {
        display: flex;
        align-items: center;
        justify-content: space-between;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }
    }

    &__safety-toggle {
      display: inline-flex;
      gap: 4px;
      align-items: center;
      padding: 3px 7px;
      font-size: 11px;
      color: var(--el-color-success);
      cursor: pointer;
      background: var(--el-color-success-light-9);
      border: 1px solid var(--el-color-success-light-7);
      border-radius: 999px;

      &.is-write-mode {
        color: var(--el-color-warning-dark-2);
        background: var(--el-color-warning-light-9);
        border-color: var(--el-color-warning-light-7);
      }
    }

    &__send-actions {
      display: flex;
      gap: 8px;
      align-items: center;

      small {
        color: var(--el-text-color-placeholder);
      }

      .el-button {
        width: 32px;
        height: 32px;
        margin: 0;
        box-shadow: 0 6px 14px rgb(64 128 255 / 24%);
      }
    }

    @media (width <= 1280px) {
      &__workspace {
        min-height: 560px;
      }

      &__stats {
        grid-template-columns: repeat(3, 1fr);
      }
    }

    @media (width <= 900px) {
      min-height: auto;
      overflow: visible;

      &__hero {
        flex-direction: column;
        gap: var(--art-space-3);
        align-items: flex-start;
      }

      &__safety {
        align-items: flex-start;

        > span {
          display: none;
        }
      }

      &__stats {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }

      &__workspace {
        height: auto;
      }

      &__splitter {
        display: block;
        height: auto;

        :deep(.el-splitter-panel) {
          width: 100% !important;
          height: 560px;
          margin-bottom: 12px;
          overflow: visible;
        }

        :deep(.el-splitter-bar) {
          display: none;
        }

        :deep(.el-splitter-panel:has(.project-assistant-object-browser)) {
          height: 420px;
        }

        :deep(.el-splitter-panel:has(.project-assistant__detail)) {
          height: 600px;
        }

        :deep(.el-splitter-panel:has(.project-assistant__chat)) {
          height: 680px;
        }
      }
    }

    @media (width <= 640px) {
      gap: var(--art-space-3);

      &__hero {
        min-height: auto;
        padding: var(--art-space-4);

        h1 {
          font-size: 20px;
        }

        p {
          font-size: 13px;
        }
      }

      &__stats {
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: var(--art-space-1);
        padding: var(--art-space-2);

        button {
          min-width: 0;
          min-height: 64px;
          padding-inline: var(--art-space-2);

          > span {
            flex: 0 0 auto;
          }

          > div {
            min-width: 0;

            small {
              overflow: hidden;
              text-overflow: ellipsis;
              white-space: nowrap;
            }
          }
        }
      }

      &__safety,
      &__hero-actions {
        width: 100%;
      }

      &__hero-actions {
        flex-wrap: wrap;
      }

      &__detail-actions,
      &__chat-actions {
        flex-wrap: wrap;
        justify-content: flex-end;
      }
    }
  }

  @media (width <= 640px) {
    .project-assistant-shell {
      height: auto;
      min-height: 0;
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .project-assistant__typing i {
      animation: none;
    }
  }

  @keyframes project-assistant-typing {
    0%,
    60%,
    100% {
      opacity: 0.35;
      transform: translateY(0);
    }

    30% {
      opacity: 1;
      transform: translateY(-2px);
    }
  }
</style>
