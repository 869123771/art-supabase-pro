<template>
  <div class="project-assistant art-full-height">
    <header class="project-assistant__hero">
      <div>
        <div class="project-assistant__eyebrow">
          <ArtSvgIcon icon="ri:database-2-line" />
          SUPABASE PROJECT COPILOT
        </div>
        <h2>Supabase AI 助手</h2>
        <p>只读查看项目结构、对象定义、关系与 Edge Function 元数据，并生成安全变更方案。</p>
      </div>
      <div class="project-assistant__safety">
        <ElTag type="success" effect="light" round>
          <ArtSvgIcon icon="ri:shield-check-line" /> 只读安全模式
        </ElTag>
        <span>项目：{{ overview?.projectRef || 'ckbftoopuyophiebamwy' }}</span>
      </div>
    </header>

    <section class="project-assistant__stats">
      <button
        v-for="stat in stats"
        :key="stat.type"
        type="button"
        :class="{ 'is-active': filters.objectType === stat.type }"
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
      <aside class="project-assistant__catalog">
        <div class="project-assistant__panel-title">
          <div
            ><strong>项目对象</strong><small>{{ objects.length }} 条结果</small></div
          >
          <ElButton text type="primary" :loading="loading.objects" @click="loadObjects">
            <ArtSvgIcon icon="ri:refresh-line" />
          </ElButton>
        </div>
        <div class="project-assistant__filters">
          <ElInput
            v-model="filters.keyword"
            clearable
            placeholder="搜索对象名称"
            @keyup.enter="loadObjects"
            @clear="loadObjects"
          >
            <template #prefix><ArtSvgIcon icon="ri:search-line" /></template>
          </ElInput>
          <div>
            <ElSelect v-model="filters.schema" @change="loadObjects">
              <ElOption label="全部 Schema" value="all" />
              <ElOption v-for="schema in schemas" :key="schema" :label="schema" :value="schema" />
            </ElSelect>
            <ElSelect v-model="filters.objectType" @change="loadObjects">
              <ElOption
                v-for="option in objectTypeOptions"
                :key="option.value"
                :label="option.label"
                :value="option.value"
              />
            </ElSelect>
          </div>
        </div>
        <ElScrollbar v-loading="loading.objects" class="project-assistant__object-list">
          <button
            v-for="item in objects"
            :key="`${item.objectType}:${item.schemaName}:${item.objectName}`"
            type="button"
            :class="{ 'is-active': isSelected(item) }"
            @click="selectObject(item)"
          >
            <span class="project-assistant__object-icon">
              <ArtSvgIcon :icon="getObjectIcon(item.objectType)" />
            </span>
            <span>
              <strong>{{ item.objectName }}</strong>
              <small>{{ item.schemaName }} · {{ getObjectTypeLabel(item.objectType) }}</small>
            </span>
          </button>
          <ElEmpty v-if="!loading.objects && !objects.length" description="没有匹配的项目对象" />
        </ElScrollbar>
      </aside>

      <main class="project-assistant__detail">
        <div class="project-assistant__panel-title">
          <div>
            <strong>{{ selectedObject?.objectName || '对象详情' }}</strong>
            <small v-if="selectedObject">
              {{ selectedObject.schemaName }} · {{ getObjectTypeLabel(selectedObject.objectType) }}
            </small>
            <small v-else>从左侧选择数据库对象</small>
          </div>
          <ElButton v-if="detail?.ddl" text type="primary" @click="copyDdl">
            <ArtSvgIcon icon="ri:file-copy-line" /> 复制 DDL
          </ElButton>
        </div>

        <ElTabs v-if="selectedObject" v-model="detailTab" class="project-assistant__detail-tabs">
          <ElTabPane label="对象定义" name="ddl">
            <ElScrollbar v-loading="loading.detail" class="project-assistant__code-scroll">
              <pre
                v-if="detail?.ddl"
                class="project-assistant__code"
              ><code>{{ detail.ddl }}</code></pre>
              <ElEmpty v-else description="当前对象没有可显示的定义" />
            </ElScrollbar>
          </ElTabPane>
          <ElTabPane v-if="detail?.columns?.length" label="字段" name="columns">
            <ElTable :data="detail.columns" height="100%" stripe>
              <ElTableColumn prop="name" label="字段" min-width="150" />
              <ElTableColumn prop="dataType" label="类型" min-width="160" />
              <ElTableColumn label="可空" width="80">
                <template #default="scope">{{ scope.row.nullable ? '是' : '否' }}</template>
              </ElTableColumn>
              <ElTableColumn
                prop="defaultValue"
                label="默认值"
                min-width="180"
                show-overflow-tooltip
              />
            </ElTable>
          </ElTabPane>
          <ElTabPane v-if="selectedObject.objectType === 'table'" label="外键关系" name="relations">
            <ElScrollbar v-loading="loading.relationships" class="project-assistant__relation-list">
              <article v-for="relation in relationships" :key="relation.constraintName">
                <strong>{{ relation.constraintName }}</strong>
                <span>
                  {{ relation.sourceSchema }}.{{ relation.sourceTable }} →
                  {{ relation.targetSchema }}.{{ relation.targetTable }}
                </span>
                <code>{{ relation.definition }}</code>
              </article>
              <ElEmpty v-if="!relationships.length" description="没有关联此外键的记录" />
            </ElScrollbar>
          </ElTabPane>
        </ElTabs>
        <div v-else class="project-assistant__detail-empty">
          <ArtSvgIcon icon="ri:code-box-line" />
          <h3>选择对象查看定义</h3>
          <p>支持表、视图、函数、触发器、RLS 策略和索引。</p>
        </div>
      </main>

      <aside class="project-assistant__chat">
        <div class="project-assistant__panel-title">
          <div><strong>项目助手</strong><small>结合当前选中对象回答</small></div>
          <ElButton text type="primary" @click="resetChat">
            <ArtSvgIcon icon="ri:chat-new-line" /> 新对话
          </ElButton>
        </div>
        <ElScrollbar ref="chatScrollbarRef" class="project-assistant__messages">
          <div v-if="!chat.messages.length" class="project-assistant__chat-welcome">
            <div><ArtSvgIcon icon="ri:sparkling-2-fill" /></div>
            <h3>询问这个 Supabase 项目</h3>
            <p>我只会调用白名单只读工具，不会执行 SQL 或修改项目。</p>
            <ElButton
              v-for="suggestion in chatSuggestions"
              :key="suggestion"
              text
              @click="sendSuggestion(suggestion)"
            >
              {{ suggestion }} <ArtSvgIcon icon="ri:arrow-right-line" />
            </ElButton>
          </div>
          <article
            v-for="message in chat.messages"
            :key="message.id"
            :class="['project-assistant__message', `is-${message.role}`]"
          >
            <span>{{ message.role === 'assistant' ? 'AI' : '我' }}</span>
            <div>{{ message.content }}</div>
          </article>
          <article v-if="chat.sending" class="project-assistant__message is-assistant">
            <span>AI</span><div class="project-assistant__typing">正在查询项目元数据…</div>
          </article>
        </ElScrollbar>
        <footer class="project-assistant__composer">
          <ElInput
            v-model="chat.input"
            type="textarea"
            resize="none"
            :autosize="{ minRows: 3, maxRows: 6 }"
            maxlength="4000"
            placeholder="例如：解释当前表的 RLS 和外键设计"
            :disabled="chat.sending"
            @keydown.enter.exact.prevent="sendMessage"
          />
          <div>
            <span><ArtSvgIcon icon="ri:shield-check-line" /> 只读安全模式</span>
            <ElButton
              type="primary"
              :loading="chat.sending"
              :disabled="!chat.input.trim()"
              @click="sendMessage"
              >发送</ElButton
            >
          </div>
        </footer>
      </aside>
    </section>
  </div>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import type { ScrollbarInstance } from 'element-plus'
  import { chatWithProjectAssistant, fetchProjectCatalog } from '@/api/supabase-ai-assistant'
  import type {
    ProjectDatabaseObject,
    ProjectEdgeFunctionResult,
    ProjectObjectDetail,
    ProjectObjectType,
    ProjectOverview,
    ProjectRelationship
  } from '@/types/supabase-ai-assistant'

  defineOptions({ name: 'SupabaseAiAssistant' })

  interface ChatMessage {
    id: string
    role: 'user' | 'assistant'
    content: string
  }

  const objectTypeOptions: Array<{ label: string; value: ProjectObjectType }> = [
    { label: '全部对象', value: 'all' },
    { label: '数据表', value: 'table' },
    { label: '视图', value: 'view' },
    { label: '函数', value: 'function' },
    { label: '触发器', value: 'trigger' },
    { label: 'RLS 策略', value: 'policy' },
    { label: '索引', value: 'index' }
  ]
  const overview = ref<ProjectOverview | null>(null)
  const schemas = ref<string[]>(['public'])
  const objects = ref<ProjectDatabaseObject[]>([])
  const detail = ref<ProjectObjectDetail | null>(null)
  const relationships = ref<ProjectRelationship[]>([])
  const edgeFunctions = ref<ProjectEdgeFunctionResult | null>(null)
  const selectedObject = ref<ProjectDatabaseObject | null>(null)
  const detailTab = ref('ddl')
  const chatScrollbarRef = ref<ScrollbarInstance>()
  const loading = reactive({ overview: false, objects: false, detail: false, relationships: false })
  const filters = reactive<{ schema: string; objectType: ProjectObjectType; keyword: string }>({
    schema: 'public',
    objectType: 'table',
    keyword: ''
  })
  const chat = reactive({
    input: '',
    sending: false,
    conversationId: undefined as string | undefined,
    messages: [] as ChatMessage[]
  })

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

  function getObjectTypeLabel(type: ProjectObjectType): string {
    return objectTypeOptions.find((item) => item.value === type)?.label ?? type
  }

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

  function isSelected(item: ProjectDatabaseObject): boolean {
    return (
      selectedObject.value?.schemaName === item.schemaName &&
      selectedObject.value?.objectName === item.objectName &&
      selectedObject.value?.objectType === item.objectType
    )
  }

  async function loadOverview(): Promise<void> {
    loading.overview = true
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
      ElMessage.error(error instanceof Error ? error.message : '项目概览加载失败')
    } finally {
      loading.overview = false
    }
  }

  async function loadObjects(): Promise<void> {
    loading.objects = true
    try {
      objects.value = await fetchProjectCatalog<ProjectDatabaseObject[]>({
        catalogAction: 'list_objects',
        args: { ...filters, limit: 100 }
      })
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '数据库对象加载失败')
    } finally {
      loading.objects = false
    }
  }

  async function selectObject(item: ProjectDatabaseObject): Promise<void> {
    selectedObject.value = item
    detail.value = null
    relationships.value = []
    detailTab.value = 'ddl'
    loading.detail = true
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
      ElMessage.error(error instanceof Error ? error.message : '对象详情加载失败')
    } finally {
      loading.detail = false
      loading.relationships = false
    }
  }

  function selectStat(type: ProjectObjectType): void {
    if (type === 'all') {
      chat.input = '列出项目 Edge Functions，并指出未启用 JWT 校验的函数'
      void sendMessage()
      return
    }
    filters.objectType = type
    void loadObjects()
  }

  async function copyDdl(): Promise<void> {
    if (!detail.value?.ddl) return
    await navigator.clipboard.writeText(detail.value.ddl)
    ElMessage.success('DDL 已复制')
  }

  function resetChat(): void {
    Object.assign(chat, { input: '', sending: false, conversationId: undefined, messages: [] })
  }

  function sendSuggestion(content: string): void {
    chat.input = content
    void sendMessage()
  }

  function scrollChatToBottom(): void {
    nextTick(() => chatScrollbarRef.value?.setScrollTop(Number.MAX_SAFE_INTEGER))
  }

  async function sendMessage(): Promise<void> {
    const content = chat.input.trim()
    if (!content || chat.sending) return
    chat.messages.push({ id: crypto.randomUUID(), role: 'user', content })
    chat.input = ''
    chat.sending = true
    scrollChatToBottom()
    try {
      const response = await chatWithProjectAssistant({
        conversationId: chat.conversationId,
        context: {
          routeName: 'SupabaseAiAssistant',
          routePath: '/data-center/supabase-ai-assistant',
          pageTitle: 'Supabase AI 助手',
          ...(selectedObject.value ? { query: { selectedObject: selectedObject.value } } : {})
        },
        messages: chat.messages.map(({ role, content: messageContent }) => ({
          role,
          content: messageContent
        }))
      })
      chat.conversationId = response.conversationId
      chat.messages.push({ id: crypto.randomUUID(), role: 'assistant', content: response.message })
    } catch (error) {
      chat.messages.push({
        id: crypto.randomUUID(),
        role: 'assistant',
        content: `暂时无法完成这次请求：${error instanceof Error ? error.message : '未知错误'}`
      })
    } finally {
      chat.sending = false
      scrollChatToBottom()
    }
  }

  onMounted(async () => {
    await Promise.all([loadOverview(), loadObjects()])
  })
</script>

<style scoped lang="scss">
  .project-assistant {
    display: flex;
    flex-direction: column;
    gap: 14px;
    min-height: 720px;
    padding: 18px;
    overflow: hidden;
    background: var(--art-main-bg-color);

    &__hero,
    &__stats,
    &__workspace > * {
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: 12px;
    }

    &__hero {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 18px 22px;
      background:
        radial-gradient(circle at 88% 0, var(--el-color-primary-light-8), transparent 34%),
        var(--el-bg-color);

      h2 {
        margin: 5px 0 4px;
        font-size: 22px;
      }

      p {
        margin: 0;
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
      letter-spacing: 1px;
    }

    &__safety {
      display: flex;
      flex-direction: column;
      gap: 7px;
      align-items: flex-end;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    &__stats {
      display: grid;
      grid-template-columns: repeat(6, minmax(110px, 1fr));
      padding: 8px;

      button {
        display: flex;
        gap: 10px;
        align-items: center;
        padding: 10px 14px;
        text-align: left;
        cursor: pointer;
        background: transparent;
        border: 0;
        border-radius: 9px;

        &:hover,
        &.is-active {
          background: var(--el-color-primary-light-9);
        }

        > span {
          display: grid;
          place-items: center;
          width: 32px;
          height: 32px;
          color: var(--el-color-primary);
          background: var(--el-color-primary-light-9);
          border-radius: 8px;
        }

        strong,
        small {
          display: block;
        }

        strong {
          font-size: 17px;
        }

        small {
          margin-top: 2px;
          color: var(--el-text-color-secondary);
        }
      }
    }

    &__workspace {
      display: grid;
      flex: 1;
      grid-template-columns: 280px minmax(380px, 1fr) minmax(340px, 410px);
      gap: 14px;
      min-height: 0;
    }

    &__catalog,
    &__detail,
    &__chat {
      display: flex;
      flex-direction: column;
      min-width: 0;
      min-height: 0;
      overflow: hidden;
    }

    &__panel-title {
      display: flex;
      align-items: center;
      justify-content: space-between;
      min-height: 61px;
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

    &__filters {
      display: flex;
      flex-direction: column;
      gap: 8px;
      padding: 12px;
      border-bottom: 1px solid var(--el-border-color-lighter);

      > div {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 8px;
      }
    }

    &__object-list {
      flex: 1;
      min-height: 0;
      padding: 7px;
    }

    &__object-list button {
      display: flex;
      gap: 10px;
      align-items: center;
      width: 100%;
      padding: 10px;
      text-align: left;
      cursor: pointer;
      background: transparent;
      border: 0;
      border-radius: 8px;

      &:hover,
      &.is-active {
        background: var(--el-color-primary-light-9);
      }

      &.is-active strong,
      .project-assistant__object-icon {
        color: var(--el-color-primary);
      }

      strong,
      small {
        display: block;
        max-width: 190px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      small {
        margin-top: 2px;
        font-size: 11px;
        color: var(--el-text-color-secondary);
      }
    }

    &__object-icon {
      display: grid;
      flex: 0 0 auto;
      place-items: center;
      width: 30px;
      height: 30px;
      background: var(--el-fill-color-light);
      border-radius: 7px;
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

    &__code-scroll,
    &__relation-list {
      height: 100%;
    }

    &__code {
      min-height: 100%;
      padding: 16px;
      margin: 0;
      overflow: auto;
      font:
        12px/1.7 Consolas,
        monospace;
      color: #d7e0ff;
      white-space: pre-wrap;
      background: #111827;
      border-radius: 9px;
    }

    &__detail-empty {
      display: grid;
      flex: 1;
      place-content: center;
      color: var(--el-text-color-secondary);
      text-align: center;
    }

    &__detail-empty > svg {
      margin: 0 auto;
      font-size: 44px;
      color: var(--el-color-primary-light-5);
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
      border-radius: 8px;
    }

    &__relation-list code {
      color: var(--el-text-color-secondary);
      white-space: pre-wrap;
    }

    &__messages {
      flex: 1;
      min-height: 0;
      padding: 15px;
      background: var(--el-fill-color-extra-light);
    }

    &__chat-welcome {
      display: flex;
      flex-direction: column;
      align-items: stretch;
      padding: 30px 10px;
      text-align: center;
    }

    &__chat-welcome > div {
      display: grid;
      place-items: center;
      width: 48px;
      height: 48px;
      margin: 0 auto;
      font-size: 22px;
      color: white;
      background: var(--el-color-primary);
      border-radius: 14px;
    }

    &__chat-welcome h3 {
      margin: 14px 0 5px;
    }

    &__chat-welcome p {
      margin: 0 0 18px;
      font-size: 12px;
      line-height: 1.6;
      color: var(--el-text-color-secondary);
    }

    &__chat-welcome .el-button {
      justify-content: space-between;
      height: 38px;
      padding: 0 12px;
      margin: 4px 0;
      background: var(--el-bg-color);
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
      font-size: 11px;
      font-weight: 700;
      color: var(--el-color-primary);
      background: var(--el-color-primary-light-9);
      border-radius: 8px;
    }

    &__message > div {
      padding: 9px 11px;
      line-height: 1.65;
      white-space: pre-wrap;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: 4px 10px 10px;
    }

    &__message.is-user {
      flex-direction: row-reverse;
    }

    &__message.is-user > div {
      color: white;
      background: var(--el-color-primary);
      border-color: var(--el-color-primary);
      border-radius: 10px 4px 10px 10px;
    }

    &__typing {
      color: var(--el-text-color-secondary);
    }

    &__composer {
      padding: 12px;
      border-top: 1px solid var(--el-border-color-lighter);
    }

    &__composer > div {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-top: 9px;
      font-size: 11px;
      color: var(--el-text-color-secondary);
    }
  }

  @media (width <= 1280px) {
    .project-assistant {
      &__workspace {
        grid-template-columns: 250px minmax(360px, 1fr);
      }

      &__chat {
        display: none;
      }

      &__stats {
        grid-template-columns: repeat(3, 1fr);
      }
    }
  }
</style>
