<template>
  <ArtDrawer
    ref="drawerRef"
    :show-footer="false"
    :drawer-props="drawerProps"
    @opened="scrollToBottom"
  >
    <template #header="{ api }">
      <header class="art-ai-assistant__header">
        <div class="art-ai-assistant__identity">
          <div class="art-ai-assistant__brand-icon">
            <ArtSvgIcon :icon="assistantIcon" />
          </div>
          <div class="art-ai-assistant__identity-copy">
            <div class="art-ai-assistant__title-row">
              <strong>{{ assistantTitle }}</strong>
              <span>只读模式</span>
            </div>
            <div class="art-ai-assistant__status">
              <i :class="{ 'is-offline': !isOnline }"></i>
              <span>{{ isOnline ? '服务已连接' : '网络已断开' }}</span>
              <em>·</em>
              <span class="art-ai-assistant__page">{{ pageTitle }}</span>
            </div>
          </div>
        </div>

        <div class="art-ai-assistant__header-actions">
          <ElSegmented
            v-if="userStore.isPlatformSuper"
            v-model="assistantMode"
            :options="assistantModeOptions"
            size="small"
            class="art-ai-assistant__mode-switch"
          />
          <ElTooltip v-if="isProjectMode" content="进入 Supabase AI 工作台" placement="bottom">
            <ArtIconButton
              icon="ri:fullscreen-line"
              circle
              aria-label="进入 Supabase AI 工作台"
              class="art-ai-assistant__header-button"
              @click="openProjectWorkbench"
            />
          </ElTooltip>
          <ElTooltip content="新建对话" placement="bottom">
            <ArtIconButton
              icon="ri:chat-new-line"
              circle
              aria-label="新建对话"
              class="art-ai-assistant__header-button"
              @click="resetConversation"
            />
          </ElTooltip>
          <ElTooltip content="关闭" placement="bottom">
            <ArtIconButton
              icon="ri:close-line"
              circle
              :aria-label="`关闭 ${assistantTitle}`"
              class="art-ai-assistant__header-button"
              @click="api.handleClose()"
            />
          </ElTooltip>
        </div>
      </header>
    </template>

    <div class="art-ai-assistant">
      <ElScrollbar ref="scrollbarRef" class="art-ai-assistant__messages">
        <div class="art-ai-assistant__conversation">
          <section v-if="showWelcome" class="art-ai-assistant__welcome">
            <div class="art-ai-assistant__welcome-mark">
              <ArtSvgIcon :icon="assistantIcon" />
            </div>
            <span class="art-ai-assistant__eyebrow">{{ assistantEyebrow }}</span>
            <h2>{{ welcomeTitle }}</h2>
            <p>{{ welcomeDescription }}</p>
            <div class="art-ai-assistant__context-pill">
              <ArtSvgIcon icon="ri:focus-3-line" />
              正在关注：{{ pageTitle }}
            </div>

            <div class="art-ai-assistant__prompt-grid">
              <button
                v-for="suggestion in suggestions"
                :key="suggestion.label"
                type="button"
                class="art-ai-assistant__prompt-card"
                :disabled="!isOnline"
                @click="sendSuggestion(suggestion.label)"
              >
                <span class="art-ai-assistant__prompt-icon">
                  <ArtSvgIcon :icon="suggestion.icon" />
                </span>
                <span>
                  <strong>{{ suggestion.label }}</strong>
                  <small>{{ suggestion.description }}</small>
                </span>
                <ArtSvgIcon icon="ri:arrow-right-up-line" />
              </button>
            </div>

            <div class="art-ai-assistant__capabilities">
              <span><ArtSvgIcon icon="ri:shield-check-line" /> 权限隔离</span>
              <span><ArtSvgIcon icon="ri:database-2-line" /> {{ dataCapabilityLabel }}</span>
              <span><ArtSvgIcon icon="ri:eye-line" /> 不修改数据</span>
            </div>
          </section>

          <template v-else>
            <article
              v-for="message in state.messages"
              :key="message.id"
              class="art-ai-assistant__message"
              :class="{
                'is-user': message.role === 'user',
                'is-error': message.isError
              }"
            >
              <ElAvatar
                v-if="message.role === 'user'"
                :size="32"
                :src="userAvatar"
                class="art-ai-assistant__avatar"
              />
              <div v-else class="art-ai-assistant__assistant-avatar">
                <ArtSvgIcon :icon="assistantIcon" />
              </div>

              <div class="art-ai-assistant__message-body">
                <div class="art-ai-assistant__message-meta">
                  <span>{{ message.role === 'user' ? userName : assistantTitle }}</span>
                  <time>{{ message.time }}</time>
                </div>
                <div class="art-ai-assistant__bubble">{{ message.content }}</div>

                <div v-if="message.tools?.length" class="art-ai-assistant__tools">
                  <span
                    v-for="tool in message.tools"
                    :key="tool.name"
                    :class="{ 'is-failed': tool.status === 'failed' }"
                  >
                    <ArtSvgIcon
                      :icon="
                        tool.status === 'succeeded' ? 'ri:check-line' : 'ri:error-warning-line'
                      "
                    />
                    {{ tool.status === 'succeeded' ? '已查询' : '查询失败' }} ·
                    {{ getToolLabel(tool.name) }}
                  </span>
                </div>

                <div v-if="message.isError" class="art-ai-assistant__retry">
                  <ElButton
                    size="small"
                    plain
                    :icon="Refresh"
                    :disabled="state.sending || !isOnline"
                    @click="retryMessage(message)"
                  >
                    重新尝试
                  </ElButton>
                </div>

                <div
                  v-else-if="message.role === 'assistant' && message.runId"
                  class="art-ai-assistant__feedback"
                >
                  <span>回答是否有帮助？</span>
                  <ElTooltip content="有帮助" placement="bottom">
                    <ArtIconButton
                      :icon="message.feedback === 1 ? 'ri:thumb-up-fill' : 'ri:thumb-up-line'"
                      :class="{ 'is-active': message.feedback === 1 }"
                      class="art-ai-assistant__feedback-button"
                      @click="handleFeedback(message, 1)"
                    />
                  </ElTooltip>
                  <ElTooltip content="需要改进" placement="bottom">
                    <ArtIconButton
                      :icon="message.feedback === -1 ? 'ri:thumb-down-fill' : 'ri:thumb-down-line'"
                      :class="{ 'is-active is-negative': message.feedback === -1 }"
                      class="art-ai-assistant__feedback-button"
                      @click="handleFeedback(message, -1)"
                    />
                  </ElTooltip>
                </div>
              </div>
            </article>

            <article v-if="state.sending" class="art-ai-assistant__message">
              <div class="art-ai-assistant__assistant-avatar">
                <ArtSvgIcon :icon="assistantIcon" />
              </div>
              <div class="art-ai-assistant__message-body">
                <div class="art-ai-assistant__message-meta">
                  <span>{{ assistantTitle }}</span>
                  <span>正在处理</span>
                </div>
                <div class="art-ai-assistant__thinking">
                  <ArtSvgIcon icon="ri:loader-4-line" />
                  <span>{{ thinkingText }}</span>
                </div>
              </div>
            </article>
          </template>
        </div>
      </ElScrollbar>

      <footer class="art-ai-assistant__composer">
        <div class="art-ai-assistant__composer-box">
          <ElInput
            v-model="state.input"
            type="textarea"
            :autosize="{ minRows: 2, maxRows: 6 }"
            :maxlength="4000"
            resize="none"
            :placeholder="composerPlaceholder"
            :disabled="state.sending || !isOnline"
            @keydown.enter.exact.prevent="sendMessage"
          />
          <div class="art-ai-assistant__composer-actions">
            <div class="art-ai-assistant__composer-meta">
              <span><ArtSvgIcon icon="ri:shield-check-line" /> 只读安全模式</span>
              <span>{{ state.input.length }} / 4000</span>
            </div>
            <ElButton
              type="primary"
              :icon="Promotion"
              :loading="state.sending"
              :disabled="!state.input.trim() || !isOnline"
              @click="sendMessage"
            >
              发送
            </ElButton>
          </div>
        </div>
        <p>{{ footerNotice }}</p>
      </footer>
    </div>
  </ArtDrawer>
</template>

<script setup lang="ts">
  import { Promotion, Refresh } from '@element-plus/icons-vue'
  import { useNetwork, useWindowSize } from '@vueuse/core'
  import { ElMessage } from 'element-plus'
  import type { ScrollbarInstance } from 'element-plus'
  import { useRoute, useRouter } from 'vue-router'
  import { chatWithAiAssistant, submitAiAssistantFeedback } from '@/api/ai-assistant'
  import {
    chatWithProjectAssistant,
    submitProjectAssistantFeedback
  } from '@/api/supabase-ai-assistant'
  import ArtDrawer from '@/components/core/drawers/art-drawer/index.vue'
  import type { ArtDrawerExpose } from '@/components/core/drawers/art-drawer/types'
  import ArtIconButton from '@/components/core/widget/art-icon-button/index.vue'
  import { useUserStore } from '@/store/modules/user'
  import type {
    AiAssistantMessageRole,
    AiAssistantPageContext,
    AiAssistantToolResult
  } from '@/types/ai-assistant'
  import { mittBus } from '@/utils/sys'
  import meAvatar from '@/assets/images/avatar/avatar5.webp'

  defineOptions({ name: 'ArtChatWindow' })

  interface ChatMessage {
    id: string
    role: AiAssistantMessageRole
    content: string
    time: string
    runId?: string
    tools?: AiAssistantToolResult[]
    feedback?: -1 | 1
    isError?: boolean
    retryContent?: string
  }

  interface AssistantState {
    sending: boolean
    input: string
    conversationId?: string
    routePath?: string
    messages: ChatMessage[]
  }

  interface PromptSuggestion {
    label: string
    description: string
    icon: string
  }

  const MOBILE_BREAKPOINT = 640
  const route = useRoute()
  const router = useRouter()
  const userStore = useUserStore()
  const { width } = useWindowSize()
  const { isOnline } = useNetwork()
  const drawerRef = ref<ArtDrawerExpose<Record<string, never>>>()
  const scrollbarRef = ref<ScrollbarInstance>()
  const isMobile = computed(() => width.value < MOBILE_BREAKPOINT)
  const assistantMode = ref<'business' | 'project'>('business')
  const assistantModeOptions = [
    { label: '业务助手', value: 'business' },
    { label: 'Supabase', value: 'project' }
  ]
  const isProjectMode = computed(() => assistantMode.value === 'project')
  const assistantTitle = computed(() => (isProjectMode.value ? 'Supabase 管理助手' : 'AI 业务助理'))
  const assistantIcon = computed(() =>
    isProjectMode.value ? 'ri:database-2-line' : 'ri:sparkling-2-fill'
  )
  const assistantEyebrow = computed(() =>
    isProjectMode.value ? 'SUPABASE PROJECT COPILOT' : 'ART BUSINESS COPILOT'
  )
  const welcomeTitle = computed(() =>
    isProjectMode.value ? '想了解项目里的什么？' : '今天想了解什么？'
  )
  const welcomeDescription = computed(() =>
    isProjectMode.value
      ? '我可以只读查看数据库对象、DDL、外键关系和 Edge Function 元数据，并生成变更方案。'
      : '我会结合当前页面和你的数据权限，查询订单、运输经营情况与车辆临期事项。'
  )
  const dataCapabilityLabel = computed(() =>
    isProjectMode.value ? '项目实时元数据' : '实时业务数据'
  )
  const thinkingText = computed(() =>
    isProjectMode.value ? '正在读取并分析项目元数据…' : '正在查询并整理业务数据…'
  )
  const composerPlaceholder = computed(() =>
    isProjectMode.value
      ? '询问数据库、函数、RLS 或 Edge Function，Enter 发送'
      : '输入业务问题，Enter 发送，Shift + Enter 换行'
  )
  const footerNotice = computed(() =>
    isProjectMode.value
      ? '当前为只读安全模式：不会执行 DDL、DML 或任意 SQL。'
      : 'AI 生成内容可能存在偏差，关键业务信息请以系统记录为准。'
  )
  const drawerProps = {
    appendToBody: true,
    closeOnClickModal: false,
    showClose: false,
    class: 'art-ai-assistant-drawer'
  }
  const pageTitle = computed(() => {
    const title = route.meta.title
    if (typeof title === 'string' && title) return title
    return typeof route.name === 'string' ? route.name : '当前页面'
  })
  const userName = computed(
    () =>
      userStore.getUserInfo.nickName ||
      userStore.getUserInfo.userName ||
      userStore.getUserInfo.email ||
      '当前用户'
  )
  const userAvatar = computed(() => userStore.getUserInfo.avatar || meAvatar)
  const state = reactive<AssistantState>({
    sending: false,
    input: '',
    conversationId: undefined,
    routePath: undefined,
    messages: []
  })

  const suggestions = computed<PromptSuggestion[]>(() => {
    if (isProjectMode.value) {
      return [
        {
          label: '概览当前 Supabase 项目',
          description: '统计数据库对象和项目能力',
          icon: 'ri:dashboard-3-line'
        },
        {
          label: '列出 public schema 的表',
          description: '查看表、说明和对象目录',
          icon: 'ri:table-2'
        },
        {
          label: '检查 RLS 策略概况',
          description: '查看策略对象并提示安全风险',
          icon: 'ri:shield-keyhole-line'
        },
        {
          label: '列出项目 Edge Functions',
          description: '查看函数状态和 JWT 校验配置',
          icon: 'ri:cloud-line'
        }
      ]
    }
    const items: PromptSuggestion[] = [
      {
        label: '总结最近订单',
        description: '查看最新订单、线路、状态和费用',
        icon: 'ri:file-list-3-line'
      },
      {
        label: '查看近 30 天运输概览',
        description: '汇总订单量、状态分布与费用',
        icon: 'ri:line-chart-line'
      },
      {
        label: '查询 30 天内车辆到期事项',
        description: '检查保险、年检和服务期限',
        icon: 'ri:alarm-warning-line'
      }
    ]
    if (getRecordId()) {
      items.unshift({
        label: '总结当前订单',
        description: '基于当前记录提炼关键信息',
        icon: 'ri:focus-3-line'
      })
    } else {
      items.unshift({
        label: '这个页面可以做什么？',
        description: '了解当前页面和可用能力',
        icon: 'ri:compass-3-line'
      })
    }
    return items
  })
  const showWelcome = computed(() => state.messages.length === 0 && !state.sending)

  function formatCurrentTime(): string {
    return new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  }

  function getRecordId(): string | undefined {
    const candidate = route.params.id ?? route.query.id
    if (Array.isArray(candidate)) return candidate[0]
    return typeof candidate === 'string' && candidate ? candidate : undefined
  }

  function getPageContext(): AiAssistantPageContext {
    return {
      routeName: typeof route.name === 'string' ? route.name : undefined,
      routePath: route.path,
      pageTitle: pageTitle.value,
      recordId: getRecordId(),
      query: { ...route.query }
    }
  }

  function scrollToBottom(): void {
    nextTick(() => scrollbarRef.value?.setScrollTop(Number.MAX_SAFE_INTEGER))
  }

  function resetConversation(): void {
    Object.assign(state, {
      sending: false,
      input: '',
      conversationId: undefined,
      routePath: route.fullPath,
      messages: []
    })
    scrollToBottom()
  }

  async function openProjectWorkbench(): Promise<void> {
    await drawerRef.value?.handleClose()
    await router.push('/data-center/supabase-ai-assistant')
  }

  function openChat(): void {
    if (state.routePath && state.routePath !== route.fullPath) resetConversation()
    state.routePath = route.fullPath
    void drawerRef.value?.handleOpen(
      {},
      {
        size: isMobile.value ? '100%' : userStore.isPlatformSuper ? '680px' : '600px',
        showFooter: false,
        resetOnClose: false,
        drawerProps
      }
    )
  }

  function sendSuggestion(suggestion: string): void {
    state.input = suggestion
    void sendMessage()
  }

  function retryMessage(message: ChatMessage): void {
    if (!message.retryContent || state.sending) return
    state.messages = state.messages.filter((item) => item.id !== message.id)
    state.input = message.retryContent
    void sendMessage()
  }

  async function sendMessage(): Promise<void> {
    const content = state.input.trim()
    if (!content || state.sending || !isOnline.value) return

    state.messages.push({
      id: crypto.randomUUID(),
      role: 'user',
      content,
      time: formatCurrentTime()
    })
    state.input = ''
    state.sending = true
    scrollToBottom()

    try {
      const chat = isProjectMode.value ? chatWithProjectAssistant : chatWithAiAssistant
      const response = await chat({
        conversationId: state.conversationId,
        context: getPageContext(),
        messages: state.messages
          .filter((message) => !message.isError)
          .map((message) => ({ role: message.role, content: message.content }))
      })
      state.conversationId = response.conversationId
      state.messages.push({
        id: crypto.randomUUID(),
        role: 'assistant',
        content: response.message,
        time: formatCurrentTime(),
        runId: response.runId,
        tools: response.tools
      })
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'AI 助手暂时不可用'
      state.messages.push({
        id: crypto.randomUUID(),
        role: 'assistant',
        content: getFriendlyErrorMessage(errorMessage),
        time: formatCurrentTime(),
        isError: true,
        retryContent: content
      })
    } finally {
      state.sending = false
      scrollToBottom()
    }
  }

  function getFriendlyErrorMessage(message: string): string {
    if (message.includes('超时') || message.toLowerCase().includes('timeout')) {
      return '这次请求没有在规定时间内完成。高频业务查询已启用快速通道，你可以重新尝试。'
    }
    return `暂时无法完成这次请求：${message}`
  }

  async function handleFeedback(message: ChatMessage, rating: -1 | 1): Promise<void> {
    if (!message.runId || message.feedback === rating) return
    try {
      const submitFeedback = isProjectMode.value
        ? submitProjectAssistantFeedback
        : submitAiAssistantFeedback
      await submitFeedback({ runId: message.runId, rating })
      message.feedback = rating
      ElMessage.success('感谢你的反馈')
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : '反馈提交失败')
    }
  }

  function getToolLabel(name: string): string {
    const labels: Record<string, string> = {
      get_order_detail: '订单详情',
      get_recent_orders: '最近订单',
      get_transport_overview: '运输概览',
      get_vehicle_expiries: '车辆到期',
      get_project_overview: '项目概览',
      list_database_objects: '数据库对象',
      get_database_object_detail: '对象定义',
      get_table_relationships: '外键关系',
      list_edge_functions: 'Edge Functions'
    }
    return labels[name] ?? name
  }

  watch(
    () => route.fullPath,
    (path) => {
      if (state.routePath && state.routePath !== path) resetConversation()
    }
  )
  watch(assistantMode, resetConversation)
  onMounted(() => mittBus.on('openChat', openChat))
  onUnmounted(() => mittBus.off('openChat', openChat))
</script>

<style scoped lang="scss">
  :global(.art-ai-assistant-drawer .el-drawer__header) {
    padding: 0;
    margin-bottom: 0;
    border-bottom: 1px solid var(--el-border-color-lighter);
  }

  :global(.art-ai-assistant-drawer .el-drawer__body) {
    padding: 0;
  }

  :global(.art-ai-assistant-drawer .art-drawer__content) {
    height: 100%;
  }

  .art-ai-assistant {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 0;
    background:
      radial-gradient(circle at 88% 4%, var(--el-color-primary-light-9), transparent 24%),
      var(--el-bg-color);

    &__header {
      display: flex;
      gap: 18px;
      align-items: center;
      justify-content: space-between;
      width: 100%;
      min-height: 76px;
      padding: 14px 20px;
    }

    &__identity,
    &__title-row,
    &__status,
    &__header-actions,
    &__tools,
    &__feedback,
    &__composer-actions,
    &__composer-meta,
    &__capabilities,
    &__context-pill,
    &__thinking {
      display: flex;
      align-items: center;
    }

    &__identity {
      gap: 12px;
      min-width: 0;
    }

    &__brand-icon,
    &__welcome-mark,
    &__assistant-avatar,
    &__prompt-icon {
      display: grid;
      flex-shrink: 0;
      place-items: center;
      color: var(--el-color-white);
      background: linear-gradient(145deg, var(--el-color-primary), #7559e8);
    }

    &__brand-icon {
      width: 42px;
      height: 42px;
      font-size: 20px;
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 8px 22px rgb(64 116 255 / 22%);
    }

    &__identity-copy {
      min-width: 0;
    }

    &__title-row {
      gap: 8px;

      strong {
        font-size: 16px;
        color: var(--el-text-color-primary);
      }

      > span {
        padding: 2px 7px;
        font-size: 10px;
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
        border-radius: 999px;
      }
    }

    &__status {
      gap: 6px;
      min-width: 0;
      margin-top: 4px;
      font-size: 12px;
      color: var(--el-text-color-secondary);

      i {
        width: 7px;
        height: 7px;
        background: var(--el-color-success);
        border-radius: 50%;

        &.is-offline {
          background: var(--el-color-danger);
        }
      }

      em {
        font-style: normal;
      }
    }

    &__page {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    &__header-actions {
      flex-shrink: 0;
      gap: 4px;
    }

    &__header-button {
      font-size: 18px;
    }

    &__messages {
      flex: 1;
      min-height: 0;
    }

    &__conversation {
      min-height: 100%;
      padding: 24px 22px 30px;
    }

    &__welcome {
      display: flex;
      flex-direction: column;
      align-items: center;
      max-width: 520px;
      padding-top: clamp(22px, 6vh, 70px);
      margin: 0 auto;
      text-align: center;

      h2 {
        margin: 12px 0 8px;
        font-size: 25px;
        color: var(--el-text-color-primary);
      }

      > p {
        max-width: 430px;
        margin: 0;
        line-height: 1.7;
        color: var(--el-text-color-secondary);
      }
    }

    &__welcome-mark {
      width: 58px;
      height: 58px;
      font-size: 28px;
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 12px 30px rgb(64 116 255 / 24%);
    }

    &__eyebrow {
      margin-top: 18px;
      font-size: 10px;
      font-weight: 700;
      color: var(--el-color-primary);
      letter-spacing: 0.15em;
    }

    &__context-pill {
      gap: 6px;
      max-width: 100%;
      padding: 6px 10px;
      margin-top: 18px;
      font-size: 12px;
      color: var(--el-text-color-regular);
      background: var(--el-fill-color-light);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: 999px;
    }

    &__prompt-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
      width: 100%;
      margin-top: 28px;
    }

    &__prompt-card {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr) auto;
      gap: 11px;
      align-items: center;
      min-height: 88px;
      padding: 14px;
      font: inherit;
      color: var(--el-text-color-primary);
      text-align: left;
      cursor: pointer;
      background: color-mix(in srgb, var(--el-bg-color) 92%, var(--el-color-primary));
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
      transition: all 0.2s ease;

      &:hover:not(:disabled) {
        border-color: var(--el-color-primary-light-5);
        box-shadow: 0 10px 24px rgb(31 45 61 / 8%);
        transform: translateY(-2px);
      }

      &:disabled {
        cursor: not-allowed;
        opacity: 0.55;
      }

      > span:nth-child(2) {
        display: grid;
        gap: 4px;
        min-width: 0;
      }

      strong {
        font-size: 13px;
      }

      small {
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 11px;
        color: var(--el-text-color-secondary);
        white-space: nowrap;
      }

      > svg,
      > :deep(svg) {
        color: var(--el-text-color-placeholder);
      }
    }

    &__prompt-icon {
      width: 34px;
      height: 34px;
      font-size: 16px;
      background: var(--el-color-primary-light-8);
      border-radius: var(--el-border-radius-small);

      :deep(svg) {
        color: var(--el-color-primary);
      }
    }

    &__capabilities {
      flex-wrap: wrap;
      gap: 14px;
      justify-content: center;
      margin-top: 22px;
      font-size: 11px;
      color: var(--el-text-color-placeholder);

      span {
        display: inline-flex;
        gap: 4px;
        align-items: center;
      }
    }

    &__message {
      display: flex;
      gap: 10px;
      align-items: flex-start;
      margin-bottom: 24px;

      &.is-user {
        flex-direction: row-reverse;

        .art-ai-assistant__message-body {
          align-items: flex-end;
        }

        .art-ai-assistant__bubble {
          color: var(--el-color-primary-dark-2);
          background: var(--el-color-primary-light-9);
          border-color: var(--el-color-primary-light-8);
        }
      }

      &.is-error {
        .art-ai-assistant__bubble {
          color: var(--el-color-danger-dark-2);
          background: var(--el-color-danger-light-9);
          border-color: var(--el-color-danger-light-7);
        }
      }
    }

    &__avatar,
    &__assistant-avatar {
      flex-shrink: 0;
    }

    &__assistant-avatar {
      width: 32px;
      height: 32px;
      font-size: 15px;
      border-radius: var(--el-border-radius-small);
      box-shadow: 0 6px 16px rgb(64 116 255 / 18%);
    }

    &__message-body {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      max-width: min(84%, 470px);
    }

    &__message-meta {
      display: flex;
      gap: 8px;
      align-items: center;
      margin-bottom: 6px;
      font-size: 11px;
      color: var(--el-text-color-secondary);

      span:first-child {
        font-weight: 600;
        color: var(--el-text-color-regular);
      }
    }

    &__bubble {
      padding: 12px 14px;
      line-height: 1.75;
      color: var(--el-text-color-primary);
      overflow-wrap: anywhere;
      white-space: pre-wrap;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color-lighter);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 5px 18px rgb(31 45 61 / 5%);
    }

    &__tools {
      flex-wrap: wrap;
      gap: 6px;
      margin-top: 8px;

      > span {
        display: inline-flex;
        gap: 4px;
        align-items: center;
        padding: 4px 8px;
        font-size: 10px;
        color: var(--el-color-success);
        background: var(--el-color-success-light-9);
        border-radius: 999px;

        &.is-failed {
          color: var(--el-color-danger);
          background: var(--el-color-danger-light-9);
        }
      }
    }

    &__feedback {
      gap: 2px;
      margin-top: 7px;
      font-size: 10px;
      color: var(--el-text-color-placeholder);
    }

    &__feedback-button {
      font-size: 13px;

      &.is-active {
        color: var(--el-color-primary);
        background: var(--el-color-primary-light-9);
      }

      &.is-negative {
        color: var(--el-color-danger);
        background: var(--el-color-danger-light-9);
      }
    }

    &__retry {
      margin-top: 8px;
    }

    &__thinking {
      gap: 8px;
      padding: 11px 13px;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      background: var(--el-fill-color-light);
      border-radius: var(--el-border-radius-base);

      > :deep(svg) {
        color: var(--el-color-primary);
        animation: assistant-rotate 1s linear infinite;
      }
    }

    &__composer {
      padding: 14px 20px 16px;
      background: color-mix(in srgb, var(--el-bg-color) 96%, var(--el-color-primary));
      border-top: 1px solid var(--el-border-color-lighter);

      > p {
        margin: 9px 0 0;
        font-size: 10px;
        color: var(--el-text-color-placeholder);
        text-align: center;
      }
    }

    &__composer-box {
      padding: 10px 10px 9px 13px;
      background: var(--el-bg-color);
      border: 1px solid var(--el-border-color);
      border-radius: var(--el-border-radius-base);
      box-shadow: 0 7px 24px rgb(31 45 61 / 7%);
      transition: border-color 0.2s ease;

      &:focus-within {
        border-color: var(--el-color-primary-light-5);
        box-shadow: 0 8px 26px rgb(64 116 255 / 11%);
      }

      :deep(.el-textarea__inner) {
        padding: 2px 0 8px;
        background: transparent;
        border: 0;
        box-shadow: none;
      }
    }

    &__composer-actions {
      gap: 12px;
      justify-content: space-between;
    }

    &__composer-meta {
      gap: 10px;
      min-width: 0;
      font-size: 10px;
      color: var(--el-text-color-placeholder);

      span {
        display: inline-flex;
        gap: 4px;
        align-items: center;
      }
    }
  }

  @keyframes assistant-rotate {
    to {
      transform: rotate(360deg);
    }
  }

  @media (width <= 640px) {
    .art-ai-assistant {
      &__header {
        padding: 12px 14px;
      }

      &__conversation {
        padding: 20px 14px 24px;
      }

      &__prompt-grid {
        grid-template-columns: 1fr;
      }

      &__welcome {
        padding-top: 18px;
      }

      &__composer {
        padding: 12px;
      }

      &__message-body {
        max-width: 87%;
      }
    }
  }
</style>
